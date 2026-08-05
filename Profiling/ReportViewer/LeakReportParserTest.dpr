{

  LeakReportParserTest
  --------------------

  Console self-test for FastMM_LeakReportParser.  It builds sample reports whose
  text matches the FastMM5.pas templates byte-for-byte, parses them, and asserts
  that the resulting object model is correct.

  This is the real end-to-end verification for the parser and is compiled and
  run under Delphi 7, Delphi 10 Seattle and Delphi 13.1.

  Exit code 0 = all checks passed, 1 = a check failed.

}

program LeakReportParserTest;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Contnrs,
  FastMM_LeakReportParser in 'FastMM_LeakReportParser.pas';

const
  CRLF = #13#10;

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

{Builds a leak report that matches FastMM_MemoryLeakDetailMessage_DebugBlock,
 FastMM_MemoryLeakDetailMessage_NormalBlock and
 FastMM_MemoryLeakSummaryMessage_LeakDetailLoggedToEventLog.}
function BuildSampleLeakReport: string;
var
  LHeader, LDebugBlock, LNormalBlock, LSummary: string;
begin
  LHeader :=
    '--------------------------------2026-07-17 14:32:01--------------------------------' + CRLF;

  {A debug block (has allocation thread + stack trace). Stack-trace token 6
   starts with CRLF, so each frame ends up on its own line.}
  LDebugBlock :=
    'A memory block has been leaked. The size is: 48' + CRLF + CRLF +
    'This block was allocated on 2026-07-17 14:31:55 by thread 0x1A2C, and the stack trace (return addresses) at the time was:' +
      CRLF +
      '0040BC53[Unit1.pas][Unit1][TForm1.Button1Click][42]' + CRLF +
      '004AB1C7[Vcl.Controls.pas][Vcl.Controls][TControl.Click][7100]' + CRLF +
      '77AABBCC[kernel32.dll]' + CRLF + CRLF +
    'The block is currently used for an object of class: TStringList' + CRLF + CRLF +
    'The allocation number is: 123456' + CRLF + CRLF +
    'Current memory dump of 48 bytes starting at pointer address 0x02A4C010:' + CRLF +
      '0x02A4C010: 90 4B 4A 00 00 00 00 00' + CRLF +
      'TStringList.....' + CRLF;

  {A second debug block of the same class, so grouping has something to merge.}
  LNormalBlock :=
    'A memory block has been leaked. The size is: 48' + CRLF + CRLF +
    'This block was allocated on 2026-07-17 14:31:56 by thread 0x1A2C, and the stack trace (return addresses) at the time was:' +
      CRLF +
      '0040BC53[Unit1.pas][Unit1][TForm1.Button1Click][43]' + CRLF + CRLF +
    'The block is currently used for an object of class: TStringList' + CRLF + CRLF +
    'The allocation number is: 123457' + CRLF + CRLF +
    'Current memory dump of 48 bytes starting at pointer address 0x02A4C080:' + CRLF +
      '0x02A4C080: 90 4B 4A 00 00 00 00 00' + CRLF +
      'TStringList.....' + CRLF;

  {A third block of a different class.}
  LSummary :=
    'A memory block has been leaked. The size is: 20' + CRLF + CRLF +
    'This block was allocated on 2026-07-17 14:31:57 by thread 0x1A2C, and the stack trace (return addresses) at the time was:' +
      CRLF +
      '0040C111[Unit1.pas][Unit1][TForm1.MakeLeak][88]' + CRLF + CRLF +
    'The block is currently used for an object of class: AnsiString' + CRLF + CRLF +
    'The allocation number is: 123458' + CRLF + CRLF +
    'Current memory dump of 20 bytes starting at pointer address 0x02A4D000:' + CRLF +
      '0x02A4D000: 41 42 43' + CRLF +
      'ABC' + CRLF;

  Result :=
    LHeader + LDebugBlock +
    LHeader + LNormalBlock +
    LHeader + LSummary +
    LHeader +
    'This application has leaked memory. The leaks ordered by size are:' + CRLF +
    CRLF +
    '20: 1 x AnsiString' + CRLF +
    '48: 2 x TStringList' + CRLF +
    CRLF +
    'Memory leak detail was logged to C:\Temp\MyApp_MemoryManager_EventLog.txt' + CRLF;
end;

{Builds a state capture that matches FastMM_LogStateToFileTemplate and
 FastMM_LogStateToFileTemplate_UsageDetail.}
function BuildSampleStateCapture: string;
begin
  Result :=
    'FastMM State Capture:' + CRLF +
    '---------------------' + CRLF + CRLF +
    'Timestamp:' + CRLF +
    '2026-07-17 14:32:01' + CRLF + CRLF +
    'Usage Summary:' + CRLF +
    '12345K Allocated' + CRLF +
    '678K Overhead' + CRLF +
    '94% Efficiency' + CRLF + CRLF +
    'Usage Detail:' + CRLF +
    '2048 bytes: TStringList x 4 (512 bytes avg.)' + CRLF +
    '1024 bytes: AnsiString x 8 (128 bytes avg.)' + CRLF +
    '512 bytes: Unknown x 2 (256 bytes avg.)' + CRLF;
end;

procedure TestLeakReport;
var
  LReport: TFastMMLeakReport;
  LGroups: TObjectList;
  LBlock: TFastMMLeakBlock;
  LFrame: TFastMMStackFrame;
  LGroup: TFastMMGroup;
  i: Integer;
  LFoundStringList: Boolean;
begin
  WriteLn('Test: event-log leak report');
  LReport := TFastMMLeakReport.Create;
  try
    LReport.LoadFromString(BuildSampleLeakReport);

    Check(LReport.Kind = rkLeakReport, 'kind is rkLeakReport');
    Check(LReport.Blocks.Count = 3, 'three leaked blocks parsed');
    Check(LReport.SummaryLines.Count = 2, 'two summary lines parsed');
    Check(LReport.EventLogPath = 'C:\Temp\MyApp_MemoryManager_EventLog.txt',
      'event-log path captured');

    {First block details.}
    LBlock := TFastMMLeakBlock(LReport.Blocks[0]);
    Check(LBlock.BlockSize = 48, 'block[0] size = 48');
    Check(LBlock.ContentType = 'TStringList', 'block[0] class = TStringList');
    Check(LBlock.AllocationNumber = '123456', 'block[0] alloc number = 123456');
    Check(LBlock.AllocatedByThread = '0x1A2C', 'block[0] thread = 0x1A2C');
    Check(LBlock.AllocationDate = '2026-07-17', 'block[0] alloc date parsed');
    Check(LBlock.AllocationTime = '14:31:55', 'block[0] alloc time parsed');
    Check(LBlock.DumpAddress = '0x02A4C010', 'block[0] dump address parsed');
    Check(LBlock.AllocStack.Count = 3, 'block[0] has 3 stack frames');

    {First frame with full source location.}
    LFrame := TFastMMStackFrame(LBlock.AllocStack[0]);
    Check(LFrame.Address = '0040BC53', 'frame[0] address parsed');
    Check(LFrame.SourceFile = 'Unit1.pas', 'frame[0] source file parsed');
    Check(LFrame.UnitName = 'Unit1', 'frame[0] unit parsed');
    Check(LFrame.Routine = 'TForm1.Button1Click', 'frame[0] routine parsed');
    Check(LFrame.LineNumber = 42, 'frame[0] line number = 42');
    Check(LFrame.HasSourceLocation, 'frame[0] has jump-to-source location');

    {Second frame uses a dotted namespace unit (Vcl.Controls): the unit must
     land in UnitName, not the routine column.}
    LFrame := TFastMMStackFrame(LBlock.AllocStack[1]);
    Check(LFrame.SourceFile = 'Vcl.Controls.pas', 'frame[1] namespaced source file');
    Check(LFrame.UnitName = 'Vcl.Controls', 'frame[1] namespaced unit = Vcl.Controls');
    Check(LFrame.Routine = 'TControl.Click', 'frame[1] routine = TControl.Click');
    Check(LFrame.LineNumber = 7100, 'frame[1] line number = 7100');

    {Third frame is just a module name (no source).}
    LFrame := TFastMMStackFrame(LBlock.AllocStack[2]);
    Check(LFrame.Address = '77AABBCC', 'frame[2] address parsed');
    Check(not LFrame.HasSourceLocation, 'frame[2] has no source location');

    {Grouping by content type, sorted by total bytes descending.}
    LGroups := LReport.BuildGroups(gsTotalBytesDesc);
    Check(LGroups.Count = 2, 'two content-type groups');
    LGroup := TFastMMGroup(LGroups[0]);
    Check(LGroup.ContentType = 'TStringList', 'largest group is TStringList');
    Check(LGroup.InstanceCount = 2, 'TStringList group has 2 instances');
    Check(LGroup.TotalBytes = 96, 'TStringList group totals 96 bytes');
    Check(LGroup.Blocks.Count = 2, 'TStringList group references 2 blocks');

    {Sort by content type ascending puts AnsiString first.}
    LGroups := LReport.BuildGroups(gsContentTypeAsc);
    LGroup := TFastMMGroup(LGroups[0]);
    Check(LGroup.ContentType = 'AnsiString', 'alphabetical sort puts AnsiString first');

    {Aggregate totals.}
    Check(LReport.TotalLeakedBytes = 116, 'total leaked bytes = 116');
    Check(LReport.TotalLeakedCount = 3, 'total leaked count = 3');

    {Summary line contents.}
    LFoundStringList := False;
    for i := 0 to LReport.SummaryLines.Count - 1 do
      if TFastMMSummaryLine(LReport.SummaryLines[i]).BlockSize = 48 then
      begin
        LFoundStringList := True;
        Check(TFastMMSummaryLine(LReport.SummaryLines[i]).TotalCount = 2,
          'summary line for size 48 counts 2');
      end;
    Check(LFoundStringList, 'summary line for size 48 present');
  finally
    LReport.Free;
  end;
  WriteLn;
end;

procedure TestStateCapture;
var
  LReport: TFastMMLeakReport;
  LEntry: TFastMMStateEntry;
  LGroups: TObjectList;
begin
  WriteLn('Test: state capture (FastMM_LogStateToFile)');
  LReport := TFastMMLeakReport.Create;
  try
    LReport.LoadFromString(BuildSampleStateCapture);

    Check(LReport.Kind = rkStateCapture, 'kind is rkStateCapture');
    Check(LReport.Timestamp = '2026-07-17 14:32:01', 'timestamp parsed');
    Check(LReport.AllocatedKB = 12345, 'allocated KB = 12345');
    Check(LReport.OverheadKB = 678, 'overhead KB = 678');
    Check(LReport.EfficiencyPercent = 94, 'efficiency = 94%');
    Check(LReport.StateEntries.Count = 3, 'three usage-detail entries');

    LEntry := TFastMMStateEntry(LReport.StateEntries[0]);
    Check(LEntry.TotalBytes = 2048, 'entry[0] total bytes = 2048');
    Check(LEntry.ContentType = 'TStringList', 'entry[0] class = TStringList');
    Check(LEntry.InstanceCount = 4, 'entry[0] instance count = 4');
    Check(LEntry.AverageBytes = 512, 'entry[0] average bytes = 512');

    LGroups := LReport.BuildGroups(gsInstanceCountDesc);
    Check(LGroups.Count = 3, 'three groups from state entries');
    Check(TFastMMGroup(LGroups[0]).ContentType = 'AnsiString',
      'most-instances group is AnsiString (8)');
  finally
    LReport.Free;
  end;
  WriteLn;
end;

procedure TestEncodingRoundTrip;
var
  LReport: TFastMMLeakReport;
  LFile: string;
  LStream: TFileStream;
  LWide: WideString;
  LBom: array[0..1] of Byte;
begin
  WriteLn('Test: UTF-16LE + BOM file decoding');
  LFile := ExtractFilePath(ParamStr(0)) + 'sample_utf16.txt';
  LWide := BuildSampleStateCapture;
  LStream := TFileStream.Create(LFile, fmCreate);
  try
    LBom[0] := $FF;
    LBom[1] := $FE;
    LStream.WriteBuffer(LBom[0], 2);
    LStream.WriteBuffer(LWide[1], Length(LWide) * 2);
  finally
    LStream.Free;
  end;

  LReport := TFastMMLeakReport.Create;
  try
    LReport.LoadFromFile(LFile);
    Check(LReport.Kind = rkStateCapture, 'UTF-16 file recognised as state capture');
    Check(LReport.AllocatedKB = 12345, 'UTF-16 file decoded correctly');
    Check(LReport.StateEntries.Count = 3, 'UTF-16 file entries parsed');
  finally
    LReport.Free;
  end;
  DeleteFile(LFile);
  WriteLn;
end;

{A report written by FastMM4 (or any build using a single-byte encoder) is
 plain ANSI.  Feeding such bytes through Utf8ToAnsi / UTF8ToString yields an
 empty string, so the decoder has to recognise them and read them as ANSI.}
procedure TestAnsiReportDecoding;
var
  LReport: TFastMMLeakReport;
  LFile: string;
  LStream: TFileStream;
  LAnsi: AnsiString;
  LEntry: TFastMMStateEntry;
begin
  WriteLn('Test: legacy ANSI (non-UTF-8) file decoding');

  {The class name carries Latin-1 high bytes.  As a raw byte sequence
   'TGr' #$F6 #$DF 'e' is *not* well-formed UTF-8 - exactly the situation with
   an ANSI report - so the decoder must fall back instead of returning blank.}
  LAnsi :=
    'FastMM State Capture:'#13#10 +
    '---------------------'#13#10#13#10 +
    'Timestamp:'#13#10 +
    '2026-08-05 14:32:01'#13#10#13#10 +
    'Usage Summary:'#13#10 +
    '4711K Allocated'#13#10 +
    '222K Overhead'#13#10 +
    '91% Efficiency'#13#10#13#10 +
    'Usage Detail:'#13#10 +
    '2048 bytes: TGr' + AnsiChar($F6) + AnsiChar($DF) + 'e x 4 (512 bytes avg.)'#13#10 +
    '1024 bytes: AnsiString x 8 (128 bytes avg.)'#13#10;

  LFile := ExtractFilePath(ParamStr(0)) + 'sample_ansi.txt';
  LStream := TFileStream.Create(LFile, fmCreate);
  try
    LStream.WriteBuffer(LAnsi[1], Length(LAnsi));
  finally
    LStream.Free;
  end;

  LReport := TFastMMLeakReport.Create;
  try
    LReport.LoadFromFile(LFile);
    Check(LReport.Kind = rkStateCapture, 'ANSI file recognised as state capture');
    Check(LReport.AllocatedKB = 4711, 'ANSI file decoded (not blank)');
    Check(LReport.OverheadKB = 222, 'ANSI overhead parsed');
    Check(LReport.StateEntries.Count = 2, 'ANSI usage-detail entries parsed');
    if LReport.StateEntries.Count = 2 then
    begin
      LEntry := TFastMMStateEntry(LReport.StateEntries[0]);
      Check(LEntry.TotalBytes = 2048, 'ANSI entry[0] total bytes');
      Check(LEntry.InstanceCount = 4, 'ANSI entry[0] instance count');
      {Each high byte must survive as exactly one character - 'TGr' + 2 + 'e'.}
      Check(Length(LEntry.ContentType) = 6, 'ANSI high bytes kept as single chars');
      Check(Copy(LEntry.ContentType, 1, 3) = 'TGr', 'ANSI class name preserved');
    end;
  finally
    LReport.Free;
  end;
  DeleteFile(LFile);
  WriteLn;
end;

{FastMM4 writes the same kind of report with slightly different wording:  no
 timestamp on the allocation line, size-class ranges in the summary, and stack
 frames whose first field is often a bare module name rather than a file.}
procedure TestFastMM4Format;
var
  LReport: TFastMMLeakReport;
  LText: string;
  LBlock: TFastMMLeakBlock;
  LFrame: TFastMMStackFrame;
  LSummary: TFastMMSummaryLine;
begin
  WriteLn('Test: FastMM4-style report');

  LText :=
    StringOfChar('-', 32) + '2026/8/4 14:49:44' + StringOfChar('-', 32) + CRLF +
    'A memory block has been leaked. The size is: 36' + CRLF + CRLF +
    'This block was allocated by thread 0xDF4, and the stack trace (return addresses) at the time was:' + CRLF +
    '00402ED8 [ZLibMinimal][ZLibMinimal][@GetMem]' + CRLF +
    '00900E0C [uRegelung.pas][uRegelung][uRegelung_Federdaten_eintragen][1084]' + CRLF +
    '0053AE03 [Forms][Forms][TCustomForm.DoShow]' + CRLF +
    '772253CF [TranslateMessage]' + CRLF +
    '714310B1 ' + CRLF + CRLF +
    'The block is currently used for an object of class: AnsiString' + CRLF + CRLF +
    'The allocation number is: 806969' + CRLF + CRLF +
    'Current memory dump of 256 bytes starting at pointer address 7DD97830:' + CRLF +
    '01 00 00 00 10 00 00 00' + CRLF + CRLF +
    StringOfChar('-', 32) + '2026/8/4 15:14:52' + StringOfChar('-', 32) + CRLF +
    'This application has leaked memory. The small block leaks are (excluding expected leaks registered by pointer):' + CRLF + CRLF +
    '21 - 36 bytes: TCriticalSection x 1, AnsiString x 1, Unknown x 2' + CRLF +
    '37 - 52 bytes: Classes.TStringList x 4, AnsiString x 1' + CRLF + CRLF +
    'Note: Memory leak detail is logged to a text file in the same folder as this application.' + CRLF;

  LReport := TFastMMLeakReport.Create;
  try
    LReport.LoadFromString(LText);
    Check(LReport.Kind = rkLeakReport, 'FastMM4 report recognised');
    Check(LReport.Blocks.Count = 1, 'FastMM4 leak block parsed');

    if LReport.Blocks.Count = 1 then
    begin
      LBlock := TFastMMLeakBlock(LReport.Blocks[0]);
      Check(LBlock.BlockSize = 36, 'FastMM4 block size');
      Check(LBlock.ContentType = 'AnsiString', 'FastMM4 block class');
      Check(LBlock.AllocationNumber = '806969', 'FastMM4 allocation number');
      {The timestamp-less allocation line must still yield the thread ...}
      Check(LBlock.AllocatedByThread = '0xDF4', 'FastMM4 thread id (no timestamp)');
      Check(LBlock.AllocationDate = '', 'FastMM4 has no allocation date');
      {... and, crucially, the stack trace that follows it.}
      Check(LBlock.AllocStack.Count = 5, 'FastMM4 stack frames parsed');

      if LBlock.AllocStack.Count = 5 then
      begin
        {Bare module name in all three fields.}
        LFrame := TFastMMStackFrame(LBlock.AllocStack[0]);
        Check(LFrame.Address = '00402ED8', 'FastMM4 frame[0] address');
        Check(LFrame.UnitName = 'ZLibMinimal', 'FastMM4 frame[0] unit');
        Check(LFrame.Routine = '@GetMem', 'FastMM4 frame[0] routine');

        {Full source information - this one must support jump-to-source.}
        LFrame := TFastMMStackFrame(LBlock.AllocStack[1]);
        Check(LFrame.SourceFile = 'uRegelung.pas', 'FastMM4 frame[1] source file');
        Check(LFrame.UnitName = 'uRegelung', 'FastMM4 frame[1] unit');
        Check(LFrame.Routine = 'uRegelung_Federdaten_eintragen', 'FastMM4 frame[1] routine');
        Check(LFrame.LineNumber = 1084, 'FastMM4 frame[1] line number');
        Check(LFrame.HasSourceLocation, 'FastMM4 frame[1] can jump to source');

        {Three fields, none of them a file name:  must not end up merged.}
        LFrame := TFastMMStackFrame(LBlock.AllocStack[2]);
        Check(LFrame.UnitName = 'Forms', 'FastMM4 frame[2] unit');
        Check(LFrame.Routine = 'TCustomForm.DoShow', 'FastMM4 frame[2] routine not merged');

        {A single field is the routine.}
        LFrame := TFastMMStackFrame(LBlock.AllocStack[3]);
        Check(LFrame.Routine = 'TranslateMessage', 'FastMM4 frame[3] routine only');

        {Address with no symbol information at all.}
        LFrame := TFastMMStackFrame(LBlock.AllocStack[4]);
        Check(LFrame.Address = '714310B1', 'FastMM4 frame[4] bare address');
      end;
    end;

    {Size-class ranges in the summary.}
    Check(LReport.SummaryLines.Count = 2, 'FastMM4 summary ranges parsed');
    if LReport.SummaryLines.Count = 2 then
    begin
      LSummary := TFastMMSummaryLine(LReport.SummaryLines[0]);
      Check(LSummary.BlockSize = 36, 'FastMM4 summary uses the range upper bound');
      Check(LSummary.SizeText = '21 - 36 bytes', 'FastMM4 summary keeps the range label');
      Check(LSummary.Pairs.Count = 3, 'FastMM4 summary pairs parsed');
      {FastMM4 puts the multiplier on the right: "TCriticalSection x 1".}
      Check(TFastMMSummaryPair(LSummary.Pairs[0]).ContentType = 'TCriticalSection',
        'FastMM4 summary pair type (count is on the right)');
      Check(TFastMMSummaryPair(LSummary.Pairs[0]).Count = 1, 'FastMM4 summary pair count');
      Check(TFastMMSummaryPair(LSummary.Pairs[2]).ContentType = 'Unknown',
        'FastMM4 summary last pair type');
      Check(TFastMMSummaryPair(LSummary.Pairs[2]).Count = 2, 'FastMM4 summary last pair count');
      Check(LSummary.TotalCount = 4, 'FastMM4 summary counts summed');
    end;

    {The entry header dates the run - needed to tell appended reports apart.}
    Check(LReport.Timestamp = '2026/8/4 14:49:44', 'FastMM4 header timestamp captured');
    Check(Pos('2026/8/4 14:49:44', LReport.Describe) > 0,
      'FastMM4 timestamp shown in the report description');
  finally
    LReport.Free;
  end;
  WriteLn;
end;

(*An event log is appended to, so the reports in a file run oldest first and the
  newest one is last.  The viewer labels them accordingly, which only works if
  each report carries the timestamp from its own header.*)
procedure TestReportTimestampsAndOrder;
var
  LSet: TFastMMReportSet;
  LText: string;

  function Run(const ATimestamp, AClass: string): string;
  begin
    Result :=
      StringOfChar('-', 32) + ATimestamp + StringOfChar('-', 32) + CRLF +
      'A memory block has been leaked. The size is: 16' + CRLF + CRLF +
      'This block was allocated by thread 0x100, and the stack trace (return addresses) at the time was:' + CRLF +
      '00401000 [Unit1.pas][Unit1][DoIt][10]' + CRLF + CRLF +
      'The block is currently used for an object of class: ' + AClass + CRLF + CRLF +
      'The allocation number is: 1' + CRLF + CRLF +
      StringOfChar('-', 32) + ATimestamp + StringOfChar('-', 32) + CRLF +
      'This application has leaked memory. The leaks ordered by size are:' + CRLF + CRLF +
      '16: 1 x ' + AClass + CRLF;
  end;

begin
  WriteLn('Test: report timestamps and chronological order');
  LText := Run('2026-08-05 09:00:00', 'TOldest') +
           Run('2026-08-05 12:30:00', 'TMiddle') +
           Run('2026-08-05 18:45:00', 'TNewest');

  LSet := TFastMMReportSet.Create;
  try
    LSet.LoadFromString(LText, 'appended.log');
    Check(LSet.Count = 3, 'three appended runs split apart');
    if LSet.Count = 3 then
    begin
      Check(LSet[0].Timestamp = '2026-08-05 09:00:00', 'run 0 keeps its own timestamp');
      Check(LSet[1].Timestamp = '2026-08-05 12:30:00', 'run 1 keeps its own timestamp');
      Check(LSet[2].Timestamp = '2026-08-05 18:45:00', 'run 2 keeps its own timestamp');
      {File order is chronological: oldest first, newest last.}
      Check(LSet[0].Timestamp < LSet[2].Timestamp, 'listed oldest first, newest last');
      Check(Pos('2026-08-05 18:45:00', LSet[2].Describe) > 0,
        'newest run describes itself with its timestamp');
    end;

    {A timestamp with milliseconds (the FastMM5 fork format) survives too.}
    LSet.LoadFromString(Run('2026-08-05 21:50:55.741', 'TMillis'), 'ms.log');
    Check(LSet[0].Timestamp = '2026-08-05 21:50:55.741', 'millisecond timestamp kept');
  finally
    LSet.Free;
  end;
  WriteLn;
end;

{The debug DLL can be built against madExcept, EurekaLog or the MacOS map-file
 code instead of the JCL default, and an application may install its own
 FastMM_ConvertStackTraceToText.  None of those use the bracket layout, so an
 unrecognised frame must still show its text rather than an empty row.}
(*The debug DLL can be built against madExcept instead of the JCL default by
  switching to {$define madExcept} in FastMM_FullDebugMode.dpr.  madStackTrace
  then formats the frames as space padded columns with no brackets at all:

    0041f412 +1a MadLeakGen.exe FastMM5    9345  +4 FastMM_DebugGetMem

  Every line below is copied verbatim from a report produced by such a DLL.*)
procedure TestMadExceptFrameFormat;
var
  LFrame: TFastMMStackFrame;
begin
  WriteLn('Test: madExcept stack-frame format');

  {Full house: module, unit, line, relative line, routine.}
  LFrame := FastMMParseStackFrame('004e1837 +0b MadLeakGen.exe MadLeakGen   56  +0 MakeStringLeak');
  try
    Check(LFrame.Address = '004e1837', 'madExcept address');
    Check(LFrame.ModuleName = 'MadLeakGen.exe', 'madExcept module');
    Check(LFrame.UnitName = 'MadLeakGen', 'madExcept unit');
    Check(LFrame.LineNumber = 56, 'madExcept line number');
    Check(LFrame.Routine = 'MakeStringLeak', 'madExcept routine');
    Check(LFrame.HasSourceLocation, 'madExcept frame can jump to source');
    Check(LFrame.SourceFileCandidate = 'MadLeakGen.pas', 'madExcept source file derived from unit');
  finally
    LFrame.Free;
  end;

  {Dotted namespace unit, and no line information.}
  LFrame := FastMMParseStackFrame('004b1959 +05 MadLeakGen.exe System.Classes          TStringList.Add');
  try
    Check(LFrame.UnitName = 'System.Classes', 'madExcept dotted unit kept intact');
    Check(LFrame.Routine = 'TStringList.Add', 'madExcept routine with no line');
    Check(LFrame.LineNumber = 0, 'madExcept missing line stays 0');
    Check(not LFrame.HasSourceLocation, 'madExcept frame without line cannot jump');
  finally
    LFrame.Free;
  end;

  {System DLL: module and routine only, no unit, no line.}
  LFrame := FastMMParseStackFrame('76d05d47 +17 KERNEL32.DLL                       BaseThreadInitThunk');
  try
    Check(LFrame.ModuleName = 'KERNEL32.DLL', 'madExcept system module');
    Check(LFrame.Routine = 'BaseThreadInitThunk', 'madExcept system routine');
    Check(LFrame.UnitName = '', 'madExcept system frame has no unit');
    Check(not LFrame.HasSourceLocation, 'madExcept system frame cannot jump');
  finally
    LFrame.Free;
  end;

  {Wider column padding for the same shape - widths are recomputed per trace,
   so the parser must not depend on fixed positions.}
  LFrame := FastMMParseStackFrame('0041f412 +1a MadLeakGen.exe FastMM5        9345  +4 FastMM_DebugGetMem');
  try
    Check(LFrame.UnitName = 'FastMM5', 'madExcept wide padding: unit');
    Check(LFrame.LineNumber = 9345, 'madExcept wide padding: line');
    Check(LFrame.Routine = 'FastMM_DebugGetMem', 'madExcept wide padding: routine');
  finally
    LFrame.Free;
  end;

  {A routine named like a keyword, with a two digit relative line.}
  LFrame := FastMMParseStackFrame('004e586e +c2 MadLeakGen.exe MadLeakGen   80 +13 initialization');
  try
    Check(LFrame.LineNumber = 80, 'madExcept initialization frame line');
    Check(LFrame.Routine = 'initialization', 'madExcept initialization frame routine');
  finally
    LFrame.Free;
  end;

  {The JCL bracket format must keep winning where brackets are present.}
  LFrame := FastMMParseStackFrame('0040BC53[Unit1.pas][Unit1][TForm1.Button1Click][42]');
  try
    Check(LFrame.SourceFile = 'Unit1.pas', 'bracket format still takes precedence');
    Check(LFrame.ModuleName = '', 'bracket format sets no module');
  finally
    LFrame.Free;
  end;
  WriteLn;
end;

procedure TestUnknownFrameFormatFallback;
var
  LFrame: TFastMMStackFrame;
begin
  WriteLn('Test: fallback for unknown stack-frame formats');

  {madExcept: space padded columns, no brackets at all.}
  LFrame := FastMMParseStackFrame('0040ce7a +02a MyApp.exe   uMain   142  +5 TForm1.Button1Click');
  try
    Check(LFrame.Address = '0040ce7a', 'unknown format: address still parsed');
    Check(Pos('TForm1.Button1Click', LFrame.Routine) > 0,
      'unknown format: text preserved in the routine column');
    Check(LFrame.DisplayText <> '', 'unknown format: something is displayable');
  finally
    LFrame.Free;
  end;

  {An entirely free-form line without any address.}
  LFrame := FastMMParseStackFrame('  some completely unexpected trace text  ');
  try
    Check(LFrame.Routine = 'some completely unexpected trace text',
      'free-form line kept verbatim');
    Check(LFrame.RawText <> '', 'free-form line keeps RawText');
  finally
    LFrame.Free;
  end;

  {An address on its own must NOT invent a routine.}
  LFrame := FastMMParseStackFrame('714310B1');
  try
    Check(LFrame.Address = '714310B1', 'bare address parsed');
    Check(LFrame.Routine = '', 'bare address has no routine');
  finally
    LFrame.Free;
  end;
  WriteLn;
end;

procedure TestUtf8Detection;
const
  {'A' 'B' - plain ASCII}
  CAscii: array[0..1] of AnsiChar = ('A', 'B');
  {U+00F6 encoded as UTF-8 ($C3 $B6)}
  CUtf8Two: array[0..1] of AnsiChar = (AnsiChar($C3), AnsiChar($B6));
  {U+20AC encoded as UTF-8 ($E2 $82 $AC)}
  CUtf8Three: array[0..2] of AnsiChar = (AnsiChar($E2), AnsiChar($82), AnsiChar($AC));
  {Latin-1 'o-umlaut' followed by ASCII - a lone high byte, invalid UTF-8}
  CAnsiHigh: array[0..1] of AnsiChar = (AnsiChar($F6), 'e');
  {A 3-byte lead with only one continuation byte present - truncated}
  CTruncated: array[0..1] of AnsiChar = (AnsiChar($E2), AnsiChar($82));
  {A stray continuation byte with no lead}
  CStrayTrail: array[0..1] of AnsiChar = (AnsiChar($AC), 'x');
begin
  WriteLn('Test: UTF-8 vs ANSI detection');
  Check(FastMMLooksLikeUtf8(@CAscii[0], 2), 'ASCII counts as UTF-8');
  Check(FastMMLooksLikeUtf8(@CUtf8Two[0], 2), '2-byte UTF-8 sequence accepted');
  Check(FastMMLooksLikeUtf8(@CUtf8Three[0], 3), '3-byte UTF-8 sequence accepted');
  Check(not FastMMLooksLikeUtf8(@CAnsiHigh[0], 2), 'lone Latin-1 high byte rejected');
  Check(not FastMMLooksLikeUtf8(@CTruncated[0], 2), 'truncated sequence rejected');
  Check(not FastMMLooksLikeUtf8(@CStrayTrail[0], 2), 'stray continuation byte rejected');
  WriteLn;
end;

procedure TestMultipleReports;
var
  LSet: TFastMMReportSet;
  LCapA, LCapB: string;
begin
  WriteLn('Test: multiple reports in one file');
  LSet := TFastMMReportSet.Create;
  try
    {Two leak-check runs appended to one event-log file (each run ends with the
     summary line).}
    LSet.LoadFromString(BuildSampleLeakReport + BuildSampleLeakReport, 'event.log');
    Check(LSet.Count = 2, 'two leak-check runs split into two reports');
    if LSet.Count = 2 then
    begin
      Check(LSet[0].Kind = rkLeakReport, 'run 0 is a leak report');
      Check(LSet[0].Blocks.Count = 3, 'run 0 has its own 3 blocks');
      Check(LSet[1].Blocks.Count = 3, 'run 1 has its own 3 blocks (not merged)');
      Check(LSet[0].SourceFileName = 'event.log', 'sub-report keeps source file name');
    end;

    {Two state captures appended (ATruncateFile = False).}
    LCapA := BuildSampleStateCapture;
    LCapB := StringReplace(BuildSampleStateCapture, '12345K Allocated', '99999K Allocated', []);
    LSet.LoadFromString(LCapA + LCapB, 'state.txt');
    Check(LSet.Count = 2, 'two appended state captures split into two reports');
    if LSet.Count = 2 then
    begin
      Check(LSet[0].AllocatedKB = 12345, 'capture 0 keeps its own allocated KB');
      Check(LSet[1].AllocatedKB = 99999, 'capture 1 keeps its own allocated KB');
    end;

    {A single report still yields exactly one entry.}
    LSet.LoadFromString(BuildSampleStateCapture, 'one.txt');
    Check(LSet.Count = 1, 'single report yields a one-element set');
  finally
    LSet.Free;
  end;
  WriteLn;
end;

begin
  WriteLn('FastMM_LeakReportParser self-test');
  WriteLn('=================================');
  WriteLn;
  try
    TestLeakReport;
    TestStateCapture;
    TestEncodingRoundTrip;
    TestAnsiReportDecoding;
    TestUtf8Detection;
    TestFastMM4Format;
    TestMadExceptFrameFormat;
    TestUnknownFrameFormatFallback;
    TestReportTimestampsAndOrder;
    TestMultipleReports;
  except
    on E: Exception do
    begin
      WriteLn('  [EXCEPTION] ', E.ClassName, ': ', E.Message);
      Inc(GFailures);
    end;
  end;

  WriteLn('=================================');
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
