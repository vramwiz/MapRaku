// 基本色と編集セッションの色履歴を表示し、文書内の使用色を重複なく収集する。
unit MapRakuColorHistory;

interface

uses System.Classes, System.Types, Vcl.Controls, Vcl.Graphics, MapRakuDocument;

type
  // 履歴または基本色のクリックを、実際の色適用を担当する所有元へ通知する。
  TMapRakuHistoryColorEvent = procedure(Sender: TObject; Color: TColor) of object;
  TMapRakuColorHistory = class(TCustomControl)
  private
    FColors: TArray<TColor>;                    // 新しく確定した順のRGB色。文書やレイヤーは所有しない。
    FOffset: Integer;                           // ホイールで表示する履歴の先頭位置。
    FOnSelect: TMapRakuHistoryColorEvent; // 色適用は所有元のピッカーへ委譲する。
    function CellRect(Index: Integer): TRect;
    procedure CollectLayer(Layer: TVectArtLayer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    // 基本16色と直近16色を表示する。古い履歴へはホイールで移動する。
    constructor Create(AOwner: TComponent); override;
    // RGBへ正規化して先頭へ移す。既存色を複製せず、文書の変更通知は発生させない。
    procedure AddColor(Value: TColor);
    // 現在の履歴を捨て、文書全体の描画色を取り込む。
    procedure LoadDocument(Document: TVectArtDocument);
    // 検証・表示用に独立した履歴のコピーを返す。
    function Colors: TArray<TColor>;
    // 選択色を通知するだけで、文書・Undo・ピッカー状態は変更しない。
    property OnSelect: TMapRakuHistoryColorEvent read FOnSelect write FOnSelect;
  end;

implementation

uses System.Math, Winapi.Windows, MapRakuPaintStyles, MapRakuPatternStyle,
  MapRakuColorTargets, MapRakuObjectPropertySelection, MapRakuObjectPropertyCommands;

const
  COLUMN_COUNT = 8; // 狭いプロパティ欄でも16色を2行で表示する。
  BASIC_COLORS: array[0..15] of TColor = // VCLの基本16色。履歴とは独立して常時表示する。
    (clBlack, clGray, clSilver, clWhite, clMaroon, clRed, clOlive, clYellow,
     clGreen, clLime, clTeal, clAqua, clNavy, clBlue, clPurple, clFuchsia);

constructor TMapRakuColorHistory.Create(AOwner: TComponent);
begin
  inherited;
  DoubleBuffered := True;
  ShowHint := True;
  Hint := '上段：色履歴（ホイールで移動） / 下段：基本16色';
end;

function TMapRakuColorHistory.Colors: TArray<TColor>;
begin
  Result := Copy(FColors);
end;

procedure TMapRakuColorHistory.AddColor(Value: TColor);
var
  I, Found: Integer;
begin
  Value := ColorToRGB(Value);
  Found := Length(FColors);
  for I := 0 to High(FColors) do
    if FColors[I] = Value then
    begin
      Found := I;
      Break;
    end;
  if Found = Length(FColors) then SetLength(FColors, Length(FColors) + 1);
  for I := Found downto 1 do FColors[I] := FColors[I - 1];
  FColors[0] := Value;
  FOffset := 0;
  Invalidate;
end;

procedure TMapRakuColorHistory.CollectLayer(Layer: TVectArtLayer);
var
  I: Integer;
  Value: TColor;
  Target: TMapRakuLayerColorTarget;
  Style: TMapRakuPaintStyle;
  Stop: TMapRakuGradientStop;
  Slot: TMapRakuPatternColor;
begin
  if Layer is TMapRakuGroupLayer then
    for I := 0 to TMapRakuGroupLayer(Layer).ChildCount - 1 do
      CollectLayer(TMapRakuGroupLayer(Layer).Children[I]);
  if (Layer is TVectArtCanvasLayer) and not TVectArtCanvasLayer(Layer).Transparent then
    AddColor(TVectArtCanvasLayer(Layer).BackgroundColor);
  if (Layer is TMapRakuShapeLayer) and (TMapRakuShapeLayer(Layer).StrokeWidth > 0) then
    AddColor(TMapRakuShapeLayer(Layer).StrokeColor);
  Style := Layer.PaintStyle;
  case Style.Kind of
    slpkGradient:
      begin
        AddColor(Style.GradientStartColor);
        for Stop in Style.GetGradientStops do AddColor(Stop.Color);
        AddColor(Style.GradientEndColor);
      end;
    slpkPattern:
      for Slot in Style.Pattern.Colors do AddColor(Slot.Color);
    slpkSolid:
      if TryGetMapRakuLayerColor(Layer, Value, Target) then AddColor(Value);
  end;
  for I := 0 to Layer.FilterCount - 1 do
    if TryGetMapRakuFilterColor(Layer.Filters[I], Value) then AddColor(Value);
end;

procedure TMapRakuColorHistory.LoadDocument(Document: TVectArtDocument);
var
  I: Integer;
begin
  FColors := nil;
  FOffset := 0;
  if Document <> nil then
    for I := 0 to Document.LayerCount - 1 do CollectLayer(Document.Layers[I]);
  Invalidate;
end;

function TMapRakuColorHistory.CellRect(Index: Integer): TRect;
var
  Row, Gap, LabelHeight, CellHeight: Integer;
begin
  Gap := MulDiv(2, CurrentPPI, 96);
  LabelHeight := MulDiv(14, CurrentPPI, 96);
  CellHeight := Max((ClientHeight - LabelHeight - Gap) div 4, 1);
  Row := Index div COLUMN_COUNT;
  Result := Rect((Index mod COLUMN_COUNT) * ClientWidth div COLUMN_COUNT,
    LabelHeight + Row * CellHeight + Ord(Row >= 2) * Gap,
    ((Index mod COLUMN_COUNT) + 1) * ClientWidth div COLUMN_COUNT - Gap,
    LabelHeight + (Row + 1) * CellHeight - Gap + Ord(Row >= 2) * Gap);
end;

procedure TMapRakuColorHistory.Paint;
var
  I: Integer;
  R: TRect;
begin
  Canvas.Brush.Color := TColor($00212121);
  Canvas.FillRect(ClientRect);
  Canvas.Font.Color := clSilver;
  Canvas.Font.Height := -MulDiv(11, CurrentPPI, 96);
  Canvas.TextOut(0, 0, '履歴 / 基本色');
  for I := 0 to 31 do
  begin
    R := CellRect(I);
    if I >= 16 then Canvas.Brush.Color := BASIC_COLORS[I - 16]
    else if I + FOffset < Length(FColors) then Canvas.Brush.Color := FColors[I + FOffset]
    else Canvas.Brush.Color := TColor($00303030);
    Canvas.Pen.Color := clGray;
    Canvas.Rectangle(R);
  end;
end;

procedure TMapRakuColorHistory.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  Value: TColor;
begin
  inherited;
  if not Enabled or (Button <> mbLeft) then Exit;
  for I := 0 to 31 do
    if PtInRect(CellRect(I), Point(X, Y)) then
    begin
      if I >= 16 then Value := BASIC_COLORS[I - 16]
      else if I + FOffset < Length(FColors) then Value := FColors[I + FOffset]
      else Exit;
      if Assigned(FOnSelect) then FOnSelect(Self, Value);
      Exit;
    end;
end;

function TMapRakuColorHistory.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  FOffset := EnsureRange(FOffset - Sign(WheelDelta) * COLUMN_COUNT, 0, Max(Length(FColors) - 16, 0));
  Invalidate;
  Result := True;
end;

end.
