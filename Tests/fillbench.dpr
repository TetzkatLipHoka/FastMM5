{In-situ benchmark of the freed debug block fill pattern check.

 Repeatedly allocates and frees a block of the requested size in debug mode.
 Freeing writes the fill pattern;  the next allocation reuses the block from the
 debug free queue and verifies that pattern through CheckFreeDebugBlockIntact,
 so the routine under test runs once per iteration on the real allocation path.

 One process measures one build, so the harness runs the baseline and the
 candidate executables as separate processes.  That is deliberate:  measuring
 both variants inside one binary lets their code layout interact, which at these
 timescales swamps the effect being measured.

 Usage:  fillbench <user size> <iterations>
 Prints one line:  the elapsed milliseconds and a checksum.}

program fillbench;

{$APPTYPE CONSOLE}
{$O+}

uses
  FastMM5 in 'FastMM5.pas',
  Windows,
  SysUtils;

var
  GFrequency, GStart, GStop: Int64;
  GSize, GIterations, i: Integer;
  GPointer: Pointer;
  GChecksum: NativeUInt;

begin
  GSize := StrToIntDef(ParamStr(1), 4096);
  GIterations := StrToIntDef(ParamStr(2), 200000);

  {No stack traces:  they would dominate the measurement and are not what is
   being compared.}
  FastMM_MessageBoxEvents := [];
  FastMM_LogToFileEvents := [];
  FastMM_OutputDebugStringEvents := [];
  FastMM_SetDebugModeStackTraceEntryCount(0);

  if not FastMM_EnterDebugMode then
  begin
    WriteLn('EnterDebugMode failed');
    Halt(2);
  end;

  SetPriorityClass(GetCurrentProcess, HIGH_PRIORITY_CLASS);
  SetThreadAffinityMask(GetCurrentThread, 2);
  QueryPerformanceFrequency(GFrequency);

  {Prime the free queue so the very first timed allocation already reuses a
   block, and page in the code.}
  for i := 1 to 1000 do
  begin
    GetMem(GPointer, GSize);
    FreeMem(GPointer);
  end;

  GChecksum := 0;
  QueryPerformanceCounter(GStart);
  for i := 1 to GIterations do
  begin
    GetMem(GPointer, GSize);
    {Accumulate the tracked user size rather than the address:  addresses differ
     between processes because the heap is allocated at a randomised base, so
     they cannot be used to prove that both builds did the same work.  The user
     size comes from the debug header, so this also confirms debug mode was
     actually active.}
    Inc(GChecksum, NativeUInt(FastMM_BlockCurrentUserBytes(GPointer)));
    FreeMem(GPointer);
  end;
  QueryPerformanceCounter(GStop);

  FastMM_ExitDebugMode;

  WriteLn(Format('%.4f %d', [(GStop - GStart) * 1000.0 / GFrequency, GChecksum]));
end.
