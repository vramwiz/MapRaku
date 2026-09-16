// Selects a canvas resolution from common presets without owning document state.
unit MapRakuCanvasSettingsDialog;

interface

uses
  System.Classes;

// Returns the selected resolution only when the user confirms the dialog.
function ExecuteCanvasSettingsDialog(AOwner: TComponent;
  CurrentWidth, CurrentHeight: Integer; CurrentDarkMap: Boolean;
  out SelectedWidth, SelectedHeight: Integer;
  out SelectedDarkMap: Boolean): Boolean;

implementation

uses
  System.SysUtils, System.Types, Vcl.Controls, Vcl.Forms, Vcl.Graphics,
  Vcl.StdCtrls, Vcl.ExtCtrls,
  Winapi.Dwmapi, Winapi.Messages, Winapi.UxTheme, Winapi.Windows;

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
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

type
  TCanvasResolution = record
    Width: Integer;
    Height: Integer;
  end;

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
    property ModalResult: TModalResult read FModalResult write FModalResult;
    property Primary: Boolean read FPrimary write FPrimary;
  end;

  TCanvasSettingsForm = class(TForm)
  private
    FCancelButton: TDarkDialogButton;
    FOkButton: TDarkDialogButton;
    FResolutionList: TListBox;
    FThemeGroup: TComboBox;
    FResolutions: TArray<TCanvasResolution>;
    procedure AddResolution(AWidth, AHeight: Integer);
    procedure ApplyDarkMode(Sender: TObject);
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    procedure ResolutionListDblClick(Sender: TObject);
    procedure ThemeDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
  public
    constructor CreateForResolution(AOwner: TComponent;
      CurrentWidth, CurrentHeight: Integer);
    function SelectedResolution(out AWidth, AHeight: Integer): Boolean;
    function SelectedDarkMap: Boolean;
  end;

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

procedure TCanvasSettingsForm.AddResolution(AWidth, AHeight: Integer);
var
  Index: Integer;
begin
  Index := Length(FResolutions);
  SetLength(FResolutions, Index + 1);
  FResolutions[Index].Width := AWidth;
  FResolutions[Index].Height := AHeight;
  FResolutionList.Items.Add(Format('%d x %d', [AWidth, AHeight]));
end;

procedure TCanvasSettingsForm.ApplyDarkMode(Sender: TObject);
var
  DarkModeEnabled: BOOL;
begin
  DarkModeEnabled := True;
  DwmSetWindowAttribute(Handle, DWMWA_USE_IMMERSIVE_DARK_MODE,
    @DarkModeEnabled, SizeOf(DarkModeEnabled));
  SetWindowTheme(Handle, 'DarkMode_Explorer', nil);
  SetWindowTheme(FResolutionList.Handle, 'DarkMode_Explorer', nil);
  SetWindowTheme(FThemeGroup.Handle, 'DarkMode_Explorer', nil);
end;

procedure TCanvasSettingsForm.CMDialogKey(var Message: TCMDialogKey);
begin
  if (Message.CharCode = VK_RETURN) and (ActiveControl = FCancelButton) then
  begin
    ModalResult := mrCancel;
    Message.Result := 1;
  end
  else if (Message.CharCode = VK_RETURN) and
    (FResolutionList.ItemIndex >= 0) then
  begin
    ModalResult := mrOk;
    Message.Result := 1;
  end
  else if Message.CharCode = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Message.Result := 1;
  end
  else
    inherited;
end;

constructor TCanvasSettingsForm.CreateForResolution(AOwner: TComponent;
  CurrentWidth, CurrentHeight: Integer);
const
  COMMON_RESOLUTIONS: array[0..11] of TCanvasResolution = (
    (Width: 640; Height: 360),
    (Width: 854; Height: 480),
    (Width: 1280; Height: 720),
    (Width: 1920; Height: 1080),
    (Width: 2560; Height: 1440),
    (Width: 3840; Height: 2160),
    (Width: 720; Height: 1280),
    (Width: 1080; Height: 1920),
    (Width: 1440; Height: 2560),
    (Width: 2160; Height: 3840),
    (Width: 1080; Height: 1080),
    (Width: 2160; Height: 2160));
var
  I: Integer;
begin
  inherited CreateNew(AOwner);
  Caption := 'Canvas Settings';
  BorderStyle := bsDialog;
  Color := COLOR_BACKGROUND;
  Font.Color := COLOR_TEXT;
  Font.Name := 'Segoe UI';
  ClientWidth := 300;
  ClientHeight := 350;
  OnShow := ApplyDarkMode;
  Position := poOwnerFormCenter;

  FResolutionList := TListBox.Create(Self);
  FResolutionList.Parent := Self;
  FResolutionList.SetBounds(12, 12, 276, 210);
  FResolutionList.Font.Name := 'Segoe UI';
  FResolutionList.Font.Height := -13;
  FResolutionList.Color := COLOR_CONTROL;
  FResolutionList.Font.Color := COLOR_TEXT;
  FResolutionList.OnDblClick := ResolutionListDblClick;

  for I := Low(COMMON_RESOLUTIONS) to High(COMMON_RESOLUTIONS) do
  begin
    AddResolution(COMMON_RESOLUTIONS[I].Width,
      COMMON_RESOLUTIONS[I].Height);
    if (CurrentWidth = COMMON_RESOLUTIONS[I].Width) and
      (CurrentHeight = COMMON_RESOLUTIONS[I].Height) then
      FResolutionList.ItemIndex := I;
  end;
  if FResolutionList.ItemIndex < 0 then
  begin
    AddResolution(CurrentWidth, CurrentHeight);
    FResolutionList.ItemIndex := FResolutionList.Items.Count - 1;
  end;

  with TLabel.Create(Self) do
  begin
    Parent := Self;
    SetBounds(12, 230, 276, 20);
    Caption := '地図の配色';
    Font.Name := 'Segoe UI';
    Font.Height := -12;
    Font.Color := COLOR_TEXT;
  end;
  FThemeGroup := TComboBox.Create(Self);
  FThemeGroup.Parent := Self;
  FThemeGroup.SetBounds(12, 252, 276, 28);
  FThemeGroup.Style := csOwnerDrawFixed;
  FThemeGroup.ItemHeight := 22;
  FThemeGroup.Items.Text := '白地図'#13'黒地図';
  FThemeGroup.Font.Name := 'Segoe UI';
  FThemeGroup.Font.Height := -12;
  FThemeGroup.Font.Color := COLOR_TEXT;
  FThemeGroup.Color := COLOR_CONTROL;
  FThemeGroup.OnDrawItem := ThemeDrawItem;

  FOkButton := TDarkDialogButton.Create(Self);
  FOkButton.Parent := Self;
  FOkButton.SetBounds(132, 310, 75, 28);
  FOkButton.Caption := 'OK';
  FOkButton.Primary := True;
  FOkButton.ModalResult := mrOk;

  FCancelButton := TDarkDialogButton.Create(Self);
  FCancelButton.Parent := Self;
  FCancelButton.SetBounds(213, 310, 75, 28);
  FCancelButton.Caption := 'Cancel';
  FCancelButton.ModalResult := mrCancel;
end;

procedure TCanvasSettingsForm.ResolutionListDblClick(Sender: TObject);
begin
  if FResolutionList.ItemIndex >= 0 then
    ModalResult := mrOk;
end;

procedure TCanvasSettingsForm.ThemeDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
begin
  FThemeGroup.Canvas.Brush.Color := COLOR_CONTROL;
  FThemeGroup.Canvas.FillRect(Rect);
  FThemeGroup.Canvas.Font.Color := COLOR_TEXT;
  if (Index >= 0) and (Index < FThemeGroup.Items.Count) then
    FThemeGroup.Canvas.TextOut(Rect.Left + 7, Rect.Top + 3,
      FThemeGroup.Items[Index]);
end;

function TCanvasSettingsForm.SelectedResolution(out AWidth,
  AHeight: Integer): Boolean;
begin
  Result := (FResolutionList.ItemIndex >= 0) and
    (FResolutionList.ItemIndex < Length(FResolutions));
  if Result then
  begin
    AWidth := FResolutions[FResolutionList.ItemIndex].Width;
    AHeight := FResolutions[FResolutionList.ItemIndex].Height;
  end;
end;

function TCanvasSettingsForm.SelectedDarkMap: Boolean;
begin
  Result := FThemeGroup.ItemIndex = 1;
end;

function ExecuteCanvasSettingsDialog(AOwner: TComponent;
  CurrentWidth, CurrentHeight: Integer; CurrentDarkMap: Boolean;
  out SelectedWidth, SelectedHeight: Integer;
  out SelectedDarkMap: Boolean): Boolean;
var
  Dialog: TCanvasSettingsForm;
begin
  Dialog := TCanvasSettingsForm.CreateForResolution(AOwner,
    CurrentWidth, CurrentHeight);
  try
    if CurrentDarkMap then
      Dialog.FThemeGroup.ItemIndex := 1
    else
      Dialog.FThemeGroup.ItemIndex := 0;
    Result := (Dialog.ShowModal = mrOk) and
      Dialog.SelectedResolution(SelectedWidth, SelectedHeight);
    if Result then
      SelectedDarkMap := Dialog.SelectedDarkMap;
  finally
    Dialog.Free;
  end;
end;

end.
