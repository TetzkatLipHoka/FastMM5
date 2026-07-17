unit foreignpre;
{Allocates blocks in its initialization section.  Listed BEFORE FastMM5 in the test program's uses clause, so these
 allocations are made by the FPC default memory manager before FastMM installs - i.e. they are foreign blocks that
 FastMM must forward to the previous memory manager when they are later freed, reallocated or measured.}
{$mode delphi}
interface

var
  ForeignSmall: Pointer;      {64 bytes}
  ForeignLarge: Pointer;      {300000 bytes}
  ForeignString: AnsiString;  {RTL-allocated string data}

implementation

initialization
  GetMem(ForeignSmall, 64);
  FillChar(ForeignSmall^, 64, $5A);
  GetMem(ForeignLarge, 300000);
  FillChar(ForeignLarge^, 300000, $C3);
  ForeignString := 'allocated before FastMM installs';
  UniqueString(ForeignString);
end.
