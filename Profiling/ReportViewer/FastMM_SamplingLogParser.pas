(*

  FastMM_SamplingLogParser
  ------------------------

  A VCL-free parser for the CSV logs written by FastMM_SamplingProfiler.pas.
  It understands both files that unit produces:

    1. The summary log (one row per sample):
         sample_index,wall_clock,elapsed_ms,mm_usage_bytes,allocated_bytes,
         reserved_bytes,overhead_bytes,efficiency_pct,small_alloc_bytes,
         small_reserved_bytes,small_block_count,medium_alloc_bytes,
         medium_reserved_bytes,medium_block_count,large_alloc_bytes,
         large_reserved_bytes,large_block_count,small_contention,
         medium_contention,large_contention

    2. The detail log (one row per small block size class per sample):
         sample_index,elapsed_ms,block_size,useable_size,allocated_count,
         reserved_bytes,used_bytes,efficiency_pct

  Columns are mapped by their header name, not by position, so a log written by
  an older or newer version of the profiler still loads:  columns that are
  missing simply stay zero (HasContentionCounts reports whether the contention
  columns were present), and unknown columns are ignored.

  Numbers are parsed locale independently:  the profiler always writes a '.'
  decimal separator, so this unit never consults DecimalSeparator.

  Design constraints (matching the rest of the D7/D2009 port):
    - No generics, no anonymous methods, no Exit(Value).
    - inline directives guarded with {$IF CompilerVersion >= 18}.
    - Collections via Contnrs.TObjectList.
    - Compiles clean on Delphi 7, Delphi 10 Seattle and Delphi 13.1.

*)

unit FastMM_SamplingLogParser;

interface

uses
  Classes, SysUtils, Contnrs;

type
  TFastMMSamplingLogKind = (slkUnknown, slkSummary, slkDetail);

  {The series that can be plotted from a summary log.  Kept in one enumeration
   so the viewer can offer them generically.}
  TFastMMSampleSeries = (
    ssMemoryManagerUsage,
    ssAllocated,
    ssReserved,
    ssOverhead,
    ssEfficiency,
    ssSmallAllocated,
    ssSmallReserved,
    ssMediumAllocated,
    ssMediumReserved,
    ssLargeAllocated,
    ssLargeReserved,
    ssSmallBlockCount,
    ssMediumBlockCount,
    ssLargeBlockCount,
    ssSmallContention,
    ssMediumContention,
    ssLargeContention);

  {One row of the summary log.}
  TFastMMSampleRow = class(TObject)
  public
    SampleIndex: Int64;
    WallClock: string;             {as written, 'yyyy-mm-dd hh:nn:ss.zzz'}
    ElapsedMilliseconds: Int64;
    MemoryManagerUsageBytes: Int64;
    AllocatedBytes: Int64;
    ReservedBytes: Int64;
    OverheadBytes: Int64;
    EfficiencyPercentage: Double;
    SmallAllocatedBytes: Int64;
    SmallReservedBytes: Int64;
    SmallBlockCount: Int64;
    MediumAllocatedBytes: Int64;
    MediumReservedBytes: Int64;
    MediumBlockCount: Int64;
    LargeAllocatedBytes: Int64;
    LargeReservedBytes: Int64;
    LargeBlockCount: Int64;
    SmallContentionCount: Int64;
    MediumContentionCount: Int64;
    LargeContentionCount: Int64;
    function Value(ASeries: TFastMMSampleSeries): Double;
  end;

  {One row of the detail log:  one small block size class within one sample.}
  TFastMMSampleDetailRow = class(TObject)
  public
    SampleIndex: Int64;
    ElapsedMilliseconds: Int64;
    BlockSize: Int64;              {internal block size of the size class}
    UseableSize: Int64;
    AllocatedCount: Int64;
    ReservedBytes: Int64;
    UsedBytes: Int64;
    EfficiencyPercentage: Double;
  end;

  {A parsed sampling log.  Load a summary log through LoadFromFile and, if the
   matching detail log exists, add it with LoadDetailFromFile.}
  TFastMMSamplingLog = class(TObject)
  private
    FRows: TObjectList;            {of TFastMMSampleRow}
    FDetailRows: TObjectList;      {of TFastMMSampleDetailRow}
    FKind: TFastMMSamplingLogKind;
    FSourceName: string;
    FDetailSourceName: string;
    FHasContentionCounts: Boolean;
    FMalformedLineCount: Integer;

    function GetRow(AIndex: Integer): TFastMMSampleRow;
    function GetCount: Integer;
    function GetDetailRow(AIndex: Integer): TFastMMSampleDetailRow;
    function GetDetailCount: Integer;

    procedure ParseSummaryText(const AText: string);
    procedure ParseDetailText(const AText: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;

    {Loads a log file.  The kind (summary or detail) is taken from the header
     line, so either file may be passed here;  a detail file loaded this way
     ends up in DetailRows with Kind = slkDetail.}
    procedure LoadFromFile(const AFileName: string);
    procedure LoadFromString(const AText, ADisplayName: string);

    {Loads the detail log that belongs to an already loaded summary log.}
    procedure LoadDetailFromFile(const AFileName: string);

    {True if the text starts with a header line this unit recognises.  Used to
     tell a sampling log apart from a leak report when opening a file.}
    class function LooksLikeSamplingLog(const AText: string): Boolean;
    {The file name of the detail log that belongs to ASummaryFileName, by the
     naming convention of the demo (..._Summary.csv -> ..._Detail.csv), or an
     empty string if the name does not follow it or the file does not exist.}
    class function GuessDetailFileName(const ASummaryFileName: string): string;

    function Describe: string;
    {The elapsed time covered by the log, in milliseconds.}
    function DurationMilliseconds: Int64;
    {Highest / lowest value of a series across all rows.  Returns 0 when there
     are no rows.}
    function MaxOf(ASeries: TFastMMSampleSeries): Double;
    function MinOf(ASeries: TFastMMSampleSeries): Double;
    {The index of the row with the highest value of ASeries, or -1.}
    function IndexOfMax(ASeries: TFastMMSampleSeries): Integer;
    {The distinct small block size classes present in the detail rows, sorted
     ascending.  The caller owns the returned list.}
    function DetailBlockSizes: TStringList;

    property Kind: TFastMMSamplingLogKind read FKind;
    property SourceName: string read FSourceName;
    property DetailSourceName: string read FDetailSourceName;
    property Count: Integer read GetCount;
    property Rows[AIndex: Integer]: TFastMMSampleRow read GetRow; default;
    property DetailCount: Integer read GetDetailCount;
    property DetailRows[AIndex: Integer]: TFastMMSampleDetailRow read GetDetailRow;
    {False when the log was written before the contention columns existed.}
    property HasContentionCounts: Boolean read FHasContentionCounts;
    {Rows that could not be parsed (wrong field count, garbage).  A non-zero
     value means the file was partially damaged, not that it is a wrong file.}
    property MalformedLineCount: Integer read FMalformedLineCount;
  end;

{The display name of a series, e.g. 'Allocated bytes'.}
function FastMMSampleSeriesName(ASeries: TFastMMSampleSeries): string;
{The unit of a series:  'bytes', 'blocks', '%' or 'events'.}
function FastMMSampleSeriesUnit(ASeries: TFastMMSampleSeries): string;
{True if the series is a byte count (so the viewer can scale it to KB / MB).}
function FastMMSampleSeriesIsBytes(ASeries: TFastMMSampleSeries): Boolean;

implementation

const
  CSummaryHeaderMarker = 'sample_index,wall_clock';
  CDetailHeaderMarker = 'sample_index,elapsed_ms,block_size';

{------------------------------------------------------------------------------
  Locale independent scalar parsing
 -----------------------------------------------------------------------------}

{Parses a decimal integer.  Returns 0 for anything unparsable, which is what the
 caller wants for a missing column.}
function ParseInt64(const AText: string): Int64;
var
  i: Integer;
  LNegative: Boolean;
  LDigitSeen: Boolean;
begin
  Result := 0;
  LNegative := False;
  LDigitSeen := False;
  i := 1;
  while (i <= Length(AText)) and (AText[i] = ' ') do
    Inc(i);
  if (i <= Length(AText)) and ((AText[i] = '-') or (AText[i] = '+')) then
  begin
    LNegative := AText[i] = '-';
    Inc(i);
  end;
  while i <= Length(AText) do
  begin
    if (AText[i] >= '0') and (AText[i] <= '9') then
    begin
      Result := Result * 10 + (Ord(AText[i]) - Ord('0'));
      LDigitSeen := True;
    end
    else
      Break;
    Inc(i);
  end;
  if not LDigitSeen then
    Result := 0
  else
    if LNegative then
      Result := -Result;
end;

{Parses a fixed point number with a '.' decimal separator, independently of the
 system locale (the profiler always writes '.').}
function ParseFloat(const AText: string): Double;
var
  i: Integer;
  LNegative: Boolean;
  LScale: Double;
begin
  Result := 0;
  LNegative := False;
  i := 1;
  while (i <= Length(AText)) and (AText[i] = ' ') do
    Inc(i);
  if (i <= Length(AText)) and ((AText[i] = '-') or (AText[i] = '+')) then
  begin
    LNegative := AText[i] = '-';
    Inc(i);
  end;
  while (i <= Length(AText)) and (AText[i] >= '0') and (AText[i] <= '9') do
  begin
    Result := Result * 10 + (Ord(AText[i]) - Ord('0'));
    Inc(i);
  end;
  if (i <= Length(AText)) and (AText[i] = '.') then
  begin
    Inc(i);
    LScale := 0.1;
    while (i <= Length(AText)) and (AText[i] >= '0') and (AText[i] <= '9') do
    begin
      Result := Result + (Ord(AText[i]) - Ord('0')) * LScale;
      LScale := LScale * 0.1;
      Inc(i);
    end;
  end;
  if LNegative then
    Result := -Result;
end;

{Splits ALine on commas into AFields.  The profiler never quotes or escapes
 anything (timestamps use ':' and '-', numbers use '.'), so a plain split is
 exactly right.}
procedure SplitCsvLine(const ALine: string; AFields: TStringList);
var
  i, LStart: Integer;
begin
  AFields.Clear;
  LStart := 1;
  for i := 1 to Length(ALine) do
  begin
    if ALine[i] = ',' then
    begin
      AFields.Add(Copy(ALine, LStart, i - LStart));
      LStart := i + 1;
    end;
  end;
  AFields.Add(Copy(ALine, LStart, Length(ALine) - LStart + 1));
end;

{Reads a text file, tolerating the UTF-8 BOM that some editors add.  The
 profiler itself writes plain 7 bit ASCII.}
function ReadTextFile(const AFileName: string): string;
var
  LStream: TFileStream;
  LBytes: TStringList;
begin
  LBytes := TStringList.Create;
  try
    LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      LBytes.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Result := LBytes.Text;
  finally
    LBytes.Free;
  end;
  {Strip a UTF-8 BOM if the RTL did not (Delphi 7 does not).}
  if (Length(Result) >= 3) and (Ord(Result[1]) = $EF) and (Ord(Result[2]) = $BB)
    and (Ord(Result[3]) = $BF) then
    Delete(Result, 1, 3);
end;

{------------------------------------------------------------------------------
  Series metadata
 -----------------------------------------------------------------------------}

function FastMMSampleSeriesName(ASeries: TFastMMSampleSeries): string;
begin
  case ASeries of
    ssMemoryManagerUsage: Result := 'Memory manager usage';
    ssAllocated:          Result := 'Allocated bytes';
    ssReserved:           Result := 'Reserved bytes';
    ssOverhead:           Result := 'Overhead bytes';
    ssEfficiency:         Result := 'Efficiency';
    ssSmallAllocated:     Result := 'Small blocks allocated';
    ssSmallReserved:      Result := 'Small blocks reserved';
    ssMediumAllocated:    Result := 'Medium blocks allocated';
    ssMediumReserved:     Result := 'Medium blocks reserved';
    ssLargeAllocated:     Result := 'Large blocks allocated';
    ssLargeReserved:      Result := 'Large blocks reserved';
    ssSmallBlockCount:    Result := 'Small block count';
    ssMediumBlockCount:   Result := 'Medium block count';
    ssLargeBlockCount:    Result := 'Large block count';
    ssSmallContention:    Result := 'Small arena contention';
    ssMediumContention:   Result := 'Medium arena contention';
    ssLargeContention:    Result := 'Large arena contention';
  else
    Result := '';
  end;
end;

function FastMMSampleSeriesUnit(ASeries: TFastMMSampleSeries): string;
begin
  case ASeries of
    ssEfficiency:
      Result := '%';
    ssSmallBlockCount, ssMediumBlockCount, ssLargeBlockCount:
      Result := 'blocks';
    ssSmallContention, ssMediumContention, ssLargeContention:
      Result := 'events';
  else
    Result := 'bytes';
  end;
end;

function FastMMSampleSeriesIsBytes(ASeries: TFastMMSampleSeries): Boolean;
begin
  Result := FastMMSampleSeriesUnit(ASeries) = 'bytes';
end;

{------------------------------------------------------------------------------
  TFastMMSampleRow
 -----------------------------------------------------------------------------}

function TFastMMSampleRow.Value(ASeries: TFastMMSampleSeries): Double;
begin
  case ASeries of
    ssMemoryManagerUsage: Result := MemoryManagerUsageBytes;
    ssAllocated:          Result := AllocatedBytes;
    ssReserved:           Result := ReservedBytes;
    ssOverhead:           Result := OverheadBytes;
    ssEfficiency:         Result := EfficiencyPercentage;
    ssSmallAllocated:     Result := SmallAllocatedBytes;
    ssSmallReserved:      Result := SmallReservedBytes;
    ssMediumAllocated:    Result := MediumAllocatedBytes;
    ssMediumReserved:     Result := MediumReservedBytes;
    ssLargeAllocated:     Result := LargeAllocatedBytes;
    ssLargeReserved:      Result := LargeReservedBytes;
    ssSmallBlockCount:    Result := SmallBlockCount;
    ssMediumBlockCount:   Result := MediumBlockCount;
    ssLargeBlockCount:    Result := LargeBlockCount;
    ssSmallContention:    Result := SmallContentionCount;
    ssMediumContention:   Result := MediumContentionCount;
    ssLargeContention:    Result := LargeContentionCount;
  else
    Result := 0;
  end;
end;

{------------------------------------------------------------------------------
  TFastMMSamplingLog
 -----------------------------------------------------------------------------}

constructor TFastMMSamplingLog.Create;
begin
  inherited Create;
  FRows := TObjectList.Create(True);
  FDetailRows := TObjectList.Create(True);
  FKind := slkUnknown;
end;

destructor TFastMMSamplingLog.Destroy;
begin
  FDetailRows.Free;
  FRows.Free;
  inherited Destroy;
end;

procedure TFastMMSamplingLog.Clear;
begin
  FRows.Clear;
  FDetailRows.Clear;
  FKind := slkUnknown;
  FSourceName := '';
  FDetailSourceName := '';
  FHasContentionCounts := False;
  FMalformedLineCount := 0;
end;

function TFastMMSamplingLog.GetRow(AIndex: Integer): TFastMMSampleRow;
begin
  Result := TFastMMSampleRow(FRows[AIndex]);
end;

function TFastMMSamplingLog.GetCount: Integer;
begin
  Result := FRows.Count;
end;

function TFastMMSamplingLog.GetDetailRow(AIndex: Integer): TFastMMSampleDetailRow;
begin
  Result := TFastMMSampleDetailRow(FDetailRows[AIndex]);
end;

function TFastMMSamplingLog.GetDetailCount: Integer;
begin
  Result := FDetailRows.Count;
end;

class function TFastMMSamplingLog.LooksLikeSamplingLog(const AText: string): Boolean;
var
  LHead: string;
begin
  {Compare against the start of the text:  the header is always the first line,
   and both markers are pure ASCII.}
  LHead := Copy(AText, 1, 256);
  if (Length(LHead) >= 3) and (Ord(LHead[1]) = $EF) and (Ord(LHead[2]) = $BB)
    and (Ord(LHead[3]) = $BF) then
    Delete(LHead, 1, 3);
  Result := (Pos(CSummaryHeaderMarker, LHead) = 1) or (Pos(CDetailHeaderMarker, LHead) = 1);
end;

class function TFastMMSamplingLog.GuessDetailFileName(const ASummaryFileName: string): string;
var
  LBase, LExt: string;
begin
  Result := '';
  LExt := ExtractFileExt(ASummaryFileName);
  LBase := Copy(ASummaryFileName, 1, Length(ASummaryFileName) - Length(LExt));
  if (Length(LBase) >= 8) and (AnsiCompareText(Copy(LBase, Length(LBase) - 7, 8), '_Summary') = 0) then
  begin
    LBase := Copy(LBase, 1, Length(LBase) - 8) + '_Detail' + LExt;
    if FileExists(LBase) then
      Result := LBase;
  end;
end;

procedure TFastMMSamplingLog.LoadFromFile(const AFileName: string);
begin
  LoadFromString(ReadTextFile(AFileName), AFileName);
end;

procedure TFastMMSamplingLog.LoadFromString(const AText, ADisplayName: string);
var
  LHead: string;
begin
  Clear;
  FSourceName := ADisplayName;

  LHead := Copy(AText, 1, 256);
  if Pos(CDetailHeaderMarker, LHead) = 1 then
  begin
    FKind := slkDetail;
    ParseDetailText(AText);
  end
  else
  begin
    FKind := slkSummary;
    ParseSummaryText(AText);
  end;
end;

procedure TFastMMSamplingLog.LoadDetailFromFile(const AFileName: string);
begin
  FDetailRows.Clear;
  FDetailSourceName := AFileName;
  ParseDetailText(ReadTextFile(AFileName));
end;

{Maps the header line onto column indices.  AColumns receives one entry per
 known column name; -1 means the column is absent from this file.}
procedure MapColumns(const AHeaderLine: string; ANames: TStringList;
  var AIndices: array of Integer);
var
  LFields: TStringList;
  i, j: Integer;
begin
  for i := 0 to High(AIndices) do
    AIndices[i] := -1;
  LFields := TStringList.Create;
  try
    SplitCsvLine(AHeaderLine, LFields);
    for i := 0 to LFields.Count - 1 do
    begin
      j := ANames.IndexOf(LowerCase(Trim(LFields[i])));
      if (j >= 0) and (j <= High(AIndices)) then
        AIndices[j] := i;
    end;
  finally
    LFields.Free;
  end;
end;

{Field accessor that tolerates an absent column or a short row.}
function FieldOf(AFields: TStringList; AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < AFields.Count) then
    Result := AFields[AIndex]
  else
    Result := '';
end;

procedure TFastMMSamplingLog.ParseSummaryText(const AText: string);
const
  {The order here defines the meaning of the index array below.}
  CColSampleIndex = 0;
  CColWallClock = 1;
  CColElapsed = 2;
  CColMMUsage = 3;
  CColAllocated = 4;
  CColReserved = 5;
  CColOverhead = 6;
  CColEfficiency = 7;
  CColSmallAlloc = 8;
  CColSmallReserved = 9;
  CColSmallCount = 10;
  CColMediumAlloc = 11;
  CColMediumReserved = 12;
  CColMediumCount = 13;
  CColLargeAlloc = 14;
  CColLargeReserved = 15;
  CColLargeCount = 16;
  CColSmallContention = 17;
  CColMediumContention = 18;
  CColLargeContention = 19;
  CColCount = 20;
var
  LLines, LFields, LNames: TStringList;
  LIndices: array[0..CColCount - 1] of Integer;
  LRow: TFastMMSampleRow;
  i: Integer;
  LLine: string;
begin
  LLines := TStringList.Create;
  LFields := TStringList.Create;
  LNames := TStringList.Create;
  try
    LNames.Add('sample_index');
    LNames.Add('wall_clock');
    LNames.Add('elapsed_ms');
    LNames.Add('mm_usage_bytes');
    LNames.Add('allocated_bytes');
    LNames.Add('reserved_bytes');
    LNames.Add('overhead_bytes');
    LNames.Add('efficiency_pct');
    LNames.Add('small_alloc_bytes');
    LNames.Add('small_reserved_bytes');
    LNames.Add('small_block_count');
    LNames.Add('medium_alloc_bytes');
    LNames.Add('medium_reserved_bytes');
    LNames.Add('medium_block_count');
    LNames.Add('large_alloc_bytes');
    LNames.Add('large_reserved_bytes');
    LNames.Add('large_block_count');
    LNames.Add('small_contention');
    LNames.Add('medium_contention');
    LNames.Add('large_contention');

    LLines.Text := AText;
    if LLines.Count = 0 then
      Exit;

    MapColumns(LLines[0], LNames, LIndices);
    FHasContentionCounts := LIndices[CColSmallContention] >= 0;

    for i := 1 to LLines.Count - 1 do
    begin
      LLine := Trim(LLines[i]);
      if LLine = '' then
        Continue;
      SplitCsvLine(LLine, LFields);
      {A row that carries neither an index nor an elapsed time is not a data
       row (a concatenated second header, for instance).}
      if LFields.Count < 3 then
      begin
        Inc(FMalformedLineCount);
        Continue;
      end;
      if Pos('sample_index', LLine) = 1 then
        Continue;   {a second header, e.g. two runs appended to one file}

      LRow := TFastMMSampleRow.Create;
      LRow.SampleIndex := ParseInt64(FieldOf(LFields, LIndices[CColSampleIndex]));
      LRow.WallClock := Trim(FieldOf(LFields, LIndices[CColWallClock]));
      LRow.ElapsedMilliseconds := ParseInt64(FieldOf(LFields, LIndices[CColElapsed]));
      LRow.MemoryManagerUsageBytes := ParseInt64(FieldOf(LFields, LIndices[CColMMUsage]));
      LRow.AllocatedBytes := ParseInt64(FieldOf(LFields, LIndices[CColAllocated]));
      LRow.ReservedBytes := ParseInt64(FieldOf(LFields, LIndices[CColReserved]));
      LRow.OverheadBytes := ParseInt64(FieldOf(LFields, LIndices[CColOverhead]));
      LRow.EfficiencyPercentage := ParseFloat(FieldOf(LFields, LIndices[CColEfficiency]));
      LRow.SmallAllocatedBytes := ParseInt64(FieldOf(LFields, LIndices[CColSmallAlloc]));
      LRow.SmallReservedBytes := ParseInt64(FieldOf(LFields, LIndices[CColSmallReserved]));
      LRow.SmallBlockCount := ParseInt64(FieldOf(LFields, LIndices[CColSmallCount]));
      LRow.MediumAllocatedBytes := ParseInt64(FieldOf(LFields, LIndices[CColMediumAlloc]));
      LRow.MediumReservedBytes := ParseInt64(FieldOf(LFields, LIndices[CColMediumReserved]));
      LRow.MediumBlockCount := ParseInt64(FieldOf(LFields, LIndices[CColMediumCount]));
      LRow.LargeAllocatedBytes := ParseInt64(FieldOf(LFields, LIndices[CColLargeAlloc]));
      LRow.LargeReservedBytes := ParseInt64(FieldOf(LFields, LIndices[CColLargeReserved]));
      LRow.LargeBlockCount := ParseInt64(FieldOf(LFields, LIndices[CColLargeCount]));
      LRow.SmallContentionCount := ParseInt64(FieldOf(LFields, LIndices[CColSmallContention]));
      LRow.MediumContentionCount := ParseInt64(FieldOf(LFields, LIndices[CColMediumContention]));
      LRow.LargeContentionCount := ParseInt64(FieldOf(LFields, LIndices[CColLargeContention]));
      FRows.Add(LRow);
    end;
  finally
    LNames.Free;
    LFields.Free;
    LLines.Free;
  end;
end;

procedure TFastMMSamplingLog.ParseDetailText(const AText: string);
const
  CColSampleIndex = 0;
  CColElapsed = 1;
  CColBlockSize = 2;
  CColUseableSize = 3;
  CColAllocatedCount = 4;
  CColReservedBytes = 5;
  CColUsedBytes = 6;
  CColEfficiency = 7;
  CColCount = 8;
var
  LLines, LFields, LNames: TStringList;
  LIndices: array[0..CColCount - 1] of Integer;
  LRow: TFastMMSampleDetailRow;
  i: Integer;
  LLine: string;
begin
  LLines := TStringList.Create;
  LFields := TStringList.Create;
  LNames := TStringList.Create;
  try
    LNames.Add('sample_index');
    LNames.Add('elapsed_ms');
    LNames.Add('block_size');
    LNames.Add('useable_size');
    LNames.Add('allocated_count');
    LNames.Add('reserved_bytes');
    LNames.Add('used_bytes');
    LNames.Add('efficiency_pct');

    LLines.Text := AText;
    if LLines.Count = 0 then
      Exit;

    MapColumns(LLines[0], LNames, LIndices);

    for i := 1 to LLines.Count - 1 do
    begin
      LLine := Trim(LLines[i]);
      if LLine = '' then
        Continue;
      if Pos('sample_index', LLine) = 1 then
        Continue;
      SplitCsvLine(LLine, LFields);
      if LFields.Count < 3 then
      begin
        Inc(FMalformedLineCount);
        Continue;
      end;

      LRow := TFastMMSampleDetailRow.Create;
      LRow.SampleIndex := ParseInt64(FieldOf(LFields, LIndices[CColSampleIndex]));
      LRow.ElapsedMilliseconds := ParseInt64(FieldOf(LFields, LIndices[CColElapsed]));
      LRow.BlockSize := ParseInt64(FieldOf(LFields, LIndices[CColBlockSize]));
      LRow.UseableSize := ParseInt64(FieldOf(LFields, LIndices[CColUseableSize]));
      LRow.AllocatedCount := ParseInt64(FieldOf(LFields, LIndices[CColAllocatedCount]));
      LRow.ReservedBytes := ParseInt64(FieldOf(LFields, LIndices[CColReservedBytes]));
      LRow.UsedBytes := ParseInt64(FieldOf(LFields, LIndices[CColUsedBytes]));
      LRow.EfficiencyPercentage := ParseFloat(FieldOf(LFields, LIndices[CColEfficiency]));
      FDetailRows.Add(LRow);
    end;
  finally
    LNames.Free;
    LFields.Free;
    LLines.Free;
  end;
end;

function TFastMMSamplingLog.DurationMilliseconds: Int64;
begin
  if FRows.Count = 0 then
    Result := 0
  else
    Result := GetRow(FRows.Count - 1).ElapsedMilliseconds - GetRow(0).ElapsedMilliseconds;
end;

function TFastMMSamplingLog.MaxOf(ASeries: TFastMMSampleSeries): Double;
var
  i: Integer;
  LValue: Double;
begin
  Result := 0;
  for i := 0 to FRows.Count - 1 do
  begin
    LValue := GetRow(i).Value(ASeries);
    if (i = 0) or (LValue > Result) then
      Result := LValue;
  end;
end;

function TFastMMSamplingLog.MinOf(ASeries: TFastMMSampleSeries): Double;
var
  i: Integer;
  LValue: Double;
begin
  Result := 0;
  for i := 0 to FRows.Count - 1 do
  begin
    LValue := GetRow(i).Value(ASeries);
    if (i = 0) or (LValue < Result) then
      Result := LValue;
  end;
end;

function TFastMMSamplingLog.IndexOfMax(ASeries: TFastMMSampleSeries): Integer;
var
  i: Integer;
  LValue, LBest: Double;
begin
  Result := -1;
  LBest := 0;
  for i := 0 to FRows.Count - 1 do
  begin
    LValue := GetRow(i).Value(ASeries);
    if (Result < 0) or (LValue > LBest) then
    begin
      LBest := LValue;
      Result := i;
    end;
  end;
end;

function TFastMMSamplingLog.DetailBlockSizes: TStringList;
var
  i: Integer;
  LSize: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  {Sorted TStringList compares as text, so left pad to a fixed width to keep the
   numeric order, then strip the padding again below.}
  for i := 0 to FDetailRows.Count - 1 do
  begin
    LSize := IntToStr(GetDetailRow(i).BlockSize);
    while Length(LSize) < 10 do
      LSize := '0' + LSize;
    Result.Add(LSize);
  end;
  Result.Sorted := False;
  for i := 0 to Result.Count - 1 do
    Result[i] := IntToStr(ParseInt64(Result[i]));
end;

function TFastMMSamplingLog.Describe: string;
begin
  case FKind of
    slkSummary:
      Result := Format('Sampling log - %d sample(s), %d ms', [FRows.Count, DurationMilliseconds]);
    slkDetail:
      Result := Format('Sampling detail log - %d row(s)', [FDetailRows.Count]);
  else
    Result := 'Empty sampling log';
  end;
end;

end.
