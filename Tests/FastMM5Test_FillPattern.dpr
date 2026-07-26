{Does the freed block fill pattern check still see every single corrupted byte?

 For each size a block is allocated and freed, and then every byte of its user
 area is corrupted in turn:  the corruption scan must report every one of them.
 One check is reported per size rather than per byte position, otherwise the log
 would be tens of thousands of lines long.

 A medium block is used on purpose:  a freed small block would be handed back out
 to hold the exception object that reports the corruption, which takes the
 process down before the result can be observed.

 The sizes cover the loop over the fill pattern and every way it can end:  runs
 that are an exact multiple of the unrolled width, runs with a 16/32/48 byte
 remainder, and runs whose trailing bytes fall through to the scalar tail.  That
 is the point of the test:  the block sizes an application really uses are rarely
 a neat multiple of whatever the check reads at a time, so the remainders are
 where a widened implementation stops looking.}

program FastMM5Test_FillPattern;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

const
  {The user sizes to cover.  2048 is an exact multiple of every width the check
   might read at a time;  the offsets from it produce the 16/32/48 byte
   remainders and the 1/2/3/7/15 byte scalar tails.}
  CSizes: array[0..11] of Integer = (
    2048,
    2048 + 16, 2048 + 32, 2048 + 48,
    2048 + 1, 2048 + 2, 2048 + 3, 2048 + 7,
    2048 + 15,
    4096, 4096 + 9, 8192);

var
  GPositionsChecked: Integer = 0;

{Runs the scan.  True means it reported a corruption.}
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
  LPosition, LMissed, LFirstMissed: Integer;
begin
  GetMem(LPointer, ASize);
  FreeMem(LPointer);
  {The block is now in the debug free queue:  filled with the debug fill pattern
   and still committed, so it can be corrupted from here.}

  if ScanDetects then
  begin
    Check(False, Format('size %d:  a clean freed block must not be reported', [ASize]));
    Exit;
  end;

  LMissed := 0;
  LFirstMissed := -1;
  for LPosition := 0 to ASize - 1 do
  begin
    LOriginal := PByte(PAnsiChar(LPointer) + LPosition)^;
    PByte(PAnsiChar(LPointer) + LPosition)^ := LOriginal xor $FF;
    if not ScanDetects then
    begin
      Inc(LMissed);
      if LFirstMissed < 0 then
        LFirstMissed := LPosition;
    end;
    PByte(PAnsiChar(LPointer) + LPosition)^ := LOriginal;
  end;
  Inc(GPositionsChecked, ASize);

  if LMissed = 0 then
    Check(True, Format('size %5d:  all %d byte positions detected', [ASize, ASize]))
  else
    Check(False, Format('size %5d:  %d of %d byte positions NOT detected, first at offset %d',
      [ASize, LMissed, ASize, LFirstMissed]));
end;

var
  i: Integer;

begin
  TestsBegin('FastMM5 freed block fill pattern check');

  Check(FastMM_EnterDebugMode, 'FastMM_EnterDebugMode succeeds');

  Section('Every corrupted byte of a freed block is detected');
  for i := Low(CSizes) to High(CSizes) do
    TestSize(CSizes[i]);

  Info(Format('%d byte positions checked in total', [GPositionsChecked]));

  Check(FastMM_ExitDebugMode, 'FastMM_ExitDebugMode succeeds');

  TestsEnd;
end.
