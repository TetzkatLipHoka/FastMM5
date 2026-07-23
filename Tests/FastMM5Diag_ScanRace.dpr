{Stress test for the race that FastMM_WalkBlocks guards against:  worker threads
 hammer small debug block allocation and freeing (so spans are constantly
 sequentially fed, split off and recycled) while another thread runs
 FastMM_ScanDebugBlocksForCorruption in a loop.

 No corruption is ever introduced, so every exception the scanner sees is a
 false positive, and any access violation is a crash in the walk itself.

 This is the counterpart to FastMM5Diag_ScanCoverage:  that one checks that real
 corruption is still found, this one that no corruption is invented.  The guard
 in FastMM_WalkBlocks trades the one against the other (upstream issue #102), so
 both directions need a test.

 Usage:  FastMM5Diag_ScanRace [seconds] [threads]   (defaults: 20 seconds, 4 threads)
 Exit code 0 = no false positive, no crash.}

program FastMM5Diag_ScanRace;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  Windows,
  SysUtils,
  Classes;

var
  GStop: Integer = 0;
  GAllocations: Integer = 0;
  GScans: Integer = 0;
  GFalsePositives: Integer = 0;
  GWorkerErrors: Integer = 0;
  GScannerCrashes: Integer = 0;

type
  TWorker = class(TThread)
  private
    FSeed: Cardinal;
    function NextRandom(ALimit: Integer): Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(ASeed: Cardinal);
  end;

  TScanner = class(TThread)
  protected
    procedure Execute; override;
  end;

constructor TWorker.Create(ASeed: Cardinal);
begin
  FSeed := ASeed;
  inherited Create(False);
end;

function TWorker.NextRandom(ALimit: Integer): Integer;
begin
  {A private generator:  the RTL one is global state and would itself become a
   source of contention.}
  FSeed := FSeed * 1103515245 + 12345;
  Result := Integer((FSeed shr 16) mod Cardinal(ALimit));
end;

procedure TWorker.Execute;
const
  CLiveBlocks = 64;
var
  LBlocks: array[0..CLiveBlocks - 1] of Pointer;
  LSizes: array[0..CLiveBlocks - 1] of Integer;
  i, LIndex, LSize: Integer;
begin
  for i := 0 to CLiveBlocks - 1 do
  begin
    LBlocks[i] := nil;
    LSizes[i] := 0;
  end;
  try
    while GStop = 0 do
    begin
      LIndex := NextRandom(CLiveBlocks);
      if LBlocks[LIndex] <> nil then
      begin
        {Verify the block still holds what was written into it:  a corruption of
         user data would show up here rather than in the scanner.}
        if PByte(LBlocks[LIndex])^ <> Byte(LSizes[LIndex]) then
          InterlockedIncrement(GWorkerErrors);
        FreeMem(LBlocks[LIndex]);
        LBlocks[LIndex] := nil;
      end;
      {Small blocks only:  that is the path the guard in FastMM_WalkBlocks is
       about.}
      LSize := 16 + NextRandom(2000);
      GetMem(LBlocks[LIndex], LSize);
      LSizes[LIndex] := LSize;
      FillChar(LBlocks[LIndex]^, LSize, Byte(LSize));
      InterlockedIncrement(GAllocations);
    end;
  except
    on E: Exception do
    begin
      InterlockedIncrement(GWorkerErrors);
      WriteLn('  worker exception: ', E.ClassName, ': ', E.Message);
    end;
  end;
  for i := 0 to CLiveBlocks - 1 do
    if LBlocks[i] <> nil then
      FreeMem(LBlocks[i]);
end;

procedure TScanner.Execute;
begin
  while GStop = 0 do
  begin
    try
      FastMM_ScanDebugBlocksForCorruption(1000);
      InterlockedIncrement(GScans);
    except
      on E: Exception do
      begin
        {Nothing corrupts anything here, so this is either a false positive
         (EInvalidPointer from the scan) or a crash inside the walk.}
        if E is EAccessViolation then
        begin
          InterlockedIncrement(GScannerCrashes);
          WriteLn('  scanner A/V: ', E.Message);
        end
        else
        begin
          InterlockedIncrement(GFalsePositives);
          WriteLn('  scanner false positive: ', E.ClassName, ': ', E.Message);
        end;
      end;
    end;
  end;
end;

var
  GWorkers: array of TWorker;
  GScanner: TScanner;
  i, GSeconds, GThreadCount: Integer;
begin
  GSeconds := 20;
  GThreadCount := 4;
  if ParamCount >= 1 then
    GSeconds := StrToIntDef(ParamStr(1), 20);
  if ParamCount >= 2 then
    GThreadCount := StrToIntDef(ParamStr(2), 4);

  FastMM_MessageBoxEvents := [];
  FastMM_LogToFileEvents := [];
  FastMM_OutputDebugStringEvents := [];

  if not FastMM_EnterDebugMode then
  begin
    WriteLn('FastMM_EnterDebugMode failed');
    Halt(2);
  end;

  WriteLn(Format('Scanning while %d thread(s) churn small debug blocks for %d s ...',
    [GThreadCount, GSeconds]));

  SetLength(GWorkers, GThreadCount);
  for i := 0 to GThreadCount - 1 do
    GWorkers[i] := TWorker.Create(Cardinal(i) * 7919 + 12345);
  GScanner := TScanner.Create(False);

  Sleep(GSeconds * 1000);
  InterlockedExchange(GStop, 1);

  GScanner.WaitFor;
  GScanner.Free;
  for i := 0 to GThreadCount - 1 do
  begin
    GWorkers[i].WaitFor;
    GWorkers[i].Free;
  end;

  FastMM_ExitDebugMode;

  WriteLn(Format('  allocations      : %d', [GAllocations]));
  WriteLn(Format('  completed scans  : %d', [GScans]));
  WriteLn(Format('  false positives  : %d', [GFalsePositives]));
  WriteLn(Format('  scanner crashes  : %d', [GScannerCrashes]));
  WriteLn(Format('  worker errors    : %d', [GWorkerErrors]));
  if (GFalsePositives = 0) and (GScannerCrashes = 0) and (GWorkerErrors = 0) then
  begin
    WriteLn('OK');
    ExitCode := 0;
  end
  else
  begin
    WriteLn('FAILED');
    ExitCode := 1;
  end;
end.
