(*

  ReportViewerDemo
  ----------------

  A tiny host application for the FastMM report viewer.

    - Run it and click "Sample leak report" / "Sample state capture" on the
      first tab, or "Sample sampling log" on the second, to see the viewer
      populated with format-exact examples.  "Open..." loads a real file your
      FastMM5-instrumented application produced:  the shutdown leak report, a
      file written by FastMM_LogStateToFile, or a CSV written by
      FastMM_SamplingProfiler.
    - You can also pass a file on the command line;  the right tab is selected
      from its content:
        ReportViewerDemo.exe "C:\path\to\MyApp_MemoryManager_EventLog.txt"
        ReportViewerDemo.exe "C:\path\to\MemUsage_Summary.csv"

  The viewer form itself (FastMM_ReportViewerForm) is self-contained and can
  be dropped into any VCL application; this demo only wires it to Application.

  Builds on Delphi 7, Delphi 10 Seattle and Delphi 13.1.

*)

program ReportViewerDemo;

uses
  Forms,
  Dialogs,
  SysUtils,
  {$IF CompilerVersion >= 24} System.UITypes, {$IFEND}
  FastMM_LeakReportParser in 'FastMM_LeakReportParser.pas',
  FastMM_SamplingLogParser in 'FastMM_SamplingLogParser.pas',
  FastMM_ReportViewerForm in 'FastMM_ReportViewerForm.pas';

var
  GForm: TFastMMReportViewerForm;
begin
  Application.Initialize;
  Application.Title := 'FastMM Report Viewer';
  Application.CreateForm(TFastMMReportViewerForm, GForm);
  if ParamCount >= 1 then
  begin
    try
      GForm.LoadReportFile(ParamStr(1));
    except
      on E: Exception do
        MessageDlg('Could not load "' + ParamStr(1) + '":' + sLineBreak + E.Message,
          mtError, [mbOK], 0);
    end;
  end;
  Application.Run;
end.
