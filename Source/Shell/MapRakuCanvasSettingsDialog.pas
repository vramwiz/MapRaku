unit MapRakuCanvasSettingsDialog;

// キャンバス設定を編集し、確定した値だけを呼び出し側へ返す。

interface

uses
  System.Classes, Vcl.Graphics, MapRakuDocument;

type
  TMapRakuCanvasColorSettings = record
    DarkMap: Boolean;
    Colors: array[0..6] of TColor; // 道路、川、ルート、JR本体、JR模様、私鉄線、私鉄枕木。
    ColorChanged: array[0..6] of Boolean;
    ApplyRoadExisting: Boolean;
    ApplyRiverExisting: Boolean;
    ApplyRouteExisting: Boolean;
  end;

// キャンセル時は文書に反映せず、確定時だけ選択値を返す。
function ExecuteCanvasSettingsDialog(AOwner: TComponent;
  CurrentWidth, CurrentHeight: Integer; Canvas: TVectArtCanvasLayer;
  out SelectedWidth, SelectedHeight: Integer;
  out Settings: TMapRakuCanvasColorSettings): Boolean;

implementation

uses
  System.SysUtils, System.Types, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ExtCtrls, MapRakuDarkDialogControls,
  MapRakuCanvasColorDialog,
  Winapi.Dwmapi, Winapi.Messages, Winapi.UxTheme, Winapi.Windows;

const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

type
  TCanvasResolution = record
    Width: Integer;
    Height: Integer;
  end;

  TCanvasSettingsForm = class(TForm)
  private
    FCancelButton: TDarkDialogButton;
    FOkButton: TDarkDialogButton;
    FResolutionList: TListBox;
    FThemeGroup: TComboBox;
    FCanvasTab, FColorTab: TDarkDialogButton;
    FCanvasPage, FColorPage: TPanel;
    FColorPanels: array[0..6] of TPanel;
    FColorValues: array[0..6] of TColor;
    FColorChanged: array[0..6] of Boolean;
    FApplyRoad, FApplyRiver, FApplyRoute: TDarkDialogCheckBox;
    FOldThemeIndex: Integer;
    FResolutions: TArray<TCanvasResolution>;
    procedure AddResolution(AWidth, AHeight: Integer);
    procedure CreatePageShell;
    procedure CreateResolutionPage(CurrentWidth, CurrentHeight: Integer);
    procedure CreateThemeSelector;
    procedure CreateColorRows(Canvas: TVectArtCanvasLayer);
    procedure CreateApplyOptions;
    procedure CreateDialogButtons;
    procedure ApplyDarkMode(Sender: TObject);
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    procedure ResolutionListDblClick(Sender: TObject);
    procedure ColorPanelClick(Sender: TObject);
    procedure PageClick(Sender: TObject);
    procedure ShowPage(ColorPage: Boolean);
    procedure ThemeChanged(Sender: TObject);
    procedure UpdateColorPanel(Index: Integer);
    procedure ThemeDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
  public
    constructor CreateForResolution(AOwner: TComponent;
      CurrentWidth, CurrentHeight: Integer; Canvas: TVectArtCanvasLayer);
    function SelectedResolution(out AWidth, AHeight: Integer): Boolean;
    function SelectedSettings: TMapRakuCanvasColorSettings;
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
  CurrentWidth, CurrentHeight: Integer; Canvas: TVectArtCanvasLayer);
begin
  inherited CreateNew(AOwner);
  CreatePageShell;
  CreateResolutionPage(CurrentWidth, CurrentHeight);
  CreateThemeSelector;
  CreateColorRows(Canvas);
  CreateApplyOptions;
  CreateDialogButtons;
  ShowPage(False);
end;

procedure TCanvasSettingsForm.CreatePageShell;
begin
  Caption := 'Canvas Settings';
  BorderStyle := bsDialog;
  Color := COLOR_BACKGROUND;
  Font.Color := COLOR_TEXT;
  Font.Name := 'Segoe UI';
  Font.Height := -14;
  ClientWidth := 400;
  ClientHeight := 520;
  OnShow := ApplyDarkMode;
  Position := poOwnerFormCenter;

  FCanvasTab := TDarkDialogButton.Create(Self);
  FCanvasTab.Parent := Self;
  FCanvasTab.SetBounds(12,12,184,30);
  FCanvasTab.Caption := 'キャンバス';
  FCanvasTab.Tag := 0;
  FCanvasTab.OnClick := PageClick;
  FColorTab := TDarkDialogButton.Create(Self);
  FColorTab.Parent := Self;
  FColorTab.SetBounds(204,12,184,30);
  FColorTab.Caption := '色';
  FColorTab.Tag := 1;
  FColorTab.OnClick := PageClick;
  FCanvasPage := TPanel.Create(Self);
  FCanvasPage.Parent := Self;
  FCanvasPage.SetBounds(12,45,376,433);
  FCanvasPage.BevelOuter := bvNone;
  FCanvasPage.Color := COLOR_BACKGROUND;
  FCanvasPage.ParentBackground := False;
  FColorPage := TPanel.Create(Self);
  FColorPage.Parent := Self;
  FColorPage.SetBounds(12,45,376,433);
  FColorPage.BevelOuter := bvNone;
  FColorPage.Color := COLOR_BACKGROUND;
  FColorPage.ParentBackground := False;

end;

procedure TCanvasSettingsForm.CreateResolutionPage(CurrentWidth,
  CurrentHeight: Integer);
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
  FResolutionList := TListBox.Create(Self);
  FResolutionList.Parent := FCanvasPage;
  FResolutionList.SetBounds(12, 12, 340, 360);
  FResolutionList.Font.Name := 'Segoe UI';
  FResolutionList.Font.Height := -16;
  FResolutionList.ItemHeight := 25;
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
    // 任意サイズの文書も設定画面を開いただけでは変更しない。
    AddResolution(CurrentWidth, CurrentHeight);
    FResolutionList.ItemIndex := FResolutionList.Items.Count - 1;
  end;

end;

procedure TCanvasSettingsForm.CreateThemeSelector;
begin
  with TLabel.Create(Self) do
  begin
    Parent := FColorPage;
    SetBounds(12, 12, 340, 20);
    Caption := '地図の配色';
    Font.Name := 'Segoe UI';
    Font.Height := -12;
    Font.Color := COLOR_TEXT;
  end;
  FThemeGroup := TComboBox.Create(Self);
  FThemeGroup.Parent := FColorPage;
  FThemeGroup.SetBounds(12, 34, 340, 28);
  FThemeGroup.Style := csOwnerDrawFixed;
  FThemeGroup.ItemHeight := 22;
  FThemeGroup.Items.Text := '白地図'#13'黒地図';
  FThemeGroup.Font.Name := 'Segoe UI';
  FThemeGroup.Font.Height := -12;
  FThemeGroup.Font.Color := COLOR_TEXT;
  FThemeGroup.Color := COLOR_CONTROL;
  FThemeGroup.OnDrawItem := ThemeDrawItem;

end;

procedure TCanvasSettingsForm.CreateColorRows(Canvas: TVectArtCanvasLayer);
var
  I: Integer;
  ColorNames: array[0..6] of string;
begin
  FColorValues[0] := Canvas.RoadPresetColor;
  FColorValues[1] := Canvas.RiverPresetColor;
  FColorValues[2] := Canvas.RoutePresetColor;
  FColorValues[3] := Canvas.JrPrimaryColor;
  FColorValues[4] := Canvas.JrSecondaryColor;
  FColorValues[5] := Canvas.RailPrimaryColor;
  FColorValues[6] := Canvas.RailSecondaryColor;
  ColorNames[0] := '道路'; ColorNames[1] := '川';
  ColorNames[2] := 'ルート'; ColorNames[3] := 'JR 本体'; ColorNames[4] := 'JR 模様';
  ColorNames[5] := '私鉄 線'; ColorNames[6] := '私鉄 枕木';
  for I := 0 to 6 do
  begin
    with TLabel.Create(Self) do
    begin
      Parent := FColorPage;
      SetBounds(12,75+I*43,130,24);
      Caption := ColorNames[I];
      Font.Color := COLOR_TEXT;
    end;
    FColorPanels[I] := TPanel.Create(Self);
    FColorPanels[I].Parent := FColorPage;
    FColorPanels[I].SetBounds(150,70+I*43,202,30);
    FColorPanels[I].Tag := I;
    FColorPanels[I].Hint := ColorNames[I];
    FColorPanels[I].ShowHint := True;
    FColorPanels[I].Cursor := crHandPoint;
    FColorPanels[I].OnClick := ColorPanelClick;
    UpdateColorPanel(I);
  end;
end;

procedure TCanvasSettingsForm.CreateApplyOptions;
begin
  with TLabel.Create(Self) do
  begin
    Parent := FColorPage;
    SetBounds(12,317,340,20);
    Caption := 'JR・私鉄の色は同種の既存経路にも反映されます';
    Font.Color := COLOR_TEXT;
  end;
  FApplyRoad := TDarkDialogCheckBox.Create(Self);
  FApplyRoad.Parent := FColorPage;
  FApplyRoad.SetBounds(12,350,340,22);
  FApplyRoad.Caption := '道路：個別色を含む既存経路へ一括適用';
  FApplyRiver := TDarkDialogCheckBox.Create(Self);
  FApplyRiver.Parent := FColorPage;
  FApplyRiver.SetBounds(12,372,340,22);
  FApplyRiver.Caption := '川：個別色を含む既存経路へ一括適用';
  FApplyRoute := TDarkDialogCheckBox.Create(Self);
  FApplyRoute.Parent := FColorPage;
  FApplyRoute.SetBounds(12,394,340,22);
  FApplyRoute.Caption := 'ルート：個別色を含む既存経路へ一括適用';

end;

procedure TCanvasSettingsForm.CreateDialogButtons;
begin
  FOkButton := TDarkDialogButton.Create(Self);
  FOkButton.Parent := Self;
  FOkButton.SetBounds(222, 482, 75, 28);
  FOkButton.Caption := 'OK';
  FOkButton.Primary := True;
  FOkButton.ModalResult := mrOk;

  FCancelButton := TDarkDialogButton.Create(Self);
  FCancelButton.Parent := Self;
  FCancelButton.SetBounds(303, 482, 85, 28);
  FCancelButton.Caption := 'Cancel';
  FCancelButton.ModalResult := mrCancel;
end;

procedure TCanvasSettingsForm.ResolutionListDblClick(Sender: TObject);
begin
  if FResolutionList.ItemIndex >= 0 then
    ModalResult := mrOk;
end;

procedure TCanvasSettingsForm.UpdateColorPanel(Index: Integer);
var RGB: TColor;
begin
  RGB := ColorToRGB(FColorValues[Index]);
  FColorPanels[Index].ParentBackground := False;
  FColorPanels[Index].Color := RGB;
  if GetRValue(RGB)+GetGValue(RGB)+GetBValue(RGB) > 384 then
    FColorPanels[Index].Font.Color := clBlack
  else
    FColorPanels[Index].Font.Color := clWhite;
  FColorPanels[Index].Caption := Format('RGB %d, %d, %d',
    [GetRValue(RGB),GetGValue(RGB),GetBValue(RGB)]);
end;

procedure TCanvasSettingsForm.ShowPage(ColorPage: Boolean);
begin
  FCanvasPage.Visible := not ColorPage;
  FColorPage.Visible := ColorPage;
  if ColorPage then FColorPage.BringToFront
  else FCanvasPage.BringToFront;
  FCanvasTab.Primary := not ColorPage;
  FColorTab.Primary := ColorPage;
  FCanvasTab.Invalidate;
  FColorTab.Invalidate;
end;

procedure TCanvasSettingsForm.PageClick(Sender: TObject);
begin
  ShowPage(TDarkDialogButton(Sender).Tag = 1);
end;

procedure TCanvasSettingsForm.ColorPanelClick(Sender: TObject);
var
  Index: Integer;
  SelectedColor: TColor;
begin
  Index := TPanel(Sender).Tag;
  if not SelectCanvasPresetColor(Self, FColorPanels[Index].Hint,
    FColorValues[Index], SelectedColor) then Exit;
  FColorValues[Index] := SelectedColor;
  FColorChanged[Index] := True;
  UpdateColorPanel(Index);
end;

procedure TCanvasSettingsForm.ThemeChanged(Sender: TObject);
const
  LightColors: array[0..5] of TColor =
    ($00E4E4E4,$00E8A050,$00222222,clWhite,$00222222,$00222222);
  DarkColors: array[0..5] of TColor =
    (clWhite,$00E8A050,clWhite,$00222222,clWhite,clWhite);
var I: Integer; OldDefault, NewDefault: TColor;
begin
  if FOldThemeIndex = FThemeGroup.ItemIndex then Exit;
  // テーマ切替で手動設定色を上書きしないよう、旧標準色だけを更新する。
  for I := 0 to 6 do
  begin
    if FOldThemeIndex = 1 then OldDefault := DarkColors[I]
    else OldDefault := LightColors[I];
    if FThemeGroup.ItemIndex = 1 then NewDefault := DarkColors[I]
    else NewDefault := LightColors[I];
    if not FColorChanged[I] and (FColorValues[I] = OldDefault) then
    begin
      FColorValues[I] := NewDefault;
      UpdateColorPanel(I);
    end;
  end;
  FOldThemeIndex := FThemeGroup.ItemIndex;
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

function TCanvasSettingsForm.SelectedSettings: TMapRakuCanvasColorSettings;
var I: Integer;
begin
  Result.DarkMap := FThemeGroup.ItemIndex = 1;
  for I := 0 to 5 do
  begin
    Result.Colors[I] := FColorValues[I];
    Result.ColorChanged[I] := FColorChanged[I];
  end;
  Result.ApplyRoadExisting := FApplyRoad.Checked;
  Result.ApplyRiverExisting := FApplyRiver.Checked;
  Result.ApplyRouteExisting := FApplyRoute.Checked;
end;

function ExecuteCanvasSettingsDialog(AOwner: TComponent;
  CurrentWidth, CurrentHeight: Integer; Canvas: TVectArtCanvasLayer;
  out SelectedWidth, SelectedHeight: Integer;
  out Settings: TMapRakuCanvasColorSettings): Boolean;
var
  Dialog: TCanvasSettingsForm;
begin
  Dialog := TCanvasSettingsForm.CreateForResolution(AOwner,
    CurrentWidth, CurrentHeight,Canvas);
  try
    if Canvas.BackgroundColor = clBlack then
      Dialog.FThemeGroup.ItemIndex := 1
    else
      Dialog.FThemeGroup.ItemIndex := 0;
    Dialog.FOldThemeIndex := Dialog.FThemeGroup.ItemIndex;
    Dialog.FThemeGroup.OnChange := Dialog.ThemeChanged;
    Result := (Dialog.ShowModal = mrOk) and
      Dialog.SelectedResolution(SelectedWidth, SelectedHeight);
    if Result then
      Settings := Dialog.SelectedSettings;
  finally
    Dialog.Free;
  end;
end;

end.
