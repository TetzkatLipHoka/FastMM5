program smallstress;
{Broader single-threaded small-block stress for the FPC PurePascal code paths.
 Phases:
   1. For every small block size 1..2600: alloc N, free N (forward + reverse) -> exercises sequential feed + span release.
   2. Random interleaved alloc/free with a deterministic PRNG -> exercises the free-block reuse path
      (AllocateFreeBlockAndUnlockArena) and the partially-free span linked list.
   3. Small-block realloc chains.
 Build:  fpc -Mdelphi -Fu.. smallstress.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  FastMM5, SysUtils;

var
  seed: Cardinal = $2A5F1C3D;

function Rnd(AMax: Cardinal): Cardinal;
begin
  {xorshift32 - deterministic}
  seed := seed xor (seed shl 13);
  seed := seed xor (seed shr 17);
  seed := seed xor (seed shl 5);
  Result := seed mod AMax;
end;

procedure Phase1;
const
  CN = 700;
var
  ptrs: array[0..CN - 1] of Pointer;
  size, i: Integer;
begin
  Writeln('Phase 1: per-size alloc/free sweeps');
  size := 1;
  while size <= 2600 do
  begin
    for i := 0 to CN - 1 do
    begin
      GetMem(ptrs[i], size);
      FillChar(ptrs[i]^, size, $AA);
    end;
    {forward free}
    for i := 0 to CN - 1 do
      FreeMem(ptrs[i]);
    for i := 0 to CN - 1 do
    begin
      GetMem(ptrs[i], size);
      FillChar(ptrs[i]^, size, $BB);
    end;
    {reverse free}
    for i := CN - 1 downto 0 do
      FreeMem(ptrs[i]);
    if (size mod 250 = 0) or (size = 1) then
      Writeln('  size ', size, ' ok');
    Inc(size, 7);
  end;
  Writeln('Phase 1 PASS');
end;

procedure Phase2;
const
  CSlots = 2048;
  CIters = 300000;
var
  slots: array[0..CSlots - 1] of Pointer;
  sizes: array[0..CSlots - 1] of Integer;
  i, s, size, live: Integer;
begin
  Writeln('Phase 2: random interleaved alloc/free (', CIters, ' iters)');
  FillChar(slots, SizeOf(slots), 0);
  live := 0;
  for i := 1 to CIters do
  begin
    s := Rnd(CSlots);
    if slots[s] = nil then
    begin
      size := 1 + Rnd(2600);
      GetMem(slots[s], size);
      sizes[s] := size;
      FillChar(slots[s]^, size, Byte(s));
      Inc(live);
    end
    else
    begin
      {verify fill pattern before freeing - catches cross-block corruption}
      if PByte(slots[s])^ <> Byte(s) then
      begin
        Writeln('CORRUPTION in slot ', s, ' at iter ', i);
        Halt(2);
      end;
      FreeMem(slots[s]);
      slots[s] := nil;
      Dec(live);
    end;
    if i mod 50000 = 0 then
      Writeln('  iter ', i, ', live blocks = ', live);
  end;
  for s := 0 to CSlots - 1 do
    if slots[s] <> nil then
      FreeMem(slots[s]);
  Writeln('Phase 2 PASS');
end;

procedure Phase3;
const
  CN = 300;
var
  p: Pointer;
  i, j, size: Integer;
begin
  Writeln('Phase 3: small-block realloc chains');
  for i := 0 to CN - 1 do
  begin
    size := 1 + Rnd(64);
    GetMem(p, size);
    FillChar(p^, size, $CC);
    for j := 1 to 40 do
    begin
      size := 1 + Rnd(2600);
      ReallocMem(p, size);
      FillChar(p^, size, $CC);
    end;
    FreeMem(p);
  end;
  Writeln('Phase 3 PASS');
end;

begin
  Writeln('Installation state = ', Ord(FastMM_GetInstallationState), '  (3 = mmisInstalled)');
  Phase1;
  Phase2;
  Phase3;
  Writeln('PASS: all phases completed');
end.
