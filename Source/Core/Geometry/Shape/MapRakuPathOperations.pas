// 開いたPathの頂点列に対する幾何操作を提供する。
// DocumentやUIの状態を変更せず、受け取った頂点データだけを扱う。
unit MapRakuPathOperations;

interface

uses
  System.Types, MapRakuDocument;

// 端点を循環接続せず、頂点種別に応じた制御点と区間種別を設定する。
procedure ConfigureMapRakuOpenPath(var Vertices: TArray<TMapRakuVertex>);
// 動的配列を共有しないPath頂点列の複製を返す。
function CloneMapRakuPathVertices(const Source: TArray<TMapRakuVertex>): TArray<TMapRakuVertex>;
// 折れ線の始終点と形状を許容誤差内で維持しながら、冗長な中間点を削減する。
function SimplifyMapRakuPolyline(const Points: TArray<TPointF>;
  Tolerance: Single): TArray<TPointF>;
// 座標、制御点、頂点種別、区間種別がすべて等しい場合にTrueを返す。
function MapRakuPathVerticesEqual(const Left, Right: TArray<TMapRakuVertex>): Boolean;
// アンカーと有効なベジェ制御点を含む外接範囲を返す。
function MapRakuPathVerticesBounds(const Vertices: TArray<TMapRakuVertex>): TRectF;
// 2頂点間が直線区間だけで構成される単線ならTrueを返す。
function MapRakuPathIsStraightLine(const Vertices: TArray<TMapRakuVertex>): Boolean;
// 指定点との最短距離を、ベジェ区間を分割して近似する。
function MapRakuPathDistanceToPoint(const Vertices: TArray<TMapRakuVertex>;
  const PointValue: TPointF): Single;
// 直線とベジェを描画順の点列へ展開する。
function FlattenMapRakuPathVertices(const Vertices: TArray<TMapRakuVertex>;
  BezierSteps: Integer = 16): TArray<TPointF>;
// 展開済み点列の先頭から終端までの合計距離を返す。
function MapRakuPolylineLength(const Points: TArray<TPointF>): Single;
// 先頭からの距離に対応する座標と接線を返し、点列が無効ならFalseを返す。
function MapRakuPolylinePointAtDistance(const Points: TArray<TPointF>;
  Distance: Single; out PointValue, Tangent: TPointF): Boolean;
// 展開済み点列上で指定点に最も近い位置を、先頭からの距離として返す。
function MapRakuPolylineNearestDistance(const Points: TArray<TPointF>;
  const PointValue: TPointF; out Distance: Single): Boolean;
// 指定頂点を鋭角または滑らかなベジェ接続へ変更し、隣接区間も更新する。
procedure SetMapRakuPathVertexKind(var Vertices: TArray<TMapRakuVertex>; VertexIndex: Integer;
  Kind: TMapRakuVertexKind);
// 指定区間を分割し、見た目を維持した新頂点の番号を返す。無効な区間では-1を返す。
function InsertMapRakuPathVertex(var Vertices: TArray<TMapRakuVertex>; SegmentIndex: Integer;
  Parameter: Single): Integer;
// 指定頂点を削除する。2頂点を維持できない場合はFalseを返す。
function DeleteMapRakuPathVertex(var Vertices: TArray<TMapRakuVertex>; VertexIndex: Integer): Boolean;
// 全アンカーを同じ量だけ移動した、元配列と独立した頂点列を返す。
function TranslateMapRakuPathVertices(const Source: TArray<TMapRakuVertex>; DX,
  DY: Single): TArray<TMapRakuVertex>;
// 中心回りにアンカーと相対制御点を同じ角度だけ回転した複製を返す。
function RotateMapRakuPathVertices(const Source: TArray<TMapRakuVertex>; const Center: TPointF;
  AngleDegrees: Single): TArray<TMapRakuVertex>;
// アンカーと相対制御点を元の外接範囲から指定範囲へ拡大縮小した複製を返す。
function ScaleMapRakuPathVertices(const Source: TArray<TMapRakuVertex>; const SourceBounds,
  TargetBounds: TRectF): TArray<TMapRakuVertex>;

implementation

uses
  System.Math, MapRakuGeometry;

function LerpPoint(const StartPoint, EndPoint: TPointF; Parameter: Single): TPointF;
begin
  Result := TPointF.Create(StartPoint.X + (EndPoint.X - StartPoint.X) * Parameter,
    StartPoint.Y + (EndPoint.Y - StartPoint.Y) * Parameter);
end;

function CubicPoint(const StartPoint, Control1, Control2, EndPoint: TPointF;
  Parameter: Single): TPointF;
var
  Inverse: Single;
begin
  Inverse := 1 - Parameter;
  Result := TPointF.Create(
    Inverse * Inverse * Inverse * StartPoint.X +
      3 * Inverse * Inverse * Parameter * Control1.X +
      3 * Inverse * Parameter * Parameter * Control2.X +
      Parameter * Parameter * Parameter * EndPoint.X,
    Inverse * Inverse * Inverse * StartPoint.Y +
      3 * Inverse * Inverse * Parameter * Control1.Y +
      3 * Inverse * Parameter * Parameter * Control2.Y +
      Parameter * Parameter * Parameter * EndPoint.Y);
end;

function DistanceToSegment(const PointValue, StartPoint, EndPoint: TPointF): Single;
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
end;

procedure IncludeBoundsPoint(var Bounds: TRectF; var Found: Boolean; const PointValue: TPointF);
begin
  if not Found then
  begin
    Bounds := TRectF.Create(PointValue, PointValue);
    Found := True;
  end
  else
  begin
    Bounds.Left := Min(Bounds.Left, PointValue.X);
    Bounds.Top := Min(Bounds.Top, PointValue.Y);
    Bounds.Right := Max(Bounds.Right, PointValue.X);
    Bounds.Bottom := Max(Bounds.Bottom, PointValue.Y);
  end;
end;

procedure RecalculateOpenPathVertex(var Vertices: TArray<TMapRakuVertex>; VertexIndex: Integer);
var
  NextPosition: TPointF;
  PreviousPosition: TPointF;
begin
  if (VertexIndex < 0) or (VertexIndex > High(Vertices)) then
    Exit;
  if Vertices[VertexIndex].Kind = slvkSharp then
  begin
    Vertices[VertexIndex].IncomingControl := TPointF.Zero;
    Vertices[VertexIndex].OutgoingControl := TPointF.Zero;
    Exit;
  end;
  if VertexIndex = 0 then
  begin
    Vertices[VertexIndex].IncomingControl := TPointF.Zero;
    if Length(Vertices) > 1 then
    begin
      NextPosition := Vertices[VertexIndex + 1].Position;
      Vertices[VertexIndex].OutgoingControl := TPointF.Create(
        (NextPosition.X - Vertices[VertexIndex].Position.X) / 3,
        (NextPosition.Y - Vertices[VertexIndex].Position.Y) / 3);
    end
    else
      Vertices[VertexIndex].OutgoingControl := TPointF.Zero;
    Exit;
  end;
  if VertexIndex = High(Vertices) then
  begin
    PreviousPosition := Vertices[VertexIndex - 1].Position;
    Vertices[VertexIndex].IncomingControl := TPointF.Create(
      (PreviousPosition.X - Vertices[VertexIndex].Position.X) / 3,
      (PreviousPosition.Y - Vertices[VertexIndex].Position.Y) / 3);
    Vertices[VertexIndex].OutgoingControl := TPointF.Zero;
    Exit;
  end;
  PreviousPosition := Vertices[VertexIndex - 1].Position;
  NextPosition := Vertices[VertexIndex + 1].Position;
  Vertices[VertexIndex].IncomingControl := TPointF.Create(
    (PreviousPosition.X - NextPosition.X) / 6,
    (PreviousPosition.Y - NextPosition.Y) / 6);
  Vertices[VertexIndex].OutgoingControl := TPointF.Create(
    (NextPosition.X - PreviousPosition.X) / 6,
    (NextPosition.Y - PreviousPosition.Y) / 6);
end;

procedure UpdateOpenPathSegment(var Vertices: TArray<TMapRakuVertex>; SegmentIndex: Integer);
begin
  if (SegmentIndex < 0) or (SegmentIndex >= High(Vertices)) then
    Exit;
  if (Vertices[SegmentIndex].Kind = slvkBezier) or
    (Vertices[SegmentIndex + 1].Kind = slvkBezier) then
    Vertices[SegmentIndex].OutgoingSegment := slskCubicBezier
  else
    Vertices[SegmentIndex].OutgoingSegment := slskLine;
end;

procedure ConfigureMapRakuOpenPath(var Vertices: TArray<TMapRakuVertex>);
var
  I: Integer;
begin
  if Length(Vertices) = 0 then
    Exit;
  for I := 0 to High(Vertices) do
    RecalculateOpenPathVertex(Vertices, I);
  for I := 0 to High(Vertices) - 1 do
    UpdateOpenPathSegment(Vertices, I);
  Vertices[High(Vertices)].OutgoingSegment := slskLine;
end;

function CloneMapRakuPathVertices(const Source: TArray<TMapRakuVertex>): TArray<TMapRakuVertex>;
begin
  Result := Copy(Source);
end;

function SimplifyMapRakuPolyline(const Points: TArray<TPointF>;
  Tolerance: Single): TArray<TPointF>;
var
  Distance: Single;
  FirstIndex: Integer;
  FirstStack: TArray<Integer>;
  FarthestDistance: Single;
  FarthestIndex: Integer;
  I: Integer;
  Keep: TArray<Boolean>;
  LastIndex: Integer;
  LastStack: TArray<Integer>;
  OutputIndex: Integer;
  StackCount: Integer;
begin
  if Length(Points) <= 2 then
    Exit(Copy(Points));
  Tolerance := Max(Tolerance, 0.0);
  SetLength(Keep, Length(Points));
  Keep[0] := True;
  Keep[High(Points)] := True;
  SetLength(FirstStack, Length(Points) * 2);
  SetLength(LastStack, Length(Points) * 2);
  StackCount := 1;
  FirstStack[0] := 0;
  LastStack[0] := High(Points);
  while StackCount > 0 do
  begin
    Dec(StackCount);
    FirstIndex := FirstStack[StackCount];
    LastIndex := LastStack[StackCount];
    FarthestDistance := -1;
    FarthestIndex := -1;
    for I := FirstIndex + 1 to LastIndex - 1 do
    begin
      Distance := DistanceToSegment(Points[I], Points[FirstIndex],
        Points[LastIndex]);
      if Distance > FarthestDistance then
      begin
        FarthestDistance := Distance;
        FarthestIndex := I;
      end;
    end;
    if (FarthestIndex < 0) or (FarthestDistance <= Tolerance) then
      Continue;
    Keep[FarthestIndex] := True;
    FirstStack[StackCount] := FirstIndex;
    LastStack[StackCount] := FarthestIndex;
    Inc(StackCount);
    FirstStack[StackCount] := FarthestIndex;
    LastStack[StackCount] := LastIndex;
    Inc(StackCount);
  end;
  SetLength(Result, Length(Points));
  OutputIndex := 0;
  for I := 0 to High(Points) do
    if Keep[I] then
    begin
      Result[OutputIndex] := Points[I];
      Inc(OutputIndex);
    end;
  SetLength(Result, OutputIndex);
end;

function MapRakuPathVerticesEqual(const Left, Right: TArray<TMapRakuVertex>): Boolean;
var
  I: Integer;
begin
  if Length(Left) <> Length(Right) then
    Exit(False);
  for I := 0 to High(Left) do
    if not SameValue(Left[I].Position.X, Right[I].Position.X) or
      not SameValue(Left[I].Position.Y, Right[I].Position.Y) or
      not SameValue(Left[I].IncomingControl.X, Right[I].IncomingControl.X) or
      not SameValue(Left[I].IncomingControl.Y, Right[I].IncomingControl.Y) or
      not SameValue(Left[I].OutgoingControl.X, Right[I].OutgoingControl.X) or
      not SameValue(Left[I].OutgoingControl.Y, Right[I].OutgoingControl.Y) or
      (Left[I].OutgoingSegment <> Right[I].OutgoingSegment) or
      (Left[I].Kind <> Right[I].Kind) then
      Exit(False);
  Result := True;
end;

function MapRakuPathVerticesBounds(const Vertices: TArray<TMapRakuVertex>): TRectF;
var
  ControlPoint: TPointF;
  Found: Boolean;
  I: Integer;
begin
  Result := TRectF.Empty;
  Found := False;
  for I := 0 to High(Vertices) do
  begin
    IncludeBoundsPoint(Result, Found, Vertices[I].Position);
    if (I > 0) and (Vertices[I - 1].OutgoingSegment = slskCubicBezier) then
    begin
      ControlPoint := TPointF.Create(Vertices[I].Position.X + Vertices[I].IncomingControl.X,
        Vertices[I].Position.Y + Vertices[I].IncomingControl.Y);
      IncludeBoundsPoint(Result, Found, ControlPoint);
    end;
    if (I < High(Vertices)) and (Vertices[I].OutgoingSegment = slskCubicBezier) then
    begin
      ControlPoint := TPointF.Create(Vertices[I].Position.X + Vertices[I].OutgoingControl.X,
        Vertices[I].Position.Y + Vertices[I].OutgoingControl.Y);
      IncludeBoundsPoint(Result, Found, ControlPoint);
    end;
  end;
end;

function MapRakuPathIsStraightLine(const Vertices: TArray<TMapRakuVertex>): Boolean;
begin
  Result := (Length(Vertices) = 2) and (Vertices[0].OutgoingSegment = slskLine);
end;

function MapRakuPathDistanceToPoint(const Vertices: TArray<TMapRakuVertex>;
  const PointValue: TPointF): Single;
const
  BEZIER_STEPS = 32;
var
  Control1: TPointF;
  Control2: TPointF;
  Distance: Single;
  I: Integer;
  PreviousPoint: TPointF;
  Step: Integer;
  StepPoint: TPointF;
begin
  Result := MaxSingle;
  for I := 0 to High(Vertices) - 1 do
  begin
    if Vertices[I].OutgoingSegment = slskLine then
    begin
      Result := Min(Result, DistanceToSegment(PointValue, Vertices[I].Position,
        Vertices[I + 1].Position));
      Continue;
    end;
    Control1 := TPointF.Create(Vertices[I].Position.X + Vertices[I].OutgoingControl.X,
      Vertices[I].Position.Y + Vertices[I].OutgoingControl.Y);
    Control2 := TPointF.Create(Vertices[I + 1].Position.X + Vertices[I + 1].IncomingControl.X,
      Vertices[I + 1].Position.Y + Vertices[I + 1].IncomingControl.Y);
    PreviousPoint := Vertices[I].Position;
    for Step := 1 to BEZIER_STEPS do
    begin
      StepPoint := CubicPoint(Vertices[I].Position, Control1, Control2,
        Vertices[I + 1].Position, Step / BEZIER_STEPS);
      Distance := DistanceToSegment(PointValue, PreviousPoint, StepPoint);
      Result := Min(Result, Distance);
      PreviousPoint := StepPoint;
    end;
  end;
end;

function FlattenMapRakuPathVertices(const Vertices: TArray<TMapRakuVertex>;
  BezierSteps: Integer): TArray<TPointF>;
var
  Control1: TPointF;
  Control2: TPointF;
  I: Integer;
  OutputIndex: Integer;
  Step: Integer;
begin
  Result := nil;
  if Length(Vertices) = 0 then
    Exit;
  BezierSteps := Max(BezierSteps, 1);
  SetLength(Result, 1 + High(Vertices) * BezierSteps);
  OutputIndex := 0;
  Result[OutputIndex] := Vertices[0].Position;
  for I := 0 to High(Vertices) - 1 do
  begin
    if Vertices[I].OutgoingSegment = slskLine then
    begin
      Inc(OutputIndex);
      Result[OutputIndex] := Vertices[I + 1].Position;
      Continue;
    end;
    Control1 := TPointF.Create(Vertices[I].Position.X + Vertices[I].OutgoingControl.X,
      Vertices[I].Position.Y + Vertices[I].OutgoingControl.Y);
    Control2 := TPointF.Create(Vertices[I + 1].Position.X + Vertices[I + 1].IncomingControl.X,
      Vertices[I + 1].Position.Y + Vertices[I + 1].IncomingControl.Y);
    for Step := 1 to BezierSteps do
    begin
      Inc(OutputIndex);
      Result[OutputIndex] := CubicPoint(Vertices[I].Position, Control1, Control2,
        Vertices[I + 1].Position, Step / BezierSteps);
    end;
  end;
  SetLength(Result, OutputIndex + 1);
end;

function MapRakuPolylineLength(const Points: TArray<TPointF>): Single;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Points) - 1 do
    Result := Result + Hypot(Points[I + 1].X - Points[I].X,
      Points[I + 1].Y - Points[I].Y);
end;

function MapRakuPolylinePointAtDistance(const Points: TArray<TPointF>;
  Distance: Single; out PointValue, Tangent: TPointF): Boolean;
var
  I: Integer;
  SegmentLength: Single;
  T: Single;
begin
  PointValue := TPointF.Zero;
  Tangent := TPointF.Zero;
  Result := Length(Points) >= 2;
  if not Result then
    Exit;
  Distance := Max(Distance, 0.0);
  for I := 0 to High(Points) - 1 do
  begin
    Tangent := TPointF.Create(Points[I + 1].X - Points[I].X,
      Points[I + 1].Y - Points[I].Y);
    SegmentLength := Hypot(Tangent.X, Tangent.Y);
    if SegmentLength <= 0.0001 then
      Continue;
    if Distance <= SegmentLength then
    begin
      T := Distance / SegmentLength;
      PointValue := TPointF.Create(Points[I].X + Tangent.X * T,
        Points[I].Y + Tangent.Y * T);
      Tangent := TPointF.Create(Tangent.X / SegmentLength,
        Tangent.Y / SegmentLength);
      Exit(True);
    end;
    Distance := Distance - SegmentLength;
  end;
  for I := High(Points) - 1 downto 0 do
  begin
    Tangent := TPointF.Create(Points[I + 1].X - Points[I].X,
      Points[I + 1].Y - Points[I].Y);
    SegmentLength := Hypot(Tangent.X, Tangent.Y);
    if SegmentLength > 0.0001 then
    begin
      PointValue := Points[High(Points)];
      Tangent := TPointF.Create(Tangent.X / SegmentLength,
        Tangent.Y / SegmentLength);
      Exit(True);
    end;
  end;
  Result := False;
end;

function MapRakuPolylineNearestDistance(const Points: TArray<TPointF>;
  const PointValue: TPointF; out Distance: Single): Boolean;
var
  AccumulatedDistance: Single;
  CandidateDistance: Single;
  DX: Single;
  DY: Single;
  I: Integer;
  NearestSquaredDistance: Single;
  Projection: Single;
  ProjectedX: Single;
  ProjectedY: Single;
  SegmentLength: Single;
  SegmentLengthSquared: Single;
  SquaredDistance: Single;
begin
  Result := False;
  Distance := 0;
  NearestSquaredDistance := MaxSingle;
  AccumulatedDistance := 0;
  for I := 0 to High(Points) - 1 do
  begin
    DX := Points[I + 1].X - Points[I].X;
    DY := Points[I + 1].Y - Points[I].Y;
    SegmentLengthSquared := DX * DX + DY * DY;
    if SegmentLengthSquared <= 0 then
      Continue;
    SegmentLength := Sqrt(SegmentLengthSquared);
    Projection := EnsureRange(((PointValue.X - Points[I].X) * DX +
      (PointValue.Y - Points[I].Y) * DY) / SegmentLengthSquared, 0.0, 1.0);
    ProjectedX := Points[I].X + DX * Projection;
    ProjectedY := Points[I].Y + DY * Projection;
    SquaredDistance := Sqr(PointValue.X - ProjectedX) +
      Sqr(PointValue.Y - ProjectedY);
    CandidateDistance := AccumulatedDistance + SegmentLength * Projection;
    if SquaredDistance < NearestSquaredDistance then
    begin
      NearestSquaredDistance := SquaredDistance;
      Distance := CandidateDistance;
      Result := True;
    end;
    AccumulatedDistance := AccumulatedDistance + SegmentLength;
  end;
end;

procedure SetMapRakuPathVertexKind(var Vertices: TArray<TMapRakuVertex>; VertexIndex: Integer;
  Kind: TMapRakuVertexKind);
begin
  if (VertexIndex < 0) or (VertexIndex > High(Vertices)) then
    Exit;
  Vertices[VertexIndex].Kind := Kind;
  RecalculateOpenPathVertex(Vertices, VertexIndex);
  UpdateOpenPathSegment(Vertices, VertexIndex - 1);
  UpdateOpenPathSegment(Vertices, VertexIndex);
  if Length(Vertices) > 0 then
    Vertices[High(Vertices)].OutgoingSegment := slskLine;
end;

function InsertMapRakuPathVertex(var Vertices: TArray<TMapRakuVertex>; SegmentIndex: Integer;
  Parameter: Single): Integer;
var
  ControlA: TPointF;
  ControlB: TPointF;
  I: Integer;
  NewVertex: TMapRakuVertex;
  NewVertices: TArray<TMapRakuVertex>;
  PointA: TPointF;
  PointB: TPointF;
  PointC: TPointF;
  PointD: TPointF;
  SplitA: TPointF;
  SplitB: TPointF;
  SplitPoint: TPointF;
begin
  Result := -1;
  if (SegmentIndex < 0) or (SegmentIndex >= High(Vertices)) then
    Exit;
  Parameter := EnsureRange(Parameter, 0.001, 0.999);
  PointA := Vertices[SegmentIndex].Position;
  PointD := Vertices[SegmentIndex + 1].Position;
  NewVertex := Default(TMapRakuVertex);
  if Vertices[SegmentIndex].OutgoingSegment = slskCubicBezier then
  begin
    PointB := TPointF.Create(PointA.X + Vertices[SegmentIndex].OutgoingControl.X,
      PointA.Y + Vertices[SegmentIndex].OutgoingControl.Y);
    PointC := TPointF.Create(PointD.X + Vertices[SegmentIndex + 1].IncomingControl.X,
      PointD.Y + Vertices[SegmentIndex + 1].IncomingControl.Y);
    ControlA := LerpPoint(PointA, PointB, Parameter);
    SplitA := LerpPoint(PointB, PointC, Parameter);
    ControlB := LerpPoint(PointC, PointD, Parameter);
    SplitB := LerpPoint(ControlA, SplitA, Parameter);
    SplitA := LerpPoint(SplitA, ControlB, Parameter);
    SplitPoint := LerpPoint(SplitB, SplitA, Parameter);
    Vertices[SegmentIndex].OutgoingControl := TPointF.Create(
      ControlA.X - PointA.X, ControlA.Y - PointA.Y);
    Vertices[SegmentIndex + 1].IncomingControl := TPointF.Create(
      ControlB.X - PointD.X, ControlB.Y - PointD.Y);
    NewVertex.Position := SplitPoint;
    NewVertex.IncomingControl := TPointF.Create(SplitB.X - SplitPoint.X,
      SplitB.Y - SplitPoint.Y);
    NewVertex.OutgoingControl := TPointF.Create(SplitA.X - SplitPoint.X,
      SplitA.Y - SplitPoint.Y);
    NewVertex.OutgoingSegment := slskCubicBezier;
    NewVertex.Kind := slvkBezier;
  end
  else
  begin
    NewVertex.Position := LerpPoint(PointA, PointD, Parameter);
    NewVertex.OutgoingSegment := slskLine;
    NewVertex.Kind := slvkSharp;
  end;
  Result := SegmentIndex + 1;
  SetLength(NewVertices, Length(Vertices) + 1);
  for I := 0 to Result - 1 do
    NewVertices[I] := Vertices[I];
  NewVertices[Result] := NewVertex;
  for I := Result to High(Vertices) do
    NewVertices[I + 1] := Vertices[I];
  Vertices := NewVertices;
end;

function DeleteMapRakuPathVertex(var Vertices: TArray<TMapRakuVertex>; VertexIndex: Integer): Boolean;
var
  I: Integer;
  NewVertices: TArray<TMapRakuVertex>;
begin
  Result := False;
  if (Length(Vertices) <= 2) or (VertexIndex < 0) or (VertexIndex > High(Vertices)) then
    Exit;
  SetLength(NewVertices, Length(Vertices) - 1);
  for I := 0 to VertexIndex - 1 do
    NewVertices[I] := Vertices[I];
  for I := VertexIndex + 1 to High(Vertices) do
    NewVertices[I - 1] := Vertices[I];
  Vertices := NewVertices;
  RecalculateOpenPathVertex(Vertices, VertexIndex - 1);
  RecalculateOpenPathVertex(Vertices, VertexIndex);
  UpdateOpenPathSegment(Vertices, VertexIndex - 1);
  UpdateOpenPathSegment(Vertices, VertexIndex);
  Vertices[High(Vertices)].OutgoingSegment := slskLine;
  Result := True;
end;

function TranslateMapRakuPathVertices(const Source: TArray<TMapRakuVertex>; DX,
  DY: Single): TArray<TMapRakuVertex>;
var
  I: Integer;
begin
  Result := CloneMapRakuPathVertices(Source);
  for I := 0 to High(Result) do
    Result[I].Position := TPointF.Create(Result[I].Position.X + DX, Result[I].Position.Y + DY);
end;

function RotateMapRakuPathVertices(const Source: TArray<TMapRakuVertex>; const Center: TPointF;
  AngleDegrees: Single): TArray<TMapRakuVertex>;
var
  I: Integer;
begin
  Result := CloneMapRakuPathVertices(Source);
  for I := 0 to High(Result) do
  begin
    Result[I].Position := RotatePointAround(Result[I].Position, Center, AngleDegrees);
    Result[I].IncomingControl := RotatePointAround(Result[I].IncomingControl, TPointF.Zero, AngleDegrees);
    Result[I].OutgoingControl := RotatePointAround(Result[I].OutgoingControl, TPointF.Zero, AngleDegrees);
  end;
end;

function ScaleMapRakuPathVertices(const Source: TArray<TMapRakuVertex>; const SourceBounds,
  TargetBounds: TRectF): TArray<TMapRakuVertex>;
var
  I: Integer;
  ScaleX: Single;
  ScaleY: Single;
begin
  Result := CloneMapRakuPathVertices(Source);
  if SameValue(SourceBounds.Width, 0.0) or SameValue(SourceBounds.Height, 0.0) then
    Exit;
  ScaleX := TargetBounds.Width / SourceBounds.Width;
  ScaleY := TargetBounds.Height / SourceBounds.Height;
  for I := 0 to High(Result) do
  begin
    Result[I].Position := TPointF.Create(TargetBounds.Left +
      (Result[I].Position.X - SourceBounds.Left) * ScaleX,
      TargetBounds.Top + (Result[I].Position.Y - SourceBounds.Top) * ScaleY);
    Result[I].IncomingControl := TPointF.Create(Result[I].IncomingControl.X * ScaleX,
      Result[I].IncomingControl.Y * ScaleY);
    Result[I].OutgoingControl := TPointF.Create(Result[I].OutgoingControl.X * ScaleX,
      Result[I].OutgoingControl.Y * ScaleY);
  end;
end;

end.
