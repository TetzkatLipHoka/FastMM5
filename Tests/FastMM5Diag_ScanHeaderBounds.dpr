{What happens when the size fields of a debug block header are themselves the
 thing that got corrupted?  DebugFooterPtr is derived from UserSize and the
 stack traces from StackTraceEntryCount, so a corrupted size field decides where
 the scan reads.  This program corrupts those fields (and nothing else) and
 reports how the scan reacts:  a clean corruption report, an access violation,
 or silence.

 What makes this safe upstream (verified for issue #102) is the evaluation
 order:  the header checksum is compared before the footer checksum, and since
 FastMM5.pas compiles with complete boolean evaluation off, the footer read is
 short-circuited away as soon as the header does not match - and a corrupted
 size field always invalidates the header checksum.  So this test is really guarding that ordering:  if anyone ever
 reorders those comparisons, or reads the footer before validating the header,
 the cases below turn into access violations.

 Why there is no "small block, freed" case:  a freed debug block sits in the
 debug free queue and is a candidate for the next allocation of that size.  When
 the scan reports the corruption it raises an exception, and raising allocates
 the exception object - which hands out precisely that corrupted block, so the
 corruption is detected again while an exception is already being raised, and
 the process dies before any handler runs.  That is FastMM doing its job;  the
 test simply cannot observe it.  For medium and large blocks the exception
 object is far too small to be given the freed block, so those cases are stable.}

program FastMM5Diag_ScanHeaderBounds;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  SysUtils;

function Header(APointer: Pointer): PFastMM_DebugBlockHeader;
begin
  Result := PFastMM_DebugBlockHeader(PAnsiChar(APointer) - SizeOf(TFastMM_DebugBlockHeader));
end;

var
  GFailures: Integer = 0;

{Runs the scan and describes what came back.  Anything other than a proper
 corruption report counts as a failure:  an access violation means the scan read
 where the corrupted size field pointed it, and silence means the corruption
 went unnoticed.}
function ScanOutcome: string;
begin
  try
    FastMM_ScanDebugBlocksForCorruption(1000);
    Result := 'FAIL  no error          (corruption NOT reported)';
    Inc(GFailures);
  except
    on E: EAccessViolation do
      begin
      Result := 'FAIL  ACCESS VIOLATION  (' + E.Message + ')';
      Inc(GFailures);
      end;
    on E: Exception do
      Result := 'ok    reported          (' + E.ClassName + ')';
  end;
end;

procedure TestUserSize(const AWhat: string; ASize: Integer; AFreeFirst: Boolean);
var
  LP: Pointer;
  LOriginal: NativeInt;
  LOutcome: string;
begin
  GetMem(LP, ASize);
  if AFreeFirst then
    FreeMem(LP);
  LOriginal := Header(LP).UserSize;
  {A plausible corruption:  something overran the previous block and wrote over
   the size field of this one.  Everything else in the header is untouched.}
  Header(LP).UserSize := $30000000;
  LOutcome := ScanOutcome;
  Header(LP).UserSize := LOriginal;
  if not AFreeFirst then
    FreeMem(LP);
  WriteLn(Format('  %-46s %s', [AWhat, LOutcome]));
  {Flush after every case:  this program deliberately corrupts the heap, so if a
   later case brings the process down, everything up to that point must already
   be on the console (piped output is buffered otherwise).}
  Flush(Output);
end;

procedure TestStackTraceEntryCount(const AWhat: string; ASize: Integer; AFreeFirst: Boolean);
var
  LP: Pointer;
  LOriginal: Byte;
  LOutcome: string;
begin
  GetMem(LP, ASize);
  if AFreeFirst then
    FreeMem(LP);
  LOriginal := Header(LP).StackTraceEntryCount;
  Header(LP).StackTraceEntryCount := 255;
  LOutcome := ScanOutcome;
  Header(LP).StackTraceEntryCount := LOriginal;
  if not AFreeFirst then
    FreeMem(LP);
  WriteLn(Format('  %-46s %s', [AWhat, LOutcome]));
  {Flush after every case:  this program deliberately corrupts the heap, so if a
   later case brings the process down, everything up to that point must already
   be on the console (piped output is buffered otherwise).}
  Flush(Output);
end;

begin
  FastMM_MessageBoxEvents := [];
  FastMM_LogToFileEvents := [];
  FastMM_OutputDebugStringEvents := [];

  if not FastMM_EnterDebugMode then
  begin
    WriteLn('FastMM_EnterDebugMode failed');
    Halt(2);
  end;

  WriteLn('Corrupted size fields in the debug block header');
  WriteLn('==============================================');
  WriteLn;
  WriteLn('UserSize overwritten with $30000000:');
  TestUserSize('small block, allocated', 100, False);
  TestUserSize('medium block, allocated', 50000, False);
  TestUserSize('medium block, freed', 50000, True);
  TestUserSize('large block, allocated', 300000, False);
  TestUserSize('large block, freed', 300000, True);
  WriteLn;
  WriteLn('StackTraceEntryCount overwritten with 255:');
  TestStackTraceEntryCount('small block, allocated', 100, False);
  TestStackTraceEntryCount('medium block, allocated', 50000, False);
  TestStackTraceEntryCount('large block, freed', 300000, True);

  FastMM_ExitDebugMode;
  WriteLn;
  if GFailures = 0 then
    WriteLn('ERGEBNIS: OK')
  else
    WriteLn('ERGEBNIS: ', GFailures, ' FEHLER');
  ExitCode := GFailures;
end.
