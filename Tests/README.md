# FastMM5 Diagnose-Tests

Kleine Konsolen-Testprogramme, entstanden bei der Delphi-7-Portierung (07/2026). Sie kompilieren
mit allen unterstützten Compilern (getestet: Delphi 7, 10 Seattle, 13.1) und dienen der schnellen
Verifikation nach Änderungen an FastMM5.pas.

Kompilieren (Beispiel Delphi 7):

    dcc32 -B -U"..;<Delphi>\Lib" -O"<Delphi>\Lib" FastMM5Diag_DebugMode.dpr

| Programm | Zweck |
|---|---|
| `FastMM5Diag_DebugMode.dpr` | Basistest Debug-Modus: Header-Layout (SizeOf muss 64 sein), GetMem/FreeMem, Größen-Schleife, Realloc-Kette — einzelthreaded. |
| `FastMM5Diag_SizeClasses.dpr` | Debug-Modus über alle Größenklassen (Small/Medium/Large bis 2 MB) inkl. klassenübergreifender Reallocs. |
| `FastMM5Diag_UsagePerSizeClass.dpr` | Leck-Detektor: hämmert GetMem/FreeMem pro Größenklasse und druckt danach `FastMM_GetUsageSummary` — Allokiert/Overhead müssen konstant bleiben. |
| `FastMM5Diag_MultiThreadStress.dpr` | Parametrisierbarer Multithread-Stresstest: `Threads Iterationen MaxSize Debug(0/1) CrossFree(0/1)`. Druckt am Ende die Usage-Bilanz. Kompiliert mit dcc32 und dcc64 (pointer-breiter Mailbox-Austausch via `XchgPtr`). |
| `FastMM5Diag_SSE2Check.dpr` | Verifiziert, dass SSE2 auch unter Delphi 7 voll aktiv ist: movdqu-Opcodes byte-korrekt assembliert (D7s BASM kann SSE2 nativ — kein db-Hardcoding nötig), CPUID-Erkennung (`Compat_TestSSE`-Logik) wählt die SSE2-Moves, Realloc-Upsize durch alle SSE2-Klassen erhält Inhalte. Kompiliert mit dcc32 und dcc64 (eigene x64-asm-Varianten, plattformspezifische Soll-Opcodes). |
| `FastMM5Diag_DoubleFreeCycle.dpr` | Double-Free-Selbstzyklus (#73): erzwingt per Walk-Lock den Pending-Free-Pfad; zweiter FreeMem muss EInvalidPointer werfen, OHNE den Pending-Link zu korrumpieren. Parameter: Blockgröße (2000/50000/500000 für Small/Medium/Large). |
| `FastMM5Diag_ModeTransition.dpr` | Vertrags-Regressionstest der Modus-Umschaltung (#85): der Nesting-Counter zählt Aufrufe unabhängig vom Rückgabewert (Pierres Vertrag — Begin/Enter immer mit End/Exit balancieren, auch bei False). Installiert einen externen MM (Begin scheitert), balanciert vertragsgemäß und prüft, dass ein anschließendes echtes Begin/End-Paar den Modus wieder korrekt schaltet — fängt insb. die falsche „Rollback bei Fehlschlag"-Idee (negativer Counter). Alle drei Modi + normale Nesting-Semantik. |
| `FastMM5Diag_ScanCoverage.dpr` | Deckungs-Regressionstest für `FastMM_ScanDebugBlocksForCorruption` (Issue #102): Header-Checksumme, Footer-Overrun und Write-after-free, jeweils über Small/Medium/Large — alle 10 Fälle müssen erkannt werden. Zwischen `cad1f04` und `a9526b2` verfehlte der Scan die drei Small-Fälle **still**. Merke: Korruptionstests, die zufällig einen Large Block nehmen, beweisen nichts über den Small-Pfad. |
| `FastMM5Diag_ScanRace.dpr` | Gegenrichtung zu ScanCoverage: n Threads walken Small-Debug-Blöcke durch, ein Thread scannt in der Schleife — **nichts** wird korrumpiert, jede Exception ist also ein Fehlalarm. Parameter: `Sekunden Threads` (Default 20/4). Der Guard in `FastMM_WalkBlocks` tauscht Erkennung gegen Fehlalarm-Risiko, deshalb braucht es beide Richtungen. |
| `FastMM5Diag_ScanHeaderBounds.dpr` | Korrumpiert gezielt die **Größenfelder** (`UserSize`, `StackTraceEntryCount`) — die bestimmen, WO der Scan liest. Erwartung überall: sauberes `EInvalidPointer`, nie eine AV. Hütet damit die Auswertungs-Reihenfolge: Header-Checksumme wird zuerst verglichen, und weil FastMM5 mit abgeschalteter vollständiger Boolean-Auswertung übersetzt, fällt der Footer-Zugriff per Kurzschluss weg. Kein „Small freed"-Fall — siehe Kommentar im Quelltext (das Anlegen des Exception-Objekts bekäme genau den korrumpierten Block aus der Debug-Free-Queue). |
| `FastMM5Diag_SharedMMHardening.dpr` | Shared-MM-Discovery-Härtung (#84): spielt im selben Prozess den Angreifer (legt die `FastMM_PID_*`-Mapping für die eigene PID an), hinterlegt Schadpointer und prüft, dass `FastMM_AttemptToUseSharedMemoryManager` sie abweist statt zu crashen — bei gleichzeitig intakter Adoption eines gültigen Records. **Kein SysUtils/keine Allokation vor den API-Aufrufen** (sonst greift der HasLivePointers-Guard). Ohne Fix: Runtime Error 216. |

## Debug-Modus-Adressraumwachstum (upstream seit 07/2026 per DebugModeOptions steuerbar)

Upstream werden Medium-Blöcke im Debug-Modus beim Freigeben **nicht koalesziert** (bewusst, um
Fill-Pattern/Free-Stacktraces freier Blöcke als Use-after-free-Tripwire zu erhalten). Als
Nebeneffekt kann die "Span komplett frei"-Prüfung nie zuschlagen — Medium-Spans werden im
Debug-Modus **nie** ans OS zurückgegeben. Unter Multithread-Last wird daraus eine Ratsche:
Immer wenn ein Thread die Bins verfehlt, weil die Arena mit dem passenden freien Block gerade
gelockt ist, wird ein neuer 3-MB-Span committet — und bleibt für immer. Der Overhead wächst
unbegrenzt; eine 32-Bit-EXE stirbt mit Runtime Error (Adressraum voll). Einzelthreaded ist das
Verhalten gutartig (konvergiert); Cross-Thread-Frees sind **keine** Zutat (identisches Wachstum
ohne). Reproduziert identisch mit Delphi 7-, 10-Seattle- und 13.1-Builds (2026-07-16):

    FastMM5Diag_MultiThreadStress.exe 8 30000 70000 1 1   -> ~1,12 GB Overhead (upstream)
    FastMM5Diag_MultiThreadStress.exe 8 100000 70000 1 1  -> Crash (2-GB-Adressraum erschöpft)

**Stand nach Upstream-Nachmerge (07/2026):** Upstream hat das Problem in Issue #82 über
`FastMM_Get/SetDebugModeOptions` gelöst. Standardmäßig bleibt das alte Verhalten erhalten
(`dmoNeverMergeFreeMediumBlocks` + `dmoNeverFreeSmallBlockSpans` gesetzt — volle Tripwires,
dafür das oben beschriebene Wachstum). Wer den Debug-Modus unter Multithread-Last dauerhaft
laufen lassen will, leert die Optionen:

    FastMM_SetDebugModeOptions([]);

Damit werden freie Medium-Blöcke wieder koalesziert und Small-Block-Spans freigegeben:
8×30000-Churn → ~12,6 MB Overhead statt ~1,12 GB (verifiziert mit Delphi 7 und 13.1,
Win32+Win64). Trade-off: keine Use-after-free-Tripwires auf freien Medium-Blöcken.
Unabhängig von den Optionen merged Upstream im Debug-Modus jetzt immer nicht-binnbare
Splitter (unterhalb der kleinsten Medium-Blockgröße) beim Free des Vorgängerblocks.
Der frühere Fork-eigene Span-Walk-Fix (`MediumBlockSpanAllBlocksFree`) ist damit obsolet
und wurde beim Nachmerge entfernt.
