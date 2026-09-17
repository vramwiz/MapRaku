// 入力欄のHEXとRGB十進表記を同じRGB色へ正規化する。
unit MapRakuColorCode;

interface

uses Vcl.Graphics;

function TryParseColorCode(const Text: string; out Color: TColor): Boolean;

implementation

uses System.Math, System.SysUtils, Winapi.Windows;

function TryParseColorCode(const Text: string; out Color: TColor): Boolean;
var
  HexText: string;
  Parts: TArray<string>;
  RedValue: Integer;
  GreenValue: Integer;
  BlueValue: Integer;
begin
  Result := False;
  HexText := Trim(Text);
  if HexText.StartsWith('#') then
    Delete(HexText, 1, 1);
  if (Length(HexText) = 6) and TryStrToInt('$' + HexText, RedValue) then
  begin
    Color := RGB((RedValue shr 16) and $FF, (RedValue shr 8) and $FF, RedValue and $FF);
    Exit(True);
  end;

  HexText := Trim(Text);
  if (Length(HexText) >= 5) and SameText(Copy(HexText, 1, 4), 'rgb(') and
    (HexText[Length(HexText)] = ')') then
    HexText := Copy(HexText, 5, Length(HexText) - 5);
  Parts := HexText.Split([',']);
  if (Length(Parts) <> 3) or not TryStrToInt(Trim(Parts[0]), RedValue) or
    not TryStrToInt(Trim(Parts[1]), GreenValue) or
    not TryStrToInt(Trim(Parts[2]), BlueValue) then
    Exit;
  if not InRange(RedValue, 0, 255) or not InRange(GreenValue, 0, 255) or
    not InRange(BlueValue, 0, 255) then
    Exit;
  Color := RGB(RedValue, GreenValue, BlueValue);
  Result := True;
end;

end.
