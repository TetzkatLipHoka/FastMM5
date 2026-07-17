program mtstress;
{Multithreaded stress test for the FPC PurePascal code paths and the asm atomics (lock xadd / cmpxchg / cmpxchg8b)
 under FPC 3.2.2 Win32.  Modelled after Tests/FastMM5Diag_MultiThreadStress.dpr:  N threads hammer GetMem/FreeMem
 with random sizes across all block classes;  optional cross-thread frees through a lock-free mailbox exercise the
 pending-free lists.  Each block is filled with a pattern derived from its size and verified before it is freed,
 so races and corruption are detected, not just crashes.
 Parameters:  Threads Iterations MaxSize CrossFree(0/1)
 Build:  fpc -B -Mdelphi -Fu.. mtstress.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  FastMM5, Windows, SysUtils;

var
  GIters, GMaxSize: Integer;
  GCrossFree: Boolean;
  GMailbox: array[0..63] of Pointer;
  GCorruption: Integer;

var
  GDumpLock: Integer;

procedure CheckAndFree(P: Pointer; AExpectedSize: Integer);
var
  LSize, i, firstbad, lastbad: Integer;
  b: PByte;
begin
  {The first 4 bytes hold the fill size;  the rest of the block is filled with Byte(size).}
  LSize := PInteger(P)^;
  if (LSize <> AExpectedSize)
    or (PByte(NativeUInt(P) + NativeUInt(LSize) - 1)^ <> Byte(LSize)) then
  begin
    InterlockedIncrement(GCorruption);
    if InterlockedExchange(GDumpLock, 1) = 0 then
    begin
      {Dump details of the first corruption event only.}
      Writeln('CORRUPTION: p=', IntToHex(NativeUInt(P), 8),
        ' expected size=', AExpectedSize, ' stored size=', LSize,
        ' hdr=', IntToHex(PWord(NativeUInt(P) - 2)^, 4));
      b := P;
      firstbad := -1;
      lastbad := -1;
      for i := 4 to AExpectedSize - 1 do
        if b[i] <> Byte(AExpectedSize) then
        begin
          if firstbad < 0 then
            firstbad := i;
          lastbad := i;
        end;
      Writeln('  bad byte range: ', firstbad, '..', lastbad, ' of 4..', AExpectedSize - 1);
      Write('  first 16 bytes:');
      for i := 0 to 15 do
        Write(' ', IntToHex(b[i], 2));
      Writeln;
      if firstbad >= 0 then
      begin
        Write('  bytes at first bad offset:');
        for i := firstbad to firstbad + 15 do
          if i < AExpectedSize then
            Write(' ', IntToHex(b[i], 2));
        Writeln;
      end;
      Flush(Output);
    end;
  end;
  FreeMem(P);
end;

function StressThread(AParam: Pointer): Integer; stdcall;
var
  LSeed: Cardinal;
  LIter, LSize, LSlot: Integer;
  P, LSwapped: Pointer;
begin
  LSeed := Cardinal(AParam) * $9E3779B9 + 1;
  for LIter := 1 to GIters do
  begin
    LSeed := LSeed xor (LSeed shl 13);
    LSeed := LSeed xor (LSeed shr 17);
    LSeed := LSeed xor (LSeed shl 5);
    LSize := Integer(LSeed mod Cardinal(GMaxSize - 5)) + 5;
    GetMem(P, LSize);
    PInteger(P)^ := LSize;
    FillChar(Pointer(NativeUInt(P) + 4)^, LSize - 4, Byte(LSize));
    if GCrossFree and (LSeed and 7 = 0) then
    begin
      LSlot := (LSeed shr 16) and 63;
      LSwapped := Pointer(InterlockedExchange(Integer(GMailbox[LSlot]), Integer(P)));
      if LSwapped <> nil then
        CheckAndFree(LSwapped, PInteger(LSwapped)^);
    end
    else
      CheckAndFree(P, LSize);
  end;
  Result := 0;
end;

var
  LThreads: array[0..31] of THandle;
  LId: Cardinal;
  I, LThreadCount: Integer;
  LStartAllocated, LEndAllocated: NativeUInt;
begin
  LThreadCount := StrToIntDef(ParamStr(1), 8);
  if LThreadCount > 32 then
    LThreadCount := 32;
  GIters := StrToIntDef(ParamStr(2), 30000);
  GMaxSize := StrToIntDef(ParamStr(3), 70000);
  GCrossFree := ParamStr(4) <> '0';
  GCorruption := 0;

  Writeln('state=', Ord(FastMM_GetInstallationState), '  (3 = mmisInstalled)');
  Write('Threads=', LThreadCount, ' Iters=', GIters, ' MaxSize=', GMaxSize,
    ' CrossFree=', GCrossFree, ' ... ');
  Flush(Output);

  LStartAllocated := FastMM_GetUsageSummary.AllocatedBytes;

  for I := 0 to LThreadCount - 1 do
    LThreads[I] := CreateThread(nil, 0, @StressThread, Pointer(I + 1), 0, LId);
  for I := 0 to LThreadCount - 1 do
  begin
    WaitForSingleObject(LThreads[I], INFINITE);
    CloseHandle(LThreads[I]);
  end;
  Writeln('threads done');

  for I := 0 to 63 do
    if GMailbox[I] <> nil then
      CheckAndFree(GMailbox[I], PInteger(GMailbox[I])^);

  FastMM_ProcessAllPendingFrees;
  LEndAllocated := FastMM_GetUsageSummary.AllocatedBytes;

  Writeln('  corruption events   = ', GCorruption);
  Writeln('  allocated before    = ', LStartAllocated);
  Writeln('  allocated after     = ', LEndAllocated);
  Writeln('  contention small/medium/large = ', FastMM_SmallBlockThreadContentionCount, '/',
    FastMM_MediumBlockThreadContentionCount, '/', FastMM_LargeBlockThreadContentionCount);

  if (GCorruption = 0) and (LEndAllocated = LStartAllocated) then
    Writeln('PASS')
  else
  begin
    Writeln('FAIL');
    ExitCode := 1;
  end;
end.
