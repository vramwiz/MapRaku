// 可変幅ストロークの採取位置と、生成輪郭の編集点削減を担当する。
unit MapRakuStrokeSampling;

interface

uses
  System.Types, MapRakuDocument;

// 頂点位置を必ず含む、0～1の昇順サンプル位置を返す。入力配列は変更しない。
function BuildMapRakuStrokeSampleOffsets(
  const Vertices: TArray<TMapRakuVertex>;
  BaseSampleCount: Integer): TArray<Single>;

// 見た目をTolerance以内に保ちながら輪郭点を削減する。両端は常に保持する。
function SimplifyMapRakuStrokePoints(const Points: TArray<TPointF>;
  Tolerance: Single): TArray<TPointF>;

// 直線または3次ベジェで結ばれた1区間の実長を返す。
function MapRakuPathSegmentLength(const StartVertex,
  EndVertex: TMapRakuVertex): Single;

implementation

uses
  System.Math, System.Skia;

function PointSegmentDistance(const PointValue, SegmentStart,
  SegmentEnd: TPointF): Single;
var
  DX: Single;
  DY: Single;
  LengthSquared: Single;
  Ratio: Single;
begin
  DX := SegmentEnd.X - SegmentStart.X;
  DY := SegmentEnd.Y - SegmentStart.Y;
  LengthSquared := DX * DX + DY * DY;
  if LengthSquared <= 0.000001 then
    Exit(Hypot(PointValue.X - SegmentStart.X, PointValue.Y - SegmentStart.Y));
  Ratio := EnsureRange(((PointValue.X - SegmentStart.X) * DX +
    (PointValue.Y - SegmentStart.Y) * DY) / LengthSquared, 0.0, 1.0);
  Result := Hypot(PointValue.X - (SegmentStart.X + DX * Ratio),
    PointValue.Y - (SegmentStart.Y + DY * Ratio));
end;

procedure MarkSimplifiedPoints(const Points: TArray<TPointF>;
  FirstIndex, LastIndex: Integer; Tolerance: Single;
  var Keep: TArray<Boolean>);
var
  Distance: Single;
  FurthestDistance: Single;
  FurthestIndex: Integer;
  I: Integer;
begin
  if LastIndex <= FirstIndex + 1 then
    Exit;
  FurthestDistance := -1;
  FurthestIndex := -1;
  for I := FirstIndex + 1 to LastIndex - 1 do
  begin
    Distance := PointSegmentDistance(Points[I], Points[FirstIndex], Points[LastIndex]);
    if Distance > FurthestDistance then
    begin
      FurthestDistance := Distance;
      FurthestIndex := I;
    end;
  end;
  if (FurthestIndex >= 0) and (FurthestDistance > Tolerance) then
  begin
    Keep[FurthestIndex] := True;
    MarkSimplifiedPoints(Points, FirstIndex, FurthestIndex, Tolerance, Keep);
    MarkSimplifiedPoints(Points, FurthestIndex, LastIndex, Tolerance, Keep);
  end;
end;

function SimplifyMapRakuStrokePoints(const Points: TArray<TPointF>;
  Tolerance: Single): TArray<TPointF>;
var
  Changed: Boolean;
  Count: Integer;
  I: Integer;
  Keep: TArray<Boolean>;
begin
  if Length(Points) <= 2 then
    Exit(Copy(Points));
  SetLength(Keep, Length(Points));
  Keep[0] := True;
  Keep[High(Keep)] := True;
  MarkSimplifiedPoints(Points, 0, High(Points), Tolerance, Keep);
  SetLength(Result, Length(Points));
  Count := 0;
  for I := 0 to High(Points) do
    if Keep[I] and ((Count = 0) or
      (Hypot(Points[I].X - Result[Count - 1].X,
        Points[I].Y - Result[Count - 1].Y) > 0.0001)) then
    begin
      Result[Count] := Points[I];
      Inc(Count);
    end;
  SetLength(Result, Count);
  repeat
    Changed := False;
    I := 1;
    while I < High(Result) do
      if PointSegmentDistance(Result[I], Result[I - 1], Result[I + 1]) <= Tolerance then
      begin
        for Count := I to High(Result) - 1 do
          Result[Count] := Result[Count + 1];
        SetLength(Result, Length(Result) - 1);
        Changed := True;
      end
      else
        Inc(I);
  until not Changed;
end;

function MapRakuPathSegmentLength(const StartVertex,
  EndVertex: TMapRakuVertex): Single;
var
  Builder: ISkPathBuilder;
  Measure: ISkPathMeasure;
begin
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(StartVertex.Position);
  if StartVertex.OutgoingSegment = slskCubicBezier then
    Builder.CubicTo(TPointF.Create(StartVertex.Position.X + StartVertex.OutgoingControl.X,
      StartVertex.Position.Y + StartVertex.OutgoingControl.Y),
      TPointF.Create(EndVertex.Position.X + EndVertex.IncomingControl.X,
      EndVertex.Position.Y + EndVertex.IncomingControl.Y), EndVertex.Position)
  else
    Builder.LineTo(EndVertex.Position);
  Measure := TSkPathMeasure.Create(Builder.Detach, False);
  Result := Measure.Length;
end;

function BuildMapRakuStrokeSampleOffsets(
  const Vertices: TArray<TMapRakuVertex>;
  BaseSampleCount: Integer): TArray<Single>;
var
  Count: Integer;
  Cumulative: Single;
  I: Integer;
  J: Integer;
  SegmentLengths: TArray<Single>;
  Temp: Single;
  TotalLength: Single;
begin
  SetLength(Result, BaseSampleCount + Max(Length(Vertices) - 2, 0));
  for I := 0 to BaseSampleCount - 1 do
    Result[I] := I / (BaseSampleCount - 1);
  if Length(Vertices) > 2 then
  begin
    SetLength(SegmentLengths, Length(Vertices) - 1);
    TotalLength := 0;
    for I := 0 to High(SegmentLengths) do
    begin
      SegmentLengths[I] := MapRakuPathSegmentLength(Vertices[I], Vertices[I + 1]);
      TotalLength := TotalLength + SegmentLengths[I];
    end;
    Cumulative := 0;
    for I := 0 to Length(Vertices) - 3 do
    begin
      Cumulative := Cumulative + SegmentLengths[I];
      if TotalLength > 0.0001 then
        Result[BaseSampleCount + I] := Cumulative / TotalLength;
    end;
  end;
  for I := 0 to High(Result) - 1 do
    for J := I + 1 to High(Result) do
      if Result[J] < Result[I] then
      begin
        Temp := Result[I];
        Result[I] := Result[J];
        Result[J] := Temp;
      end;
  Count := 0;
  for I := 0 to High(Result) do
    if (Count = 0) or not SameValue(Result[I], Result[Count - 1], 0.000001) then
    begin
      Result[Count] := Result[I];
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

end.
