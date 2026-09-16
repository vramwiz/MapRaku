// 回転を持つ図形の四隅、外接範囲、座標変換を共通計算する。
unit MapRakuGeometry;

interface

uses
  System.Types;

type
  TVectArtQuad = array[0..3] of TPointF;

function NormalizeAngleDegrees(Value: Single): Single;
function RotatePointAround(const Point, Center: TPointF;
  AngleDegrees: Single): TPointF;
function RectangleCorners(const Bounds: TRectF;
  RotationDegrees: Single): TVectArtQuad;
function QuadBounds(const Quad: TVectArtQuad): TRectF;
function PointsBounds(const Points: TArray<TPointF>): TRectF;
function PointInRotatedRectangle(const Point: TPointF; const Bounds: TRectF;
  RotationDegrees: Single): Boolean;
function PointInPolygon(const Point: TPointF;
  const Polygon: TArray<TPointF>): Boolean;
// 中央原点の論理座標を編集Control上の表示座標へ変換する。
function LogicalToScreenX(Value: Single; const CanvasBounds: TRect;
  Zoom, CanvasWidth: Single): Integer;
function LogicalToScreenY(Value: Single; const CanvasBounds: TRect;
  Zoom, CanvasHeight: Single): Integer;
// 編集Control上の表示座標をキャンバス中央原点の論理座標へ変換する。
function ScreenToLogicalX(Value: Single; const CanvasBounds: TRect;
  Zoom, CanvasWidth: Single): Single;
function ScreenToLogicalY(Value: Single; const CanvasBounds: TRect;
  Zoom, CanvasHeight: Single): Single;

implementation

uses
  System.Math;

function NormalizeAngleDegrees(Value: Single): Single;
begin
  Result := Value - Floor((Value + 180.0) / 360.0) * 360.0;
  if Result >= 180.0 then
    Result := Result - 360.0;
end;

function RotatePointAround(const Point, Center: TPointF;
  AngleDegrees: Single): TPointF;
var
  Cosine: Extended;
  DX: Single;
  DY: Single;
  Radians: Extended;
  Sine: Extended;
begin
  Radians := DegToRad(AngleDegrees);
  SinCos(Radians, Sine, Cosine);
  DX := Point.X - Center.X;
  DY := Point.Y - Center.Y;
  Result.X := Center.X + DX * Cosine - DY * Sine;
  Result.Y := Center.Y + DX * Sine + DY * Cosine;
end;

function RectangleCorners(const Bounds: TRectF;
  RotationDegrees: Single): TVectArtQuad;
var
  Center: TPointF;
begin
  Center := TPointF.Create((Bounds.Left + Bounds.Right) * 0.5,
    (Bounds.Top + Bounds.Bottom) * 0.5);
  Result[0] := RotatePointAround(TPointF.Create(Bounds.Left, Bounds.Top),
    Center, RotationDegrees);
  Result[1] := RotatePointAround(TPointF.Create(Bounds.Right, Bounds.Top),
    Center, RotationDegrees);
  Result[2] := RotatePointAround(TPointF.Create(Bounds.Right, Bounds.Bottom),
    Center, RotationDegrees);
  Result[3] := RotatePointAround(TPointF.Create(Bounds.Left, Bounds.Bottom),
    Center, RotationDegrees);
end;

function QuadBounds(const Quad: TVectArtQuad): TRectF;
var
  I: Integer;
begin
  Result := TRectF.Create(Quad[0], Quad[0]);
  for I := 1 to High(Quad) do
  begin
    Result.Left := Min(Result.Left, Quad[I].X);
    Result.Top := Min(Result.Top, Quad[I].Y);
    Result.Right := Max(Result.Right, Quad[I].X);
    Result.Bottom := Max(Result.Bottom, Quad[I].Y);
  end;
end;

function PointsBounds(const Points: TArray<TPointF>): TRectF;
var
  I: Integer;
begin
  if Length(Points) = 0 then
    Exit(TRectF.Empty);
  Result := TRectF.Create(Points[0], Points[0]);
  for I := 1 to High(Points) do
  begin
    Result.Left := Min(Result.Left, Points[I].X);
    Result.Top := Min(Result.Top, Points[I].Y);
    Result.Right := Max(Result.Right, Points[I].X);
    Result.Bottom := Max(Result.Bottom, Points[I].Y);
  end;
end;

function PointInRotatedRectangle(const Point: TPointF; const Bounds: TRectF;
  RotationDegrees: Single): Boolean;
var
  Center: TPointF;
  LocalPoint: TPointF;
begin
  Center := TPointF.Create((Bounds.Left + Bounds.Right) * 0.5,
    (Bounds.Top + Bounds.Bottom) * 0.5);
  LocalPoint := RotatePointAround(Point, Center, -RotationDegrees);
  Result := (LocalPoint.X >= Bounds.Left) and
    (LocalPoint.X <= Bounds.Right) and (LocalPoint.Y >= Bounds.Top) and
    (LocalPoint.Y <= Bounds.Bottom);
end;

function PointInPolygon(const Point: TPointF;
  const Polygon: TArray<TPointF>): Boolean;
var
  I: Integer;
  J: Integer;
begin
  Result := False;
  if Length(Polygon) < 3 then
    Exit;
  J := High(Polygon);
  for I := 0 to High(Polygon) do
  begin
    if ((Polygon[I].Y > Point.Y) <> (Polygon[J].Y > Point.Y)) and
      (Point.X < (Polygon[J].X - Polygon[I].X) *
      (Point.Y - Polygon[I].Y) / (Polygon[J].Y - Polygon[I].Y) +
      Polygon[I].X) then
      Result := not Result;
    J := I;
  end;
end;

function LogicalToScreenX(Value: Single; const CanvasBounds: TRect;
  Zoom, CanvasWidth: Single): Integer;
begin
  // 表示寸法は整数pxへ丸められるため、左端と論理幅から原点を再計算しない。
  Result := Round(CanvasBounds.Left + CanvasBounds.Width div 2 +
    Value * Zoom);
end;

function LogicalToScreenY(Value: Single; const CanvasBounds: TRect;
  Zoom, CanvasHeight: Single): Integer;
begin
  Result := Round(CanvasBounds.Top + CanvasBounds.Height div 2 +
    Value * Zoom);
end;

function ScreenToLogicalX(Value: Single; const CanvasBounds: TRect;
  Zoom, CanvasWidth: Single): Single;
begin
  Result := (Value - (CanvasBounds.Left + CanvasBounds.Width div 2)) / Zoom;
end;

function ScreenToLogicalY(Value: Single; const CanvasBounds: TRect;
  Zoom, CanvasHeight: Single): Single;
begin
  Result := (Value - (CanvasBounds.Top + CanvasBounds.Height div 2)) / Zoom;
end;

end.
