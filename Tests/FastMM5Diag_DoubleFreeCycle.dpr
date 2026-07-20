program FastMM5Diag_DoubleFreeCycle;
{Regressionstest fuer den Double-Free-Selbstzyklus (upstream #73):  Ein Walker-Thread schlaeft im
 WalkBlocks-Callback NUR auf unserem Zielblock, damit garantiert dessen Manager gelockt ist, wenn
 die beiden FreeMem-Aufrufe kommen - beide landen dann deterministisch im Pending-Free-Pfad.
 Der zweite FreeMem desselben Blocks muss (a) EInvalidPointer ausloesen und darf (b) den
 Pending-Link des Blocks NICHT veraendern.  Vor dem Ordering-Fix schrieb der Head-Guard erst
 PPointer(Block)^ := Head und verglich dann - bei Head=Block entstand der Selbstzyklus trotz
 Exception (Reopen von #73 durch janrysavy, 07/2026).
 Parameter: Blockgroesse (Default 2000; 50000 = Medium, 500000 = Large).}
{$APPTYPE CONSOLE}
uses FastMM5, Windows, SysUtils;
var
  GTarget: Pointer;
  GOnTarget: Integer;
procedure WalkCallback(const ABlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo);
begin
  if ABlockInfo.BlockAddress = GTarget then
  begin
    InterlockedExchange(GOnTarget, 1);
    Sleep(2000);
  end;
end;
function LockerThread(AParam: Pointer): DWORD; stdcall;
begin
  FastMM_WalkBlocks(WalkCallback, [btSmallBlock, btMediumBlock, btLargeBlock], False, nil, 5000);
  Result := 0;
end;
var
  P: Pointer; H: THandle; LId: DWORD;
  LRaised: Boolean;
  LFirstWordAfterFirst, LFirstWordAfterSecond: NativeUInt;
begin
  GetMem(GTarget, StrToIntDef(ParamStr(1), 2000));
  P := GTarget;
  H := CreateThread(nil, 0, @LockerThread, nil, 0, LId);
  while GOnTarget = 0 do Sleep(1);
  FreeMem(P);
  LFirstWordAfterFirst := PNativeUInt(P)^;
  LRaised := False;
  try
    FreeMem(P);
  except
    LRaised := True;
  end;
  LFirstWordAfterSecond := PNativeUInt(P)^;
  WaitForSingleObject(H, INFINITE);
  CloseHandle(H);
  Writeln('SecondFreeRaised=', LRaised);
  Writeln('P=', NativeUInt(P));
  Writeln('FirstWordAfterFirstFree =', LFirstWordAfterFirst);
  Writeln('FirstWordAfterSecondFree=', LFirstWordAfterSecond);
  if LFirstWordAfterSecond = NativeUInt(P) then
  begin
    Writeln('BUG BESTAETIGT: Selbstzyklus in der Pending-Free-Liste trotz Exception.');
    Halt(1);
  end;
  Writeln('OK: Pending-Link unveraendert.');
end.
