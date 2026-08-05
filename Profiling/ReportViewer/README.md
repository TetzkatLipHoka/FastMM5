# FastMM Report Viewer

A VCL GUI for the files FastMM5 produces. It has one tab per kind of input, and
the tab is picked automatically from the content of the file you open or drop:

* **Leak report / state capture** – modelled on the madExcept bug-report viewer.
  Instead of scrolling a plain text file you get a tree grouped by class,
  sortable by size / count / name, with per-block metadata, expandable
  allocation (and free) stack traces, the memory dump, and double-click
  *jump to source*.
* **Sampling log** – the CSV time series written by `FastMM_SamplingProfiler`,
  plotted over the elapsed time of the run, with the full sample table and the
  per-size-class breakdown underneath.

Everything here lives under `FastMM5\Profiling\ReportViewer\` so it stays
neutral with respect to upstream FastMM merges.

You can **drag a file from Explorer and drop it anywhere on the window** to open
it (the whole client area is a drop target, not just the caption).

## Files

| File | Purpose |
|------|---------|
| `FastMM_LeakReportParser.pas` | VCL-free parser + object model for leak reports and state captures. Reusable on its own (no GUI dependency). |
| `FastMM_SamplingLogParser.pas` | VCL-free parser for the sampling profiler CSVs (summary and detail). Also reusable on its own. |
| `FastMM_ReportViewerForm.pas` | The viewer form. Built entirely in code (no `.dfm`), so it drops into any VCL app and has no designer-resource baggage. |
| `ReportViewerDemo.dpr` | A tiny host app that shows the viewer. |
| `LeakReportParserTest.dpr` | Console self-test for the leak report parser (49 assertions). Exit code 0 = all passed. |
| `SamplingLogParserTest.dpr` | Console self-test for the sampling log parser (73 assertions). Exit code 0 = all passed. |
| `Build.ps1` | Command-line build + tests for Delphi 7 / 10 Seattle / 13.1. |

## What it parses

Three formats, all written against the actual output of the units that produce
them. Which tab a file lands on is decided by its content, not its extension, so
a renamed file still opens correctly.

`FastMM_LeakReportParser` handles the two textual formats of `FastMM5.pas`
(verified against the message templates in that unit):

1. **Event-log leak report** – the shutdown leak report, and anything written
   through `FastMM_LogToFileEvents`. Each entry is wrapped by a
   `--------…YYYY-MM-DD HH:NN:SS…--------` header. Leak-detail entries come from
   `FastMM_MemoryLeakDetailMessage_DebugBlock` / `_NormalBlock`, and the trailing
   summary from `FastMM_MemoryLeakSummaryMessage_*` (the `<size>: <count> x
   <Type>` lines).

2. **State capture** – written by `FastMM_LogStateToFile`
   (`FastMM State Capture:` … `Usage Summary` … `<total> bytes: <Class> x
   <count> (<avg> bytes avg.)`).

The kind is auto-detected. Text encoding is auto-detected too: UTF-8 (the
FastMM default, `teUTF8`, no BOM), UTF-8 with BOM, and UTF-16LE/BE with or
without BOM.

### Multiple reports per file

FastMM happily writes "endless" files: the `<app>_MemoryManager_EventLog.txt`
accumulates one leak-check run per process launch, and
`FastMM_LogStateToFile(..., ATruncateFile := False)` appends state captures. A
file like that is split into its individual reports (state captures at each
`FastMM State Capture:` marker; event-log runs at each summary boundary), each
parsed independently — they are **not** merged. In the GUI a **Report:**
selector appears (enabled when there is more than one) so you can step through
them; the status bar shows how many were found. Headless, use
`TFastMMReportSet`:

```pascal
var
  S: TFastMMReportSet;
  i: Integer;
begin
  S := TFastMMReportSet.Create;
  try
    S.LoadFromFile(AFileName);
    for i := 0 to S.Count - 1 do
      WriteLn(S[i].Describe);   // each S[i] is a full TFastMMLeakReport
  finally
    S.Free;
  end;
end;
```

### Stack traces and jump-to-source

Stack-trace lines produced by the FullDebugMode support DLL
(`FastMM_FullDebugMode.dll`, `LogStackTrace`) have the shape

```
0040BC53[SourceFile.pas][UnitName][Routine][LineNumber]
```

with empty fields omitted. The parser recognises the source file and line by
content and takes the remaining fields positionally (unit, then routine), so
dotted namespace units such as `Vcl.Controls` stay out of the routine column.

Double-clicking a frame that has a source file + line number:

* fires the form's `OnSourceJump` event (set `AHandled := True` to integrate
  with your IDE / editor of choice), otherwise
* falls back to locating the file under the configured **source folders**
  (button *Add source folder…*) and opening it with the OS default handler. The
  line number is shown in the status bar (a generic editor cannot be told a line
  via `ShellExecute`).

## Sampling logs

`FastMM_SamplingLogParser` reads both CSVs that `FastMM_SamplingProfiler` writes:
the **summary** log (one row per sample: process footprint, allocated / reserved
/ overhead bytes, efficiency, the small / medium / large breakdown and the arena
contention counters) and the **detail** log (one row per small block size class
per sample).

Columns are mapped **by header name, not by position**, so a log written by an
older or newer build of the profiler still loads: missing columns read as zero
(`HasContentionCounts` tells you whether the contention columns were there) and
unknown columns are ignored. Numbers are parsed locale independently, because
the profiler always writes a `.` decimal separator. Two runs appended to the
same file are handled (the repeated header line is skipped, not parsed as a
sample), and a run that was cut short by a killed process still loads - the
truncated last row is counted in `MalformedLineCount` rather than aborting.

In the GUI:

* Open the `..._Summary.csv`; if the matching `..._Detail.csv` sits next to it,
  it is loaded too and the *Size classes* tab fills in for whichever sample is
  selected.
* Tick the series to plot in the list on the left. Bytes, block counts, percent
  and contention events do not share a scale, so mixing them labels the axis
  *mixed* - tick **Normalise each series to its own peak (%)** to compare the
  shapes of series with different units.
* Moving the mouse over the plot reads the sample out in the status bar;
  clicking selects it in the table below.

Headless, use `TFastMMSamplingLog`:

```pascal
uses
  FastMM_SamplingLogParser;

var
  L: TFastMMSamplingLog;
  i: Integer;
begin
  L := TFastMMSamplingLog.Create;
  try
    L.LoadFromFile('MemUsage_Summary.csv');
    WriteLn(L.Count, ' samples over ', L.DurationMilliseconds, ' ms');
    WriteLn('peak allocated: ', L.MaxOf(ssAllocated):0:0, ' bytes at sample ',
      L.IndexOfMax(ssAllocated));
    for i := 0 to L.Count - 1 do
      WriteLn(L[i].ElapsedMilliseconds, #9, L[i].AllocatedBytes, #9, L[i].ReservedBytes);
  finally
    L.Free;
  end;
end;
```

## Using the viewer in your own app

```pascal
uses
  FastMM_ReportViewerForm;

// convenience one-liner (non-modal):
ShowFastMMReportViewer('C:\...\MyApp_MemoryManager_EventLog.txt');

// or embed / drive it yourself:
var
  V: TFastMMReportViewerForm;
begin
  V := TFastMMReportViewerForm.Create(Application);
  V.SourcePaths.Add('C:\MyProject\Src');
  V.OnSourceJump := MyIdeJumpHandler;   // optional
  V.LoadReportFile(AFileName);          // any kind; selects the matching tab
  V.Show;
end;
```

`LoadReportFile` detects the kind from the file content. To bypass the detection
(e.g. when you already know what you have), call `LoadSamplingLogFile` for a
profiler CSV, or `LoadReportText` / `LoadSamplingLogText` to display text you
already hold in memory.

The leak report parser can also be used headless:

```pascal
uses
  FastMM_LeakReportParser;

var
  R: TFastMMLeakReport;
begin
  R := TFastMMLeakReport.Create;
  try
    R.LoadFromFile(AFileName);
    if R.Kind = rkLeakReport then
      WriteLn(R.TotalLeakedBytes, ' bytes leaked in ', R.TotalLeakedCount, ' blocks');
    // R.BuildGroups(gsTotalBytesDesc) returns per-class aggregates
  finally
    R.Free;
  end;
end;
```

## Building

The code is D7-compatible (no generics, no anonymous methods, guarded `inline`)
and compiles clean – no errors, warnings or hints – on **Delphi 7**,
**Delphi 10 Seattle** and **Delphi 13.1**.

The easiest route is the build script, which compiles and runs both self-tests
and compiles the demo with every configured compiler:

```powershell
pwsh -File Build.ps1
pwsh -File Build.ps1 -Only Delphi7    # a single compiler
```

Edit the `$Compilers` table at the top of `Build.ps1` if your Delphi
installations are not at `C:\Delphi\7`, `C:\Delphi\10`, `C:\Delphi\13.1`. The
script copies the sources to a short temporary folder before building, because
old `dcc32` (Delphi 7) can crash on very long working-directory paths.

Manual `dcc32` invocation (modern Delphi):

```
dcc32 -B -NSSystem;System.Win;Winapi;Vcl -U<lib\win32\release> ReportViewerDemo.dpr
```

Delphi 7:

```
dcc32 -B -UC:\Delphi\7\Lib ReportViewerDemo.dpr
```

### Project files

No `.dproj` / `.dof` is shipped, because those are compiler-version specific and
this project deliberately targets three very different Delphi versions. Just
open `ReportViewerDemo.dpr` in your IDE (it will generate the project file
for that version), or use `Build.ps1` for headless builds.
