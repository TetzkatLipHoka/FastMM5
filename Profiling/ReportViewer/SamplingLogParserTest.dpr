{

  SamplingLogParserTest
  ---------------------

  Console self-test for FastMM_SamplingLogParser.  It builds CSV logs whose text
  matches what FastMM_SamplingProfiler.pas writes (same header, same column
  order, same '.' decimal separator), parses them, and asserts that the
  resulting object model is correct.

  It also covers the awkward cases the viewer will actually meet:  a log without
  the contention columns (written by an older profiler), a file with two runs
  appended to it, reordered columns, short rows and a detail log.

  Exit code 0 = all checks passed, 1 = a check failed.

}

program SamplingLogParserTest;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Contnrs,
  FastMM_SamplingLogParser in 'FastMM_SamplingLogParser.pas';

const
  CRLF = #13#10;
  CSummaryHeader =
    'sample_index,wall_clock,elapsed_ms,mm_usage_bytes,allocated_bytes,reserved_bytes,overhead_bytes,'
    + 'efficiency_pct,small_alloc_bytes,small_reserved_bytes,small_block_count,medium_alloc_bytes,'
    + 'medium_reserved_bytes,medium_block_count,large_alloc_bytes,large_reserved_bytes,large_block_count,'
    + 'small_contention,medium_contention,large_contention';
  CDetailHeader =
    'sample_index,elapsed_ms,block_size,useable_size,allocated_count,reserved_bytes,used_bytes,efficiency_pct';

var
  GFailures: Integer = 0;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if ACondition then
    WriteLn('  [ok]   ', AMessage)
  else
  begin
    WriteLn('  [FAIL] ', AMessage);
    Inc(GFailures);
  end;
end;

procedure CheckEqualsInt(AExpected, AActual: Int64; const AMessage: string);
begin
  Check(AExpected = AActual, AMessage + Format('  (expected %d, got %d)', [AExpected, AActual]));
end;

{A three sample log:  allocation rises then falls, so the aggregate helpers have
 something meaningful to find.}
function BuildSummaryLog: string;
begin
  Result :=
    CSummaryHeader + CRLF +
    '0,2026-07-23 10:00:00.000,0,3145728,100000,150000,50000,66.67,'
      + '60000,90000,700,30000,40000,20,10000,20000,2,0,0,0' + CRLF +
    '1,2026-07-23 10:00:01.000,1000,8388608,500000,600000,100000,83.33,'
      + '300000,350000,3000,150000,180000,60,50000,70000,5,7,3,1' + CRLF +
    '2,2026-07-23 10:00:02.000,2000,4194304,200000,260000,60000,76.92,'
      + '120000,150000,1200,60000,80000,25,20000,30000,3,9,4,1' + CRLF;
end;

{The same shape, but written by a profiler build that did not have the
 contention columns yet.}
function BuildLogWithoutContention: string;
begin
  Result :=
    'sample_index,wall_clock,elapsed_ms,mm_usage_bytes,allocated_bytes,reserved_bytes,overhead_bytes,'
      + 'efficiency_pct,small_alloc_bytes,small_reserved_bytes,small_block_count,medium_alloc_bytes,'
      + 'medium_reserved_bytes,medium_block_count,large_alloc_bytes,large_reserved_bytes,large_block_count' + CRLF +
    '0,2026-07-23 10:00:00.000,0,3145728,100000,150000,50000,66.67,60000,90000,700,30000,40000,20,10000,20000,2' + CRLF +
    '1,2026-07-23 10:00:01.000,1000,8388608,500000,600000,100000,83.33,300000,350000,3000,150000,180000,60,50000,70000,5' + CRLF;
end;

{Columns in a different order, and a subset:  the parser maps by name.}
function BuildReorderedLog: string;
begin
  Result :=
    'elapsed_ms,allocated_bytes,sample_index,efficiency_pct' + CRLF +
    '500,777000,4,42.50' + CRLF;
end;

function BuildDetailLog: string;
begin
  Result :=
    CDetailHeader + CRLF +
    '0,0,16,8,100,65536,800,1.22' + CRLF +
    '0,0,32,24,50,65536,1200,1.83' + CRLF +
    '1,1000,16,8,900,131072,7200,5.49' + CRLF +
    '1,1000,32,24,400,65536,9600,14.65' + CRLF;
end;

procedure TestSummaryLog;
var
  LLog: TFastMMSamplingLog;
begin
  WriteLn('Summary log');
  LLog := TFastMMSamplingLog.Create;
  try
    LLog.LoadFromString(BuildSummaryLog, 'test.csv');

    Check(LLog.Kind = slkSummary, 'kind detected as summary');
    CheckEqualsInt(3, LLog.Count, 'row count');
    CheckEqualsInt(0, LLog.MalformedLineCount, 'no malformed lines');
    Check(LLog.HasContentionCounts, 'contention columns detected');

    Check(LLog[0].WallClock = '2026-07-23 10:00:00.000', 'wall clock parsed verbatim');
    CheckEqualsInt(0, LLog[0].SampleIndex, 'first sample index');
    CheckEqualsInt(1000, LLog[1].ElapsedMilliseconds, 'elapsed of second sample');
    CheckEqualsInt(500000, LLog[1].AllocatedBytes, 'allocated of second sample');
    CheckEqualsInt(600000, LLog[1].ReservedBytes, 'reserved of second sample');
    CheckEqualsInt(100000, LLog[1].OverheadBytes, 'overhead of second sample');
    CheckEqualsInt(8388608, LLog[1].MemoryManagerUsageBytes, 'mm usage of second sample');
    CheckEqualsInt(3000, LLog[1].SmallBlockCount, 'small block count');
    CheckEqualsInt(60, LLog[1].MediumBlockCount, 'medium block count');
    CheckEqualsInt(5, LLog[1].LargeBlockCount, 'large block count');
    CheckEqualsInt(7, LLog[1].SmallContentionCount, 'small contention count');
    CheckEqualsInt(3, LLog[1].MediumContentionCount, 'medium contention count');
    CheckEqualsInt(1, LLog[1].LargeContentionCount, 'large contention count');

    {The efficiency is the only fractional column;  it must survive locale
     independently, so compare against the exact written value.}
    Check(Abs(LLog[1].EfficiencyPercentage - 83.33) < 0.0001, 'efficiency parsed as 83.33');
    Check(Abs(LLog[0].EfficiencyPercentage - 66.67) < 0.0001, 'efficiency parsed as 66.67');

    CheckEqualsInt(2000, LLog.DurationMilliseconds, 'duration');
    Check(Abs(LLog.MaxOf(ssAllocated) - 500000) < 0.5, 'max allocated');
    Check(Abs(LLog.MinOf(ssAllocated) - 100000) < 0.5, 'min allocated');
    CheckEqualsInt(1, LLog.IndexOfMax(ssAllocated), 'index of peak allocated');
    Check(Abs(LLog[1].Value(ssReserved) - 600000) < 0.5, 'series accessor reads reserved');
    Check(Abs(LLog[2].Value(ssSmallContention) - 9) < 0.5, 'series accessor reads contention');
  finally
    LLog.Free;
  end;
end;

procedure TestLogWithoutContentionColumns;
var
  LLog: TFastMMSamplingLog;
begin
  WriteLn('Log without contention columns');
  LLog := TFastMMSamplingLog.Create;
  try
    LLog.LoadFromString(BuildLogWithoutContention, 'old.csv');

    CheckEqualsInt(2, LLog.Count, 'row count');
    Check(not LLog.HasContentionCounts, 'contention columns reported as absent');
    CheckEqualsInt(0, LLog[1].SmallContentionCount, 'missing contention column reads as 0');
    CheckEqualsInt(500000, LLog[1].AllocatedBytes, 'the columns that are present still parse');
    CheckEqualsInt(0, LLog.MalformedLineCount, 'no malformed lines');
  finally
    LLog.Free;
  end;
end;

procedure TestReorderedColumns;
var
  LLog: TFastMMSamplingLog;
begin
  WriteLn('Reordered / partial columns');
  LLog := TFastMMSamplingLog.Create;
  try
    LLog.LoadFromString(BuildReorderedLog, 'reordered.csv');

    CheckEqualsInt(1, LLog.Count, 'row count');
    CheckEqualsInt(4, LLog[0].SampleIndex, 'sample index taken from its named column');
    CheckEqualsInt(500, LLog[0].ElapsedMilliseconds, 'elapsed taken from its named column');
    CheckEqualsInt(777000, LLog[0].AllocatedBytes, 'allocated taken from its named column');
    Check(Abs(LLog[0].EfficiencyPercentage - 42.5) < 0.0001, 'efficiency taken from its named column');
    CheckEqualsInt(0, LLog[0].ReservedBytes, 'absent column reads as 0');
  finally
    LLog.Free;
  end;
end;

procedure TestTwoRunsInOneFile;
var
  LLog: TFastMMSamplingLog;
begin
  WriteLn('Two runs appended to one file');
  LLog := TFastMMSamplingLog.Create;
  try
    {The profiler opens the summary file in append mode, so a second run writes
     its header again in the middle of the file.  Those header lines must not
     turn into bogus samples.}
    LLog.LoadFromString(BuildSummaryLog + BuildSummaryLog, 'twice.csv');

    CheckEqualsInt(6, LLog.Count, 'both runs are loaded as rows');
    CheckEqualsInt(0, LLog.MalformedLineCount, 'the repeated header is skipped, not counted as damage');
    CheckEqualsInt(0, LLog[3].SampleIndex, 'the second run starts at sample index 0 again');
  finally
    LLog.Free;
  end;
end;

procedure TestDamagedRows;
var
  LLog: TFastMMSamplingLog;
begin
  WriteLn('Damaged rows');
  LLog := TFastMMSamplingLog.Create;
  try
    {A truncated last row is what a log from a killed process looks like.}
    LLog.LoadFromString(
      CSummaryHeader + CRLF +
      '0,2026-07-23 10:00:00.000,0,3145728,100000,150000,50000,66.67,'
        + '60000,90000,700,30000,40000,20,10000,20000,2,0,0,0' + CRLF +
      '1,2' + CRLF +
      '2,2026-07-23 10:00:02.000,2000' + CRLF, 'damaged.csv');

    CheckEqualsInt(2, LLog.Count, 'the intact row and the partially written row load');
    CheckEqualsInt(1, LLog.MalformedLineCount, 'the too short row is counted as malformed');
    CheckEqualsInt(2000, LLog[1].ElapsedMilliseconds, 'the partial row keeps the fields it has');
    CheckEqualsInt(0, LLog[1].AllocatedBytes, 'the fields it lacks read as 0');
  finally
    LLog.Free;
  end;
end;

procedure TestDetailLog;
var
  LLog: TFastMMSamplingLog;
  LSizes: TStringList;
begin
  WriteLn('Detail log');
  LLog := TFastMMSamplingLog.Create;
  try
    LLog.LoadFromString(BuildDetailLog, 'detail.csv');

    Check(LLog.Kind = slkDetail, 'kind detected as detail');
    CheckEqualsInt(4, LLog.DetailCount, 'detail row count');
    CheckEqualsInt(0, LLog.Count, 'a detail log produces no summary rows');
    CheckEqualsInt(16, LLog.DetailRows[0].BlockSize, 'block size');
    CheckEqualsInt(8, LLog.DetailRows[0].UseableSize, 'useable size');
    CheckEqualsInt(900, LLog.DetailRows[2].AllocatedCount, 'allocated count');
    CheckEqualsInt(131072, LLog.DetailRows[2].ReservedBytes, 'reserved bytes');
    CheckEqualsInt(7200, LLog.DetailRows[2].UsedBytes, 'used bytes');
    Check(Abs(LLog.DetailRows[3].EfficiencyPercentage - 14.65) < 0.0001, 'detail efficiency');

    LSizes := LLog.DetailBlockSizes;
    try
      CheckEqualsInt(2, LSizes.Count, 'distinct block sizes');
      Check(LSizes[0] = '16', 'block sizes sorted numerically ascending (first)');
      Check(LSizes[1] = '32', 'block sizes sorted numerically ascending (second)');
    finally
      LSizes.Free;
    end;
  finally
    LLog.Free;
  end;
end;

procedure TestDetailAlongsideSummary;
var
  LLog: TFastMMSamplingLog;
begin
  WriteLn('Summary plus detail in one log object');
  LLog := TFastMMSamplingLog.Create;
  try
    LLog.LoadFromString(BuildSummaryLog, 'test.csv');
    CheckEqualsInt(3, LLog.Count, 'summary rows loaded');
    CheckEqualsInt(0, LLog.DetailCount, 'no detail rows yet');
  finally
    LLog.Free;
  end;
end;

procedure TestRecognition;
begin
  WriteLn('File type recognition');
  Check(TFastMMSamplingLog.LooksLikeSamplingLog(BuildSummaryLog), 'summary log recognised');
  Check(TFastMMSamplingLog.LooksLikeSamplingLog(BuildDetailLog), 'detail log recognised');
  Check(TFastMMSamplingLog.LooksLikeSamplingLog(#$EF#$BB#$BF + BuildSummaryLog),
    'summary log with a UTF-8 BOM recognised');
  Check(not TFastMMSamplingLog.LooksLikeSamplingLog(
    '--------------------------------2026-07-17 14:32:01--------------------------------'#13#10 +
    'A memory block has been leaked. The size is: 48'),
    'a leak report is not mistaken for a sampling log');
  Check(not TFastMMSamplingLog.LooksLikeSamplingLog('FastMM State Capture:'),
    'a state capture is not mistaken for a sampling log');
  Check(not TFastMMSamplingLog.LooksLikeSamplingLog(''), 'empty text is not a sampling log');
end;

procedure TestEmptyLog;
var
  LLog: TFastMMSamplingLog;
begin
  WriteLn('Header only / empty log');
  LLog := TFastMMSamplingLog.Create;
  try
    LLog.LoadFromString(CSummaryHeader + CRLF, 'empty.csv');
    CheckEqualsInt(0, LLog.Count, 'no rows');
    CheckEqualsInt(0, LLog.DurationMilliseconds, 'duration of an empty log is 0');
    Check(Abs(LLog.MaxOf(ssAllocated)) < 0.5, 'max of an empty log is 0');
    CheckEqualsInt(-1, LLog.IndexOfMax(ssAllocated), 'index of max of an empty log is -1');
  finally
    LLog.Free;
  end;
end;

procedure TestSeriesMetadata;
begin
  WriteLn('Series metadata');
  Check(FastMMSampleSeriesName(ssAllocated) = 'Allocated bytes', 'series name');
  Check(FastMMSampleSeriesUnit(ssEfficiency) = '%', 'efficiency is a percentage');
  Check(FastMMSampleSeriesUnit(ssSmallBlockCount) = 'blocks', 'block count unit');
  Check(FastMMSampleSeriesUnit(ssSmallContention) = 'events', 'contention unit');
  Check(FastMMSampleSeriesIsBytes(ssReserved), 'reserved is a byte series');
  Check(not FastMMSampleSeriesIsBytes(ssEfficiency), 'efficiency is not a byte series');
end;

begin
  WriteLn('FastMM_SamplingLogParser self test');
  WriteLn('==================================');
  try
    TestSummaryLog;
    TestLogWithoutContentionColumns;
    TestReorderedColumns;
    TestTwoRunsInOneFile;
    TestDamagedRows;
    TestDetailLog;
    TestDetailAlongsideSummary;
    TestRecognition;
    TestEmptyLog;
    TestSeriesMetadata;
  except
    on E: Exception do
    begin
      WriteLn('  [EXCEPTION] ', E.ClassName, ': ', E.Message);
      Inc(GFailures);
    end;
  end;

  WriteLn('==================================');
  if GFailures = 0 then
  begin
    WriteLn('ALL CHECKS PASSED');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(GFailures, ' CHECK(S) FAILED');
    ExitCode := 1;
  end;
end.
