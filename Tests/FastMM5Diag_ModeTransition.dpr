program FastMM5Diag_ModeTransition;
{Vertrags-Regressionstest fuer die Debug-/Erase-Modus-Umschaltung (#85).

 Pierres dokumentierter Vertrag (Kommentar in FastMM5.pas / Issue #85): der interne Nesting-Counter
 wird bei JEDEM Begin/Enter- bzw. End/Exit-Aufruf angepasst - UNABHAENGIG vom Rueckgabewert. Wer die
 Funktionen benutzt, muss Begin/Enter und End/Exit paarweise ausgleichen (auch wenn Begin/Enter False
 liefert). *Active ist True gdw. Counter>0 UND der letzte Aufruf erfolgreich war.

 Dieser Test sichert genau diesen Vertrag ab - insbesondere gegen die naheliegende (falsche) "Rollback
 bei Fehlschlag"-Idee: die wuerde bei korrekt balancierter Nutzung den Counter ins Negative treiben,
 sodass ein spaeteres echtes Begin den Modus nicht mehr aktiviert (Szenario A unten faengt das).}
{$APPTYPE CONSOLE}
uses FastMM5;
type
  {Delphi 7 exportiert TMemoryManagerEx nicht; dort genuegt der 3-Feld-TMemoryManager. Ein Manager mit
   anderen Funktionszeigern als FastMM loest den "changed externally"-Pfad aus (Begin/Enter -> False).
   Der Groessenparameter wurde in XE2 (CompilerVersion 23) NativeInt; aeltere Compiler nutzen Integer.}
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

{Szenario A (Kern): Ein fehlgeschlagenes Begin wird vertragsgemaess mit End balanciert. Danach muss ein
 ECHTES Begin/End-Paar den Modus weiterhin korrekt schalten. (Ein Fehlschlag-Rollback wuerde hier den
 Counter ins Negative treiben und das echte Begin wirkungslos machen.)}
procedure TestBalancedThroughFailure_Freed;
var LActiveAfterRealBegin: Boolean;
begin
  SetMemoryManager(LExt);
  try
    Chk(not FastMM_BeginEraseFreedBlockContent, 'Freed/A: Begin scheitert mit externem MM');
    {Vertrag: Active ist False, obwohl der Counter erhoeht wurde (letzter Aufruf nicht erfolgreich).}
    Chk(not FastMM_EraseFreedBlockContentActive, 'Freed/A: nach Fehlschlag inaktiv (letzter Aufruf != Erfolg)');
  finally
    SetMemoryManager(GOrig);
  end;
  Chk(FastMM_EndEraseFreedBlockContent, 'Freed/A: balancierendes End gelingt');
  {Jetzt echte Nutzung - MUSS aktivieren.}
  Chk(FastMM_BeginEraseFreedBlockContent, 'Freed/A: echtes Begin gelingt');
  LActiveAfterRealBegin := FastMM_EraseFreedBlockContentActive;
  Chk(FastMM_EndEraseFreedBlockContent, 'Freed/A: echtes End gelingt');
  Chk(LActiveAfterRealBegin, 'Freed/A: echtes Begin AKTIVIERT den Modus (Counter intakt)');
  Chk(not FastMM_EraseFreedBlockContentActive, 'Freed/A: nach echtem Paar wieder inaktiv');
end;

procedure TestBalancedThroughFailure_Allocated;
var LActiveAfterRealBegin: Boolean;
begin
  SetMemoryManager(LExt);
  try
    Chk(not FastMM_BeginEraseAllocatedBlockContent, 'Alloc/A: Begin scheitert mit externem MM');
    Chk(not FastMM_EraseAllocatedBlockContentActive, 'Alloc/A: nach Fehlschlag inaktiv');
  finally
    SetMemoryManager(GOrig);
  end;
  Chk(FastMM_EndEraseAllocatedBlockContent, 'Alloc/A: balancierendes End gelingt');
  Chk(FastMM_BeginEraseAllocatedBlockContent, 'Alloc/A: echtes Begin gelingt');
  LActiveAfterRealBegin := FastMM_EraseAllocatedBlockContentActive;
  Chk(FastMM_EndEraseAllocatedBlockContent, 'Alloc/A: echtes End gelingt');
  Chk(LActiveAfterRealBegin, 'Alloc/A: echtes Begin AKTIVIERT den Modus (Counter intakt)');
  Chk(not FastMM_EraseAllocatedBlockContentActive, 'Alloc/A: nach echtem Paar wieder inaktiv');
end;

procedure TestBalancedThroughFailure_Debug;
var LActiveAfterRealEnter: Boolean;
begin
  SetMemoryManager(LExt);
  try
    Chk(not FastMM_EnterDebugMode, 'Debug/A: Enter scheitert mit externem MM');
    Chk(not FastMM_DebugModeActive, 'Debug/A: nach Fehlschlag inaktiv');
  finally
    SetMemoryManager(GOrig);
  end;
  Chk(FastMM_ExitDebugMode, 'Debug/A: balancierendes Exit gelingt');
  Chk(FastMM_EnterDebugMode, 'Debug/A: echtes Enter gelingt');
  LActiveAfterRealEnter := FastMM_DebugModeActive;
  Chk(FastMM_ExitDebugMode, 'Debug/A: echtes Exit gelingt');
  Chk(LActiveAfterRealEnter, 'Debug/A: echtes Enter AKTIVIERT den Modus (Counter intakt)');
  Chk(not FastMM_DebugModeActive, 'Debug/A: nach echtem Paar wieder inaktiv');
end;

{Szenario B: normale verschachtelte Nutzung ohne externen MM.}
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

  Writeln('#85 Modus-Umschaltung: Vertrags-Regressionstest');
  TestBalancedThroughFailure_Freed;
  TestBalancedThroughFailure_Allocated;
  TestBalancedThroughFailure_Debug;
  TestNormalNesting;

  if GFails = 0 then Writeln('ERGEBNIS: OK')
  else begin Writeln('ERGEBNIS: ', GFails, ' FEHLER'); Halt(1); end;
end.
