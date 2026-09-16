// Line詳細設定で使うダークボタンと拡大した線端形状アイコンを描画する。
unit MapRakuLineStyleControls;

interface

uses
  System.Classes, Winapi.Messages, Vcl.Controls, Vcl.Graphics,
  MapRakuDocument;

type
  TVectArtDarkButton = class(TCustomControl)
  private
    FMouseOver: Boolean;
    FPressed: Boolean;
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    procedure WMKillFocus(var Message: TWMKillFocus); message WM_KILLFOCUS;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
  public
    // キーボード操作とフォーカス表示に対応するダークボタンを生成する。
    constructor Create(AOwner: TComponent); override;
    // 無効状態ではイベントを発生させず、有効時だけOnClickを呼び出す。
    procedure Click; override;
    property Caption;
    property OnClick;
  end;

  TVectArtLineCapButton = class(TVectArtDarkButton)
  private
    FLineCap: TVectArtLineCap;
    FSelected: Boolean;
    procedure SetSelected(Value: Boolean);
  protected
    procedure Paint; override;
  public
    property LineCap: TVectArtLineCap read FLineCap write FLineCap;
    property Selected: Boolean read FSelected write SetSelected;
  end;

  TMapRakuStrokeWidthModeButton = class(TVectArtDarkButton)
  private
    FMode: TMapRakuStrokeWidthMode;
    FSelected: Boolean;
    procedure SetMode(Value: TMapRakuStrokeWidthMode);
    procedure SetSelected(Value: Boolean);
  protected
    procedure Paint; override;
  public
    property Mode: TMapRakuStrokeWidthMode read FMode write SetMode;
    property Selected: Boolean read FSelected write SetSelected;
  end;

  TMapRakuTextStyleButton = class(TVectArtDarkButton)
  private
    FSelected: Boolean;
    FStyle: TFontStyle;
    procedure SetSelected(Value: Boolean);
  protected
    procedure Paint; override;
  public
    property Selected: Boolean read FSelected write SetSelected;
    property Style: TFontStyle read FStyle write FStyle;
    property Font;
  end;

  TMapRakuTextAlignmentButton = class(TVectArtDarkButton)
  private
    FAlignment: TMapRakuTextAlignment;
    FMixed: Boolean;
    FSelected: Boolean;
    procedure SetAlignment(Value: TMapRakuTextAlignment);
    procedure SetMixed(Value: Boolean);
    procedure SetSelected(Value: Boolean);
  protected
    procedure Paint; override;
  public
    property Alignment: TMapRakuTextAlignment read FAlignment
      write SetAlignment;
    property Mixed: Boolean read FMixed write SetMixed;
    property Selected: Boolean read FSelected write SetSelected;
  end;

  TMapRakuTextPathAttachmentButton = class(TVectArtDarkButton)
  private
    FAttachment: TMapRakuTextPathAttachment;
    FMixed: Boolean;
    FSelected: Boolean;
    procedure SetAttachment(Value: TMapRakuTextPathAttachment);
    procedure SetMixed(Value: Boolean);
    procedure SetSelected(Value: Boolean);
  protected
    procedure Paint; override;
  public
    property Attachment: TMapRakuTextPathAttachment read FAttachment
      write SetAttachment;
    property Mixed: Boolean read FMixed write SetMixed;
    property Selected: Boolean read FSelected write SetSelected;
  end;

implementation

uses
  System.Math, System.Types, System.UITypes, Winapi.Windows;

const
  COLOR_BUTTON = TColor($00383838);
  COLOR_BUTTON_BORDER = TColor($00606060);
  COLOR_BUTTON_DISABLED = TColor($002E2E2E);
  COLOR_BUTTON_FOCUS = TColor($00D69C4A);
  COLOR_BUTTON_HOVER = TColor($00484848);
  COLOR_BUTTON_PRESSED = TColor($00202020);
  COLOR_BUTTON_SELECTED = TColor($00613D12);
  COLOR_BUTTON_SELECTED_BORDER = TColor($00D69C4A);
  COLOR_TEXT = TColor($00EEEEEE);

{ TVectArtDarkButton }

procedure TVectArtDarkButton.Click;
begin
  if Enabled then
    inherited Click;
end;

procedure TVectArtDarkButton.CMMouseEnter(var Message: TMessage);
begin
  FMouseOver := True;
  Invalidate;
end;

procedure TVectArtDarkButton.CMMouseLeave(var Message: TMessage);
begin
  FMouseOver := False;
  FPressed := False;
  Invalidate;
end;

constructor TVectArtDarkButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  DoubleBuffered := True;
  Font.Name := 'Segoe UI';
  Font.Height := -12;
  Font.Color := COLOR_TEXT;
end;

procedure TVectArtDarkButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Enabled and ((Key = VK_RETURN) or (Key = VK_SPACE)) then
  begin
    Click;
    Key := 0;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TVectArtDarkButton.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Enabled and (Button = mbLeft) then
  begin
    SetFocus;
    FPressed := True;
    Invalidate;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtDarkButton.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FPressed := False;
  Invalidate;
  // TControl自身のマウスメッセージ処理がClickを発生させるため、ここでは重複して呼ばない。
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TVectArtDarkButton.Paint;
var
  BackgroundColor: TColor;
  Bounds: TRect;
begin
  if not Enabled then
    BackgroundColor := COLOR_BUTTON_DISABLED
  else if FPressed then
    BackgroundColor := COLOR_BUTTON_PRESSED
  else if FMouseOver then
    BackgroundColor := COLOR_BUTTON_HOVER
  else
    BackgroundColor := COLOR_BUTTON;
  Bounds := ClientRect;
  Dec(Bounds.Right);
  Dec(Bounds.Bottom);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := BackgroundColor;
  Canvas.Pen.Color := COLOR_BUTTON_BORDER;
  Canvas.Rectangle(Bounds);
  if Focused then
  begin
    InflateRect(Bounds, -2, -2);
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := COLOR_BUTTON_FOCUS;
    Canvas.Rectangle(Bounds);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  if not Enabled then
    Canvas.Font.Color := COLOR_BUTTON_BORDER;
  DrawText(Canvas.Handle, PChar(Caption), Length(Caption), Bounds,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TVectArtDarkButton.WMKillFocus(var Message: TWMKillFocus);
begin
  inherited;
  Invalidate;
end;

procedure TVectArtDarkButton.WMSetFocus(var Message: TWMSetFocus);
begin
  inherited;
  Invalidate;
end;

{ TVectArtLineCapButton }

procedure TVectArtLineCapButton.Paint;
var
  BackgroundColor: TColor;
  Bounds: TRect;
  EndX: Integer;
  MidY: Integer;
  Points: array[0..2] of TPoint;
  ShaftLeft: Integer;
  StrokeHalfWidth: Integer;
begin
  inherited Paint;
  Bounds := ClientRect;
  Dec(Bounds.Right);
  Dec(Bounds.Bottom);
  if FSelected then
  begin
    if Enabled then
      BackgroundColor := COLOR_BUTTON_SELECTED
    else
      BackgroundColor := COLOR_BUTTON_DISABLED;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := BackgroundColor;
    Canvas.Pen.Color := COLOR_BUTTON_SELECTED_BORDER;
    Canvas.Rectangle(Bounds);
  end;

  ShaftLeft := MulDiv(7, CurrentPPI, 96);
  EndX := Width - MulDiv(10, CurrentPPI, 96);
  MidY := Height div 2;
  StrokeHalfWidth := Height div 6;
  if StrokeHalfWidth < MulDiv(3, CurrentPPI, 96) then
    StrokeHalfWidth := MulDiv(3, CurrentPPI, 96);
  Canvas.Pen.Color := TColor($00606060);
  Canvas.Pen.Style := psDot;
  Canvas.MoveTo(EndX, MulDiv(4, CurrentPPI, 96));
  Canvas.LineTo(EndX, Height - MulDiv(4, CurrentPPI, 96));
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsSolid;
  if Enabled then
  begin
    Canvas.Brush.Color := COLOR_TEXT;
    Canvas.Pen.Color := COLOR_TEXT;
  end
  else
  begin
    Canvas.Brush.Color := COLOR_BUTTON_BORDER;
    Canvas.Pen.Color := COLOR_BUTTON_BORDER;
  end;
  case FLineCap of
    vlcSquare:
      Canvas.FillRect(Rect(ShaftLeft, MidY - StrokeHalfWidth, EndX + 1,
        MidY + StrokeHalfWidth + 1));
    vlcRound:
      begin
        Canvas.FillRect(Rect(ShaftLeft, MidY - StrokeHalfWidth, EndX + 1,
          MidY + StrokeHalfWidth + 1));
        Canvas.Ellipse(EndX - StrokeHalfWidth, MidY - StrokeHalfWidth,
          EndX + StrokeHalfWidth + 1, MidY + StrokeHalfWidth + 1);
      end;
    vlcTriangle:
      begin
        Canvas.FillRect(Rect(ShaftLeft, MidY - StrokeHalfWidth, EndX + 1,
          MidY + StrokeHalfWidth + 1));
        Points[0] := Point(EndX, MidY - StrokeHalfWidth);
        Points[1] := Point(EndX + StrokeHalfWidth, MidY);
        Points[2] := Point(EndX, MidY + StrokeHalfWidth);
        Canvas.Polygon(Points);
      end;
  end;
end;

procedure TVectArtLineCapButton.SetSelected(Value: Boolean);
begin
  if FSelected = Value then
    Exit;
  FSelected := Value;
  Invalidate;
end;

{ TMapRakuStrokeWidthModeButton }

procedure TMapRakuStrokeWidthModeButton.Paint;
var
  BackgroundColor: TColor;
  Bounds: TRect;
  CenterY: Integer;
  HalfHeight: Integer;
  Points: array[0..5] of TPoint;
begin
  inherited Paint;
  Bounds := ClientRect;
  Dec(Bounds.Right);
  Dec(Bounds.Bottom);
  if FSelected then
  begin
    if Enabled then
      BackgroundColor := COLOR_BUTTON_SELECTED
    else
      BackgroundColor := COLOR_BUTTON_DISABLED;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := BackgroundColor;
    Canvas.Pen.Color := COLOR_BUTTON_SELECTED_BORDER;
    Canvas.Rectangle(Bounds);
  end;
  CenterY := Height div 2;
  HalfHeight := Max(MulDiv(2, CurrentPPI, 96), 1);
  Canvas.Brush.Style := bsSolid;
  if Enabled then
    Canvas.Brush.Color := COLOR_TEXT
  else
    Canvas.Brush.Color := COLOR_BUTTON_BORDER;
  Canvas.Pen.Color := Canvas.Brush.Color;
  if FMode = slwmUniform then
    Canvas.FillRect(Rect(MulDiv(6, CurrentPPI, 96), CenterY - HalfHeight,
      Width - MulDiv(6, CurrentPPI, 96), CenterY + HalfHeight + 1))
  else
  begin
    Points[0] := Point(MulDiv(5, CurrentPPI, 96), CenterY - 1);
    Points[1] := Point(Width div 2, CenterY - MulDiv(7, CurrentPPI, 96));
    Points[2] := Point(Width - MulDiv(5, CurrentPPI, 96), CenterY - 1);
    Points[3] := Point(Width - MulDiv(5, CurrentPPI, 96), CenterY + 2);
    Points[4] := Point(Width div 2, CenterY + MulDiv(7, CurrentPPI, 96));
    Points[5] := Point(MulDiv(5, CurrentPPI, 96), CenterY + 2);
    Canvas.Polygon(Points);
  end;
end;

procedure TMapRakuStrokeWidthModeButton.SetMode(
  Value: TMapRakuStrokeWidthMode);
begin
  if FMode = Value then
    Exit;
  FMode := Value;
  Invalidate;
end;

procedure TMapRakuStrokeWidthModeButton.SetSelected(Value: Boolean);
begin
  if FSelected = Value then
    Exit;
  FSelected := Value;
  Invalidate;
end;

{ TMapRakuTextStyleButton }

procedure TMapRakuTextStyleButton.Paint;
var
  Bounds: TRect;
begin
  inherited Paint;
  if not FSelected then
    Exit;
  Bounds := ClientRect;
  Dec(Bounds.Right);
  Dec(Bounds.Bottom);
  Canvas.Brush.Style := bsSolid;
  if Enabled then
    Canvas.Brush.Color := COLOR_BUTTON_SELECTED
  else
    Canvas.Brush.Color := COLOR_BUTTON_DISABLED;
  Canvas.Pen.Color := COLOR_BUTTON_SELECTED_BORDER;
  Canvas.Rectangle(Bounds);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  if not Enabled then
    Canvas.Font.Color := COLOR_BUTTON_BORDER;
  DrawText(Canvas.Handle, PChar(Caption), Length(Caption), Bounds,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TMapRakuTextStyleButton.SetSelected(Value: Boolean);
begin
  if FSelected = Value then
    Exit;
  FSelected := Value;
  Invalidate;
end;

{ TMapRakuTextAlignmentButton }

procedure TMapRakuTextAlignmentButton.Paint;
const
  LINE_LENGTHS: array[0..2] of Integer = (16, 11, 14);
var
  BackgroundColor: TColor;
  Bounds: TRect;
  Column: Integer;
  I: Integer;
  LeftValue: Integer;
  LineLength: Integer;
  Row: Integer;
  TopValue: Integer;
begin
  inherited Paint;
  Bounds := ClientRect;
  Dec(Bounds.Right);
  Dec(Bounds.Bottom);
  if FSelected then
  begin
    if Enabled then
      BackgroundColor := COLOR_BUTTON_SELECTED
    else
      BackgroundColor := COLOR_BUTTON_DISABLED;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := BackgroundColor;
    Canvas.Pen.Color := COLOR_BUTTON_SELECTED_BORDER;
    Canvas.Rectangle(Bounds);
  end;
  Canvas.Pen.Style := psSolid;
  if Enabled then
    Canvas.Pen.Color := COLOR_TEXT
  else
    Canvas.Pen.Color := COLOR_BUTTON_BORDER;
  if FMixed then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Canvas.Pen.Color;
    for I := 0 to 2 do
      Canvas.Ellipse(Width div 2 - MulDiv(1, CurrentPPI, 96),
        Height div 2 - MulDiv(5, CurrentPPI, 96) +
        I * MulDiv(4, CurrentPPI, 96),
        Width div 2 + MulDiv(2, CurrentPPI, 96),
        Height div 2 - MulDiv(2, CurrentPPI, 96) +
        I * MulDiv(4, CurrentPPI, 96));
    Exit;
  end;
  Column := Ord(FAlignment) mod 3;
  Row := Ord(FAlignment) div 3;
  case Row of
    0: TopValue := MulDiv(6, CurrentPPI, 96);
    2: TopValue := Height - MulDiv(13, CurrentPPI, 96);
  else
    TopValue := (Height - MulDiv(7, CurrentPPI, 96)) div 2;
  end;
  for I := 0 to 2 do
  begin
    LineLength := MulDiv(LINE_LENGTHS[I], CurrentPPI, 96);
    case Column of
      0: LeftValue := MulDiv(6, CurrentPPI, 96);
      2: LeftValue := Width - MulDiv(6, CurrentPPI, 96) - LineLength;
    else
      LeftValue := (Width - LineLength) div 2;
    end;
    Canvas.MoveTo(LeftValue, TopValue + I * MulDiv(3, CurrentPPI, 96));
    Canvas.LineTo(LeftValue + LineLength,
      TopValue + I * MulDiv(3, CurrentPPI, 96));
  end;
end;

procedure TMapRakuTextAlignmentButton.SetAlignment(
  Value: TMapRakuTextAlignment);
begin
  if FAlignment = Value then
    Exit;
  FAlignment := Value;
  Invalidate;
end;

procedure TMapRakuTextAlignmentButton.SetMixed(Value: Boolean);
begin
  if FMixed = Value then
    Exit;
  FMixed := Value;
  Invalidate;
end;

procedure TMapRakuTextAlignmentButton.SetSelected(Value: Boolean);
begin
  if FSelected = Value then
    Exit;
  FSelected := Value;
  Invalidate;
end;

{ TMapRakuTextPathAttachmentButton }

procedure TMapRakuTextPathAttachmentButton.Paint;
var
  BackgroundColor: TColor;
  Bounds: TRect;
  I: Integer;
  LinePosition: Integer;
  TextHeight: Integer;
  TextWidth: Integer;
  TextX: Integer;
  TextY: Integer;
begin
  inherited Paint;
  Bounds := ClientRect;
  Dec(Bounds.Right);
  Dec(Bounds.Bottom);
  if FSelected then
  begin
    if Enabled then
      BackgroundColor := COLOR_BUTTON_SELECTED
    else
      BackgroundColor := COLOR_BUTTON_DISABLED;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := BackgroundColor;
    Canvas.Pen.Color := COLOR_BUTTON_SELECTED_BORDER;
    Canvas.Rectangle(Bounds);
  end;
  if Enabled then
    Canvas.Pen.Color := COLOR_TEXT
  else
    Canvas.Pen.Color := COLOR_BUTTON_BORDER;
  if FMixed then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Canvas.Pen.Color;
    for I := 0 to 2 do
      Canvas.Ellipse(Width div 2 - MulDiv(1, CurrentPPI, 96),
        Height div 2 - MulDiv(5, CurrentPPI, 96) +
        I * MulDiv(4, CurrentPPI, 96),
        Width div 2 + MulDiv(2, CurrentPPI, 96),
        Height div 2 - MulDiv(2, CurrentPPI, 96) +
        I * MulDiv(4, CurrentPPI, 96));
    Exit;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -MulDiv(16, CurrentPPI, 96);
  Canvas.Font.Style := [fsBold];
  if Enabled then
    Canvas.Font.Color := COLOR_TEXT
  else
    Canvas.Font.Color := COLOR_BUTTON_BORDER;
  TextWidth := Canvas.TextWidth('A');
  TextHeight := Canvas.TextHeight('A');
  TextX := (Width - TextWidth) div 2;
  TextY := (Height - TextHeight) div 2;
  Canvas.Pen.Style := psSolid;
  if Enabled then
    Canvas.Pen.Color := COLOR_BUTTON_SELECTED_BORDER
  else
    Canvas.Pen.Color := COLOR_BUTTON_BORDER;
  Canvas.Pen.Width := Max(MulDiv(3, CurrentPPI, 96), 1);
  case FAttachment of
    sltpaTop:
      begin
        LinePosition := MulDiv(5, CurrentPPI, 96);
        TextY := LinePosition + MulDiv(3, CurrentPPI, 96);
        Canvas.MoveTo((Width - MulDiv(18, CurrentPPI, 96)) div 2,
          LinePosition);
        Canvas.LineTo((Width + MulDiv(18, CurrentPPI, 96)) div 2,
          LinePosition);
      end;
    sltpaLeft:
      begin
        LinePosition := MulDiv(6, CurrentPPI, 96);
        TextX := LinePosition + MulDiv(3, CurrentPPI, 96);
        Canvas.MoveTo(LinePosition, MulDiv(5, CurrentPPI, 96));
        Canvas.LineTo(LinePosition, Height - MulDiv(5, CurrentPPI, 96));
      end;
    sltpaRight:
      begin
        LinePosition := Width - MulDiv(7, CurrentPPI, 96);
        TextX := LinePosition - MulDiv(3, CurrentPPI, 96) - TextWidth;
        Canvas.MoveTo(LinePosition, MulDiv(5, CurrentPPI, 96));
        Canvas.LineTo(LinePosition, Height - MulDiv(5, CurrentPPI, 96));
      end;
  else
    LinePosition := Height - MulDiv(6, CurrentPPI, 96);
    TextY := LinePosition - MulDiv(3, CurrentPPI, 96) - TextHeight;
    Canvas.MoveTo((Width - MulDiv(18, CurrentPPI, 96)) div 2, LinePosition);
    Canvas.LineTo((Width + MulDiv(18, CurrentPPI, 96)) div 2, LinePosition);
  end;
  Canvas.Pen.Width := 1;
  Canvas.TextOut(TextX, TextY, 'A');
end;

procedure TMapRakuTextPathAttachmentButton.SetAttachment(
  Value: TMapRakuTextPathAttachment);
begin
  if FAttachment = Value then
    Exit;
  FAttachment := Value;
  Invalidate;
end;

procedure TMapRakuTextPathAttachmentButton.SetMixed(Value: Boolean);
begin
  if FMixed = Value then
    Exit;
  FMixed := Value;
  Invalidate;
end;

procedure TMapRakuTextPathAttachmentButton.SetSelected(Value: Boolean);
begin
  if FSelected = Value then
    Exit;
  FSelected := Value;
  Invalidate;
end;

end.
