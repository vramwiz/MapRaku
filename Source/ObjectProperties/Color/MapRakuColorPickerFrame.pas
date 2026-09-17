// 画面内へ埋め込む色選択UI。オブジェクトへの適用は上位側で接続する。
unit MapRakuColorPickerFrame;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics,
  Vcl.StdCtrls, ColorPickerHueBar, ColorPickerSVArea,
  HorizontalTrackBarControl, MapRakuGradientKindCombo,
  MapRakuPaintStyles, MapRakuTextureControl, MapRakuPaintModeSelector,
  MapRakuColorHistory, MapRakuDocument, MapRakuColorTargetSelector,
  MapRakuPatternControl, MapRakuPatternStyle, VerticalScrollBarControl;

type
  TMapRakuColorPickerFrame = class(TFrame)
  private
    FColorHistory: TMapRakuColorHistory; // 所有する基本色・確定色履歴の表示。
    FColorCodeEdit: TEdit;                    // HEX表示とHEX／RGB十進入力を兼ねる編集欄。
    FColorCodeLabel: TLabel;                  // 編集欄の用途を示す固定ラベル。
    FHistoryGestureActive: Boolean; // 色ドラッグ中だけ履歴の確定を待つ。
    FHistoryStartColor: TColor; // 変更のないクリックを履歴へ追加しないための開始色。
    FPatternControl: TMapRakuPatternControl; // パターン専用の定義別編集UI。
    FScrollBar: TVerticalScrollBarControl;        // 表示高が不足する時だけ使う暗色の縦スクロールUI。
    FUpdatingScrollBar: Boolean;                  // Resize中の範囲同期によるOnChange再入を抑止する。
    FOnPaintGestureStart: TNotifyEvent; // 共通塗り連続編集の開始。
    FOnPaintGestureEnd: TNotifyEvent;   // 共通塗り連続編集の終了。
    FTextureControl: TMapRakuTextureControl; // テクスチャモードだけで表示する画像設定。
    FGradientKindSelector: TMapRakuGradientKindCombo;
    FColor: TColor;
    FCompactColorMode: Boolean;
    FColorEnabled: Boolean;
    FCurrentHue: Double;
    FHueBar: TColorPickerHueBar;
    FOnChange: TNotifyEvent;
    FOnColorGestureEnd: TNotifyEvent;
    FOnColorGestureStart: TNotifyEvent;
    FOnGradientStopSelect: TNotifyEvent;
    FOnOpacityChange: TNotifyEvent;
    FOnOpacityGestureEnd: TNotifyEvent;
    FOnOpacityGestureStart: TNotifyEvent;
    FOpacityLabel: TLabel;
    FOpacityEnabled: Boolean;
    FOpacityTrackBar: THorizontalTrackBarControl;
    FColorTargetSelector: TMapRakuColorTargetSelector; // 色見本とグラデーション点操作を委譲する。
    FGradientStop: Integer;
    FModeSelector: TMapRakuPaintModeSelector; // 塗り方式の表示とクリック判定を委譲する。
    FPaintModeEnabled: Boolean;
    FPaintStyle: TMapRakuPaintStyle;
    FOnPaintStyleChange: TNotifyEvent;
    FSVArea: TColorPickerSVArea;
    FTitleLabel: TLabel;
    FUpdating: Boolean;
    procedure HistorySelected(Sender: TObject; Color: TColor);
    procedure ColorCodeExit(Sender: TObject);
    procedure ColorCodeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CommitColorCode;
    procedure ScrollBarChanged(Sender: TObject);
    procedure PatternChanged(Sender: TObject);
    procedure PatternSlotSelected(Sender: TObject);
    procedure PaintGestureStart(Sender: TObject);
    procedure PaintGestureEnd(Sender: TObject);
    procedure UpdatePatternColor;
    procedure GradientKindChanged(Sender: TObject);
    procedure HueBarChange(Sender: TObject);
    procedure ColorMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ColorMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure OpacityChanged(Sender: TObject);
    procedure OpacityMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure OpacityMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ColorTargetPaintStyleChanged(Sender: TObject);
    procedure ColorTargetStopSelected(Sender: TObject);
    procedure PaintModeSelected(Sender: TObject; Kind: TMapRakuPaintKind);
    procedure SetPaintStyle(const Value: TMapRakuPaintStyle);
    procedure SetGradientStopId(Value: Integer);
    procedure SetPaintModeEnabled(Value: Boolean);
    procedure SetSelectedColor(const Value: TColor);
    procedure SetColorEnabled(Value: Boolean);
    procedure SetCompactColorMode(Value: Boolean);
    procedure SetTargetCaption(const Value: string);
    function GetOpacity: Integer;
    procedure SetOpacity(Value: Integer);
    procedure SetOpacityEnabled(Value: Boolean);
    procedure SVAreaChange(Sender: TObject);
    procedure SyncControls;
    procedure TextureChanged(Sender: TObject);
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure Resize; override;
    procedure SetParent(AParent: TWinControl); override;
  public
    // エディタを開いた時点の使用色を履歴へ取り込む。同期による色設定では追加しない。
    procedure LoadColorHistory(Document: TVectArtDocument);
    property OnPaintGestureStart: TNotifyEvent read FOnPaintGestureStart write FOnPaintGestureStart;
    property OnPaintGestureEnd: TNotifyEvent read FOnPaintGestureEnd write FOnPaintGestureEnd;
    // 色選択、選択色表示、不透明度トラックバーを埋め込み可能な状態で生成する。
    constructor Create(AOwner: TComponent); override;
    // 有効な描画モードへ切り替え、保持済みの各モード設定を復元する。
    procedure SelectPaintKind(Value: TMapRakuPaintKind);
    // VCLのTColor値で現在色を同期する。設定だけではOnChangeを発生させない。
    property SelectedColor: TColor read FColor write SetSelectedColor;
    property PaintStyle: TMapRakuPaintStyle read FPaintStyle
      write SetPaintStyle;
    // 線形グラデーションの開始点、終了点、中間点を安定したIDで指定する。
    property GradientStopId: Integer read FGradientStop write SetGradientStopId;
    // 作成スタイルなど、モード全体を変更できる対象でだけ有効にする。
    property PaintModeEnabled: Boolean read FPaintModeEnabled
      write SetPaintModeEnabled;
    // 色を持たない選択では色操作だけを無効化し、不透明度操作は独立して維持する。
    property ColorEnabled: Boolean read FColorEnabled write SetColorEnabled;
    // 単色だけを選ぶダイアログでは、共通ピッカーの色操作を詰めて表示する。
    property CompactColorMode: Boolean read FCompactColorMode
      write SetCompactColorMode;
    // 選択中のオブジェクトまたはフィルターなど、現在の色適用先を見出しへ表示する。
    property TargetCaption: string write SetTargetCaption;
    // 0から100の整数で表示・編集する不透明度。
    property Opacity: Integer read GetOpacity write SetOpacity;
    property OpacityEnabled: Boolean read FOpacityEnabled
      write SetOpacityEnabled;
    // ユーザーが色を変更した時だけ発生する。
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnPaintStyleChange: TNotifyEvent read FOnPaintStyleChange
      write FOnPaintStyleChange;
    // 色相またはSVのドラッグ境界を通知し、連続変更を1件の履歴へまとめられるようにする。
    property OnColorGestureEnd: TNotifyEvent read FOnColorGestureEnd
      write FOnColorGestureEnd;
    property OnColorGestureStart: TNotifyEvent read FOnColorGestureStart
      write FOnColorGestureStart;
    property OnGradientStopSelect: TNotifyEvent read FOnGradientStopSelect
      write FOnGradientStopSelect;
    // ユーザーが不透明度を変更するたびに発生し、ドラッグ中は連続して通知する。
    property OnOpacityChange: TNotifyEvent read FOnOpacityChange
      write FOnOpacityChange;
    // ドラッグ終了を通知し、呼び出し側が連続変更を1件の履歴へ確定できるようにする。
    property OnOpacityGestureEnd: TNotifyEvent read FOnOpacityGestureEnd
      write FOnOpacityGestureEnd;
    // ドラッグ開始を通知し、呼び出し側が変更前の値を保存できるようにする。
    property OnOpacityGestureStart: TNotifyEvent read FOnOpacityGestureStart
      write FOnOpacityGestureStart;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, ColorPickerColorMath,
  MapRakuColorCode;

{$R *.dfm}

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_HEADER = TColor($00292929);
  COLOR_TEXT = TColor($00EEEEEE);
  COLOR_ERROR_TEXT = TColor($006060FF);
  COLOR_EDIT_BACKGROUND = TColor($00303030);
  COLOR_PICKER_HEIGHT = 92;
  COLOR_PICKER_MARGIN = 6;
  COLOR_SELECTOR_SIZE = 26;
  HUE_BAR_WIDTH = 16;
  MODE_CONTENT_TOP = 122; // この位置より下だけをモード切り替えで変更する。
  PICKER_GAP = 4;
  SCROLL_CONTENT_HEIGHT = 538; // 全モードで共通の仮想表示高。狭い親ではこの範囲をスクロールする。
  SCROLL_BAR_WIDTH = 14;

constructor TMapRakuColorPickerFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  Constraints.MinHeight := MulDiv(330, CurrentPPI, 96);
  Height := MulDiv(538, CurrentPPI, 96);

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Caption := '色';
  FTitleLabel.Color := COLOR_HEADER;
  FTitleLabel.Font.Name := 'Segoe UI';
  FTitleLabel.Font.Height := -MulDiv(12, CurrentPPI, 96);
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Color := COLOR_TEXT;
  FTitleLabel.ParentColor := False;
  FTitleLabel.ParentFont := False;
  FTitleLabel.Layout := tlCenter;

  FColorTargetSelector := TMapRakuColorTargetSelector.Create(Self);
  FColorTargetSelector.Parent := Self;
  FColorTargetSelector.Hint := '塗りの色';
  FColorTargetSelector.ShowHint := True;
  FColorTargetSelector.OnPaintStyleChange := ColorTargetPaintStyleChanged;
  FColorTargetSelector.OnStopSelect := ColorTargetStopSelected;

  FModeSelector := TMapRakuPaintModeSelector.Create(Self);
  FModeSelector.Parent := Self;
  FModeSelector.OnSelect := PaintModeSelected;

  FGradientKindSelector := TMapRakuGradientKindCombo.Create(Self);
  FGradientKindSelector.Parent := Self;
  FGradientKindSelector.Visible := False;
  FGradientKindSelector.OnChange := GradientKindChanged;
  FGradientKindSelector.Hint := '線方向・線幅方向は線オブジェクト用。図形では線形として表示';
  FGradientKindSelector.ShowHint := True;
  FColorTargetSelector.Hint := '点を選択 / Ctrl+クリックで追加 / 右クリックで中間点削除';

  FOpacityLabel := TLabel.Create(Self);
  FOpacityLabel.Parent := Self;
  FOpacityLabel.AutoSize := False;
  FOpacityLabel.Font.Name := 'Segoe UI';
  FOpacityLabel.Font.Height := -MulDiv(11, CurrentPPI, 96);
  FOpacityLabel.Font.Color := COLOR_TEXT;
  FOpacityLabel.ParentFont := False;
  FOpacityLabel.Caption := '透明度：';

  FOpacityTrackBar := THorizontalTrackBarControl.Create(Self);
  FOpacityTrackBar.Parent := Self;
  FOpacityTrackBar.BackgroundColor := COLOR_BACKGROUND;
  FOpacityTrackBar.ChannelColor := TColor($00505050);
  FOpacityTrackBar.FillColor := TColor($00D77800);
  FOpacityTrackBar.ThumbColor := TColor($00303030);
  FOpacityTrackBar.ThumbBorderColor := COLOR_TEXT;
  FOpacityTrackBar.ShowTicks := False;
  FOpacityTrackBar.SetRange(0, 100);
  FOpacityTrackBar.SmallChange := 1;
  FOpacityTrackBar.LargeChange := 10;
  FOpacityTrackBar.OnChange := OpacityChanged;
  FOpacityTrackBar.OnMouseDown := OpacityMouseDown;
  FOpacityTrackBar.OnMouseUp := OpacityMouseUp;
  FOpacityTrackBar.Position := 100;

  FColorHistory := TMapRakuColorHistory.Create(Self);
  FColorHistory.Parent := Self;
  FColorHistory.OnSelect := HistorySelected;

  FColorCodeLabel := TLabel.Create(Self);
  FColorCodeLabel.Parent := Self;
  FColorCodeLabel.AutoSize := False;
  FColorCodeLabel.Caption := 'カラーコード';
  FColorCodeLabel.Font.Name := 'Segoe UI';
  FColorCodeLabel.Font.Height := -MulDiv(9, CurrentPPI, 96);
  FColorCodeLabel.Font.Color := COLOR_TEXT;
  FColorCodeLabel.ParentFont := False;
  FColorCodeLabel.Layout := tlCenter;

  FColorCodeEdit := TEdit.Create(Self);
  FColorCodeEdit.Parent := Self;
  FColorCodeEdit.Color := COLOR_EDIT_BACKGROUND;
  FColorCodeEdit.Font.Name := 'Consolas';
  FColorCodeEdit.Font.Height := -MulDiv(11, CurrentPPI, 96);
  FColorCodeEdit.Font.Color := COLOR_TEXT;
  FColorCodeEdit.ParentFont := False;
  FColorCodeEdit.MaxLength := 24;
  FColorCodeEdit.Hint := '#RRGGBB、rgb(r,g,b)、または r,g,b';
  FColorCodeEdit.ShowHint := True;
  FColorCodeEdit.OnExit := ColorCodeExit;
  FColorCodeEdit.OnKeyDown := ColorCodeKeyDown;

  FHueBar := TColorPickerHueBar.Create(Self);
  FHueBar.Parent := Self;
  FHueBar.OnChange := HueBarChange;
  FHueBar.OnMouseDown := ColorMouseDown;
  FHueBar.OnMouseUp := ColorMouseUp;
  FSVArea := TColorPickerSVArea.Create(Self);
  FSVArea.Parent := Self;
  FSVArea.OnChange := SVAreaChange;
  FSVArea.OnMouseDown := ColorMouseDown;
  FSVArea.OnMouseUp := ColorMouseUp;

  FColor := clBlack;
  FPaintStyle := TMapRakuPaintStyle.Solid(FColor);
  FPaintModeEnabled := True;
  FGradientStop := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  FColorEnabled := True;
  FCurrentHue := 0;
  FOpacityEnabled := True;
  FTextureControl := TMapRakuTextureControl.Create(Self);
  FTextureControl.Parent := Self;
  FTextureControl.Visible := False;
  FTextureControl.OnChange := TextureChanged;
  FPatternControl := TMapRakuPatternControl.Create(Self);
  FPatternControl.Parent := Self;
  FPatternControl.Visible := False;
  FPatternControl.OnChange := PatternChanged;
  FPatternControl.OnSlotSelect := PatternSlotSelected;
  FPatternControl.OnGestureStart := PaintGestureStart;
  FPatternControl.OnGestureEnd := PaintGestureEnd;
  FScrollBar := TVerticalScrollBarControl.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Visible := False;
  FScrollBar.OnChange := ScrollBarChanged;
  SyncControls;
end;

procedure TMapRakuColorPickerFrame.ColorCodeExit(Sender: TObject);
begin
  CommitColorCode;
end;

procedure TMapRakuColorPickerFrame.ColorCodeKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        CommitColorCode;
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        SyncControls;
      end;
  end;
end;

procedure TMapRakuColorPickerFrame.CommitColorCode;
var
  NewColor: TColor;
begin
  if FUpdating then Exit;
  if not FColorEnabled or (FPaintStyle.Kind = slpkTexture) then
  begin
    SyncControls;
    Exit;
  end;
  if not TryParseColorCode(FColorCodeEdit.Text, NewColor) then
  begin
    FColorCodeEdit.Font.Color := COLOR_ERROR_TEXT;
    Exit;
  end;
  FColorCodeEdit.Font.Color := COLOR_TEXT;
  if ColorToRGB(NewColor) = ColorToRGB(FColor) then
  begin
    SyncControls;
    Exit;
  end;
  ColorMouseDown(Self, mbLeft, [], 0, 0);
  try
    SetSelectedColor(NewColor);
    if FPaintStyle.Kind = slpkPattern then
    begin
      if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
    end
    else if Assigned(FOnChange) then FOnChange(Self);
  finally
    ColorMouseUp(Self, mbLeft, [], 0, 0);
  end;
end;

function TMapRakuColorPickerFrame.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := (FScrollBar <> nil) and FScrollBar.Visible and (WheelDelta <> 0);
  if Result then
    FScrollBar.Position := FScrollBar.Position - MulDiv(WheelDelta,
      FScrollBar.SmallChange * 3, WHEEL_DELTA)
  else
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure TMapRakuColorPickerFrame.LoadColorHistory(Document: TVectArtDocument);
begin
  FColorHistory.LoadDocument(Document);
end;

procedure TMapRakuColorPickerFrame.HistorySelected(Sender: TObject; Color: TColor);
begin
  if FUpdating or not FColorEnabled or (FPaintStyle.Kind = slpkTexture) then Exit;
  ColorMouseDown(Self, mbLeft, [], 0, 0);
  try
    SetSelectedColor(Color);
    if FPaintStyle.Kind = slpkPattern then
    begin
      if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
    end
    else if Assigned(FOnChange) then FOnChange(Self);
  finally
    ColorMouseUp(Self, mbLeft, [], 0, 0);
  end;
  FColorHistory.AddColor(Color);
end;

procedure TMapRakuColorPickerFrame.PaintGestureStart(Sender: TObject);
begin
  if Assigned(FOnPaintGestureStart) then FOnPaintGestureStart(Self);
end;

procedure TMapRakuColorPickerFrame.PaintGestureEnd(Sender: TObject);
begin
  if Assigned(FOnPaintGestureEnd) then FOnPaintGestureEnd(Self);
end;

procedure TMapRakuColorPickerFrame.PatternChanged(Sender: TObject);
begin
  if FUpdating or not FColorEnabled or not FPaintModeEnabled then Exit;
  FPaintStyle.Pattern := FPatternControl.Pattern;
  SetPaintStyle(FPaintStyle);
  if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
end;

procedure TMapRakuColorPickerFrame.PatternSlotSelected(Sender: TObject);
var Slot: TMapRakuPatternColor;
begin
  Slot := FPaintStyle.Pattern.Slot(FPatternControl.SlotId);
  SetSelectedColor(Slot.Color);
  SetOpacity(Round(Slot.Opacity * 100));
end;

procedure TMapRakuColorPickerFrame.UpdatePatternColor;
var Pattern: TMapRakuPatternStyle; Slot: TMapRakuPatternColor;
begin
  Pattern := FPaintStyle.Pattern;
  Slot := Pattern.Slot(FPatternControl.SlotId);
  Slot.Color := FColor;
  Pattern.SetSlot(Slot);
  FPaintStyle.Pattern := Pattern;
  FPatternControl.Pattern := Pattern;
end;

procedure TMapRakuColorPickerFrame.TextureChanged(Sender: TObject);
begin
  if FUpdating or not FColorEnabled or not FPaintModeEnabled then Exit;
  FPaintStyle.Texture := FTextureControl.Texture;
  if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
end;

procedure TMapRakuColorPickerFrame.ColorTargetPaintStyleChanged(Sender: TObject);
begin
  FPaintStyle := FColorTargetSelector.PaintStyle;
  FGradientStop := FColorTargetSelector.SelectedStopId;
  if Assigned(FOnPaintStyleChange) then
    FOnPaintStyleChange(Self);
end;

procedure TMapRakuColorPickerFrame.ColorTargetStopSelected(Sender: TObject);
begin
  SetGradientStopId(FColorTargetSelector.SelectedStopId);
  if Assigned(FOnGradientStopSelect) then
    FOnGradientStopSelect(Self);
end;

procedure TMapRakuColorPickerFrame.GradientKindChanged(Sender: TObject);
begin
  if FUpdating or not FGradientKindSelector.Enabled or (FGradientKindSelector.ItemIndex < 0) then
    Exit;
  if FPaintStyle.GradientKind = TMapRakuGradientKind(FGradientKindSelector.ItemIndex) then
    Exit;
  FPaintStyle.GradientKind := TMapRakuGradientKind(FGradientKindSelector.ItemIndex);
  FGradientKindSelector.SetPendingItemIndex(FGradientKindSelector.ItemIndex);
  if FPaintStyle.GradientKind in [slgkRadial, slgkRectangle, slgkSweep] then
  begin
    FPaintStyle.LinearStart := TPointF.Create(0.5, 0.5);
    FPaintStyle.LinearEnd := TPointF.Create(1, 0.5);
    FPaintStyle.GradientAspect := 1;
  end;
  FGradientKindSelector.Invalidate;
  if Assigned(FOnPaintStyleChange) then
    FOnPaintStyleChange(Self);
end;

procedure TMapRakuColorPickerFrame.ColorMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and FColorEnabled then
  begin
    FHistoryGestureActive := True;
    FHistoryStartColor := FColor;
  end;
  if (FPaintStyle.Kind = slpkPattern) and (Button = mbLeft) then
  begin
    PaintGestureStart(Self);
    Exit;
  end;
  if (Button = mbLeft) and FColorEnabled and
    Assigned(FOnColorGestureStart) then
    FOnColorGestureStart(Self);
end;

procedure TMapRakuColorPickerFrame.ColorMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and FHistoryGestureActive then
  begin
    FHistoryGestureActive := False;
    if FColorEnabled and (ColorToRGB(FHistoryStartColor) <> ColorToRGB(FColor)) then
      FColorHistory.AddColor(FColor);
  end;
  if (FPaintStyle.Kind = slpkPattern) and (Button = mbLeft) then
  begin
    PaintGestureEnd(Self);
    Exit;
  end;
  if (Button = mbLeft) and Assigned(FOnColorGestureEnd) then
    FOnColorGestureEnd(Self);
end;

procedure TMapRakuColorPickerFrame.HueBarChange(Sender: TObject);
var
  Saturation: Double;
  Value: Double;
begin
  if FUpdating then
    Exit;
  FCurrentHue := ColorHue(FHueBar.Color);
  ColorToSv(FColor, Saturation, Value);
  FColor := HsvToColor(FCurrentHue, Saturation, Value);
  if FPaintStyle.Kind = slpkPattern then
    UpdatePatternColor
  else if FPaintStyle.Kind = slpkGradient then
    FPaintStyle.SetGradientStopColor(FGradientStop, FColor)
  else
    FPaintStyle.SolidColor := FColor;
  SyncControls;
  if FPaintStyle.Kind = slpkPattern then
  begin
    if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
  end
  else if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TMapRakuColorPickerFrame.GetOpacity: Integer;
begin
  Result := FOpacityTrackBar.Position;
end;

procedure TMapRakuColorPickerFrame.OpacityChanged(Sender: TObject);
var Pattern: TMapRakuPatternStyle; Slot: TMapRakuPatternColor;
begin
  if not FUpdating then
  begin
    if FPaintStyle.Kind = slpkPattern then
    begin
      Pattern := FPaintStyle.Pattern;
      Slot := Pattern.Slot(FPatternControl.SlotId);
      Slot.Opacity := FOpacityTrackBar.Position / 100.0;
      Pattern.SetSlot(Slot);
      FPaintStyle.Pattern := Pattern;
      FPatternControl.Pattern := Pattern;
      if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
      Exit;
    end;
    if FPaintStyle.Kind = slpkGradient then
      FPaintStyle.SetGradientStopOpacity(FGradientStop, FOpacityTrackBar.Position / 100.0);
    FColorTargetSelector.PaintStyle := FPaintStyle;
    if Assigned(FOnOpacityChange) then
      FOnOpacityChange(Self);
  end;
end;

procedure TMapRakuColorPickerFrame.OpacityMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (FPaintStyle.Kind = slpkPattern) and (Button = mbLeft) then
  begin
    PaintGestureStart(Self);
    Exit;
  end;
  if (Button = mbLeft) and FOpacityTrackBar.Enabled and
    Assigned(FOnOpacityGestureStart) then
    FOnOpacityGestureStart(Self);
end;

procedure TMapRakuColorPickerFrame.OpacityMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (FPaintStyle.Kind = slpkPattern) and (Button = mbLeft) then
  begin
    PaintGestureEnd(Self);
    Exit;
  end;
  if (Button = mbLeft) and Assigned(FOnOpacityGestureEnd) then
    FOnOpacityGestureEnd(Self);
end;

procedure TMapRakuColorPickerFrame.PaintModeSelected(Sender: TObject;
  Kind: TMapRakuPaintKind);
begin
  SelectPaintKind(Kind);
end;

procedure TMapRakuColorPickerFrame.SelectPaintKind(
  Value: TMapRakuPaintKind);
begin
  if not FPaintModeEnabled or
    (FPaintStyle.Kind = Value) then
    Exit;
  FPaintStyle.Kind := Value;
  if Value = slpkPattern then FPaintStyle.PreparePattern;
  if Value = slpkTexture then FPaintStyle.PrepareTexture;
  if Value = slpkGradient then
  begin
    FPaintStyle.PrepareLinearGradient(FColor);
    FGradientStop := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
    SelectedColor := FPaintStyle.GradientStartColor;
  end
  else if Value <> slpkPattern then
    SelectedColor := FPaintStyle.SolidColor;
  SetPaintStyle(FPaintStyle);
  FModeSelector.PaintStyle := FPaintStyle;
  FColorTargetSelector.Invalidate;
  if Assigned(FOnPaintStyleChange) then
    FOnPaintStyleChange(Self);
end;

procedure TMapRakuColorPickerFrame.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  if (AParent <> nil) and (FGradientKindSelector <> nil) then
  begin
    FGradientKindSelector.SetPendingItemIndex(Ord(FPaintStyle.GradientKind));
    Resize;
  end;
end;

procedure TMapRakuColorPickerFrame.Resize;
var
  BarWidth: Integer;
  ContentHeight: Integer;
  ContentWidth: Integer;
  HueWidth: Integer;
  SelectorSize: Integer;
  Margin: Integer;
  PickerGap: Integer;
  PickerHeight: Integer;
  PickerTop: Integer;
  ContentTop: Integer;
  HistoryHeight: Integer;
  CodeTop: Integer;
  CodeHeight: Integer;
  CodeLabelWidth: Integer;
  ScrollOffset: Integer;
  CellSize: Integer;
begin
  inherited Resize;
  if FSVArea = nil then
    Exit;
  Margin := MulDiv(COLOR_PICKER_MARGIN, CurrentPPI, 96);
  PickerGap := MulDiv(PICKER_GAP, CurrentPPI, 96);
  HueWidth := MulDiv(HUE_BAR_WIDTH, CurrentPPI, 96);
  SelectorSize := MulDiv(COLOR_SELECTOR_SIZE, CurrentPPI, 96);
  if FCompactColorMode then
  begin
    FScrollBar.Visible := False;
    FTitleLabel.SetBounds(0,0,ClientWidth,MulDiv(26,CurrentPPI,96));
    FColorTargetSelector.SetBounds(Margin,MulDiv(32,CurrentPPI,96),
      ClientWidth-Margin*2,SelectorSize);
    CellSize := Max((ClientWidth-Margin*2-
      7*MulDiv(2,CurrentPPI,96)) div 8,1);
    HistoryHeight := MulDiv(19,CurrentPPI,96)+4*CellSize+
      4*MulDiv(2,CurrentPPI,96);
    FColorHistory.SetBounds(Margin,MulDiv(66,CurrentPPI,96),
      ClientWidth-Margin*2,HistoryHeight);
    CodeTop := MulDiv(66,CurrentPPI,96)+HistoryHeight+
      MulDiv(8,CurrentPPI,96);
    CodeHeight := MulDiv(32,CurrentPPI,96);
    CodeLabelWidth := MulDiv(92,CurrentPPI,96);
    FColorCodeLabel.SetBounds(Margin,CodeTop,CodeLabelWidth,CodeHeight);
    FColorCodeEdit.SetBounds(Margin+CodeLabelWidth,CodeTop,
      ClientWidth-Margin*2-CodeLabelWidth,CodeHeight);
    PickerTop := CodeTop+CodeHeight+MulDiv(8,CurrentPPI,96);
    PickerHeight := Max(ClientHeight-PickerTop-Margin,1);
    FHueBar.SetBounds(ClientWidth-Margin-HueWidth,
      PickerTop,HueWidth,PickerHeight);
    FSVArea.SetBounds(Margin,PickerTop,
      FHueBar.Left-Margin-PickerGap,PickerHeight);
    Exit;
  end;
  ContentTop := MulDiv(MODE_CONTENT_TOP, CurrentPPI, 96);
  ContentHeight := MulDiv(SCROLL_CONTENT_HEIGHT, CurrentPPI, 96);
  BarWidth := MulDiv(SCROLL_BAR_WIDTH, CurrentPPI, 96);
  FUpdatingScrollBar := True;
  try
    FScrollBar.Visible := (Parent <> nil) and (ClientHeight < ContentHeight);
    FScrollBar.SmallChange := MulDiv(24, CurrentPPI, 96);
    FScrollBar.LargeChange := Max(ClientHeight - FScrollBar.SmallChange,
      FScrollBar.SmallChange);
    FScrollBar.SetRange(Max(ContentHeight - ClientHeight, 0), Max(ClientHeight, 1));
    FScrollBar.SetBounds(Max(ClientWidth - BarWidth, 0), 0, BarWidth, ClientHeight);
  finally
    FUpdatingScrollBar := False;
  end;
  if FScrollBar.Visible then
    ContentWidth := Max(ClientWidth - BarWidth, 1)
  else
    ContentWidth := ClientWidth;
  ScrollOffset := FScrollBar.Position;
  PickerHeight := MulDiv(COLOR_PICKER_HEIGHT, CurrentPPI, 96);
  FTitleLabel.SetBounds(0, -ScrollOffset, ContentWidth, MulDiv(26, CurrentPPI, 96));
  FOpacityLabel.SetBounds(Margin, MulDiv(28, CurrentPPI, 96) - ScrollOffset,
    MulDiv(48, CurrentPPI, 96), MulDiv(24, CurrentPPI, 96));
  FOpacityTrackBar.SetBounds(Margin + MulDiv(48, CurrentPPI, 96),
    MulDiv(28, CurrentPPI, 96) - ScrollOffset,
    Max(ContentWidth - Margin * 2 - MulDiv(48, CurrentPPI, 96), 1), MulDiv(24, CurrentPPI, 96));
  FColorTargetSelector.SetBounds(Margin, MulDiv(58, CurrentPPI, 96) - ScrollOffset,
    Max(ContentWidth - Margin * 2, SelectorSize), SelectorSize);
  FModeSelector.SetBounds(Margin, MulDiv(90, CurrentPPI, 96) - ScrollOffset,
    Min(ContentWidth - Margin * 2,
      MulDiv(SCREEN_LAYOUT_PAINT_MODE_BUTTON_SIZE * 4 +
      SCREEN_LAYOUT_PAINT_MODE_BUTTON_GAP * 3, CurrentPPI, 96)),
    MulDiv(SCREEN_LAYOUT_PAINT_MODE_BUTTON_SIZE, CurrentPPI, 96));
  FGradientKindSelector.SetBounds(Margin, ContentTop - ScrollOffset,
    Max(ContentWidth - Margin * 2, 1), MulDiv(24, CurrentPPI, 96));
  PickerTop := ContentHeight - Margin - PickerHeight;
  HistoryHeight := MulDiv(78, CurrentPPI, 96);
  CodeHeight := MulDiv(24, CurrentPPI, 96);
  CodeLabelWidth := MulDiv(64, CurrentPPI, 96);
  CodeTop := PickerTop - CodeHeight - PickerGap;
  FColorCodeLabel.SetBounds(Margin, CodeTop - ScrollOffset, CodeLabelWidth, CodeHeight);
  FColorCodeEdit.SetBounds(Margin + CodeLabelWidth, CodeTop - ScrollOffset,
    Max(ContentWidth - Margin * 2 - CodeLabelWidth, 1), CodeHeight);
  FColorHistory.SetBounds(Margin,
    CodeTop - HistoryHeight - PickerGap - ScrollOffset,
    Max(ContentWidth - Margin * 2, 1), HistoryHeight);
  FHueBar.SetBounds(Max(ContentWidth - Margin - HueWidth, Margin),
    PickerTop - ScrollOffset, HueWidth, PickerHeight);
  FSVArea.SetBounds(Margin, PickerTop - ScrollOffset,
    Max(FHueBar.Left - PickerGap - Margin, 1), PickerHeight);
  if FTextureControl <> nil then
    FTextureControl.SetBounds(Margin, ContentTop - ScrollOffset,
      Max(ContentWidth - Margin * 2, 1),
      Max(CodeTop - HistoryHeight - PickerGap - ContentTop - PickerGap, 1));
  if FPatternControl <> nil then
    FPatternControl.SetBounds(Margin, ContentTop - ScrollOffset,
      Max(ContentWidth - Margin * 2, 1),
      Max(CodeTop - HistoryHeight - PickerGap - ContentTop - PickerGap, 1));
end;

procedure TMapRakuColorPickerFrame.ScrollBarChanged(Sender: TObject);
begin
  if not FUpdatingScrollBar then
    Resize;
end;

procedure TMapRakuColorPickerFrame.SetOpacity(Value: Integer);
begin
  FUpdating := True;
  try
    FOpacityTrackBar.Position := EnsureRange(Value, 0, 100);
    FOpacityLabel.Caption := '透明度：';
  finally
    FUpdating := False;
  end;
end;

procedure TMapRakuColorPickerFrame.SetCompactColorMode(Value: Boolean);
begin
  if FCompactColorMode = Value then Exit;
  FCompactColorMode := Value;
  FColorHistory.SquareCells := Value;
  if Value then
  begin
    FColorCodeLabel.Font.Height := -MulDiv(13,CurrentPPI,96);
    FColorCodeEdit.Font.Height := -MulDiv(14,CurrentPPI,96);
  end
  else
  begin
    FColorCodeLabel.Font.Height := -MulDiv(9,CurrentPPI,96);
    FColorCodeEdit.Font.Height := -MulDiv(11,CurrentPPI,96);
  end;
  FOpacityLabel.Visible := not Value;
  FOpacityTrackBar.Visible := not Value;
  FModeSelector.Visible := not Value;
  FGradientKindSelector.Visible := not Value and
    (FPaintStyle.Kind = slpkGradient);
  Resize;
end;

procedure TMapRakuColorPickerFrame.SetColorEnabled(Value: Boolean);
begin
  FColorEnabled := Value;
  FColorHistory.Enabled := Value and (FPaintStyle.Kind <> slpkTexture);
  FColorCodeEdit.Enabled := Value and (FPaintStyle.Kind <> slpkTexture);
  FColorCodeLabel.Enabled := FColorCodeEdit.Enabled;
  FTextureControl.Enabled := Value and FPaintModeEnabled;
  FPatternControl.Enabled := Value and FPaintModeEnabled;
  FGradientKindSelector.Enabled := Value and FPaintModeEnabled and (FPaintStyle.Kind = slpkGradient);
  FGradientKindSelector.Visible := FPaintStyle.Kind = slpkGradient;
  FHueBar.Enabled := Value and (FPaintStyle.Kind <> slpkTexture);
  FSVArea.Enabled := Value and (FPaintStyle.Kind <> slpkTexture);
  FColorTargetSelector.Enabled := Value and (FPaintStyle.Kind <> slpkTexture);
  FColorTargetSelector.Invalidate;
end;

procedure TMapRakuColorPickerFrame.SetPaintStyle(
  const Value: TMapRakuPaintStyle);
begin
  FPaintStyle := Value;
  if FPaintStyle.Kind = slpkPattern then FPaintStyle.PreparePattern;
  FModeSelector.PaintStyle := FPaintStyle;
  FPatternControl.Pattern := FPaintStyle.Pattern;
  FPatternControl.Visible := Value.Kind = slpkPattern;
  FTextureControl.Texture := Value.Texture;
  FTextureControl.Visible := Value.Kind = slpkTexture;
  FHueBar.Visible := True;
  FSVArea.Visible := True;
  FColorTargetSelector.Visible := True;
  if FPaintStyle.Kind = slpkGradient then
  begin
    FPaintStyle.PrepareLinearGradient(FPaintStyle.SolidColor);
    if not FPaintStyle.GetGradientStopColor(FGradientStop, FColor) then
    begin
      FGradientStop := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
      FColor := FPaintStyle.GradientStartColor;
    end;
  end
  else
    FColor := FPaintStyle.SolidColor;
  if Parent <> nil then
    FGradientKindSelector.SetPendingItemIndex(Ord(FPaintStyle.GradientKind));
  FGradientKindSelector.Enabled := FPaintModeEnabled and FColorEnabled and (FPaintStyle.Kind = slpkGradient);
  FGradientKindSelector.Visible := FPaintStyle.Kind = slpkGradient;
  FColorHistory.Enabled := FColorEnabled and (FPaintStyle.Kind <> slpkTexture);
  FColorCodeEdit.Enabled := FColorEnabled and (FPaintStyle.Kind <> slpkTexture);
  FColorCodeLabel.Enabled := FColorCodeEdit.Enabled;
  FHueBar.Enabled := FColorEnabled and (FPaintStyle.Kind <> slpkTexture);
  FSVArea.Enabled := FColorEnabled and (FPaintStyle.Kind <> slpkTexture);
  FColorTargetSelector.Enabled := FColorEnabled and (FPaintStyle.Kind <> slpkTexture);
  if FPaintStyle.Kind = slpkGradient then
    SetGradientStopId(FGradientStop);
  if FPaintStyle.Kind = slpkPattern then PatternSlotSelected(Self);
  SyncControls;
  FModeSelector.PaintStyle := FPaintStyle;
end;

procedure TMapRakuColorPickerFrame.SetGradientStopId(Value: Integer);
var
  ColorValue: TColor;
  OpacityValue: Single;
begin
  if (FPaintStyle.Kind <> slpkGradient) or
    not FPaintStyle.GetGradientStopColor(Value, ColorValue) then
    Value := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  FGradientStop := Value;
  FColorTargetSelector.SelectedStopId := FGradientStop;
  if FPaintStyle.GetGradientStopColor(FGradientStop, ColorValue) then
    SetSelectedColor(ColorValue);
  if (FPaintStyle.Kind = slpkGradient) and
    FPaintStyle.GetGradientStopOpacity(FGradientStop, OpacityValue) then
    SetOpacity(Round(OpacityValue * 100));
  FColorTargetSelector.Invalidate;
end;

procedure TMapRakuColorPickerFrame.SetPaintModeEnabled(Value: Boolean);
begin
  if FPaintModeEnabled = Value then
    Exit;
  FPaintModeEnabled := Value;
  FModeSelector.Enabled := Value;
  FTextureControl.Enabled := Value and FColorEnabled;
  FPatternControl.Enabled := Value and FColorEnabled;
  FGradientKindSelector.Enabled := Value and FColorEnabled and (FPaintStyle.Kind = slpkGradient);
  FGradientKindSelector.Visible := FPaintStyle.Kind = slpkGradient;
  FModeSelector.Invalidate;
end;

procedure TMapRakuColorPickerFrame.SetTargetCaption(
  const Value: string);
begin
  FTitleLabel.Caption := Value;
end;

procedure TMapRakuColorPickerFrame.SetOpacityEnabled(Value: Boolean);
begin
  FOpacityEnabled := Value;
  FOpacityTrackBar.Enabled := Value;
  FOpacityLabel.Enabled := Value;
end;

procedure TMapRakuColorPickerFrame.SetSelectedColor(
  const Value: TColor);
var
  ColorValue: Double;
  Hue: Double;
  Saturation: Double;
begin
  FColor := ColorToRGB(Value);
  if FPaintStyle.Kind = slpkPattern then
    UpdatePatternColor
  else if FPaintStyle.Kind = slpkGradient then
    FPaintStyle.SetGradientStopColor(FGradientStop, FColor)
  else
    FPaintStyle.SolidColor := FColor;
  ColorToHsv(FColor, Hue, Saturation, ColorValue);
  if (Saturation > 0.000001) and (ColorValue > 0) then
    FCurrentHue := Hue;
  SyncControls;
end;

procedure TMapRakuColorPickerFrame.SVAreaChange(Sender: TObject);
begin
  if FUpdating then
    Exit;
  FColor := FSVArea.Color;
  if FPaintStyle.Kind = slpkPattern then
    UpdatePatternColor
  else if FPaintStyle.Kind = slpkGradient then
    FPaintStyle.SetGradientStopColor(FGradientStop, FColor)
  else
    FPaintStyle.SolidColor := FColor;
  SyncControls;
  if FPaintStyle.Kind = slpkPattern then
  begin
    if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
  end
  else if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TMapRakuColorPickerFrame.SyncControls;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    FHueBar.Color := HsvToColor(FCurrentHue, 1, 1);
    FSVArea.BaseColor := HsvToColor(FCurrentHue, 1, 1);
    FSVArea.Color := FColor;
    FColorCodeEdit.Font.Color := COLOR_TEXT;
    FColorCodeEdit.Text := Format('#%.2X%.2X%.2X',
      [GetRValue(ColorToRGB(FColor)), GetGValue(ColorToRGB(FColor)),
      GetBValue(ColorToRGB(FColor))]);
    FColorTargetSelector.ColorValue := FColor;
    FColorTargetSelector.PaintStyle := FPaintStyle;
    FColorTargetSelector.SelectedStopId := FGradientStop;
  finally
    FUpdating := False;
  end;
end;

end.
