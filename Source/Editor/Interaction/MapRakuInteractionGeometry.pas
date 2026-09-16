// キャンバス操作で使う、UI状態を持たない距離・外接範囲計算を提供する。
unit MapRakuInteractionGeometry;

interface

uses
  System.Types, MapRakuDocument, MapRakuSelectionGeometry;

// 画像の4隅を包含する論理座標の外接矩形を返す。
function ImagePointsBounds(const Points: TVectArtImagePoints): TRectF;
// 符号を維持しながら画像の辺長を操作可能な最小値へ制限する。
function ClampImageDimension(Value, OriginalValue: Single): Single;
// 点から線分までの距離と、線分上の最近点を表す0～1の比率を返す。
function DistanceToSegmentParameter(const PointValue, StartPoint,
  EndPoint: TPointF; out Parameter: Single): Single;
// 点から線分までの最短距離を返す。
function DistanceToSegment(const PointValue, StartPoint,
  EndPoint: TPointF): Single;
// 点から楕円弧の輪郭までの近似距離を返す。
function ArcDistanceToPoint(ArcLayer: TMapRakuArcLayer;
  const PointValue: TPointF): Single;
// 点から閉じた楕円線の輪郭までの近似距離を返す。
function EllipseLineDistanceToPoint(LineLayer: TMapRakuEllipseLineLayer;
  const PointValue: TPointF): Single;
// 点から角丸四角形線の輪郭までの近似距離を返す。
function RoundedRectangleLineDistanceToPoint(
  LineLayer: TMapRakuRoundedRectangleLineLayer;
  const PointValue: TPointF): Single;
// 図形または線の角丸四角形から、変形に必要な共通値を取得する。
function RoundedRectangleValues(Layer: TVectArtLayer; out Bounds: TRectF;
  out Radii: TMapRakuCornerRadii; out RotationDegrees: Single): Boolean;
// 開始角から終了角までの時計回り角度を0～360度で返す。
function ClockwiseAngleDelta(StartAngle, EndAngle: Single): Single;
// 回転後の外接枠を操作した差分から、元の軸に沿った新しい矩形を返す。
function ResizeAxisAlignedOuterBounds(const StartBounds: TRectF;
  const DragStart, Current: TPoint; Handle: TVectArtSelectionHandle;
  Zoom, RotationDegrees, MinimumSize: Single): TRectF;
// 反対側のハンドルを固定し、回転を考慮した均等拡縮後の矩形を返す。
function ResizeUniformBounds(const StartBounds: TRectF;
  const StartLogical, CurrentLogical: TPointF;
  Handle: TVectArtSelectionHandle; RotationDegrees,
  MinimumSize: Single): TRectF;
// 反対側のハンドルを固定し、回転したローカル軸上で変更した矩形を返す。
function ResizeRotatedBounds(const StartBounds: TRectF;
  const StartLogical, CurrentLogical: TPointF;
  Handle: TVectArtSelectionHandle; RotationDegrees,
  MinimumSize: Single): TRectF;

implementation

uses
  System.Math, MapRakuEllipseGeometry, MapRakuGeometry;

const
  MIN_IMAGE_DIMENSION = 16.0;
  ARC_HIT_TEST_SEGMENTS = 64;

function ImagePointsBounds(const Points: TVectArtImagePoints): TRectF;
var
  I: Integer;
begin
  Result := TRectF.Create(Points[0], Points[0]);
  for I := 1 to High(Points) do
  begin
    Result.Left := Min(Result.Left, Points[I].X);
    Result.Top := Min(Result.Top, Points[I].Y);
    Result.Right := Max(Result.Right, Points[I].X);
    Result.Bottom := Max(Result.Bottom, Points[I].Y);
  end;
end;

function ClampImageDimension(Value, OriginalValue: Single): Single;
begin
  if Abs(Value) >= MIN_IMAGE_DIMENSION then
    Exit(Value);
  if not SameValue(Value, 0.0) then
    Result := Sign(Value) * MIN_IMAGE_DIMENSION
  else if OriginalValue < 0 then
    Result := -MIN_IMAGE_DIMENSION
  else
    Result := MIN_IMAGE_DIMENSION;
end;

function DistanceToSegmentParameter(const PointValue, StartPoint,
  EndPoint: TPointF; out Parameter: Single): Single;
var
  DX: Single;
  DY: Single;
  Projection: Single;
  SegmentLengthSquared: Single;
begin
  DX := EndPoint.X - StartPoint.X;
  DY := EndPoint.Y - StartPoint.Y;
  SegmentLengthSquared := DX * DX + DY * DY;
  if SegmentLengthSquared > 0 then
    Projection := EnsureRange(((PointValue.X - StartPoint.X) * DX +
      (PointValue.Y - StartPoint.Y) * DY) / SegmentLengthSquared, 0.0, 1.0)
  else
    Projection := 0;
  Result := Hypot(PointValue.X - (StartPoint.X + Projection * DX),
    PointValue.Y - (StartPoint.Y + Projection * DY));
  Parameter := Projection;
end;

function DistanceToSegment(const PointValue, StartPoint,
  EndPoint: TPointF): Single;
var
  Parameter: Single;
begin
  Result := DistanceToSegmentParameter(PointValue, StartPoint, EndPoint,
    Parameter);
end;

function ArcDistanceToPoint(ArcLayer: TMapRakuArcLayer;
  const PointValue: TPointF): Single;
var
  CurrentPoint: TPointF;
  I: Integer;
  PreviousPoint: TPointF;
begin
  Result := MaxSingle;
  PreviousPoint := MapRakuEllipsePoint(ArcLayer.Bounds,
    ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees);
  for I := 1 to ARC_HIT_TEST_SEGMENTS do
  begin
    CurrentPoint := MapRakuEllipsePoint(ArcLayer.Bounds,
      ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees +
      ArcLayer.SweepAngleDegrees * I / ARC_HIT_TEST_SEGMENTS);
    Result := Min(Result, DistanceToSegment(PointValue, PreviousPoint,
      CurrentPoint));
    PreviousPoint := CurrentPoint;
  end;
end;

function EllipseLineDistanceToPoint(LineLayer: TMapRakuEllipseLineLayer;
  const PointValue: TPointF): Single;
var
  CurrentPoint: TPointF;
  I: Integer;
  PreviousPoint: TPointF;
begin
  Result := MaxSingle;
  PreviousPoint := MapRakuEllipsePoint(LineLayer.Bounds,
    LineLayer.RotationDegrees, 0);
  for I := 1 to ARC_HIT_TEST_SEGMENTS * 2 do
  begin
    CurrentPoint := MapRakuEllipsePoint(LineLayer.Bounds,
      LineLayer.RotationDegrees, 360 * I / (ARC_HIT_TEST_SEGMENTS * 2));
    Result := Min(Result, DistanceToSegment(PointValue, PreviousPoint,
      CurrentPoint));
    PreviousPoint := CurrentPoint;
  end;
end;

function RoundedRectangleLineDistanceToPoint(
  LineLayer: TMapRakuRoundedRectangleLineLayer;
  const PointValue: TPointF): Single;
const
  ARC_SEGMENTS = 8;
var
  Angle: Single;
  Center: TPointF;
  Corner: Integer;
  CurrentPoint: TPointF;
  I: Integer;
  LocalPoint: TPointF;
  PreviousPoint: TPointF;
  Radii: TMapRakuCornerRadii;
  Radius: Single;
  StartAngle: Single;
begin
  Center := TPointF.Create((LineLayer.Bounds.Left + LineLayer.Bounds.Right) *
    0.5, (LineLayer.Bounds.Top + LineLayer.Bounds.Bottom) * 0.5);
  LocalPoint := RotatePointAround(PointValue, Center,
    -LineLayer.RotationDegrees);
  Radii := ClampMapRakuCornerRadii(LineLayer.Bounds,
    LineLayer.CornerRadii);
  Result := Min(
    DistanceToSegment(LocalPoint,
      TPointF.Create(LineLayer.Bounds.Left + Radii.TopLeft,
        LineLayer.Bounds.Top),
      TPointF.Create(LineLayer.Bounds.Right - Radii.TopRight,
        LineLayer.Bounds.Top)),
    DistanceToSegment(LocalPoint,
      TPointF.Create(LineLayer.Bounds.Right,
        LineLayer.Bounds.Top + Radii.TopRight),
      TPointF.Create(LineLayer.Bounds.Right,
        LineLayer.Bounds.Bottom - Radii.BottomRight)));
  Result := Min(Result, DistanceToSegment(LocalPoint,
    TPointF.Create(LineLayer.Bounds.Right - Radii.BottomRight,
      LineLayer.Bounds.Bottom),
    TPointF.Create(LineLayer.Bounds.Left + Radii.BottomLeft,
      LineLayer.Bounds.Bottom)));
  Result := Min(Result, DistanceToSegment(LocalPoint,
    TPointF.Create(LineLayer.Bounds.Left,
      LineLayer.Bounds.Bottom - Radii.BottomLeft),
    TPointF.Create(LineLayer.Bounds.Left,
      LineLayer.Bounds.Top + Radii.TopLeft)));
  for Corner := 0 to 3 do
  begin
    case Corner of
      0:
        begin
          Radius := Radii.TopRight;
          Center := TPointF.Create(LineLayer.Bounds.Right - Radius,
            LineLayer.Bounds.Top + Radius);
          StartAngle := -90;
        end;
      1:
        begin
          Radius := Radii.BottomRight;
          Center := TPointF.Create(LineLayer.Bounds.Right - Radius,
            LineLayer.Bounds.Bottom - Radius);
          StartAngle := 0;
        end;
      2:
        begin
          Radius := Radii.BottomLeft;
          Center := TPointF.Create(LineLayer.Bounds.Left + Radius,
            LineLayer.Bounds.Bottom - Radius);
          StartAngle := 90;
        end;
    else
      Radius := Radii.TopLeft;
      Center := TPointF.Create(LineLayer.Bounds.Left + Radius,
        LineLayer.Bounds.Top + Radius);
      StartAngle := 180;
    end;
    PreviousPoint := TPointF.Create(Center.X + Radius *
      Cos(DegToRad(StartAngle)), Center.Y + Radius * Sin(DegToRad(StartAngle)));
    for I := 1 to ARC_SEGMENTS do
    begin
      Angle := StartAngle + 90 * I / ARC_SEGMENTS;
      CurrentPoint := TPointF.Create(Center.X + Radius * Cos(DegToRad(Angle)),
        Center.Y + Radius * Sin(DegToRad(Angle)));
      Result := Min(Result, DistanceToSegment(LocalPoint, PreviousPoint,
        CurrentPoint));
      PreviousPoint := CurrentPoint;
    end;
  end;
end;

function RoundedRectangleValues(Layer: TVectArtLayer; out Bounds: TRectF;
  out Radii: TMapRakuCornerRadii; out RotationDegrees: Single): Boolean;
begin
  Result := Layer is TMapRakuRoundedRectangleLayer;
  if Result then
  begin
    Bounds := TMapRakuRoundedRectangleLayer(Layer).Bounds;
    Radii := TMapRakuRoundedRectangleLayer(Layer).CornerRadii;
    RotationDegrees :=
      TMapRakuRoundedRectangleLayer(Layer).RotationDegrees;
    Exit;
  end;
  Result := Layer is TMapRakuRoundedRectangleLineLayer;
  if Result then
  begin
    Bounds := TMapRakuRoundedRectangleLineLayer(Layer).Bounds;
    Radii := TMapRakuRoundedRectangleLineLayer(Layer).CornerRadii;
    RotationDegrees :=
      TMapRakuRoundedRectangleLineLayer(Layer).RotationDegrees;
  end;
end;

function ClockwiseAngleDelta(StartAngle, EndAngle: Single): Single;
begin
  Result := NormalizeMapRakuEllipseAngleDegrees(EndAngle - StartAngle);
end;

function ResizeAxisAlignedOuterBounds(const StartBounds: TRectF;
  const DragStart, Current: TPoint; Handle: TVectArtSelectionHandle;
  Zoom, RotationDegrees, MinimumSize: Single): TRectF;
var
  Cosine: Single;
  DesiredOuter: TRectF;
  Determinant: Single;
  DX: Single;
  DY: Single;
  NewCenter: TPointF;
  NewHeight: Single;
  NewWidth: Single;
  OriginalOuter: TRectF;
  OuterHeight: Single;
  OuterWidth: Single;
  Scale: Single;
  Sine: Single;
begin
  OriginalOuter := QuadBounds(RectangleCorners(StartBounds,
    RotationDegrees));
  DesiredOuter := OriginalOuter;
  DX := (Current.X - DragStart.X) / Zoom;
  DY := (Current.Y - DragStart.Y) / Zoom;
  if Handle in [vshTopLeft, vshLeft, vshBottomLeft] then
    DesiredOuter.Left := Min(DesiredOuter.Left + DX,
      DesiredOuter.Right - MinimumSize)
  else if Handle in [vshTopRight, vshRight, vshBottomRight] then
    DesiredOuter.Right := Max(DesiredOuter.Right + DX,
      DesiredOuter.Left + MinimumSize);
  if Handle in [vshTopLeft, vshTop, vshTopRight] then
    DesiredOuter.Top := Min(DesiredOuter.Top + DY,
      DesiredOuter.Bottom - MinimumSize)
  else if Handle in [vshBottomLeft, vshBottom, vshBottomRight] then
    DesiredOuter.Bottom := Max(DesiredOuter.Bottom + DY,
      DesiredOuter.Top + MinimumSize);

  Cosine := Abs(Cos(DegToRad(RotationDegrees)));
  Sine := Abs(Sin(DegToRad(RotationDegrees)));
  Determinant := Cosine * Cosine - Sine * Sine;
  if Abs(Determinant) > 0.05 then
  begin
    NewWidth := (Cosine * DesiredOuter.Width -
      Sine * DesiredOuter.Height) / Determinant;
    NewHeight := (Cosine * DesiredOuter.Height -
      Sine * DesiredOuter.Width) / Determinant;
  end
  else
  begin
    NewWidth := -1;
    NewHeight := -1;
  end;
  if (NewWidth < MinimumSize) or (NewHeight < MinimumSize) then
  begin
    // 45度付近や成立しない外接寸法では縦横比を保って破綻を避ける。
    Scale := Max(DesiredOuter.Width / Max(OriginalOuter.Width, 0.001),
      DesiredOuter.Height / Max(OriginalOuter.Height, 0.001));
    NewWidth := StartBounds.Width * Scale;
    NewHeight := StartBounds.Height * Scale;
  end;
  NewWidth := Max(NewWidth, MinimumSize);
  NewHeight := Max(NewHeight, MinimumSize);
  OuterWidth := Cosine * NewWidth + Sine * NewHeight;
  OuterHeight := Sine * NewWidth + Cosine * NewHeight;
  NewCenter := TPointF.Create(
    (DesiredOuter.Left + DesiredOuter.Right) * 0.5,
    (DesiredOuter.Top + DesiredOuter.Bottom) * 0.5);
  if Handle in [vshTopLeft, vshLeft, vshBottomLeft] then
    NewCenter.X := DesiredOuter.Right - OuterWidth * 0.5
  else if Handle in [vshTopRight, vshRight, vshBottomRight] then
    NewCenter.X := DesiredOuter.Left + OuterWidth * 0.5;
  if Handle in [vshTopLeft, vshTop, vshTopRight] then
    NewCenter.Y := DesiredOuter.Bottom - OuterHeight * 0.5
  else if Handle in [vshBottomLeft, vshBottom, vshBottomRight] then
    NewCenter.Y := DesiredOuter.Top + OuterHeight * 0.5;
  Result := TRectF.Create(NewCenter.X - NewWidth * 0.5,
    NewCenter.Y - NewHeight * 0.5, NewCenter.X + NewWidth * 0.5,
    NewCenter.Y + NewHeight * 0.5);
end;

function ResizeUniformBounds(const StartBounds: TRectF;
  const StartLogical, CurrentLogical: TPointF;
  Handle: TVectArtSelectionHandle; RotationDegrees,
  MinimumSize: Single): TRectF;
var
  Anchor: TPointF;
  Center: TPointF;
  DesiredHandle: TPointF;
  HandlePoint: TPointF;
  LocalCurrent: TPointF;
  LocalStart: TPointF;
  MinimumScale: Single;
  NewAnchor: TPointF;
  NewCenter: TPointF;
  Scale: Single;
  StartAnchor: TPointF;
  VectorX: Single;
  VectorY: Single;
begin
  Result := StartBounds;
  Center := StartBounds.CenterPoint;
  case Handle of
    vshTopLeft:
    begin
      HandlePoint := StartBounds.TopLeft;
      Anchor := StartBounds.BottomRight;
    end;
    vshTop:
    begin
      HandlePoint := TPointF.Create(Center.X, StartBounds.Top);
      Anchor := TPointF.Create(Center.X, StartBounds.Bottom);
    end;
    vshTopRight:
    begin
      HandlePoint := TPointF.Create(StartBounds.Right, StartBounds.Top);
      Anchor := TPointF.Create(StartBounds.Left, StartBounds.Bottom);
    end;
    vshRight:
    begin
      HandlePoint := TPointF.Create(StartBounds.Right, Center.Y);
      Anchor := TPointF.Create(StartBounds.Left, Center.Y);
    end;
    vshBottomRight:
    begin
      HandlePoint := StartBounds.BottomRight;
      Anchor := StartBounds.TopLeft;
    end;
    vshBottom:
    begin
      HandlePoint := TPointF.Create(Center.X, StartBounds.Bottom);
      Anchor := TPointF.Create(Center.X, StartBounds.Top);
    end;
    vshBottomLeft:
    begin
      HandlePoint := TPointF.Create(StartBounds.Left, StartBounds.Bottom);
      Anchor := TPointF.Create(StartBounds.Right, StartBounds.Top);
    end;
    vshLeft:
    begin
      HandlePoint := TPointF.Create(StartBounds.Left, Center.Y);
      Anchor := TPointF.Create(StartBounds.Right, Center.Y);
    end;
  else
    Exit;
  end;
  LocalStart := RotatePointAround(StartLogical, Center, -RotationDegrees);
  LocalCurrent := RotatePointAround(CurrentLogical, Center,
    -RotationDegrees);
  DesiredHandle := TPointF.Create(
    HandlePoint.X + LocalCurrent.X - LocalStart.X,
    HandlePoint.Y + LocalCurrent.Y - LocalStart.Y);
  VectorX := HandlePoint.X - Anchor.X;
  VectorY := HandlePoint.Y - Anchor.Y;
  Scale := ((DesiredHandle.X - Anchor.X) * VectorX +
    (DesiredHandle.Y - Anchor.Y) * VectorY) /
    Max(VectorX * VectorX + VectorY * VectorY, 0.001);
  MinimumScale := Max(MinimumSize / Max(StartBounds.Width, 0.001),
    MinimumSize / Max(StartBounds.Height, 0.001));
  Scale := Max(Scale, MinimumScale);
  Result := TRectF.Create(
    Anchor.X + (StartBounds.Left - Anchor.X) * Scale,
    Anchor.Y + (StartBounds.Top - Anchor.Y) * Scale,
    Anchor.X + (StartBounds.Right - Anchor.X) * Scale,
    Anchor.Y + (StartBounds.Bottom - Anchor.Y) * Scale);
  if not SameValue(RotationDegrees, 0.0) then
  begin
    NewCenter := Result.CenterPoint;
    StartAnchor := RotatePointAround(Anchor, Center, RotationDegrees);
    NewAnchor := RotatePointAround(Anchor, NewCenter, RotationDegrees);
    Result.Offset(StartAnchor.X - NewAnchor.X,
      StartAnchor.Y - NewAnchor.Y);
  end;
end;

function ResizeRotatedBounds(const StartBounds: TRectF;
  const StartLogical, CurrentLogical: TPointF;
  Handle: TVectArtSelectionHandle; RotationDegrees,
  MinimumSize: Single): TRectF;
var
  Anchor: TPointF;
  Center: TPointF;
  DX: Single;
  DY: Single;
  LocalCurrent: TPointF;
  LocalStart: TPointF;
  NewAnchor: TPointF;
  NewCenter: TPointF;
  StartAnchor: TPointF;
begin
  Result := StartBounds;
  Center := StartBounds.CenterPoint;
  LocalStart := RotatePointAround(StartLogical, Center, -RotationDegrees);
  LocalCurrent := RotatePointAround(CurrentLogical, Center,
    -RotationDegrees);
  DX := LocalCurrent.X - LocalStart.X;
  DY := LocalCurrent.Y - LocalStart.Y;
  if Handle in [vshTopLeft, vshLeft, vshBottomLeft] then
    Result.Left := Min(StartBounds.Left + DX,
      StartBounds.Right - MinimumSize);
  if Handle in [vshTopRight, vshRight, vshBottomRight] then
    Result.Right := Max(StartBounds.Right + DX,
      StartBounds.Left + MinimumSize);
  if Handle in [vshTopLeft, vshTop, vshTopRight] then
    Result.Top := Min(StartBounds.Top + DY,
      StartBounds.Bottom - MinimumSize);
  if Handle in [vshBottomLeft, vshBottom, vshBottomRight] then
    Result.Bottom := Max(StartBounds.Bottom + DY,
      StartBounds.Top + MinimumSize);
  if not SameValue(RotationDegrees, 0.0) then
  begin
    Anchor := Center;
    if Handle in [vshTopLeft, vshLeft, vshBottomLeft] then
      Anchor.X := StartBounds.Right
    else if Handle in [vshTopRight, vshRight, vshBottomRight] then
      Anchor.X := StartBounds.Left;
    if Handle in [vshTopLeft, vshTop, vshTopRight] then
      Anchor.Y := StartBounds.Bottom
    else if Handle in [vshBottomLeft, vshBottom, vshBottomRight] then
      Anchor.Y := StartBounds.Top;
    NewCenter := Result.CenterPoint;
    StartAnchor := RotatePointAround(Anchor, Center, RotationDegrees);
    NewAnchor := RotatePointAround(Anchor, NewCenter, RotationDegrees);
    Result.Offset(StartAnchor.X - NewAnchor.X,
      StartAnchor.Y - NewAnchor.Y);
  end;
end;

end.
