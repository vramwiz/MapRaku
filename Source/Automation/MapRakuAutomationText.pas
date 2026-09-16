// AIの文字配置案を、キャンバスと共通のSkia組版で計測する。
unit MapRakuAutomationText;

interface

uses System.JSON;

// 横書き通常文字の組版寸法を返す。変形・縁取り・影は描画プレビューで確認する。
function MeasureMapRakuAutomationText(Request: TJSONObject): TJSONObject;
// 現在のWindowsセッションで使用できるフォントファミリーを返す。
function MapRakuAutomationFonts: TJSONArray;

implementation

uses
  System.SysUtils, System.Math, System.Skia, Vcl.Forms, Vcl.Graphics,
  MapRakuTextGeometry, MapRakuDocument;

function NumberField(Request: TJSONObject; const Name: string;
  DefaultValue, Minimum, Maximum: Double): Double;
var
  Value: TJSONValue;
begin
  Value := Request.GetValue(Name);
  if Value = nil then
    Exit(DefaultValue);
  if not (Value is TJSONNumber) then
    raise EArgumentException.Create(Name + ' must be a number.');
  Result := TJSONNumber(Value).AsDouble;
  if IsNan(Result) or IsInfinite(Result) or (Result < Minimum) or (Result > Maximum) then
    raise EArgumentException.Create(Name + ' is out of range.');
end;

function BooleanField(Request: TJSONObject; const Name: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := Request.GetValue(Name);
  if Value = nil then
    Exit(False);
  if not (Value is TJSONBool) then
    raise EArgumentException.Create(Name + ' must be a boolean.');
  Result := TJSONBool(Value).AsBoolean;
end;

function MeasureMapRakuAutomationText(Request: TJSONObject): TJSONObject;
var
  Layout: TMapRakuTextLayout;
  Font: ISkFont;
  Styles: TFontStyles;
  Text, Family: string;
  Size, MaxWidth, MaxHeight, LetterSpacing, LineSpacing: Single;
  Lines: TJSONArray;
  Line: TJSONObject;
  Value: TJSONValue;
  I: Integer;
begin
  Value := Request.GetValue('text');
  if not (Value is TJSONString) then
    raise EArgumentException.Create('text must be a string.');
  Text := Value.Value;
  if Length(Text) > 4096 then
    raise EArgumentException.Create('text is limited to 4096 UTF-16 code units.');
  Family := 'Yu Gothic UI';
  Value := Request.GetValue('font_family');
  if Value <> nil then
  begin
    if not (Value is TJSONString) then
      raise EArgumentException.Create('font_family must be a string.');
    Family := Value.Value;
  end;
  Size := NumberField(Request, 'font_size', 64, 1, 4096);
  MaxWidth := NumberField(Request, 'max_width', 0, 0, 100000);
  MaxHeight := NumberField(Request, 'max_height', 0, 0, 100000);
  LetterSpacing := NumberField(Request, 'letter_spacing_ratio', 0,
    SCREEN_LAYOUT_TEXT_LETTER_SPACING_MIN, SCREEN_LAYOUT_TEXT_LETTER_SPACING_MAX);
  LineSpacing := NumberField(Request, 'line_spacing_ratio', 0,
    SCREEN_LAYOUT_TEXT_LINE_SPACING_MIN, SCREEN_LAYOUT_TEXT_LINE_SPACING_MAX);
  Styles := [];
  if BooleanField(Request, 'bold') then Include(Styles, fsBold);
  if BooleanField(Request, 'italic') then Include(Styles, fsItalic);
  Layout := BuildMapRakuTextLayout(Text, Family, Size, MaxWidth, Styles,
    LetterSpacing, LineSpacing);
  Font := CreateMapRakuTextFont(Family, Size, Styles);
  Result := TJSONObject.Create;
  try
    Result.AddPair('measurement_kind', 'untransformed_horizontal_layout');
    Result.AddPair('effects_included', TJSONBool.Create(False));
    Result.AddPair('font_family_requested', Family);
    Result.AddPair('font_family_resolved', Font.Typeface.FamilyName);
    Result.AddPair('width', TJSONNumber.Create(Layout.Width));
    Result.AddPair('height', TJSONNumber.Create(Layout.Height));
    Result.AddPair('ascent', TJSONNumber.Create(Layout.Ascent));
    Result.AddPair('line_height', TJSONNumber.Create(Layout.LineHeight));
    Result.AddPair('line_count', TJSONNumber.Create(Length(Layout.Lines)));
    Result.AddPair('fits_width', TJSONBool.Create((MaxWidth = 0) or (Layout.Width <= MaxWidth)));
    Result.AddPair('fits_height', TJSONBool.Create((MaxHeight = 0) or (Layout.Height <= MaxHeight)));
    Lines := TJSONArray.Create;
    Result.AddPair('lines', Lines);
    for I := 0 to High(Layout.Lines) do
    begin
      Line := TJSONObject.Create;
      Lines.AddElement(Line);
      Line.AddPair('text', Layout.Lines[I]);
      Line.AddPair('width', TJSONNumber.Create(MeasureMapRakuText(Layout.Lines[I],
        Font, Size * LetterSpacing)));
      Line.AddPair('baseline_y', TJSONNumber.Create(Layout.Ascent + I * Layout.LineHeight));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function MapRakuAutomationFonts: TJSONArray;
var
  I: Integer;
begin
  Result := TJSONArray.Create;
  for I := 0 to Screen.Fonts.Count - 1 do
    Result.Add(Screen.Fonts[I]);
end;

end.
