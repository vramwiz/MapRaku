// 任意レイヤーとグループ子孫の外接範囲取得、平行移動を再帰的に提供する。
// 描画属性が使うローカル範囲と回転も、描画・ガイド間で共通化する。
unit MapRakuLayerGeometry;

interface

uses
  System.Types, MapRakuDocument, MapRakuProjectiveTransform;

// 射影変換前の外接範囲を返す。
function TryGetMapRakuLayerSourceBounds(Layer: TVectArtLayer; out Bounds: TRectF): Boolean;
// 選択枠に使う変形後の四隅を返す。
function TryGetMapRakuLayerQuad(Layer: TVectArtLayer; out Quad: TMapRakuQuad): Boolean;

// 表示内容を含むDocument座標の軸平行外接範囲を返す。
function TryGetMapRakuLayerBounds(Layer: TVectArtLayer;
  out Bounds: TRectF): Boolean;
// グラデーションなど、レイヤー固有のローカル座標と回転を使う描画属性の基準を返す。
function TryGetMapRakuLayerPaintGeometry(Layer: TVectArtLayer;
  out Bounds: TRectF; out RotationDegrees: Single): Boolean;
// 正規化された描画属性座標を、レイヤー回転後のDocument座標へ変換する。
function MapRakuLayerPaintPoint(const Bounds: TRectF;
  RotationDegrees: Single; const NormalizedPoint: TPointF): TPointF;
// 指定中心を基準にレイヤーの実座標と回転属性を更新する。
procedure RotateMapRakuLayer(Layer: TVectArtLayer;
  const Center: TPointF; Degrees: Single);
// SourceBounds内の配置比率を維持してTargetBoundsへ拡縮する。
procedure ScaleMapRakuLayer(Layer: TVectArtLayer;
  const SourceBounds, TargetBounds: TRectF);
// レイヤーとグループ子孫をDocument座標上で平行移動する。
procedure TranslateMapRakuLayer(Layer: TVectArtLayer; DX, DY: Single);

implementation

uses
  System.Math, MapRakuEllipseGeometry, MapRakuGeometry,
  MapRakuPathOperations, MapRakuShapeOperations,
  MapRakuTextPathGeometry;

function MapRakuImagePointsBounds(
  const Points: TVectArtImagePoints): TRectF;
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

function ScaleLayerPoint(const Point: TPointF;
  const SourceBounds, TargetBounds: TRectF): TPointF;
begin
  Result := TPointF.Create(
    TargetBounds.Left + (Point.X - SourceBounds.Left) /
      Max(SourceBounds.Width, 0.0001) * TargetBounds.Width,
    TargetBounds.Top + (Point.Y - SourceBounds.Top) /
      Max(SourceBounds.Height, 0.0001) * TargetBounds.Height);
end;

function TryGetMapRakuLayerSourceBounds(Layer: TVectArtLayer;
  out Bounds: TRectF): Boolean;
var
  ArcLayer: TMapRakuArcLayer;
  ChildBounds: TRectF;
  GroupLayer: TMapRakuGroupLayer;
  I: Integer;
  RectangleLayer: TVectArtRectangleLayer;
  RectangleLine: TMapRakuRectangleLineLayer;
begin
  Result := False;
  Bounds := TRectF.Empty;
  if Layer = nil then
    Exit;
  if Layer is TMapRakuGroupLayer then
  begin
    GroupLayer := TMapRakuGroupLayer(Layer);
    for I := 0 to GroupLayer.ChildCount - 1 do
      if GroupLayer[I].Visible and
        TryGetMapRakuLayerBounds(GroupLayer[I], ChildBounds) then
      begin
        if not Result then
          Bounds := ChildBounds
        else
        begin
          Bounds.Left := Min(Bounds.Left, ChildBounds.Left);
          Bounds.Top := Min(Bounds.Top, ChildBounds.Top);
          Bounds.Right := Max(Bounds.Right, ChildBounds.Right);
          Bounds.Bottom := Max(Bounds.Bottom, ChildBounds.Bottom);
        end;
        Result := True;
      end;
    Exit;
  end;
  if Layer is TMapRakuTextPathLayer then
  begin
    Result := TryGetMapRakuTextPathBounds(
      TMapRakuTextPathLayer(Layer), Bounds);
    Exit;
  end
  else if Layer is TVectArtImageLayer then
    Bounds := MapRakuImagePointsBounds(TVectArtImageLayer(Layer).Points)
  else if Layer is TVectArtPathLayer then
  begin
    Bounds := MapRakuPathVerticesBounds(TVectArtPathLayer(Layer).Vertices);
    if TVectArtPathLayer(Layer).MapElement <> '' then
      Bounds.Inflate(TVectArtPathLayer(Layer).StrokeWidth*0.5+1, TVectArtPathLayer(Layer).StrokeWidth*0.5+1);
  end
  else if Layer is TMapRakuShapeLayer then
    Bounds := MapRakuShapeContoursBounds(
      TMapRakuShapeLayer(Layer).Contours)
  else if Layer is TMapRakuRectangleLineLayer then
  begin
    RectangleLine := TMapRakuRectangleLineLayer(Layer);
    Bounds := QuadBounds(RectangleCorners(RectangleLine.Bounds,
      RectangleLine.RotationDegrees));
  end
  else if Layer is TMapRakuArcLayer then
  begin
    ArcLayer := TMapRakuArcLayer(Layer);
    Bounds := MapRakuEllipseBounds(ArcLayer.Bounds,
      ArcLayer.RotationDegrees);
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    RectangleLayer := TVectArtRectangleLayer(Layer);
    Bounds := QuadBounds(RectangleCorners(RectangleLayer.Bounds,
      RectangleLayer.RotationDegrees));
  end
  else
    Exit;
  Result := True;
end;

function TryGetMapRakuLayerQuad(Layer: TVectArtLayer; out Quad: TMapRakuQuad): Boolean;
var Bounds: TRectF; Corners: TVectArtQuad; I: Integer;
begin
  Result := TryGetMapRakuLayerSourceBounds(Layer, Bounds);
  if not Result then Exit;
  Quad := MapRakuRectQuad(Bounds);
  if Layer is TVectArtRectangleLayer then
    Corners := RectangleCorners(TVectArtRectangleLayer(Layer).Bounds,
      TVectArtRectangleLayer(Layer).RotationDegrees)
  else if Layer is TMapRakuRectangleLineLayer then
    Corners := RectangleCorners(TMapRakuRectangleLineLayer(Layer).Bounds,
      TMapRakuRectangleLineLayer(Layer).RotationDegrees)
  else if Layer is TMapRakuArcLayer then
    Corners := RectangleCorners(TMapRakuArcLayer(Layer).Bounds,
      TMapRakuArcLayer(Layer).RotationDegrees)
  else
    for I := 0 to 3 do Corners[I] := Quad[I];
  if Layer is TVectArtImageLayer then
    for I := 0 to 3 do Corners[I] := TVectArtImageLayer(Layer).Points[I];
  for I := 0 to 3 do Quad[I] := Layer.Transform.Map(Corners[I]);
end;

function TryGetMapRakuLayerBounds(Layer: TVectArtLayer; out Bounds: TRectF): Boolean;
var Quad: TMapRakuQuad;
begin
  if (Layer <> nil) and not Layer.Transform.IsIdentity then
  begin
    Result := TryGetMapRakuLayerQuad(Layer, Quad);
    if Result then Bounds := MapRakuQuadBounds(Quad) else Bounds := TRectF.Empty;
  end
  else Result := TryGetMapRakuLayerSourceBounds(Layer, Bounds);
end;

function TryGetMapRakuLayerPaintGeometry(Layer: TVectArtLayer;
  out Bounds: TRectF; out RotationDegrees: Single): Boolean;
begin
  RotationDegrees := 0.0;
  if Layer is TMapRakuTextPathLayer then
    Exit(TryGetMapRakuTextPathBounds(
      TMapRakuTextPathLayer(Layer), Bounds));
  if Layer is TMapRakuRectangleLineLayer then
  begin
    Bounds := TMapRakuRectangleLineLayer(Layer).Bounds;
    RotationDegrees :=
      TMapRakuRectangleLineLayer(Layer).RotationDegrees;
    Exit(True);
  end;
  if Layer is TMapRakuArcLayer then
  begin
    Bounds := TMapRakuArcLayer(Layer).Bounds;
    RotationDegrees := TMapRakuArcLayer(Layer).RotationDegrees;
    Exit(True);
  end;
  if Layer is TVectArtRectangleLayer then
  begin
    Bounds := TVectArtRectangleLayer(Layer).Bounds;
    RotationDegrees := TVectArtRectangleLayer(Layer).RotationDegrees;
    Exit(True);
  end;
  Result := TryGetMapRakuLayerBounds(Layer, Bounds);
  // 水平・垂直のPathにも編集可能な正規化座標を与える。
  if Result then
  begin
    if Abs(Bounds.Width) < 0.0001 then
    begin
      Bounds.Left := Bounds.Left - 0.5;
      Bounds.Right := Bounds.Right + 0.5;
    end;
    if Abs(Bounds.Height) < 0.0001 then
    begin
      Bounds.Top := Bounds.Top - 0.5;
      Bounds.Bottom := Bounds.Bottom + 0.5;
    end;
  end;
end;

function MapRakuLayerPaintPoint(const Bounds: TRectF;
  RotationDegrees: Single; const NormalizedPoint: TPointF): TPointF;
begin
  Result := TPointF.Create(
    Bounds.Left + Bounds.Width * NormalizedPoint.X,
    Bounds.Top + Bounds.Height * NormalizedPoint.Y);
  if not SameValue(RotationDegrees, 0.0) then
    Result := RotatePointAround(Result, Bounds.CenterPoint, RotationDegrees);
end;

procedure RotateMapRakuLayer(Layer: TVectArtLayer;
  const Center: TPointF; Degrees: Single);
var
  Transform: TMapRakuTransform;
  Bounds: TRectF;
  BoundsCenter: TPointF;
  Contours: TArray<TMapRakuContour>;
  GroupLayer: TMapRakuGroupLayer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  NewCenter: TPointF;
  Points: TVectArtImagePoints;
  TextPathLayer: TMapRakuTextPathLayer;
  Vertices: TArray<TMapRakuVertex>;
begin
  if not Layer.Transform.IsIdentity then
  begin
    Transform := TMapRakuTransform.Identity;
    Transform.Values[0] := Cos(DegToRad(Degrees));
    Transform.Values[1] := -Sin(DegToRad(Degrees));
    Transform.Values[3] := -Transform.Values[1];
    Transform.Values[4] := Transform.Values[0];
    Transform.Values[2] := Center.X - Transform.Values[0] * Center.X - Transform.Values[1] * Center.Y;
    Transform.Values[5] := Center.Y - Transform.Values[3] * Center.X - Transform.Values[4] * Center.Y;
    Layer.Transform := Layer.Transform.ThenApply(Transform);
    Exit;
  end;
  if Layer is TMapRakuGroupLayer then
  begin
    GroupLayer := TMapRakuGroupLayer(Layer);
    for I := 0 to GroupLayer.ChildCount - 1 do
      RotateMapRakuLayer(GroupLayer[I], Center, Degrees);
  end
  else if Layer is TMapRakuTextPathLayer then
  begin
    TextPathLayer := TMapRakuTextPathLayer(Layer);
    Vertices := RotateMapRakuPathVertices(
      TextPathLayer.EditablePathVertices, Center, Degrees);
    TextPathLayer.AssignEditablePathVertices(Vertices);
    TextPathLayer.RotationDegrees := TextPathLayer.RotationDegrees + Degrees;
  end
  else if Layer is TVectArtImageLayer then
  begin
    ImageLayer := TVectArtImageLayer(Layer);
    Points := ImageLayer.Points;
    for I := 0 to High(Points) do
      Points[I] := RotatePointAround(Points[I], Center, Degrees);
    ImageLayer.Points := Points;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Vertices := RotateMapRakuPathVertices(
      TVectArtPathLayer(Layer).Vertices, Center, Degrees);
    TVectArtPathLayer(Layer).Vertices := Vertices;
  end
  else if Layer is TMapRakuShapeLayer then
  begin
    Contours := RotateMapRakuShapeContours(
      TMapRakuShapeLayer(Layer).Contours, Center, Degrees);
    TMapRakuShapeLayer(Layer).Contours := Contours;
  end
  else if Layer is TMapRakuRectangleLineLayer then
  begin
    Bounds := TMapRakuRectangleLineLayer(Layer).Bounds;
    BoundsCenter := TPointF.Create(Bounds.CenterPoint.X, Bounds.CenterPoint.Y);
    NewCenter := RotatePointAround(BoundsCenter, Center, Degrees);
    Bounds.Offset(NewCenter.X - BoundsCenter.X, NewCenter.Y - BoundsCenter.Y);
    TMapRakuRectangleLineLayer(Layer).Bounds := Bounds;
    TMapRakuRectangleLineLayer(Layer).RotationDegrees :=
      TMapRakuRectangleLineLayer(Layer).RotationDegrees + Degrees;
  end
  else if Layer is TMapRakuArcLayer then
  begin
    Bounds := TMapRakuArcLayer(Layer).Bounds;
    BoundsCenter := TPointF.Create(Bounds.CenterPoint.X, Bounds.CenterPoint.Y);
    NewCenter := RotatePointAround(BoundsCenter, Center, Degrees);
    Bounds.Offset(NewCenter.X - BoundsCenter.X, NewCenter.Y - BoundsCenter.Y);
    TMapRakuArcLayer(Layer).Bounds := Bounds;
    TMapRakuArcLayer(Layer).RotationDegrees :=
      TMapRakuArcLayer(Layer).RotationDegrees + Degrees;
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    Bounds := TVectArtRectangleLayer(Layer).Bounds;
    BoundsCenter := TPointF.Create(Bounds.CenterPoint.X, Bounds.CenterPoint.Y);
    NewCenter := RotatePointAround(BoundsCenter, Center, Degrees);
    Bounds.Offset(NewCenter.X - BoundsCenter.X, NewCenter.Y - BoundsCenter.Y);
    TVectArtRectangleLayer(Layer).Bounds := Bounds;
    TVectArtRectangleLayer(Layer).RotationDegrees :=
      TVectArtRectangleLayer(Layer).RotationDegrees + Degrees;
  end;
end;

procedure ScaleMapRakuLayer(Layer: TVectArtLayer;
  const SourceBounds, TargetBounds: TRectF);
var
  Transform: TMapRakuTransform;
  Bounds: TRectF;
  Contours: TArray<TMapRakuContour>;
  GroupLayer: TMapRakuGroupLayer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Points: TVectArtImagePoints;
  Radii: TMapRakuCornerRadii;
  ScaleValue: Single;
  TextPathLayer: TMapRakuTextPathLayer;
  Vertices: TArray<TMapRakuVertex>;
begin
  if not Layer.Transform.IsIdentity then
  begin
    if not TryMapRakuQuadTransform(MapRakuRectQuad(SourceBounds),
      MapRakuRectQuad(TargetBounds), Transform) then Exit;
    Layer.Transform := Layer.Transform.ThenApply(Transform);
    Exit;
  end;
  if (SourceBounds.Width <= 0.0001) or
    (SourceBounds.Height <= 0.0001) then
    Exit;
  if Layer is TMapRakuGroupLayer then
  begin
    GroupLayer := TMapRakuGroupLayer(Layer);
    for I := 0 to GroupLayer.ChildCount - 1 do
      ScaleMapRakuLayer(GroupLayer[I], SourceBounds, TargetBounds);
  end
  else if Layer is TMapRakuTextPathLayer then
  begin
    TextPathLayer := TMapRakuTextPathLayer(Layer);
    Vertices := ScaleMapRakuPathVertices(
      TextPathLayer.EditablePathVertices, SourceBounds, TargetBounds);
    TextPathLayer.AssignEditablePathVertices(Vertices);
    // 非等方のグループ変形でも逆変換時に元の文字サイズへ正確に戻せる倍率を使う。
    ScaleValue := Sqrt(Abs(TargetBounds.Width / SourceBounds.Width) *
      Abs(TargetBounds.Height / SourceBounds.Height));
    TextPathLayer.FontSize := Max(TextPathLayer.FontSize * ScaleValue, 1.0);
  end
  else if Layer is TVectArtImageLayer then
  begin
    ImageLayer := TVectArtImageLayer(Layer);
    Points := ImageLayer.Points;
    for I := 0 to High(Points) do
      Points[I] := ScaleLayerPoint(Points[I], SourceBounds, TargetBounds);
    ImageLayer.Points := Points;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Vertices := ScaleMapRakuPathVertices(
      TVectArtPathLayer(Layer).Vertices, SourceBounds, TargetBounds);
    TVectArtPathLayer(Layer).Vertices := Vertices;
  end
  else if Layer is TMapRakuShapeLayer then
  begin
    Contours := ScaleMapRakuShapeContours(
      TMapRakuShapeLayer(Layer).Contours, SourceBounds, TargetBounds);
    TMapRakuShapeLayer(Layer).Contours := Contours;
  end
  else if Layer is TMapRakuRectangleLineLayer then
  begin
    Bounds := TMapRakuRectangleLineLayer(Layer).Bounds;
    Bounds := TRectF.Create(ScaleLayerPoint(Bounds.TopLeft, SourceBounds,
      TargetBounds), ScaleLayerPoint(Bounds.BottomRight, SourceBounds,
      TargetBounds));
    TMapRakuRectangleLineLayer(Layer).Bounds := Bounds;
    if Layer is TMapRakuRoundedRectangleLineLayer then
    begin
      ScaleValue := Min(Abs(TargetBounds.Width / SourceBounds.Width),
        Abs(TargetBounds.Height / SourceBounds.Height));
      Radii := TMapRakuRoundedRectangleLineLayer(Layer).CornerRadii;
      Radii.TopLeft := Radii.TopLeft * ScaleValue;
      Radii.TopRight := Radii.TopRight * ScaleValue;
      Radii.BottomRight := Radii.BottomRight * ScaleValue;
      Radii.BottomLeft := Radii.BottomLeft * ScaleValue;
      TMapRakuRoundedRectangleLineLayer(Layer).CornerRadii := Radii;
    end;
  end
  else if Layer is TMapRakuArcLayer then
  begin
    Bounds := TMapRakuArcLayer(Layer).Bounds;
    Bounds := TRectF.Create(ScaleLayerPoint(Bounds.TopLeft, SourceBounds,
      TargetBounds), ScaleLayerPoint(Bounds.BottomRight, SourceBounds,
      TargetBounds));
    TMapRakuArcLayer(Layer).Bounds := Bounds;
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    Bounds := TVectArtRectangleLayer(Layer).Bounds;
    Bounds := TRectF.Create(ScaleLayerPoint(Bounds.TopLeft, SourceBounds,
      TargetBounds), ScaleLayerPoint(Bounds.BottomRight, SourceBounds,
      TargetBounds));
    TVectArtRectangleLayer(Layer).Bounds := Bounds;
    if Layer is TMapRakuRoundedRectangleLayer then
    begin
      ScaleValue := Min(Abs(TargetBounds.Width / SourceBounds.Width),
        Abs(TargetBounds.Height / SourceBounds.Height));
      Radii := TMapRakuRoundedRectangleLayer(Layer).CornerRadii;
      Radii.TopLeft := Radii.TopLeft * ScaleValue;
      Radii.TopRight := Radii.TopRight * ScaleValue;
      Radii.BottomRight := Radii.BottomRight * ScaleValue;
      Radii.BottomLeft := Radii.BottomLeft * ScaleValue;
      TMapRakuRoundedRectangleLayer(Layer).CornerRadii := Radii;
    end;
  end;
end;

procedure TranslateMapRakuLayer(Layer: TVectArtLayer; DX, DY: Single);
var
  Transform: TMapRakuTransform;
  Bounds: TRectF;
  Contours: TArray<TMapRakuContour>;
  GroupLayer: TMapRakuGroupLayer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Points: TVectArtImagePoints;
  TextPathLayer: TMapRakuTextPathLayer;
  Vertices: TArray<TMapRakuVertex>;
begin
  if not Layer.Transform.IsIdentity then
  begin
    Transform := TMapRakuTransform.Identity;
    Transform.Values[2] := DX;
    Transform.Values[5] := DY;
    Layer.Transform := Layer.Transform.ThenApply(Transform);
    Exit;
  end;
  if Layer is TMapRakuGroupLayer then
  begin
    GroupLayer := TMapRakuGroupLayer(Layer);
    for I := 0 to GroupLayer.ChildCount - 1 do
      TranslateMapRakuLayer(GroupLayer[I], DX, DY);
  end
  else if Layer is TMapRakuTextPathLayer then
  begin
    TextPathLayer := TMapRakuTextPathLayer(Layer);
    Vertices := TranslateMapRakuPathVertices(
      TextPathLayer.EditablePathVertices, DX, DY);
    TextPathLayer.AssignEditablePathVertices(Vertices);
  end
  else if Layer is TVectArtImageLayer then
  begin
    ImageLayer := TVectArtImageLayer(Layer);
    Points := ImageLayer.Points;
    for I := 0 to High(Points) do
      Points[I].Offset(DX, DY);
    ImageLayer.Points := Points;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Vertices := TranslateMapRakuPathVertices(
      TVectArtPathLayer(Layer).Vertices, DX, DY);
    TVectArtPathLayer(Layer).Vertices := Vertices;
  end
  else if Layer is TMapRakuShapeLayer then
  begin
    Contours := TranslateMapRakuShapeContours(
      TMapRakuShapeLayer(Layer).Contours, DX, DY);
    TMapRakuShapeLayer(Layer).Contours := Contours;
  end
  else if Layer is TMapRakuRectangleLineLayer then
  begin
    Bounds := TMapRakuRectangleLineLayer(Layer).Bounds;
    Bounds.Offset(DX, DY);
    TMapRakuRectangleLineLayer(Layer).Bounds := Bounds;
  end
  else if Layer is TMapRakuArcLayer then
  begin
    Bounds := TMapRakuArcLayer(Layer).Bounds;
    Bounds.Offset(DX, DY);
    TMapRakuArcLayer(Layer).Bounds := Bounds;
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    Bounds := TVectArtRectangleLayer(Layer).Bounds;
    Bounds.Offset(DX, DY);
    TVectArtRectangleLayer(Layer).Bounds := Bounds;
  end;
end;

end.
