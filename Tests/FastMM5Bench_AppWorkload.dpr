{An application shaped workload for the freed block fill pattern check.

 The microbenchmark next to this one allocates one size in a loop, which answers
 "how much faster is the check itself" but not "what does an application get".
 This program answers the second question:  it runs a mixed workload of the kind
 a real Delphi program produces - strings, objects, growing lists, and the odd
 large buffer - in debug mode, and reports the elapsed time.

 It also reports where the allocation volume actually sits, which is what makes
 an end to end number transferable at all:  the vector path engages only from
 CMinimumVectorFillPatternBytes upward, so an application that allocates nothing
 but short strings cannot gain anything no matter how fast the vector loop is.

 Everything here is RTL only and deterministic - a fixed seed linear congruential
 generator, no file or network access - so the same run can be reproduced
 anywhere.

 Usage:  FastMM5Bench_AppWorkload <rounds> [stack trace depth] [-histogram]

   rounds             workload rounds;  8 takes roughly a third of a second
   stack trace depth  0 (default) isolates the allocator, 20 is the debug mode
                      default and is what an application actually runs with
   -histogram         instead of timing, install a counting memory manager in
                      front of FastMM and report the size distribution of the
                      blocks that get freed - the population the check runs over

 Timing mode prints:  elapsed milliseconds and a work checksum.  The checksum is
 derived from the data, not from addresses, so two builds can be compared:  the
 heap base is randomised per process and addresses never match.}

program FastMM5Bench_AppWorkload;

{$APPTYPE CONSOLE}
{$O+}

uses
  FastMM5,
  {$if CompilerVersion >= 23}Winapi.Windows, System.SysUtils, System.Classes
  {$else}Windows, SysUtils, Classes{$ifend};

{The RTL changed the memory manager signatures from Integer to NativeInt.  Only
 the histogram mode installs a manager, but it has to match exactly.}
{$if CompilerVersion >= 20}
type
  TMMSize = NativeInt;
  TMMAllocSize = NativeInt;
{$else}
type
  TMMSize = Integer;
  TMMAllocSize = Cardinal;
{$ifend}

const
  {Bucket boundaries in bytes.  The interesting line is 136:  that is the first
   user size at which the vector path engages, so everything below it pays the
   scalar path no matter what.}
  CBucketCount = 12;
  CBucketLimit: array[0..CBucketCount - 1] of Integer = (
    16, 32, 64, 96, 136, 192, 256, 512, 1024, 4096, 65536, MaxInt);
  {136 is the last user size that still runs entirely on the scalar path, so the
   vector path starts with the bucket after the one ending at 136.}
  CVectorThresholdBucket = 5;

type
  {A record like the ones an application shuffles around:  a few strings and a
   payload buffer, so one "record" produces several allocations of different
   sizes rather than one.}
  TRecordObject = class(TObject)
  public
    Name: string;
    Description: string;
    Payload: TBytes;
    Value: Integer;
    destructor Destroy; override;
  end;

var
  {Deterministic generator:  the RTL's Random is seeded reproducibly too, but a
   local LCG cannot change behaviour between compiler versions.}
  GSeed: Cardinal = 123456789;

  GHistogramMode: Boolean = False;
  GOldMM: TMemoryManagerEx;
  GFreeCounts: array[0..CBucketCount - 1] of Int64;
  GFreeBytes: array[0..CBucketCount - 1] of Int64;
  GChecksum: NativeUInt = 0;

destructor TRecordObject.Destroy;
begin
  Name := '';
  Description := '';
  SetLength(Payload, 0);
  inherited;
end;

function NextRandom(ALimit: Integer): Integer;
begin
  GSeed := GSeed * 1103515245 + 12345;
  Result := Integer((GSeed shr 16) and $7FFF) mod ALimit;
end;

function BucketFor(ASize: Integer): Integer;
begin
  Result := 0;
  while (Result < CBucketCount - 1) and (ASize > CBucketLimit[Result]) do
    Inc(Result);
end;

{--------------------------------------------------------- the counting manager}

{Only installed in histogram mode.  FreeMem is the interesting hook:  it is the
 block sizes that get freed that end up in the debug free queue, and that is the
 population the fill pattern check walks.}

function TrackGetMem(ASize: TMMSize): Pointer;
begin
  Result := GOldMM.GetMem(ASize);
end;

function TrackFreeMem(APointer: Pointer): Integer;
var
  LBucket: Integer;
  LSize: NativeInt;
begin
  {Returns 0 for anything that is not a live FastMM block.}
  LSize := FastMM_BlockCurrentUserBytes(APointer);
  if LSize > 0 then
  begin
    LBucket := BucketFor(Integer(LSize));
    Inc(GFreeCounts[LBucket]);
    Inc(GFreeBytes[LBucket], LSize);
  end;
  Result := GOldMM.FreeMem(APointer);
end;

function TrackReallocMem(APointer: Pointer; ASize: TMMSize): Pointer;
begin
  Result := GOldMM.ReallocMem(APointer, ASize);
end;

function TrackAllocMem(ASize: TMMAllocSize): Pointer;
begin
  Result := GOldMM.AllocMem(ASize);
end;

function TrackRegisterExpectedMemoryLeak(APointer: Pointer): Boolean;
begin
  Result := GOldMM.RegisterExpectedMemoryLeak(APointer);
end;

function TrackUnregisterExpectedMemoryLeak(APointer: Pointer): Boolean;
begin
  Result := GOldMM.UnregisterExpectedMemoryLeak(APointer);
end;

procedure InstallCountingManager;
var
  LNewMM: TMemoryManagerEx;
begin
  GetMemoryManager(GOldMM);
  LNewMM.GetMem := TrackGetMem;
  LNewMM.FreeMem := TrackFreeMem;
  LNewMM.ReallocMem := TrackReallocMem;
  LNewMM.AllocMem := TrackAllocMem;
  LNewMM.RegisterExpectedMemoryLeak := TrackRegisterExpectedMemoryLeak;
  LNewMM.UnregisterExpectedMemoryLeak := TrackUnregisterExpectedMemoryLeak;
  SetMemoryManager(LNewMM);
end;

procedure RemoveCountingManager;
begin
  SetMemoryManager(GOldMM);
end;

{------------------------------------------------------------------- the work}

{One round of the sort of thing an application does:  build a batch of records,
 put them in a list, walk the list, format some output, throw it all away.  The
 mix is deliberate - most allocations are small (strings, objects), a few are
 large (payload buffers, the list's own array as it grows).}
procedure RunRound(ARecordsPerRound: Integer);
var
  LList: TList;
  LRecord: TRecordObject;
  LLines: TStringList;
  LText: string;
  i, j, LPayloadSize: Integer;
begin
  LList := TList.Create;
  try
    for i := 0 to ARecordsPerRound - 1 do
    begin
      LRecord := TRecordObject.Create;
      LRecord.Name := 'item_' + IntToStr(i) + '_' + IntToStr(NextRandom(100000));
      LRecord.Description := StringOfChar('d', 24 + NextRandom(200));
      LRecord.Value := NextRandom(1000);

      {Payload sizes span the threshold on purpose:  most are small, some are in
       the KB range, a few are large - the shape of a real document or record
       cache rather than a uniform distribution.}
      case NextRandom(10) of
        0..5: LPayloadSize := 16 + NextRandom(112);        //below the threshold
        6..8: LPayloadSize := 256 + NextRandom(3840);      //KB range
      else
        LPayloadSize := 16384 + NextRandom(49152);         //large buffers
      end;
      SetLength(LRecord.Payload, LPayloadSize);
      for j := 0 to 7 do
        LRecord.Payload[j mod LPayloadSize] := Byte(LRecord.Value + j);

      LList.Add(LRecord);
    end;

    {Walk the batch and produce formatted output, the way a report or an export
     would:  lots of short lived strings.}
    LLines := TStringList.Create;
    try
      for i := 0 to LList.Count - 1 do
      begin
        LRecord := TRecordObject(LList[i]);
        LText := LRecord.Name + ' = ' + IntToStr(LRecord.Value) + ' [' +
          IntToStr(Length(LRecord.Payload)) + '] ' + Copy(LRecord.Description, 1, 32);
        LLines.Add(LText);
        Inc(GChecksum, NativeUInt(Length(LText)) + NativeUInt(LRecord.Value));
      end;
      LText := LLines.Text;
      Inc(GChecksum, NativeUInt(Length(LText)));
    finally
      LLines.Free;
    end;
  finally
    for i := 0 to LList.Count - 1 do
      TRecordObject(LList[i]).Free;
    LList.Free;
  end;
end;

procedure ReportHistogram;
var
  i: Integer;
  LTotalCount, LTotalBytes, LVectorCount, LVectorBytes: Int64;
  LLow: Integer;
begin
  LTotalCount := 0;
  LTotalBytes := 0;
  LVectorCount := 0;
  LVectorBytes := 0;
  for i := 0 to CBucketCount - 1 do
  begin
    Inc(LTotalCount, GFreeCounts[i]);
    Inc(LTotalBytes, GFreeBytes[i]);
    if i >= CVectorThresholdBucket then
    begin
      Inc(LVectorCount, GFreeCounts[i]);
      Inc(LVectorBytes, GFreeBytes[i]);
    end;
  end;
  if LTotalCount = 0 then
    LTotalCount := 1;
  if LTotalBytes = 0 then
    LTotalBytes := 1;

  WriteLn('Size distribution of freed blocks - the population the check walks');
  WriteLn;
  WriteLn('        user size          blocks     share        bytes     share');
  LLow := 0;
  for i := 0 to CBucketCount - 1 do
  begin
    if CBucketLimit[i] = MaxInt then
      Write(Format('%10d ..%9s', [LLow, 'up']))
    else
      Write(Format('%10d ..%9d', [LLow, CBucketLimit[i]]));
    WriteLn(Format(' %13d %8.2f%% %12d %8.2f%%',
      [GFreeCounts[i], GFreeCounts[i] * 100.0 / LTotalCount,
       GFreeBytes[i], GFreeBytes[i] * 100.0 / LTotalBytes]));
    LLow := CBucketLimit[i] + 1;
  end;
  WriteLn;
  WriteLn(Format('Blocks that can reach the vector path (>%d bytes):  %.2f%% of blocks, %.2f%% of bytes',
    [CBucketLimit[CVectorThresholdBucket - 1],
     LVectorCount * 100.0 / LTotalCount, LVectorBytes * 100.0 / LTotalBytes]));
  WriteLn(Format('Total: %d freed blocks, %d bytes', [LTotalCount, LTotalBytes]));
end;

var
  GFrequency, GStart, GStop: Int64;
  GRounds, GStackDepth, i: Integer;

begin
  GRounds := StrToIntDef(ParamStr(1), 8);
  GStackDepth := StrToIntDef(ParamStr(2), 0);
  for i := 1 to ParamCount do
    if SameText(ParamStr(i), '-histogram') then
      GHistogramMode := True;

  FastMM_MessageBoxEvents := [];
  FastMM_LogToFileEvents := [];
  FastMM_OutputDebugStringEvents := [];
  FastMM_SetDebugModeStackTraceEntryCount(GStackDepth);

  if not FastMM_EnterDebugMode then
  begin
    WriteLn('EnterDebugMode failed');
    Halt(2);
  end;

  SetPriorityClass(GetCurrentProcess, HIGH_PRIORITY_CLASS);
  SetThreadAffinityMask(GetCurrentThread, 2);
  QueryPerformanceFrequency(GFrequency);

  {Warm up:  page in the code and prime the debug free queue, so the timed part
   already reuses blocks instead of getting fresh ones.}
  RunRound(200);
  RunRound(200);

  if GHistogramMode then
  begin
    InstallCountingManager;
    try
      for i := 1 to GRounds do
        RunRound(500);
    finally
      RemoveCountingManager;
    end;
    FastMM_ExitDebugMode;
    ReportHistogram;
  end
  else
  begin
    GChecksum := 0;
    QueryPerformanceCounter(GStart);
    for i := 1 to GRounds do
      RunRound(500);
    QueryPerformanceCounter(GStop);
    FastMM_ExitDebugMode;
    WriteLn(Format('%.4f %d', [(GStop - GStart) * 1000.0 / GFrequency, GChecksum]));
  end;
end.
