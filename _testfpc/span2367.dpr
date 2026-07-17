program span2367;
{Diagnoses the size-2367 span-release crash.  Reads FastMM5 internal structures from the outside:
   small block header word at p-2 -> span base
   32-bit TSmallBlockSpanHeader: +0 Next, +4 Prev, +8 FirstFree, +12 Manager, +16 TotalBlocks, +20 BlocksInUse
   medium block header at spanbase-8: SizeMultiple(Word), SpanOffsetMultiple(Word), PrevBlockIsFree(Byte), IsSmallBlockSpan(Byte), StatusFlags(Word)
 Build:  fpc -B -Mdelphi -Fu.. -gl span2367.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  Windows, FastMM5, SysUtils;

const
  CN = 700;
  CSize = 2367;

type
  TMedHdr = packed record
    SizeMul: Word;
    SpanOffMul: Word;
    PrevFree: ByteBool;
    IsSmallSpan: ByteBool;
    Flags: Word;
  end;
  PMedHdr = ^TMedHdr;

var
  ptrs: array[0..CN - 1] of Pointer;
  i: Integer;
  hdr: Word;
  span, prevspan: NativeUInt;
  mh: PMedHdr;
  mbi: TMemoryBasicInformation;

function SpanOf(p: Pointer): NativeUInt;
var
  h: Word;
begin
  h := PWord(NativeUInt(p) - 2)^;
  Result := (NativeUInt(p) and not NativeUInt(63)) - (NativeUInt(h and $FFF8) shl 3);
end;

procedure DumpSpan(ASpan: NativeUInt; const AWhen: string);
var
  m: PMedHdr;
  medsize, regionend: NativeUInt;
begin
  m := PMedHdr(ASpan - 8);
  medsize := NativeUInt(m.SizeMul) shl 6;
  VirtualQuery(Pointer(ASpan), mbi, SizeOf(mbi));
  regionend := NativeUInt(mbi.BaseAddress) + mbi.RegionSize;
  Writeln(AWhen, ' span=', IntToHex(ASpan, 8),
    ' medsize=', medsize,
    ' spanoffmul=', m.SpanOffMul,
    ' issmallspan=', Ord(m.IsSmallSpan),
    ' flags=', IntToHex(m.Flags, 4),
    ' total=', PInteger(ASpan + 16)^,
    ' inuse=', PInteger(ASpan + 20)^,
    ' commit_end=', IntToHex(regionend, 8),
    ' span_end=', IntToHex(ASpan + medsize, 8),
    ' OVER=', Ord(ASpan + medsize > regionend));
end;

begin
  Writeln('state=', Ord(FastMM_GetInstallationState));
  for i := 0 to CN - 1 do
  begin
    GetMem(ptrs[i], CSize);
    FillChar(ptrs[i]^, CSize, $AA);
  end;

  prevspan := 0;
  for i := 0 to CN - 1 do
  begin
    span := SpanOf(ptrs[i]);
    if span <> prevspan then
    begin
      Writeln('block i=', i, ' p=', IntToHex(NativeUInt(ptrs[i]), 8), ' hdr=', IntToHex(PWord(NativeUInt(ptrs[i]) - 2)^, 4));
      DumpSpan(span, 'after-alloc');
      prevspan := span;
    end;
  end;

  for i := 0 to CN - 1 do
  begin
    span := SpanOf(ptrs[i]);
    {If this span is about to be fully released, dump it first.}
    if PInteger(span + 20)^ = 1 then
    begin
      Writeln('freeing LAST block of span, i=', i);
      DumpSpan(span, 'pre-release');
      Flush(Output);
    end;
    FreeMem(ptrs[i]);
  end;
  Writeln('PASS');
end.
