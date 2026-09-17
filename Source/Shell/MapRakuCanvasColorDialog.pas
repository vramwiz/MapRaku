// キャンバスの種類別プリセットに限り、既存の色ピッカーをダークダイアログで開く。
unit MapRakuCanvasColorDialog;

interface

uses
  System.Classes, Vcl.Graphics;

function SelectCanvasPresetColor(AOwner: TComponent; const ColorName: string;
  CurrentColor: TColor; out SelectedColor: TColor): Boolean;

implementation

uses
  Vcl.Forms, Vcl.Controls, MapRakuColorPickerFrame, MapRakuPaintStyles,
  MapRakuDarkDialogControls, Winapi.Dwmapi, Winapi.Windows;

const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

function SelectCanvasPresetColor(AOwner: TComponent; const ColorName: string;
  CurrentColor: TColor; out SelectedColor: TColor): Boolean;
var
  PickerDialog: TForm;
  Picker: TMapRakuColorPickerFrame;
  AcceptButton, CancelButton: TDarkDialogButton;
  DarkModeEnabled: BOOL;
begin
  Result := False;
  PickerDialog := TForm.CreateNew(AOwner);
  try
    PickerDialog.Caption := ColorName + 'の色';
    PickerDialog.BorderStyle := bsDialog;
    PickerDialog.Color := COLOR_BACKGROUND;
    PickerDialog.ClientWidth := 376;
    PickerDialog.ClientHeight := 528;
    PickerDialog.Position := poOwnerFormCenter;
    Picker := TMapRakuColorPickerFrame.Create(PickerDialog);
    Picker.Parent := PickerDialog;
    Picker.SetBounds(8,8,360,480);
    Picker.PaintModeEnabled := False;
    Picker.OpacityEnabled := False;
    Picker.ColorEnabled := True;
    Picker.PaintStyle := TMapRakuPaintStyle.Solid(CurrentColor);
    Picker.TargetCaption := ColorName;
    Picker.CompactColorMode := True;
    AcceptButton := TDarkDialogButton.Create(PickerDialog);
    AcceptButton.Parent := PickerDialog;
    AcceptButton.SetBounds(204,492,75,28);
    AcceptButton.Caption := 'OK';
    AcceptButton.Primary := True;
    AcceptButton.ModalResult := mrOk;
    CancelButton := TDarkDialogButton.Create(PickerDialog);
    CancelButton.Parent := PickerDialog;
    CancelButton.SetBounds(285,492,83,28);
    CancelButton.Caption := 'Cancel';
    CancelButton.ModalResult := mrCancel;
    DarkModeEnabled := True;
    DwmSetWindowAttribute(PickerDialog.Handle,DWMWA_USE_IMMERSIVE_DARK_MODE,
      @DarkModeEnabled,SizeOf(DarkModeEnabled));
    if PickerDialog.ShowModal <> mrOk then Exit;
    // 同色の確定を変更として扱うと、既存経路への一括適用が誤って走る。
    SelectedColor := ColorToRGB(Picker.SelectedColor);
    Result := ColorToRGB(CurrentColor) <> SelectedColor;
  finally
    PickerDialog.Free;
  end;
end;

end.
