{Does FastMM_ScanDebugBlocksForCorruption still detect a corrupted debug block?

 For each block size class the program allocates a debug block, corrupts one
 field, runs the scan and reports whether the scan raised (= corruption
 detected).  The corruption is repaired again afterwards, and a clean scan
 confirms that the heap is back to normal, so one run covers every case.

 Regression test for upstream issue #102:  between cad1f04 and a9526b2 the walk
 only reported debug info for a small block whose header AND footer checksums
 were already valid, so the scan could not see the very state it looks for.  The
 three small block cases below failed silently in that window, medium and large
 kept working - which is why a corruption test that happens to use a large block
 proves nothing about the small block path.

 Exit code 0 = every corruption was detected.}

program FastMM5Diag_ScanCoverage;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  SysUtils;

var
  GFailures: Integer = 0;

function ScanDetects: Boolean;
begin
  try
    FastMM_ScanDebugBlocksForCorruption(1000);
    Result := False;
  except
    Result := True;
  end;
end;

procedure Report(const AWhat: string; ADetected, AExpected: Boolean);
const
  CYesNo: array[Boolean] of string = ('NOT detected', 'detected');
begin
  if ADetected = AExpected then
    WriteLn(Format('  ok    %-58s %s', [AWhat, CYesNo[ADetected]]))
  else
  begin
    WriteLn(Format('  FAIL  %-58s %s (expected %s)',
      [AWhat, CYesNo[ADetected], CYesNo[AExpected]]));
    Inc(GFailures);
  end;
end;

{Corrupts the header checksum of the debug block behind APointer, scans, and
 restores it.}
procedure TestHeaderCorruption(const AWhat: string; ASize: Integer; AExpected: Boolean);
var
  LP: Pointer;
  LHeader: PFastMM_DebugBlockHeader;
  LOriginal: Cardinal;
  LDetected: Boolean;
begin
  GetMem(LP, ASize);
  try
    LHeader := PFastMM_DebugBlockHeader(PAnsiChar(LP) - SizeOf(TFastMM_DebugBlockHeader));
    LOriginal := LHeader.HeaderCheckSum;
    LHeader.HeaderCheckSum := LOriginal xor $DEADBEEF;
    LDetected := ScanDetects;
    LHeader.HeaderCheckSum := LOriginal;
    Report(AWhat, LDetected, AExpected);
    if ScanDetects then
    begin
      WriteLn('  FAIL  heap not clean again after repairing the header');
      Inc(GFailures);
    end;
  finally
    FreeMem(LP);
  end;
end;

{Overwrites the first byte after the user data, which lands in the debug footer
 (the footer checksum), and scans.}
procedure TestFooterCorruption(const AWhat: string; ASize: Integer; AExpected: Boolean);
var
  LP: Pointer;
  LHeader: PFastMM_DebugBlockHeader;
  LOriginal: Cardinal;
  LDetected: Boolean;
begin
  GetMem(LP, ASize);
  try
    LHeader := PFastMM_DebugBlockHeader(PAnsiChar(LP) - SizeOf(TFastMM_DebugBlockHeader));
    LOriginal := LHeader.DebugFooterPtr^;
    PByte(PAnsiChar(LP) + ASize)^ := PByte(PAnsiChar(LP) + ASize)^ xor $FF;
    LDetected := ScanDetects;
    LHeader.DebugFooterPtr^ := LOriginal;
    Report(AWhat, LDetected, AExpected);
  finally
    FreeMem(LP);
  end;
end;

{Writes into a block after it was freed, i.e. destroys the fill pattern of a
 freed debug block, and scans.  The header and footer stay intact here.}
procedure TestUseAfterFree(const AWhat: string; ASize: Integer; AExpected: Boolean);
var
  LP: Pointer;
  LOriginal: Byte;
  LDetected: Boolean;
begin
  GetMem(LP, ASize);
  FreeMem(LP);
  {The block is now in the debug free queue and still committed.}
  LOriginal := PByte(PAnsiChar(LP) + ASize - 1)^;
  PByte(PAnsiChar(LP) + ASize - 1)^ := LOriginal xor $FF;
  LDetected := ScanDetects;
  PByte(PAnsiChar(LP) + ASize - 1)^ := LOriginal;
  Report(AWhat, LDetected, AExpected);
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

  WriteLn('FastMM_ScanDebugBlocksForCorruption coverage');
  WriteLn('============================================');
  WriteLn;
  WriteLn('Header checksum corrupted (allocated block):');
  TestHeaderCorruption('small block (100 bytes)', 100, True);
  TestHeaderCorruption('small block (2000 bytes)', 2000, True);
  TestHeaderCorruption('medium block (50000 bytes)', 50000, True);
  TestHeaderCorruption('large block (300000 bytes)', 300000, True);
  WriteLn;
  WriteLn('Buffer overrun into the debug footer (allocated block):');
  TestFooterCorruption('small block (100 bytes)', 100, True);
  TestFooterCorruption('medium block (50000 bytes)', 50000, True);
  TestFooterCorruption('large block (300000 bytes)', 300000, True);
  WriteLn;
  WriteLn('Write after free (fill pattern destroyed, header intact):');
  TestUseAfterFree('small block (100 bytes)', 100, True);
  TestUseAfterFree('medium block (50000 bytes)', 50000, True);
  TestUseAfterFree('large block (300000 bytes)', 300000, True);

  FastMM_ExitDebugMode;

  WriteLn;
  if GFailures = 0 then
    WriteLn('Every corruption was detected.')
  else
    WriteLn(GFailures, ' case(s) went undetected.');
  ExitCode := GFailures;
end.
