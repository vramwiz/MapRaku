// 編集キャンバス上の図形作成プレビューと操作補助アイコンを描画する。
unit MapRakuCanvasPreview;

interface

uses
  System.Types, Vcl.Direct2D, Vcl.Graphics, MapRakuDocument;

// 頂点種別を示す鋭角またはベジェ形状のアイコン座標を返す。
function BuildVertexKindIconPoints(const Bounds: TRect;
  Kind: TMapRakuVertexKind): TArray<TPoint>;
// 角丸半径ハンドルとして使用する菱形の4頂点を返す。
function BuildDiamondPoints(const Bounds: TRect): TArray<TPoint>;
// 回転ハンドル内へ収まる円弧と矢印の座標を返す。
procedure BuildRotationMarkPoints(const Bounds: TRect;
  out ArcPoints, ArrowPoints: TArray<TPoint>);
// 明暗どちらの背景でも判別できる字間・行間用の双方向矢印をGDIへ描画する。
procedure DrawBidirectionalArrow(Target: TCanvas;
  const ArrowStart, ArrowEnd: TPoint); overload;
// GDI版と同じ双方向矢印をDirect2Dへ描画する。
procedure DrawBidirectionalArrow(Target: TDirect2DCanvas;
  const ArrowStart, ArrowEnd: TPoint); overload;
// GDIキャンバスへ線種と線端を反映した作成プレビューを描画する。
procedure DrawStyledPreviewLine(Target: TCanvas; const StartPoint,
  EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap); overload;
// Direct2Dキャンバスへ線種と線端を反映した作成プレビューを描画する。
procedure DrawStyledPreviewLine(Target: TDirect2DCanvas;
  const StartPoint, EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap); overload;
// Draws the freehand input hotspot and its current document stroke diameter.
procedure DrawStrokeWidthCursor(Target: TCanvas; const Center: TPoint;
  Width: Single; MarkerHalfSize: Integer); overload;
// Direct2D counterpart of the freehand stroke-width cursor.
procedure DrawStrokeWidthCursor(Target: TDirect2DCanvas;
  const Center: TPoint; Width: Single; MarkerHalfSize: Integer); overload;
// Draws pressure samples with per-segment widths during freehand creation.
procedure DrawVariableWidthPreview(Target: TCanvas;
  const Points: TArray<TPoint>; const WidthScales: TArray<Single>;
  Color: TColor; BaseWidth: Single); overload;
// Direct2D counterpart of the pressure-sensitive freehand preview.
procedure DrawVariableWidthPreview(Target: TDirect2DCanvas;
  const Points: TArray<TPoint>; const WidthScales: TArray<Single>;
  Color: TColor; BaseWidth: Single); overload;

implementation

uses
  System.Math, System.UITypes, Winapi.D2D1, MapRakuOverlayHandles,
  MapRakuOverlayPrimitives, MapRakuOverlayShapes,
  MapRakuRenderer;

type
  TPreviewLineSegment = record
    StartPoint: TPoint; // 画面座標での描画開始点。
    EndPoint: TPoint;   // 画面座標での描画終了点。
  end;

procedure BidirectionalArrowHeadPoints(const ArrowStart, ArrowEnd: TPoint;
  out StartHeadA, StartHeadB, EndHeadA, EndHeadB: TPoint);
const
  HEAD_LENGTH = 8.0;
  HEAD_HALF_WIDTH = 6.0;
var
  AxisLength: Single;
  AxisX: Single;
  AxisY: Single;
  PerpendicularX: Single;
  PerpendicularY: Single;
begin
  AxisX := ArrowEnd.X - ArrowStart.X;
  AxisY := ArrowEnd.Y - ArrowStart.Y;
  AxisLength := Hypot(AxisX, AxisY);
  if AxisLength <= 0 then
  begin
    StartHeadA := ArrowStart;
    StartHeadB := ArrowStart;
    EndHeadA := ArrowEnd;
    EndHeadB := ArrowEnd;
    Exit;
  end;
  AxisX := AxisX / AxisLength;
  AxisY := AxisY / AxisLength;
  PerpendicularX := -AxisY;
  PerpendicularY := AxisX;
  StartHeadA := Point(
    Round(ArrowStart.X + AxisX * HEAD_LENGTH +
      PerpendicularX * HEAD_HALF_WIDTH),
    Round(ArrowStart.Y + AxisY * HEAD_LENGTH +
      PerpendicularY * HEAD_HALF_WIDTH));
  StartHeadB := Point(
    Round(ArrowStart.X + AxisX * HEAD_LENGTH -
      PerpendicularX * HEAD_HALF_WIDTH),
    Round(ArrowStart.Y + AxisY * HEAD_LENGTH -
      PerpendicularY * HEAD_HALF_WIDTH));
  EndHeadA := Point(
    Round(ArrowEnd.X - AxisX * HEAD_LENGTH +
      PerpendicularX * HEAD_HALF_WIDTH),
    Round(ArrowEnd.Y - AxisY * HEAD_LENGTH +
      PerpendicularY * HEAD_HALF_WIDTH));
  EndHeadB := Point(
    Round(ArrowEnd.X - AxisX * HEAD_LENGTH -
      PerpendicularX * HEAD_HALF_WIDTH),
    Round(ArrowEnd.Y - AxisY * HEAD_LENGTH -
      PerpendicularY * HEAD_HALF_WIDTH));
end;

procedure DrawBidirectionalArrow(Target: TCanvas;
  const ArrowStart, ArrowEnd: TPoint);
var
  EndTriangle: array[0..2] of TPoint;
  EndHeadA: TPoint;
  EndHeadB: TPoint;
  StartTriangle: array[0..2] of TPoint;
  StartHeadA: TPoint;
  StartHeadB: TPoint;
begin
  BidirectionalArrowHeadPoints(ArrowStart, ArrowEnd, StartHeadA,
    StartHeadB, EndHeadA, EndHeadB);
  DrawOverlayLine(Target, ArrowStart, ArrowEnd, clBlack, psSolid, 5, 2);
  StartTriangle[0] := ArrowStart;
  StartTriangle[1] := StartHeadA;
  StartTriangle[2] := StartHeadB;
  EndTriangle[0] := ArrowEnd;
  EndTriangle[1] := EndHeadA;
  EndTriangle[2] := EndHeadB;
  DrawOverlayHandlePolygon(Target, StartTriangle, clBlack, clBlack);
  DrawOverlayHandlePolygon(Target, EndTriangle, clBlack, clBlack);
end;

procedure DrawBidirectionalArrow(Target: TDirect2DCanvas;
  const ArrowStart, ArrowEnd: TPoint);
var
  EndTriangle: array[0..2] of TPoint;
  EndHeadA: TPoint;
  EndHeadB: TPoint;
  StartTriangle: array[0..2] of TPoint;
  StartHeadA: TPoint;
  StartHeadB: TPoint;
begin
  BidirectionalArrowHeadPoints(ArrowStart, ArrowEnd, StartHeadA,
    StartHeadB, EndHeadA, EndHeadB);
  DrawOverlayLine(Target, ArrowStart, ArrowEnd, clBlack, psSolid, 5, 2);
  StartTriangle[0] := ArrowStart;
  StartTriangle[1] := StartHeadA;
  StartTriangle[2] := StartHeadB;
  EndTriangle[0] := ArrowEnd;
  EndTriangle[1] := EndHeadA;
  EndTriangle[2] := EndHeadB;
  DrawOverlayHandlePolygon(Target, StartTriangle, clBlack, clBlack);
  DrawOverlayHandlePolygon(Target, EndTriangle, clBlack, clBlack);
end;

function BuildVertexKindIconPoints(const Bounds: TRect;
  Kind: TMapRakuVertexKind): TArray<TPoint>;
var
  CenterX: Integer;
begin
  CenterX := (Bounds.Left + Bounds.Right) div 2;
  if Kind = slvkSharp then
  begin
    SetLength(Result, 3);
    Result[0] := Point(Bounds.Left + 5, Bounds.Top + 5);
    Result[1] := Point(CenterX, Bounds.Bottom - 5);
    Result[2] := Point(Bounds.Right - 5, Bounds.Top + 5);
  end
  else
  begin
    SetLength(Result, 7);
    Result[0] := Point(Bounds.Left + 5, Bounds.Top + 5);
    Result[1] := Point(Bounds.Left + 5, Bounds.Bottom - 8);
    Result[2] := Point(Bounds.Left + 7, Bounds.Bottom - 5);
    Result[3] := Point(CenterX, Bounds.Bottom - 4);
    Result[4] := Point(Bounds.Right - 7, Bounds.Bottom - 5);
    Result[5] := Point(Bounds.Right - 5, Bounds.Bottom - 8);
    Result[6] := Point(Bounds.Right - 5, Bounds.Top + 5);
  end;
end;

function BuildDiamondPoints(const Bounds: TRect): TArray<TPoint>;
begin
  SetLength(Result, 4);
  Result[0] := Point((Bounds.Left + Bounds.Right) div 2, Bounds.Top);
  Result[1] := Point(Bounds.Right, (Bounds.Top + Bounds.Bottom) div 2);
  Result[2] := Point((Bounds.Left + Bounds.Right) div 2, Bounds.Bottom);
  Result[3] := Point(Bounds.Left, (Bounds.Top + Bounds.Bottom) div 2);
end;

function StrokeWidthCursorBounds(const Center: TPoint;
  Width: Single): TRect;
var
  Diameter: Integer;
begin
  Diameter := Max(Round(Width), 1);
  Result.Left := Center.X - Diameter div 2;
  Result.Top := Center.Y - Diameter div 2;
  Result.Right := Result.Left + Diameter;
  Result.Bottom := Result.Top + Diameter;
end;

procedure DrawStrokeWidthCursor(Target: TCanvas; const Center: TPoint;
  Width: Single; MarkerHalfSize: Integer);
var
  Bounds: TRect;
begin
  Bounds := StrokeWidthCursorBounds(Center, Width);
  DrawOverlayEllipse(Target, Bounds);
  MarkerHalfSize := Max(MarkerHalfSize, 2);
  DrawOverlayLine(Target,
    Point(Center.X - MarkerHalfSize, Center.Y),
    Point(Center.X + MarkerHalfSize, Center.Y));
  DrawOverlayLine(Target,
    Point(Center.X, Center.Y - MarkerHalfSize),
    Point(Center.X, Center.Y + MarkerHalfSize));
end;

procedure DrawStrokeWidthCursor(Target: TDirect2DCanvas;
  const Center: TPoint; Width: Single; MarkerHalfSize: Integer);
var
  Bounds: TRect;
begin
  Bounds := StrokeWidthCursorBounds(Center, Width);
  DrawOverlayEllipse(Target, Bounds);
  MarkerHalfSize := Max(MarkerHalfSize, 2);
  DrawOverlayLine(Target,
    Point(Center.X - MarkerHalfSize, Center.Y),
    Point(Center.X + MarkerHalfSize, Center.Y));
  DrawOverlayLine(Target,
    Point(Center.X, Center.Y - MarkerHalfSize),
    Point(Center.X, Center.Y + MarkerHalfSize));
end;

procedure DrawVariableWidthPreview(Target: TCanvas;
  const Points: TArray<TPoint>; const WidthScales: TArray<Single>;
  Color: TColor; BaseWidth: Single);
var
  CoreWidth: Integer;
  I: Integer;
  SegmentScale: Single;
begin
  if (Length(Points) < 2) or
    (Length(WidthScales) <> Length(Points)) then
    Exit;
  for I := 0 to High(Points) - 1 do
  begin
    SegmentScale := (WidthScales[I] + WidthScales[I + 1]) * 0.5;
    CoreWidth := Max(Round(BaseWidth * SegmentScale), 1);
    DrawOverlayLine(Target, Points[I], Points[I + 1], Color, psSolid,
      CoreWidth + 2, CoreWidth);
  end;
end;

procedure DrawVariableWidthPreview(Target: TDirect2DCanvas;
  const Points: TArray<TPoint>; const WidthScales: TArray<Single>;
  Color: TColor; BaseWidth: Single);
var
  CoreWidth: Integer;
  I: Integer;
  SegmentScale: Single;
begin
  if (Length(Points) < 2) or
    (Length(WidthScales) <> Length(Points)) then
    Exit;
  for I := 0 to High(Points) - 1 do
  begin
    SegmentScale := (WidthScales[I] + WidthScales[I + 1]) * 0.5;
    CoreWidth := Max(Round(BaseWidth * SegmentScale), 1);
    DrawOverlayLine(Target, Points[I], Points[I + 1], Color, psSolid,
      CoreWidth + 2, CoreWidth);
  end;
end;

procedure BuildRotationMarkPoints(const Bounds: TRect;
  out ArcPoints, ArrowPoints: TArray<TPoint>);
const
  ARC_POINT_COUNT = 10;
var
  Angle: Single;
  CenterX: Single;
  CenterY: Single;
  I: Integer;
  PerpendicularX: Single;
  PerpendicularY: Single;
  Radius: Single;
  TangentX: Single;
  TangentY: Single;
  Tip: TPoint;
begin
  CenterX := (Bounds.Left + Bounds.Right) * 0.5;
  CenterY := (Bounds.Top + Bounds.Bottom) * 0.5;
  Radius := Max(Min(Bounds.Width, Bounds.Height) * 0.5 - 4, 2);
  SetLength(ArcPoints, ARC_POINT_COUNT);
  for I := 0 to High(ArcPoints) do
  begin
    Angle := DegToRad(45 + 270 * I / High(ArcPoints));
    ArcPoints[I] := Point(Round(CenterX + Cos(Angle) * Radius),
      Round(CenterY - Sin(Angle) * Radius));
  end;
  Tip := ArcPoints[High(ArcPoints)];
  Angle := DegToRad(315);
  TangentX := -Sin(Angle);
  TangentY := -Cos(Angle);
  PerpendicularX := -TangentY;
  PerpendicularY := TangentX;
  SetLength(ArrowPoints, 3);
  ArrowPoints[0] := Tip;
  ArrowPoints[1] := Point(Round(Tip.X - TangentX * 4 +
    PerpendicularX * 2), Round(Tip.Y - TangentY * 4 +
    PerpendicularY * 2));
  ArrowPoints[2] := Point(Round(Tip.X - TangentX * 4 -
    PerpendicularX * 2), Round(Tip.Y - TangentY * 4 -
    PerpendicularY * 2));
end;

function BuildStyledPreviewSegments(const StartPoint, EndPoint: TPoint;
  Width: Single; Style: TVectArtMifStrokeStyle): TArray<TPreviewLineSegment>;
var
  CurrentDistance: Single;
  DashIndex: Integer;
  DrawSegment: Boolean;
  DX: Single;
  DY: Single;
  EndDistance: Single;
  Intervals: TArray<Single>;
  LineLength: Single;
  SegmentLength: Single;
  UnitX: Single;
  UnitY: Single;
begin
  Result := nil;
  DX := EndPoint.X - StartPoint.X;
  DY := EndPoint.Y - StartPoint.Y;
  LineLength := Hypot(DX, DY);
  if LineLength <= 0 then
    Exit;
  Intervals := VectArtStrokeDashIntervals(Style, Max(Width, 1.0));
  if Length(Intervals) = 0 then
  begin
    SetLength(Result, 1);
    Result[0].StartPoint := StartPoint;
    Result[0].EndPoint := EndPoint;
    Exit;
  end;
  UnitX := DX / LineLength;
  UnitY := DY / LineLength;
  CurrentDistance := 0;
  DashIndex := 0;
  DrawSegment := True;
  while CurrentDistance < LineLength do
  begin
    SegmentLength := Max(Intervals[DashIndex], 1.0);
    EndDistance := Min(CurrentDistance + SegmentLength, LineLength);
    if DrawSegment then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].StartPoint := Point(
        StartPoint.X + Round(UnitX * CurrentDistance),
        StartPoint.Y + Round(UnitY * CurrentDistance));
      Result[High(Result)].EndPoint := Point(
        StartPoint.X + Round(UnitX * EndDistance),
        StartPoint.Y + Round(UnitY * EndDistance));
    end;
    CurrentDistance := EndDistance;
    DashIndex := (DashIndex + 1) mod Length(Intervals);
    DrawSegment := not DrawSegment;
  end;
end;

procedure DrawStyledPreviewLine(Target: TCanvas; const StartPoint,
  EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap);
var
  DX: Single;
  DY: Single;
  I: Integer;
  LengthValue: Single;
  P1: TPoint;
  P2: TPoint;
  Points: array[0..2] of TPoint;
  Radius: Integer;
  Segments: TArray<TPreviewLineSegment>;
begin
  Segments := BuildStyledPreviewSegments(StartPoint, EndPoint, Width, Style);
  Target.Pen.Color := Color;
  Target.Pen.Width := Max(Round(Width), 1);
  Target.Pen.Style := psSolid;
  for I := 0 to High(Segments) do
  begin
    P1 := Segments[I].StartPoint;
    P2 := Segments[I].EndPoint;
    if LineCap = vlcSquare then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        P1.Offset(-Round(DX / LengthValue * Width * 0.5),
          -Round(DY / LengthValue * Width * 0.5));
        P2.Offset(Round(DX / LengthValue * Width * 0.5),
          Round(DY / LengthValue * Width * 0.5));
      end;
    end;
    DrawOverlayLine(Target, P1, P2, Color, psSolid,
      Max(Round(Width), 1) + 2, Max(Round(Width), 1));
    if LineCap = vlcRound then
    begin
      Radius := Max(Round(Width * 0.5), 1);
      DrawOverlayHandleEllipse(Target,
        Rect(P1.X - Radius, P1.Y - Radius, P1.X + Radius + 1,
          P1.Y + Radius + 1), Color, Color);
      DrawOverlayHandleEllipse(Target,
        Rect(P2.X - Radius, P2.Y - Radius, P2.X + Radius + 1,
          P2.Y + Radius + 1), Color, Color);
    end
    else if LineCap = vlcTriangle then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        Radius := Max(Round(Width * 0.5), 1);
        DX := DX / LengthValue;
        DY := DY / LengthValue;
        Points[0] := Point(P1.X - Round(DY * Radius),
          P1.Y + Round(DX * Radius));
        Points[1] := Point(P1.X - Round(DX * Radius),
          P1.Y - Round(DY * Radius));
        Points[2] := Point(P1.X + Round(DY * Radius),
          P1.Y - Round(DX * Radius));
        DrawOverlayHandlePolygon(Target, Points, Color, Color);
        Points[0] := Point(P2.X - Round(DY * Radius),
          P2.Y + Round(DX * Radius));
        Points[1] := Point(P2.X + Round(DX * Radius),
          P2.Y + Round(DY * Radius));
        Points[2] := Point(P2.X + Round(DY * Radius),
          P2.Y - Round(DX * Radius));
        DrawOverlayHandlePolygon(Target, Points, Color, Color);
      end;
    end;
  end;
  Target.Pen.Width := 1;
end;

procedure DrawStyledPreviewLine(Target: TDirect2DCanvas;
  const StartPoint, EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap);
var
  DX: Single;
  DY: Single;
  I: Integer;
  LengthValue: Single;
  P1: TPoint;
  P2: TPoint;
  Points: array[0..2] of TPoint;
  Radius: Integer;
  Segments: TArray<TPreviewLineSegment>;
begin
  Target.RenderTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  Segments := BuildStyledPreviewSegments(StartPoint, EndPoint, Width, Style);
  Target.Pen.Color := Color;
  Target.Pen.Width := Max(Round(Width), 1);
  Target.Pen.Style := psSolid;
  for I := 0 to High(Segments) do
  begin
    P1 := Segments[I].StartPoint;
    P2 := Segments[I].EndPoint;
    if LineCap = vlcSquare then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        P1.Offset(-Round(DX / LengthValue * Width * 0.5),
          -Round(DY / LengthValue * Width * 0.5));
        P2.Offset(Round(DX / LengthValue * Width * 0.5),
          Round(DY / LengthValue * Width * 0.5));
      end;
    end;
    DrawOverlayLine(Target, P1, P2, Color, psSolid,
      Max(Round(Width), 1) + 2, Max(Round(Width), 1));
    if LineCap = vlcRound then
    begin
      Radius := Max(Round(Width * 0.5), 1);
      DrawOverlayHandleEllipse(Target,
        Rect(P1.X - Radius, P1.Y - Radius, P1.X + Radius + 1,
          P1.Y + Radius + 1), Color, Color);
      DrawOverlayHandleEllipse(Target,
        Rect(P2.X - Radius, P2.Y - Radius, P2.X + Radius + 1,
          P2.Y + Radius + 1), Color, Color);
    end
    else if LineCap = vlcTriangle then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        Radius := Max(Round(Width * 0.5), 1);
        DX := DX / LengthValue;
        DY := DY / LengthValue;
        Points[0] := Point(P1.X - Round(DY * Radius),
          P1.Y + Round(DX * Radius));
        Points[1] := Point(P1.X - Round(DX * Radius),
          P1.Y - Round(DY * Radius));
        Points[2] := Point(P1.X + Round(DY * Radius),
          P1.Y - Round(DX * Radius));
        DrawOverlayHandlePolygon(Target, Points, Color, Color);
        Points[0] := Point(P2.X - Round(DY * Radius),
          P2.Y + Round(DX * Radius));
        Points[1] := Point(P2.X + Round(DX * Radius),
          P2.Y + Round(DY * Radius));
        Points[2] := Point(P2.X + Round(DY * Radius),
          P2.Y - Round(DX * Radius));
        DrawOverlayHandlePolygon(Target, Points, Color, Color);
      end;
    end;
  end;
  Target.Pen.Width := 1;
  Target.RenderTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
end;

end.
