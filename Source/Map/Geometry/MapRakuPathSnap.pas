// 入れ子グループ内の地図経路から最寄り位置・接線を求める。接続拘束は作らない。
unit MapRakuPathSnap;
interface
uses System.Types, MapRakuDocument;
function NearestMapPath(Document: TVectArtDocument; const Position: TPointF;
  Tolerance: Single; ExcludeSelected: Boolean; const Kind: string;
  out Point, Tangent: TPointF; out Path: TVectArtPathLayer; Ignore: TVectArtPathLayer = nil): Boolean;
implementation
uses System.Math, MapRakuPathOperations;
procedure Consider(Layer: TVectArtLayer; const Position: TPointF;
  const Kind: string; var Best: Single; var Point, Tangent: TPointF;
  var Path: TVectArtPathLayer; Ignore: TVectArtPathLayer);
var I: Integer; Points: TArray<TPointF>; D, Dist: Single; P, T: TPointF;
  Candidate: TVectArtPathLayer;
begin
  if (Layer=Ignore) or not Layer.Visible then Exit;
  if Layer is TMapRakuGroupLayer then begin
    for I := 0 to TMapRakuGroupLayer(Layer).ChildCount - 1 do
      Consider(TMapRakuGroupLayer(Layer)[I], Position, Kind, Best, Point, Tangent, Path, Ignore);
    Exit;
  end;
  if not (Layer is TVectArtPathLayer) then Exit;
  Candidate := TVectArtPathLayer(Layer);
  if (Candidate.MapElement = '') or ((Kind <> '') and (Kind <> Candidate.MapElement)) then Exit;
  Points := FlattenMapRakuPathVertices(Candidate.Vertices,64);
  for I := 0 to High(Points) do Points[I] := Candidate.Transform.Map(Points[I]);
  if not MapRakuPolylineNearestDistance(Points,Position,D) or
    not MapRakuPolylinePointAtDistance(Points,D,P,T) then Exit;
  Dist := Hypot(P.X-Position.X,P.Y-Position.Y);
  if Dist <= Best then begin Best := Dist; Point := P; Tangent := T; Path := Candidate; end;
end;
function NearestMapPath(Document: TVectArtDocument; const Position: TPointF;
  Tolerance: Single; ExcludeSelected: Boolean; const Kind: string;
  out Point, Tangent: TPointF; out Path: TVectArtPathLayer; Ignore: TVectArtPathLayer): Boolean;
var I: Integer; Best: Single;
begin
  Path := nil; Point := Position; Tangent := PointF(1,0); Best := Tolerance;
  for I := 1 to Document.LayerCount - 1 do
    if not (ExcludeSelected and Document.IsLayerSelected(I)) then
      Consider(Document[I],Position,Kind,Best,Point,Tangent,Path,Ignore);
  Result := Path <> nil;
end;
end.
