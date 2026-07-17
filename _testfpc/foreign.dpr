program foreign;
{Tests foreign-block forwarding:  blocks allocated by the FPC RTL before FastMM installed (via the foreignpre unit,
 which initializes first) must be measured, reallocated and freed through the previous memory manager without
 corrupting the FastMM heap.
 Build:  fpc -B -Mdelphi -Fu.. foreign.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  foreignpre, FastMM5, SysUtils;

var
  i, fails: Integer;
  sz: SizeUInt;
  p: PByte;
  ptrs: array[0..99] of Pointer;

procedure Check(ACond: Boolean; const AName: string);
begin
  if ACond then
    Writeln('  ok   ', AName)
  else
  begin
    Writeln('  FAIL ', AName);
    Inc(fails);
  end;
end;

begin
  fails := 0;
  Writeln('Installation state = ', Ord(FastMM_GetInstallationState), '  (3 = mmisInstalled)');
  Check(FastMM_GetInstallationState = mmisInstalled, 'FastMM installed despite pre-existing RTL allocations');

{$ifdef FPCDIAG}
  FPCDIAG_DumpRegionRegistry;
  Writeln('ForeignSmall  = ', NativeUInt(ForeignSmall));
  Writeln('ForeignLarge  = ', NativeUInt(ForeignLarge));
  Writeln('ForeignString = ', NativeUInt(Pointer(ForeignString)));
{$endif}

  {MemSize on a foreign block must go to the previous manager and report at least the requested size.}
  sz := MemSize(ForeignSmall);
  Writeln('  MemSize(ForeignSmall) = ', sz);
  Check(sz >= 64, 'MemSize forwards for foreign small block');
  sz := MemSize(ForeignLarge);
  Writeln('  MemSize(ForeignLarge) = ', sz);
  Check(sz >= 300000, 'MemSize forwards for foreign large block');

  {Content of foreign blocks intact?}
  p := ForeignSmall;
  Check((p[0] = $5A) and (p[63] = $5A), 'foreign small block content intact');
  p := ForeignLarge;
  Check((p[0] = $C3) and (p[299999] = $C3), 'foreign large block content intact');

  {Realloc of a foreign block:  must preserve content and stay usable.}
  ReallocMem(ForeignSmall, 128);
  p := ForeignSmall;
  Check((p[0] = $5A) and (p[63] = $5A), 'foreign block content preserved across ReallocMem grow');
  FillChar(p[64], 64, $77);
  ReallocMem(ForeignSmall, 32);
  p := ForeignSmall;
  Check(p[0] = $5A, 'foreign block content preserved across ReallocMem shrink');

  {Free the foreign blocks - must not raise and must not damage the FastMM heap.}
  FreeMem(ForeignSmall);
  FreeMem(ForeignLarge);
  ForeignString := '';  {releases the RTL-allocated string data via forwarding}
  Check(True, 'foreign blocks freed without error');

  {FastMM heap still fully functional after the foreign operations?}
  for i := 0 to 99 do
  begin
    GetMem(ptrs[i], 100 + i * 37);
    FillChar(ptrs[i]^, 100 + i * 37, Byte(i));
  end;
  for i := 0 to 99 do
  begin
    p := ptrs[i];
    if p^ <> Byte(i) then
      fails := fails + 1;
    FreeMem(ptrs[i]);
  end;
  Check(True, 'FastMM heap churn after foreign frees');

  if fails = 0 then
    Writeln('PASS')
  else
  begin
    Writeln('FAIL: ', fails, ' checks failed');
    ExitCode := 1;
  end;
end.
