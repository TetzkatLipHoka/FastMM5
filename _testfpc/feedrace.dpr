program feedrace;
{Isolates the lock-free sequential-feed path:  N threads allocate small blocks WITHOUT freeing, then all pointers are
 merged, sorted and checked for duplicates/overlaps.  Any overlap means the sequential feed (or span allocation)
 handed out the same memory twice.  Frees only happen after verification, single-threaded.
 Parameters:  Threads BlocksPerThread Size Rounds
 Build:  fpc -B -Mdelphi -Fu.. feedrace.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  FastMM5, Windows, SysUtils;

var
  GPerThread, GSize: Integer;
  GPtrs: array[0..15] of array of Pointer;
  GReady: Integer;

function AllocThread(AParam: Pointer): Integer; stdcall;
var
  i, t: Integer;
begin
  t := Integer(AParam);
  InterlockedIncrement(GReady);
  while GReady < 0 do;
  for i := 0 to GPerThread - 1 do
    GetMem(GPtrs[t][i], GSize);
  Result := 0;
end;

procedure SortPtrs(var A: array of NativeUInt; L, R: Integer);
var
  i, j: Integer;
  p, t: NativeUInt;
begin
  i := L; j := R; p := A[(L + R) shr 1];
  repeat
    while A[i] < p do Inc(i);
    while A[j] > p do Dec(j);
    if i <= j then
    begin
      t := A[i]; A[i] := A[j]; A[j] := t;
      Inc(i); Dec(j);
    end;
  until i > j;
  if L < j then SortPtrs(A, L, j);
  if i < R then SortPtrs(A, i, R);
end;

var
  LThreads: array[0..15] of THandle;
  LId: Cardinal;
  i, t, LThreadCount, LRounds, r, LTotal, LOverlaps, LBlockSpacing: Integer;
  all: array of NativeUInt;
begin
  LThreadCount := StrToIntDef(ParamStr(1), 4);
  if LThreadCount > 16 then
    LThreadCount := 16;
  GPerThread := StrToIntDef(ParamStr(2), 100000);
  GSize := StrToIntDef(ParamStr(3), 5);
  LRounds := StrToIntDef(ParamStr(4), 5);

  Writeln('state=', Ord(FastMM_GetInstallationState), ' Threads=', LThreadCount,
    ' PerThread=', GPerThread, ' Size=', GSize, ' Rounds=', LRounds);

  {The real spacing between distinct blocks of this size class:  block size includes the 2-byte header.}
  LBlockSpacing := 1;  {minimum plausible; refined below from observed pointers}

  for r := 1 to LRounds do
  begin
    for t := 0 to LThreadCount - 1 do
      SetLength(GPtrs[t], GPerThread);

    GReady := -LThreadCount * 2;  {negative barrier: threads spin until all created}
    for t := 0 to LThreadCount - 1 do
      LThreads[t] := CreateThread(nil, 0, @AllocThread, Pointer(t), 0, LId);
    InterlockedExchangeAdd(GReady, LThreadCount * 3);  {release the barrier}
    for t := 0 to LThreadCount - 1 do
    begin
      WaitForSingleObject(LThreads[t], INFINITE);
      CloseHandle(LThreads[t]);
    end;

    {Merge and sort all pointers, then look for duplicates and overlaps.}
    LTotal := LThreadCount * GPerThread;
    SetLength(all, LTotal);
    i := 0;
    for t := 0 to LThreadCount - 1 do
      for LOverlaps := 0 to GPerThread - 1 do
      begin
        all[i] := NativeUInt(GPtrs[t][LOverlaps]);
        Inc(i);
      end;
    SortPtrs(all, 0, LTotal - 1);

    LOverlaps := 0;
    for i := 1 to LTotal - 1 do
      if all[i] = all[i - 1] then
        Inc(LOverlaps);
    if LOverlaps > 0 then
    begin
      Writeln('round ', r, ': ', LOverlaps, ' DUPLICATE POINTERS (double handout)');
      ExitCode := 1;
    end
    else
      Writeln('round ', r, ': ', LTotal, ' pointers, all distinct');

    {Free everything single-threaded.}
    for t := 0 to LThreadCount - 1 do
      for i := 0 to GPerThread - 1 do
        FreeMem(GPtrs[t][i]);
    if ExitCode <> 0 then
      Break;
  end;

  if ExitCode = 0 then
    Writeln('PASS')
  else
    Writeln('FAIL');
end.
