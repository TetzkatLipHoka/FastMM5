program bench;
{Throughput benchmark for comparing the PurePascal and BASM builds of FastMM5 under FPC.
 Build BASM:        fpc -B -Mdelphi -Fu.. -O2 bench.dpr
 Build PurePascal:  fpc -B -Mdelphi -Fu.. -O2 -dPurePascal bench.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  Windows, FastMM5, SysUtils;

var
  QPF: Int64;

function Secs(AStart, AStop: Int64): Double;
begin
  Result := (AStop - AStart) / QPF;
end;

procedure Report(const AName: string; AOps: Int64; ASeconds: Double);
begin
  Writeln(Format('%-28s %8.0f ops/ms  (%6.2f s)', [AName, AOps / 1000.0 / ASeconds, ASeconds]));
end;

procedure BenchPingPong(ASize: Integer; AIters: Integer);
var
  t0, t1: Int64;
  i: Integer;
  p: Pointer;
begin
  QueryPerformanceCounter(t0);
  for i := 1 to AIters do
  begin
    GetMem(p, ASize);
    FreeMem(p);
  end;
  QueryPerformanceCounter(t1);
  Report(Format('ping-pong %d B', [ASize]), Int64(AIters) * 2, Secs(t0, t1));
end;

procedure BenchBatch(ASize, ABatch, ARounds: Integer);
var
  t0, t1: Int64;
  i, r: Integer;
  ptrs: array of Pointer;
begin
  SetLength(ptrs, ABatch);
  QueryPerformanceCounter(t0);
  for r := 1 to ARounds do
  begin
    for i := 0 to ABatch - 1 do
      GetMem(ptrs[i], ASize);
    for i := 0 to ABatch - 1 do
      FreeMem(ptrs[i]);
  end;
  QueryPerformanceCounter(t1);
  Report(Format('batch %d B x%d', [ASize, ABatch]), Int64(ARounds) * ABatch * 2, Secs(t0, t1));
end;

procedure BenchMixed(AIters: Integer);
var
  t0, t1: Int64;
  i, s: Integer;
  seed: Cardinal;
  slots: array[0..255] of Pointer;
begin
  FillChar(slots, SizeOf(slots), 0);
  seed := $1234ABCD;
  QueryPerformanceCounter(t0);
  for i := 1 to AIters do
  begin
    seed := seed xor (seed shl 13);
    seed := seed xor (seed shr 17);
    seed := seed xor (seed shl 5);
    s := Integer(seed and 255);
    if slots[s] = nil then
      GetMem(slots[s], 1 + Integer(seed mod 65536))
    else
    begin
      FreeMem(slots[s]);
      slots[s] := nil;
    end;
  end;
  QueryPerformanceCounter(t1);
  for s := 0 to 255 do
    if slots[s] <> nil then
      FreeMem(slots[s]);
  Report('mixed 1..64k B', AIters, Secs(t0, t1));
end;

procedure BenchRealloc(AIters: Integer);
var
  t0, t1: Int64;
  i: Integer;
  p: Pointer;
begin
  GetMem(p, 16);
  QueryPerformanceCounter(t0);
  for i := 1 to AIters do
    ReallocMem(p, 16 + ((i * 61) mod 4000));
  QueryPerformanceCounter(t1);
  FreeMem(p);
  Report('realloc chain', AIters, Secs(t0, t1));
end;

var
  GMTIters: Integer;

function MTThread(AParam: Pointer): Integer; stdcall;
var
  i: Integer;
  p: Pointer;
begin
  for i := 1 to GMTIters do
  begin
    GetMem(p, 64);
    FreeMem(p);
  end;
  Result := 0;
end;

procedure BenchMT(AThreads, AIters: Integer);
var
  t0, t1: Int64;
  h: array[0..31] of THandle;
  id: Cardinal;
  i: Integer;
begin
  GMTIters := AIters;
  QueryPerformanceCounter(t0);
  for i := 0 to AThreads - 1 do
    h[i] := CreateThread(nil, 0, @MTThread, nil, 0, id);
  for i := 0 to AThreads - 1 do
  begin
    WaitForSingleObject(h[i], INFINITE);
    CloseHandle(h[i]);
  end;
  QueryPerformanceCounter(t1);
  Report(Format('MT %d threads 64 B', [AThreads]), Int64(AThreads) * AIters * 2, Secs(t0, t1));
end;

begin
  QueryPerformanceFrequency(QPF);
  {$ifdef PurePascal}
  Writeln('build: PurePascal');
  {$else}
  Writeln('build: BASM (X86ASM)');
  {$endif}
  Writeln('state=', Ord(FastMM_GetInstallationState));

  {Warm up}
  BenchPingPong(64, 1000000);
  Writeln('--- measured ---');

  BenchPingPong(16, 20000000);
  BenchPingPong(64, 20000000);
  BenchPingPong(256, 20000000);
  BenchPingPong(1024, 20000000);
  BenchBatch(64, 4000, 2000);
  BenchBatch(512, 4000, 2000);
  BenchMixed(10000000);
  BenchRealloc(5000000);
  BenchMT(4, 5000000);
  BenchMT(8, 3000000);
end.
