// Windows IMEの確定前入力と、描画側で保持する文字編集バッファの操作を担当する。
unit MapRakuTextEditing;

interface

uses
  System.Types, Winapi.Messages, Vcl.Graphics, Vcl.StdCtrls;

type
  TMapRakuCommittedTextEvent = procedure(Sender: TObject;
    const Text: string) of object;
  TMapRakuCompositionEvent = procedure(Sender: TObject;
    const Text: string; CursorPosition: Integer; Active: Boolean) of object;

  TMapRakuCaretLine = record
    EndIndex: Integer;   // 改行文字を含まないUTF-16終端位置。
    StartIndex: Integer; // 行先頭の直前にあるUTF-16位置。
    Text: string;        // 折り返し後にこの行へ表示する文字列。
  end;

  TMapRakuImeEdit = class(TEdit)
  private
    FOnCommittedText: TMapRakuCommittedTextEvent;
    FOnComposition: TMapRakuCompositionEvent;
    procedure WMChar(var Message: TWMChar); message WM_CHAR;
    procedure WMImeComposition(var Message: TMessage);
      message WM_IME_COMPOSITION;
    procedure WMImeEndComposition(var Message: TMessage);
      message WM_IME_ENDCOMPOSITION;
    procedure WMImeStartComposition(var Message: TMessage);
      message WM_IME_STARTCOMPOSITION;
  public
    // IMEまたは通常キー入力が確定した文字列を通知する。
    property OnCommittedText: TMapRakuCommittedTextEvent
      read FOnCommittedText write FOnCommittedText;
    // IME未確定文字列、変換カーソル位置、変換中かどうかを通知する。
    property OnComposition: TMapRakuCompositionEvent
      read FOnComposition write FOnComposition;
  end;

// 明示改行とWrapWidthによる折り返しを反映した仮想カーソル行を返す。
function BuildMapRakuTextCaretLines(const Text, FontFamily: string;
  FontSize, WrapWidth: Single;
  FontStyle: TFontStyles = []; LetterSpacingRatio: Single = 0;
  LineSpacingRatio: Single = 0): TArray<TMapRakuCaretLine>;
// 指定行の横位置に最も近いUTF-16カーソル位置を返す。
function MapRakuTextCaretIndexAtLineX(
  const Line: TMapRakuCaretLine; const FontFamily: string;
  FontSize, TargetX: Single; FontStyle: TFontStyles = [];
  LetterSpacingRatio: Single = 0): Integer;
// 折り返し後の組版座標から、最も近い行と文字間のUTF-16位置を返す。
function MapRakuTextCaretIndexAtPoint(const Text, FontFamily: string;
  FontSize, WrapWidth, TargetX, TargetY: Single;
  FontStyle: TFontStyles = []; LetterSpacingRatio: Single = 0;
  LineSpacingRatio: Single = 0): Integer;
// 選択範囲を削除してカーソルを範囲先頭へ移し、削除した場合にTrueを返す。
function DeleteMapRakuTextSelection(var Text: string;
  var CaretIndex, SelectionAnchor: Integer;
  var PreferredCaretX: Single): Boolean;
// 選択範囲を置換してTextを挿入し、カーソルを挿入末尾へ移す。
procedure InsertMapRakuTextAtCaret(var Buffer: string;
  var CaretIndex, SelectionAnchor: Integer; var PreferredCaretX: Single;
  const Text: string);
// サロゲートペアとCRLFを分割せず左右へ移動し、必要なら選択を拡張する。
procedure MoveMapRakuTextCaretHorizontal(const Text: string;
  var CaretIndex, SelectionAnchor: Integer; var PreferredCaretX: Single;
  Direction: Integer; ExtendSelection: Boolean);

implementation

uses
  System.Generics.Collections, System.Math, System.Skia, Winapi.Imm,
  MapRakuTextGeometry;

function BuildMapRakuTextCaretLines(const Text, FontFamily: string;
  FontSize, WrapWidth: Single;
  FontStyle: TFontStyles; LetterSpacingRatio,
  LineSpacingRatio: Single): TArray<TMapRakuCaretLine>;
var
  Candidate: string;
  CharacterLength: Integer;
  CurrentLine: TMapRakuCaretLine;
  Font: ISkFont;
  I: Integer;
  Lines: TList<TMapRakuCaretLine>;
  NewLineLength: Integer;
  NextCharacter: string;
  LetterSpacing: Single;
begin
  Font := CreateMapRakuTextFont(FontFamily, FontSize, FontStyle);
  LetterSpacing := FontSize * LetterSpacingRatio;
  Lines := TList<TMapRakuCaretLine>.Create;
  try
    CurrentLine := Default(TMapRakuCaretLine);
    CurrentLine.StartIndex := 0;
    I := 1;
    while I <= Length(Text) do
    begin
      NewLineLength := 0;
      if Text[I] = #13 then
      begin
        NewLineLength := 1;
        if (I < Length(Text)) and (Text[I + 1] = #10) then
          NewLineLength := 2;
      end
      else if Text[I] = #10 then
        NewLineLength := 1;
      if NewLineLength > 0 then
      begin
        CurrentLine.EndIndex := I - 1;
        Lines.Add(CurrentLine);
        Inc(I, NewLineLength);
        CurrentLine := Default(TMapRakuCaretLine);
        CurrentLine.StartIndex := I - 1;
        Continue;
      end;
      CharacterLength := MapRakuTextUnitLengthAt(Text, I);
      NextCharacter := Copy(Text, I, CharacterLength);
      Candidate := CurrentLine.Text + NextCharacter;
      if (CurrentLine.Text <> '') and (WrapWidth > 0) and
        (MeasureMapRakuText(Candidate, Font, LetterSpacing) >
          WrapWidth) then
      begin
        CurrentLine.EndIndex := I - 1;
        Lines.Add(CurrentLine);
        CurrentLine := Default(TMapRakuCaretLine);
        CurrentLine.StartIndex := I - 1;
        CurrentLine.Text := NextCharacter;
      end
      else
        CurrentLine.Text := Candidate;
      Inc(I, CharacterLength);
    end;
    CurrentLine.EndIndex := Length(Text);
    Lines.Add(CurrentLine);
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

function MapRakuTextCaretIndexAtLineX(
  const Line: TMapRakuCaretLine; const FontFamily: string;
  FontSize, TargetX: Single; FontStyle: TFontStyles;
  LetterSpacingRatio: Single): Integer;
var
  CharacterLength: Integer;
  Font: ISkFont;
  I: Integer;
  PreviousWidth: Single;
  Width: Single;
begin
  Result := Line.StartIndex;
  Font := CreateMapRakuTextFont(FontFamily, FontSize, FontStyle);
  PreviousWidth := 0;
  I := 1;
  while I <= Length(Line.Text) do
  begin
    CharacterLength := MapRakuTextUnitLengthAt(Line.Text, I);
    Width := MeasureMapRakuText(Copy(Line.Text, 1,
      I + CharacterLength - 1), Font, FontSize * LetterSpacingRatio);
    if TargetX < (PreviousWidth + Width) * 0.5 then
      Exit;
    Inc(Result, CharacterLength);
    PreviousWidth := Width;
    Inc(I, CharacterLength);
  end;
end;

function MapRakuTextCaretIndexAtPoint(const Text, FontFamily: string;
  FontSize, WrapWidth, TargetX, TargetY: Single;
  FontStyle: TFontStyles; LetterSpacingRatio,
  LineSpacingRatio: Single): Integer;
var
  Font: ISkFont;
  LineHeight: Single;
  LineIndex: Integer;
  Lines: TArray<TMapRakuCaretLine>;
begin
  Lines := BuildMapRakuTextCaretLines(Text, FontFamily, FontSize,
    WrapWidth, FontStyle, LetterSpacingRatio, LineSpacingRatio);
  if Length(Lines) = 0 then
    Exit(0);
  Font := CreateMapRakuTextFont(FontFamily, FontSize, FontStyle);
  LineHeight := Max(Font.Spacing + FontSize * LineSpacingRatio, 1.0);
  LineIndex := EnsureRange(Floor(TargetY / Max(LineHeight, 1.0)), 0,
    High(Lines));
  Result := MapRakuTextCaretIndexAtLineX(Lines[LineIndex],
    FontFamily, FontSize, TargetX, FontStyle, LetterSpacingRatio);
end;

function DeleteMapRakuTextSelection(var Text: string;
  var CaretIndex, SelectionAnchor: Integer;
  var PreferredCaretX: Single): Boolean;
var
  SelectionEnd: Integer;
  SelectionStart: Integer;
begin
  SelectionStart := Min(CaretIndex, SelectionAnchor);
  SelectionEnd := Max(CaretIndex, SelectionAnchor);
  Result := SelectionStart <> SelectionEnd;
  if not Result then
    Exit;
  Delete(Text, SelectionStart + 1, SelectionEnd - SelectionStart);
  CaretIndex := SelectionStart;
  SelectionAnchor := SelectionStart;
  PreferredCaretX := -1.0;
end;

procedure InsertMapRakuTextAtCaret(var Buffer: string;
  var CaretIndex, SelectionAnchor: Integer; var PreferredCaretX: Single;
  const Text: string);
begin
  if Text = '' then
    Exit;
  DeleteMapRakuTextSelection(Buffer, CaretIndex, SelectionAnchor,
    PreferredCaretX);
  Insert(Text, Buffer, CaretIndex + 1);
  Inc(CaretIndex, Length(Text));
  SelectionAnchor := CaretIndex;
  PreferredCaretX := -1.0;
end;

procedure MoveMapRakuTextCaretHorizontal(const Text: string;
  var CaretIndex, SelectionAnchor: Integer; var PreferredCaretX: Single;
  Direction: Integer; ExtendSelection: Boolean);
var
  SelectionEnd: Integer;
  SelectionStart: Integer;
begin
  SelectionStart := Min(CaretIndex, SelectionAnchor);
  SelectionEnd := Max(CaretIndex, SelectionAnchor);
  if not ExtendSelection and (SelectionStart <> SelectionEnd) then
  begin
    if Direction < 0 then
      CaretIndex := SelectionStart
    else
      CaretIndex := SelectionEnd;
  end
  else if Direction < 0 then
  begin
    if CaretIndex > 0 then
      Dec(CaretIndex);
    if (CaretIndex > 0) and (Ord(Text[CaretIndex]) >= $D800) and
      (Ord(Text[CaretIndex]) <= $DBFF) then
      Dec(CaretIndex);
    if (CaretIndex > 0) and (Text[CaretIndex] = #13) and
      (Text[CaretIndex + 1] = #10) then
      Dec(CaretIndex);
  end
  else
  begin
    if CaretIndex < Length(Text) then
      Inc(CaretIndex);
    if (CaretIndex < Length(Text)) and
      (Ord(Text[CaretIndex]) >= $D800) and
      (Ord(Text[CaretIndex]) <= $DBFF) then
      Inc(CaretIndex);
    if (CaretIndex < Length(Text)) and (Text[CaretIndex] = #13) and
      (Text[CaretIndex + 1] = #10) then
      Inc(CaretIndex);
  end;
  if not ExtendSelection then
    SelectionAnchor := CaretIndex;
  PreferredCaretX := -1.0;
end;

procedure TMapRakuImeEdit.WMChar(var Message: TWMChar);
begin
  if (Message.CharCode >= 32) and Assigned(FOnCommittedText) then
    FOnCommittedText(Self, string(WideChar(Message.CharCode)));
  // 確定文字はDocument側へ渡し、Edit自身の文字列には残さない。
  Message.Result := 0;
end;

procedure TMapRakuImeEdit.WMImeComposition(var Message: TMessage);
var
  ByteCount: Integer;
  CompositionCursor: Integer;
  CompositionText: string;
  InputContext: HIMC;
begin
  CompositionText := '';
  CompositionCursor := 0;
  InputContext := ImmGetContext(Handle);
  if InputContext <> 0 then
  try
    ByteCount := ImmGetCompositionStringW(InputContext, GCS_COMPSTR,
      nil, 0);
    if ByteCount > 0 then
    begin
      SetLength(CompositionText, ByteCount div SizeOf(Char));
      ImmGetCompositionStringW(InputContext, GCS_COMPSTR,
        PChar(CompositionText), ByteCount);
    end;
    CompositionCursor := ImmGetCompositionStringW(InputContext,
      GCS_CURSORPOS, nil, 0);
    if CompositionCursor < 0 then
      CompositionCursor := 0;
  finally
    ImmReleaseContext(Handle, InputContext);
  end;
  inherited;
  if Assigned(FOnComposition) then
    FOnComposition(Self, CompositionText, CompositionCursor, True);
end;

procedure TMapRakuImeEdit.WMImeEndComposition(var Message: TMessage);
begin
  inherited;
  if Assigned(FOnComposition) then
    FOnComposition(Self, '', 0, False);
end;

procedure TMapRakuImeEdit.WMImeStartComposition(var Message: TMessage);
begin
  inherited;
  if Assigned(FOnComposition) then
    FOnComposition(Self, '', 0, True);
end;

end.
