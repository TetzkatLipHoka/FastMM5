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
| `FastMM5Diag_MultiThreadStress.dpr` | Parametrisierbarer Multithread-Stresstest: `Threads Iterationen MaxSize Debug(0/1) CrossFree(0/1)`. Druckt am Ende die Usage-Bilanz. |

## Debug-Modus-Adressraumwachstum (Upstream-Bug, im Fork behoben)

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

**Fork-Fix:** Im Debug-Zweig des Medium-Frees prüft ein Span-Walk (`MediumBlockSpanAllBlocksFree`),
ob alle Blöcke des Spans frei sind; wenn ja, wird der Span nach Entfernen seiner gebinnten Blöcke
regulär ans OS zurückgegeben. Der aktuelle Sequential-Feed-Span ist ausgenommen, solange er einen
ungefütterten Rest hat; die Debug-Tripwires lebender Spans bleiben vollständig erhalten. Ergebnis:
8×30000 → ~60 MB Steady-State statt 1,12 GB; 8×120000 läuft ohne Wachstum durch; Normalmodus
byte-identisch. Verifiziert mit Delphi 7, 10 Seattle und 13.1.
