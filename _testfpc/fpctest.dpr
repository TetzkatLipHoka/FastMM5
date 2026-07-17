program fpctest;
{$APPTYPE CONSOLE}
uses
  FastMM5,
  SysUtils;
var
  p: Pointer;
begin
  GetMem(p, 12345);
  FillChar(p^, 12345, 0);
  FreeMem(p);
  Writeln('FastMM5 under FPC: alloc/free ok');
end.
