program fpctest;
{Free Pascal (Win32) bring-up test for FastMM5.  Verifies that FastMM installs as the memory manager under FPC and
tracks allocations.  Build:  fpc -Mdelphi -Fu.. fpctest.dpr

STATUS (2026-07-17):  FastMM5 compiles, links, installs (state = mmisInstalled) and manages large-block allocations,
realloc and RTL string/object allocation under FPC 3.2.2.  KNOWN ISSUE:  freeing many *small* blocks crashes in the
PurePascal small-block free path (which Delphi never compiles, as it uses assembler there) - the next debugging
target, alongside foreign-block forwarding for blocks the RTL allocated before FastMM installed.}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  FastMM5, SysUtils;
var
  p: Pointer;
  usage0, usage1: NativeUInt;
  state: TFastMM_MemoryManagerInstallationState;
begin
  state := FastMM_GetInstallationState;
  Writeln('Installation state = ', Ord(state), '  (3 = mmisInstalled)');

  usage0 := FastMM_GetCurrentMemoryUsage;
  GetMem(p, 1000000);            {a large block - works today}
  FillChar(p^, 1000000, 0);
  usage1 := FastMM_GetCurrentMemoryUsage;
  Writeln('MM usage delta for a 1 MB GetMem = ', Int64(usage1) - Int64(usage0));
  FreeMem(p);

  if (state = mmisInstalled) and (Int64(usage1) - Int64(usage0) >= 1000000) then
    Writeln('PASS: FastMM5 installed and tracking allocations under FPC')
  else
  begin
    Writeln('FAIL');
    ExitCode := 1;
  end;
end.
