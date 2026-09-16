// 文字列の折り返し、行送り、実寸範囲をSkiaの文字計測から求める。
unit MapRakuTextGeometry;

interface

uses
  System.Skia, Vcl.Graphics;

type
  TMapRakuTextLayout = record
    Ascent: Single;        // 行上端からベースラインまでの距離。
    Height: Single;        // 全行を含む組版高。
    LineGapOffsets: TArray<Integer>; // 各表示行の先頭文字に対応する個別字間添字。
    Lines: TArray<string>; // 明示改行と幅折り返しを反映した表示行。
    LineHeight: Single;    // 連続するベースライン間の距離。
    Width: Single;         // 最長行の文字送り幅。
  end;

// 指定ファミリーを優先し、利用できない場合は既定書体を返す。
function CreateMapRakuTextFont(const FontFamily: string;
  FontSize: Single; FontStyle: TFontStyles = []): ISkFont;
// MaxWidthを超えない位置で文字単位に折り返し、空行を含む実寸を返す。
function BuildMapRakuTextLayout(const Text, FontFamily: string;
  FontSize, MaxWidth: Single;
  FontStyle: TFontStyles = []; LetterSpacingRatio: Single = 0;
  LineSpacingRatio: Single = 0): TMapRakuTextLayout; overload;
function BuildMapRakuTextLayout(const Text, FontFamily: string;
  FontSize, MaxWidth: Single; FontStyle: TFontStyles;
  LetterSpacingRatio, LineSpacingRatio: Single;
  const IndividualLetterSpacingRatios: TArray<Single>):
  TMapRakuTextLayout; overload;
// UTF-16のサロゲートペアを分割せず、Indexから始まる1文字の長さを返す。
function MapRakuTextUnitLengthAt(const Text: string;
  Index: Integer): Integer;
// Fontによる文字送りへ、文字間ごとの追加幅を加えた行幅を返す。
function MeasureMapRakuText(const Text: string; const Font: ISkFont;
  LetterSpacing: Single): Single; overload;
function MeasureMapRakuText(const Text: string; const Font: ISkFont;
  LetterSpacing, FontSize: Single;
  const IndividualLetterSpacingRatios: TArray<Single>;
  GapOffset: Integer = 0): Single; overload;

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils;

function MapRakuTextUnitLengthAt(const Text: string;
  Index: Integer): Integer;
begin
  Result := 1;
  if (Index >= 1) and (Index < Length(Text)) and
    (Ord(Text[Index]) >= $D800) and (Ord(Text[Index]) <= $DBFF) and
    (Ord(Text[Index + 1]) >= $DC00) and
    (Ord(Text[Index + 1]) <= $DFFF) then
    Result := 2;
end;

function MeasureMapRakuText(const Text: string; const Font: ISkFont;
  LetterSpacing: Single): Single;
begin
  Result := MeasureMapRakuText(Text, Font, LetterSpacing, 0, nil, 0);
end;

function MeasureMapRakuText(const Text: string; const Font: ISkFont;
  LetterSpacing, FontSize: Single;
  const IndividualLetterSpacingRatios: TArray<Single>;
  GapOffset: Integer): Single;
var
  GapIndex: Integer;
  I: Integer;
  UnitLength: Integer;
  UnitText: string;
begin
  if (Text = '') or (Font = nil) then
    Exit(0);
  if SameValue(LetterSpacing, 0) and
    (Length(IndividualLetterSpacingRatios) = 0) then
    Exit(Font.MeasureText(Text));
  Result := 0;
  GapIndex := GapOffset;
  I := 1;
  while I <= Length(Text) do
  begin
    UnitLength := MapRakuTextUnitLengthAt(Text, I);
    UnitText := Copy(Text, I, UnitLength);
    Result := Result + Font.MeasureText(UnitText);
    Inc(I, UnitLength);
    if I <= Length(Text) then
    begin
      Result := Result + LetterSpacing;
      if (GapIndex >= 0) and
        (GapIndex < Length(IndividualLetterSpacingRatios)) then
        Result := Result + FontSize *
          IndividualLetterSpacingRatios[GapIndex];
      Inc(GapIndex);
    end;
  end;
end;

procedure AppendWrappedParagraph(Lines: TList<string>; const Paragraph: string;
  const Font: ISkFont; MaxWidth, LetterSpacing, FontSize: Single;
  const IndividualLetterSpacingRatios: TArray<Single>;
  ParagraphGapOffset: Integer; GapOffsets: TList<Integer>);
var
  Candidate: string;
  CharacterLength: Integer;
  CurrentLine: string;
  I: Integer;
  NextCharacter: string;
  CurrentGapOffset: Integer;
  CurrentUnitCount: Integer;
begin
  if Paragraph = '' then
  begin
    Lines.Add('');
    GapOffsets.Add(ParagraphGapOffset);
    Exit;
  end;
  CurrentLine := '';
  CurrentGapOffset := ParagraphGapOffset;
  CurrentUnitCount := 0;
  I := 1;
  while I <= Length(Paragraph) do
  begin
    CharacterLength := MapRakuTextUnitLengthAt(Paragraph, I);
    NextCharacter := Copy(Paragraph, I, CharacterLength);
    Candidate := CurrentLine + NextCharacter;
    if (CurrentLine <> '') and (MaxWidth > 0) and
      (MeasureMapRakuText(Candidate, Font, LetterSpacing, FontSize,
        IndividualLetterSpacingRatios, CurrentGapOffset) > MaxWidth) then
    begin
      Lines.Add(CurrentLine);
      GapOffsets.Add(CurrentGapOffset);
      Inc(CurrentGapOffset, CurrentUnitCount);
      CurrentLine := NextCharacter;
      CurrentUnitCount := 1;
    end
    else
    begin
      CurrentLine := Candidate;
      Inc(CurrentUnitCount);
    end;
    Inc(I, CharacterLength);
  end;
  Lines.Add(CurrentLine);
  GapOffsets.Add(CurrentGapOffset);
end;

function CreateMapRakuTextFont(const FontFamily: string;
  FontSize: Single; FontStyle: TFontStyles): ISkFont;
var
  SkiaStyle: TSkFontStyle;
  Slant: TSkFontSlant;
  Typeface: ISkTypeface;
  Weight: TSkFontWeight;
begin
  if fsBold in FontStyle then
    Weight := TSkFontWeight.Bold
  else
    Weight := TSkFontWeight.Normal;
  if fsItalic in FontStyle then
    Slant := TSkFontSlant.Italic
  else
    Slant := TSkFontSlant.Upright;
  SkiaStyle := TSkFontStyle.Create(Weight, TSkFontWidth.Normal, Slant);
  Typeface := nil;
  if FontFamily <> '' then
    Typeface := TSkTypeface.MakeFromName(FontFamily, SkiaStyle);
  if Typeface = nil then
    Typeface := TSkTypeface.MakeFromName('Yu Gothic UI',
      SkiaStyle);
  if Typeface = nil then
    Typeface := TSkTypeface.MakeDefault;
  Result := TSkFont.Create(Typeface, Max(FontSize, 1.0));
  Result.Edging := TSkFontEdging.AntiAlias;
end;

function BuildMapRakuTextLayout(const Text, FontFamily: string;
  FontSize, MaxWidth: Single;
  FontStyle: TFontStyles; LetterSpacingRatio,
  LineSpacingRatio: Single): TMapRakuTextLayout;
begin
  Result := BuildMapRakuTextLayout(Text, FontFamily, FontSize,
    MaxWidth, FontStyle, LetterSpacingRatio, LineSpacingRatio, nil);
end;

function BuildMapRakuTextLayout(const Text, FontFamily: string;
  FontSize, MaxWidth: Single; FontStyle: TFontStyles; LetterSpacingRatio,
  LineSpacingRatio: Single;
  const IndividualLetterSpacingRatios: TArray<Single>):
  TMapRakuTextLayout;
var
  Font: ISkFont;
  FontMetrics: TSkFontMetrics;
  I: Integer;
  LetterSpacing: Single;
  GapOffsets: TList<Integer>;
  Lines: TList<string>;
  NormalizedText: string;
  Paragraphs: TArray<string>;
  ParagraphGapOffset: Integer;
  J: Integer;
begin
  Result := Default(TMapRakuTextLayout);
  Font := CreateMapRakuTextFont(FontFamily, FontSize, FontStyle);
  Font.GetMetrics(FontMetrics);
  LetterSpacing := FontSize * LetterSpacingRatio;
  Result.Ascent := Max(-FontMetrics.Ascent, 1.0);
  Result.LineHeight := Max(Font.Spacing + FontSize * LineSpacingRatio, 1.0);
  NormalizedText := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  NormalizedText := StringReplace(NormalizedText, #13, #10, [rfReplaceAll]);
  Paragraphs := NormalizedText.Split([#10], TStringSplitOptions.None);
  Lines := TList<string>.Create;
  GapOffsets := TList<Integer>.Create;
  try
    if Length(Paragraphs) = 0 then
    begin
      Lines.Add('');
      GapOffsets.Add(0);
    end
    else
    begin
      ParagraphGapOffset := 0;
      for I := 0 to High(Paragraphs) do
      begin
        AppendWrappedParagraph(Lines, Paragraphs[I], Font, MaxWidth,
          LetterSpacing, FontSize, IndividualLetterSpacingRatios,
          ParagraphGapOffset, GapOffsets);
        J := 1;
        while J <= Length(Paragraphs[I]) do
        begin
          Inc(ParagraphGapOffset);
          Inc(J, MapRakuTextUnitLengthAt(Paragraphs[I], J));
        end;
      end;
    end;
    Result.Lines := Lines.ToArray;
    Result.LineGapOffsets := GapOffsets.ToArray;
  finally
    GapOffsets.Free;
    Lines.Free;
  end;
  for I := 0 to High(Result.Lines) do
    Result.Width := Max(Result.Width, MeasureMapRakuText(
      Result.Lines[I], Font, LetterSpacing, FontSize,
      IndividualLetterSpacingRatios, Result.LineGapOffsets[I]));
  Result.Height := Max(Length(Result.Lines), 1) * Result.LineHeight;
end;

end.
