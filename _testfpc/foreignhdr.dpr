program foreignhdr;
{Dumps the word preceding foreign RTL blocks to design the foreign-block classifier.}
{$APPTYPE CONSOLE}{$mode delphi}
uses
  foreignpre, FastMM5, SysUtils;

procedure Dump(p: Pointer; const AName: string);
var
  w: Word;
  d: Cardinal;
begin
  w := PWord(NativeUInt(p) - 2)^;
  d := PCardinal(NativeUInt(p) - 4)^;
  Writeln(AName, ': p=', IntToHex(NativeUInt(p), 8),
    ' word[p-2]=', IntToHex(w, 4),
    ' dword[p-4]=', IntToHex(d, 8),
    ' dword[p-8]=', IntToHex(PCardinal(NativeUInt(p) - 8)^, 8));
end;

begin
  Writeln('state=', Ord(FastMM_GetInstallationState));
  Dump(ForeignSmall, 'ForeignSmall (64)');
  Dump(ForeignLarge, 'ForeignLarge (300000)');
  Dump(Pointer(ForeignString), 'ForeignString data');
  Writeln('done');
end.
