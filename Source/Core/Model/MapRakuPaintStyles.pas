// 塗り、線、文字の単色、グラデーション、パターン、画像テクスチャを共通スタイルとして保持する。
// 各モードの値を同時保持し、切替後も以前の設定を復元できるようにする。
unit MapRakuPaintStyles;

interface

uses
  System.Types, Vcl.Graphics, MapRakuTextureStyle, MapRakuPatternStyle;

type
  TMapRakuPaintKind = (slpkSolid, slpkGradient, slpkPattern,
    slpkTexture);
  TMapRakuGradientKind = (slgkLinear, slgkRadial, slgkRectangle,
    slgkSweep, slgkAlongStroke, slgkAcrossStroke);

  TMapRakuGradientStop = record
    Id: Integer;       // 選択とUndo後も同じ中間点を識別する正のID。
    Offset: Single;    // 始点を0、終点を1とする線上の比率。
    Color: TColor;     // この中間点で使用するVCL色。
    Opacity: Single;   // この点の不透明度。0は透明、1は不透明。
  end;

const
  SCREEN_LAYOUT_GRADIENT_KIND_NAMES: array[TMapRakuGradientKind] of string =
    ('linearGradient', 'radialGradient', 'rectangleGradient', 'sweepGradient',
     'alongStrokeGradient', 'acrossStrokeGradient');
  SCREEN_LAYOUT_GRADIENT_STOP_NONE = 0;
  SCREEN_LAYOUT_GRADIENT_START_STOP_ID = -1;
  SCREEN_LAYOUT_GRADIENT_END_STOP_ID = -2;

type

  TMapRakuPaintStyle = record
  private
    FPattern: TMapRakuPatternStyle; // 内蔵定義、数値、可変個数の色。
    FTexture: TMapRakuTextureStyle; // 埋め込み画像とローカル配置。
    FKind: TMapRakuPaintKind;       // 現在採用している描画モード。
    FSolidColor: TColor;                 // 単色モードへ戻した場合に復元する色。
    FGradientKind: TMapRakuGradientKind; // 保持中のグラデーション種別。
    FGradientInitialized: Boolean;       // グラデーション値を初期化済みならTrue。
    FGradientStartColor: TColor;         // 始点の色。
    FGradientEndColor: TColor;           // 終点の色。
    FGradientStartOpacity: Single;      // 始点の不透明度（0..1）。
    FGradientEndOpacity: Single;        // 終点の不透明度（0..1）。
    FGradientAspect: Single;            // 放射・矩形の副軸半径 / 主軸半径。
    FGradientStops: TArray<TMapRakuGradientStop>; // 比率順の中間点。
    FNextGradientStopId: Integer;        // 次に割り当てる中間点ID。
    FLinearStart: TPointF;               // ローカル範囲に対する始点の正規化座標。
    FLinearEnd: TPointF;                 // ローカル範囲に対する終点の正規化座標。
    procedure SetSolidColor(const Value: TColor);
    procedure SetGradientStartColor(const Value: TColor);
    procedure SetGradientEndColor(const Value: TColor);
    procedure SortGradientStops;
  public
    // 単色を初期値とし、将来切り替える各描画モードの保持領域も初期化する。
    class function Solid(const Color: TColor): TMapRakuPaintStyle;
      static;
    // 動的配列を含む全モードの保持値が等しい場合にTrueを返す。
    function SameAs(const Value: TMapRakuPaintStyle): Boolean;
    // 未初期化の場合だけ、BaseColorから既定の左から右への線形グラデーションを準備する。
    procedure PrepareLinearGradient(const BaseColor: TColor);
    // ゼロ初期化された旧レコードでも、画像未設定時の配置倍率を等倍に揃える。
    procedure PrepareTexture;
    // 初回だけ現在色を使って斜線パターンを準備する。
    procedure PreparePattern;
    // 現在の見た目を変えない補間色で中間点を追加し、安定した正のIDを返す。
    function AddGradientStop(Offset: Single): Integer;
    // 端点と中間点を補間し、指定比率で描画される色を返す。
    function GradientColorAt(Offset: Single): TColor;
    // 呼び出し側の変更が内部配列へ波及しない複製を返す。
    function GetGradientStops: TArray<TMapRakuGradientStop>;
    // 始点、終点、または安定IDで指定した中間点の色を返す。
    function GetGradientStopColor(Id: Integer; out Value: TColor): Boolean;
    // 中間点を端点の内側へ制限して移動し、IDは維持する。
    function MoveGradientStop(Id: Integer; Offset: Single): Boolean;
    // 中間点だけを削除する。始点と終点の予約IDには適用しない。
    function RemoveGradientStop(Id: Integer): Boolean;
    // 指定した端点または中間点だけの色を変更する。
    function SetGradientStopColor(Id: Integer; Value: TColor): Boolean;
    // 点の不透明度を取得し、無効なIDならFalseを返す。
    function GetGradientStopOpacity(Id: Integer; out Value: Single): Boolean;
    // 点の不透明度を0..1へ制限して変更する。
    function SetGradientStopOpacity(Id: Integer; Value: Single): Boolean;
    // 指定比率の不透明度を補間する。
    function GradientOpacityAt(Offset: Single): Single;
    // JSON復元などで受け取った中間点を複製し、比率順と次回IDを正規化する。
    procedure SetGradientStops(const Value: TArray<TMapRakuGradientStop>);
    property Kind: TMapRakuPaintKind read FKind write FKind;
    property Texture: TMapRakuTextureStyle read FTexture write FTexture;
    property Pattern: TMapRakuPatternStyle read FPattern write FPattern;
    property SolidColor: TColor read FSolidColor write SetSolidColor;
    property GradientKind: TMapRakuGradientKind read FGradientKind
      write FGradientKind;
    property GradientStartColor: TColor read FGradientStartColor
      write SetGradientStartColor;
    property GradientEndColor: TColor read FGradientEndColor
      write SetGradientEndColor;
    property GradientStartOpacity: Single read FGradientStartOpacity write FGradientStartOpacity;
    property GradientEndOpacity: Single read FGradientEndOpacity write FGradientEndOpacity;
    property GradientAspect: Single read FGradientAspect write FGradientAspect;
    property LinearStart: TPointF read FLinearStart write FLinearStart;
    property LinearEnd: TPointF read FLinearEnd write FLinearEnd;
  end;

implementation

uses
  System.Math, Winapi.Windows;

procedure TMapRakuPaintStyle.PreparePattern;
begin
  if FPattern.Id = '' then FPattern := TMapRakuPatternStyle.Create(slptHatch, FSolidColor);
end;

procedure TMapRakuPaintStyle.PrepareTexture;
begin
  if FTexture.Scale <= 0 then FTexture := TMapRakuTextureStyle.DefaultStyle;
end;

function InterpolateColor(Color1, Color2: TColor; Ratio: Single): TColor;
var
  RGB1: TColor;
  RGB2: TColor;
begin
  Ratio := EnsureRange(Ratio, 0.0, 1.0);
  RGB1 := ColorToRGB(Color1);
  RGB2 := ColorToRGB(Color2);
  Result := RGB(
    Round(GetRValue(RGB1) + (GetRValue(RGB2) - GetRValue(RGB1)) * Ratio),
    Round(GetGValue(RGB1) + (GetGValue(RGB2) - GetGValue(RGB1)) * Ratio),
    Round(GetBValue(RGB1) + (GetBValue(RGB2) - GetBValue(RGB1)) * Ratio));
end;

function TMapRakuPaintStyle.AddGradientStop(Offset: Single): Integer;
var
  Stop: TMapRakuGradientStop;
begin
  Offset := EnsureRange(Offset, 0.0001, 0.9999);
  if FNextGradientStopId <= 0 then
    FNextGradientStopId := 1;
  Stop.Id := FNextGradientStopId;
  Inc(FNextGradientStopId);
  Stop.Offset := Offset;
  Stop.Color := GradientColorAt(Offset);
  Stop.Opacity := GradientOpacityAt(Offset);
  FGradientStops := Copy(FGradientStops);
  SetLength(FGradientStops, Length(FGradientStops) + 1);
  FGradientStops[High(FGradientStops)] := Stop;
  SortGradientStops;
  Result := Stop.Id;
end;

function TMapRakuPaintStyle.GetGradientStops:
  TArray<TMapRakuGradientStop>;
begin
  Result := Copy(FGradientStops);
end;

function TMapRakuPaintStyle.GetGradientStopColor(Id: Integer;
  out Value: TColor): Boolean;
var
  Stop: TMapRakuGradientStop;
begin
  if Id = SCREEN_LAYOUT_GRADIENT_START_STOP_ID then
  begin
    Value := FGradientStartColor;
    Exit(True);
  end;
  if Id = SCREEN_LAYOUT_GRADIENT_END_STOP_ID then
  begin
    Value := FGradientEndColor;
    Exit(True);
  end;
  for Stop in FGradientStops do
    if Stop.Id = Id then
    begin
      Value := Stop.Color;
      Exit(True);
    end;
  Value := clNone;
  Result := False;
end;

function TMapRakuPaintStyle.GradientColorAt(Offset: Single): TColor;
var
  I: Integer;
  LeftColor: TColor;
  LeftOffset: Single;
  RightColor: TColor;
  RightOffset: Single;
begin
  Offset := EnsureRange(Offset, 0.0, 1.0);
  LeftColor := FGradientStartColor;
  LeftOffset := 0.0;
  RightColor := FGradientEndColor;
  RightOffset := 1.0;
  for I := 0 to High(FGradientStops) do
    if FGradientStops[I].Offset <= Offset then
    begin
      LeftColor := FGradientStops[I].Color;
      LeftOffset := FGradientStops[I].Offset;
    end
    else
    begin
      RightColor := FGradientStops[I].Color;
      RightOffset := FGradientStops[I].Offset;
      Break;
    end;
  if SameValue(LeftOffset, RightOffset) then
    Exit(LeftColor);
  Result := InterpolateColor(LeftColor, RightColor,
    (Offset - LeftOffset) / (RightOffset - LeftOffset));
end;

function TMapRakuPaintStyle.GetGradientStopOpacity(Id: Integer; out Value: Single): Boolean;
var
  Stop: TMapRakuGradientStop;
begin
  Value := 1;
  if Id = SCREEN_LAYOUT_GRADIENT_START_STOP_ID then
    Value := FGradientStartOpacity
  else if Id = SCREEN_LAYOUT_GRADIENT_END_STOP_ID then
    Value := FGradientEndOpacity
  else
  begin
    for Stop in FGradientStops do
      if Stop.Id = Id then
      begin
        Value := Stop.Opacity;
        Exit(True);
      end;
    Exit(False);
  end;
  Result := True;
end;

function TMapRakuPaintStyle.SetGradientStopOpacity(Id: Integer; Value: Single): Boolean;
var
  I: Integer;
  OldValue: Single;
begin
  Result := False;
  Value := EnsureRange(Value, 0.0, 1.0);
  if not GetGradientStopOpacity(Id, OldValue) or SameValue(OldValue, Value) then
    Exit;
  if Id = SCREEN_LAYOUT_GRADIENT_START_STOP_ID then
    FGradientStartOpacity := Value
  else if Id = SCREEN_LAYOUT_GRADIENT_END_STOP_ID then
    FGradientEndOpacity := Value
  else
    for I := 0 to High(FGradientStops) do
      if FGradientStops[I].Id = Id then
      begin
        FGradientStops := Copy(FGradientStops);
        FGradientStops[I].Opacity := Value;
        Break;
      end;
  Result := True;
end;

function TMapRakuPaintStyle.GradientOpacityAt(Offset: Single): Single;
var
  Stop: TMapRakuGradientStop;
  A, B, X, Y: Single;
begin
  Offset := EnsureRange(Offset, 0.0, 1.0);
  A := FGradientStartOpacity;
  B := FGradientEndOpacity;
  X := 0;
  Y := 1;
  for Stop in FGradientStops do
    if Stop.Offset <= Offset then
    begin
      A := Stop.Opacity;
      X := Stop.Offset;
    end
    else
    begin
      B := Stop.Opacity;
      Y := Stop.Offset;
      Break;
    end;
  if SameValue(X, Y) then
    Exit(A);
  Result := A + (B - A) * (Offset - X) / (Y - X);
end;

function TMapRakuPaintStyle.MoveGradientStop(Id: Integer;
  Offset: Single): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FGradientStops) do
    if FGradientStops[I].Id = Id then
    begin
      Offset := EnsureRange(Offset, 0.0001, 0.9999);
      if SameValue(FGradientStops[I].Offset, Offset) then
        Exit;
      FGradientStops := Copy(FGradientStops);
      FGradientStops[I].Offset := Offset;
      SortGradientStops;
      Exit(True);
    end;
end;

function TMapRakuPaintStyle.RemoveGradientStop(Id: Integer): Boolean;
var
  I: Integer;
  J: Integer;
begin
  Result := False;
  for I := 0 to High(FGradientStops) do
    if FGradientStops[I].Id = Id then
    begin
      FGradientStops := Copy(FGradientStops);
      for J := I to High(FGradientStops) - 1 do
        FGradientStops[J] := FGradientStops[J + 1];
      SetLength(FGradientStops, Length(FGradientStops) - 1);
      Exit(True);
    end;
end;

function TMapRakuPaintStyle.SetGradientStopColor(Id: Integer;
  Value: TColor): Boolean;
var
  I: Integer;
begin
  Value := ColorToRGB(Value);
  if Id = SCREEN_LAYOUT_GRADIENT_START_STOP_ID then
  begin
    Result := ColorToRGB(FGradientStartColor) <> Value;
    if Result then
      FGradientStartColor := Value;
    Exit;
  end;
  if Id = SCREEN_LAYOUT_GRADIENT_END_STOP_ID then
  begin
    Result := ColorToRGB(FGradientEndColor) <> Value;
    if Result then
      FGradientEndColor := Value;
    Exit;
  end;
  for I := 0 to High(FGradientStops) do
    if FGradientStops[I].Id = Id then
    begin
      Result := ColorToRGB(FGradientStops[I].Color) <> Value;
      if Result then
      begin
        FGradientStops := Copy(FGradientStops);
        FGradientStops[I].Color := Value;
      end;
      Exit;
    end;
  Result := False;
end;

procedure TMapRakuPaintStyle.SortGradientStops;
var
  I: Integer;
  J: Integer;
  Stop: TMapRakuGradientStop;
begin
  for I := 1 to High(FGradientStops) do
  begin
    Stop := FGradientStops[I];
    J := I - 1;
    while (J >= 0) and (FGradientStops[J].Offset > Stop.Offset) do
    begin
      FGradientStops[J + 1] := FGradientStops[J];
      Dec(J);
    end;
    FGradientStops[J + 1] := Stop;
  end;
end;

function TMapRakuPaintStyle.SameAs(
  const Value: TMapRakuPaintStyle): Boolean;
var
  I: Integer;
begin
  Result := FPattern.SameAs(Value.FPattern) and FTexture.SameAs(Value.FTexture) and (FKind = Value.FKind) and
    (ColorToRGB(FSolidColor) = ColorToRGB(Value.FSolidColor)) and
    (FGradientKind = Value.FGradientKind) and
    SameValue(FGradientStartOpacity, Value.FGradientStartOpacity) and
    SameValue(FGradientEndOpacity, Value.FGradientEndOpacity) and
    SameValue(FGradientAspect, Value.FGradientAspect) and
    (FGradientInitialized = Value.FGradientInitialized) and
    (ColorToRGB(FGradientStartColor) =
      ColorToRGB(Value.FGradientStartColor)) and
    (ColorToRGB(FGradientEndColor) = ColorToRGB(Value.FGradientEndColor)) and
    SameValue(FLinearStart.X, Value.FLinearStart.X) and
    SameValue(FLinearStart.Y, Value.FLinearStart.Y) and
    SameValue(FLinearEnd.X, Value.FLinearEnd.X) and
    SameValue(FLinearEnd.Y, Value.FLinearEnd.Y) and
    (FNextGradientStopId = Value.FNextGradientStopId) and
    (Length(FGradientStops) = Length(Value.FGradientStops));
  if not Result then
    Exit;
  for I := 0 to High(FGradientStops) do
    if (FGradientStops[I].Id <> Value.FGradientStops[I].Id) or
      not SameValue(FGradientStops[I].Offset,
        Value.FGradientStops[I].Offset) or
      (ColorToRGB(FGradientStops[I].Color) <>
        ColorToRGB(Value.FGradientStops[I].Color)) or
      not SameValue(FGradientStops[I].Opacity,
        Value.FGradientStops[I].Opacity) then
      Exit(False);
end;

procedure TMapRakuPaintStyle.PrepareLinearGradient(
  const BaseColor: TColor);
begin
  if not FGradientInitialized then
  begin
    FGradientStartOpacity := 1;
    FGradientEndOpacity := 1;
    FGradientAspect := 1;
    FLinearStart := TPointF.Create(0, 0.5);
    FLinearEnd := TPointF.Create(1, 0.5);
    FGradientStartColor := ColorToRGB(BaseColor);
    FGradientEndColor := clWhite;
    FGradientInitialized := True;
    FNextGradientStopId := 1;
  end;
end;

procedure TMapRakuPaintStyle.SetGradientEndColor(const Value: TColor);
begin
  FGradientInitialized := True;
  FGradientEndColor := ColorToRGB(Value);
end;

procedure TMapRakuPaintStyle.SetGradientStartColor(const Value: TColor);
begin
  FGradientInitialized := True;
  FGradientStartColor := ColorToRGB(Value);
end;

procedure TMapRakuPaintStyle.SetGradientStops(
  const Value: TArray<TMapRakuGradientStop>);
var
  I: Integer;
begin
  FGradientStops := Copy(Value);
  FNextGradientStopId := 1;
  for I := 0 to High(FGradientStops) do
  begin
    FGradientStops[I].Offset := EnsureRange(FGradientStops[I].Offset,
      0.0001, 0.9999);
    FGradientStops[I].Color := ColorToRGB(FGradientStops[I].Color);
    FGradientStops[I].Opacity := EnsureRange(FGradientStops[I].Opacity,
      0.0, 1.0);
    if FGradientStops[I].Id <= 0 then
      FGradientStops[I].Id := FNextGradientStopId;
    FNextGradientStopId := Max(FNextGradientStopId,
      FGradientStops[I].Id + 1);
  end;
  SortGradientStops;
end;

procedure TMapRakuPaintStyle.SetSolidColor(const Value: TColor);
begin
  FSolidColor := ColorToRGB(Value);
end;

class function TMapRakuPaintStyle.Solid(
  const Color: TColor): TMapRakuPaintStyle;
begin
  Result := Default(TMapRakuPaintStyle);
  Result.FTexture := TMapRakuTextureStyle.DefaultStyle;
  Result.FKind := slpkSolid;
  Result.FSolidColor := ColorToRGB(Color);
  Result.FGradientKind := slgkLinear;
  Result.FGradientStartOpacity := 1;
  Result.FGradientEndOpacity := 1;
  Result.FGradientAspect := 1;
  Result.FGradientInitialized := False;
  Result.FNextGradientStopId := 1;
  Result.FGradientStartColor := ColorToRGB(Color);
  Result.FGradientEndColor := clWhite;
  Result.FLinearStart := TPointF.Create(0, 0.5);
  Result.FLinearEnd := TPointF.Create(1, 0.5);
end;

end.
