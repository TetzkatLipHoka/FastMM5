# Fork-spezifische Test-Notizen

`Tests/README.md` beschreibt die Suite, die auch upstream angeboten ist (englisch, damit sie
dort ohne Anpassung passt). Diese Datei sammelt, was nur den Fork betrifft — sie kollidiert
deshalb bei keinem Nachmerge.

## Zusätzliche Testprogramme im Fork

| Programm | Zweck | Branch |
|---|---|---|
| `FastMM5Diag_SharedMMHardening.dpr` | Shared-MM-Discovery-Härtung (#84): spielt im selben Prozess den Angreifer (legt die `FastMM_PID_*`-Mapping für die eigene PID an), hinterlegt Schadpointer und prüft, dass `FastMM_AttemptToUseSharedMemoryManager` sie abweist statt zu crashen — bei gleichzeitig intakter Adoption eines gültigen Records. **Kein SysUtils/keine Allokation vor den API-Aufrufen** (sonst greift der HasLivePointers-Guard). Ohne Fix: Runtime Error 216. Fällt auf pristine Upstream durch, gehört deshalb nicht in die Suite. | ab `delphi2009-support` |
| `FastMM5Diag_SSE2Check.dpr` | Verifiziert, dass SSE2 auch unter Delphi 7 voll aktiv ist: movdqu-Opcodes byte-korrekt assembliert (D7s BASM kann SSE2 nativ — kein db-Hardcoding nötig), CPUID-Erkennung wählt die SSE2-Moves, Realloc-Upsize durch alle SSE2-Klassen erhält Inhalte. Rein D7-spezifisch. | `fpc-windows-support` |
| `FastMM5Diag_ProfilingMode.dpr` | Leichtgewichtiger Profiling-Modus (`dmoNoBlockFillPatterns`/`dmoNoBlockCheckSums`): Referenzverhalten, Fill/Checksummen wirklich aus, Options-Wechsel bei aktivem Debug-Modus (Blöcke behalten ihre Features), Timing-Vergleich. Braucht PR #92. | `profiling-toolkit` |

Die alten deutschen `FastMM5Diag_*`-Programme für DebugMode, SizeClasses, UsagePerSizeClass,
MultiThreadStress, DoubleFreeCycle, ModeTransition und die drei Scan-Tests sind durch die
`FastMM5Test_*`-Suite ersetzt worden (englisch, echte Assertions, Exit-Code = Anzahl Fehler).

## Delphi 7 in der Suite

`RunTests.ps1` findet Compiler selbst, aber nur die der Embarcadero-Ära (Registry-Zweig
`Embarcadero\BDS`). **D7 registriert sich unter `Borland\Delphi` und wird deshalb nicht
gefunden** — dafür gibt es `Tests/CompilerPaths.txt` (gitignored, liegt lokal schon):

    D7      = C:\Delphi\7
    Seattle = C:\Delphi\10
    D13.1   = C:\Delphi\13.1

Damit läuft die Suite unverändert auch unter D7 (`-Only D7`); zwei Kleinigkeiten im Runner
machen das möglich und sind bewusst auch upstream drin, damit die Datei in Fork und Upstream
identisch bleibt: `-O` wird mitgegeben (D7s `ZLibMinimal` deklariert externe Routinen aus
.obj-Dateien) und es gibt einen Fallback auf das flache `lib`-Verzeichnis (D7 hat kein
`lib\win32\release`). D7/Win64 wird automatisch übersprungen, weil kein `dcc64` existiert.

Stand: **45/45 Läufe grün** (D7 Win32, Seattle + 13.1 je Win32/Win64).

Beim manuellen Aufruf aus dem `Tests`-Verzeichnis starten (die `in '...'`-Klausel wird relativ
zum Arbeitsverzeichnis aufgelöst) und **nicht** aus einem sehr langen Pfad — altes `dcc32`
bleibt dort ohne Fehlermeldung hängen.

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
