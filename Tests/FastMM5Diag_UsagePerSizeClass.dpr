program FastMM5Diag_UsagePerSizeClass;
{$APPTYPE CONSOLE}

uses
  FastMM5, Windows, SysUtils;

procedure Report(const APhase: string);
var
  LSummary: TFastMM_UsageSummary;
begin
  LSummary := FastMM_GetUsageSummary;
  WriteLn(APhase, ': Allokiert=', LSummary.AllocatedBytes, ' Overhead=', LSummary.OverheadBytes);
end;

procedure Hammer(ASize, ACount: Integer);
var
  P: Pointer;
  I: Integer;
begin
  for I := 1 to ACount do
  begin
    GetMem(P, ASize);
    FillChar(P^, ASize, 1);
    FreeMem(P);
  end;
  Report('Nach ' + IntToStr(ACount) + 'x GetMem/FreeMem(' + IntToStr(ASize) + ')');
end;

begin
  Report('Start');
  if not FastMM_EnterDebugMode then
  begin
    WriteLn('EnterDebugMode fehlgeschlagen');
    Halt(2);
  end;
  Report('Nach EnterDebugMode');

  Hammer(500, 10000);
  Hammer(3000, 10000);
  Hammer(10000, 10000);
  Hammer(40000, 10000);
  Hammer(70000, 10000);
  Hammer(200000, 2000);
  Hammer(500000, 1000);

  FastMM_ExitDebugMode;
  Report('Nach ExitDebugMode');
  WriteLn('ERGEBNIS: OK');
end.

