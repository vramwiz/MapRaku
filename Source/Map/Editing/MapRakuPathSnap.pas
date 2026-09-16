// 入れ子グループ内の地図経路から最寄り位置・接線を求める。接続拘束は作らない。
unit MapRakuPathSnap;
interface
uses System.Types, MapRakuDocument;
const
  // ズームに依存しない画面上の吸着距離。呼び出し元で地図座標へ換算する。
  MAP_PATH_ENDPOINT_SNAP_PIXELS = 8.0;
type
  TMapRakuEndpointSnap = record
    Path: TVectArtPathLayer;
    Index: Integer;
    Point, Outward: TPointF;
    CanAdjust: Boolean; // 祖先グループを含めてロックされていない場合だけ相手を変更できる。
  end;
// 同系列の端点だけを候補にする。位置とToleranceは変換後の地図座標。
function NearestMapEndpoint(Document: TVectArtDocument; const Position: TPointF;
  Tolerance: Single; ExcludeSelected: Boolean; const Kind: string;
  out Snap: TMapRakuEndpointSnap; Ignore: TVectArtPathLayer = nil): Boolean;
// 端点を線上の途中より優先し、配置と編集で同じ吸着規則を使う。
function NearestMapPath(Document: TVectArtDocument; const Position: TPointF;
  Tolerance: Single; ExcludeSelected: Boolean; const Kind: string;
  out Point, Tangent: TPointF; out Path: TVectArtPathLayer; Ignore: TVectArtPathLayer = nil): Boolean;
implementation
uses System.Math, MapRakuPathOperations;
function NearestMapEndpoint(Document: TVectArtDocument; const Position: TPointF;
  Tolerance: Single; ExcludeSelected: Boolean; const Kind: string;
  out Snap: TMapRakuEndpointSnap; Ignore: TVectArtPathLayer): Boolean;
var Best: Single; I: Integer; Found: TMapRakuEndpointSnap;
  procedure Visit(Layer: TVectArtLayer; Editable: Boolean);
  var J, Endpoint: Integer; Path: TVectArtPathLayer; P,T: TPointF; Dist: Single;
  begin
    if (Layer=Ignore) or not Layer.Visible or (Layer.Opacity<=0) then Exit;
    Editable:=Editable and not Layer.Locked;
    if Layer is TMapRakuGroupLayer then begin
      for J:=0 to TMapRakuGroupLayer(Layer).ChildCount-1 do
        Visit(TMapRakuGroupLayer(Layer)[J],Editable);
      Exit;
    end;
    if not (Layer is TVectArtPathLayer) then Exit;
    Path:=TVectArtPathLayer(Layer);
    if (Path.ConnectionFamily='') or ((Kind<>'') and
      (Path.ConnectionFamily<>TVectArtPathLayer.ConnectionFamilyOf(Kind))) then Exit;
    for J:=0 to 1 do begin
      if J=0 then Endpoint:=0 else Endpoint:=High(Path.Vertices);
      if not Path.TryEndpoint(Endpoint,P,T) then Continue;
      Dist:=Hypot(P.X-Position.X,P.Y-Position.Y);
      if (Dist<=Best) and ((Found.Path=nil) or (Dist<Best)) then begin
        Best:=Dist; Found.Path:=Path; Found.Index:=Endpoint;
        Found.Point:=P; Found.Outward:=T; Found.CanAdjust:=Editable;
      end;
    end;
  end;
begin
  Snap:=Default(TMapRakuEndpointSnap); Found:=Snap; Best:=Tolerance;
  if (Document=nil) or (Tolerance<0) then Exit(False);
  for I:=1 to Document.LayerCount-1 do
    if not (ExcludeSelected and Document.IsLayerSelected(I)) then Visit(Document[I],True);
  Snap:=Found; Result:=Snap.Path<>nil;
end;

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
  if (Candidate.ConnectionFamily = '') or ((Kind <> '') and
    (TVectArtPathLayer.ConnectionFamilyOf(Kind) <> Candidate.ConnectionFamily)) then Exit;
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
var I: Integer; Best: Single; Snap: TMapRakuEndpointSnap;
begin
  Path := nil; Point := Position; Tangent := PointF(1,0); Best := Tolerance;
  if Document=nil then Exit(False);
  // 近傍の線上点より実際の端点を優先し、位置を丸めずそのまま返す。
  if NearestMapEndpoint(Document,Position,Tolerance,ExcludeSelected,Kind,Snap,Ignore) then begin
    Point:=Snap.Point; Tangent:=Snap.Outward;
    if Snap.Index=0 then Tangent:=Tangent*(-1);
    Path:=Snap.Path; Exit(True);
  end;
  for I := 1 to Document.LayerCount - 1 do
    if not (ExcludeSelected and Document.IsLayerSelected(I)) then
      Consider(Document[I],Position,Kind,Best,Point,Tangent,Path,Ignore);
  Result := Path <> nil;
end;
end.
