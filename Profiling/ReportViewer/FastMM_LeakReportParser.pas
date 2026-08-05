(*

  FastMM_LeakReportParser
  -----------------------

  A VCL-free parser that turns FastMM5 text reports into a navigable object
  model.  It understands the two textual formats that FastMM5.pas produces:

    1. The event-log style memory-leak report (the shutdown leak report and
       anything written through FastMM_LogToFileEvents).  Each entry is wrapped
       by a header line of the form
         --------------------------------YYYY-MM-DD HH:NN:SS--------------------------------
       Leak-detail entries follow FastMM_MemoryLeakDetailMessage_DebugBlock /
       _NormalBlock, and a trailing summary entry follows
       FastMM_MemoryLeakSummaryMessage_* (the "<size>: <count> x <Type>" lines).

    2. The state capture written by FastMM_LogStateToFile:
         FastMM State Capture:
         ---------------------
         Timestamp: ...
         Usage Summary: nK Allocated / nK Overhead / n% Efficiency
         Usage Detail:  {total} bytes: {Class} x {count} ({avg} bytes avg.)

  Stack-trace lines (produced by the FullDebugMode support DLL's LogStackTrace)
  have the shape
         <hexaddress>[SourceFile.pas][UnitName][Routine][LineNumber]
  where empty fields are omitted.  The frame parser is heuristic so it also
  copes gracefully with madExcept / EurekaLog style traces.

  Design constraints (matching the rest of the D7/D2009 port):
    - No generics, no anonymous methods, no Exit(Value).
    - inline directives guarded with {$IF CompilerVersion >= 18}.
    - Collections via Contnrs.TObjectList.
    - Compiles clean on Delphi 7, Delphi 10 Seattle and Delphi 13.1.

  This unit lives under FastMM5\Profiling\LeakReportViewer\ so it stays neutral
  with respect to upstream merges.

*)

unit FastMM_LeakReportParser;

interface

uses
  Classes, SysUtils, Contnrs;

type
  TFastMMReportKind = (rkUnknown, rkLeakReport, rkStateCapture);

  {A single stack-trace frame.}
  TFastMMStackFrame = class(TObject)
  public
    Address: string;      {Return address in hex, e.g. '0040BC53' (may be empty)}
    SourceFile: string;   {e.g. 'MyUnit.pas' (empty when not available)}
    UnitName: string;     {e.g. 'MyUnit' (empty when not available)}
    Routine: string;      {e.g. 'TMyClass.DoWork' (empty when not available)}
    LineNumber: Integer;  {0 when not available}
    ModuleName: string;   {e.g. 'MyApp.exe' - madExcept traces carry this}
    RawText: string;      {The original, unparsed trace line}
    {True when the frame can be resolved to a source line.  madExcept reports a
     unit name rather than a file name, so a unit plus a line qualifies too.}
    function HasSourceLocation: Boolean;
    {The file name to look for when jumping to source:  the reported source
     file if there is one, otherwise derived from the unit name.}
    function SourceFileCandidate: string;
    function DisplayText: string;
  end;

  {A leaked block (one leak-detail entry in the event-log report).}
  TFastMMLeakBlock = class(TObject)
  private
    FAllocStack: TObjectList; {of TFastMMStackFrame}
    FFreeStack: TObjectList;  {of TFastMMStackFrame}
  public
    BlockSize: Int64;         {Usable block size in bytes}
    ContentType: string;      (*Class name / content type, token {8}*)
    AllocatedByThread: string;
    FreedByThread: string;
    AllocationDate: string;
    AllocationTime: string;
    AllocationNumber: string;
    DumpAddress: string;      {Pointer address from the memory-dump line}
    HexDump: string;          {The raw hex+ascii dump block, verbatim}
    RawEntry: string;         {The full original entry text}
    constructor Create;
    destructor Destroy; override;
    property AllocStack: TObjectList read FAllocStack;
    property FreeStack: TObjectList read FFreeStack;
  end;

  {One "<count> x <ContentType>" pair inside a summary line.}
  TFastMMSummaryPair = class(TObject)
  public
    Count: Int64;
    ContentType: string;
  end;

  (*One summary line: a block size plus the pairs of that size, token {14}.*)
  TFastMMSummaryLine = class(TObject)
  private
    FPairs: TObjectList; {of TFastMMSummaryPair}
  public
    {The size this line groups.  For a FastMM4 size-class range this is the
     upper bound; SizeText keeps the label as it was written.}
    BlockSize: Int64;
    SizeText: string;
    constructor Create;
    destructor Destroy; override;
    function TotalCount: Int64;
    property Pairs: TObjectList read FPairs;
  end;

  {A "Usage Detail" entry from a state capture (also reused as a generic
   per-class aggregate row).}
  TFastMMStateEntry = class(TObject)
  public
    TotalBytes: Int64;
    ContentType: string;
    InstanceCount: Int64;
    AverageBytes: Int64;
  end;

  {A grouping of leaked blocks (or state entries) by content type, used to
   drive the tree view.}
  TFastMMGroup = class(TObject)
  private
    FBlocks: TList; {references to TFastMMLeakBlock, not owned}
  public
    ContentType: string;
    TotalBytes: Int64;
    InstanceCount: Int64;
    constructor Create;
    destructor Destroy; override;
    property Blocks: TList read FBlocks;
  end;

  TFastMMGroupSortOrder = (gsTotalBytesDesc, gsInstanceCountDesc, gsContentTypeAsc);

  {The parsed report.}
  TFastMMLeakReport = class(TObject)
  private
    FKind: TFastMMReportKind;
    FSourceFileName: string;
    FRawText: string;

    {Leak-report data.}
    FBlocks: TObjectList;       {of TFastMMLeakBlock (owned)}
    FSummaryLines: TObjectList; {of TFastMMSummaryLine (owned)}
    FEventLogPath: string;      (*token {16}, if present*)

    {State-capture data.}
    FTimestamp: string;
    FAllocatedKB: Int64;
    FOverheadKB: Int64;
    FEfficiencyPercent: Integer;
    FStateEntries: TObjectList; {of TFastMMStateEntry (owned)}

    FGroups: TObjectList;       {of TFastMMGroup (owned), rebuilt on demand}

    procedure Clear;
    procedure ParseLeakReport(ALines: TStrings);
    procedure ParseStateCapture(ALines: TStrings);
    procedure ParseLeakDetail(const AEntry: string);
    procedure ParseSummaryEntry(const AEntry: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure LoadFromFile(const AFileName: string);
    procedure LoadFromString(const AText: string);

    {Groups leaked blocks / state entries by content type and returns them in
     the requested order.  The returned list is owned by this report; callers
     must not free it.}
    function BuildGroups(ASortOrder: TFastMMGroupSortOrder): TObjectList;

    {Aggregate totals across the whole report.}
    function TotalLeakedBytes: Int64;
    function TotalLeakedCount: Int64;

    {A short human-readable one-liner describing this report (kind, timestamp,
     totals) - used to label reports in a multi-report file.}
    function Describe: string;

    property Kind: TFastMMReportKind read FKind;
    property SourceFileName: string read FSourceFileName write FSourceFileName;
    property RawText: string read FRawText;

    property Blocks: TObjectList read FBlocks;
    property SummaryLines: TObjectList read FSummaryLines;
    property EventLogPath: string read FEventLogPath;

    property Timestamp: string read FTimestamp;
    property AllocatedKB: Int64 read FAllocatedKB;
    property OverheadKB: Int64 read FOverheadKB;
    property EfficiencyPercent: Integer read FEfficiencyPercent;
    property StateEntries: TObjectList read FStateEntries;
  end;

  {A whole report *file* may contain more than one report:  FastMM appends to
   the event log (one leak-check run per process launch) and
   FastMM_LogStateToFile can append captures when called with
   ATruncateFile = False.  TFastMMReportSet splits such a file into its
   individual reports and parses each one independently.}
  TFastMMReportSet = class(TObject)
  private
    FReports: TObjectList; {of TFastMMLeakReport (owned)}
    FSourceFileName: string;
    function GetReport(AIndex: Integer): TFastMMLeakReport;
  public
    constructor Create;
    destructor Destroy; override;

    procedure LoadFromFile(const AFileName: string);
    procedure LoadFromString(const AText, ASourceFileName: string);

    function Count: Integer;
    property Reports[AIndex: Integer]: TFastMMLeakReport read GetReport; default;
    property SourceFileName: string read FSourceFileName;
  end;

{Splits the text of a report file into one string per contained report.  Each
 segment is suitable for TFastMMLeakReport.LoadFromString.  Exposed for tests.}
procedure FastMMSplitReports(const AText: string; ASegments: TStrings);

{Low-level helpers, exposed for the unit test.}
function FastMMDecodeReportBytes(const ABytes: TStream): string;
function FastMMParseStackFrame(const ALine: string): TFastMMStackFrame;
function FastMMExtractFirstInteger(const AText: string): Int64;

{True when ABuffer holds a well-formed UTF-8 byte sequence (pure ASCII counts).
 Used to tell a UTF-8 report from a legacy ANSI one when there is no BOM.}
function FastMMLooksLikeUtf8(ABuffer: PAnsiChar; ALength: Integer): Boolean;

implementation

const
  CReportHeaderDashes = '----------------'; {A run this long only appears in headers/rules}

{--------------------------------------------------------------------------}
{ Small string utilities (deliberately D7-friendly)                         }
{--------------------------------------------------------------------------}

function CharIsDigit(AChar: Char): Boolean;
{$IF CompilerVersion >= 18}inline;{$IFEND}
begin
  Result := (AChar >= '0') and (AChar <= '9');
end;

function CharIsHex(AChar: Char): Boolean;
{$IF CompilerVersion >= 18}inline;{$IFEND}
begin
  Result := ((AChar >= '0') and (AChar <= '9')) or
            ((AChar >= 'A') and (AChar <= 'F')) or
            ((AChar >= 'a') and (AChar <= 'f'));
end;

{Returns the first run of digits in AText as an integer (ignoring thousands
 separators like ',' or '.').  Returns 0 when no digits are present.}
function FastMMExtractFirstInteger(const AText: string): Int64;
var
  i, LLen: Integer;
  LStarted: Boolean;
  LDigit: Integer;
begin
  Result := 0;
  LStarted := False;
  LLen := Length(AText);
  i := 1;
  while i <= LLen do
  begin
    if CharIsDigit(AText[i]) then
    begin
      LStarted := True;
      LDigit := Ord(AText[i]) - Ord('0');
      Result := Result * 10 + LDigit;
    end
    else if LStarted and ((AText[i] = ',') or (AText[i] = '.')) then
    begin
      {Thousands separator inside the number - keep going.}
    end
    else if LStarted then
      Break;
    Inc(i);
  end;
end;

{Returns the substring of ALine after the first occurrence of AMarker, trimmed.
 Returns '' when the marker is not found.}
function AfterMarker(const ALine, AMarker: string): string;
var
  P: Integer;
begin
  P := Pos(AMarker, ALine);
  if P > 0 then
    Result := Trim(Copy(ALine, P + Length(AMarker), MaxInt))
  else
    Result := '';
end;

function StartsWithText(const AText, APrefix: string): Boolean;
begin
  Result := (Length(AText) >= Length(APrefix)) and
    (AnsiStrLIComp(PChar(AText), PChar(APrefix), Length(APrefix)) = 0);
end;

function EndsWithTextCI(const AText, ASuffix: string): Boolean;
var
  LStart: Integer;
begin
  LStart := Length(AText) - Length(ASuffix) + 1;
  if LStart < 1 then
  begin
    Result := False;
    Exit;
  end;
  Result := AnsiStrLIComp(PChar(AText) + (LStart - 1), PChar(ASuffix), Length(ASuffix)) = 0;
end;

{True when the whole (trimmed) string consists of decimal digits.}
function IsAllDigits(const AText: string): Boolean;
var
  i: Integer;
begin
  Result := AText <> '';
  for i := 1 to Length(AText) do
    if not CharIsDigit(AText[i]) then
    begin
      Result := False;
      Exit;
    end;
end;

{True for the size label that introduces a leak-summary line.  FastMM5 writes a
 single size ("48"), FastMM4 a size-class range ("21 - 36 bytes").  Anything
 else before the colon is prose (the summary headline, a "Note:" line, ...).}
function IsSummarySizeLabel(const AText: string): Boolean;
var
  LWork: string;
  i: Integer;
  LSeenDigit: Boolean;
begin
  Result := False;
  LWork := Trim(AText);
  if EndsWithTextCI(LWork, 'bytes') then
    LWork := Trim(Copy(LWork, 1, Length(LWork) - Length('bytes')));
  if LWork = '' then
    Exit;
  {Must start with a digit, so prose can never qualify.}
  if not CharIsDigit(LWork[1]) then
    Exit;
  LSeenDigit := False;
  for i := 1 to Length(LWork) do
  begin
    if CharIsDigit(LWork[i]) then
      LSeenDigit := True
    else if (LWork[i] <> ' ') and (LWork[i] <> '-') then
      Exit; {Result is still False}
  end;
  Result := LSeenDigit;
end;

{Returns the last run of digits in AText as an integer.  For a FastMM4 size
 range ("21 - 36 bytes") that is the upper bound of the size class, which is the
 figure the block sizes in that bin are reported against.}
function ExtractLastInteger(const AText: string): Int64;
var
  i, LEnd: Integer;
begin
  Result := 0;
  i := Length(AText);
  {Skip trailing non-digits.}
  while (i >= 1) and (not CharIsDigit(AText[i])) do
    Dec(i);
  if i < 1 then
    Exit;
  LEnd := i;
  while (i >= 1) and CharIsDigit(AText[i]) do
    Dec(i);
  Result := FastMMExtractFirstInteger(Copy(AText, i + 1, LEnd - i));
end;

{--------------------------------------------------------------------------}
{ Encoding detection / decoding                                             }
{--------------------------------------------------------------------------}

{True when the buffer is a well-formed UTF-8 sequence.  A buffer without any
 byte >= $80 is plain ASCII and therefore trivially valid UTF-8 as well.

 This is a structural check (lead byte announces N continuation bytes, each of
 which must be $80..$BF), plus rejection of the lead bytes that can never be
 legal ($C0/$C1 are always overlong, anything above $F4 is beyond U+10FFFF).
 It is deliberately not a full canonical-form validator: the only job here is
 to tell a UTF-8 report apart from a legacy ANSI one, and real ANSI text (for
 example German umlauts in Latin-1, or the raw bytes inside a memory dump)
 practically never satisfies even the structural rules.}
{How many continuation bytes the given UTF-8 lead byte announces, or -1 when it
 cannot be a valid lead byte at all ($80..$BF is a stray continuation byte,
 $C0/$C1 would always be an overlong encoding, above $F4 is beyond U+10FFFF).}
function Utf8TrailByteCount(ALeadByte: Byte): Integer;
begin
  if (ALeadByte and $E0) = $C0 then
  begin
    if ALeadByte < $C2 then
      Result := -1
    else
      Result := 1;
  end
  else if (ALeadByte and $F0) = $E0 then
    Result := 2
  else if (ALeadByte and $F8) = $F0 then
  begin
    if ALeadByte > $F4 then
      Result := -1
    else
      Result := 3;
  end
  else
    Result := -1;
end;

function FastMMLooksLikeUtf8(ABuffer: PAnsiChar; ALength: Integer): Boolean;
var
  i, j, LTrailCount: Integer;
  LByte: Byte;
begin
  Result := True;
  i := 0;
  while i < ALength do
  begin
    LByte := Byte(ABuffer[i]);

    if LByte < $80 then
    begin
      {Plain ASCII.}
      Inc(i);
      Continue;
    end;

    LTrailCount := Utf8TrailByteCount(LByte);
    if LTrailCount < 0 then
    begin
      Result := False;
      Exit;
    end;

    {The announced continuation bytes must exist and must all be $80..$BF.}
    if i + LTrailCount >= ALength then
    begin
      Result := False;
      Exit;
    end;
    for j := 1 to LTrailCount do
    begin
      if (Byte(ABuffer[i + j]) and $C0) <> $80 then
      begin
        Result := False;
        Exit;
      end;
    end;

    Inc(i, LTrailCount + 1);
  end;
end;

{Reads the whole stream and decodes it to a native string.  Handles UTF-8
 (with or without BOM - the FastMM5 default is teUTF8, no BOM), UTF-16LE and
 UTF-16BE (each with or without BOM), and - for reports written by FastMM4 or
 by any build using a legacy single-byte encoder - plain ANSI.

 Without a BOM the payload is only treated as UTF-8 when it actually is
 well-formed UTF-8; otherwise it is read as ANSI.  That matters because
 Utf8ToAnsi (and UTF8ToString) return an empty string for malformed input,
 which previously made every ANSI report load as blank.}
function FastMMDecodeReportBytes(const ABytes: TStream): string;
var
  LSize: Integer;
  LBuf: array of Byte;
  LStart: Integer;
  LIsUtf16LE, LIsUtf16BE, LHasUtf8BOM, LIsUtf8: Boolean;
  LWide: WideString;
  LWideLen, i: Integer;
  LRawUtf8: AnsiString;
  LRawAnsi: AnsiString;
begin
  Result := '';
  ABytes.Position := 0;
  LSize := ABytes.Size;
  if LSize <= 0 then
    Exit;
  SetLength(LBuf, LSize);
  ABytes.ReadBuffer(LBuf[0], LSize);

  LStart := 0;
  LIsUtf16LE := False;
  LIsUtf16BE := False;
  LHasUtf8BOM := False;

  {BOM detection.}
  if (LSize >= 3) and (LBuf[0] = $EF) and (LBuf[1] = $BB) and (LBuf[2] = $BF) then
  begin
    LHasUtf8BOM := True;
    LStart := 3; {UTF-8 with BOM}
  end
  else if (LSize >= 2) and (LBuf[0] = $FF) and (LBuf[1] = $FE) then
  begin
    LIsUtf16LE := True;
    LStart := 2;
  end
  else if (LSize >= 2) and (LBuf[0] = $FE) and (LBuf[1] = $FF) then
  begin
    LIsUtf16BE := True;
    LStart := 2;
  end;

  if LIsUtf16LE or LIsUtf16BE then
  begin
    LWideLen := (LSize - LStart) div 2;
    SetLength(LWide, LWideLen);
    for i := 0 to LWideLen - 1 do
    begin
      if LIsUtf16LE then
        LWide[i + 1] := WideChar(LBuf[LStart + i * 2] or (LBuf[LStart + i * 2 + 1] shl 8))
      else
        LWide[i + 1] := WideChar(LBuf[LStart + i * 2 + 1] or (LBuf[LStart + i * 2] shl 8));
    end;
    {$IFDEF UNICODE}
    Result := LWide;
    {$ELSE}
    Result := LWide; {WideString -> AnsiString via the RTL}
    {$ENDIF}
  end
  else
  begin
    {No UTF-16 BOM:  either UTF-8 (with the BOM already skipped, or bare) or a
     legacy ANSI report.  A BOM settles it; otherwise inspect the bytes.}
    if LHasUtf8BOM or (LSize - LStart <= 0) then
      LIsUtf8 := True
    else
      LIsUtf8 := FastMMLooksLikeUtf8(PAnsiChar(@LBuf[LStart]), LSize - LStart);

    if LIsUtf8 then
    begin
      SetLength(LRawUtf8, LSize - LStart);
      if LSize - LStart > 0 then
        Move(LBuf[LStart], LRawUtf8[1], LSize - LStart);
      {$IFDEF UNICODE}
      Result := UTF8ToString(LRawUtf8);
      {$ELSE}
      Result := Utf8ToAnsi(LRawUtf8);
      {$ENDIF}
    end
    else
    begin
      {ANSI:  the bytes are already single-byte characters.}
      SetLength(LRawAnsi, LSize - LStart);
      if LSize - LStart > 0 then
        Move(LBuf[LStart], LRawAnsi[1], LSize - LStart);
      {$IFDEF UNICODE}
      {Assigning AnsiString to string converts via the default ANSI codepage.}
      Result := string(LRawAnsi);
      {$ELSE}
      Result := LRawAnsi;
      {$ENDIF}
    end;
  end;
end;

{--------------------------------------------------------------------------}
{ TFastMMStackFrame                                                         }
{--------------------------------------------------------------------------}

function TFastMMStackFrame.HasSourceLocation: Boolean;
begin
  Result := (LineNumber > 0) and ((SourceFile <> '') or (UnitName <> ''));
end;

function TFastMMStackFrame.SourceFileCandidate: string;
begin
  if SourceFile <> '' then
    Result := SourceFile
  else if UnitName <> '' then
    {madExcept reports the unit, not the file.  The overwhelmingly common case
     is that the unit lives in a like-named .pas.}
    Result := UnitName + '.pas'
  else
    Result := '';
end;

function TFastMMStackFrame.DisplayText: string;
begin
  Result := Routine;
  if Result = '' then
    Result := UnitName;
  if Result = '' then
    Result := Address;
  if HasSourceLocation then
    Result := Result + '  (' + SourceFileCandidate + ' line ' + IntToStr(LineNumber) + ')';
end;

{True for a token like '+1a' / '+13' - madExcept's relative address and
 relative line offsets.}
function IsPlusOffsetToken(const AToken: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (Length(AToken) < 2) or (AToken[1] <> '+') then
    Exit;
  for i := 2 to Length(AToken) do
    if not CharIsHex(AToken[i]) then
      Exit;
  Result := True;
end;

{True for a token that looks like a binary module - 'MyApp.exe', 'KERNEL32.DLL'.
 The short extension is what separates it from a dotted unit name such as
 'System.Classes'.}
function IsModuleToken(const AToken: string): Boolean;
var
  LDot, i: Integer;
  LExtLen: Integer;
begin
  Result := False;
  LDot := 0;
  for i := Length(AToken) downto 1 do
    if AToken[i] = '.' then
    begin
      LDot := i;
      Break;
    end;
  if LDot = 0 then
    Exit;
  LExtLen := Length(AToken) - LDot;
  if (LExtLen < 2) or (LExtLen > 4) then
    Exit;
  for i := LDot + 1 to Length(AToken) do
    if not (((AToken[i] >= 'a') and (AToken[i] <= 'z')) or
            ((AToken[i] >= 'A') and (AToken[i] <= 'Z')) or
            CharIsDigit(AToken[i])) then
      Exit;
  Result := True;
end;

{Splits AText on runs of white space.  Returns the number of tokens stored.}
function SplitTokens(const AText: string; var ATokens: array of string): Integer;
var
  i, LLen, LStart: Integer;
begin
  Result := 0;
  LLen := Length(AText);
  i := 1;
  while (i <= LLen) and (Result <= High(ATokens)) do
  begin
    while (i <= LLen) and (AText[i] = ' ') do
      Inc(i);
    if i > LLen then
      Break;
    LStart := i;
    while (i <= LLen) and (AText[i] <> ' ') do
      Inc(i);
    ATokens[Result] := Copy(AText, LStart, i - LStart);
    Inc(Result);
  end;
end;

{Parses the column layout produced by a debug DLL built against madExcept
 (madStackTrace.FastMM_LogStackTrace).  Unlike the JCL default there are no
 brackets - the fields are space padded columns whose widths are recomputed for
 every trace, so the layout has to be recovered from the tokens:

   0041f412 +1a MadLeakGen.exe FastMM5    9345  +4 FastMM_DebugGetMem
   00406c08 +04 MadLeakGen.exe System              @GetMem
   76d05d47 +17 KERNEL32.DLL                       BaseThreadInitThunk
   <address> <+relAddr> <module> [unit] [line] [+relLine] <function>

 The function name is always last; walking backwards from it picks up the
 optional relative-line and line columns, and whatever remains between the
 module and those is the unit.  Returns False when ATextAfterAddress does not
 fit the shape, so the caller can fall back.}
function ParseMadExceptFrame(const ATextAfterAddress: string;
  AFrame: TFastMMStackFrame): Boolean;
var
  LTokens: array[0..15] of string;
  LCount, LFirst, LLast: Integer;
  LHasOffset, LHasModule: Boolean;
begin
  Result := False;
  LCount := SplitTokens(ATextAfterAddress, LTokens);
  if LCount < 1 then
    Exit;

  LFirst := 0;
  {Relative address offset - madExcept is asked for these by the debug DLL.}
  LHasOffset := IsPlusOffsetToken(LTokens[LFirst]);
  if LHasOffset then
    Inc(LFirst);
  if LFirst >= LCount then
    Exit;

  {Module name.}
  LHasModule := IsModuleToken(LTokens[LFirst]);
  if LHasModule then
  begin
    AFrame.ModuleName := LTokens[LFirst];
    Inc(LFirst);
  end;
  if LFirst >= LCount then
    Exit;

  {Require at least one of the two hallmarks, otherwise this is just prose that
   happens to follow an address and must be left to the caller's fallback.}
  if not (LHasOffset or LHasModule) then
    Exit;

  {The last token is the routine.}
  LLast := LCount - 1;
  AFrame.Routine := LTokens[LLast];
  Dec(LLast);

  {Optional relative line offset, then the line number.}
  if (LLast >= LFirst) and IsPlusOffsetToken(LTokens[LLast]) then
    Dec(LLast);
  if (LLast >= LFirst) and IsAllDigits(LTokens[LLast]) then
  begin
    AFrame.LineNumber := StrToIntDef(LTokens[LLast], 0);
    Dec(LLast);
  end;

  {Anything still between the module and the line columns is the unit.}
  if LLast >= LFirst then
    AFrame.UnitName := LTokens[LFirst];

  {Only accept the line if it actually yielded something identifiable.}
  Result := (AFrame.Routine <> '') or (AFrame.UnitName <> '');
end;

{True when the field carries a Pascal source file name.}
function LooksLikeSourceFile(const AField: string): Boolean;
begin
  Result := EndsWithTextCI(AField, '.pas') or EndsWithTextCI(AField, '.inc') or
            EndsWithTextCI(AField, '.dpr') or EndsWithTextCI(AField, '.pp');
end;

{Parses one stack-trace line into a frame.  The line looks like
   0040BC53[MyUnit.pas][MyUnit][TMyClass.DoWork][123]      (FastMM5)
   00900E0C [uRegelung.pas][uRegelung][SomeRoutine][1084]  (FastMM4 - note the
                                                            space, and that
                                                            fields may be a
                                                            module name only)
 Fields are emitted in the fixed order [Source][Unit][Proc][Line] with empty
 ones omitted; the numeric field is the line number and the rest are assigned
 according to how many there are (see the case statement below).  Anything not
 recognised is still preserved in RawText.}
function FastMMParseStackFrame(const ALine: string): TFastMMStackFrame;
var
  LTrim: string;
  i, LLen: Integer;
  LDepth: Integer;
  LField: string;
  LFieldStart: Integer;
  LTextFields: array[0..3] of string;
  LTextFieldCount: Integer;
  LAfterAddress: string;
begin
  Result := TFastMMStackFrame.Create;
  Result.RawText := ALine;
  Result.LineNumber := 0;

  LTrim := Trim(ALine);
  LLen := Length(LTrim);
  if LLen = 0 then
    Exit;

  i := 1;
  LTextFieldCount := 0;

  {Leading hex address (before the first bracket).}
  LFieldStart := i;
  while (i <= LLen) and CharIsHex(LTrim[i]) do
    Inc(i);
  if i > LFieldStart then
    Result.Address := Copy(LTrim, LFieldStart, i - LFieldStart);

  {Everything after the address, kept for the fallback below.}
  LAfterAddress := Trim(Copy(LTrim, i, MaxInt));

  {Walk the bracketed fields and classify each.}
  while i <= LLen do
  begin
    if LTrim[i] = '[' then
    begin
      LDepth := 1;
      Inc(i);
      LFieldStart := i;
      while (i <= LLen) and (LDepth > 0) do
      begin
        if LTrim[i] = '[' then
          Inc(LDepth)
        else if LTrim[i] = ']' then
        begin
          Dec(LDepth);
          if LDepth = 0 then
            Break;
        end;
        Inc(i);
      end;
      LField := Copy(LTrim, LFieldStart, i - LFieldStart);
      if i <= LLen then
        Inc(i); {skip closing ']'}

      LField := Trim(LField);
      if LField <> '' then
      begin
        if IsAllDigits(LField) then
          Result.LineNumber := StrToIntDef(LField, 0)
        else
        begin
          {Collect the non-numeric fields; they are classified below, once their
           total count is known.}
          if LTextFieldCount <= High(LTextFields) then
          begin
            LTextFields[LTextFieldCount] := LField;
            Inc(LTextFieldCount);
          end
          else
            {More fields than expected - do not lose them.}
            LTextFields[High(LTextFields)] :=
              LTextFields[High(LTextFields)] + ' / ' + LField;
        end;
      end;
    end
    else
      Inc(i);
  end;

  {The trace writers (the FullDebugMode DLL, and FastMM4's madExcept/JCL based
   equivalents) emit the fields in the fixed order
     [SourceName][UnitName][ProcedureName][LineNumber]
   and simply omit the ones they have no value for.  So the meaning of a field
   follows from how many there are, not from what it looks like:

     3 or more : source, unit, routine   e.g. [Forms][Forms][TCustomForm.DoShow]
     2         : unit, routine           (source unknown)
     1         : routine                 e.g. [TranslateMessage]

   Note that SourceName is not always a file name - when no source file is
   known it can be a plain module name - which is why the count decides rather
   than a ".pas" test.}
  case LTextFieldCount of
    0:
      {No bracketed fields at all.  Either the line carries nothing but an
       address, or the trace was produced by one of the alternative back-ends
       the debug DLL supports (madExcept, EurekaLog, the MacOS map-file code)
       or by an application-supplied FastMM_ConvertStackTraceToText, none of
       which use the bracket layout.  Try the madExcept column layout first
       (only meaningful when the line actually started with an address);
       failing that show the raw text rather than leaving the row blank.}
      if (Result.Address = '') or (not ParseMadExceptFrame(LAfterAddress, Result)) then
        Result.Routine := LAfterAddress;
    1:
      begin
        if LooksLikeSourceFile(LTextFields[0]) then
          Result.SourceFile := LTextFields[0]
        else
          Result.Routine := LTextFields[0];
      end;
    2:
      begin
        if LooksLikeSourceFile(LTextFields[0]) then
          Result.SourceFile := LTextFields[0]
        else
          Result.UnitName := LTextFields[0];
        Result.Routine := LTextFields[1];
      end;
  else
    Result.SourceFile := LTextFields[0];
    Result.UnitName := LTextFields[1];
    Result.Routine := LTextFields[2];
  end;
end;

{--------------------------------------------------------------------------}
{ TFastMMLeakBlock                                                          }
{--------------------------------------------------------------------------}

constructor TFastMMLeakBlock.Create;
begin
  inherited Create;
  FAllocStack := TObjectList.Create(True);
  FFreeStack := TObjectList.Create(True);
end;

destructor TFastMMLeakBlock.Destroy;
begin
  FAllocStack.Free;
  FFreeStack.Free;
  inherited Destroy;
end;

{--------------------------------------------------------------------------}
{ TFastMMSummaryLine                                                        }
{--------------------------------------------------------------------------}

constructor TFastMMSummaryLine.Create;
begin
  inherited Create;
  FPairs := TObjectList.Create(True);
end;

destructor TFastMMSummaryLine.Destroy;
begin
  FPairs.Free;
  inherited Destroy;
end;

function TFastMMSummaryLine.TotalCount: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FPairs.Count - 1 do
    Inc(Result, TFastMMSummaryPair(FPairs[i]).Count);
end;

{--------------------------------------------------------------------------}
{ TFastMMGroup                                                              }
{--------------------------------------------------------------------------}

constructor TFastMMGroup.Create;
begin
  inherited Create;
  FBlocks := TList.Create;
end;

destructor TFastMMGroup.Destroy;
begin
  FBlocks.Free; {references only - do not free the blocks themselves}
  inherited Destroy;
end;

{--------------------------------------------------------------------------}
{ TFastMMLeakReport                                                         }
{--------------------------------------------------------------------------}

constructor TFastMMLeakReport.Create;
begin
  inherited Create;
  FBlocks := TObjectList.Create(True);
  FSummaryLines := TObjectList.Create(True);
  FStateEntries := TObjectList.Create(True);
  FGroups := TObjectList.Create(True);
  FKind := rkUnknown;
end;

destructor TFastMMLeakReport.Destroy;
begin
  FGroups.Free;
  FStateEntries.Free;
  FSummaryLines.Free;
  FBlocks.Free;
  inherited Destroy;
end;

procedure TFastMMLeakReport.Clear;
begin
  FBlocks.Clear;
  FSummaryLines.Clear;
  FStateEntries.Clear;
  FGroups.Clear;
  FKind := rkUnknown;
  FEventLogPath := '';
  FTimestamp := '';
  FAllocatedKB := 0;
  FOverheadKB := 0;
  FEfficiencyPercent := 0;
end;

procedure TFastMMLeakReport.LoadFromFile(const AFileName: string);
var
  LStream: TFileStream;
  LText: string;
begin
  LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    LText := FastMMDecodeReportBytes(LStream);
  finally
    LStream.Free;
  end;
  FSourceFileName := AFileName;
  LoadFromString(LText);
end;

{Splits text into lines on CRLF / LF / CR without the surprises of
 TStringList.Text on some compilers.}
procedure SplitLines(const AText: string; ALines: TStrings);
var
  i, LLen, LStart: Integer;
  LCh: Char;
begin
  ALines.BeginUpdate;
  try
    ALines.Clear;
    LLen := Length(AText);
    LStart := 1;
    i := 1;
    while i <= LLen do
    begin
      LCh := AText[i];
      if (LCh = #10) or (LCh = #13) then
      begin
        ALines.Add(Copy(AText, LStart, i - LStart));
        {Swallow a CRLF pair as a single break.}
        if (LCh = #13) and (i < LLen) and (AText[i + 1] = #10) then
          Inc(i);
        LStart := i + 1;
      end;
      Inc(i);
    end;
    if LStart <= LLen + 1 then
      ALines.Add(Copy(AText, LStart, LLen - LStart + 1));
  finally
    ALines.EndUpdate;
  end;
end;

procedure TFastMMLeakReport.LoadFromString(const AText: string);
var
  LLines: TStringList;
begin
  Clear;
  FRawText := AText;

  if Pos('FastMM State Capture', AText) > 0 then
    FKind := rkStateCapture
  else if (Pos('has been leaked', AText) > 0) or
          (Pos('has leaked memory', AText) > 0) then
    FKind := rkLeakReport
  else
    FKind := rkUnknown;

  LLines := TStringList.Create;
  try
    SplitLines(AText, LLines);
    case FKind of
      rkStateCapture: ParseStateCapture(LLines);
      rkLeakReport:   ParseLeakReport(LLines);
    else
      {Unknown - try both; leak report first.}
      ParseLeakReport(LLines);
      if (FBlocks.Count = 0) and (FSummaryLines.Count = 0) then
        ParseStateCapture(LLines);
    end;
  finally
    LLines.Free;
  end;
end;

function LineIsHeader(const ALine: string): Boolean;
begin
  Result := Pos(CReportHeaderDashes, ALine) > 0;
end;

{Pulls the timestamp out of an entry header, which wraps it in dashes:
   --------------------------------2026-08-05 21:50:55.741--------------------
   --------------------------------2026/8/4 14:49:44--------------------------
 Returns '' when there is nothing between the dashes.}
function ExtractHeaderTimestamp(const ALine: string): string;
var
  LFirst, LLast: Integer;
begin
  LFirst := 1;
  while (LFirst <= Length(ALine)) and ((ALine[LFirst] = '-') or (ALine[LFirst] = ' ')) do
    Inc(LFirst);
  LLast := Length(ALine);
  while (LLast >= LFirst) and ((ALine[LLast] = '-') or (ALine[LLast] = ' ')) do
    Dec(LLast);
  if LLast >= LFirst then
    Result := Trim(Copy(ALine, LFirst, LLast - LFirst + 1))
  else
    Result := '';
end;

procedure TFastMMLeakReport.ParseLeakReport(ALines: TStrings);
var
  i: Integer;
  LEntry: TStringList;
  LLine: string;

  procedure FlushEntry;
  var
    LText: string;
  begin
    if LEntry.Count = 0 then
      Exit;
    LText := LEntry.Text;
    if Pos('has been leaked', LText) > 0 then
      ParseLeakDetail(LText)
    else if Pos('has leaked memory', LText) > 0 then
      ParseSummaryEntry(LText);
    LEntry.Clear;
  end;

begin
  LEntry := TStringList.Create;
  try
    for i := 0 to ALines.Count - 1 do
    begin
      LLine := ALines[i];
      if LineIsHeader(LLine) then
      begin
        {The first header of the run dates the whole report.  Event logs are
         appended to, so this is what tells the reports in a file apart.}
        if FTimestamp = '' then
          FTimestamp := ExtractHeaderTimestamp(LLine);
        FlushEntry;
      end
      else
        LEntry.Add(LLine);
    end;
    FlushEntry;
  finally
    LEntry.Free;
  end;
end;

{Reads the stack-trace lines that follow a "... stack trace ... was:" line,
 starting at ALines[AStartIndex].  Frames are collected until a blank line or
 a line that is clearly a new section.  Returns the index of the first line
 not consumed.}
function ReadStackFrames(ALines: TStrings; AStartIndex: Integer;
  ATarget: TObjectList): Integer;
var
  i: Integer;
  LLine, LTrim: string;
begin
  i := AStartIndex;
  while i < ALines.Count do
  begin
    LLine := ALines[i];
    LTrim := Trim(LLine);
    if LTrim = '' then
      Break;
    {A frame line starts with a hex address; be lenient and accept any line
     that is not obviously prose.  Stop at the next known section keyword.}
    if (Pos('stack trace', LTrim) > 0) or
       (Pos('currently used for', LTrim) > 0) or
       (Pos('allocation number', LTrim) > 0) or
       (Pos('Current memory dump', LTrim) > 0) or
       (Pos('was freed by thread', LTrim) > 0) then
      Break;
    ATarget.Add(FastMMParseStackFrame(LLine));
    Inc(i);
  end;
  Result := i;
end;

procedure TFastMMLeakReport.ParseLeakDetail(const AEntry: string);
var
  LLines: TStringList;
  LBlock: TFastMMLeakBlock;
  i: Integer;
  LLine, LTrim, LRest, LThreadPart: string;
  LDumpLines: TStringList;
  LInDump: Boolean;
  P: Integer;
begin
  LBlock := TFastMMLeakBlock.Create;
  LBlock.RawEntry := AEntry;
  LLines := TStringList.Create;
  LDumpLines := TStringList.Create;
  try
    SplitLines(AEntry, LLines);
    LInDump := False;
    i := 0;
    while i < LLines.Count do
    begin
      LLine := LLines[i];
      LTrim := Trim(LLine);

      if StartsWithText(LTrim, 'A memory block has been leaked') then
        LBlock.BlockSize := FastMMExtractFirstInteger(AfterMarker(LTrim, 'The size is:'))
      else if Pos('used for an object of class:', LTrim) > 0 then
        LBlock.ContentType := AfterMarker(LTrim, 'used for an object of class:')
      else if Pos('The allocation number is:', LTrim) > 0 then
        LBlock.AllocationNumber := AfterMarker(LTrim, 'The allocation number is:')
      else if StartsWithText(LTrim, 'This block was allocated') then
      begin
        {Two wordings have to be handled:
           FastMM5: "This block was allocated on <date> <time> by thread <id>, ..."
           FastMM4: "This block was allocated by thread <id>, ..."  (no timestamp)
         Matching only the leading "This block was allocated" covers both; what
         sits between that and "by thread" is the optional timestamp.}
        LRest := AfterMarker(LTrim, 'This block was allocated');
        P := Pos('by thread ', LRest);
        if P > 0 then
        begin
          LThreadPart := Trim(Copy(LRest, 1, P - 1)); {'' or 'on <date> <time>'}
          if StartsWithText(LThreadPart, 'on ') then
          begin
            LThreadPart := Trim(Copy(LThreadPart, Length('on ') + 1, MaxInt));
            {date and time separated by a space}
            P := Pos(' ', LThreadPart);
            if P > 0 then
            begin
              LBlock.AllocationDate := Copy(LThreadPart, 1, P - 1);
              LBlock.AllocationTime := Trim(Copy(LThreadPart, P + 1, MaxInt));
            end
            else
              LBlock.AllocationDate := LThreadPart;
          end;
          LRest := AfterMarker(LRest, 'by thread ');
          P := Pos(',', LRest);
          if P > 0 then
            LBlock.AllocatedByThread := Trim(Copy(LRest, 1, P - 1))
          else
            LBlock.AllocatedByThread := Trim(LRest);
        end;
        {The stack trace follows on the next lines.}
        i := ReadStackFrames(LLines, i + 1, LBlock.AllocStack) - 1;
      end
      else if StartsWithText(LTrim, 'This block was freed by thread') then
      begin
        LRest := AfterMarker(LTrim, 'This block was freed by thread');
        P := Pos(',', LRest);
        if P > 0 then
          LBlock.FreedByThread := Trim(Copy(LRest, 1, P - 1))
        else
          LBlock.FreedByThread := Trim(LRest);
        i := ReadStackFrames(LLines, i + 1, LBlock.FreeStack) - 1;
      end
      else if StartsWithText(LTrim, 'Current memory dump of') then
      begin
        P := Pos('pointer address', LTrim);
        if P > 0 then
          LBlock.DumpAddress := Trim(Copy(LTrim, P + Length('pointer address'), MaxInt));
        {Strip a trailing ':'.}
        if (LBlock.DumpAddress <> '') and
           (LBlock.DumpAddress[Length(LBlock.DumpAddress)] = ':') then
          SetLength(LBlock.DumpAddress, Length(LBlock.DumpAddress) - 1);
        LInDump := True;
      end
      else if LInDump then
        LDumpLines.Add(LLine);

      Inc(i);
    end;
    LBlock.HexDump := LDumpLines.Text;
    FBlocks.Add(LBlock);
  finally
    LDumpLines.Free;
    LLines.Free;
  end;
end;

procedure TFastMMLeakReport.ParseSummaryEntry(const AEntry: string);
var
  LLines: TStringList;
  i, P: Integer;
  LLine, LTrim, LSizePart, LListPart, LItem, LLeft, LRight: string;
  LSummary: TFastMMSummaryLine;
  LPair: TFastMMSummaryPair;
  LItems: TStringList;
  j, LxPos: Integer;
begin
  LLines := TStringList.Create;
  LItems := TStringList.Create;
  try
    SplitLines(AEntry, LLines);
    for i := 0 to LLines.Count - 1 do
    begin
      LLine := LLines[i];
      LTrim := Trim(LLine);
      if LTrim = '' then
        Continue;

      (*Capture the event-log path token {16} if present.*)
      if Pos('Memory leak detail was logged to', LTrim) > 0 then
      begin
        FEventLogPath := AfterMarker(LTrim, 'Memory leak detail was logged to');
        Continue;
      end;

      {Summary data lines look like "<size>: <count> x <Type>, <count> x ..."
       under FastMM5, and "<lower> - <upper> bytes: <count> x <Type>, ..." under
       FastMM4, which groups the leaks by size class instead of exact size.}
      P := Pos(':', LTrim);
      if P <= 0 then
        Continue;
      LSizePart := Trim(Copy(LTrim, 1, P - 1));
      if not IsSummarySizeLabel(LSizePart) then
        Continue; {prose line such as the header sentence}

      LListPart := Trim(Copy(LTrim, P + 1, MaxInt));

      LSummary := TFastMMSummaryLine.Create;
      {For a range the upper bound is the size class the blocks are binned in.}
      LSummary.BlockSize := ExtractLastInteger(LSizePart);
      LSummary.SizeText := LSizePart;

      {Split the list on commas.}
      LItems.Clear;
      LItems.CommaText := ''; {reset}
      {Manual split to avoid CommaText quoting surprises.}
      LListPart := LListPart + ',';
      while True do
      begin
        j := Pos(',', LListPart);
        if j <= 0 then
          Break;
        LItem := Trim(Copy(LListPart, 1, j - 1));
        Delete(LListPart, 1, j);
        if LItem = '' then
          Continue;
        LxPos := Pos(' x ', LItem);
        if LxPos > 0 then
        begin
          LPair := TFastMMSummaryPair.Create;
          {The two versions put the multiplier on opposite sides:
             FastMM5: "2 x TStringList"        (count first)
             FastMM4: "TCriticalSection x 1"   (type first)
           Whichever side is a plain number is the count.}
          LLeft := Trim(Copy(LItem, 1, LxPos - 1));
          LRight := Trim(Copy(LItem, LxPos + Length(' x '), MaxInt));
          if IsAllDigits(LLeft) then
          begin
            LPair.Count := FastMMExtractFirstInteger(LLeft);
            LPair.ContentType := LRight;
          end
          else
          begin
            LPair.Count := FastMMExtractFirstInteger(LRight);
            LPair.ContentType := LLeft;
          end;
          LSummary.Pairs.Add(LPair);
        end;
      end;

      if LSummary.Pairs.Count > 0 then
        FSummaryLines.Add(LSummary)
      else
        LSummary.Free;
    end;
  finally
    LItems.Free;
    LLines.Free;
  end;
end;

procedure TFastMMLeakReport.ParseStateCapture(ALines: TStrings);
var
  i, P, LxPos, LParenPos: Integer;
  LLine, LTrim, LClassPart, LCountPart, LRest: string;
  LEntry: TFastMMStateEntry;
  LExpectTimestamp: Boolean;
begin
  LExpectTimestamp := False;
  for i := 0 to ALines.Count - 1 do
  begin
    LLine := ALines[i];
    LTrim := Trim(LLine);

    if LExpectTimestamp then
    begin
      if LTrim <> '' then
      begin
        FTimestamp := LTrim;
        LExpectTimestamp := False;
      end;
      Continue;
    end;

    if LTrim = 'Timestamp:' then
      LExpectTimestamp := True
    else if EndsWithTextCI(LTrim, 'K Allocated') then
      FAllocatedKB := FastMMExtractFirstInteger(LTrim)
    else if EndsWithTextCI(LTrim, 'K Overhead') then
      FOverheadKB := FastMMExtractFirstInteger(LTrim)
    else if EndsWithTextCI(LTrim, '% Efficiency') then
      FEfficiencyPercent := FastMMExtractFirstInteger(LTrim)
    else
    begin
      {Usage detail: "<total> bytes: <Class> x <count> (<avg> bytes avg.)"}
      P := Pos(' bytes:', LTrim);
      if (P > 0) and (Pos(' x ', LTrim) > 0) then
      begin
        LEntry := TFastMMStateEntry.Create;
        LEntry.TotalBytes := FastMMExtractFirstInteger(Copy(LTrim, 1, P - 1));
        LRest := Trim(Copy(LTrim, P + Length(' bytes:'), MaxInt));
        LxPos := Pos(' x ', LRest);
        LClassPart := Trim(Copy(LRest, 1, LxPos - 1));
        LEntry.ContentType := LClassPart;
        LCountPart := Trim(Copy(LRest, LxPos + 3, MaxInt));
        LEntry.InstanceCount := FastMMExtractFirstInteger(LCountPart);
        LParenPos := Pos('(', LCountPart);
        if LParenPos > 0 then
          LEntry.AverageBytes := FastMMExtractFirstInteger(Copy(LCountPart, LParenPos, MaxInt));
        FStateEntries.Add(LEntry);
      end;
    end;
  end;
end;

{--------------------------------------------------------------------------}
{ Grouping and aggregation                                                  }
{--------------------------------------------------------------------------}

function CompareGroups(AGroup1, AGroup2: TFastMMGroup;
  ASortOrder: TFastMMGroupSortOrder): Integer;
begin
  case ASortOrder of
    gsInstanceCountDesc:
      begin
        if AGroup1.InstanceCount < AGroup2.InstanceCount then
          Result := 1
        else if AGroup1.InstanceCount > AGroup2.InstanceCount then
          Result := -1
        else
          Result := AnsiCompareText(AGroup1.ContentType, AGroup2.ContentType);
      end;
    gsContentTypeAsc:
      Result := AnsiCompareText(AGroup1.ContentType, AGroup2.ContentType);
  else
    {gsTotalBytesDesc}
    begin
      if AGroup1.TotalBytes < AGroup2.TotalBytes then
        Result := 1
      else if AGroup1.TotalBytes > AGroup2.TotalBytes then
        Result := -1
      else
        Result := AnsiCompareText(AGroup1.ContentType, AGroup2.ContentType);
    end;
  end;
end;

{Simple insertion sort over the group list (D7-friendly, stable enough and the
 group count is small).}
procedure SortGroupList(AList: TObjectList; ASortOrder: TFastMMGroupSortOrder);
var
  i, j: Integer;
  LCur: TFastMMGroup;
begin
  AList.OwnsObjects := False; {do not free while re-ordering references}
  try
    for i := 1 to AList.Count - 1 do
    begin
      LCur := TFastMMGroup(AList[i]);
      j := i - 1;
      while (j >= 0) and (CompareGroups(TFastMMGroup(AList[j]), LCur, ASortOrder) > 0) do
      begin
        AList[j + 1] := AList[j];
        Dec(j);
      end;
      AList[j + 1] := LCur;
    end;
  finally
    AList.OwnsObjects := True;
  end;
end;

function TFastMMLeakReport.BuildGroups(ASortOrder: TFastMMGroupSortOrder): TObjectList;
var
  i, j: Integer;
  LBlock: TFastMMLeakBlock;
  LStateEntry: TFastMMStateEntry;
  LGroup: TFastMMGroup;
  LFound: Boolean;
begin
  FGroups.Clear;

  {From leak-detail blocks.}
  for i := 0 to FBlocks.Count - 1 do
  begin
    LBlock := TFastMMLeakBlock(FBlocks[i]);
    LFound := False;
    for j := 0 to FGroups.Count - 1 do
    begin
      LGroup := TFastMMGroup(FGroups[j]);
      if AnsiCompareText(LGroup.ContentType, LBlock.ContentType) = 0 then
      begin
        Inc(LGroup.TotalBytes, LBlock.BlockSize);
        Inc(LGroup.InstanceCount);
        LGroup.Blocks.Add(LBlock);
        LFound := True;
        Break;
      end;
    end;
    if not LFound then
    begin
      LGroup := TFastMMGroup.Create;
      LGroup.ContentType := LBlock.ContentType;
      LGroup.TotalBytes := LBlock.BlockSize;
      LGroup.InstanceCount := 1;
      LGroup.Blocks.Add(LBlock);
      FGroups.Add(LGroup);
    end;
  end;

  {From state-capture entries (each is already one class aggregate).}
  for i := 0 to FStateEntries.Count - 1 do
  begin
    LStateEntry := TFastMMStateEntry(FStateEntries[i]);
    LGroup := TFastMMGroup.Create;
    LGroup.ContentType := LStateEntry.ContentType;
    LGroup.TotalBytes := LStateEntry.TotalBytes;
    LGroup.InstanceCount := LStateEntry.InstanceCount;
    FGroups.Add(LGroup);
  end;

  SortGroupList(FGroups, ASortOrder);
  Result := FGroups;
end;

function TFastMMLeakReport.TotalLeakedBytes: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FBlocks.Count - 1 do
    Inc(Result, TFastMMLeakBlock(FBlocks[i]).BlockSize);
  for i := 0 to FStateEntries.Count - 1 do
    Inc(Result, TFastMMStateEntry(FStateEntries[i]).TotalBytes);
end;

function TFastMMLeakReport.TotalLeakedCount: Int64;
var
  i: Integer;
begin
  Result := FBlocks.Count;
  for i := 0 to FStateEntries.Count - 1 do
    Inc(Result, TFastMMStateEntry(FStateEntries[i]).InstanceCount);
end;

function TFastMMLeakReport.Describe: string;
begin
  case FKind of
    rkLeakReport:
      begin
        Result := 'Leak report';
        if FTimestamp <> '' then
          Result := Result + ' ' + FTimestamp;
        Result := Result + Format(' - %d bytes leaked in %d block(s)',
          [TotalLeakedBytes, FBlocks.Count]);
      end;
    rkStateCapture:
      begin
        Result := 'State capture';
        if FTimestamp <> '' then
          Result := Result + ' ' + FTimestamp;
        Result := Result + Format(' - %d K allocated, %d class(es)',
          [FAllocatedKB, FStateEntries.Count]);
      end;
  else
    Result := 'Report';
  end;
end;

{--------------------------------------------------------------------------}
{ Multi-report splitting                                                    }
{--------------------------------------------------------------------------}

procedure FastMMSplitReports(const AText: string; ASegments: TStrings);
var
  LLines: TStringList;
  i: Integer;
  LLine, LTrim: string;
  LCur: string;
  LHasState: Boolean;
  LSawSummary: Boolean;

  procedure FlushCurrent;
  begin
    if Trim(LCur) <> '' then
      ASegments.Add(LCur);
    LCur := '';
  end;

begin
  ASegments.Clear;
  LLines := TStringList.Create;
  try
    SplitLines(AText, LLines);

    {Decide the file kind once: a state-capture file is delimited cleanly by the
     "FastMM State Capture:" marker; otherwise it is treated as an event log,
     where each leak-check run ends with the summary line.}
    LHasState := Pos('FastMM State Capture', AText) > 0;

    LCur := '';
    LSawSummary := False;
    for i := 0 to LLines.Count - 1 do
    begin
      LLine := LLines[i];
      LTrim := Trim(LLine);

      if LHasState then
      begin
        {A new capture marker starts a new segment.}
        if StartsWithText(LTrim, 'FastMM State Capture') and (Trim(LCur) <> '') then
          FlushCurrent;
      end
      else
      begin
        {In the event log a header line that follows a completed summary starts
         a new run.}
        if LineIsHeader(LLine) and LSawSummary then
        begin
          FlushCurrent;
          LSawSummary := False;
        end;
      end;

      LCur := LCur + LLine + sLineBreak;

      if (not LHasState) and (Pos('has leaked memory', LTrim) > 0) then
        LSawSummary := True;
    end;
    FlushCurrent;

    {A file that matched neither delimiter still yields a single segment.}
    if ASegments.Count = 0 then
      ASegments.Add(AText);
  finally
    LLines.Free;
  end;
end;

{--------------------------------------------------------------------------}
{ TFastMMReportSet                                                          }
{--------------------------------------------------------------------------}

constructor TFastMMReportSet.Create;
begin
  inherited Create;
  FReports := TObjectList.Create(True);
end;

destructor TFastMMReportSet.Destroy;
begin
  FReports.Free;
  inherited Destroy;
end;

function TFastMMReportSet.GetReport(AIndex: Integer): TFastMMLeakReport;
begin
  Result := TFastMMLeakReport(FReports[AIndex]);
end;

function TFastMMReportSet.Count: Integer;
begin
  Result := FReports.Count;
end;

procedure TFastMMReportSet.LoadFromFile(const AFileName: string);
var
  LStream: TFileStream;
  LText: string;
begin
  LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    LText := FastMMDecodeReportBytes(LStream);
  finally
    LStream.Free;
  end;
  LoadFromString(LText, AFileName);
end;

procedure TFastMMReportSet.LoadFromString(const AText, ASourceFileName: string);
var
  LSegments: TStringList;
  i: Integer;
  LReport: TFastMMLeakReport;
begin
  FReports.Clear;
  FSourceFileName := ASourceFileName;

  LSegments := TStringList.Create;
  try
    FastMMSplitReports(AText, LSegments);
    for i := 0 to LSegments.Count - 1 do
    begin
      LReport := TFastMMLeakReport.Create;
      LReport.LoadFromString(LSegments[i]);
      LReport.SourceFileName := ASourceFileName;
      {Drop empty leading/trailing fragments (e.g. stray whitespace), but keep
       genuine "no leaks" captures - those have a known kind.}
      if (LReport.Kind <> rkUnknown) or (LReport.Blocks.Count > 0) or
         (LReport.SummaryLines.Count > 0) or (LReport.StateEntries.Count > 0) then
        FReports.Add(LReport)
      else
        LReport.Free;
    end;
  finally
    LSegments.Free;
  end;

  {Never return an empty set: if nothing parsed, keep one (unknown) report so
   callers always have something to show.}
  if FReports.Count = 0 then
  begin
    LReport := TFastMMLeakReport.Create;
    LReport.LoadFromString(AText);
    LReport.SourceFileName := ASourceFileName;
    FReports.Add(LReport);
  end;
end;

end.
