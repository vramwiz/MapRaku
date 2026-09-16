// フィルター一覧の描画、選択、並べ替え、主要値の直接操作を担当する。
unit MapRakuFilterListControl;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Graphics,
  MapRakuDocument, MapRakuFilters, VerticalScrollBarControl;

type
  TMapRakuFilterIndexEvent = procedure(Sender: TObject;
    Index: Integer) of object;
  TMapRakuFilterMoveEvent = procedure(Sender: TObject;
    FromIndex, ToIndex: Integer) of object;
  TMapRakuFilterValueEvent = procedure(Sender: TObject;
    Index: Integer; Value: Single) of object;

  TMapRakuFilterListControl = class(TCustomControl)
  private
    FScrollBar: TVerticalScrollBarControl; // 所有する共通の暗色スクロールバー。
    FScrollOffset: Integer; // 一覧先頭からの画面ピクセル単位の移動量。
    FUpdatingScrollBar: Boolean; // 範囲同期時のOnChange再入を抑止する。
    FDragCandidateIndex: Integer;
    FDragStartPoint: TPoint;
    FDragTargetIndex: Integer;
    FDragging: Boolean;
    FLayer: TVectArtLayer;
    FOnMoveFilter: TMapRakuFilterMoveEvent;
    FOnSelectionChanged: TNotifyEvent;
    FOnToggleEnabled: TMapRakuFilterIndexEvent;
    FOnValueChanged: TMapRakuFilterValueEvent;
    FOnValueGestureEnd: TMapRakuFilterIndexEvent;
    FOnValueGestureStart: TMapRakuFilterIndexEvent;
    FSelectedIndex: Integer;
    FSliderDragIndex: Integer;
    function ContentWidth: Integer;
    procedure ScrollBarChanged(Sender: TObject);
    procedure UpdateScrollBar;
    procedure EnsureSelectionVisible;
    function FilterIndexAt(Y: Integer): Integer;
    function HandleRect(Index: Integer): TRect;
    function RowHeight: Integer;
    function SliderRect(Index: Integer): TRect;
    function SwitchRect(Index: Integer): TRect;
    procedure UpdateSliderValue(Index, X: Integer);
    procedure SetLayer(const Value: TVectArtLayer);
    procedure SetSelectedIndex(const Value: Integer);
  protected
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    // 一覧専用のD&D状態とスライダー操作状態を初期化する。
    constructor Create(AOwner: TComponent); override;
    property Layer: TVectArtLayer read FLayer write SetLayer;
    property OnMoveFilter: TMapRakuFilterMoveEvent read FOnMoveFilter
      write FOnMoveFilter;
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged
      write FOnSelectionChanged;
    property OnToggleEnabled: TMapRakuFilterIndexEvent
      read FOnToggleEnabled write FOnToggleEnabled;
    property OnValueChanged: TMapRakuFilterValueEvent
      read FOnValueChanged write FOnValueChanged;
    property OnValueGestureEnd: TMapRakuFilterIndexEvent
      read FOnValueGestureEnd write FOnValueGestureEnd;
    property OnValueGestureStart: TMapRakuFilterIndexEvent
      read FOnValueGestureStart write FOnValueGestureStart;
    property SelectedIndex: Integer read FSelectedIndex write SetSelectedIndex;
  end;

// 一覧スライダーで扱う主要値を0～1へ正規化して返す。
function FilterRepresentativeRatio(Filter: TMapRakuFilter): Single;

implementation

uses
  System.Math, Winapi.Windows;

const
  COLOR_BACKGROUND       = TColor($00212121);
  COLOR_DRAG_HANDLE      = TColor($00707070);
  COLOR_ROW              = TColor($00252525);
  COLOR_ROW_SELECTED     = TColor($0042382E);
  COLOR_SLIDER           = TColor($00404040);
  COLOR_SLIDER_VALUE     = TColor($00D69C4A);
  COLOR_SWITCH_OFF       = TColor($00505050);
  COLOR_SWITCH_ON        = TColor($006AA84F);
  COLOR_TEXT_PRIMARY     = TColor($00EEEEEE);
  COLOR_TEXT_SECONDARY   = TColor($00909090);
  DRAG_THRESHOLD         = 5;  // 誤操作を避けるためD&D開始までに必要な画面距離。
  FILTER_ROW_HEIGHT      = 38; // 96 DPIでの1行の高さ。

function FilterColor(Filter: TMapRakuFilter;
  out Value: TColor): Boolean;
begin
  Result := True;
  if Filter is TMapRakuOutlineFilter then
    Value := TMapRakuOutlineFilter(Filter).Color
  else if Filter is TMapRakuShadowFilter then
    Value := TMapRakuShadowFilter(Filter).Color
  else
  begin
    Value := clNone;
    Result := False;
  end;
end;

function FilterRepresentativeRatio(Filter: TMapRakuFilter): Single;
begin
  if Filter is TMapRakuOutlineFilter then
    Result := TMapRakuOutlineFilter(Filter).Width / 40.0
  else if Filter is TMapRakuShadowFilter then
    Result := TMapRakuShadowFilter(Filter).BlurRadius / 50.0
  else if Filter is TMapRakuBlurFilter then
    Result := TMapRakuBlurFilter(Filter).Radius / 50.0
  else
    Result := 0.0;
  Result := EnsureRange(Result, 0.0, 1.0);
end;

function FilterRepresentativeMaximum(
  Filter: TMapRakuFilter): Single;
begin
  if Filter is TMapRakuOutlineFilter then
    Result := 40.0
  else
    Result := 50.0;
end;

{ TMapRakuFilterListControl }

constructor TMapRakuFilterListControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := alClient;
  Color := COLOR_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  FDragCandidateIndex := -1;
  FDragTargetIndex := -1;
  FSelectedIndex := -1;
  FSliderDragIndex := -1;
  FScrollBar := TVerticalScrollBarControl.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Visible := False;
  FScrollBar.OnChange := ScrollBarChanged;
end;

function TMapRakuFilterListControl.ContentWidth: Integer;
begin
  Result := ClientWidth;
  if (FScrollBar <> nil) and FScrollBar.Visible then
    Result := Max(Result - FScrollBar.Width, 0);
end;

procedure TMapRakuFilterListControl.UpdateScrollBar;
var
  MaximumOffset, BarWidth: Integer;
begin
  if FScrollBar = nil then Exit;
  MaximumOffset := 0;
  if FLayer <> nil then MaximumOffset := Max(FLayer.FilterCount * RowHeight - ClientHeight, 0);
  FUpdatingScrollBar := True;
  try
    BarWidth := MulDiv(14, CurrentPPI, 96);
    FScrollBar.SetBounds(Max(ClientWidth - BarWidth, 0), 0, BarWidth, ClientHeight);
    FScrollBar.Visible := MaximumOffset > 0;
    FScrollBar.SmallChange := RowHeight;
    FScrollBar.LargeChange := Max(ClientHeight - RowHeight, RowHeight);
    FScrollBar.SetRange(MaximumOffset, Max(ClientHeight, 1));
    FScrollOffset := EnsureRange(FScrollOffset, 0, MaximumOffset);
    FScrollBar.Position := FScrollOffset;
  finally
    FUpdatingScrollBar := False;
  end;
  Invalidate;
end;

procedure TMapRakuFilterListControl.ScrollBarChanged(Sender: TObject);
begin
  if FUpdatingScrollBar then Exit;
  FScrollOffset := FScrollBar.Position;
  Invalidate;
end;

procedure TMapRakuFilterListControl.EnsureSelectionVisible;
begin
  UpdateScrollBar;
  if FSelectedIndex < 0 then Exit;
  if FSelectedIndex * RowHeight < FScrollOffset then
    FScrollBar.Position := FSelectedIndex * RowHeight
  else if (FSelectedIndex + 1) * RowHeight > FScrollOffset + ClientHeight then
    FScrollBar.Position := Min(FSelectedIndex * RowHeight, (FSelectedIndex + 1) * RowHeight - ClientHeight);
end;

procedure TMapRakuFilterListControl.Resize;
begin
  inherited;
  UpdateScrollBar;
end;

function TMapRakuFilterListControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  UpdateScrollBar;
  Result := FScrollBar.Visible and (WheelDelta <> 0);
  if Result then FScrollBar.Position := FScrollOffset - MulDiv(WheelDelta, RowHeight * 3, WHEEL_DELTA);
end;

function TMapRakuFilterListControl.FilterIndexAt(Y: Integer): Integer;
begin
  if (Y < 0) or (Y >= ClientHeight) then Exit(-1);
  Result := (Y + FScrollOffset) div RowHeight;
  if (FLayer = nil) or (Result < 0) or (Result >= FLayer.FilterCount) then
    Result := -1;
end;

function TMapRakuFilterListControl.HandleRect(Index: Integer): TRect;
var
  Top: Integer;
begin
  Top := Index * RowHeight - FScrollOffset;
  Result := Rect(MulDiv(5, CurrentPPI, 96),
    Top + MulDiv(12, CurrentPPI, 96), MulDiv(17, CurrentPPI, 96),
    Top + MulDiv(26, CurrentPPI, 96));
end;

procedure TMapRakuFilterListControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  HitSwitch, HitSlider, HitHandle: Boolean;
begin
  inherited;
  if (Button <> mbLeft) or (X < 0) or (X >= ContentWidth) then
    Exit;
  Index := FilterIndexAt(Y);
  HitSwitch := (Index >= 0) and PtInRect(SwitchRect(Index), Point(X, Y));
  HitSlider := (Index >= 0) and PtInRect(SliderRect(Index), Point(X, Y));
  HitHandle := (Index >= 0) and PtInRect(HandleRect(Index), Point(X, Y));
  SelectedIndex := Index;
  if Index < 0 then
    Exit;
  if HitSwitch then
  begin
    if Assigned(FOnToggleEnabled) then
      FOnToggleEnabled(Self, Index);
    Exit;
  end;
  if HitSlider then
  begin
    FSliderDragIndex := Index;
    MouseCapture := True;
    if Assigned(FOnValueGestureStart) then
      FOnValueGestureStart(Self, Index);
    UpdateSliderValue(Index, X);
    Exit;
  end;
  if HitHandle then
  begin
    FDragCandidateIndex := Index;
    FDragStartPoint := Point(X, Y);
    FDragTargetIndex := Index;
  end;
end;

procedure TMapRakuFilterListControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  TargetIndex: Integer;
begin
  inherited;
  if (ssLeft in Shift) and (FSliderDragIndex >= 0) then
  begin
    UpdateSliderValue(FSliderDragIndex, X);
    Exit;
  end;
  if not (ssLeft in Shift) or (FDragCandidateIndex < 0) or
    (FLayer = nil) then
    Exit;
  if not FDragging and
    (Abs(X - FDragStartPoint.X) < DRAG_THRESHOLD) and
    (Abs(Y - FDragStartPoint.Y) < DRAG_THRESHOLD) then
    Exit;
  FDragging := True;
  MouseCapture := True;
  if Y < 0 then FScrollBar.Position := FScrollOffset - RowHeight
  else if Y >= ClientHeight then FScrollBar.Position := FScrollOffset + RowHeight;
  TargetIndex := EnsureRange((Y + FScrollOffset) div RowHeight, 0, FLayer.FilterCount - 1);
  if FDragTargetIndex <> TargetIndex then
  begin
    FDragTargetIndex := TargetIndex;
    Invalidate;
  end;
end;

procedure TMapRakuFilterListControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  FromIndex: Integer;
  ToIndex: Integer;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  if FSliderDragIndex >= 0 then
  begin
    UpdateSliderValue(FSliderDragIndex, X);
    if Assigned(FOnValueGestureEnd) then
      FOnValueGestureEnd(Self, FSliderDragIndex);
    FSliderDragIndex := -1;
    MouseCapture := False;
    Exit;
  end;
  MouseCapture := False;
  FromIndex := FDragCandidateIndex;
  ToIndex := FDragTargetIndex;
  FDragCandidateIndex := -1;
  FDragTargetIndex := -1;
  if FDragging and (FromIndex >= 0) and (ToIndex >= 0) and
    (FromIndex <> ToIndex) and Assigned(FOnMoveFilter) then
    FOnMoveFilter(Self, FromIndex, ToIndex);
  FDragging := False;
  Invalidate;
end;

procedure TMapRakuFilterListControl.Paint;
var
  ColorRect: TRect;
  ColorValue: TColor;
  Filter: TMapRakuFilter;
  Handle: TRect;
  I: Integer;
  KnobRadius: Integer;
  KnobX: Integer;
  KnobY: Integer;
  RowRect: TRect;
  SliderRect: TRect;
  SwitchBounds: TRect;
  TextRect: TRect;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -MulDiv(12, CurrentPPI, 96);
  Canvas.Brush.Style := bsSolid;
  if (FLayer = nil) or (FLayer.FilterCount = 0) then
  begin
    Canvas.Font.Color := COLOR_TEXT_SECONDARY;
    Canvas.Brush.Style := bsClear;
    TextRect := ClientRect;
    DrawText(Canvas.Handle, 'フィルターなし', -1, TextRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Exit;
  end;

  for I := 0 to FLayer.FilterCount - 1 do
  begin
    Filter := FLayer.Filters[I];
    RowRect := Rect(0, I * RowHeight - FScrollOffset, ContentWidth,
      (I + 1) * RowHeight - FScrollOffset - 1);
    if (RowRect.Bottom <= 0) or (RowRect.Top >= ClientHeight) then Continue;
    if I = FSelectedIndex then
      Canvas.Brush.Color := COLOR_ROW_SELECTED
    else
      Canvas.Brush.Color := COLOR_ROW;
    Canvas.FillRect(RowRect);

    Handle := HandleRect(I);
    Canvas.Brush.Color := COLOR_DRAG_HANDLE;
    Canvas.Pen.Color := COLOR_DRAG_HANDLE;
    Canvas.Rectangle(Handle);

    SwitchBounds := SwitchRect(I);
    if Filter.Enabled then
    begin
      Canvas.Brush.Color := COLOR_SWITCH_ON;
      Canvas.Pen.Color := COLOR_SWITCH_ON;
    end
    else
    begin
      Canvas.Brush.Color := COLOR_SWITCH_OFF;
      Canvas.Pen.Color := COLOR_SWITCH_OFF;
    end;
    Canvas.RoundRect(SwitchBounds.Left, SwitchBounds.Top,
      SwitchBounds.Right, SwitchBounds.Bottom,
      SwitchBounds.Height, SwitchBounds.Height);

    TextRect := Rect(MulDiv(48, CurrentPPI, 96), RowRect.Top,
      MulDiv(96, CurrentPPI, 96), RowRect.Bottom);
    Canvas.Font.Color := COLOR_TEXT_PRIMARY;
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(Filter.DisplayName), -1, TextRect,
      DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS or
      DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;

    ColorRect := Rect(Max(ContentWidth - MulDiv(24, CurrentPPI, 96),
      MulDiv(104, CurrentPPI, 96)), RowRect.Top + MulDiv(9, CurrentPPI, 96),
      ContentWidth - MulDiv(6, CurrentPPI, 96),
      RowRect.Bottom - MulDiv(9, CurrentPPI, 96));
    SliderRect := Self.SliderRect(I);
    InflateRect(SliderRect, 0, -7);
    if SliderRect.Right > SliderRect.Left then
    begin
      KnobX := SliderRect.Left + Round(SliderRect.Width *
        FilterRepresentativeRatio(Filter));
      KnobY := (SliderRect.Top + SliderRect.Bottom) div 2;
      Canvas.Brush.Color := COLOR_SLIDER;
      Canvas.FillRect(SliderRect);
      SliderRect.Right := KnobX;
      Canvas.Brush.Color := COLOR_SLIDER_VALUE;
      Canvas.FillRect(SliderRect);
      KnobRadius := MulDiv(6, CurrentPPI, 96);
      Canvas.Brush.Color := clWhite;
      Canvas.Pen.Color := clBlack;
      Canvas.Pen.Width := Max(MulDiv(2, CurrentPPI, 96), 1);
      Canvas.Ellipse(KnobX - KnobRadius, KnobY - KnobRadius,
        KnobX + KnobRadius + 1, KnobY + KnobRadius + 1);
      Canvas.Pen.Width := 1;
    end;
    if FilterColor(Filter, ColorValue) then
    begin
      Canvas.Brush.Color := ColorValue;
      if I = FSelectedIndex then
        Canvas.Pen.Color := COLOR_SLIDER_VALUE
      else
        Canvas.Pen.Color := COLOR_TEXT_SECONDARY;
      Canvas.Rectangle(ColorRect);
    end;

    if FDragging and (I = FDragTargetIndex) then
    begin
      Canvas.Pen.Color := COLOR_SLIDER_VALUE;
      Canvas.Pen.Width := 2;
      Canvas.MoveTo(RowRect.Left, RowRect.Top);
      Canvas.LineTo(RowRect.Right, RowRect.Top);
      Canvas.Pen.Width := 1;
    end;
  end;
end;

function TMapRakuFilterListControl.SliderRect(Index: Integer): TRect;
var
  ColorLeft: Integer;
  Top: Integer;
begin
  Top := Index * RowHeight - FScrollOffset;
  ColorLeft := Max(ContentWidth - MulDiv(24, CurrentPPI, 96),
    MulDiv(104, CurrentPPI, 96));
  Result := Rect(MulDiv(100, CurrentPPI, 96),
    Top + MulDiv(10, CurrentPPI, 96),
    ColorLeft - MulDiv(4, CurrentPPI, 96),
    Top + MulDiv(28, CurrentPPI, 96));
end;

function TMapRakuFilterListControl.RowHeight: Integer;
begin
  Result := MulDiv(FILTER_ROW_HEIGHT, CurrentPPI, 96);
end;

procedure TMapRakuFilterListControl.SetLayer(
  const Value: TVectArtLayer);
begin
  if FLayer = Value then
  begin
    UpdateScrollBar;
    Exit;
  end;
  FLayer := Value;
  FScrollOffset := 0;
  UpdateScrollBar;
  FSelectedIndex := -1;
  FDragCandidateIndex := -1;
  FSliderDragIndex := -1;
  FDragging := False;
  Invalidate;
  if Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
end;

procedure TMapRakuFilterListControl.UpdateSliderValue(Index,
  X: Integer);
var
  Bounds: TRect;
  Ratio: Single;
begin
  if (FLayer = nil) or (Index < 0) or (Index >= FLayer.FilterCount) then
    Exit;
  Bounds := SliderRect(Index);
  if Bounds.Width <= 0 then
    Exit;
  Ratio := EnsureRange((X - Bounds.Left) / Bounds.Width, 0.0, 1.0);
  if Assigned(FOnValueChanged) then
    FOnValueChanged(Self, Index,
      Ratio * FilterRepresentativeMaximum(FLayer.Filters[Index]));
end;

procedure TMapRakuFilterListControl.SetSelectedIndex(
  const Value: Integer);
var
  NewValue: Integer;
begin
  NewValue := Value;
  if (FLayer = nil) or (NewValue < 0) or
    (NewValue >= FLayer.FilterCount) then
    NewValue := -1;
  if FSelectedIndex = NewValue then
    Exit;
  FSelectedIndex := NewValue;
  EnsureSelectionVisible;
  Invalidate;
  if Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
end;

function TMapRakuFilterListControl.SwitchRect(Index: Integer): TRect;
var
  Top: Integer;
begin
  Top := Index * RowHeight - FScrollOffset;
  Result := Rect(MulDiv(22, CurrentPPI, 96),
    Top + MulDiv(12, CurrentPPI, 96), MulDiv(43, CurrentPPI, 96),
    Top + MulDiv(26, CurrentPPI, 96));
end;

{ TMapRakuFilterFrame }

end.
