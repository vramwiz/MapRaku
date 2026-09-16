// 単色プレビューとグラデーション点の表示、選択、追加、削除を一つのコントロールへ集約する。
unit MapRakuColorTargetSelector;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Graphics, MapRakuPaintStyles;

type
  TMapRakuColorTargetSelector = class(TCustomControl)
  private
    FColor: TColor;                         // 単色モードで表示する現在色。
    FOnPaintStyleChange: TNotifyEvent;       // 点追加・削除後のスタイル確定要求。
    FOnStopSelect: TNotifyEvent;             // 選択点が変わった後の通知。
    FPaintStyle: TMapRakuPaintStyle;    // 描画と点操作に使う値コピー。
    FSelectedStopId: Integer;                // 端点の予約IDまたは正の中間点ID。
    procedure SetColor(const Value: TColor);
    procedure SetPaintStyle(const Value: TMapRakuPaintStyle);
    procedure SetSelectedStopId(Value: Integer);
  protected
    // 不透明度を市松背景へ合成し、選択点を白黒の高コントラスト線で示す。
    procedure Paint; override;
    // Ctrl+左で点追加、右で中間点削除、それ以外は最寄りの点を選択する。
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    // ダークテーマと既定の単色プレビューを準備する。
    constructor Create(AOwner: TComponent); override;
    property ColorValue: TColor read FColor write SetColor;
    property PaintStyle: TMapRakuPaintStyle read FPaintStyle write SetPaintStyle;
    property SelectedStopId: Integer read FSelectedStopId write SetSelectedStopId;
    property OnPaintStyleChange: TNotifyEvent read FOnPaintStyleChange write FOnPaintStyleChange;
    property OnStopSelect: TNotifyEvent read FOnStopSelect write FOnStopSelect;
  end;

implementation

uses
  System.Math, System.Types, Winapi.Windows;

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_TEXT       = TColor($00EEEEEE);

constructor TMapRakuColorTargetSelector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentColor := False;
  DoubleBuffered := True;
  FColor := clBlack;
  FPaintStyle := TMapRakuPaintStyle.Solid(FColor);
  FSelectedStopId := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
end;

procedure TMapRakuColorTargetSelector.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  BestDistance: Single;
  CandidateDistance: Single;
  Ratio: Single;
  Stop: TMapRakuGradientStop;
begin
  inherited;
  if not Enabled or (FPaintStyle.Kind <> slpkGradient) then
    Exit;
  Ratio := EnsureRange((X - 5) / Max(ClientWidth - 11, 1), 0.0, 1.0);
  if (Button = mbLeft) and (ssCtrl in Shift) then
  begin
    FSelectedStopId := FPaintStyle.AddGradientStop(Ratio);
    if Assigned(FOnPaintStyleChange) then
      FOnPaintStyleChange(Self);
    if Assigned(FOnStopSelect) then
      FOnStopSelect(Self);
    Invalidate;
    Exit;
  end;
  FSelectedStopId := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  BestDistance := Ratio;
  CandidateDistance := Abs(1.0 - Ratio);
  if CandidateDistance < BestDistance then
  begin
    BestDistance := CandidateDistance;
    FSelectedStopId := SCREEN_LAYOUT_GRADIENT_END_STOP_ID;
  end;
  for Stop in FPaintStyle.GetGradientStops do
  begin
    CandidateDistance := Abs(Stop.Offset - Ratio);
    if CandidateDistance < BestDistance then
    begin
      BestDistance := CandidateDistance;
      FSelectedStopId := Stop.Id;
    end;
  end;
  if (Button = mbRight) and FPaintStyle.RemoveGradientStop(FSelectedStopId) then
  begin
    FSelectedStopId := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
    if Assigned(FOnPaintStyleChange) then
      FOnPaintStyleChange(Self);
  end;
  if Assigned(FOnStopSelect) then
    FOnStopSelect(Self);
  Invalidate;
end;

procedure TMapRakuColorTargetSelector.Paint;
var
  Alpha: Single;
  Background: Integer;
  Bounds: TRect;
  ColorValue: TColor;
  I: Integer;
  Ratio: Single;
  SelectedOffset: Single;
  SelectorBounds: TRect;
  Stop: TMapRakuGradientStop;
  Y: Integer;
begin
  SelectorBounds := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor($00443820);
  Canvas.Pen.Color := TColor($00D77800);
  Canvas.Rectangle(SelectorBounds);
  Bounds := SelectorBounds;
  InflateRect(Bounds, -5, -5);
  if FPaintStyle.Kind = slpkGradient then
  begin
    for I := Bounds.Left to Bounds.Right - 1 do
    begin
      Ratio := (I - Bounds.Left) / Max(Bounds.Width - 1, 1);
      ColorValue := ColorToRGB(FPaintStyle.GradientColorAt(Ratio));
      Alpha := FPaintStyle.GradientOpacityAt(Ratio);
      for Y := Bounds.Top to Bounds.Bottom - 1 do
      begin
        Background := 120 + 60 * (((I div 4) + (Y div 4)) mod 2);
        Canvas.Pixels[I, Y] := RGB(
          Round(GetRValue(ColorValue) * Alpha + Background * (1 - Alpha)),
          Round(GetGValue(ColorValue) * Alpha + Background * (1 - Alpha)),
          Round(GetBValue(ColorValue) * Alpha + Background * (1 - Alpha)));
      end;
    end;
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := COLOR_TEXT;
    Canvas.Rectangle(Bounds);
    Canvas.Brush.Style := bsSolid;
    SelectedOffset := 0.0;
    if FSelectedStopId = SCREEN_LAYOUT_GRADIENT_END_STOP_ID then
      SelectedOffset := 1.0
    else
      for Stop in FPaintStyle.GetGradientStops do
        if Stop.Id = FSelectedStopId then
        begin
          SelectedOffset := Stop.Offset;
          Break;
        end;
    I := Bounds.Left + Round(SelectedOffset * Max(Bounds.Width - 1, 1));
    Canvas.Pen.Color := clBlack;
    Canvas.Pen.Width := 3;
    Canvas.MoveTo(I, Bounds.Top);
    Canvas.LineTo(I, Bounds.Bottom);
    Canvas.Pen.Width := 1;
    Canvas.Pen.Color := clWhite;
    Canvas.MoveTo(I, Bounds.Top);
    Canvas.LineTo(I, Bounds.Bottom);
  end
  else
  begin
    Canvas.Brush.Color := FColor;
    Canvas.Pen.Color := COLOR_TEXT;
    Canvas.Rectangle(Bounds);
  end;
end;

procedure TMapRakuColorTargetSelector.SetColor(const Value: TColor);
begin
  FColor := ColorToRGB(Value);
  Invalidate;
end;

procedure TMapRakuColorTargetSelector.SetPaintStyle(const Value: TMapRakuPaintStyle);
var
  ColorValue: TColor;
begin
  FPaintStyle := Value;
  if (FPaintStyle.Kind = slpkGradient) and
    not FPaintStyle.GetGradientStopColor(FSelectedStopId, ColorValue) then
    FSelectedStopId := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  Invalidate;
end;

procedure TMapRakuColorTargetSelector.SetSelectedStopId(Value: Integer);
var
  ColorValue: TColor;
begin
  if (FPaintStyle.Kind <> slpkGradient) or
    not FPaintStyle.GetGradientStopColor(Value, ColorValue) then
    Value := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  FSelectedStopId := Value;
  Invalidate;
end;

end.
