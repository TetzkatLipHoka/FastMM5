program reusecrash;
{Minimal repro for the X86ASM free-block-reuse crash:  alloc N, free N, alloc N again.
 A vectored exception handler prints the faulting code/data addresses for objdump mapping.
 Build:  fpc -B -Mdelphi -Fu.. reusecrash.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  Windows, FastMM5, SysUtils;

function AddVectoredExceptionHandler(First: DWORD; Handler: Pointer): Pointer; stdcall;
  external 'kernel32.dll' name 'AddVectoredExceptionHandler';

procedure HexToBuf(AValue: NativeUInt; ABuf: PAnsiChar);
const
  CHex: array[0..15] of AnsiChar = '0123456789ABCDEF';
var
  i: Integer;
begin
  for i := 7 downto 0 do
  begin
    ABuf[i] := CHex[AValue and 15];
    AValue := AValue shr 4;
  end;
end;

function VEHandler(ExceptionInfo: PEXCEPTION_POINTERS): LONG; stdcall;
var
  rec: PExceptionRecord;
  msg: array[0..63] of AnsiChar;
  written: DWORD;
begin
  rec := ExceptionInfo^.ExceptionRecord;
  if rec^.ExceptionCode = STATUS_ACCESS_VIOLATION then
  begin
    {No heap, no RTL:  raw WriteFile of "AV code=xxxxxxxx op=x data=xxxxxxxx".}
    Move(PAnsiChar('AV code=........ op=. data=........'#13#10)^, msg, 37);
    HexToBuf(NativeUInt(rec^.ExceptionAddress), @msg[8]);
    msg[20] := AnsiChar(Ord('0') + (rec^.ExceptionInformation[0] and 15));
    HexToBuf(NativeUInt(rec^.ExceptionInformation[1]), @msg[27]);
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), msg, 37, written, nil);
    TerminateProcess(GetCurrentProcess, 3);
  end;
  Result := 0;  {EXCEPTION_CONTINUE_SEARCH}
end;

const
  CN = 100;
var
  ptrs: array[0..CN - 1] of Pointer;
  i, size: Integer;
begin
  AddVectoredExceptionHandler(1, @VEHandler);
  Writeln('state=', Ord(FastMM_GetInstallationState));
  size := 8;
  while size <= 2600 do
  begin
    for i := 0 to CN - 1 do
      GetMem(ptrs[i], size);
    for i := 0 to CN - 1 do
      FreeMem(ptrs[i]);
    {Second allocation round reuses the freed blocks.}
    for i := 0 to CN - 1 do
      GetMem(ptrs[i], size);
    for i := 0 to CN - 1 do
      FreeMem(ptrs[i]);
    Writeln('size ', size, ' ok');
    Flush(Output);
    Inc(size, 61);
  end;
  Writeln('PASS');
end.
