program sizefind;
{Finds the exact small-block size whose alloc/free sweep crashes under the FPC PurePascal paths.
 Build:  fpc -B -Mdelphi -Fu.. -gl sizefind.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  FastMM5, SysUtils;

const
  CN = 700;
var
  ptrs: array[0..CN - 1] of Pointer;
  size, i, startsize: Integer;
begin
  startsize := 751;
  if ParamCount >= 1 then
    startsize := StrToInt(ParamStr(1));
  size := startsize;
  while size <= 2600 do
  begin
    Write('size ', size, ' alloc');
    for i := 0 to CN - 1 do
    begin
      GetMem(ptrs[i], size);
      FillChar(ptrs[i]^, size, $AA);
    end;
    Write(' fwd-free');
    Flush(Output);
    for i := 0 to CN - 1 do
      FreeMem(ptrs[i]);
    Write(' alloc2');
    for i := 0 to CN - 1 do
    begin
      GetMem(ptrs[i], size);
      FillChar(ptrs[i]^, size, $BB);
    end;
    Write(' rev-free');
    Flush(Output);
    for i := CN - 1 downto 0 do
      FreeMem(ptrs[i]);
    Writeln(' ok');
    Inc(size);
  end;
  Writeln('PASS');
end.
