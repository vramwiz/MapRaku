// 単色、グラデーション、パターン、テクスチャの選択ボタンだけを描画し、選択意図を通知する。
unit MapRakuPaintModeSelector;

interface

uses
  System.Classes, Vcl.Controls, MapRakuPaintStyles;

const
  SCREEN_LAYOUT_PAINT_MODE_BUTTON_SIZE = 26; // 96 DPIでの正方形ボタン一辺。
  SCREEN_LAYOUT_PAINT_MODE_BUTTON_GAP  = 4;  // 96 DPIでのボタン間隔。

type
  TMapRakuPaintKindEvent = procedure(Sender: TObject; Kind: TMapRakuPaintKind) of object;

  TMapRakuPaintModeSelector = class(TCustomControl)
  private
    FOnSelect: TMapRakuPaintKindEvent; // 有効なボタンを左クリックしたときだけ通知する。
    FPaintStyle: TMapRakuPaintStyle;   // 選択状態と単色アイコンに使う非所有の値コピー。
    procedure SetPaintStyle(const Value: TMapRakuPaintStyle);
  protected
    // 4方式を同じ位置へ描き、無効状態を暗く表示する。
    procedure Paint; override;
    // 有効な描画方式の選択を通知する。
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    // ダークテーマと利用者向けヒントを設定する。
    constructor Create(AOwner: TComponent); override;
    property PaintStyle: TMapRakuPaintStyle read FPaintStyle write SetPaintStyle;
    property OnSelect: TMapRakuPaintKindEvent read FOnSelect write FOnSelect;
  end;

implementation

uses
  System.Math, System.Types, Winapi.Windows, Vcl.Graphics;

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_TEXT       = TColor($00EEEEEE);

constructor TMapRakuPaintModeSelector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentColor := False;
  DoubleBuffered := True;
  FPaintStyle := TMapRakuPaintStyle.Solid(clBlack);
  Hint := '単色 / グラデーション / パターン / テクスチャ';
  ShowHint := True;
end;

procedure TMapRakuPaintModeSelector.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  ButtonSize: Integer;
  Gap: Integer;
  Index: Integer;
begin
  inherited;
  if (Button <> mbLeft) or not Enabled then
    Exit;
  ButtonSize := MulDiv(SCREEN_LAYOUT_PAINT_MODE_BUTTON_SIZE, CurrentPPI, 96);
  Gap := MulDiv(SCREEN_LAYOUT_PAINT_MODE_BUTTON_GAP, CurrentPPI, 96);
  Index := X div (ButtonSize + Gap);
  if (Index < Ord(Low(TMapRakuPaintKind))) or
    (Index > Ord(High(TMapRakuPaintKind))) then
    Exit;
  if Assigned(FOnSelect) then
    FOnSelect(Self, TMapRakuPaintKind(Index));
end;

procedure TMapRakuPaintModeSelector.Paint;
var
  ButtonSize: Integer;
  Gap: Integer;
  I: Integer;
  J: Integer;
  Left: Integer;
  Bounds: TRect;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  ButtonSize := MulDiv(SCREEN_LAYOUT_PAINT_MODE_BUTTON_SIZE, CurrentPPI, 96);
  Gap := MulDiv(SCREEN_LAYOUT_PAINT_MODE_BUTTON_GAP, CurrentPPI, 96);
  for I := Ord(Low(TMapRakuPaintKind)) to Ord(High(TMapRakuPaintKind)) do
  begin
    Left := I * (ButtonSize + Gap);
    Bounds := Rect(Left, 0, Left + ButtonSize, ButtonSize);
    Canvas.Brush.Color := IfThen(I = Ord(FPaintStyle.Kind),
      TColor($00443820), TColor($002E2E2E));
    Canvas.Pen.Color := IfThen(I = Ord(FPaintStyle.Kind),
      TColor($00D77800), TColor($00585858));
    Canvas.Rectangle(Bounds);
    InflateRect(Bounds, -6, -6);
    if not Enabled then
      Canvas.Pen.Color := TColor($00666666)
    else
      Canvas.Pen.Color := COLOR_TEXT;
    case TMapRakuPaintKind(I) of
      slpkSolid:
        begin
          Canvas.Brush.Color := FPaintStyle.SolidColor;
          Canvas.Rectangle(Bounds);
        end;
      slpkGradient:
        for J := Bounds.Left to Bounds.Right - 1 do
        begin
          Canvas.Pen.Color := RGB(255 - MulDiv(190, J - Bounds.Left,
            Max(Bounds.Width - 1, 1)), 255 - MulDiv(190, J - Bounds.Left,
            Max(Bounds.Width - 1, 1)), 255 - MulDiv(190, J - Bounds.Left,
            Max(Bounds.Width - 1, 1)));
          Canvas.MoveTo(J, Bounds.Top);
          Canvas.LineTo(J, Bounds.Bottom);
        end;
      slpkPattern:
        begin
          Canvas.Brush.Style := bsClear;
          Canvas.Rectangle(Bounds);
          Canvas.MoveTo(Bounds.Left, (Bounds.Top + Bounds.Bottom) div 2);
          Canvas.LineTo(Bounds.Right, (Bounds.Top + Bounds.Bottom) div 2);
          Canvas.MoveTo((Bounds.Left + Bounds.Right) div 2, Bounds.Top);
          Canvas.LineTo((Bounds.Left + Bounds.Right) div 2, Bounds.Bottom);
          Canvas.Brush.Style := bsSolid;
        end;
      slpkTexture:
        begin
          Canvas.Brush.Style := bsClear;
          Canvas.Rectangle(Bounds);
          Canvas.MoveTo(Bounds.Left, Bounds.Bottom);
          Canvas.LineTo((Bounds.Left + Bounds.Right) div 2, Bounds.Top);
          Canvas.LineTo(Bounds.Right, Bounds.Bottom);
          Canvas.Brush.Style := bsSolid;
        end;
    end;
  end;
end;

procedure TMapRakuPaintModeSelector.SetPaintStyle(const Value: TMapRakuPaintStyle);
begin
  FPaintStyle := Value;
  Invalidate;
end;

end.
