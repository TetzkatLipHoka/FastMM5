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

## Bekanntes Verhalten (Upstream, kein Portierungsfehler)

Im Debug-Modus werden Medium-Blöcke beim Freigeben **nicht koalesziert**, wodurch Medium-Spans nie
ans OS zurückgegeben werden. Unter Multithread-Last mit Cross-Thread-Frees wächst der Overhead
unbegrenzt — eine 32-Bit-EXE stirbt dann mit Runtime Error 203/204 (Adressraum voll):

    FastMM5Diag_MultiThreadStress.exe 8 30000 70000 1 1   -> ~1,18 GB Overhead (läuft durch)
    FastMM5Diag_MultiThreadStress.exe 8 100000 70000 1 1  -> Crash (2-GB-Adressraum erschöpft)

Reproduziert identisch mit Delphi 7- und 10-Seattle-Builds (2026-07-16).
