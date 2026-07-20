program FastMM5Diag_SharedMMHardening;
{Reproduziert/verifiziert #84: FastMM_AttemptToUseSharedMemoryManager adoptiert einen Pointer aus
 einer vorhersagbar benannten Named-Mapping (Local\FastMM_PID_xxxxxxxx) und dereferenziert ihn als
 TMemoryManagerEx. Ein Fremdprozess in derselben Session kann die Mapping vorab anlegen und einen
 Schadpointer hinterlegen -> Crash. Dieser Test spielt den Angreifer im selben Prozess: er legt die
 Mapping fuer die eigene PID an (aus FastMM-Sicht ununterscheidbar von der eines Fremdprozesses),
 hinterlegt einen boesen Pointer und ruft dann die Adoptions-API auf.
 VOR dem Fix: Access Violation. NACH dem Fix: sauberes False, kein Crash.
 KEIN SysUtils/keine Allokation vor dem Aufruf - sonst greift der HasLivePointers-Guard und die
 Discovery wird gar nicht erst betreten.}
{$APPTYPE CONSOLE}
uses FastMM5, Windows;

type
  {Delphi 7 exportiert TMemoryManagerEx nicht; dort liefert GetMemoryManager den 3-Feld-Record.}
  {$if CompilerVersion >= 18}
  TMMRec = TMemoryManagerEx;
  {$else}
  TMMRec = TMemoryManager;
  {$ifend}

const
  CHex: array[0..15] of AnsiChar = '0123456789ABCDEF';

var
  GName: array[0..25] of AnsiChar;
  GHandle: THandle;
  GView: Pointer;
  GBadTarget: array[0..63] of Pointer; {lesbarer Datenpuffer, aber nicht ausfuehrbar}
  GCur: TMMRec;
  GGoodRec: array[0..5] of Pointer; {gueltiger 6-Slot-Record mit echten Code-Entrypoints}

procedure BuildName;
const
  CPrefix: array[0..16] of AnsiChar = 'Local\FastMM_PID_';
var
  i: Integer;
  LPid: Cardinal;
begin
  for i := 0 to 16 do GName[i] := CPrefix[i];
  LPid := GetCurrentProcessId;
  for i := 0 to 7 do
    GName[24 - i] := CHex[(LPid shr (i * 4)) and $F];
  GName[25] := #0;
end;

{Legt die Mapping fuer die eigene PID an und hinterlegt APlant als "Shared-MM-Pointer".}
function PlantPointer(APlant: Pointer): Boolean;
begin
  Result := False;
  GHandle := CreateFileMappingA(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, SizeOf(Pointer), @GName[0]);
  if GHandle = 0 then Exit;
  GView := MapViewOfFile(GHandle, FILE_MAP_WRITE, 0, 0, 0);
  if GView = nil then
  begin
    CloseHandle(GHandle); GHandle := 0;
    Exit;
  end;
  PPointer(GView)^ := APlant;
  Result := True;
end;

procedure Unplant;
begin
  if GView <> nil then begin UnmapViewOfFile(GView); GView := nil; end;
  if GHandle <> 0 then begin CloseHandle(GHandle); GHandle := 0; end;
end;

var
  R1, R2, R3: Boolean;
  LPlant1, LPlant2, LPlant3: Boolean;
  i: Integer;
begin
  {WICHTIG: Bis der letzte AttemptToUse-Aufruf durch ist, darf NICHTS ueber FastMM allokiert werden
   (auch kein Writeln - dessen RTL-Textpuffer wird lazy alloziert). Sonst greift der interne
   HasLivePointers-Guard, die Discovery wird uebersprungen und der Test misst den falschen Pfad
   (samt "cannot switch"-Meldung). Deshalb erst ALLE drei Szenarien fahren, Ergebnisse merken, dann
   ausgeben. Event-Meldeboxen/Logs werden vorsorglich abgeschaltet (reine Set-/Var-Zuweisung, keine
   Allokation).}
  FastMM_MessageBoxEvents := [];
  FastMM_LogToFileEvents := [];
  FastMM_OutputDebugStringEvents := [];

  BuildName;

  {Gueltigen Record fuer Szenario 3 vorbereiten (GetMemoryManager allokiert nicht).}
  GetMemoryManager(GCur);
  GGoodRec[0] := PPointerArray(@GCur)[0];
  GGoodRec[1] := PPointerArray(@GCur)[1];
  GGoodRec[2] := PPointerArray(@GCur)[2];
  GGoodRec[3] := GGoodRec[0];
  GGoodRec[4] := GGoodRec[0];
  GGoodRec[5] := GGoodRec[0];
  for i := 0 to High(GBadTarget) do GBadTarget[i] := Pointer(i + 1);

  {Szenario 1: klassischer Schadpointer (nicht lesbar).}
  LPlant1 := PlantPointer(Pointer(1));
  R1 := FastMM_AttemptToUseSharedMemoryManager;
  Unplant;

  {Szenario 2: lesbarer, aber nicht ausfuehrbarer Datenpuffer.}
  LPlant2 := PlantPointer(@GBadTarget[0]);
  R2 := FastMM_AttemptToUseSharedMemoryManager;
  Unplant;

  {Szenario 3 (positive Kontrolle): gueltiger Record mit echten, ausfuehrbaren Entrypoints - MUSS
   adoptiert werden (Rueckwaertskompatibilitaet). Zuletzt, da eine Adoption den Zustand aendert.}
  LPlant3 := PlantPointer(@GGoodRec[0]);
  R3 := FastMM_AttemptToUseSharedMemoryManager;
  Unplant;

  {Ab hier ist Allokation/Ausgabe wieder unbedenklich.}
  if not (LPlant1 and LPlant2 and LPlant3) then begin Writeln('FEHLER: Mapping-Erzeugung fehlgeschlagen'); Halt(3); end;

  if R1 then begin Writeln('FAIL: Szenario 1 - Schadpointer (1) wurde adoptiert'); Halt(1); end;
  Writeln('ok   Szenario 1: nicht-lesbarer Schadpointer abgewiesen (kein Crash)');

  if R2 then begin Writeln('FAIL: Szenario 2 - lesbarer Nicht-Code-Puffer wurde adoptiert'); Halt(1); end;
  Writeln('ok   Szenario 2: lesbarer, nicht-ausfuehrbarer Puffer abgewiesen');

  if not R3 then begin Writeln('FAIL: Szenario 3 - gueltiger Record faelschlich abgewiesen (Kompat-Bruch)'); Halt(1); end;
  Writeln('ok   Szenario 3: gueltiger Record mit Code-Entrypoints adoptiert (Kompat intakt)');

  Writeln('ERGEBNIS: OK');
end.
