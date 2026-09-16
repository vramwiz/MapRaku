// Shapeの閉輪郭に対する幾何操作を提供する。
// DocumentやUIの状態を変更せず、受け取った輪郭データだけを扱う。
unit MapRakuShapeOperations;

interface

uses
  System.Types, MapRakuDocument;

// 動的配列を共有しない輪郭群の複製を返す。
function CloneMapRakuShapeContours(
  const Source: TArray<TMapRakuContour>): TArray<TMapRakuContour>;
// 頂点、相対制御点、区間種別がすべて等しい場合にTrueを返す。
function MapRakuShapeContoursEqual(const Left, Right: TArray<TMapRakuContour>): Boolean;
// アンカーと相対制御点を含む輪郭群の外接範囲を返す。
function MapRakuShapeContoursBounds(const Contours: TArray<TMapRakuContour>): TRectF;
// 各アンカーの前後頂点から、閉輪郭の自動平滑化制御点を再計算する。
procedure RecalculateMapRakuSmoothContour(var Contour: TMapRakuContour);
// 終端から始点までを含め、直線とベジェを描画順の点列へ展開する。
function FlattenMapRakuShapeContour(const Contour: TMapRakuContour;
  BezierSteps: Integer = 16): TArray<TPointF>;
// 指定頂点を鋭角または滑らかなベジェ接続へ変更し、隣接区間も更新する。
procedure SetMapRakuShapeVertexKind(var Contour: TMapRakuContour; VertexIndex: Integer;
  Kind: TMapRakuVertexKind);
// 指定区間を分割し、見た目を維持した新頂点の番号を返す。無効な区間では-1を返す。
function InsertMapRakuShapeVertex(var Contour: TMapRakuContour; SegmentIndex: Integer;
  Parameter: Single): Integer;
// 指定頂点を削除する。3頂点の閉輪郭を維持できない場合はFalseを返す。
function DeleteMapRakuShapeVertex(var Contour: TMapRakuContour; VertexIndex: Integer): Boolean;
// 全アンカーを同じ量だけ移動した、元配列と独立した輪郭群を返す。
function TranslateMapRakuShapeContours(const Source: TArray<TMapRakuContour>; DX,
  DY: Single): TArray<TMapRakuContour>;
// 中心回りに全輪郭のアンカーと相対制御点を同じ角度だけ回転した複製を返す。
function RotateMapRakuShapeContours(const Source: TArray<TMapRakuContour>; const Center: TPointF;
  AngleDegrees: Single): TArray<TMapRakuContour>;
// アンカーと相対制御点を元の外接範囲から指定範囲へ拡大縮小した複製を返す。
function ScaleMapRakuShapeContours(const Source: TArray<TMapRakuContour>; const SourceBounds,
  TargetBounds: TRectF): TArray<TMapRakuContour>;

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

procedure RecalculateSmoothVertex(var Contour: TMapRakuContour; VertexIndex: Integer);
var
  NextPosition: TPointF;
  PreviousPosition: TPointF;
begin
  if (VertexIndex < 0) or (VertexIndex > High(Contour.Vertices)) then
    Exit;
  if Contour.Vertices[VertexIndex].Kind = slvkSharp then
  begin
    Contour.Vertices[VertexIndex].IncomingControl := TPointF.Zero;
    Contour.Vertices[VertexIndex].OutgoingControl := TPointF.Zero;
    Exit;
  end;
  PreviousPosition := Contour.Vertices[(VertexIndex + Length(Contour.Vertices) - 1) mod
    Length(Contour.Vertices)].Position;
  NextPosition := Contour.Vertices[(VertexIndex + 1) mod Length(Contour.Vertices)].Position;
  Contour.Vertices[VertexIndex].IncomingControl := TPointF.Create(
    (PreviousPosition.X - NextPosition.X) / 6, (PreviousPosition.Y - NextPosition.Y) / 6);
  Contour.Vertices[VertexIndex].OutgoingControl := TPointF.Create(
    (NextPosition.X - PreviousPosition.X) / 6, (NextPosition.Y - PreviousPosition.Y) / 6);
end;

function CloneMapRakuShapeContours(
  const Source: TArray<TMapRakuContour>): TArray<TMapRakuContour>;
var
  I: Integer;
begin
  SetLength(Result, Length(Source));
  for I := 0 to High(Source) do
    Result[I].Vertices := Copy(Source[I].Vertices);
end;

function MapRakuShapeContoursEqual(const Left, Right: TArray<TMapRakuContour>): Boolean;
var
  ContourIndex: Integer;
  VertexIndex: Integer;
begin
  if Length(Left) <> Length(Right) then
    Exit(False);
  for ContourIndex := 0 to High(Left) do
  begin
    if Length(Left[ContourIndex].Vertices) <> Length(Right[ContourIndex].Vertices) then
      Exit(False);
    for VertexIndex := 0 to High(Left[ContourIndex].Vertices) do
      with Left[ContourIndex].Vertices[VertexIndex] do
        if not SameValue(Position.X, Right[ContourIndex].Vertices[VertexIndex].Position.X) or
          not SameValue(Position.Y, Right[ContourIndex].Vertices[VertexIndex].Position.Y) or
          not SameValue(IncomingControl.X,
            Right[ContourIndex].Vertices[VertexIndex].IncomingControl.X) or
          not SameValue(IncomingControl.Y,
            Right[ContourIndex].Vertices[VertexIndex].IncomingControl.Y) or
          not SameValue(OutgoingControl.X,
            Right[ContourIndex].Vertices[VertexIndex].OutgoingControl.X) or
          not SameValue(OutgoingControl.Y,
            Right[ContourIndex].Vertices[VertexIndex].OutgoingControl.Y) or
          (OutgoingSegment <> Right[ContourIndex].Vertices[VertexIndex].OutgoingSegment) or
          (Kind <> Right[ContourIndex].Vertices[VertexIndex].Kind) then
          Exit(False);
  end;
  Result := True;
end;

function MapRakuShapeContoursBounds(const Contours: TArray<TMapRakuContour>): TRectF;
var
  ContourIndex: Integer;
  ControlPoint: TPointF;
  Found: Boolean;
  Vertex: TMapRakuVertex;
  VertexIndex: Integer;
begin
  Result := TRectF.Empty;
  Found := False;
  for ContourIndex := 0 to High(Contours) do
    for VertexIndex := 0 to High(Contours[ContourIndex].Vertices) do
    begin
      Vertex := Contours[ContourIndex].Vertices[VertexIndex];
      IncludeBoundsPoint(Result, Found, Vertex.Position);
      ControlPoint := TPointF.Create(Vertex.Position.X + Vertex.IncomingControl.X,
        Vertex.Position.Y + Vertex.IncomingControl.Y);
      IncludeBoundsPoint(Result, Found, ControlPoint);
      ControlPoint := TPointF.Create(Vertex.Position.X + Vertex.OutgoingControl.X,
        Vertex.Position.Y + Vertex.OutgoingControl.Y);
      IncludeBoundsPoint(Result, Found, ControlPoint);
    end;
end;

procedure RecalculateMapRakuSmoothContour(var Contour: TMapRakuContour);
var
  I: Integer;
begin
  if Length(Contour.Vertices) < 3 then
    Exit;
  for I := 0 to High(Contour.Vertices) do
    RecalculateSmoothVertex(Contour, I);
end;

function FlattenMapRakuShapeContour(const Contour: TMapRakuContour;
  BezierSteps: Integer): TArray<TPointF>;
var
  Control1: TPointF;
  Control2: TPointF;
  I: Integer;
  NextIndex: Integer;
  OutputIndex: Integer;
  Step: Integer;
begin
  Result := nil;
  if Length(Contour.Vertices) = 0 then
    Exit;
  BezierSteps := Max(BezierSteps, 1);
  SetLength(Result, 1 + Length(Contour.Vertices) * BezierSteps);
  OutputIndex := 0;
  Result[OutputIndex] := Contour.Vertices[0].Position;
  for I := 0 to High(Contour.Vertices) do
  begin
    NextIndex := (I + 1) mod Length(Contour.Vertices);
    if Contour.Vertices[I].OutgoingSegment = slskLine then
    begin
      Inc(OutputIndex);
      Result[OutputIndex] := Contour.Vertices[NextIndex].Position;
      Continue;
    end;
    Control1 := TPointF.Create(Contour.Vertices[I].Position.X +
      Contour.Vertices[I].OutgoingControl.X, Contour.Vertices[I].Position.Y +
      Contour.Vertices[I].OutgoingControl.Y);
    Control2 := TPointF.Create(Contour.Vertices[NextIndex].Position.X +
      Contour.Vertices[NextIndex].IncomingControl.X, Contour.Vertices[NextIndex].Position.Y +
      Contour.Vertices[NextIndex].IncomingControl.Y);
    for Step := 1 to BezierSteps do
    begin
      Inc(OutputIndex);
      Result[OutputIndex] := CubicPoint(Contour.Vertices[I].Position, Control1, Control2,
        Contour.Vertices[NextIndex].Position, Step / BezierSteps);
    end;
  end;
  SetLength(Result, OutputIndex + 1);
end;

procedure SetMapRakuShapeVertexKind(var Contour: TMapRakuContour; VertexIndex: Integer;
  Kind: TMapRakuVertexKind);
var
  NextIndex: Integer;
  PreviousIndex: Integer;
begin
  if (VertexIndex < 0) or (VertexIndex > High(Contour.Vertices)) then
    Exit;
  PreviousIndex := (VertexIndex + Length(Contour.Vertices) - 1) mod Length(Contour.Vertices);
  NextIndex := (VertexIndex + 1) mod Length(Contour.Vertices);
  Contour.Vertices[VertexIndex].Kind := Kind;
  RecalculateSmoothVertex(Contour, VertexIndex);
  if (Contour.Vertices[PreviousIndex].Kind = slvkBezier) or
    (Contour.Vertices[VertexIndex].Kind = slvkBezier) then
    Contour.Vertices[PreviousIndex].OutgoingSegment := slskCubicBezier
  else
    Contour.Vertices[PreviousIndex].OutgoingSegment := slskLine;
  if (Contour.Vertices[VertexIndex].Kind = slvkBezier) or
    (Contour.Vertices[NextIndex].Kind = slvkBezier) then
    Contour.Vertices[VertexIndex].OutgoingSegment := slskCubicBezier
  else
    Contour.Vertices[VertexIndex].OutgoingSegment := slskLine;
end;

function InsertMapRakuShapeVertex(var Contour: TMapRakuContour; SegmentIndex: Integer;
  Parameter: Single): Integer;
var
  ControlA: TPointF;
  ControlB: TPointF;
  I: Integer;
  NewVertex: TMapRakuVertex;
  NewVertices: TArray<TMapRakuVertex>;
  NextIndex: Integer;
  PointA: TPointF;
  PointB: TPointF;
  PointC: TPointF;
  PointD: TPointF;
  SplitA: TPointF;
  SplitB: TPointF;
  SplitPoint: TPointF;
begin
  Result := -1;
  if (SegmentIndex < 0) or (SegmentIndex > High(Contour.Vertices)) then
    Exit;
  Parameter := EnsureRange(Parameter, 0.001, 0.999);
  NextIndex := (SegmentIndex + 1) mod Length(Contour.Vertices);
  PointA := Contour.Vertices[SegmentIndex].Position;
  PointD := Contour.Vertices[NextIndex].Position;
  NewVertex := Default(TMapRakuVertex);
  if Contour.Vertices[SegmentIndex].OutgoingSegment = slskCubicBezier then
  begin
    PointB := TPointF.Create(PointA.X + Contour.Vertices[SegmentIndex].OutgoingControl.X,
      PointA.Y + Contour.Vertices[SegmentIndex].OutgoingControl.Y);
    PointC := TPointF.Create(PointD.X + Contour.Vertices[NextIndex].IncomingControl.X,
      PointD.Y + Contour.Vertices[NextIndex].IncomingControl.Y);
    ControlA := LerpPoint(PointA, PointB, Parameter);
    SplitA := LerpPoint(PointB, PointC, Parameter);
    ControlB := LerpPoint(PointC, PointD, Parameter);
    SplitB := LerpPoint(ControlA, SplitA, Parameter);
    SplitA := LerpPoint(SplitA, ControlB, Parameter);
    SplitPoint := LerpPoint(SplitB, SplitA, Parameter);
    Contour.Vertices[SegmentIndex].OutgoingControl := TPointF.Create(
      ControlA.X - PointA.X, ControlA.Y - PointA.Y);
    Contour.Vertices[NextIndex].IncomingControl := TPointF.Create(
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
  SetLength(NewVertices, Length(Contour.Vertices) + 1);
  for I := 0 to Result - 1 do
    NewVertices[I] := Contour.Vertices[I];
  NewVertices[Result] := NewVertex;
  for I := Result to High(Contour.Vertices) do
    NewVertices[I + 1] := Contour.Vertices[I];
  Contour.Vertices := NewVertices;
end;

function DeleteMapRakuShapeVertex(var Contour: TMapRakuContour; VertexIndex: Integer): Boolean;
var
  I: Integer;
  NewVertices: TArray<TMapRakuVertex>;
  NextIndex: Integer;
  PreviousIndex: Integer;
begin
  Result := False;
  if (Length(Contour.Vertices) <= 3) or (VertexIndex < 0) or
    (VertexIndex > High(Contour.Vertices)) then
    Exit;
  SetLength(NewVertices, Length(Contour.Vertices) - 1);
  for I := 0 to VertexIndex - 1 do
    NewVertices[I] := Contour.Vertices[I];
  for I := VertexIndex + 1 to High(Contour.Vertices) do
    NewVertices[I - 1] := Contour.Vertices[I];
  Contour.Vertices := NewVertices;
  NextIndex := VertexIndex mod Length(Contour.Vertices);
  PreviousIndex := (NextIndex + Length(Contour.Vertices) - 1) mod Length(Contour.Vertices);
  if (Contour.Vertices[PreviousIndex].Kind = slvkBezier) or
    (Contour.Vertices[NextIndex].Kind = slvkBezier) then
    Contour.Vertices[PreviousIndex].OutgoingSegment := slskCubicBezier
  else
    Contour.Vertices[PreviousIndex].OutgoingSegment := slskLine;
  RecalculateSmoothVertex(Contour, PreviousIndex);
  RecalculateSmoothVertex(Contour, NextIndex);
  Result := True;
end;

function TranslateMapRakuShapeContours(const Source: TArray<TMapRakuContour>; DX,
  DY: Single): TArray<TMapRakuContour>;
var
  ContourIndex: Integer;
  VertexIndex: Integer;
begin
  Result := CloneMapRakuShapeContours(Source);
  for ContourIndex := 0 to High(Result) do
    for VertexIndex := 0 to High(Result[ContourIndex].Vertices) do
      with Result[ContourIndex].Vertices[VertexIndex] do
        Position := TPointF.Create(Position.X + DX, Position.Y + DY);
end;

function RotateMapRakuShapeContours(const Source: TArray<TMapRakuContour>; const Center: TPointF;
  AngleDegrees: Single): TArray<TMapRakuContour>;
var
  ContourIndex: Integer;
  VertexIndex: Integer;
begin
  Result := CloneMapRakuShapeContours(Source);
  for ContourIndex := 0 to High(Result) do
    for VertexIndex := 0 to High(Result[ContourIndex].Vertices) do
      with Result[ContourIndex].Vertices[VertexIndex] do
      begin
        Position := RotatePointAround(Position, Center, AngleDegrees);
        IncomingControl := RotatePointAround(IncomingControl, TPointF.Zero, AngleDegrees);
        OutgoingControl := RotatePointAround(OutgoingControl, TPointF.Zero, AngleDegrees);
      end;
end;

function ScaleMapRakuShapeContours(const Source: TArray<TMapRakuContour>; const SourceBounds,
  TargetBounds: TRectF): TArray<TMapRakuContour>;
var
  ContourIndex: Integer;
  ScaleX: Single;
  ScaleY: Single;
  VertexIndex: Integer;
begin
  Result := CloneMapRakuShapeContours(Source);
  if SameValue(SourceBounds.Width, 0.0) or SameValue(SourceBounds.Height, 0.0) then
    Exit;
  ScaleX := TargetBounds.Width / SourceBounds.Width;
  ScaleY := TargetBounds.Height / SourceBounds.Height;
  for ContourIndex := 0 to High(Result) do
    for VertexIndex := 0 to High(Result[ContourIndex].Vertices) do
      with Result[ContourIndex].Vertices[VertexIndex] do
      begin
        Position := TPointF.Create(TargetBounds.Left +
          (Position.X - SourceBounds.Left) * ScaleX,
          TargetBounds.Top + (Position.Y - SourceBounds.Top) * ScaleY);
        IncomingControl := TPointF.Create(IncomingControl.X * ScaleX,
          IncomingControl.Y * ScaleY);
        OutgoingControl := TPointF.Create(OutgoingControl.X * ScaleX,
          OutgoingControl.Y * ScaleY);
      end;
end;

end.
