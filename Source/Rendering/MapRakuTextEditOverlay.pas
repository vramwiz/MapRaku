// 文字編集中だけ表示する選択範囲と新規入力ガイドの配置計算・描画を担当する。
unit MapRakuTextEditOverlay;

interface

uses
  System.Types, Vcl.Direct2D, Vcl.Graphics, MapRakuDocument;

type
  TMapRakuTextEditOverlayState = record
    Layer: TMapRakuTextLayer; // 編集対象。nilなら選択範囲を表示しない。
    Text: string;                  // Document反映前を含む現在の編集文字列。
    CaretIndex: Integer;           // 選択可動端のUTF-16挿入位置。
    SelectionAnchor: Integer;      // 選択固定端のUTF-16挿入位置。
    CompositionText: string;       // Document未反映のIME未確定文字列。
    CompositionPosition: TPoint;   // 未確定文字列の画面座標上の左上。
    CompositionFontHeight: Integer; // IME受取用Editと同じフォント高。
    CanvasBounds: TRect;           // コントロール座標上の出力範囲。
    CanvasWidth: Integer;          // 中央原点変換に使用する論理出力幅。
    CanvasHeight: Integer;         // 中央原点変換に使用する論理出力高。
    Zoom: Single;                  // 論理座標から画面座標への表示倍率。
    DragActive: Boolean;           // 新規文字入力ガイドのドラッグ中ならTrue。
    DragStart: TPoint;             // コントロール座標上のドラッグ始点。
    DragCurrent: TPoint;           // コントロール座標上の現在の終点。
  end;

// Documentを変更せず、文字選択範囲と新規入力ガイドをGDIへ描画する。
procedure DrawMapRakuTextEditOverlay(Target: TCanvas;
  const State: TMapRakuTextEditOverlayState); overload;
// GDI版と同じ配置計算を使用して文字編集オーバーレイをDirect2Dへ描画する。
procedure DrawMapRakuTextEditOverlay(Target: TDirect2DCanvas;
  const State: TMapRakuTextEditOverlayState); overload;

implementation

uses
  System.Math, System.Skia, MapRakuGeometry, MapRakuTextEditing,
  MapRakuOverlayShapes, MapRakuTextGeometry, MapRakuProjectiveTransform;

type
  TMapRakuTextSelectionRun = record
    Bounds: TRect; // 選択された行内範囲の画面座標矩形。
    Text: string;  // 選択色の矩形上へ描画する文字列。
    Points: array[0..3] of TPoint; // 変形後の文字選択範囲。
  end;

function HorizontalTextAlignmentOffset(
  Alignment: TMapRakuTextAlignment; LayoutWidth,
  LineWidth: Single): Single;
begin
  case Ord(Alignment) mod 3 of
    1: Result := (LayoutWidth - LineWidth) * 0.5;
    2: Result := LayoutWidth - LineWidth;
  else
    Result := 0;
  end;
end;

function ToScreenX(Value: Single;
  const State: TMapRakuTextEditOverlayState): Integer;
begin
  Result := LogicalToScreenX(Value, State.CanvasBounds, State.Zoom,
    State.CanvasWidth);
end;

function ToScreenY(Value: Single;
  const State: TMapRakuTextEditOverlayState): Integer;
begin
  Result := LogicalToScreenY(Value, State.CanvasBounds, State.Zoom,
    State.CanvasHeight);
end;

function BuildSelectionRuns(const State: TMapRakuTextEditOverlayState;
  out FontHeight: Integer): TArray<TMapRakuTextSelectionRun>;
var
  CaretLines: TArray<TMapRakuCaretLine>;
  Font: ISkFont;
  I: Integer;
  Layout: TMapRakuTextLayout;
  LogicalBottom: Single;
  LogicalLeft: Single;
  LogicalRight: Single;
  LogicalTop: Single;
  LineHeight: Single;
  LineOffset: Single;
  LineWidth: Single;
  PrefixText: string;
  RunIndex: Integer;
  ScaleX: Single;
  ScaleY: Single;
  SelectionEnd: Integer;
  SelectionStart: Integer;
  SelectedText: string;
  SpanEnd: Integer;
  SpanStart: Integer;
  Q: TMapRakuQuad;
  P: TPointF;
  J: Integer;
begin
  Result := nil;
  FontHeight := 0;
  if State.Layer = nil then
    Exit;
  SelectionStart := Min(State.CaretIndex, State.SelectionAnchor);
  SelectionEnd := Max(State.CaretIndex, State.SelectionAnchor);
  if SelectionStart = SelectionEnd then
    Exit;
  Font := CreateMapRakuTextFont(State.Layer.FontFamily,
    State.Layer.FontSize, State.Layer.FontStyle);
  LineHeight := Max(Font.Spacing + State.Layer.FontSize *
    State.Layer.LineSpacingRatio, 1.0);
  CaretLines := BuildMapRakuTextCaretLines(State.Text,
    State.Layer.FontFamily, State.Layer.FontSize, State.Layer.WrapWidth,
    State.Layer.FontStyle, State.Layer.LetterSpacingRatio,
    State.Layer.LineSpacingRatio);
  Layout := BuildMapRakuTextLayout(State.Text,
    State.Layer.FontFamily, State.Layer.FontSize, State.Layer.WrapWidth,
    State.Layer.FontStyle, State.Layer.LetterSpacingRatio,
    State.Layer.LineSpacingRatio);
  if State.Layer is TMapRakuTextPathLayer then
  begin
    ScaleX := 1.0;
    ScaleY := 1.0;
  end
  else
  begin
    ScaleX := State.Layer.Bounds.Width / Max(Layout.Width, 1.0);
    ScaleY := State.Layer.Bounds.Height /
      Max(Layout.Height, State.Layer.FontSize);
  end;
  FontHeight := -Max(Round(State.Layer.FontSize * ScaleY * State.Zoom), 1);
  for I := 0 to High(CaretLines) do
  begin
    SpanStart := Max(SelectionStart, CaretLines[I].StartIndex);
    SpanEnd := Min(SelectionEnd, CaretLines[I].EndIndex);
    if SpanStart >= SpanEnd then
      Continue;
    PrefixText := Copy(State.Text, CaretLines[I].StartIndex + 1,
      SpanStart - CaretLines[I].StartIndex);
    SelectedText := Copy(State.Text, SpanStart + 1, SpanEnd - SpanStart);
    LineWidth := MeasureMapRakuText(CaretLines[I].Text, Font,
      State.Layer.FontSize * State.Layer.LetterSpacingRatio);
    LineOffset := HorizontalTextAlignmentOffset(State.Layer.Alignment,
      Layout.Width, LineWidth);
    RunIndex := Length(Result);
    SetLength(Result, RunIndex + 1);
    LogicalLeft := State.Layer.Bounds.Left + (LineOffset +
      MeasureMapRakuText(PrefixText, Font,
        State.Layer.FontSize * State.Layer.LetterSpacingRatio)) * ScaleX;
    LogicalRight := State.Layer.Bounds.Left + (LineOffset +
      MeasureMapRakuText(PrefixText + SelectedText, Font,
        State.Layer.FontSize * State.Layer.LetterSpacingRatio)) * ScaleX;
    LogicalTop := State.Layer.Bounds.Top + I * LineHeight * ScaleY;
    LogicalBottom := State.Layer.Bounds.Top + (I + 1) * LineHeight * ScaleY;
    if State.Layer.FlipHorizontal then
    begin
      LogicalLeft := State.Layer.Bounds.Left + State.Layer.Bounds.Right -
        LogicalLeft;
      LogicalRight := State.Layer.Bounds.Left + State.Layer.Bounds.Right -
        LogicalRight;
    end;
    if State.Layer.FlipVertical then
    begin
      LogicalTop := State.Layer.Bounds.Top + State.Layer.Bounds.Bottom -
        LogicalTop;
      LogicalBottom := State.Layer.Bounds.Top + State.Layer.Bounds.Bottom -
        LogicalBottom;
    end;
    Result[RunIndex].Bounds := Rect(
      ToScreenX(Min(LogicalLeft, LogicalRight), State),
      ToScreenY(Min(LogicalTop, LogicalBottom), State),
      ToScreenX(Max(LogicalLeft, LogicalRight), State),
      ToScreenY(Max(LogicalTop, LogicalBottom), State));
    Result[RunIndex].Text := SelectedText;
    Q := MapRakuRectQuad(TRectF.Create(Min(LogicalLeft,LogicalRight),
      Min(LogicalTop,LogicalBottom),Max(LogicalLeft,LogicalRight),Max(LogicalTop,LogicalBottom)));
    for J := 0 to 3 do
    begin
      P := RotatePointAround(Q[J],State.Layer.Bounds.CenterPoint,State.Layer.RotationDegrees);
      P := State.Layer.Transform.Map(P);
      Result[RunIndex].Points[J] := Point(ToScreenX(P.X,State),ToScreenY(P.Y,State));
    end;
  end;
end;

function InputGuideRect(
  const State: TMapRakuTextEditOverlayState): TRect;
begin
  Result := TRect.Create(Min(State.DragStart.X, State.DragCurrent.X),
    Min(State.DragStart.Y, State.DragCurrent.Y),
    Max(State.DragStart.X, State.DragCurrent.X),
    Max(State.DragStart.Y, State.DragCurrent.Y));
end;

procedure DrawContrastText(Target: TCanvas; const State:
  TMapRakuTextEditOverlayState); overload;
var
  OffsetX: Integer;
  OffsetY: Integer;
begin
  if (State.Layer = nil) or (State.CompositionText = '') then
    Exit;
  Target.Font.Name := State.Layer.FontFamily;
  Target.Font.Height := State.CompositionFontHeight;
  Target.Font.Style := State.Layer.FontStyle + [fsUnderline];
  Target.Brush.Style := bsClear;
  Target.Font.Color := clWhite;
  for OffsetY := -1 to 1 do
    for OffsetX := -1 to 1 do
      if (OffsetX <> 0) or (OffsetY <> 0) then
        Target.TextOut(State.CompositionPosition.X + OffsetX,
          State.CompositionPosition.Y + OffsetY, State.CompositionText);
  Target.Font.Color := clBlack;
  Target.TextOut(State.CompositionPosition.X, State.CompositionPosition.Y,
    State.CompositionText);
end;

procedure DrawContrastText(Target: TDirect2DCanvas; const State:
  TMapRakuTextEditOverlayState); overload;
var
  OffsetX: Integer;
  OffsetY: Integer;
begin
  if (State.Layer = nil) or (State.CompositionText = '') then
    Exit;
  Target.Font.Name := State.Layer.FontFamily;
  Target.Font.Height := State.CompositionFontHeight;
  Target.Font.Style := State.Layer.FontStyle + [fsUnderline];
  Target.Brush.Style := bsClear;
  Target.Font.Color := clWhite;
  for OffsetY := -1 to 1 do
    for OffsetX := -1 to 1 do
      if (OffsetX <> 0) or (OffsetY <> 0) then
        Target.TextOut(State.CompositionPosition.X + OffsetX,
          State.CompositionPosition.Y + OffsetY, State.CompositionText);
  Target.Font.Color := clBlack;
  Target.TextOut(State.CompositionPosition.X, State.CompositionPosition.Y,
    State.CompositionText);
end;

procedure DrawMapRakuTextEditOverlay(Target: TCanvas;
  const State: TMapRakuTextEditOverlayState);
var
  FontHeight: Integer;
  GuideRect: TRect;
  Run: TMapRakuTextSelectionRun;
  Runs: TArray<TMapRakuTextSelectionRun>;
begin
  Runs := BuildSelectionRuns(State, FontHeight);
  if Length(Runs) > 0 then
  begin
    Target.Font.Name := State.Layer.FontFamily;
    Target.Font.Height := FontHeight;
    Target.Font.Style := State.Layer.FontStyle;
    Target.Font.Color := clHighlightText;
    for Run in Runs do
    begin
      if not State.Layer.Transform.IsIdentity then
      begin
        // 射影後の文字を元の矩形文字で覆わず、選択範囲の輪郭を示す。
        Target.Brush.Style := bsClear;
        Target.Pen.Color := clHighlight;
        Target.Polygon(Run.Points);
        Continue;
      end;
      Target.Brush.Style := bsSolid;
      Target.Brush.Color := clHighlight;
      Target.FillRect(Run.Bounds);
      Target.Brush.Style := bsClear;
      Target.TextOut(Run.Bounds.Left, Run.Bounds.Top, Run.Text);
    end;
  end;
  DrawContrastText(Target, State);
  if State.DragActive then
  begin
    GuideRect := InputGuideRect(State);
    DrawOverlayFrameRect(Target, GuideRect, clBlack, psDot);
  end;
end;

procedure DrawMapRakuTextEditOverlay(Target: TDirect2DCanvas;
  const State: TMapRakuTextEditOverlayState);
var
  FontHeight: Integer;
  GuideRect: TRect;
  Run: TMapRakuTextSelectionRun;
  Runs: TArray<TMapRakuTextSelectionRun>;
begin
  Runs := BuildSelectionRuns(State, FontHeight);
  if Length(Runs) > 0 then
  begin
    Target.Font.Name := State.Layer.FontFamily;
    Target.Font.Height := FontHeight;
    Target.Font.Style := State.Layer.FontStyle;
    Target.Font.Color := clHighlightText;
    for Run in Runs do
    begin
      if not State.Layer.Transform.IsIdentity then
      begin
        Target.Brush.Style := bsClear;
        Target.Pen.Color := clHighlight;
        Target.Polygon(Run.Points);
        Continue;
      end;
      Target.Brush.Style := bsSolid;
      Target.Brush.Color := clHighlight;
      Target.FillRect(Run.Bounds);
      Target.Brush.Style := bsClear;
      Target.TextOut(Run.Bounds.Left, Run.Bounds.Top, Run.Text);
    end;
  end;
  DrawContrastText(Target, State);
  if State.DragActive then
  begin
    GuideRect := InputGuideRect(State);
    DrawOverlayFrameRect(Target, GuideRect, clBlack, psDot);
  end;
end;

end.
