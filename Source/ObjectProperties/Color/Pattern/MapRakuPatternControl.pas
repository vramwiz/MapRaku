// パターン種類、色スロット、定義別の数値を暗色で編集する。適用と履歴は上位へ通知する。
unit MapRakuPatternControl;

interface

uses System.Classes, System.Types, Vcl.Controls, Vcl.StdCtrls, Vcl.Forms, Vcl.ExtCtrls,
  Vcl.Imaging.pngimage, Winapi.Messages, HorizontalTrackBarControl, VerticalScrollBarControl,
  MapRakuPatternStyle;

type
  TMapRakuPatternControl = class(TCustomControl)
  private
    FStyle: TMapRakuPatternStyle; // UIで編集中の値。文書の所有権は持たない。
    FSlotId: string;                   // 色ピッカーが編集するスロット。
    FSliders: TArray<THorizontalTrackBarControl>; // 定義順の汎用スライダー。
    FLabels: TArray<TLabel>;            // 項目名だけを表示する。数値は表示しない。
    FScroll: TPanel;                   // スクロール対象の子コントロールを切り抜く表示領域。
    FScrollBar: TVerticalScrollBarControl; // レイヤー一覧と同じ汎用スクロールバー。
    FScrollOffset: Integer;            // 設定領域の先頭からの表示位置。
    FLayoutUpdating: Boolean;          // 範囲更新で発生するスクロール通知の再入を抑止する。
    FUpdating: Boolean;               // 文書からの表示同期による変更通知を抑止する。
    FDragging: Boolean;                // スライダー操作を1件の履歴にまとめる状態。
    FPreview: TPngImage;               // Skiaの寿命に依存しないプレビュー。
    FPreviewDirty: Boolean;            // 再生成が必要な場合にTrue。
    FOnChange: TNotifyEvent;           // 設定変更通知。
    FOnSlotSelect: TNotifyEvent;       // 適用を伴わない色スロットの切り替え。
    FOnGestureStart: TNotifyEvent;     // 変更前の履歴スナップショット要求。
    FOnGestureEnd: TNotifyEvent;       // 連続操作の履歴確定要求。
    procedure SetStyle(const Value: TMapRakuPatternStyle);
    procedure SyncSliders;
    procedure SliderChanged(Sender: TObject);
    procedure SliderMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SliderMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SliderCaptureEnd(Sender: TObject);
    procedure SliderFineAdjust(Sender: TObject; Delta: Single; Boundary: Integer);
    procedure FinishDrag;
    procedure ScrollBarChanged(Sender: TObject);
    function Logical(Value: Integer): Integer;
  protected
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    // 汎用スライダーを置くスクロール領域とプレビューを用意する。
    constructor Create(AOwner: TComponent); override;
    // CPU側のプレビュー画像を破棄する。
    destructor Destroy; override;
    // 種類変更時は数値を既定値へ戻し、共通の色設定を引き継ぐ。
    procedure SelectKind(Kind: TMapRakuPatternKind);
    // 指定スロットを選択し、色UI更新だけを通知する。
    procedure SelectSlot(const Id: string);
    property Pattern: TMapRakuPatternStyle read FStyle write SetStyle;
    property SlotId: string read FSlotId;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSlotSelect: TNotifyEvent read FOnSlotSelect write FOnSlotSelect;
    property OnGestureStart: TNotifyEvent read FOnGestureStart write FOnGestureStart;
    property OnGestureEnd: TNotifyEvent read FOnGestureEnd write FOnGestureEnd;
  end;

implementation

uses System.SysUtils, System.Math, Vcl.Graphics, Winapi.Windows,
  MapRakuPatternControlRenderer;

type
  TPatternSliderFineAdjustEvent = procedure(Sender: TObject; Delta: Single;
    Boundary: Integer) of object;

  TPatternSlider = class(THorizontalTrackBarControl)
  private
    FOnCaptureEnd: TNotifyEvent; // 捕捉解除時も連続履歴を閉じる。
    FOnFineAdjust: TPatternSliderFineAdjustEvent; // キーとホイールの論理値変更要求。
    procedure WMCaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    property OnCaptureEnd: TNotifyEvent read FOnCaptureEnd write FOnCaptureEnd;
    property OnFineAdjust: TPatternSliderFineAdjustEvent read FOnFineAdjust write FOnFineAdjust;
  end;

const
  PATTERN_SLIDER_MAX = 10000; // 曲線変換に使う共通の表示分解能。

function ParameterPosition(const Parameter: TMapRakuPatternParameter;
  Value: Single): Integer;
var Normalized: Double;
begin
  Value := EnsureRange(Value, Parameter.Minimum, Parameter.Maximum);
  if Parameter.Minimum > 0 then
    Normalized := Ln(Value / Parameter.Minimum) / Ln(Parameter.Maximum / Parameter.Minimum)
  else if Parameter.Minimum = 0 then
    Normalized := Power(Value / Parameter.Maximum, 1 / 3)
  else if Value < 0 then
    Normalized := (1 - Power(Value / Parameter.Minimum, 1 / 3)) / 2
  else
    Normalized := (1 + Power(Value / Parameter.Maximum, 1 / 3)) / 2;
  Result := EnsureRange(Round(Normalized * PATTERN_SLIDER_MAX), 0, PATTERN_SLIDER_MAX);
end;

function ParameterValue(const Parameter: TMapRakuPatternParameter;
  Position: Integer): Single;
var Normalized, SignedValue: Double;
begin
  Normalized := EnsureRange(Position, 0, PATTERN_SLIDER_MAX) / PATTERN_SLIDER_MAX;
  if Parameter.Minimum > 0 then
    Result := Parameter.Minimum * Exp(Normalized * Ln(Parameter.Maximum / Parameter.Minimum))
  else if Parameter.Minimum = 0 then
    Result := Parameter.Maximum * Power(Normalized, 3)
  else
  begin
    SignedValue := Normalized * 2 - 1;
    if SignedValue < 0 then
      Result := -Abs(Parameter.Minimum) * Power(Abs(SignedValue), 3)
    else
      Result := Parameter.Maximum * Power(SignedValue, 3);
  end;
  Result := EnsureRange(Round(Result * 10) / 10, Parameter.Minimum, Parameter.Maximum);
end;

function TPatternSlider.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := Enabled and (WheelDelta <> 0) and Assigned(FOnFineAdjust);
  if Result then FOnFineAdjust(Self, Sign(WheelDelta) * 0.1, 0)
  else Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure TPatternSlider.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Enabled and Assigned(FOnFineAdjust) then
    case Key of
      VK_LEFT, VK_DOWN: FOnFineAdjust(Self, -0.1, 0);
      VK_RIGHT, VK_UP: FOnFineAdjust(Self, 0.1, 0);
      VK_PRIOR: FOnFineAdjust(Self, 1, 0);
      VK_NEXT: FOnFineAdjust(Self, -1, 0);
      VK_HOME: FOnFineAdjust(Self, 0, -1);
      VK_END: FOnFineAdjust(Self, 0, 1);
    else
      inherited;
      Exit;
    end
  else
  begin
    inherited;
    Exit;
  end;
  Key := 0;
end;

procedure TPatternSlider.WMCaptureChanged(var Message: TMessage);
begin
  inherited;
  // 汎用コントロール側のドラッグ状態も閉じ、捕捉解除後のホバーで値を変更しない。
  MouseUp(mbLeft, [], 0, 0);
  if Assigned(FOnCaptureEnd) then FOnCaptureEnd(Self);
end;

constructor TMapRakuPatternControl.Create(AOwner: TComponent);
begin
  inherited;
  Color := $212121;
  Font.Color := $EEEEEE;
  Font.Height := -11;
  ParentColor := False;
  ParentFont := False;
  DoubleBuffered := True;
  TabStop := True;
  FStyle := TMapRakuPatternStyle.Create(slptHatch, clBlack);
  FSlotId := 'foreground';
  FPreview := TPngImage.Create;
  FPreviewDirty := True;
  FScroll := TPanel.Create(Self);
  FScroll.Parent := Self;
  FScroll.BevelOuter := bvNone;
  FScroll.Caption := '';
  FScroll.Color := Color;
  FScroll.ParentBackground := False;
  FScrollBar := TVerticalScrollBarControl.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Visible := False;
  FScrollBar.OnChange := ScrollBarChanged;
end;

destructor TMapRakuPatternControl.Destroy;
begin
  FPreview.Free;
  inherited;
end;

function TMapRakuPatternControl.Logical(Value: Integer): Integer;
begin
  Result := MulDiv(Value, CurrentPPI, 96);
end;

procedure TMapRakuPatternControl.SetStyle(const Value: TMapRakuPatternStyle);
var Slot: TMapRakuPatternColor; Found: Boolean;
begin
  if Value.Id = '' then Exit;
  if not FStyle.SameAs(Value) then
  begin
    if FStyle.Id <> Value.Id then
    begin
      FinishDrag;
      FScrollOffset := 0;
    end;
    FStyle := Value;
    Found := False;
    for Slot in FStyle.Colors do Found := Found or (Slot.Id = FSlotId);
    if not Found then FSlotId := FStyle.Colors[0].Id;
    FPreviewDirty := True;
    SyncSliders;
    Invalidate;
  end;
end;

procedure TMapRakuPatternControl.SelectKind(Kind: TMapRakuPatternKind);
var C, OldColor: TMapRakuPatternColor; NewStyle: TMapRakuPatternStyle;
begin
  if not Enabled or (FStyle.Kind = Kind) then Exit;
  FinishDrag;
  NewStyle := TMapRakuPatternStyle.Create(Kind, FStyle.Slot('foreground').Color);
  for C in NewStyle.Colors do
    for OldColor in FStyle.Colors do
      if C.Id = OldColor.Id then NewStyle.SetSlot(OldColor);
  SetStyle(NewStyle);
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TMapRakuPatternControl.SelectSlot(const Id: string);
begin
  if not Enabled then Exit;
  FStyle.Slot(Id);
  FSlotId := Id;
  Invalidate;
  if Assigned(FOnSlotSelect) then FOnSlotSelect(Self);
end;

procedure TMapRakuPatternControl.Paint;
begin
  Canvas.Font := Font;
  DrawMapRakuPatternControl(Canvas, ClientRect, CurrentPPI, Enabled,
    FStyle, FSlotId, FPreview, FPreviewDirty);
end;

procedure TMapRakuPatternControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var Index: Integer; Slots: TArray<TMapRakuPatternColor>;
begin
  inherited;
  if not Enabled or (Button <> mbLeft) then Exit;
  SetFocus;
  if Y < Logical(48) then
  begin
    Index := (Y div Logical(24)) * 3 + Min(X div Max(ClientWidth div 3, 1), 2);
    SelectKind(TMapRakuPatternKind(Index));
  end
  else if (Y >= Logical(96)) and (Y < Logical(120)) then
  begin
    Slots := FStyle.Colors;
    SelectSlot(Slots[Min(X div Max(ClientWidth div Length(Slots), 1), High(Slots))].Id);
  end;
end;

procedure TMapRakuPatternControl.CreateWnd;
begin
  inherited;
  SyncSliders;
end;

procedure TMapRakuPatternControl.Resize;
var I, ViewHeight, MaximumOffset, ContentWidth, LabelWidth: Integer;
begin
  inherited;
  if FLayoutUpdating or (FScrollBar = nil) or (GetParentForm(Self) = nil) then Exit;
  FLayoutUpdating := True;
  try
    ViewHeight := Max(ClientHeight - Logical(124), 1);
    MaximumOffset := Max(Logical(Length(MapRakuPatternParameters(FStyle.Kind)) * 28) - ViewHeight, 0);
    FScrollOffset := EnsureRange(FScrollOffset, 0, MaximumOffset);
    FScrollBar.Visible := MaximumOffset > 0;
    FScrollBar.SetBounds(Max(ClientWidth - Logical(14), 0), Logical(124), Logical(14), ViewHeight);
    FScrollBar.SmallChange := Logical(28);
    FScrollBar.LargeChange := Max(ViewHeight - Logical(28), Logical(28));
    FScrollBar.SetRange(MaximumOffset, ViewHeight);
    // 汎用部品はMaximumが上端。レイヤー一覧と同じ向きへ対応させる。
    FScrollBar.Position := MaximumOffset - FScrollOffset;
    ContentWidth := ClientWidth;
    if FScrollBar.Visible then Dec(ContentWidth, Logical(14));
    FScroll.SetBounds(0, Logical(124), Max(ContentWidth, 1), ViewHeight);
    LabelWidth := Logical(66);
    for I := 0 to High(FSliders) do
    begin
      FLabels[I].SetBounds(2, Logical(I * 28 + 4) - FScrollOffset,
        LabelWidth - 2, Logical(20));
      FSliders[I].SetBounds(LabelWidth, Logical(I * 28) - FScrollOffset,
        Max(ContentWidth - LabelWidth - 2, 1), Logical(24));
    end;
  finally
    FLayoutUpdating := False;
  end;
end;

procedure TMapRakuPatternControl.ScrollBarChanged(Sender: TObject);
begin
  if FLayoutUpdating then Exit;
  FScrollOffset := FScrollBar.Maximum - FScrollBar.Position;
  Resize;
end;

function TMapRakuPatternControl.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := Enabled and FScrollBar.Visible and (WheelDelta <> 0);
  if Result then
  begin
    FScrollOffset := EnsureRange(FScrollOffset - MulDiv(WheelDelta, Logical(28), WHEEL_DELTA),
      0, FScrollBar.Maximum);
    Resize;
  end
  else Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure TMapRakuPatternControl.SyncSliders;
var
  Parameters: TArray<TMapRakuPatternParameter>;
  I, PreviousCount: Integer;
  Slider: TPatternSlider;
begin
  if (FScroll = nil) or (GetParentForm(Self) = nil) then Exit;
  Parameters := MapRakuPatternParameters(FStyle.Kind);
  FUpdating := True;
  try
    PreviousCount := Length(FSliders);
    if Length(Parameters) > PreviousCount then
    begin
      SetLength(FSliders, Length(Parameters));
      SetLength(FLabels, Length(Parameters));
      for I := PreviousCount to High(FSliders) do
      begin
        FLabels[I] := TLabel.Create(Self);
        FLabels[I].Parent := FScroll;
        FLabels[I].Tag := I;
        FLabels[I].AutoSize := False;
        FLabels[I].Font := Font;
        Slider := TPatternSlider.Create(Self);
        Slider.Parent := FScroll;
        Slider.Tag := I;
        Slider.BackgroundColor := $212121;
        Slider.ChannelColor := $505050;
        Slider.FillColor := $D77800;
        Slider.ThumbColor := $303030;
        Slider.ThumbBorderColor := $EEEEEE;
        Slider.ShowTicks := False;
        Slider.SmallChange := 1;
        Slider.LargeChange := 10;
        Slider.WheelChangesPosition := False;
        Slider.OnChange := SliderChanged;
        Slider.OnMouseDown := SliderMouseDown;
        Slider.OnMouseUp := SliderMouseUp;
        Slider.OnCaptureEnd := SliderCaptureEnd;
        Slider.OnFineAdjust := SliderFineAdjust;
        Slider.Hint := 'ドラッグで変更 / ホイール・矢印キーで0.1ずつ微調整';
        Slider.ShowHint := True;
        FSliders[I] := Slider;
      end;
    end;
    for I := 0 to High(FSliders) do
    begin
      FSliders[I].Visible := I < Length(Parameters);
      FLabels[I].Visible := I < Length(Parameters);
      if I >= Length(Parameters) then Continue;
      // 広い値域でも既定値付近を操作できる曲線へ変換し、保存値の範囲は変えない。
      FSliders[I].SetRange(0, PATTERN_SLIDER_MAX);
      FSliders[I].Position := ParameterPosition(Parameters[I], FStyle.Number(Parameters[I].Id));
      FLabels[I].Caption := Parameters[I].Caption;
    end;
    Resize;
  finally
    FUpdating := False;
  end;
end;

procedure TMapRakuPatternControl.SliderChanged(Sender: TObject);
var Slider: THorizontalTrackBarControl; Parameters: TArray<TMapRakuPatternParameter>;
begin
  if FUpdating or not Enabled then Exit;
  Slider := THorizontalTrackBarControl(Sender);
  Parameters := MapRakuPatternParameters(FStyle.Kind);
  if (Slider.Tag < 0) or (Slider.Tag >= Length(Parameters)) then Exit;
  FStyle.SetNumber(Parameters[Slider.Tag].Id,
    ParameterValue(Parameters[Slider.Tag], Slider.Position));
  FPreviewDirty := True;
  SyncSliders;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TMapRakuPatternControl.SliderMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled or (Button <> mbLeft) then Exit;
  FDragging := True;
  if Assigned(FOnGestureStart) then FOnGestureStart(Self);
end;

procedure TMapRakuPatternControl.SliderMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then FinishDrag;
end;

procedure TMapRakuPatternControl.SliderCaptureEnd(Sender: TObject);
begin
  FinishDrag;
end;

procedure TMapRakuPatternControl.SliderFineAdjust(Sender: TObject; Delta: Single;
  Boundary: Integer);
var
  Slider: THorizontalTrackBarControl;
  Parameters: TArray<TMapRakuPatternParameter>;
  Parameter: TMapRakuPatternParameter;
  Value: Single;
begin
  if FUpdating or not Enabled then Exit;
  Slider := THorizontalTrackBarControl(Sender);
  Parameters := MapRakuPatternParameters(FStyle.Kind);
  if (Slider.Tag < 0) or (Slider.Tag >= Length(Parameters)) then Exit;
  Parameter := Parameters[Slider.Tag];
  if Boundary < 0 then Value := Parameter.Minimum
  else if Boundary > 0 then Value := Parameter.Maximum
  else Value := EnsureRange(FStyle.Number(Parameter.Id) + Delta,
    Parameter.Minimum, Parameter.Maximum);
  if SameValue(Value, FStyle.Number(Parameter.Id), 0.0001) then Exit;
  if Assigned(FOnGestureStart) then FOnGestureStart(Self);
  FStyle.SetNumber(Parameter.Id, Value);
  FPreviewDirty := True;
  SyncSliders;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
  if Assigned(FOnGestureEnd) then FOnGestureEnd(Self);
end;

procedure TMapRakuPatternControl.FinishDrag;
begin
  if not FDragging then Exit;
  FDragging := False;
  if Assigned(FOnGestureEnd) then FOnGestureEnd(Self);
end;

end.
