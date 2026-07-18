program FastMM5Diag_SSE2Check;
{Verifiziert den SSE2-Status des Builds:
   1. Assembliert der Compiler movdqu korrekt? (Opcode-Bytes der Testroutine pruefen)
   2. Meldet die CPUID-Erkennung SSE2? (gleiche Logik wie Compat_TestSSE in FastMM5.pas)
   3. Kopiert die SSE2-Move-Routine korrekt? (Muster-Roundtrip ueber einen Realloc-Upsize,
      der intern die gewaehlte UpsizeMoveProcedure benutzt)
 Kompilieren wie die anderen Diag-Tests, siehe README.}
{$APPTYPE CONSOLE}

uses
  FastMM5, SysUtils;

{Lokale Kopie der movdqu-Sequenz aus Move16_x86_SSE2 - zum Pruefen der vom Compiler erzeugten Opcodes.}
procedure LocalMove16SSE2(const ASource; var ADest; ACount: Integer);
asm
  movdqu xmm0, [eax]
  movdqu [edx], xmm0
end;

{CPUID-SSE2-Erkennung, identisch zur Logik von Compat_TestSSE in FastMM5.pas.}
function LocalTestSSE2: Boolean;
asm
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
  {Erwartete Encodings: movdqu xmm0,[eax] = F3 0F 6F 00 / movdqu [edx],xmm0 = F3 0F 7F 02}
  CExpectedOpcodes: array[0..7] of Byte = ($F3, $0F, $6F, $00, $F3, $0F, $7F, $02);

var
  LPCode: PByte;
  i: Integer;
  LOpcodesOK: Boolean;
  LSrc, LDst: array[0..15] of Byte;
  p: Pointer;
  LSizes: array[0..3] of Integer;
  s: Integer;
begin
  LFails := 0;
  WriteLn('SSE2-Status unter ', {$ifdef VER150}'Delphi 7'{$else}'diesem Compiler'{$endif}, ':');

  {1. Opcode-Pruefung: hat der eingebaute Assembler movdqu korrekt encodiert?}
  LPCode := @LocalMove16SSE2;
  LOpcodesOK := True;
  for i := 0 to High(CExpectedOpcodes) do
    if PByte(Integer(LPCode) + i)^ <> CExpectedOpcodes[i] then
      LOpcodesOK := False;
  Check(LOpcodesOK, 'movdqu-Opcodes byte-korrekt assembliert');

  {2. Laufzeit-Erkennung}
  Check(LocalTestSSE2, 'CPUID meldet SSE2 (auf dieser Maschine erwartet)');

  {3. Funktionstest der lokalen SSE2-Kopierroutine}
  for i := 0 to 15 do
    LSrc[i] := Byte(i * 7 + 3);
  FillChar(LDst, SizeOf(LDst), 0);
  LocalMove16SSE2(LSrc, LDst, 16);
  LOpcodesOK := True;
  for i := 0 to 15 do
    if LDst[i] <> LSrc[i] then
      LOpcodesOK := False;
  Check(LOpcodesOK, 'movdqu-Kopie inhaltlich korrekt');

  {4. End-to-End: Realloc-Upsize durch FastMM benutzt die gewaehlte Move-Routine (bei SSE2-CPU die
   SSE2-Variante).  Muster muss die Kette von Upsizes ueberleben.}
  LSizes[0] := 14; LSizes[1] := 30; LSizes[2] := 46; LSizes[3] := 62;  {Klassen 16/32/48/64}
  for s := 0 to High(LSizes) do
  begin
    GetMem(p, LSizes[s]);
    for i := 0 to LSizes[s] - 1 do
      PByte(Integer(p) + i)^ := Byte(i xor $5A);
    ReallocMem(p, LSizes[s] * 40);  {Upsize erzwingt Kopie in groessere Klasse}
    LOpcodesOK := True;
    for i := 0 to LSizes[s] - 1 do
      if PByte(Integer(p) + i)^ <> Byte(i xor $5A) then
        LOpcodesOK := False;
    FreeMem(p);
    Check(LOpcodesOK, Format('Realloc-Upsize aus %d-Byte-Klasse erhaelt Inhalt', [LSizes[s] + 2]));
  end;

  if LFails = 0 then
    WriteLn('ERGEBNIS: OK')
  else
  begin
    WriteLn('ERGEBNIS: ', LFails, ' FEHLER');
    Halt(1);
  end;
end.
