program FastMM5Diag_SizeClasses;
{$APPTYPE CONSOLE}
uses FastMM5;
var
  P: Pointer;
  i, LSize: Integer;
begin
  WriteLn('EnterDebugMode = ', FastMM_EnterDebugMode);
  WriteLn('Groessen 1..70000 (Schrittweite 61) ...');
  LSize := 1;
  while LSize <= 70000 do
  begin
    GetMem(P, LSize);
    FillChar(P^, LSize, Byte(LSize));
    FreeMem(P);
    Inc(LSize, 61);
  end;
  WriteLn('  ok');
  WriteLn('Grosse Bloecke 100000..2000000 ...');
  LSize := 100000;
  while LSize <= 2000000 do
  begin
    GetMem(P, LSize);
    FillChar(P^, LSize, Byte(LSize));
    FreeMem(P);
    Inc(LSize, 100000);
  end;
  WriteLn('  ok');
  WriteLn('Realloc quer durch die Klassen ...');
  GetMem(P, 10);
  for i := 1 to 60 do
  begin
    ReallocMem(P, (i * 12345) mod 300000 + 1);
    FillChar(P^, 10, 7);
  end;
  FreeMem(P);
  WriteLn('  ok');
  WriteLn('ERGEBNIS: OK');
end.

