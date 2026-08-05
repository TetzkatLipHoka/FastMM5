(*

  FastMM_ReportViewerForm
  -----------------------

  A VCL viewer for the files FastMM5 produces.  It has one tab per kind of
  input, and the tab is selected automatically from the content of the file
  that is opened (or dropped onto the window).

  Leak reports and state captures, modelled on the madExcept bug-report viewer:

    - A tree on the left, grouped by class / content type.  Each group expands
      to the individual leaked blocks.
    - Sortable by total size, instance count or class name.
    - A details pane on the right showing the selected block's metadata plus its
      allocation (and, if present, free) stack traces in a grid, and the raw
      memory dump on a second tab.
    - Double-clicking a stack frame that carries source information jumps to the
      source line (via the OnSourceJump event, or a best-effort ShellExecute
      fallback that searches the configured source folders).

  Sampling logs, i.e. the CSV time series written by FastMM_SamplingProfiler:

    - A plot of the selected series over the elapsed time of the run, with the
      sample under the mouse read out in the status bar and click-to-select
      into the table below.
    - A checklist to pick the series;  since bytes, block counts, percent and
      contention events do not share a scale, mixing them is allowed but the
      axis then says so - use "normalise each series to its own peak" to
      compare shapes across units.
    - The full sample table underneath, and, when the matching detail log is
      found next to it, a per-size-class table for the selected sample.

  The whole UI is built in code (the form uses CreateNew, so there is no .dfm).
  That keeps the unit a single self-contained file, avoids designer-resource
  differences between Delphi versions, and keeps it neutral with respect to
  upstream FastMM merges.

  Compiles on Delphi 7, Delphi 10 Seattle and Delphi 13.1.  No generics, no
  anonymous methods, inline directives guarded.

*)

unit FastMM_ReportViewerForm;

{FileCtrl / SelectDirectory are Windows-only by design; this viewer is a VCL
 Windows tool, so silence the platform-portability warnings.}
{$WARN UNIT_PLATFORM OFF}
{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ComCtrls, ExtCtrls, FileCtrl, Contnrs, CheckLst,
  {$IF CompilerVersion >= 24} System.UITypes, {$IFEND}
  FastMM_LeakReportParser, FastMM_SamplingLogParser;

type
  {Fired when the user double-clicks a stack frame with a known source
   location.  Set AHandled to True to suppress the built-in ShellExecute
   fallback (e.g. when integrating with the IDE).}
  TFastMMSourceJumpEvent = procedure(Sender: TObject; const ASourceFile: string;
    ALineNumber: Integer; var AHandled: Boolean) of object;

  TFastMMReportViewerForm = class(TForm)
  private
    FReportSet: TFastMMReportSet;
    FReport: TFastMMLeakReport;   {the currently displayed report; not owned}
    FSourcePaths: TStringList;
    FSortOrder: TFastMMGroupSortOrder;
    FOnSourceJump: TFastMMSourceJumpEvent;
    FDropForwarders: TObjectList; {keeps child controls forwarding WM_DROPFILES}
    FDropRegistered: Boolean;
    {The number of class groups in the tree, for the summary line.}
    FGroupCount: Integer;

    {UI, all created in BuildUI.}
    FTopPanel: TPanel;
    FBtnOpen: TButton;
    FBtnSample1: TButton;
    FBtnSample2: TButton;
    FSortLabel: TLabel;
    FSortCombo: TComboBox;
    FBtnExpand: TButton;
    FBtnCollapse: TButton;
    FBtnSourceFolder: TButton;
    FReportLabel: TLabel;
    FReportCombo: TComboBox;
    FSummaryLabel: TLabel;

    FTree: TTreeView;
    FSplitter: TSplitter;
    FRightPanel: TPanel;
    FInfoMemo: TMemo;
    FInfoSplitter: TSplitter;
    FPageControl: TPageControl;
    FStackTab: TTabSheet;
    FDumpTab: TTabSheet;
    FStackList: TListView;
    FDumpMemo: TMemo;
    FStatus: TStatusBar;
    FOpenDialog: TOpenDialog;

    {Sampling log tab.}
    FSamplingLog: TFastMMSamplingLog;
    FOuterPages: TPageControl;
    FLeakTab: TTabSheet;
    FSamplingTab: TTabSheet;
    FSampTopPanel: TPanel;
    FSampSummaryLabel: TLabel;
    FSampSeriesLabel: TLabel;
    FSampSeriesList: TCheckListBox;
    FSampNormalize: TCheckBox;
    FSampChartPanel: TPanel;
    FSampChart: TPaintBox;
    FSampSplitter: TSplitter;
    FSampBottomPages: TPageControl;
    FSampTableTab: TTabSheet;
    FSampDetailTab: TTabSheet;
    FSampGrid: TListView;
    FSampDetailGrid: TListView;
    {The sample the mouse is over (-1 = none);  drawn as a marker line.}
    FSampHotIndex: Integer;

    procedure BuildUI;
    procedure BuildSamplingTab;
    procedure PopulateReportCombo;
    procedure SelectReport(AIndex: Integer);
    procedure PopulateTree;
    procedure ShowGroup(AGroup: TFastMMGroup);
    procedure ShowBlock(ABlock: TFastMMLeakBlock);
    procedure ShowStateEntryFor(AGroup: TFastMMGroup);
    procedure FillStackList(AAllocStack, AFreeStack: TObjectList);
    procedure ClearDetails;
    function SortOrderFromCombo: TFastMMGroupSortOrder;
    function FindSourceFile(const AFileName: string): string;
    procedure JumpToFrame(AFrame: TFastMMStackFrame);
    procedure UpdateSummaryLabel;

    {Event handlers.}
    procedure DoOpenClick(Sender: TObject);
    procedure DoSample1Click(Sender: TObject);
    procedure DoSample2Click(Sender: TObject);
    procedure DoSortChange(Sender: TObject);
    procedure DoExpandClick(Sender: TObject);
    procedure DoCollapseClick(Sender: TObject);
    procedure DoAddSourceFolderClick(Sender: TObject);
    procedure DoReportChange(Sender: TObject);
    procedure DoTreeChange(Sender: TObject; Node: TTreeNode);
    procedure DoStackDblClick(Sender: TObject);

    {Sampling log tab.}
    procedure PopulateSamplingSeriesList;
    procedure PopulateSamplingGrid;
    procedure PopulateSamplingDetailGrid(ASampleIndex: Int64);
    procedure UpdateSamplingSummaryLabel;
    function SamplingChartRect: TRect;
    function SamplingSampleAt(AX: Integer): Integer;
    function SelectedSeriesMaximum: Double;
    function SelectedSeriesUnit: string;
    procedure DoSampOpenClick(Sender: TObject);
    procedure DoSampSampleClick(Sender: TObject);
    procedure DoSampSeriesClick(Sender: TObject);
    procedure DoSampChartPaint(Sender: TObject);
    procedure DoSampChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure DoSampChartMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    {TControl.OnMouseLeave only exists from Delphi 2009 on;  without it the
     marker simply stays on the last sample until the mouse returns.}
    {$IF CompilerVersion >= 20}
    procedure DoSampChartMouseLeave(Sender: TObject);
    {$IFEND}
    procedure DoSampGridSelect(Sender: TObject; Item: TListItem; Selected: Boolean);

    {Windows shell drag & drop: accept a report file dropped onto the window.}
    procedure HandleDroppedHandle(ADrop: THandle);
    procedure RegisterDropTargets;
    procedure WMDropFiles(var AMessage: TWMDropFiles); message WM_DROPFILES;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    {Loads and displays any file this viewer understands:  a leak report, a
     state capture, or a sampling profiler CSV.  The kind is detected from the
     content and the matching tab is brought to front.}
    procedure LoadReportFile(const AFileName: string);
    {Loads and displays report text directly (used for the built-in samples).}
    procedure LoadReportText(const AText, ADisplayName: string);
    {Loads a sampling profiler CSV.  If the matching detail log sits next to it
     (..._Summary.csv / ..._Detail.csv) it is loaded as well.}
    procedure LoadSamplingLogFile(const AFileName: string);
    procedure LoadSamplingLogText(const AText, ADisplayName: string);

    property Report: TFastMMLeakReport read FReport;
    property SamplingLog: TFastMMSamplingLog read FSamplingLog;
    property SourcePaths: TStringList read FSourcePaths;
    property OnSourceJump: TFastMMSourceJumpEvent read FOnSourceJump write FOnSourceJump;
  end;

{Convenience: create, show (non-modal) and return a viewer for AFileName.
 Pass an empty string to open with no report loaded.}
function ShowFastMMReportViewer(const AFileName: string): TFastMMReportViewerForm;

{Format-exact sample generators (handy for demos and manual testing).  They
 mirror the FastMM5.pas templates, and for the sampling log the CSV layout
 written by FastMM_SamplingProfiler.pas.}
function FastMMSampleLeakReport: string;
function FastMMSampleStateCapture: string;
function FastMMSampleSamplingLog: string;

implementation

uses
  ShellAPI;

const
  CRLF = #13#10;

type
  {Intercepts WM_DROPFILES on a single child control and forwards it to the
   owning viewer form, leaving all other messages to the control's original
   window procedure.  This is how the whole client area (tree, memos, list, ...)
   becomes a drop target - DragAcceptFiles only affects the exact window under
   the cursor, and messages do not bubble to the parent.}
  TFastMMDropForwarder = class(TObject)
  private
    FForm: TFastMMReportViewerForm;
    FControl: TWinControl;
    FOldWindowProc: TWndMethod;
    procedure NewWindowProc(var AMessage: TMessage);
  public
    constructor Create(AForm: TFastMMReportViewerForm; AControl: TWinControl);
    destructor Destroy; override;
  end;

constructor TFastMMDropForwarder.Create(AForm: TFastMMReportViewerForm;
  AControl: TWinControl);
begin
  inherited Create;
  FForm := AForm;
  FControl := AControl;
  DragAcceptFiles(FControl.Handle, True);
  FOldWindowProc := FControl.WindowProc;
  FControl.WindowProc := NewWindowProc;
end;

destructor TFastMMDropForwarder.Destroy;
begin
  if (FControl <> nil) and FControl.HandleAllocated then
    DragAcceptFiles(FControl.Handle, False);
  if (FControl <> nil) and Assigned(FOldWindowProc) then
    FControl.WindowProc := FOldWindowProc;
  inherited Destroy;
end;

procedure TFastMMDropForwarder.NewWindowProc(var AMessage: TMessage);
begin
  if AMessage.Msg = WM_DROPFILES then
  begin
    FForm.HandleDroppedHandle(THandle(AMessage.WParam));
    DragFinish(THandle(AMessage.WParam));
    AMessage.Result := 0;
  end
  else
    FOldWindowProc(AMessage);
end;

{--------------------------------------------------------------------------}
{ Helpers                                                                   }
{--------------------------------------------------------------------------}

function DisplayContentType(const AContentType: string): string;
begin
  if Trim(AContentType) = '' then
    Result := '(unknown)'
  else
    Result := AContentType;
end;

function ThousandsInt(AValue: Int64): string;
begin
  Result := Format('%.0n', [AValue + 0.0]);
end;

function FastMMSampleLeakReport: string;
var
  LHeader: string;
begin
  LHeader := StringOfChar('-', 32) + '2026-07-17 14:32:01' + StringOfChar('-', 32) + CRLF;
  Result :=
    LHeader +
    'A memory block has been leaked. The size is: 48' + CRLF + CRLF +
    'This block was allocated on 2026-07-17 14:31:55 by thread 0x1A2C, and the stack trace (return addresses) at the time was:' + CRLF +
    '0040BC53[Unit1.pas][Unit1][TForm1.Button1Click][42]' + CRLF +
    '004AB1C7[Vcl.Controls.pas][Vcl.Controls][TControl.Click][7100]' + CRLF +
    '77AABBCC[kernel32.dll]' + CRLF + CRLF +
    'The block is currently used for an object of class: TStringList' + CRLF + CRLF +
    'The allocation number is: 123456' + CRLF + CRLF +
    'Current memory dump of 48 bytes starting at pointer address 0x02A4C010:' + CRLF +
    '0x02A4C010: 90 4B 4A 00 00 00 00 00 - 10 C0 A4 02 03 00 00 00  .KJ.......?.....' + CRLF + CRLF +
    LHeader +
    'A memory block has been leaked. The size is: 48' + CRLF + CRLF +
    'This block was allocated on 2026-07-17 14:31:56 by thread 0x1A2C, and the stack trace (return addresses) at the time was:' + CRLF +
    '0040BC53[Unit1.pas][Unit1][TForm1.Button1Click][43]' + CRLF +
    '004AB1C7[Vcl.Controls.pas][Vcl.Controls][TControl.Click][7100]' + CRLF + CRLF +
    'The block is currently used for an object of class: TStringList' + CRLF + CRLF +
    'The allocation number is: 123457' + CRLF + CRLF +
    'Current memory dump of 48 bytes starting at pointer address 0x02A4C080:' + CRLF +
    '0x02A4C080: 90 4B 4A 00 00 00 00 00 - 80 C0 A4 02 03 00 00 00  .KJ.......?.....' + CRLF + CRLF +
    LHeader +
    'A memory block has been leaked. The size is: 20' + CRLF + CRLF +
    'This block was allocated on 2026-07-17 14:31:57 by thread 0x1A2C, and the stack trace (return addresses) at the time was:' + CRLF +
    '0040C111[Unit1.pas][Unit1][TForm1.MakeStringLeak][88]' + CRLF +
    '0040D222[Unit1.pas][Unit1][TForm1.FormCreate][15]' + CRLF + CRLF +
    'The block is currently used for an object of class: AnsiString' + CRLF + CRLF +
    'The allocation number is: 123458' + CRLF + CRLF +
    'Current memory dump of 20 bytes starting at pointer address 0x02A4D000:' + CRLF +
    '0x02A4D000: 48 65 6C 6C 6F 20 77 6F - 72 6C 64 00              Hello world.' + CRLF + CRLF +
    LHeader +
    'This application has leaked memory. The leaks ordered by size are:' + CRLF + CRLF +
    '20: 1 x AnsiString' + CRLF +
    '48: 2 x TStringList' + CRLF + CRLF +
    'Memory leak detail was logged to C:\Temp\MyApp_MemoryManager_EventLog.txt' + CRLF;
end;

function FastMMSampleStateCapture: string;
begin
  Result :=
    'FastMM State Capture:' + CRLF +
    '---------------------' + CRLF + CRLF +
    'Timestamp:' + CRLF +
    '2026-07-17 14:32:01' + CRLF + CRLF +
    'Usage Summary:' + CRLF +
    '12345K Allocated' + CRLF +
    '678K Overhead' + CRLF +
    '94% Efficiency' + CRLF + CRLF +
    'Usage Detail:' + CRLF +
    '2048 bytes: TStringList x 4 (512 bytes avg.)' + CRLF +
    '1024 bytes: AnsiString x 8 (128 bytes avg.)' + CRLF +
    '768 bytes: TList x 3 (256 bytes avg.)' + CRLF +
    '512 bytes: Unknown x 2 (256 bytes avg.)' + CRLF;
end;

function FastMMSampleSamplingLog: string;
const
  CSampleCount = 60;
  CIntervalMs = 250;
var
  i: Integer;
  LAllocated, LReserved, LOverhead, LUsage: Int64;
  LSmallAlloc, LMediumAlloc, LLargeAlloc: Int64;
  LEfficiency: Double;
  LContention: Int64;
  LText: string;
  LSeconds: Integer;
begin
  {A grow-then-shrink run:  allocation ramps up over the first two thirds and is
   released again over the last third, while the reserved address space follows
   with a lag and does not fall all the way back - the classic shape the plot is
   meant to make obvious.}
  Result :=
    'sample_index,wall_clock,elapsed_ms,mm_usage_bytes,allocated_bytes,reserved_bytes,overhead_bytes,'
    + 'efficiency_pct,small_alloc_bytes,small_reserved_bytes,small_block_count,medium_alloc_bytes,'
    + 'medium_reserved_bytes,medium_block_count,large_alloc_bytes,large_reserved_bytes,large_block_count,'
    + 'small_contention,medium_contention,large_contention' + CRLF;

  for i := 0 to CSampleCount - 1 do
  begin
    if i <= 40 then
      LAllocated := 2 * 1024 * 1024 + Int64(i) * 1200 * 1024
    else
      LAllocated := 2 * 1024 * 1024 + Int64(40) * 1200 * 1024 - Int64(i - 40) * 2200 * 1024;
    if LAllocated < 2 * 1024 * 1024 then
      LAllocated := 2 * 1024 * 1024;

    {Reserved trails the peak:  freed spans are not handed back immediately.}
    if i <= 40 then
      LReserved := LAllocated + 3 * 1024 * 1024 + Int64(i) * 90 * 1024
    else
      LReserved := 2 * 1024 * 1024 + Int64(40) * 1200 * 1024 + 3 * 1024 * 1024 + Int64(40) * 90 * 1024
        - Int64(i - 40) * 700 * 1024;
    if LReserved < LAllocated then
      LReserved := LAllocated;

    LOverhead := LReserved - LAllocated;
    LUsage := LReserved + 2 * 1024 * 1024;
    if LReserved > 0 then
      LEfficiency := 100.0 * LAllocated / LReserved
    else
      LEfficiency := 100.0;

    LSmallAlloc := LAllocated div 2;
    LMediumAlloc := LAllocated div 3;
    LLargeAlloc := LAllocated - LSmallAlloc - LMediumAlloc;
    {Contention is cumulative, so it only ever rises;  it rises fastest while
     the workload is allocating hardest.}
    if i <= 40 then
      LContention := Int64(i) * Int64(i) div 8
    else
      LContention := Int64(40) * 40 div 8 + Int64(i - 40);

    LSeconds := (i * CIntervalMs) div 1000;

    LText := IntToStr(i);
    LText := LText + ',' + Format('2026-07-23 11:%.2d:%.2d.%.3d',
      [15 + LSeconds div 60, LSeconds mod 60, (i * CIntervalMs) mod 1000]);
    LText := LText + ',' + IntToStr(i * CIntervalMs);
    LText := LText + ',' + IntToStr(LUsage);
    LText := LText + ',' + IntToStr(LAllocated);
    LText := LText + ',' + IntToStr(LReserved);
    LText := LText + ',' + IntToStr(LOverhead);
    {The profiler writes two decimals with a '.' separator regardless of the
     locale, so build the same shape here rather than using FloatToStr.}
    LText := LText + ',' + IntToStr(Trunc(LEfficiency)) + '.' +
      Format('%.2d', [Trunc(LEfficiency * 100) mod 100]);
    LText := LText + ',' + IntToStr(LSmallAlloc);
    LText := LText + ',' + IntToStr(LSmallAlloc + 512 * 1024);
    LText := LText + ',' + IntToStr(LSmallAlloc div 96);
    LText := LText + ',' + IntToStr(LMediumAlloc);
    LText := LText + ',' + IntToStr(LMediumAlloc + 256 * 1024);
    LText := LText + ',' + IntToStr(LMediumAlloc div 12000);
    LText := LText + ',' + IntToStr(LLargeAlloc);
    LText := LText + ',' + IntToStr(LLargeAlloc + 64 * 1024);
    LText := LText + ',' + IntToStr(LLargeAlloc div 300000);
    LText := LText + ',' + IntToStr(LContention);
    LText := LText + ',' + IntToStr(LContention div 4);
    LText := LText + ',' + IntToStr(LContention div 20);
    Result := Result + LText + CRLF;
  end;
end;

{--------------------------------------------------------------------------}
{ TFastMMReportViewerForm                                               }
{--------------------------------------------------------------------------}

constructor TFastMMReportViewerForm.Create(AOwner: TComponent);
begin
  {CreateNew: build the whole form in code, no .dfm resource.}
  inherited CreateNew(AOwner);
  FReportSet := TFastMMReportSet.Create;
  FReport := nil;
  FSamplingLog := TFastMMSamplingLog.Create;
  FSourcePaths := TStringList.Create;
  FDropForwarders := TObjectList.Create(True);
  FSortOrder := gsTotalBytesDesc;
  FSampHotIndex := -1;

  Caption := 'FastMM Report Viewer';
  Width := 1000;
  Height := 680;
  Position := poScreenCenter;
  BuildUI;
  UpdateSummaryLabel;
end;

destructor TFastMMReportViewerForm.Destroy;
begin
  {Free the forwarders before the child controls (inherited) so each can restore
   its original window procedure on a still-valid control.}
  FDropForwarders.Free;
  FSourcePaths.Free;
  FSamplingLog.Free;
  FReportSet.Free;   {owns the reports; FReport is only a pointer into it}
  inherited Destroy;
end;

procedure TFastMMReportViewerForm.CreateWnd;
begin
  inherited CreateWnd;
  {Register the window as a drop target once its handle exists (and again after
   any handle recreation).}
  DragAcceptFiles(Handle, True);
end;

procedure TFastMMReportViewerForm.DestroyWnd;
begin
  if HandleAllocated then
    DragAcceptFiles(Handle, False);
  inherited DestroyWnd;
end;

procedure TFastMMReportViewerForm.HandleDroppedHandle(ADrop: THandle);
var
  LCount, LLen: Integer;
  LFileName: string;
begin
  LCount := DragQueryFile(ADrop, $FFFFFFFF, nil, 0);
  if LCount > 0 then
  begin
    {Only one file can be shown at a time; take the first and note if more were
     dropped.}
    LLen := DragQueryFile(ADrop, 0, nil, 0);
    SetLength(LFileName, LLen);
    DragQueryFile(ADrop, 0, PChar(LFileName), LLen + 1);
    try
      LoadReportFile(LFileName);
      if LCount > 1 then
        FStatus.SimpleText := FStatus.SimpleText +
          Format('   (%d files dropped; showing the first)', [LCount]);
    except
      on E: Exception do
        MessageDlg('Could not load the dropped file:' + sLineBreak + sLineBreak +
          LFileName + sLineBreak + sLineBreak + E.Message, mtError, [mbOK], 0);
    end;
  end;
end;

procedure TFastMMReportViewerForm.WMDropFiles(var AMessage: TWMDropFiles);
begin
  HandleDroppedHandle(AMessage.Drop);
  DragFinish(AMessage.Drop);
  AMessage.Result := 0;
end;

procedure TFastMMReportViewerForm.DoShow;
begin
  inherited DoShow;
  {Child windows only receive WM_DROPFILES if they themselves are registered as
   drop targets, so hook the ones that cover the client area.  Their handles
   exist by the time the form is shown.}
  if not FDropRegistered then
  begin
    RegisterDropTargets;
    FDropRegistered := True;
  end;
end;

procedure TFastMMReportViewerForm.RegisterDropTargets;

  procedure Hook(AControl: TWinControl);
  begin
    if AControl <> nil then
      FDropForwarders.Add(TFastMMDropForwarder.Create(Self, AControl));
  end;

begin
  Hook(FTree);
  Hook(FRightPanel);
  Hook(FInfoMemo);
  Hook(FStackList);
  Hook(FDumpMemo);
  Hook(FTopPanel);
  Hook(FStatus);
  Hook(FOuterPages);
  Hook(FSampTopPanel);
  Hook(FSampSeriesList);
  Hook(FSampChartPanel);
  Hook(FSampGrid);
  Hook(FSampDetailGrid);
end;

procedure TFastMMReportViewerForm.BuildUI;
var
  LCol: TListColumn;
begin
  {--- status bar (shared by both tabs, so it lives on the form) ---}
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  FStatus.SimpleText := 'Ready.';

  {--- one tab per kind of input ---}
  FOuterPages := TPageControl.Create(Self);
  FOuterPages.Parent := Self;
  FOuterPages.Align := alClient;

  FLeakTab := TTabSheet.Create(Self);
  FLeakTab.PageControl := FOuterPages;
  FLeakTab.Caption := 'Leak report / state capture';

  FSamplingTab := TTabSheet.Create(Self);
  FSamplingTab.PageControl := FOuterPages;
  FSamplingTab.Caption := 'Sampling log';

  {--- top toolbar ---}
  FTopPanel := TPanel.Create(Self);
  FTopPanel.Parent := FLeakTab;
  FTopPanel.Align := alTop;
  FTopPanel.Height := 96;
  FTopPanel.BevelOuter := bvNone;
  FTopPanel.BorderWidth := 4;

  FBtnOpen := TButton.Create(Self);
  FBtnOpen.Parent := FTopPanel;
  FBtnOpen.SetBounds(6, 8, 90, 25);
  FBtnOpen.Caption := 'Open...';
  FBtnOpen.OnClick := DoOpenClick;

  FBtnSample1 := TButton.Create(Self);
  FBtnSample1.Parent := FTopPanel;
  FBtnSample1.SetBounds(102, 8, 150, 25);
  FBtnSample1.Caption := 'Sample leak report';
  FBtnSample1.OnClick := DoSample1Click;

  FBtnSample2 := TButton.Create(Self);
  FBtnSample2.Parent := FTopPanel;
  FBtnSample2.SetBounds(258, 8, 150, 25);
  FBtnSample2.Caption := 'Sample state capture';
  FBtnSample2.OnClick := DoSample2Click;

  FSortLabel := TLabel.Create(Self);
  FSortLabel.Parent := FTopPanel;
  FSortLabel.SetBounds(430, 13, 30, 17);
  FSortLabel.Caption := 'Sort:';

  FSortCombo := TComboBox.Create(Self);
  FSortCombo.Parent := FTopPanel;
  FSortCombo.SetBounds(462, 9, 170, 24);
  FSortCombo.Style := csDropDownList;
  FSortCombo.Items.Add('Total size (descending)');
  FSortCombo.Items.Add('Instance count (descending)');
  FSortCombo.Items.Add('Class name (A-Z)');
  FSortCombo.ItemIndex := 0;
  FSortCombo.OnChange := DoSortChange;

  FBtnExpand := TButton.Create(Self);
  FBtnExpand.Parent := FTopPanel;
  FBtnExpand.SetBounds(644, 8, 80, 25);
  FBtnExpand.Caption := 'Expand all';
  FBtnExpand.OnClick := DoExpandClick;

  FBtnCollapse := TButton.Create(Self);
  FBtnCollapse.Parent := FTopPanel;
  FBtnCollapse.SetBounds(728, 8, 90, 25);
  FBtnCollapse.Caption := 'Collapse all';
  FBtnCollapse.OnClick := DoCollapseClick;

  FBtnSourceFolder := TButton.Create(Self);
  FBtnSourceFolder.Parent := FTopPanel;
  FBtnSourceFolder.SetBounds(824, 8, 150, 25);
  FBtnSourceFolder.Caption := 'Add source folder...';
  FBtnSourceFolder.OnClick := DoAddSourceFolderClick;

  {--- report selector (for files that contain more than one report) ---}
  FReportLabel := TLabel.Create(Self);
  FReportLabel.Parent := FTopPanel;
  FReportLabel.SetBounds(6, 43, 45, 17);
  FReportLabel.Caption := 'Report:';

  FReportCombo := TComboBox.Create(Self);
  FReportCombo.Parent := FTopPanel;
  FReportCombo.SetBounds(54, 39, 578, 24);
  FReportCombo.Style := csDropDownList;
  FReportCombo.OnChange := DoReportChange;

  FSummaryLabel := TLabel.Create(Self);
  FSummaryLabel.Parent := FTopPanel;
  FSummaryLabel.SetBounds(6, 72, 960, 17);
  FSummaryLabel.Caption := '';

  {--- left tree ---}
  FTree := TTreeView.Create(Self);
  FTree.Parent := FLeakTab;
  FTree.Align := alLeft;
  FTree.Width := 430;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.RowSelect := True;
  FTree.ShowLines := True;
  FTree.OnChange := DoTreeChange;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := FLeakTab;
  FSplitter.Align := alLeft;
  FSplitter.Left := FTree.Width + 1;
  FSplitter.Width := 5;

  {--- right details pane ---}
  FRightPanel := TPanel.Create(Self);
  FRightPanel.Parent := FLeakTab;
  FRightPanel.Align := alClient;
  FRightPanel.BevelOuter := bvNone;

  FInfoMemo := TMemo.Create(Self);
  FInfoMemo.Parent := FRightPanel;
  FInfoMemo.Align := alTop;
  FInfoMemo.Height := 150;
  FInfoMemo.ReadOnly := True;
  FInfoMemo.ScrollBars := ssVertical;
  FInfoMemo.Color := clWindow;
  FInfoMemo.Font.Name := 'Courier New';
  FInfoMemo.Font.Size := 9;

  FInfoSplitter := TSplitter.Create(Self);
  FInfoSplitter.Parent := FRightPanel;
  FInfoSplitter.Align := alTop;
  FInfoSplitter.Top := FInfoMemo.Height + 1;
  FInfoSplitter.Height := 5;

  FPageControl := TPageControl.Create(Self);
  FPageControl.Parent := FRightPanel;
  FPageControl.Align := alClient;

  FStackTab := TTabSheet.Create(Self);
  FStackTab.PageControl := FPageControl;
  FStackTab.Caption := 'Stack trace';

  FDumpTab := TTabSheet.Create(Self);
  FDumpTab.PageControl := FPageControl;
  FDumpTab.Caption := 'Memory dump';

  FStackList := TListView.Create(Self);
  FStackList.Parent := FStackTab;
  FStackList.Align := alClient;
  FStackList.ViewStyle := vsReport;
  FStackList.ReadOnly := True;
  FStackList.RowSelect := True;
  FStackList.HideSelection := False;
  FStackList.OnDblClick := DoStackDblClick;

  LCol := FStackList.Columns.Add; LCol.Caption := '#'; LCol.Width := 40;
  LCol := FStackList.Columns.Add; LCol.Caption := 'Routine'; LCol.Width := 220;
  LCol := FStackList.Columns.Add; LCol.Caption := 'Unit'; LCol.Width := 110;
  LCol := FStackList.Columns.Add; LCol.Caption := 'Source'; LCol.Width := 130;
  LCol := FStackList.Columns.Add; LCol.Caption := 'Line'; LCol.Width := 60;
  LCol := FStackList.Columns.Add; LCol.Caption := 'Address'; LCol.Width := 90;

  FDumpMemo := TMemo.Create(Self);
  FDumpMemo.Parent := FDumpTab;
  FDumpMemo.Align := alClient;
  FDumpMemo.ReadOnly := True;
  FDumpMemo.ScrollBars := ssBoth;
  FDumpMemo.WordWrap := False;
  FDumpMemo.Font.Name := 'Courier New';
  FDumpMemo.Font.Size := 9;

  {--- open dialog ---}
  FOpenDialog := TOpenDialog.Create(Self);
  FOpenDialog.Filter :=
    'FastMM files (*.txt;*.log;*.csv)|*.txt;*.log;*.csv|'
    + 'Leak reports and state captures (*.txt;*.log)|*.txt;*.log|'
    + 'Sampling logs (*.csv)|*.csv|All files (*.*)|*.*';
  FOpenDialog.Options := FOpenDialog.Options + [ofFileMustExist];

  BuildSamplingTab;
end;

procedure TFastMMReportViewerForm.BuildSamplingTab;
var
  LBtn: TButton;
  LCol: TListColumn;
begin
  {--- toolbar ---}
  FSampTopPanel := TPanel.Create(Self);
  FSampTopPanel.Parent := FSamplingTab;
  FSampTopPanel.Align := alTop;
  FSampTopPanel.Height := 62;
  FSampTopPanel.BevelOuter := bvNone;
  FSampTopPanel.BorderWidth := 4;

  LBtn := TButton.Create(Self);
  LBtn.Parent := FSampTopPanel;
  LBtn.SetBounds(6, 8, 110, 25);
  LBtn.Caption := 'Open CSV...';
  LBtn.OnClick := DoSampOpenClick;

  LBtn := TButton.Create(Self);
  LBtn.Parent := FSampTopPanel;
  LBtn.SetBounds(122, 8, 150, 25);
  LBtn.Caption := 'Sample sampling log';
  LBtn.OnClick := DoSampSampleClick;

  FSampNormalize := TCheckBox.Create(Self);
  FSampNormalize.Parent := FSampTopPanel;
  FSampNormalize.SetBounds(288, 11, 300, 20);
  FSampNormalize.Caption := 'Normalise each series to its own peak (%)';
  FSampNormalize.OnClick := DoSampSeriesClick;

  FSampSummaryLabel := TLabel.Create(Self);
  FSampSummaryLabel.Parent := FSampTopPanel;
  FSampSummaryLabel.SetBounds(6, 40, 960, 17);
  FSampSummaryLabel.Caption := '';

  {--- series picker on the left ---}
  FSampSeriesLabel := TLabel.Create(Self);
  FSampSeriesLabel.Parent := FSampTopPanel;
  FSampSeriesLabel.SetBounds(600, 13, 190, 17);
  FSampSeriesLabel.Caption := 'Series to plot (left):';

  FSampSeriesList := TCheckListBox.Create(Self);
  FSampSeriesList.Parent := FSamplingTab;
  FSampSeriesList.Align := alLeft;
  FSampSeriesList.Width := 200;
  FSampSeriesList.OnClickCheck := DoSampSeriesClick;

  {--- table area at the bottom ---}
  FSampBottomPages := TPageControl.Create(Self);
  FSampBottomPages.Parent := FSamplingTab;
  FSampBottomPages.Align := alBottom;
  FSampBottomPages.Height := 220;

  FSampTableTab := TTabSheet.Create(Self);
  FSampTableTab.PageControl := FSampBottomPages;
  FSampTableTab.Caption := 'Samples';

  FSampDetailTab := TTabSheet.Create(Self);
  FSampDetailTab.PageControl := FSampBottomPages;
  FSampDetailTab.Caption := 'Size classes of the selected sample';

  FSampSplitter := TSplitter.Create(Self);
  FSampSplitter.Parent := FSamplingTab;
  FSampSplitter.Align := alBottom;
  FSampSplitter.Height := 5;

  FSampGrid := TListView.Create(Self);
  FSampGrid.Parent := FSampTableTab;
  FSampGrid.Align := alClient;
  FSampGrid.ViewStyle := vsReport;
  FSampGrid.ReadOnly := True;
  FSampGrid.RowSelect := True;
  FSampGrid.HideSelection := False;
  FSampGrid.OnSelectItem := DoSampGridSelect;

  LCol := FSampGrid.Columns.Add; LCol.Caption := '#'; LCol.Width := 50;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Elapsed (ms)'; LCol.Width := 90;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Wall clock'; LCol.Width := 150;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'MM usage'; LCol.Width := 100;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Allocated'; LCol.Width := 100;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Reserved'; LCol.Width := 100;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Overhead'; LCol.Width := 100;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Efficiency'; LCol.Width := 75;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Small'; LCol.Width := 70;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Medium'; LCol.Width := 70;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Large'; LCol.Width := 70;
  LCol := FSampGrid.Columns.Add; LCol.Caption := 'Contention s/m/l'; LCol.Width := 110;

  FSampDetailGrid := TListView.Create(Self);
  FSampDetailGrid.Parent := FSampDetailTab;
  FSampDetailGrid.Align := alClient;
  FSampDetailGrid.ViewStyle := vsReport;
  FSampDetailGrid.ReadOnly := True;
  FSampDetailGrid.RowSelect := True;

  LCol := FSampDetailGrid.Columns.Add; LCol.Caption := 'Block size'; LCol.Width := 90;
  LCol := FSampDetailGrid.Columns.Add; LCol.Caption := 'Useable size'; LCol.Width := 90;
  LCol := FSampDetailGrid.Columns.Add; LCol.Caption := 'Allocated blocks'; LCol.Width := 110;
  LCol := FSampDetailGrid.Columns.Add; LCol.Caption := 'Used bytes'; LCol.Width := 100;
  LCol := FSampDetailGrid.Columns.Add; LCol.Caption := 'Reserved bytes'; LCol.Width := 110;
  LCol := FSampDetailGrid.Columns.Add; LCol.Caption := 'Efficiency'; LCol.Width := 80;

  {--- the plot fills what is left ---}
  FSampChartPanel := TPanel.Create(Self);
  FSampChartPanel.Parent := FSamplingTab;
  FSampChartPanel.Align := alClient;
  FSampChartPanel.BevelOuter := bvNone;
  FSampChartPanel.Color := clWindow;
  {$IF CompilerVersion >= 18}
  {Without this the themed tab background paints over the panel colour.}
  FSampChartPanel.ParentBackground := False;
  {$IFEND}

  FSampChart := TPaintBox.Create(Self);
  FSampChart.Parent := FSampChartPanel;
  FSampChart.Align := alClient;
  FSampChart.OnPaint := DoSampChartPaint;
  FSampChart.OnMouseMove := DoSampChartMouseMove;
  FSampChart.OnMouseDown := DoSampChartMouseDown;
  {$IF CompilerVersion >= 20}
  FSampChart.OnMouseLeave := DoSampChartMouseLeave;
  {$IFEND}

  PopulateSamplingSeriesList;
  UpdateSamplingSummaryLabel;
end;

{--------------------------------------------------------------------------}
{ Sampling log tab                                                          }
{--------------------------------------------------------------------------}

const
  {One colour per plotted series, reused cyclically.  Chosen to stay
   distinguishable on a white background.}
  CSeriesColors: array[0..8] of TColor = (
    clNavy, clRed, clGreen, clPurple, clTeal, clMaroon, clOlive, clBlue, clGray);

{Formats a byte count the way a human reads it, with one decimal from KB up.}
function FormatBytes(AValue: Double): string;
begin
  if Abs(AValue) >= 1024 * 1024 * 1024 then
    Result := Format('%.1f GB', [AValue / (1024 * 1024 * 1024)])
  else if Abs(AValue) >= 1024 * 1024 then
    Result := Format('%.1f MB', [AValue / (1024 * 1024)])
  else if Abs(AValue) >= 1024 then
    Result := Format('%.1f KB', [AValue / 1024])
  else
    Result := Format('%.0f B', [AValue]);
end;

{Formats a value for the axis / read-out according to the unit of its series.}
function FormatSeriesValue(AValue: Double; const AUnit: string): string;
begin
  if AUnit = 'bytes' then
    Result := FormatBytes(AValue)
  else if AUnit = '%' then
    Result := Format('%.2f %%', [AValue])
  else if AUnit = 'blocks' then
    Result := Format('%.0n', [AValue])
  else if AUnit = 'events' then
    Result := Format('%.0n', [AValue])
  else
    {Mixed units, or normalised:  a bare number is the honest rendering.}
    Result := Format('%.1f', [AValue]);
end;

procedure TFastMMReportViewerForm.PopulateSamplingSeriesList;
var
  LSeries: TFastMMSampleSeries;
begin
  FSampSeriesList.Items.BeginUpdate;
  try
    FSampSeriesList.Items.Clear;
    for LSeries := Low(TFastMMSampleSeries) to High(TFastMMSampleSeries) do
      FSampSeriesList.Items.Add(FastMMSampleSeriesName(LSeries));
  finally
    FSampSeriesList.Items.EndUpdate;
  end;
  {A useful default:  the three series that answer "is this run growing?".}
  FSampSeriesList.Checked[Ord(ssAllocated)] := True;
  FSampSeriesList.Checked[Ord(ssReserved)] := True;
  FSampSeriesList.Checked[Ord(ssMemoryManagerUsage)] := True;
end;

function TFastMMReportViewerForm.SelectedSeriesUnit: string;
var
  i: Integer;
  LUnit: string;
  LSeen: Boolean;
begin
  Result := '';
  LSeen := False;
  for i := 0 to FSampSeriesList.Items.Count - 1 do
  begin
    if not FSampSeriesList.Checked[i] then
      Continue;
    LUnit := FastMMSampleSeriesUnit(TFastMMSampleSeries(i));
    if not LSeen then
    begin
      Result := LUnit;
      LSeen := True;
    end
    else
      if Result <> LUnit then
      begin
        {Different units are being plotted together;  say so rather than
         pretending the axis means one thing.}
        Result := 'mixed';
        Exit;
      end;
  end;
end;

function TFastMMReportViewerForm.SelectedSeriesMaximum: Double;
var
  i: Integer;
  LMax: Double;
begin
  Result := 0;
  for i := 0 to FSampSeriesList.Items.Count - 1 do
  begin
    if not FSampSeriesList.Checked[i] then
      Continue;
    LMax := FSamplingLog.MaxOf(TFastMMSampleSeries(i));
    if LMax > Result then
      Result := LMax;
  end;
end;

function TFastMMReportViewerForm.SamplingChartRect: TRect;
begin
  {Margins leave room for the axis labels.}
  Result.Left := 78;
  Result.Top := 10;
  Result.Right := FSampChart.Width - 14;
  Result.Bottom := FSampChart.Height - 24;
  if Result.Right < Result.Left + 10 then
    Result.Right := Result.Left + 10;
  if Result.Bottom < Result.Top + 10 then
    Result.Bottom := Result.Top + 10;
end;

function TFastMMReportViewerForm.SamplingSampleAt(AX: Integer): Integer;
var
  LRect: TRect;
  LWidth: Integer;
begin
  Result := -1;
  if FSamplingLog.Count = 0 then
    Exit;
  LRect := SamplingChartRect;
  if FSamplingLog.Count = 1 then
  begin
    Result := 0;
    Exit;
  end;
  LWidth := LRect.Right - LRect.Left;
  if LWidth <= 0 then
    Exit;
  Result := Round((AX - LRect.Left) * (FSamplingLog.Count - 1) / LWidth);
  if Result < 0 then
    Result := 0;
  if Result > FSamplingLog.Count - 1 then
    Result := FSamplingLog.Count - 1;
end;

procedure TFastMMReportViewerForm.DoSampChartPaint(Sender: TObject);
var
  LCanvas: TCanvas;
  LRect: TRect;
  LMax, LValue, LSeriesMax: Double;
  LUnit, LText: string;
  i, j, LX, LY, LPrevX, LPrevY, LColorIndex, LLegendY: Integer;
  LNormalize: Boolean;
  LRowCount: Integer;
begin
  LCanvas := FSampChart.Canvas;
  LRect := SamplingChartRect;
  LRowCount := FSamplingLog.Count;

  {Background.}
  LCanvas.Brush.Color := clWindow;
  LCanvas.FillRect(FSampChart.ClientRect);
  LCanvas.Font.Name := 'Tahoma';
  LCanvas.Font.Size := 8;
  LCanvas.Font.Color := clWindowText;

  if LRowCount = 0 then
  begin
    LCanvas.TextOut(LRect.Left, LRect.Top + 8,
      'No sampling log loaded.  Use "Open CSV...", drop a sampling log onto this window, or try the sample.');
    Exit;
  end;

  LNormalize := FSampNormalize.Checked;
  if LNormalize then
  begin
    LMax := 100;
    LUnit := '% of own peak';
  end
  else
  begin
    LMax := SelectedSeriesMaximum;
    LUnit := SelectedSeriesUnit;
  end;
  if LMax <= 0 then
    LMax := 1;

  {Plot frame.}
  LCanvas.Pen.Color := clGray;
  LCanvas.Pen.Style := psSolid;
  LCanvas.Brush.Style := bsClear;
  LCanvas.Rectangle(LRect.Left, LRect.Top, LRect.Right, LRect.Bottom);

  {Horizontal grid plus the value axis.}
  for i := 0 to 4 do
  begin
    LY := LRect.Bottom - Round((LRect.Bottom - LRect.Top) * i / 4);
    if (i > 0) and (i < 4) then
    begin
      LCanvas.Pen.Color := clSilver;
      LCanvas.Pen.Style := psDot;
      LCanvas.MoveTo(LRect.Left + 1, LY);
      LCanvas.LineTo(LRect.Right - 1, LY);
    end;
    LValue := LMax * i / 4;
    if LNormalize then
      LText := Format('%.0f %%', [LValue])
    else
      LText := FormatSeriesValue(LValue, LUnit);
    LCanvas.Font.Color := clWindowText;
    LCanvas.TextOut(LRect.Left - 6 - LCanvas.TextWidth(LText), LY - 7, LText);
  end;

  {Time axis:  first, middle and last elapsed value.}
  LCanvas.Pen.Style := psSolid;
  for i := 0 to 2 do
  begin
    j := (LRowCount - 1) * i div 2;
    LX := LRect.Left;
    if LRowCount > 1 then
      LX := LRect.Left + Round((LRect.Right - LRect.Left) * j / (LRowCount - 1));
    LText := IntToStr(FSamplingLog[j].ElapsedMilliseconds) + ' ms';
    if i = 0 then
      LCanvas.TextOut(LX, LRect.Bottom + 4, LText)
    else if i = 2 then
      LCanvas.TextOut(LX - LCanvas.TextWidth(LText), LRect.Bottom + 4, LText)
    else
      LCanvas.TextOut(LX - LCanvas.TextWidth(LText) div 2, LRect.Bottom + 4, LText);
  end;

  {The marker for the sample under the mouse, drawn behind the series.}
  if (FSampHotIndex >= 0) and (FSampHotIndex < LRowCount) then
  begin
    LX := LRect.Left;
    if LRowCount > 1 then
      LX := LRect.Left + Round((LRect.Right - LRect.Left) * FSampHotIndex / (LRowCount - 1));
    LCanvas.Pen.Color := clSilver;
    LCanvas.Pen.Style := psSolid;
    LCanvas.MoveTo(LX, LRect.Top + 1);
    LCanvas.LineTo(LX, LRect.Bottom - 1);
  end;

  {The series themselves.}
  LColorIndex := 0;
  LLegendY := LRect.Top + 4;
  for i := 0 to FSampSeriesList.Items.Count - 1 do
  begin
    if not FSampSeriesList.Checked[i] then
      Continue;

    LSeriesMax := 1;
    if LNormalize then
    begin
      LSeriesMax := FSamplingLog.MaxOf(TFastMMSampleSeries(i));
      if LSeriesMax <= 0 then
        LSeriesMax := 1;
    end;

    LCanvas.Pen.Color := CSeriesColors[LColorIndex mod (High(CSeriesColors) + 1)];
    LCanvas.Pen.Style := psSolid;
    LCanvas.Pen.Width := 1;

    LPrevX := 0;
    LPrevY := 0;
    for j := 0 to LRowCount - 1 do
    begin
      LValue := FSamplingLog[j].Value(TFastMMSampleSeries(i));
      if LNormalize then
        LValue := 100 * LValue / LSeriesMax;

      LX := LRect.Left;
      if LRowCount > 1 then
        LX := LRect.Left + Round((LRect.Right - LRect.Left) * j / (LRowCount - 1));
      LY := LRect.Bottom - Round((LRect.Bottom - LRect.Top) * LValue / LMax);
      if LY < LRect.Top then
        LY := LRect.Top;
      if LY > LRect.Bottom then
        LY := LRect.Bottom;

      if j = 0 then
        LCanvas.MoveTo(LX, LY)
      else
        LCanvas.LineTo(LX, LY);
      LPrevX := LX;
      LPrevY := LY;
    end;
    {A single sample has no line;  mark it so the plot is not simply empty.}
    if LRowCount = 1 then
      LCanvas.Rectangle(LPrevX - 2, LPrevY - 2, LPrevX + 3, LPrevY + 3);

    {Legend entry.}
    LCanvas.Brush.Style := bsSolid;
    LCanvas.Brush.Color := LCanvas.Pen.Color;
    LCanvas.FillRect(Rect(LRect.Left + 8, LLegendY + 4, LRect.Left + 20, LLegendY + 12));
    LCanvas.Brush.Style := bsClear;
    LCanvas.Font.Color := clWindowText;
    LCanvas.TextOut(LRect.Left + 24, LLegendY, FSampSeriesList.Items[i]);
    Inc(LLegendY, 15);
    Inc(LColorIndex);
  end;

  if LColorIndex = 0 then
    LCanvas.TextOut(LRect.Left + 8, LRect.Top + 8, 'No series selected.');
end;

procedure TFastMMReportViewerForm.DoSampChartMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  LIndex: Integer;
  LRow: TFastMMSampleRow;
begin
  LIndex := SamplingSampleAt(X);
  if LIndex <> FSampHotIndex then
  begin
    FSampHotIndex := LIndex;
    FSampChart.Invalidate;
  end;
  if LIndex < 0 then
    Exit;

  LRow := FSamplingLog[LIndex];
  FStatus.SimpleText := Format(
    'Sample #%d at %d ms:  allocated %s, reserved %s, overhead %s, efficiency %.2f%%, ' +
    'blocks %d/%d/%d (small/medium/large)',
    [LRow.SampleIndex, LRow.ElapsedMilliseconds, FormatBytes(LRow.AllocatedBytes),
     FormatBytes(LRow.ReservedBytes), FormatBytes(LRow.OverheadBytes),
     LRow.EfficiencyPercentage, LRow.SmallBlockCount, LRow.MediumBlockCount,
     LRow.LargeBlockCount]);
end;

procedure TFastMMReportViewerForm.DoSampChartMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  LIndex: Integer;
begin
  LIndex := SamplingSampleAt(X);
  if (LIndex >= 0) and (LIndex < FSampGrid.Items.Count) then
  begin
    FSampGrid.Selected := FSampGrid.Items[LIndex];
    FSampGrid.Items[LIndex].MakeVisible(False);
  end;
end;

{$IF CompilerVersion >= 20}
procedure TFastMMReportViewerForm.DoSampChartMouseLeave(Sender: TObject);
begin
  if FSampHotIndex <> -1 then
  begin
    FSampHotIndex := -1;
    FSampChart.Invalidate;
  end;
end;
{$IFEND}

procedure TFastMMReportViewerForm.DoSampSeriesClick(Sender: TObject);
begin
  FSampChart.Invalidate;
end;

procedure TFastMMReportViewerForm.PopulateSamplingGrid;
var
  i: Integer;
  LRow: TFastMMSampleRow;
  LItem: TListItem;
begin
  FSampGrid.Items.BeginUpdate;
  try
    FSampGrid.Items.Clear;
    for i := 0 to FSamplingLog.Count - 1 do
    begin
      LRow := FSamplingLog[i];
      LItem := FSampGrid.Items.Add;
      LItem.Caption := IntToStr(LRow.SampleIndex);
      LItem.SubItems.Add(ThousandsInt(LRow.ElapsedMilliseconds));
      LItem.SubItems.Add(LRow.WallClock);
      LItem.SubItems.Add(FormatBytes(LRow.MemoryManagerUsageBytes));
      LItem.SubItems.Add(FormatBytes(LRow.AllocatedBytes));
      LItem.SubItems.Add(FormatBytes(LRow.ReservedBytes));
      LItem.SubItems.Add(FormatBytes(LRow.OverheadBytes));
      LItem.SubItems.Add(Format('%.2f %%', [LRow.EfficiencyPercentage]));
      LItem.SubItems.Add(ThousandsInt(LRow.SmallBlockCount));
      LItem.SubItems.Add(ThousandsInt(LRow.MediumBlockCount));
      LItem.SubItems.Add(ThousandsInt(LRow.LargeBlockCount));
      if FSamplingLog.HasContentionCounts then
        LItem.SubItems.Add(Format('%d / %d / %d',
          [LRow.SmallContentionCount, LRow.MediumContentionCount, LRow.LargeContentionCount]))
      else
        LItem.SubItems.Add('n/a');
    end;
  finally
    FSampGrid.Items.EndUpdate;
  end;
end;

procedure TFastMMReportViewerForm.PopulateSamplingDetailGrid(ASampleIndex: Int64);
var
  i: Integer;
  LDetail: TFastMMSampleDetailRow;
  LItem: TListItem;
begin
  FSampDetailGrid.Items.BeginUpdate;
  try
    FSampDetailGrid.Items.Clear;
    for i := 0 to FSamplingLog.DetailCount - 1 do
    begin
      LDetail := FSamplingLog.DetailRows[i];
      if LDetail.SampleIndex <> ASampleIndex then
        Continue;
      LItem := FSampDetailGrid.Items.Add;
      LItem.Caption := ThousandsInt(LDetail.BlockSize);
      LItem.SubItems.Add(ThousandsInt(LDetail.UseableSize));
      LItem.SubItems.Add(ThousandsInt(LDetail.AllocatedCount));
      LItem.SubItems.Add(FormatBytes(LDetail.UsedBytes));
      LItem.SubItems.Add(FormatBytes(LDetail.ReservedBytes));
      LItem.SubItems.Add(Format('%.2f %%', [LDetail.EfficiencyPercentage]));
    end;
  finally
    FSampDetailGrid.Items.EndUpdate;
  end;

  if FSamplingLog.DetailCount = 0 then
    FSampDetailTab.Caption := 'Size classes (no detail log loaded)'
  else
    FSampDetailTab.Caption := Format('Size classes of sample #%d', [ASampleIndex]);
end;

procedure TFastMMReportViewerForm.DoSampGridSelect(Sender: TObject;
  Item: TListItem; Selected: Boolean);
var
  LIndex: Integer;
begin
  if not Selected then
    Exit;
  LIndex := Item.Index;
  if (LIndex >= 0) and (LIndex < FSamplingLog.Count) then
  begin
    PopulateSamplingDetailGrid(FSamplingLog[LIndex].SampleIndex);
    if FSampHotIndex <> LIndex then
    begin
      FSampHotIndex := LIndex;
      FSampChart.Invalidate;
    end;
  end;
end;

procedure TFastMMReportViewerForm.UpdateSamplingSummaryLabel;
var
  LPeakIndex: Integer;
  LText: string;
begin
  if FSamplingLog.Count = 0 then
  begin
    FSampSummaryLabel.Caption :=
      'No sampling log loaded.  Use "Open CSV...", drag a FastMM_SamplingProfiler CSV onto this window, or try the sample.';
    Exit;
  end;

  LPeakIndex := FSamplingLog.IndexOfMax(ssAllocated);
  LText := Format('%d sample(s) over %s ms  -  allocated %s at start, peak %s',
    [FSamplingLog.Count, ThousandsInt(FSamplingLog.DurationMilliseconds),
     FormatBytes(FSamplingLog[0].AllocatedBytes),
     FormatBytes(FSamplingLog.MaxOf(ssAllocated))]);
  if LPeakIndex >= 0 then
    LText := LText + Format(' at %s ms', [ThousandsInt(FSamplingLog[LPeakIndex].ElapsedMilliseconds)]);
  LText := LText + Format(', %s at end  -  peak reserved %s',
    [FormatBytes(FSamplingLog[FSamplingLog.Count - 1].AllocatedBytes),
     FormatBytes(FSamplingLog.MaxOf(ssReserved))]);
  if FSamplingLog.MalformedLineCount > 0 then
    LText := LText + Format('  (%d damaged line(s) skipped)', [FSamplingLog.MalformedLineCount]);
  FSampSummaryLabel.Caption := LText;
end;

procedure TFastMMReportViewerForm.LoadSamplingLogFile(const AFileName: string);
var
  LDetailName: string;
begin
  FSamplingLog.LoadFromFile(AFileName);
  LDetailName := TFastMMSamplingLog.GuessDetailFileName(AFileName);
  if LDetailName <> '' then
    FSamplingLog.LoadDetailFromFile(LDetailName);

  PopulateSamplingGrid;
  UpdateSamplingSummaryLabel;
  FSampHotIndex := -1;
  FSampChart.Invalidate;
  if FSampGrid.Items.Count > 0 then
    FSampGrid.Selected := FSampGrid.Items[0]
  else
    PopulateSamplingDetailGrid(-1);

  FOuterPages.ActivePage := FSamplingTab;
  if LDetailName <> '' then
    FStatus.SimpleText := Format('Loaded: %s  (+ detail log %s)',
      [AFileName, ExtractFileName(LDetailName)])
  else
    FStatus.SimpleText := 'Loaded: ' + AFileName;
  Caption := 'FastMM Report Viewer  -  ' + ExtractFileName(AFileName);
end;

procedure TFastMMReportViewerForm.LoadSamplingLogText(const AText, ADisplayName: string);
begin
  FSamplingLog.LoadFromString(AText, ADisplayName);
  PopulateSamplingGrid;
  UpdateSamplingSummaryLabel;
  FSampHotIndex := -1;
  FSampChart.Invalidate;
  if FSampGrid.Items.Count > 0 then
    FSampGrid.Selected := FSampGrid.Items[0]
  else
    PopulateSamplingDetailGrid(-1);

  FOuterPages.ActivePage := FSamplingTab;
  FStatus.SimpleText := 'Loaded: ' + ADisplayName;
  Caption := 'FastMM Report Viewer  -  ' + ADisplayName;
end;

procedure TFastMMReportViewerForm.DoSampOpenClick(Sender: TObject);
var
  LDialog: TOpenDialog;
begin
  LDialog := TOpenDialog.Create(Self);
  try
    LDialog.Filter := 'Sampling logs (*.csv)|*.csv|All files (*.*)|*.*';
    LDialog.Options := LDialog.Options + [ofFileMustExist];
    if LDialog.Execute then
      LoadSamplingLogFile(LDialog.FileName);
  finally
    LDialog.Free;
  end;
end;

procedure TFastMMReportViewerForm.DoSampSampleClick(Sender: TObject);
begin
  LoadSamplingLogText(FastMMSampleSamplingLog, '(built-in sample sampling log)');
end;

function TFastMMReportViewerForm.SortOrderFromCombo: TFastMMGroupSortOrder;
begin
  case FSortCombo.ItemIndex of
    1: Result := gsInstanceCountDesc;
    2: Result := gsContentTypeAsc;
  else
    Result := gsTotalBytesDesc;
  end;
end;

procedure TFastMMReportViewerForm.UpdateSummaryLabel;
begin
  if FReport = nil then
  begin
    FSummaryLabel.Caption := 'No report loaded.  Use "Open...", drag a report file onto this window, or try a sample.';
    Exit;
  end;
  case FReport.Kind of
    rkLeakReport:
      FSummaryLabel.Caption := Format(
        'Leak report  -  %s bytes leaked in %s block(s), %d class group(s)',
        [ThousandsInt(FReport.TotalLeakedBytes), ThousandsInt(FReport.TotalLeakedCount),
         FGroupCount]);
    rkStateCapture:
      FSummaryLabel.Caption := Format(
        'State capture %s  -  %s K allocated, %s K overhead, %d%% efficiency, %d class(es)',
        [FReport.Timestamp, ThousandsInt(FReport.AllocatedKB),
         ThousandsInt(FReport.OverheadKB), FReport.EfficiencyPercent,
         FReport.StateEntries.Count]);
  else
    FSummaryLabel.Caption := 'No report loaded.  Use "Open...", drag a report file onto this window, or try a sample.';
  end;
end;

procedure TFastMMReportViewerForm.PopulateReportCombo;
var
  i: Integer;
begin
  FReportCombo.Items.BeginUpdate;
  try
    FReportCombo.Items.Clear;
    for i := 0 to FReportSet.Count - 1 do
    begin
      {Reports are listed in file order.  FastMM appends, so the first entry is
       the oldest run and the last one is the newest - say so explicitly rather
       than making the reader infer it from the timestamps.}
      if (FReportSet.Count > 1) and (i = FReportSet.Count - 1) then
        FReportCombo.Items.Add(Format('#%d  %s   [newest]',
          [i + 1, FReportSet[i].Describe]))
      else if (FReportSet.Count > 1) and (i = 0) then
        FReportCombo.Items.Add(Format('#%d  %s   [oldest]',
          [i + 1, FReportSet[i].Describe]))
      else
        FReportCombo.Items.Add(Format('#%d  %s', [i + 1, FReportSet[i].Describe]));
    end;
  finally
    FReportCombo.Items.EndUpdate;
  end;
  {The selector only earns its keep when a file holds more than one report.}
  FReportLabel.Enabled := FReportSet.Count > 1;
  FReportCombo.Enabled := FReportSet.Count > 1;
end;

procedure TFastMMReportViewerForm.SelectReport(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FReportSet.Count) then
  begin
    FReport := nil;
    Exit;
  end;
  FReport := FReportSet[AIndex];
  if FReportCombo.ItemIndex <> AIndex then
    FReportCombo.ItemIndex := AIndex;
  FSortOrder := SortOrderFromCombo;
  PopulateTree;
  UpdateSummaryLabel;
end;

{Reads the first bytes of a file as raw bytes.  Enough to tell a sampling log
 (which is always plain ASCII) from a leak report, whatever the report's
 encoding is.}
function ReadFileHead(const AFileName: string; AMaxBytes: Integer): string;
var
  LStream: TFileStream;
  LBuffer: AnsiString;
  LRead: Integer;
begin
  Result := '';
  LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    if LStream.Size < AMaxBytes then
      AMaxBytes := LStream.Size;
    if AMaxBytes <= 0 then
      Exit;
    SetLength(LBuffer, AMaxBytes);
    LRead := LStream.Read(LBuffer[1], AMaxBytes);
    SetLength(LBuffer, LRead);
    Result := string(LBuffer);
  finally
    LStream.Free;
  end;
end;

procedure TFastMMReportViewerForm.LoadReportFile(const AFileName: string);
begin
  {A sampling profiler CSV belongs on the other tab.  Detect it by content
   rather than by extension, so a renamed file still lands in the right place.}
  if TFastMMSamplingLog.LooksLikeSamplingLog(ReadFileHead(AFileName, 256)) then
  begin
    LoadSamplingLogFile(AFileName);
    Exit;
  end;

  {Drop all references to the current report's objects before the report set
   frees them, so no stale tree node can be touched during the reload.}
  FReport := nil;
  FTree.Items.Clear;
  ClearDetails;

  FReportSet.LoadFromFile(AFileName);
  PopulateReportCombo;
  SelectReport(0);
  if FReportSet.Count > 1 then
    FStatus.SimpleText := Format('Loaded: %s  (%d reports in file)',
      [AFileName, FReportSet.Count])
  else
    FStatus.SimpleText := 'Loaded: ' + AFileName;
  Caption := 'FastMM Report Viewer  -  ' + ExtractFileName(AFileName);
  FOuterPages.ActivePage := FLeakTab;
end;

procedure TFastMMReportViewerForm.LoadReportText(const AText, ADisplayName: string);
begin
  {See LoadReportFile: release references before the report set frees them.}
  FReport := nil;
  FTree.Items.Clear;
  ClearDetails;

  FReportSet.LoadFromString(AText, '');
  PopulateReportCombo;
  SelectReport(0);
  if FReportSet.Count > 1 then
    FStatus.SimpleText := Format('Loaded: %s  (%d reports)', [ADisplayName, FReportSet.Count])
  else
    FStatus.SimpleText := 'Loaded: ' + ADisplayName;
  Caption := 'FastMM Report Viewer  -  ' + ADisplayName;
  FOuterPages.ActivePage := FLeakTab;
end;

procedure TFastMMReportViewerForm.DoReportChange(Sender: TObject);
begin
  if FReportCombo.ItemIndex >= 0 then
    SelectReport(FReportCombo.ItemIndex);
end;

procedure TFastMMReportViewerForm.PopulateTree;
var
  LGroups: TObjectList;
  i, j: Integer;
  LGroup: TFastMMGroup;
  LBlock: TFastMMLeakBlock;
  LGroupNode, LBlockNode: TTreeNode;
begin
  ClearDetails;
  if FReport = nil then
  begin
    FTree.Items.Clear;
    FGroupCount := 0;
    Exit;
  end;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    LGroups := FReport.BuildGroups(FSortOrder);
    FGroupCount := LGroups.Count;
    for i := 0 to LGroups.Count - 1 do
    begin
      LGroup := TFastMMGroup(LGroups[i]);
      LGroupNode := FTree.Items.AddChild(nil, Format('%s  -  %s bytes in %s block(s)',
        [DisplayContentType(LGroup.ContentType), ThousandsInt(LGroup.TotalBytes),
         ThousandsInt(LGroup.InstanceCount)]));
      LGroupNode.Data := LGroup;

      {Child block nodes only exist for leak reports (state captures are
       aggregate-only).}
      for j := 0 to LGroup.Blocks.Count - 1 do
      begin
        LBlock := TFastMMLeakBlock(LGroup.Blocks[j]);
        LBlockNode := FTree.Items.AddChild(LGroupNode, Format('%s bytes  (alloc #%s, thread %s)',
          [ThousandsInt(LBlock.BlockSize),
           LBlock.AllocationNumber, LBlock.AllocatedByThread]));
        LBlockNode.Data := LBlock;
      end;
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
    FTree.Items[0].Selected := True;
end;

procedure TFastMMReportViewerForm.ClearDetails;
begin
  FInfoMemo.Lines.Clear;
  FStackList.Items.Clear;
  FDumpMemo.Lines.Clear;
end;

procedure TFastMMReportViewerForm.DoTreeChange(Sender: TObject; Node: TTreeNode);
begin
  {Node.Data references group/block objects owned by FReport.  While a new
   report is being loaded FReport is nil and the tree is being cleared, so any
   selection-change fired during that teardown must be ignored - otherwise it
   would dereference objects that are about to be (or have been) freed.}
  if (FReport = nil) or (Node = nil) or (Node.Data = nil) then
  begin
    ClearDetails;
    Exit;
  end;
  if Node.Level = 0 then
    ShowGroup(TFastMMGroup(Node.Data))
  else
    ShowBlock(TFastMMLeakBlock(Node.Data));
end;

procedure TFastMMReportViewerForm.ShowGroup(AGroup: TFastMMGroup);
begin
  {For a state capture the group is the only level of detail, so show the
   aggregate figures.  For a leak report the group node summarises its blocks.}
  if FReport.Kind = rkStateCapture then
    ShowStateEntryFor(AGroup)
  else
  begin
    ClearDetails;
    FInfoMemo.Lines.Add('Class / content type : ' + DisplayContentType(AGroup.ContentType));
    FInfoMemo.Lines.Add('Leaked instances     : ' + ThousandsInt(AGroup.InstanceCount));
    FInfoMemo.Lines.Add('Total bytes leaked   : ' + ThousandsInt(AGroup.TotalBytes));
    FInfoMemo.Lines.Add('');
    FInfoMemo.Lines.Add('Expand this node in the tree to inspect the individual blocks');
    FInfoMemo.Lines.Add('and their allocation stack traces.');
  end;
end;

procedure TFastMMReportViewerForm.ShowStateEntryFor(AGroup: TFastMMGroup);
var
  i: Integer;
  LEntry: TFastMMStateEntry;
begin
  ClearDetails;
  FInfoMemo.Lines.Add('Class / content type : ' + DisplayContentType(AGroup.ContentType));
  FInfoMemo.Lines.Add('Instances            : ' + ThousandsInt(AGroup.InstanceCount));
  FInfoMemo.Lines.Add('Total bytes          : ' + ThousandsInt(AGroup.TotalBytes));
  {Pull the average from the matching state entry.}
  for i := 0 to FReport.StateEntries.Count - 1 do
  begin
    LEntry := TFastMMStateEntry(FReport.StateEntries[i]);
    if (AnsiCompareText(LEntry.ContentType, AGroup.ContentType) = 0) and
       (LEntry.TotalBytes = AGroup.TotalBytes) then
    begin
      FInfoMemo.Lines.Add('Average per instance : ' + ThousandsInt(LEntry.AverageBytes) + ' bytes');
      Break;
    end;
  end;
  FInfoMemo.Lines.Add('');
  FInfoMemo.Lines.Add('(State captures do not record per-block allocation stack traces.)');
end;

procedure TFastMMReportViewerForm.ShowBlock(ABlock: TFastMMLeakBlock);
begin
  ClearDetails;
  FInfoMemo.Lines.Add('Class / content type : ' + DisplayContentType(ABlock.ContentType));
  FInfoMemo.Lines.Add('Block size           : ' + ThousandsInt(ABlock.BlockSize) + ' bytes');
  if ABlock.AllocationNumber <> '' then
    FInfoMemo.Lines.Add('Allocation number    : ' + ABlock.AllocationNumber);
  if ABlock.AllocatedByThread <> '' then
    FInfoMemo.Lines.Add('Allocated by thread  : ' + ABlock.AllocatedByThread);
  if (ABlock.AllocationDate <> '') or (ABlock.AllocationTime <> '') then
    FInfoMemo.Lines.Add('Allocated at         : ' +
      Trim(ABlock.AllocationDate + ' ' + ABlock.AllocationTime));
  if ABlock.FreedByThread <> '' then
    FInfoMemo.Lines.Add('Freed by thread      : ' + ABlock.FreedByThread);
  if ABlock.DumpAddress <> '' then
    FInfoMemo.Lines.Add('Address              : ' + ABlock.DumpAddress);

  FillStackList(ABlock.AllocStack, ABlock.FreeStack);

  FDumpMemo.Lines.Text := ABlock.HexDump;
  if Trim(FDumpMemo.Lines.Text) = '' then
    FDumpMemo.Lines.Text := '(no memory dump in this report)';
end;

procedure TFastMMReportViewerForm.FillStackList(AAllocStack, AFreeStack: TObjectList);

  procedure AddFrames(ACaption: string; AStack: TObjectList);
  var
    i: Integer;
    LFrame: TFastMMStackFrame;
    LItem: TListItem;
  begin
    if AStack.Count = 0 then
      Exit;
    {Section header row.}
    LItem := FStackList.Items.Add;
    LItem.Caption := '';
    LItem.SubItems.Add(ACaption);
    LItem.SubItems.Add('');
    LItem.SubItems.Add('');
    LItem.SubItems.Add('');
    LItem.SubItems.Add('');
    LItem.Data := nil;
    for i := 0 to AStack.Count - 1 do
    begin
      LFrame := TFastMMStackFrame(AStack[i]);
      LItem := FStackList.Items.Add;
      LItem.Caption := IntToStr(i);
      LItem.SubItems.Add(LFrame.Routine);
      LItem.SubItems.Add(LFrame.UnitName);
      {madExcept traces name a module rather than a source file; show that
       instead of leaving the column blank.}
      if LFrame.SourceFile <> '' then
        LItem.SubItems.Add(LFrame.SourceFile)
      else
        LItem.SubItems.Add(LFrame.ModuleName);
      if LFrame.LineNumber > 0 then
        LItem.SubItems.Add(IntToStr(LFrame.LineNumber))
      else
        LItem.SubItems.Add('');
      LItem.SubItems.Add(LFrame.Address);
      LItem.Data := LFrame;
    end;
  end;

begin
  FStackList.Items.BeginUpdate;
  try
    FStackList.Items.Clear;
    AddFrames('=== Allocation stack trace ===', AAllocStack);
    AddFrames('=== Free stack trace ===', AFreeStack);
    if FStackList.Items.Count = 0 then
    begin
      with FStackList.Items.Add do
        SubItems.Add('(no stack trace - build with FullDebugMode for allocation traces)');
    end;
  finally
    FStackList.Items.EndUpdate;
  end;
end;

procedure TFastMMReportViewerForm.DoStackDblClick(Sender: TObject);
begin
  if (FStackList.Selected <> nil) and (FStackList.Selected.Data <> nil) then
    JumpToFrame(TFastMMStackFrame(FStackList.Selected.Data));
end;

function TFastMMReportViewerForm.FindSourceFile(const AFileName: string): string;
var
  i: Integer;
  LCandidate, LBare: string;
begin
  Result := '';
  LBare := ExtractFileName(AFileName);
  {Search the report's own folder first.}
  if FReport.SourceFileName <> '' then
  begin
    LCandidate := ExtractFilePath(FReport.SourceFileName) + LBare;
    if FileExists(LCandidate) then
    begin
      Result := LCandidate;
      Exit;
    end;
  end;
  for i := 0 to FSourcePaths.Count - 1 do
  begin
    LCandidate := IncludeTrailingPathDelimiter(FSourcePaths[i]) + LBare;
    if FileExists(LCandidate) then
    begin
      Result := LCandidate;
      Exit;
    end;
  end;
end;

procedure TFastMMReportViewerForm.JumpToFrame(AFrame: TFastMMStackFrame);
var
  LHandled: Boolean;
  LResolved, LWantedFile: string;
begin
  if not AFrame.HasSourceLocation then
  begin
    FStatus.SimpleText := 'This frame carries no source location (' +
      AFrame.DisplayText + ').';
    Exit;
  end;

  {A JCL/FullDebugMode trace names the source file outright; a madExcept trace
   only names the unit, so the file name is derived from it.}
  LWantedFile := AFrame.SourceFileCandidate;

  LHandled := False;
  if Assigned(FOnSourceJump) then
    FOnSourceJump(Self, LWantedFile, AFrame.LineNumber, LHandled);
  if LHandled then
    Exit;

  {Built-in fallback: locate the file under the configured source folders and
   open it with the OS default handler.  The line number cannot be passed to an
   arbitrary editor, so it is reported in the status bar.}
  LResolved := FindSourceFile(LWantedFile);
  if LResolved <> '' then
  begin
    ShellExecute(Handle, 'open', PChar(LResolved), nil, nil, SW_SHOWNORMAL);
    FStatus.SimpleText := Format('Opened %s  (go to line %d)',
      [LResolved, AFrame.LineNumber]);
  end
  else
    FStatus.SimpleText := Format(
      '%s (line %d) not found. Use "Add source folder..." to point the viewer at your sources.',
      [LWantedFile, AFrame.LineNumber]);
end;

procedure TFastMMReportViewerForm.DoOpenClick(Sender: TObject);
begin
  if FOpenDialog.Execute then
    LoadReportFile(FOpenDialog.FileName);
end;

procedure TFastMMReportViewerForm.DoSample1Click(Sender: TObject);
begin
  LoadReportText(FastMMSampleLeakReport, '(sample leak report)');
end;

procedure TFastMMReportViewerForm.DoSample2Click(Sender: TObject);
begin
  LoadReportText(FastMMSampleStateCapture, '(sample state capture)');
end;

procedure TFastMMReportViewerForm.DoSortChange(Sender: TObject);
begin
  FSortOrder := SortOrderFromCombo;
  if (FReport <> nil) and (FReport.Kind <> rkUnknown) then
    PopulateTree;
end;

procedure TFastMMReportViewerForm.DoExpandClick(Sender: TObject);
begin
  FTree.FullExpand;
  if FTree.Items.Count > 0 then
    FTree.Items[0].MakeVisible;
end;

procedure TFastMMReportViewerForm.DoCollapseClick(Sender: TObject);
begin
  FTree.FullCollapse;
end;

procedure TFastMMReportViewerForm.DoAddSourceFolderClick(Sender: TObject);
var
  LDir: string;
begin
  LDir := '';
  if SelectDirectory('Select a folder containing your source files', '', LDir) then
  begin
    if FSourcePaths.IndexOf(LDir) < 0 then
      FSourcePaths.Add(LDir);
    FStatus.SimpleText := Format('%d source folder(s) configured.', [FSourcePaths.Count]);
  end;
end;

function ShowFastMMReportViewer(const AFileName: string): TFastMMReportViewerForm;
begin
  Result := TFastMMReportViewerForm.Create(Application);
  if AFileName <> '' then
  try
    Result.LoadReportFile(AFileName);
  except
    on E: Exception do
      MessageDlg('Could not load report:' + sLineBreak + E.Message, mtError, [mbOK], 0);
  end;
  Result.Show;
end;

end.
