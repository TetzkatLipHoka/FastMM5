{Exhaustive in-situ check of the freed block fill pattern detection.

 For each size, a medium block is allocated and freed, and then every single byte
 of its user area is corrupted in turn and the corruption scan must report it.
 A medium block is used on purpose:  a freed small block would be handed back out
 to hold the exception object that reports the corruption, which kills the
 process before the result can be observed.

 The sizes are chosen to cover the vector loop and every way it can end:  runs
 that are an exact multiple of 64, runs with a 16/32/48 byte remainder, and runs
 whose trailing bytes fall through to the 8/4/2/1 byte scalar tail.

 Exit code 0 = every byte position of every size was detected.}

program exhaustive;

{$APPTYPE CONSOLE}

uses
  FastMM5 in 'FastMM5.pas',
  SysUtils;

var
  GFailures: Integer = 0;
  GChecked: Integer = 0;

function ScanDetects: Boolean;
begin
  try
    FastMM_ScanDebugBlocksForCorruption(1000);
    Result := False;
  except
    Result := True;
  end;
end;

procedure TestSize(ASize: Integer);
var
  LPointer: Pointer;
  LOriginal: Byte;
  LPosition: Integer;
  LMissed: Integer;
begin
  GetMem(LPointer, ASize);
  FreeMem(LPointer);

  {A clean freed block must not be reported.}
  if ScanDetects then
  begin
    WriteLn(Format('  FAIL  size %d: clean freed block reported as corrupt', [ASize]));
    Inc(GFailures);
    Exit;
  end;

  LMissed := 0;
  for LPosition := 0 to ASize - 1 do
  begin
    LOriginal := PByte(PAnsiChar(LPointer) + LPosition)^;
    PByte(PAnsiChar(LPointer) + LPosition)^ := LOriginal xor $FF;
    if not ScanDetects then
      Inc(LMissed);
    PByte(PAnsiChar(LPointer) + LPosition)^ := LOriginal;
    Inc(GChecked);
  end;

  if LMissed = 0 then
    WriteLn(Format('  ok    size %5d: all %d byte positions detected', [ASize, ASize]))
  else
  begin
    WriteLn(Format('  FAIL  size %5d: %d of %d byte positions NOT detected', [ASize, LMissed, ASize]));
    Inc(GFailures);
  end;
  Flush(Output);
end;

const
  {Medium block sizes.  The user area after the 8/16 byte freed object marker
   gives vector runs with every possible remainder.}
  CSizes: array[0..11] of Integer = (
    2048,      //exact multiples
    2048 + 16, 2048 + 32, 2048 + 48,   //16/32/48 byte vector remainders
    2048 + 1, 2048 + 2, 2048 + 3, 2048 + 7,  //scalar tail 1/2/3/7
    2048 + 15,                          //longest possible scalar tail
    4096, 4096 + 9, 8192);

var
  i: Integer;

begin
  FastMM_MessageBoxEvents := [];
  FastMM_LogToFileEvents := [];
  FastMM_OutputDebugStringEvents := [];

  WriteLn('Exhaustive freed block corruption detection');
  WriteLn('==========================================');

  if not FastMM_EnterDebugMode then
  begin
    WriteLn('EnterDebugMode failed');
    Halt(2);
  end;

  for i := Low(CSizes) to High(CSizes) do
    TestSize(CSizes[i]);

  FastMM_ExitDebugMode;

  WriteLn;
  WriteLn(Format('%d byte positions checked', [GChecked]));
  if GFailures = 0 then
    WriteLn('PASSED')
  else
    WriteLn(Format('FAILED - %d size(s)', [GFailures]));
  ExitCode := GFailures;
end.
