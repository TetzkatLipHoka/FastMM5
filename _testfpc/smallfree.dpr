program smallfree;
{Instrumented reproduction of the FPC PurePascal small-block free crash.
 Allocates N small blocks, validates each block's header + derived span pointer from the outside,
 then frees them one by one with progress output to pinpoint the crashing free.
 Build:  fpc -Mdelphi -Fu.. smallfree.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  FastMM5, SysUtils;

const
  CBlockCount = 1000;
  CBlockSize = 64;

  {Mirrors of FastMM5 internals (verified against FastMM5.pas):}
  CSmallBlockHeaderSize = 2;
  CBlockIsFreeFlag = 1;
  CHasDebugInfoFlag = 2;
  CIsSmallBlockFlag = 4;
  CSmallBlockSpanOffsetBitShift = 3;

var
  ptrs: array[0..CBlockCount - 1] of Pointer;
  i: Integer;
  hdr: Word;
  span, prevspan: NativeUInt;
  badHeaders: Integer;

function HeaderOf(p: Pointer): Word;
begin
  Result := PWord(NativeUInt(p) - CSmallBlockHeaderSize)^;
end;

function SpanOf(p: Pointer; AHdr: Word): NativeUInt;
begin
  Result := (NativeUInt(p) and not NativeUInt(63))
    - (NativeUInt(AHdr and $FFF8) shl CSmallBlockSpanOffsetBitShift);
end;

begin
  Writeln('Installation state = ', Ord(FastMM_GetInstallationState), '  (3 = mmisInstalled)');

  {Phase 1: allocate}
  for i := 0 to CBlockCount - 1 do
  begin
    GetMem(ptrs[i], CBlockSize);
    FillChar(ptrs[i]^, CBlockSize, $AA);
  end;
  Writeln('Allocated ', CBlockCount, ' blocks of ', CBlockSize, ' bytes');

  {Phase 2: validate all headers before touching free}
  badHeaders := 0;
  prevspan := 0;
  for i := 0 to CBlockCount - 1 do
  begin
    hdr := HeaderOf(ptrs[i]);
    span := SpanOf(ptrs[i], hdr);
    if (hdr and CIsSmallBlockFlag = 0) or (hdr and CBlockIsFreeFlag <> 0) then
    begin
      Inc(badHeaders);
      if badHeaders <= 10 then
        Writeln('BAD HEADER i=', i, ' p=', IntToHex(NativeUInt(ptrs[i]), 8),
          ' hdr=', IntToHex(hdr, 4), ' span=', IntToHex(span, 8));
    end;
    if span <> prevspan then
    begin
      Writeln('i=', i, ' p=', IntToHex(NativeUInt(ptrs[i]), 8),
        ' hdr=', IntToHex(hdr, 4), ' -> new span=', IntToHex(span, 8));
      prevspan := span;
    end;
  end;
  Writeln('Header validation done, bad headers = ', badHeaders);

  {Phase 3: free with progress}
  for i := 0 to CBlockCount - 1 do
  begin
    if (i mod 50 = 0) or (i >= CBlockCount - 5) then
      Writeln('freeing i=', i, ' p=', IntToHex(NativeUInt(ptrs[i]), 8),
        ' hdr=', IntToHex(HeaderOf(ptrs[i]), 4));
    FreeMem(ptrs[i]);
  end;

  Writeln('PASS: all ', CBlockCount, ' small blocks freed without crash');
end.
