program FastMM5Diag_SSE2Check;
{Verifiziert den SSE2-Status des Builds:
   1. Assembliert der Compiler movdqu korrekt? (Opcode-Bytes der Testroutine pruefen)
   2. Meldet die CPUID-Erkennung SSE2? (gleiche Logik wie Compat_TestSSE in FastMM5.pas;
      unter Win64 ist CPUID immer vorhanden)
   3. Kopiert die SSE2-Move-Routine korrekt? (Muster-Roundtrip ueber einen Realloc-Upsize,
      der intern die gewaehlte UpsizeMoveProcedure benutzt)
 Kompilierbar mit dcc32 (ab Delphi 7) und dcc64.  Kompilieren wie die anderen Diag-Tests, siehe README.}
{$APPTYPE CONSOLE}

uses
  FastMM5, SysUtils;

{Lokale Kopie der movdqu-Sequenz aus den SSE2-Move-Routinen - zum Pruefen der vom Compiler erzeugten Opcodes.
 Unter Win64 erzwingt .noframe, dass die Routine direkt mit dem movdqu beginnt.}
procedure LocalMove16SSE2(const ASource; var ADest; ACount: Integer);
asm
{$ifdef WIN64}
  .noframe
  movdqu xmm0, [rcx]
  movdqu [rdx], xmm0
{$else}
  movdqu xmm0, [eax]
  movdqu [edx], xmm0
{$endif}
end;

{CPUID-SSE2-Erkennung, identisch zur Logik von Compat_TestSSE in FastMM5.pas.}
function LocalTestSSE2: Boolean;
asm
{$ifdef WIN64}
  .noframe
  push rbx
  mov eax, 1
  cpuid
  test edx, $4000000
  setnz al
  pop rbx
{$else}
  push ebx
  pushfd
  pop eax
  mov ecx, eax
  xor eax, $200000
  push eax
  popfd
  pushfd
  pop eax
  xor eax, ecx
  jz @NoCPUID
  mov eax, 1
  cpuid
  test edx, $4000000
  setnz al
  pop ebx
  ret
@NoCPUID:
  xor eax, eax
  pop ebx
{$endif}
end;

var
  LFails: Integer;

procedure Check(ACond: Boolean; const AName: string);
begin
  if ACond then
    WriteLn('  ok   ', AName)
  else
  begin
    WriteLn('  FEHLER ', AName);
    Inc(LFails);
  end;
end;

const
  {Erwartete Encodings (die ModRM-Bytes unterscheiden sich je nach Registersatz):
   Win32: movdqu xmm0,[eax] = F3 0F 6F 00 / movdqu [edx],xmm0 = F3 0F 7F 02
   Win64: movdqu xmm0,[rcx] = F3 0F 6F 01 / movdqu [rdx],xmm0 = F3 0F 7F 02}
  CExpectedOpcodes: array[0..7] of Byte =
    {$ifdef WIN64}($F3, $0F, $6F, $01, $F3, $0F, $7F, $02)
    {$else}($F3, $0F, $6F, $00, $F3, $0F, $7F, $02){$endif};

var
  LPCode: PAnsiChar;
  i: Integer;
  LOK: Boolean;
  LSrc, LDst: array[0..15] of Byte;
  p: Pointer;
  LPBytes: PAnsiChar;
  LSizes: array[0..3] of Integer;
  s: Integer;
begin
  LFails := 0;
  WriteLn('SSE2-Status unter ', {$ifdef VER150}'Delphi 7'{$else}{$ifdef WIN64}'diesem Compiler (Win64)'{$else}'diesem Compiler (Win32)'{$endif}{$endif}, ':');

  {1. Opcode-Pruefung: hat der eingebaute Assembler movdqu korrekt encodiert?}
  LPCode := PAnsiChar(@LocalMove16SSE2);
  LOK := True;
  for i := 0 to High(CExpectedOpcodes) do
    if Byte(LPCode[i]) <> CExpectedOpcodes[i] then
      LOK := False;
  Check(LOK, 'movdqu-Opcodes byte-korrekt assembliert');

  {2. Laufzeit-Erkennung}
  Check(LocalTestSSE2, 'CPUID meldet SSE2 (auf dieser Maschine erwartet)');

  {3. Funktionstest der lokalen SSE2-Kopierroutine}
  for i := 0 to 15 do
    LSrc[i] := Byte(i * 7 + 3);
  FillChar(LDst, SizeOf(LDst), 0);
  LocalMove16SSE2(LSrc, LDst, 16);
  LOK := True;
  for i := 0 to 15 do
    if LDst[i] <> LSrc[i] then
      LOK := False;
  Check(LOK, 'movdqu-Kopie inhaltlich korrekt');

  {4. End-to-End: Realloc-Upsize durch FastMM benutzt die gewaehlte Move-Routine (bei SSE2-CPU die
   SSE2-Variante).  Muster muss die Kette von Upsizes ueberleben.}
  LSizes[0] := 14; LSizes[1] := 30; LSizes[2] := 46; LSizes[3] := 62;  {Klassen 16/32/48/64}
  for s := 0 to High(LSizes) do
  begin
    GetMem(p, LSizes[s]);
    LPBytes := p;
    for i := 0 to LSizes[s] - 1 do
      LPBytes[i] := AnsiChar(Byte(i xor $5A));
    ReallocMem(p, LSizes[s] * 40);  {Upsize erzwingt Kopie in groessere Klasse}
    LPBytes := p;
    LOK := True;
    for i := 0 to LSizes[s] - 1 do
      if Byte(LPBytes[i]) <> Byte(i xor $5A) then
        LOK := False;
    FreeMem(p);
    Check(LOK, Format('Realloc-Upsize aus %d-Byte-Klasse erhaelt Inhalt', [LSizes[s] + 2]));
  end;

  if LFails = 0 then
    WriteLn('ERGEBNIS: OK')
  else
  begin
    WriteLn('ERGEBNIS: ', LFails, ' FEHLER');
    Halt(1);
  end;
end.
