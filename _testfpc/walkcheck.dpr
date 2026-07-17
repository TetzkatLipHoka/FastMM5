program walkcheck;
{Pinpoints the phase that corrupts the medium block heap:  repeats the sizefind sweep, but validates the
 entire heap with FastMM_WalkBlocks after every sub-phase.  The walk follows the same medium-block size
 chains as the crashing free path, so the first walk that reports an out-of-span block (or crashes)
 identifies the corrupting phase.
 Build:  fpc -B -Mdelphi -Fu.. -gl walkcheck.dpr}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  Windows, FastMM5, SysUtils;

const
  CN = 700;

{Not declared in the FPC 3.2.2 Windows unit.}
function AddVectoredExceptionHandler(First: DWORD; Handler: Pointer): Pointer; stdcall;
  external 'kernel32.dll' name 'AddVectoredExceptionHandler';

function VEHandler(ExceptionInfo: PEXCEPTION_POINTERS): LONG; stdcall;
var
  rec: PExceptionRecord;
begin
  rec := ExceptionInfo^.ExceptionRecord;
  if rec^.ExceptionCode = STATUS_ACCESS_VIOLATION then
  begin
    Writeln('=== ACCESS VIOLATION ===');
    Writeln('  code addr  = ', IntToHex(NativeUInt(rec^.ExceptionAddress), 8));
    Writeln('  operation  = ', rec^.ExceptionInformation[0], ' (0=read 1=write)');
    Writeln('  data addr  = ', IntToHex(NativeUInt(rec^.ExceptionInformation[1]), 8));
    Writeln('  FPCDIAG_LastMediumBlock = ', IntToHex(NativeUInt(FPCDIAG_LastMediumBlock), 8));
    Writeln('  FPCDIAG_LastBlockSize   = ', FPCDIAG_LastBlockSize);
    Writeln('  FPCDIAG_LastSpan        = ', IntToHex(NativeUInt(FPCDIAG_LastSpan), 8));
    Writeln('  FPCDIAG_LastSpanSize    = ', FPCDIAG_LastSpanSize);
    Writeln('  block+size (next hdr region) = ', IntToHex(NativeUInt(FPCDIAG_LastMediumBlock) + NativeUInt(FPCDIAG_LastBlockSize), 8));
    Flush(Output);
  end;
  Result := EXCEPTION_CONTINUE_SEARCH;
end;

var
  GSpanBase, GSpanEnd: NativeUInt;
  GBad: Boolean;
  GBadInfo: string;
  GBlocks: Integer;

procedure WalkCB(const ABlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo);
var
  a: NativeUInt;
begin
  Inc(GBlocks);
  a := NativeUInt(ABlockInfo.BlockAddress);
  case ABlockInfo.BlockType of
    btMediumBlockSpan:
    begin
      GSpanBase := a;
      GSpanEnd := a + NativeUInt(ABlockInfo.BlockSize);
    end;
    btMediumBlock, btSmallBlockSpan:
    begin
      if not GBad then
        if (a < GSpanBase + 64) or (a + NativeUInt(ABlockInfo.BlockSize) > GSpanEnd) then
        begin
          GBad := True;
          GBadInfo := 'block@' + IntToHex(a, 8) + ' size=' + IntToStr(ABlockInfo.BlockSize)
            + ' span=' + IntToHex(GSpanBase, 8) + '..' + IntToHex(GSpanEnd, 8)
            + ' type=' + IntToStr(Ord(ABlockInfo.BlockType));
        end;
    end;
  end;
end;

procedure CheckHeap(ASize: Integer; const APhase: string);
begin
  GBad := False;
  GBlocks := 0;
  GSpanBase := 0;
  GSpanEnd := High(NativeUInt);
  FastMM_WalkBlocks(WalkCB, [btMediumBlockSpan, btMediumBlock, btSmallBlockSpan]);
  if GBad then
  begin
    Writeln('HEAP CORRUPT after size ', ASize, ' phase ', APhase, ': ', GBadInfo);
    Halt(3);
  end;
end;

var
  ptrs: array[0..CN - 1] of Pointer;
  size, i, startsize: Integer;
begin
  AddVectoredExceptionHandler(1, @VEHandler);
  startsize := 1200;
  if ParamCount >= 1 then
    startsize := StrToInt(ParamStr(1));
  size := startsize;
  while size <= 2600 do
  begin
    for i := 0 to CN - 1 do
    begin
      GetMem(ptrs[i], size);
      FillChar(ptrs[i]^, size, $AA);
    end;
    CheckHeap(size, 'alloc');
    for i := 0 to CN - 1 do
      FreeMem(ptrs[i]);
    CheckHeap(size, 'fwd-free');
    for i := 0 to CN - 1 do
    begin
      GetMem(ptrs[i], size);
      FillChar(ptrs[i]^, size, $BB);
    end;
    CheckHeap(size, 'alloc2');
    for i := CN - 1 downto 0 do
      FreeMem(ptrs[i]);
    CheckHeap(size, 'rev-free');
    if size mod 100 = 0 then
      Writeln('size ', size, ' ok');
    Inc(size);
  end;
  Writeln('PASS');
end.
