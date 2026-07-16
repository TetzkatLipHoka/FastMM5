program FastMM5Diag_MultiThreadStress;
{$APPTYPE CONSOLE}

uses
  FastMM5, Windows, SysUtils;

var
  GIters, GMaxSize: Integer;
  GCrossFree: Boolean;
  GMailbox: array[0..63] of Pointer;
  GDone: Integer;

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
    LSize := Integer(LSeed mod Cardinal(GMaxSize)) + 1;
    GetMem(P, LSize);
    FillChar(P^, LSize, Byte(LSize));
    if GCrossFree and (LSeed and 7 = 0) then
    begin
      LSlot := (LSeed shr 16) and 63;
      LSwapped := Pointer(InterlockedExchange(Integer(GMailbox[LSlot]), Integer(P)));
      if LSwapped <> nil then
        FreeMem(LSwapped);
    end
    else
      FreeMem(P);
  end;
  InterlockedIncrement(GDone);
  Result := 0;
end;

var
  LThreads: array[0..31] of THandle;
  LId: Cardinal;
  I, LThreadCount: Integer;
  LDebug: Boolean;
begin
  {Parameter: Threads Iterationen MaxSize Debug(0/1) CrossFree(0/1)}
  LThreadCount := StrToIntDef(ParamStr(1), 8);
  GIters := StrToIntDef(ParamStr(2), 20000);
  GMaxSize := StrToIntDef(ParamStr(3), 70000);
  LDebug := ParamStr(4) = '1';
  GCrossFree := ParamStr(5) <> '0';

  Write('Threads=', LThreadCount, ' Iters=', GIters, ' MaxSize=', GMaxSize,
    ' Debug=', LDebug, ' CrossFree=', GCrossFree, ' ... ');

  if LDebug then
    if not FastMM_EnterDebugMode then
    begin
      WriteLn('EnterDebugMode FEHLGESCHLAGEN');
      Halt(2);
    end;

  GDone := 0;
  for I := 0 to LThreadCount - 1 do
    LThreads[I] := CreateThread(nil, 0, @StressThread, Pointer(I + 1), 0, LId);
  for I := 0 to LThreadCount - 1 do
  begin
    WaitForSingleObject(LThreads[I], INFINITE);
    CloseHandle(LThreads[I]);
  end;

  for I := 0 to 63 do
    if GMailbox[I] <> nil then
      FreeMem(GMailbox[I]);

  WriteLn;
  with FastMM_GetUsageSummary do
    WriteLn('  Bilanz: Allokiert=', AllocatedBytes, ' Overhead=', OverheadBytes);
  FastMM_ProcessAllPendingFrees;
  with FastMM_GetUsageSummary do
    WriteLn('  Nach ProcessAllPendingFrees: Allokiert=', AllocatedBytes, ' Overhead=', OverheadBytes);
  if LDebug then
    FastMM_ExitDebugMode;
  WriteLn('OK');
end.


