# FastMM5 FPC-Port — Testbatterie

Testprogramme für den Free-Pascal-Port (Branch `fpc-windows-support`), FPC 3.2.2.

Kompilieren (Win32):

    fpc -B -Mdelphi -Fu.. <test>.dpr

Kompilieren (Win64, benötigt den Cross-Compiler ppcrossx64 aus
`fpc-3.2.2.i386-win32.cross.x86_64-win64.exe`, installiert nach C:\FPC\3.2.2):

    fpc -B -Px86_64 -Twin64 -Mdelphi -Fu.. <test>.dpr

| Programm | Zweck |
|---|---|
| `fpctest.dpr` | Bring-up: Installation (state=3), 1-MB-GetMem als exaktes Usage-Delta. |
| `smallfree.dpr` | 1000 Small-Blöcke alloc/free mit externer Header-/Span-Validierung. |
| `smallstress.dpr` | Einzelthread: Größen-Sweep 1..2600 (fwd+rev free), 300k Random-Interleave mit Füllmuster-Check, Realloc-Ketten. |
| `sizefind.dpr` | Größen-Sweep mit Parameter `Startgröße` — grenzt größenabhängige Crashes ein. |
| `walkcheck.dpr` | Sweep mit `FastMM_WalkBlocks`-Heap-Validierung nach jeder Phase; VEH meldet Fault-Datenadresse. Mit `-dFPCDIAG` bauen (aktiviert Konsistenzchecks in FastMM5.pas). |
| `foreign.dpr` + `foreignpre.pas` | Fremd-Block-Forwarding: `foreignpre` alloziert in seiner initialization (VOR FastMM5 in der uses-Klausel) → echte Vor-Installations-Blöcke; testet MemSize/Realloc/Free-Weiterleitung an den FPC-Default-MM. |
| `foreignhdr.dpr` | Dump der FPC-Chunk-Header vor Fremdblöcken (32-bit-Offsets). |
| `span2367.dpr` | Forensik-Tool des Peephole-Bugs (32-bit-Offsets, historisch). |
| `mtstress.dpr` | Multithread: `Threads Iter MaxSize CrossFree` — Füllmuster-Verifikation, Cross-Thread-Frees via Lock-free-Mailbox, Bilanz-Check. |
| `doublealloc.dpr` | Lock-free-Ownership-Tabelle: beweist/widerlegt Double-Handout desselben Blocks. |
| `feedrace.dpr` | Isoliert den Lock-free-Sequential-Feed: parallel allozieren ohne Frees, dann Duplikat-Check aller Pointer. |

## Gefundene und behobene Bugs (Chronik)

1. **Fehlendes Semikolon** im PurePascal-Zweig von `FastMM_GetMem_GetSmallBlock`
   (latenter Upstream-Bug — Delphi kompiliert den Pfad nie).
2. **FPC-Peephole-Load-Widening:** Der i386-Peephole-Optimizer verbreitert maskierte
   Word-Loads zu 32-Bit-Loads; beim Lesen des Span-Trailer-Headers am Ende der
   committeten Region liest das 2 Bytes zu weit → AV, wenn die Folgeseite nicht
   committed ist. Fix: `{$Optimization NOPEEPHOLE}` für die Unit unter FPC.
3. **Fremd-Block-Erkennung:** Das Flag-Word vor FPC-RTL-Blöcken kollidiert
   systematisch mit FastMM-Header-Mustern → strukturelle Ownership-Prüfung
   (`BlockLooksForeign`: Manager-Zeiger muss in FastMMs Manager-Arrays liegen).
4. **Win64:** FPC sagt `CPUX86_64` statt `CPUX64` (Mapping im Scaffold), der
   D2009-Kompat-Block darf auf 64-bit kein `CPUX86` definieren, FPCs
   `TObject.GetHashCode` ist `PtrInt`, und `.noframe`-ASM
   (`CountTrailingZeros32`) wird durch FPCs `BsfDWord`-Intrinsic ersetzt.

## BASM-Reaktivierung unter FPC (2026-07-18)

Die handoptimierten Assembler-Pfade sind unter FPC auf **beiden** Targets
aktiv: X86ASM auf Win32, X64ASM auf Win64.
Notwendige Anpassungen (alle beidseitig gültig):

- `TType.Field(reg - const)`-Memory-Operanden → portable Bracket-Form
  `[reg - const + TType.Field]` (24 Stellen; explizite `word ptr`/`byte ptr`
  bei Immediates, da die Feldtyp-Information verloren geht). Die Typecast-Form
  `TType(reg).Field` versteht FPC nur mit nacktem Register.
- `(A or B)`/`(not A)`-Konstantenausdrücke im asm versteht FPC nicht — die
  betroffenen Dispatcher laufen unter FPC ohnehin in Pascal (s.u.).
- **Stackframe-Falle:** Delphi erzeugt für asm-Routinen mit Stack-Parametern
  einen `push ebp`-Prolog, der Epilog poppt aber nur (kein `mov esp,ebp`) —
  das asm darf ebp als Scratch nutzen. FPCs Epilog macht `mov esp,ebp` →
  Absturz. Fix: `assembler; nostackframe;` unter FPC + Stack-Offset −4
  (betrifft `FastMM_GetMem_GetMediumBlock_AllocateFreeBlockAndUnlockArena`).
- FreeMem/ReallocMem-Dispatcher bleiben unter FPC Pascal
  (`FastMM_ForeignBlockDispatchInPascal`): sie tragen den Fremd-Block-Check,
  den die asm-Dispatcher nicht haben. Alle inneren Hot-Paths sind asm.

X64-Spezifika (FPC-Win64):

- `.noframe` → `assembler; nostackframe;` (ohne den Modifier polstert FPC
  den Stack um 8 Bytes für die Alignment-Invariante — bricht manuelle
  rsp-Offsets und explizite `ret`s).
- `.pushnv rbx/rsi/rdi` + `.params 3` (AllocateFreeBlockAndUnlockArena
  medium): unter FPC exakt repliziert als 3 Pushes + `sub rsp,$20`
  (Gesamt-Displacement 56 → die `[rsp+80]`-Home-Space-Referenzen bleiben
  gültig).
- `lea rdx, Symbol` assembliert FPC als 32-bit-Absolut-Relokation (Linker
  warnt!) — bei FPCs Win64-Imagebase über 4 GB fatal → explizit
  `lea rdx, [rip + Symbol]` unter FPC (Delphi macht RIP-relativ automatisch).

Benchmark BASM vs. PurePascal (bench.dpr, -O2, FPC 3.2.2):
Win32: Small-Block-Ping-Pong **+47–50 %** (84 → 124–127k ops/ms), Batch
+17 %, Realloc +24 %, Mixed +10 %, MT contention-bound unverändert.
Win64: Ping-Pong +10 %, Batch +11–13 %, Realloc +19 %, MT +10–12 %
(moderater: auf x64 sind nur Sequential-Feed, Medium-Bin-Alloc, der
GetMem-Dispatcher und die Moves asm, und FPCs x64-Codegen ist stärker).

## FPC-Trunk-Gegenprobe (3.3.1-Snapshot, 2026-07-18)

- **Das Peephole-Load-Widening ist in Trunk behoben:** dieselbe Quelle, die
  3.2.2 zu `mov eax,[p-2]` (4-Byte-Load) kompiliert, erzeugt unter 3.3.1
  `testw $1,(%eax)` — ein 16-Bit-Zugriff. Kein FPC-Bugreport nötig; der
  `NOPEEPHOLE`-Workaround bleibt für 3.2.2 drin (unter Trunk harmlos).
- **Trunk deckte eine Schwäche der Fremd-Block-Erkennung auf:** Die
  ursprüngliche strukturelle Header-Validierung dereferenzierte aus dem
  (kollidierenden) Header abgeleitete Zeiger — unter Trunks Heap-Layout traf
  das nicht gemapptes Gebiet (AV). Ersetzt durch die **OS-Region-Registry**:
  FastMM registriert jede von VirtualAlloc bezogene Region; Ownership ist ein
  reiner Adressbereichs-Lookup ohne jeden Header-Zugriff.
- Dabei gefunden: Der übliche `p - base < size`-Wraparound-Trick ist unter
  FPC/Win32 **falsch** — FPC promoted die unsigned-Subtraktion nach Int64,
  negative Differenzen bestehen den Größenvergleich. Untere Grenze explizit
  prüfen.

Verifiziert (2026-07-18): alle Tests grün auf FPC 3.2.2 Win32, 3.2.2 Win64
**und** Trunk 3.3.1 (inkl. 16M-Op-MT-Soak mit 32 Threads je Compiler);
FastMM5 kompiliert auf beiden 3.2.2-Targets warnungs- und notefrei.
Delphi-Regression grün auf D7, 10 Seattle, 13.1 (dcc32) und 13.1 Win64
(dcc64).
