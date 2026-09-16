// 中心線と幅プロファイルから、描画と分解に共用する閉じた輪郭を生成する。
unit MapRakuVariableWidthRenderer;

interface

uses
  System.Skia, MapRakuDocument;

// 幅点はBaseWidthの半幅に対する左右倍率。入力を変更せず、生成不能時はnilを返す。
function BuildMapRakuVariableWidthPath(const CenterPath: ISkPath;
  const WidthPoints: TArray<TMapRakuStrokeWidthPoint>;
  BaseWidth: Single; LineCap: TVectArtLineCap;
  const Vertices: TArray<TMapRakuVertex>): ISkPath;

implementation

uses
  System.Math, System.Types, MapRakuStrokeSampling;

const
  MAX_SAMPLE_COUNT = 2049;
  CUBIC_CIRCLE_KAPPA = 0.55228475;
  SAMPLE_DISTANCE = 2.0;
  OUTLINE_SIMPLIFY_TOLERANCE = 0.25;

function TryLineIntersection(const Point1, Direction1, Point2,
  Direction2: TPointF; out Intersection: TPointF;
  out Parameter1, Parameter2: Single): Boolean;
var
  Cross: Single;
  DX: Single;
  DY: Single;
begin
  Cross := Direction1.X * Direction2.Y -
    Direction1.Y * Direction2.X;
  Result := Abs(Cross) > 0.0001;
  if not Result then
    Exit;
  DX := Point2.X - Point1.X;
  DY := Point2.Y - Point1.Y;
  Parameter1 := (DX * Direction2.Y - DY * Direction2.X) / Cross;
  Parameter2 := (DX * Direction1.Y - DY * Direction1.X) / Cross;
  Intersection := TPointF.Create(Point1.X + Direction1.X * Parameter1,
    Point1.Y + Direction1.Y * Parameter1);
end;

function NormalizedDirection(const Value, Fallback: TPointF): TPointF;
var
  ValueLength: Single;
begin
  ValueLength := Hypot(Value.X, Value.Y);
  if ValueLength <= 0.0001 then
    Exit(Fallback);
  Result := TPointF.Create(Value.X / ValueLength, Value.Y / ValueLength);
end;

procedure ApplyVertexJoins(const Vertices: TArray<TMapRakuVertex>;
  const SampleOffsets: TArray<Single>; const Centers: TArray<TPointF>;
  const LeftRadii, RightRadii: TArray<Single>;
  RoundJoins: Boolean; var LeftPoints, RightPoints: TArray<TPointF>);
const
  MITER_LIMIT = 4.0;
var
  Cumulative: Single;
  DirectionFromCenter: TPointF;
  I: Integer;
  IncomingNormal: TPointF;
  IncomingTangent: TPointF;
  Index: Integer;
  JoinDistance: Single;
  JoinPoint: TPointF;
  OutgoingNormal: TPointF;
  OutgoingTangent: TPointF;
  Parameter1: Single;
  Parameter2: Single;
  Radius: Single;
  SegmentLengths: TArray<Single>;
  SidePoint1: TPointF;
  SidePoint2: TPointF;
  TotalLength: Single;
  TurnCross: Single;
  VertexOffset: Single;

  procedure ApplySide(LeftSide: Boolean);
  var
    JoinIncomingParameter: Single;
    JoinOutgoingParameter: Single;
    K: Integer;
    Projection: Single;
  begin
    if LeftSide then
      Radius := LeftRadii[Index]
    else
      Radius := RightRadii[Index];
    if LeftSide then
    begin
      SidePoint1 := TPointF.Create(Vertices[I].Position.X +
        IncomingNormal.X * Radius, Vertices[I].Position.Y +
        IncomingNormal.Y * Radius);
      SidePoint2 := TPointF.Create(Vertices[I].Position.X +
        OutgoingNormal.X * Radius, Vertices[I].Position.Y +
        OutgoingNormal.Y * Radius);
    end
    else
    begin
      SidePoint1 := TPointF.Create(Vertices[I].Position.X -
        IncomingNormal.X * Radius, Vertices[I].Position.Y -
        IncomingNormal.Y * Radius);
      SidePoint2 := TPointF.Create(Vertices[I].Position.X -
        OutgoingNormal.X * Radius, Vertices[I].Position.Y -
        OutgoingNormal.Y * Radius);
    end;
    if not TryLineIntersection(SidePoint1, IncomingTangent, SidePoint2,
      OutgoingTangent, JoinPoint, Parameter1, Parameter2) then
      Exit;
    // ラウンド結合の外側ではマイターを残さない。中心まで引いた部分は
    // 後段で合成する円の内側に隠れ、外周には円弧だけが残る。
    if RoundJoins and (((TurnCross > 0) and not LeftSide) or
      ((TurnCross < 0) and LeftSide)) then
    begin
      JoinPoint := Vertices[I].Position;
      if LeftSide then
        LeftPoints[Index] := JoinPoint
      else
        RightPoints[Index] := JoinPoint;
      Exit;
    end;
    JoinDistance := Hypot(JoinPoint.X - Vertices[I].Position.X,
      JoinPoint.Y - Vertices[I].Position.Y);
    if JoinDistance > Max(Radius, 0.1) * MITER_LIMIT then
    begin
      DirectionFromCenter := NormalizedDirection(TPointF.Create(
        JoinPoint.X - Vertices[I].Position.X,
        JoinPoint.Y - Vertices[I].Position.Y), TPointF.Zero);
      JoinPoint := TPointF.Create(Vertices[I].Position.X +
        DirectionFromCenter.X * Max(Radius, 0.1) * MITER_LIMIT,
        Vertices[I].Position.Y +
        DirectionFromCenter.Y * Max(Radius, 0.1) * MITER_LIMIT);
    end;
    if LeftSide then
    begin
      LeftPoints[Index] := JoinPoint;
      JoinIncomingParameter := (JoinPoint.X - SidePoint1.X) *
        IncomingTangent.X + (JoinPoint.Y - SidePoint1.Y) *
        IncomingTangent.Y;
      if JoinIncomingParameter < 0 then
      begin
        K := Index - 1;
        while K >= 0 do
        begin
          Projection := (LeftPoints[K].X - SidePoint1.X) *
            IncomingTangent.X + (LeftPoints[K].Y - SidePoint1.Y) *
            IncomingTangent.Y;
          if Projection <= JoinIncomingParameter then
            Break;
          LeftPoints[K] := JoinPoint;
          Dec(K);
        end;
      end;
      JoinOutgoingParameter := (JoinPoint.X - SidePoint2.X) *
        OutgoingTangent.X + (JoinPoint.Y - SidePoint2.Y) *
        OutgoingTangent.Y;
      if JoinOutgoingParameter > 0 then
      begin
        K := Index + 1;
        while K <= High(LeftPoints) do
        begin
          Projection := (LeftPoints[K].X - SidePoint2.X) *
            OutgoingTangent.X + (LeftPoints[K].Y - SidePoint2.Y) *
            OutgoingTangent.Y;
          if Projection >= JoinOutgoingParameter then
            Break;
          LeftPoints[K] := JoinPoint;
          Inc(K);
        end;
      end;
    end
    else
    begin
      RightPoints[Index] := JoinPoint;
      JoinIncomingParameter := (JoinPoint.X - SidePoint1.X) *
        IncomingTangent.X + (JoinPoint.Y - SidePoint1.Y) *
        IncomingTangent.Y;
      if JoinIncomingParameter < 0 then
      begin
        K := Index - 1;
        while K >= 0 do
        begin
          Projection := (RightPoints[K].X - SidePoint1.X) *
            IncomingTangent.X + (RightPoints[K].Y - SidePoint1.Y) *
            IncomingTangent.Y;
          if Projection <= JoinIncomingParameter then
            Break;
          RightPoints[K] := JoinPoint;
          Dec(K);
        end;
      end;
      JoinOutgoingParameter := (JoinPoint.X - SidePoint2.X) *
        OutgoingTangent.X + (JoinPoint.Y - SidePoint2.Y) *
        OutgoingTangent.Y;
      if JoinOutgoingParameter > 0 then
      begin
        K := Index + 1;
        while K <= High(RightPoints) do
        begin
          Projection := (RightPoints[K].X - SidePoint2.X) *
            OutgoingTangent.X + (RightPoints[K].Y - SidePoint2.Y) *
            OutgoingTangent.Y;
          if Projection >= JoinOutgoingParameter then
            Break;
          RightPoints[K] := JoinPoint;
          Inc(K);
        end;
      end;
    end;
  end;

begin
  if Length(Vertices) < 3 then
    Exit;
  SetLength(SegmentLengths, Length(Vertices) - 1);
  TotalLength := 0;
  for I := 0 to High(SegmentLengths) do
  begin
    SegmentLengths[I] := MapRakuPathSegmentLength(Vertices[I], Vertices[I + 1]);
    TotalLength := TotalLength + SegmentLengths[I];
  end;
  if TotalLength <= 0.0001 then
    Exit;
  Cumulative := 0;
  for I := 1 to High(Vertices) - 1 do
  begin
    Cumulative := Cumulative + SegmentLengths[I - 1];
    VertexOffset := Cumulative / TotalLength;
    Index := 0;
    while (Index < High(SampleOffsets)) and
      not SameValue(SampleOffsets[Index], VertexOffset, 0.000001) do
      Inc(Index);
    if not SameValue(SampleOffsets[Index], VertexOffset, 0.000001) then
      Continue;
    if Vertices[I - 1].OutgoingSegment = slskCubicBezier then
      IncomingTangent := NormalizedDirection(TPointF.Create(
        -Vertices[I].IncomingControl.X, -Vertices[I].IncomingControl.Y),
        TPointF.Create(Vertices[I].Position.X - Vertices[I - 1].Position.X,
          Vertices[I].Position.Y - Vertices[I - 1].Position.Y))
    else
      IncomingTangent := NormalizedDirection(TPointF.Create(
        Vertices[I].Position.X - Vertices[I - 1].Position.X,
        Vertices[I].Position.Y - Vertices[I - 1].Position.Y),
        TPointF.Create(1, 0));
    if Vertices[I].OutgoingSegment = slskCubicBezier then
      OutgoingTangent := NormalizedDirection(Vertices[I].OutgoingControl,
        TPointF.Create(Vertices[I + 1].Position.X - Vertices[I].Position.X,
          Vertices[I + 1].Position.Y - Vertices[I].Position.Y))
    else
      OutgoingTangent := NormalizedDirection(TPointF.Create(
        Vertices[I + 1].Position.X - Vertices[I].Position.X,
        Vertices[I + 1].Position.Y - Vertices[I].Position.Y),
        TPointF.Create(1, 0));
    IncomingNormal := TPointF.Create(-IncomingTangent.Y, IncomingTangent.X);
    OutgoingNormal := TPointF.Create(-OutgoingTangent.Y, OutgoingTangent.X);
    TurnCross := IncomingTangent.X * OutgoingTangent.Y -
      IncomingTangent.Y * OutgoingTangent.X;
    ApplySide(True);
    ApplySide(False);
  end;
end;

function AddRoundVertexJoins(const OutlinePath: ISkPath;
  const Vertices: TArray<TMapRakuVertex>;
  const SampleOffsets: TArray<Single>;
  const LeftRadii, RightRadii: TArray<Single>): ISkPath;
var
  CircleBuilder: ISkPathBuilder;
  CirclePath: ISkPath;
  Cumulative: Single;
  I: Integer;
  Index: Integer;
  Radius: Single;
  SegmentLengths: TArray<Single>;
  TotalLength: Single;
  VertexOffset: Single;
begin
  Result := OutlinePath;
  if (Result = nil) or (Length(Vertices) < 3) then
    Exit;
  SetLength(SegmentLengths, Length(Vertices) - 1);
  TotalLength := 0;
  for I := 0 to High(SegmentLengths) do
  begin
    SegmentLengths[I] := MapRakuPathSegmentLength(Vertices[I], Vertices[I + 1]);
    TotalLength := TotalLength + SegmentLengths[I];
  end;
  if TotalLength <= 0.0001 then
    Exit;
  Cumulative := 0;
  for I := 1 to High(Vertices) - 1 do
  begin
    Cumulative := Cumulative + SegmentLengths[I - 1];
    VertexOffset := Cumulative / TotalLength;
    Index := 0;
    while (Index < High(SampleOffsets)) and
      not SameValue(SampleOffsets[Index], VertexOffset, 0.000001) do
      Inc(Index);
    if not SameValue(SampleOffsets[Index], VertexOffset, 0.000001) then
      Continue;
    Radius := Max(LeftRadii[Index], RightRadii[Index]);
    if Radius <= 0.0001 then
      Continue;
    CircleBuilder := TSkPathBuilder.Create;
    CircleBuilder.AddCircle(Vertices[I].Position, Radius);
    CirclePath := CircleBuilder.Detach;
    Result := Result.Op(CirclePath, TSkPathOp.Union);
  end;
end;

procedure WidthScalesAt(const WidthPoints:
  TArray<TMapRakuStrokeWidthPoint>; Offset: Single;
  var PointIndex: Integer; out LeftScale, RightScale: Single);
var
  A: TMapRakuStrokeWidthPoint;
  B: TMapRakuStrokeWidthPoint;
  Ratio: Single;
begin
  while (PointIndex < High(WidthPoints) - 1) and
    (Offset > WidthPoints[PointIndex + 1].Offset) do
    Inc(PointIndex);
  A := WidthPoints[PointIndex];
  B := WidthPoints[Min(PointIndex + 1, High(WidthPoints))];
  if B.Offset <= A.Offset then
    Ratio := 0
  else
    Ratio := EnsureRange((Offset - A.Offset) / (B.Offset - A.Offset),
      0.0, 1.0);
  LeftScale := A.LeftScale + (B.LeftScale - A.LeftScale) * Ratio;
  RightScale := A.RightScale + (B.RightScale - A.RightScale) * Ratio;
end;

procedure AddEndCap(const Builder: ISkPathBuilder; const Center,
  Tangent, Normal: TPointF; LeftRadius, RightRadius: Single;
  LineCap: TVectArtLineCap);
var
  Radius: Single;
  Tip: TPointF;
begin
  if LineCap = vlcTriangle then
  begin
    Radius := Max(LeftRadius, RightRadius);
    Builder.LineTo(TPointF.Create(Center.X + Tangent.X * Radius,
      Center.Y + Tangent.Y * Radius));
    Exit;
  end;
  if LineCap <> vlcRound then
    Exit;
  Radius := Max(LeftRadius, RightRadius);
  Tip := TPointF.Create(Center.X + Tangent.X * Radius,
    Center.Y + Tangent.Y * Radius);
  // 左輪郭から先端、先端から右輪郭を各1本の3次ベジェで近似する。
  // 左右幅が異なる場合も各象限の法線半径を独立させ、接線を連続させる。
  Builder.CubicTo(
    TPointF.Create(Center.X + Normal.X * LeftRadius +
      Tangent.X * Radius * CUBIC_CIRCLE_KAPPA,
      Center.Y + Normal.Y * LeftRadius +
      Tangent.Y * Radius * CUBIC_CIRCLE_KAPPA),
    TPointF.Create(Tip.X + Normal.X * LeftRadius * CUBIC_CIRCLE_KAPPA,
      Tip.Y + Normal.Y * LeftRadius * CUBIC_CIRCLE_KAPPA), Tip);
  Builder.CubicTo(
    TPointF.Create(Tip.X - Normal.X * RightRadius * CUBIC_CIRCLE_KAPPA,
      Tip.Y - Normal.Y * RightRadius * CUBIC_CIRCLE_KAPPA),
    TPointF.Create(Center.X - Normal.X * RightRadius +
      Tangent.X * Radius * CUBIC_CIRCLE_KAPPA,
      Center.Y - Normal.Y * RightRadius +
      Tangent.Y * Radius * CUBIC_CIRCLE_KAPPA),
    TPointF.Create(Center.X - Normal.X * RightRadius,
      Center.Y - Normal.Y * RightRadius));
end;

procedure AddStartCap(const Builder: ISkPathBuilder; const Center,
  Tangent, Normal: TPointF; LeftRadius, RightRadius: Single;
  LineCap: TVectArtLineCap);
var
  Radius: Single;
  Tip: TPointF;
begin
  if LineCap = vlcTriangle then
  begin
    Radius := Max(LeftRadius, RightRadius);
    Builder.LineTo(TPointF.Create(Center.X - Tangent.X * Radius,
      Center.Y - Tangent.Y * Radius));
    Exit;
  end;
  if LineCap <> vlcRound then
    Exit;
  Radius := Max(LeftRadius, RightRadius);
  Tip := TPointF.Create(Center.X - Tangent.X * Radius,
    Center.Y - Tangent.Y * Radius);
  // 逆向きにたどる始端も、右輪郭から先端、先端から左輪郭の2本にする。
  Builder.CubicTo(
    TPointF.Create(Center.X - Normal.X * RightRadius -
      Tangent.X * Radius * CUBIC_CIRCLE_KAPPA,
      Center.Y - Normal.Y * RightRadius -
      Tangent.Y * Radius * CUBIC_CIRCLE_KAPPA),
    TPointF.Create(Tip.X - Normal.X * RightRadius * CUBIC_CIRCLE_KAPPA,
      Tip.Y - Normal.Y * RightRadius * CUBIC_CIRCLE_KAPPA), Tip);
  Builder.CubicTo(
    TPointF.Create(Tip.X + Normal.X * LeftRadius * CUBIC_CIRCLE_KAPPA,
      Tip.Y + Normal.Y * LeftRadius * CUBIC_CIRCLE_KAPPA),
    TPointF.Create(Center.X + Normal.X * LeftRadius -
      Tangent.X * Radius * CUBIC_CIRCLE_KAPPA,
      Center.Y + Normal.Y * LeftRadius -
      Tangent.Y * Radius * CUBIC_CIRCLE_KAPPA),
    TPointF.Create(Center.X + Normal.X * LeftRadius,
      Center.Y + Normal.Y * LeftRadius));
end;

function BuildMapRakuVariableWidthPath(const CenterPath: ISkPath;
  const WidthPoints: TArray<TMapRakuStrokeWidthPoint>;
  BaseWidth: Single; LineCap: TVectArtLineCap;
  const Vertices: TArray<TMapRakuVertex>): ISkPath;
var
  Builder: ISkPathBuilder;
  Centers: TArray<TPointF>;
  I: Integer;
  LeftPoints: TArray<TPointF>;
  LeftRadii: TArray<Single>;
  LeftScale: Single;
  Measure: ISkPathMeasure;
  Normals: TArray<TPointF>;
  Offset: Single;
  PointIndex: Integer;
  RightPoints: TArray<TPointF>;
  RightRadii: TArray<Single>;
  RightScale: Single;
  RightStartIndex: Integer;
  SampleCount: Integer;
  SampleOffsets: TArray<Single>;
  TangentLength: Single;
  Tangents: TArray<TPointF>;
begin
  Result := nil;
  if (CenterPath = nil) or (Length(WidthPoints) < 2) or
    (BaseWidth <= 0) then
    Exit;
  Measure := TSkPathMeasure.Create(CenterPath, False);
  if Measure.Length <= 0.0001 then
    Exit;
  SampleCount := EnsureRange(Ceil(Measure.Length / SAMPLE_DISTANCE) + 1,
    2, MAX_SAMPLE_COUNT);
  SampleOffsets := BuildMapRakuStrokeSampleOffsets(Vertices, SampleCount);
  SampleCount := Length(SampleOffsets);
  SetLength(Centers, SampleCount);
  SetLength(Tangents, SampleCount);
  SetLength(Normals, SampleCount);
  SetLength(LeftPoints, SampleCount);
  SetLength(RightPoints, SampleCount);
  SetLength(LeftRadii, SampleCount);
  SetLength(RightRadii, SampleCount);
  PointIndex := 0;
  for I := 0 to SampleCount - 1 do
  begin
    Offset := SampleOffsets[I];
    Measure.GetPositionAndTangent(Measure.Length * Offset,
      Centers[I], Tangents[I]);
    TangentLength := Hypot(Tangents[I].X, Tangents[I].Y);
    if TangentLength <= 0.0001 then
    begin
      if I > 0 then
        Tangents[I] := Tangents[I - 1]
      else
        Tangents[I] := TPointF.Create(1, 0);
    end
    else
      Tangents[I] := TPointF.Create(Tangents[I].X / TangentLength,
        Tangents[I].Y / TangentLength);
    Normals[I] := TPointF.Create(-Tangents[I].Y, Tangents[I].X);
    WidthScalesAt(WidthPoints, Offset, PointIndex, LeftScale, RightScale);
    LeftRadii[I] := BaseWidth * 0.5 * Max(LeftScale, 0.0);
    RightRadii[I] := BaseWidth * 0.5 * Max(RightScale, 0.0);
    LeftPoints[I] := TPointF.Create(
      Centers[I].X + Normals[I].X * LeftRadii[I],
      Centers[I].Y + Normals[I].Y * LeftRadii[I]);
    RightPoints[I] := TPointF.Create(
      Centers[I].X - Normals[I].X * RightRadii[I],
      Centers[I].Y - Normals[I].Y * RightRadii[I]);
  end;
  // PathMeasureの接線が跳ぶ鋭角では、前後のオフセット線の交点を共有する。
  // これにより内側輪郭の交差／欠けを防ぎ、外側はマイター上限内だけ延長する。
  ApplyVertexJoins(Vertices, SampleOffsets, Centers, LeftRadii, RightRadii,
    LineCap = vlcRound, LeftPoints, RightPoints);
  if LineCap = vlcSquare then
  begin
    LeftPoints[0].Offset(
      -Tangents[0].X * Max(LeftRadii[0], RightRadii[0]),
      -Tangents[0].Y * Max(LeftRadii[0], RightRadii[0]));
    RightPoints[0].Offset(
      -Tangents[0].X * Max(LeftRadii[0], RightRadii[0]),
      -Tangents[0].Y * Max(LeftRadii[0], RightRadii[0]));
    LeftPoints[High(LeftPoints)].Offset(
      Tangents[High(Tangents)].X *
        Max(LeftRadii[High(LeftRadii)], RightRadii[High(RightRadii)]),
      Tangents[High(Tangents)].Y *
        Max(LeftRadii[High(LeftRadii)], RightRadii[High(RightRadii)]));
    RightPoints[High(RightPoints)].Offset(
      Tangents[High(Tangents)].X *
        Max(LeftRadii[High(LeftRadii)], RightRadii[High(RightRadii)]),
      Tangents[High(Tangents)].Y *
        Max(LeftRadii[High(LeftRadii)], RightRadii[High(RightRadii)]));
  end;
  // 2px描画サンプルをそのまま編集頂点にせず、直線区間と視覚上同一の
  // 微小変化を統合する。端点は必ず保持するため線端生成には影響しない。
  LeftPoints := SimplifyMapRakuStrokePoints(LeftPoints, OUTLINE_SIMPLIFY_TOLERANCE);
  RightPoints := SimplifyMapRakuStrokePoints(RightPoints, OUTLINE_SIMPLIFY_TOLERANCE);
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(LeftPoints[0]);
  for I := 1 to High(LeftPoints) do
    Builder.LineTo(LeftPoints[I]);
  AddEndCap(Builder, Centers[High(Centers)], Tangents[High(Tangents)],
    Normals[High(Normals)], LeftRadii[High(LeftRadii)],
    RightRadii[High(RightRadii)], LineCap);
  RightStartIndex := High(RightPoints);
  if LineCap = vlcRound then
    Dec(RightStartIndex);
  for I := RightStartIndex downto 0 do
    Builder.LineTo(RightPoints[I]);
  AddStartCap(Builder, Centers[0], Tangents[0], Normals[0],
    LeftRadii[0], RightRadii[0], LineCap);
  Builder.Close;
  Result := Builder.Detach;
  if LineCap = vlcRound then
    Result := AddRoundVertexJoins(Result, Vertices, SampleOffsets,
      LeftRadii, RightRadii);
end;

end.
