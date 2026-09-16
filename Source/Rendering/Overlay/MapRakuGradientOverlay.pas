// グラデーションの方向、外周、編集点を白黒の高コントラスト表示で描く。
unit MapRakuGradientOverlay;

interface

uses
  System.Types, Vcl.Direct2D, Vcl.Graphics, MapRakuDocument,
  MapRakuEditorState;

// 選択中レイヤーのガイドをGDIへ描く。座標は画面座標で受け取る。
procedure DrawMapRakuGradientGuide(Target: TCanvas;
  Layer: TVectArtLayer; EditorState: TVectArtEditorState;
  const StartPoint, EndPoint: TPoint); overload;
// GDI版と同じ幾何と色でDirect2Dへ描く。
procedure DrawMapRakuGradientGuide(Target: TDirect2DCanvas;
  Layer: TVectArtLayer; EditorState: TVectArtEditorState;
  const StartPoint, EndPoint: TPoint); overload;

implementation

uses
  System.Math, MapRakuOverlayHandles, MapRakuOverlayPrimitives,
  MapRakuPaintStyles;

const
  GRADIENT_HANDLE_RADIUS = 6;

function GradientAspectPoint(const A, B: TPoint; Aspect: Single): TPoint;
begin
  Result := Point(Round(A.X - (B.Y - A.Y) * Aspect),
    Round(A.Y + (B.X - A.X) * Aspect));
end;

function GradientOutline(const A, B: TPoint;
  const Style: TMapRakuPaintStyle): TArray<TPoint>;
var
  Angle: Single;
  I: Integer;
  X: Single;
  Y: Single;
begin
  Result := nil;
  if not (Style.GradientKind in
    [slgkRadial, slgkRectangle, slgkSweep]) then
    Exit;
  if Style.GradientKind = slgkRectangle then
    SetLength(Result, 5)
  else
    SetLength(Result, 65);
  for I := 0 to High(Result) do
  begin
    if Style.GradientKind = slgkRectangle then
      case I mod 4 of
        0: begin X := 1; Y := 1; end;
        1: begin X := -1; Y := 1; end;
        2: begin X := -1; Y := -1; end;
      else
        begin X := 1; Y := -1; end;
      end
    else
    begin
      Angle := 2 * Pi * I / 64;
      X := Cos(Angle);
      Y := Sin(Angle);
    end;
    Y := Y * Style.GradientAspect;
    Result[I] := Point(
      Round(A.X + X * (B.X - A.X) - Y * (B.Y - A.Y)),
      Round(A.Y + X * (B.Y - A.Y) + Y * (B.X - A.X)));
  end;
end;

function StopPoint(Offset: Single; const StartPoint,
  EndPoint: TPoint): TPoint;
begin
  Result := Point(
    Round(StartPoint.X + (EndPoint.X - StartPoint.X) * Offset),
    Round(StartPoint.Y + (EndPoint.Y - StartPoint.Y) * Offset));
end;

procedure DrawGradientHandle(Target: TCanvas; const Bounds: TRect;
  FillColor: TColor; Selected: Boolean); overload;
var
  Outer: TRect;
begin
  if Selected then
  begin
    Outer := Bounds;
    InflateRect(Outer, 3, 3);
    DrawOverlayHandleEllipse(Target, Outer, clWhite, clBlack);
  end;
  DrawOverlayHandleEllipse(Target, Bounds, FillColor, clBlack);
end;

procedure DrawGradientHandle(Target: TDirect2DCanvas; const Bounds: TRect;
  FillColor: TColor; Selected: Boolean); overload;
var
  Outer: TRect;
begin
  if Selected then
  begin
    Outer := Bounds;
    InflateRect(Outer, 3, 3);
    DrawOverlayHandleEllipse(Target, Outer, clWhite, clBlack);
  end;
  DrawOverlayHandleEllipse(Target, Bounds, FillColor, clBlack);
end;

procedure DrawMapRakuGradientGuide(Target: TCanvas;
  Layer: TVectArtLayer; EditorState: TVectArtEditorState;
  const StartPoint, EndPoint: TPoint);
var
  I: Integer;
  Outline: TArray<TPoint>;
  PointValue: TPoint;
  Stop: TMapRakuGradientStop;
begin
  Outline := GradientOutline(StartPoint, EndPoint, Layer.PaintStyle);
  for I := 1 to High(Outline) do
    DrawOverlayLine(Target, Outline[I - 1], Outline[I]);
  if Length(Outline) > 0 then
  begin
    PointValue := GradientAspectPoint(StartPoint, EndPoint,
      Layer.PaintStyle.GradientAspect);
    DrawGradientHandle(Target, Rect(PointValue.X - 4, PointValue.Y - 4,
      PointValue.X + 5, PointValue.Y + 5), clWhite, False);
  end;
  DrawOverlayLine(Target, StartPoint, EndPoint);
  DrawGradientHandle(Target,
    Rect(StartPoint.X - GRADIENT_HANDLE_RADIUS,
      StartPoint.Y - GRADIENT_HANDLE_RADIUS,
      StartPoint.X + GRADIENT_HANDLE_RADIUS + 1,
      StartPoint.Y + GRADIENT_HANDLE_RADIUS + 1),
    Layer.PaintStyle.GradientStartColor,
    (EditorState.SelectedGradientLayer = Layer) and
      (EditorState.SelectedGradientStopId =
        SCREEN_LAYOUT_GRADIENT_START_STOP_ID));
  for Stop in Layer.PaintStyle.GetGradientStops do
  begin
    PointValue := StopPoint(Stop.Offset, StartPoint, EndPoint);
    DrawGradientHandle(Target,
      Rect(PointValue.X - GRADIENT_HANDLE_RADIUS,
        PointValue.Y - GRADIENT_HANDLE_RADIUS,
        PointValue.X + GRADIENT_HANDLE_RADIUS + 1,
        PointValue.Y + GRADIENT_HANDLE_RADIUS + 1), Stop.Color,
      (EditorState.SelectedGradientLayer = Layer) and
        (EditorState.SelectedGradientStopId = Stop.Id));
  end;
  DrawGradientHandle(Target,
    Rect(EndPoint.X - GRADIENT_HANDLE_RADIUS,
      EndPoint.Y - GRADIENT_HANDLE_RADIUS,
      EndPoint.X + GRADIENT_HANDLE_RADIUS + 1,
      EndPoint.Y + GRADIENT_HANDLE_RADIUS + 1),
    Layer.PaintStyle.GradientEndColor,
    (EditorState.SelectedGradientLayer = Layer) and
      (EditorState.SelectedGradientStopId =
        SCREEN_LAYOUT_GRADIENT_END_STOP_ID));
end;

procedure DrawMapRakuGradientGuide(Target: TDirect2DCanvas;
  Layer: TVectArtLayer; EditorState: TVectArtEditorState;
  const StartPoint, EndPoint: TPoint);
var
  I: Integer;
  Outline: TArray<TPoint>;
  PointValue: TPoint;
  Stop: TMapRakuGradientStop;
begin
  Outline := GradientOutline(StartPoint, EndPoint, Layer.PaintStyle);
  for I := 1 to High(Outline) do
    DrawOverlayLine(Target, Outline[I - 1], Outline[I]);
  if Length(Outline) > 0 then
  begin
    PointValue := GradientAspectPoint(StartPoint, EndPoint,
      Layer.PaintStyle.GradientAspect);
    DrawGradientHandle(Target, Rect(PointValue.X - 4, PointValue.Y - 4,
      PointValue.X + 5, PointValue.Y + 5), clWhite, False);
  end;
  DrawOverlayLine(Target, StartPoint, EndPoint);
  DrawGradientHandle(Target,
    Rect(StartPoint.X - GRADIENT_HANDLE_RADIUS,
      StartPoint.Y - GRADIENT_HANDLE_RADIUS,
      StartPoint.X + GRADIENT_HANDLE_RADIUS + 1,
      StartPoint.Y + GRADIENT_HANDLE_RADIUS + 1),
    Layer.PaintStyle.GradientStartColor,
    (EditorState.SelectedGradientLayer = Layer) and
      (EditorState.SelectedGradientStopId =
        SCREEN_LAYOUT_GRADIENT_START_STOP_ID));
  for Stop in Layer.PaintStyle.GetGradientStops do
  begin
    PointValue := StopPoint(Stop.Offset, StartPoint, EndPoint);
    DrawGradientHandle(Target,
      Rect(PointValue.X - GRADIENT_HANDLE_RADIUS,
        PointValue.Y - GRADIENT_HANDLE_RADIUS,
        PointValue.X + GRADIENT_HANDLE_RADIUS + 1,
        PointValue.Y + GRADIENT_HANDLE_RADIUS + 1), Stop.Color,
      (EditorState.SelectedGradientLayer = Layer) and
        (EditorState.SelectedGradientStopId = Stop.Id));
  end;
  DrawGradientHandle(Target,
    Rect(EndPoint.X - GRADIENT_HANDLE_RADIUS,
      EndPoint.Y - GRADIENT_HANDLE_RADIUS,
      EndPoint.X + GRADIENT_HANDLE_RADIUS + 1,
      EndPoint.Y + GRADIENT_HANDLE_RADIUS + 1),
    Layer.PaintStyle.GradientEndColor,
    (EditorState.SelectedGradientLayer = Layer) and
      (EditorState.SelectedGradientStopId =
        SCREEN_LAYOUT_GRADIENT_END_STOP_ID));
end;

end.
