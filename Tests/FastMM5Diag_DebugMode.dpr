program FastMM5Diag_DebugMode;
{$APPTYPE CONSOLE}

uses
  FastMM5;

var
  P: Pointer;
  i: Integer;
begin
  WriteLn('SizeOf(TFastMM_DebugBlockHeader) = ', SizeOf(TFastMM_DebugBlockHeader));
  WriteLn('SizeOf(TSimpleLock-Bereich siehe Header) ok');

  WriteLn('Normal GetMem/FreeMem ...');
  GetMem(P, 100);
  FillChar(P^, 100, 1);
  FreeMem(P);
  WriteLn('  ok');

  WriteLn('EnterDebugMode = ', FastMM_EnterDebugMode);

  WriteLn('Debug GetMem(100) ...');
  GetMem(P, 100);
  WriteLn('  ptr ok, schreibe ...');
  FillChar(P^, 100, 2);
  WriteLn('  FreeMem ...');
  FreeMem(P);
  WriteLn('  ok');

  WriteLn('Groessen-Schleife 1..2000 ...');
  for i := 1 to 2000 do
  begin
    GetMem(P, i);
    FillChar(P^, i, 3);
    FreeMem(P);
  end;
  WriteLn('  ok');

  WriteLn('Realloc-Kette ...');
  GetMem(P, 10);
  for i := 1 to 200 do
    ReallocMem(P, (i * 37) mod 5000 + 1);
  FreeMem(P);
  WriteLn('  ok');

  WriteLn('ExitDebugMode = ', FastMM_ExitDebugMode);
  WriteLn('ERGEBNIS: OK');
end.

