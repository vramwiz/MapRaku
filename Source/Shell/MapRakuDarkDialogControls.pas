unit MapRakuDarkDialogControls;

// ダーク背景でボタンとチェック欄の文字・選択状態を明瞭に描画する。

interface

uses
  System.Classes, Vcl.Controls, Vcl.Graphics, Vcl.Forms, Winapi.Messages;

const
  COLOR_BACKGROUND = TColor($00282828);
  COLOR_BUTTON_BORDER = TColor($00606060);
  COLOR_BUTTON_FOCUS = TColor($00D69C4A);
  COLOR_BUTTON_PRIMARY = TColor($009C630E);
  COLOR_BUTTON_PRIMARY_HOVER = TColor($00BB7711);
  COLOR_BUTTON_PRIMARY_PRESSED = TColor($007D4F0B);
  COLOR_BUTTON_SECONDARY = TColor($00383838);
  COLOR_BUTTON_SECONDARY_HOVER = TColor($00484848);
  COLOR_BUTTON_SECONDARY_PRESSED = TColor($00282828);
  COLOR_CONTROL = TColor($00303030);
  COLOR_TEXT = TColor($00E6E6E6);

type
  TDarkDialogButton = class(TCustomControl)
  private
    FModalResult: TModalResult;
    FMouseOver: Boolean;
    FPressed: Boolean;
    FPrimary: Boolean;
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Click; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
    procedure WMKillFocus(var Message: TWMKillFocus); message WM_KILLFOCUS;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
  public
    constructor Create(AOwner: TComponent); override;
    property Caption;
    property OnClick;
    property ModalResult: TModalResult read FModalResult write FModalResult;
    property Primary: Boolean read FPrimary write FPrimary;
  end;

  // 標準チェック欄の文字色はWindowsテーマに依存するため、自前で暗色表示する。
  TDarkDialogCheckBox = class(TCustomControl)
  private
    FChecked: Boolean;
    procedure SetChecked(Value: Boolean);
  protected
    procedure Click; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Caption;
    property Checked: Boolean read FChecked write SetChecked;
  end;

implementation

uses
  System.Types, Winapi.Windows;

{ TDarkDialogButton }

procedure TDarkDialogButton.Click;
var
  ParentForm: TCustomForm;
begin
  inherited Click;
  ParentForm := GetParentForm(Self);
  if (ParentForm <> nil) and (FModalResult <> mrNone) then
    ParentForm.ModalResult := FModalResult;
end;

procedure TDarkDialogButton.CMMouseEnter(var Message: TMessage);
begin
  FMouseOver := True;
  Invalidate;
end;

procedure TDarkDialogButton.CMMouseLeave(var Message: TMessage);
begin
  FMouseOver := False;
  FPressed := False;
  Invalidate;
end;

constructor TDarkDialogButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  DoubleBuffered := True;
  Font.Name := 'Segoe UI';
  Font.Height := -12;
  Font.Color := COLOR_TEXT;
end;

procedure TDarkDialogButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) or (Key = VK_SPACE) then
  begin
    Click;
    Key := 0;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TDarkDialogButton.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
  begin
    SetFocus;
    FPressed := True;
    Invalidate;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TDarkDialogButton.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Activate: Boolean;
begin
  Activate := (Button = mbLeft) and FPressed and PtInRect(ClientRect,
    Point(X, Y));
  FPressed := False;
  Invalidate;
  if Activate then
    Click;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TDarkDialogButton.Paint;
var
  BackgroundColor: TColor;
  Bounds: TRect;
begin
  if FPrimary then
    if FPressed then
      BackgroundColor := COLOR_BUTTON_PRIMARY_PRESSED
    else if FMouseOver then
      BackgroundColor := COLOR_BUTTON_PRIMARY_HOVER
    else
      BackgroundColor := COLOR_BUTTON_PRIMARY
  else if FPressed then
    BackgroundColor := COLOR_BUTTON_SECONDARY_PRESSED
  else if FMouseOver then
    BackgroundColor := COLOR_BUTTON_SECONDARY_HOVER
  else
    BackgroundColor := COLOR_BUTTON_SECONDARY;

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
  DrawText(Canvas.Handle, PChar(Caption), Length(Caption), Bounds,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TDarkDialogButton.WMKillFocus(var Message: TWMKillFocus);
begin
  inherited;
  Invalidate;
end;

procedure TDarkDialogButton.WMSetFocus(var Message: TWMSetFocus);
begin
  inherited;
  Invalidate;
end;

{ TDarkDialogCheckBox }

constructor TDarkDialogCheckBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  DoubleBuffered := True;
  Font.Name := 'Segoe UI';
  Font.Height := -14;
  Font.Color := COLOR_TEXT;
end;

procedure TDarkDialogCheckBox.SetChecked(Value: Boolean);
begin
  if FChecked = Value then Exit;
  FChecked := Value;
  Invalidate;
end;

procedure TDarkDialogCheckBox.Click;
begin
  Checked := not Checked;
  inherited Click;
end;

procedure TDarkDialogCheckBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) or (Key = VK_RETURN) then
  begin
    Click;
    Key := 0;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TDarkDialogCheckBox.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(ClientRect, Point(X, Y)) then
  begin
    SetFocus;
    Click;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TDarkDialogCheckBox.Paint;
var
  BoxRect, TextRect: TRect;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  BoxRect := Rect(1, (Height-17) div 2, 18, (Height+17) div 2);
  Canvas.Brush.Color := COLOR_CONTROL;
  Canvas.Pen.Color := COLOR_BUTTON_BORDER;
  Canvas.Rectangle(BoxRect);
  if Checked then
  begin
    Canvas.Pen.Color := COLOR_BUTTON_FOCUS;
    Canvas.Pen.Width := 2;
    Canvas.MoveTo(4, BoxRect.Top+8);
    Canvas.LineTo(8, BoxRect.Top+12);
    Canvas.LineTo(15, BoxRect.Top+4);
    Canvas.Pen.Width := 1;
  end;
  if Focused then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := COLOR_BUTTON_FOCUS;
    Canvas.Rectangle(ClientRect);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  TextRect := Rect(25,0,Width,Height);
  DrawText(Canvas.Handle,PChar(Caption),Length(Caption),TextRect,
    DT_LEFT or DT_VCENTER or DT_SINGLELINE);
end;

end.
