program FastMM5Diag_ModeTransition;
{Regressionstest fuer #85 (Reopen): Eine fehlgeschlagene Modus-Transition (externer MM installiert)
 darf den Nesting-Counter NICHT verbleibend erhoehen. Sonst baut FastMM_SetMemoryManagerEntryPoints
 die Entrypoints spaeter aus dem vergifteten Counter und *Active bleibt haengen - auch modusuebergreifend.}
{$APPTYPE CONSOLE}
uses FastMM5;
type
  {Delphi 7 does not publicly export TMemoryManagerEx, so use the basic TMemoryManager there.  Installing any manager
   with different function pointers than FastMM's is enough to trigger the "changed externally" path we want to test.
   The block size parameter became NativeInt in XE2 (CompilerVersion 23); older compilers use Integer.}
  {$if CompilerVersion >= 18}
  TMMRec = TMemoryManagerEx;
  {$else}
  TMMRec = TMemoryManager;
  {$ifend}
  {$if CompilerVersion >= 23}
  TMMSize = NativeInt;
  {$else}
  TMMSize = Integer;
  {$ifend}
var
  GOrig: TMMRec;
  GFails: Integer;
function ForwardGetMem(ASize: TMMSize): Pointer;
begin Result := GOrig.GetMem(ASize); end;
function ForwardFreeMem(APtr: Pointer): Integer;
begin Result := GOrig.FreeMem(APtr); end;
function ForwardReallocMem(APtr: Pointer; ASize: TMMSize): Pointer;
begin Result := GOrig.ReallocMem(APtr, ASize); end;
procedure Chk(ACond: Boolean; const AName: string);
begin
  if ACond then Writeln('  ok   ', AName)
  else begin Writeln('  FAIL ', AName); Inc(GFails); end;
end;

var
  LExt: TMMRec;
  LFailedActive: Boolean;

{Ruft waehrend eines installierten externen MM zweimal Begin auf (beide muessen scheitern),
 stellt FastMM wieder her und prueft per balanciertem Begin/End-Paar, dass Active danach False ist.}
procedure TestFreedContentRollback;
begin
  SetMemoryManager(LExt);
  try
    Chk(not FastMM_BeginEraseFreedBlockContent, 'FreedContent: 1. Begin scheitert mit externem MM');
    Chk(not FastMM_BeginEraseFreedBlockContent, 'FreedContent: 2. Begin scheitert mit externem MM');
  finally
    SetMemoryManager(GOrig);
  end;
  Chk(FastMM_BeginEraseFreedBlockContent, 'FreedContent: Recovery-Begin gelingt');
  Chk(FastMM_EndEraseFreedBlockContent, 'FreedContent: Recovery-End gelingt');
  LFailedActive := FastMM_EraseFreedBlockContentActive;
  while FastMM_EraseFreedBlockContentActive do
    FastMM_EndEraseFreedBlockContent;
  Chk(not LFailedActive, 'FreedContent: Active nach balanciertem Paar wieder False');
end;

procedure TestAllocatedContentRollback;
begin
  SetMemoryManager(LExt);
  try
    Chk(not FastMM_BeginEraseAllocatedBlockContent, 'AllocContent: 1. Begin scheitert');
    Chk(not FastMM_BeginEraseAllocatedBlockContent, 'AllocContent: 2. Begin scheitert');
  finally
    SetMemoryManager(GOrig);
  end;
  Chk(FastMM_BeginEraseAllocatedBlockContent, 'AllocContent: Recovery-Begin gelingt');
  Chk(FastMM_EndEraseAllocatedBlockContent, 'AllocContent: Recovery-End gelingt');
  LFailedActive := FastMM_EraseAllocatedBlockContentActive;
  while FastMM_EraseAllocatedBlockContentActive do
    FastMM_EndEraseAllocatedBlockContent;
  Chk(not LFailedActive, 'AllocContent: Active nach balanciertem Paar wieder False');
end;

procedure TestDebugModeRollback;
begin
  SetMemoryManager(LExt);
  try
    Chk(not FastMM_EnterDebugMode, 'DebugMode: 1. Enter scheitert');
    Chk(not FastMM_EnterDebugMode, 'DebugMode: 2. Enter scheitert');
  finally
    SetMemoryManager(GOrig);
  end;
  Chk(FastMM_EnterDebugMode, 'DebugMode: Recovery-Enter gelingt');
  Chk(FastMM_ExitDebugMode, 'DebugMode: Recovery-Exit gelingt');
  LFailedActive := FastMM_DebugModeActive;
  while FastMM_DebugModeActive do
    FastMM_ExitDebugMode;
  Chk(not LFailedActive, 'DebugMode: Active nach balanciertem Paar wieder False');
end;

{Cross-Mode: FreedContent scheitert (Counter darf nicht vergiftet bleiben), danach eine
 ERFOLGREICHE DebugMode-Transition. Diese baut die Entrypoints aus allen Countern - ein
 vergifteter FreedContent-Counter wuerde FastMM_FreeMem_EraseBeforeFree installieren und
 EraseFreedBlockContentActive faelschlich True setzen.}
procedure TestCrossModeContamination;
begin
  SetMemoryManager(LExt);
  try
    FastMM_BeginEraseFreedBlockContent;
    FastMM_BeginEraseFreedBlockContent;
  finally
    SetMemoryManager(GOrig);
  end;
  Chk(FastMM_EnterDebugMode, 'CrossMode: DebugMode-Enter gelingt nach FreedContent-Fehlschlag');
  Chk(not FastMM_EraseFreedBlockContentActive,
    'CrossMode: FreedContent-Active bleibt False (kein Durchschlag in fremde Transition)');
  FastMM_ExitDebugMode;
  while FastMM_EraseFreedBlockContentActive do
    FastMM_EndEraseFreedBlockContent;
end;

{Normale Nesting-Semantik ohne externen MM darf sich nicht geaendert haben.}
procedure TestNormalNesting;
begin
  Chk(FastMM_BeginEraseFreedBlockContent, 'Normal: Begin gelingt');
  Chk(FastMM_EraseFreedBlockContentActive, 'Normal: nach Begin aktiv');
  Chk(FastMM_BeginEraseFreedBlockContent, 'Normal: verschachteltes Begin gelingt');
  Chk(FastMM_EndEraseFreedBlockContent, 'Normal: 1. End gelingt');
  Chk(FastMM_EraseFreedBlockContentActive, 'Normal: nach 1. End noch aktiv (Nesting)');
  Chk(FastMM_EndEraseFreedBlockContent, 'Normal: 2. End gelingt');
  Chk(not FastMM_EraseFreedBlockContentActive, 'Normal: nach balanciertem End inaktiv');
end;

begin
  GFails := 0;
  GetMemoryManager(GOrig);
  LExt := GOrig;
  LExt.GetMem := ForwardGetMem;
  LExt.FreeMem := ForwardFreeMem;
  LExt.ReallocMem := ForwardReallocMem;

  Writeln('#85 Counter-Rollback-Regression');
  TestFreedContentRollback;
  TestAllocatedContentRollback;
  TestDebugModeRollback;
  TestCrossModeContamination;
  TestNormalNesting;

  if GFails = 0 then Writeln('ERGEBNIS: OK')
  else begin Writeln('ERGEBNIS: ', GFails, ' FEHLER'); Halt(1); end;
end.
