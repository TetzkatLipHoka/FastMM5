program doublealloc;
{Proves/disproves double-handout of small blocks under MT load:  every allocated pointer is claimed in a lock-free
 ownership table;  if GetMem returns a pointer that is already claimed (and not yet freed), the allocator handed the
 same block to two threads.  Fixed size class, 2..N threads, tight loop.
 Parameters:  Threads Iterations Size
 Build:  fpc -B -Mdelphi -Fu.. doublealloc.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  FastMM5, Windows, SysUtils;

const
  CTableSize = 1 shl 16;

var
  GIters, GSize: Integer;
  GClaims: array[0..CTableSize - 1] of Pointer;
  GDoubleHandout, GCollisions: Integer;

function Idx(P: Pointer): Integer;
begin
  Result := Integer((NativeUInt(P) shr 3) and (CTableSize - 1));
end;

function CasPtr(var ATarget: Pointer; ANew, AComparand: Pointer): Pointer;
begin
{$ifdef CPU64}
  Result := Pointer(InterlockedCompareExchange64(Int64(ATarget), Int64(ANew), Int64(AComparand)));
{$else}
  Result := Pointer(InterlockedCompareExchange(Integer(ATarget), Integer(ANew), Integer(AComparand)));
{$endif}
end;

function StressThread(AParam: Pointer): Integer; stdcall;
var
  LIter, LIdx: Integer;
  P: Pointer;
  LPrev: Pointer;
  LTracked: Boolean;
begin
  for LIter := 1 to GIters do
  begin
    GetMem(P, GSize);
    LIdx := Idx(P);
    LPrev := CasPtr(GClaims[LIdx], P, nil);
    LTracked := LPrev = nil;
    if (LPrev <> nil) and (LPrev = P) then
    begin
      {The block is already live in another thread!}
      InterlockedIncrement(GDoubleHandout);
    end
    else if LPrev <> nil then
      InterlockedIncrement(GCollisions);

    {Touch the block the way a user would.}
    FillChar(P^, GSize, $AA);

    if LTracked then
      CasPtr(GClaims[LIdx], nil, P);
    FreeMem(P);
  end;
  Result := 0;
end;

var
  LThreads: array[0..31] of THandle;
  LId: Cardinal;
  I, LThreadCount: Integer;
begin
  LThreadCount := StrToIntDef(ParamStr(1), 2);
  if LThreadCount > 32 then
    LThreadCount := 32;
  GIters := StrToIntDef(ParamStr(2), 500000);
  GSize := StrToIntDef(ParamStr(3), 5);

  Writeln('state=', Ord(FastMM_GetInstallationState), ' Threads=', LThreadCount,
    ' Iters=', GIters, ' Size=', GSize);

  for I := 0 to LThreadCount - 1 do
    LThreads[I] := CreateThread(nil, 0, @StressThread, Pointer(I + 1), 0, LId);
  for I := 0 to LThreadCount - 1 do
  begin
    WaitForSingleObject(LThreads[I], INFINITE);
    CloseHandle(LThreads[I]);
  end;

  Writeln('  double handouts = ', GDoubleHandout);
  Writeln('  hash collisions = ', GCollisions);
  if GDoubleHandout = 0 then
    Writeln('PASS (no double handout detected)')
  else
  begin
    Writeln('FAIL: allocator returned a live block to a second thread');
    ExitCode := 1;
  end;
end.
