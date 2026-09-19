// 入れ子グループ内の地図経路から最寄り位置・接線を求める。接続拘束は作らない。
unit MapRakuPathSnap;
interface
uses System.Types, MapRakuDocument;
const
  // ズームに依存しない画面上の吸着距離。呼び出し元で地図座標へ換算する。
  MAP_PATH_ENDPOINT_SNAP_PIXELS = 8.0;
  MAP_ROUTE_SNAP_PIXELS = 24.0;
type
  // 吸着時の形状を所有し、元レイヤーの寿命や後続編集に依存しない。
  TMapRakuRouteSnap = record
    PathId: string;
    Vertices: TArray<TMapRakuVertex>;
    Segment: Integer;
    Parameter: Single;
    Point: TPointF;
  end;
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
// ルート専用。道路・線路・川の最寄り中心線へ画面24px以内で吸着する。
function NearestMapRouteTarget(Document: TVectArtDocument; const Position: TPointF;
  Zoom: Single; out Point: TPointF; Ignore: TVectArtPathLayer = nil): Boolean;
function NearestMapRouteSnap(Document: TVectArtDocument; const Position: TPointF;
  Zoom: Single; out Snap: TMapRakuRouteSnap;
  Ignore: TVectArtPathLayer = nil): Boolean;
// 同一経路の2点間を切り出す。ベジェ制御点を保持し、逆方向にも対応する。
function MapRouteSection(const First, Last: TMapRakuRouteSnap): TArray<TMapRakuVertex>;
function BuildMapRouteFollowing(const Base: TArray<TMapRakuVertex>;
  const Snaps: TArray<TMapRakuRouteSnap>): TArray<TMapRakuVertex>;
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
procedure RouteCurve(const V: TArray<TMapRakuVertex>; I: Integer; T: Single;
  out P, Derivative: TPointF);
var A,B,C,D: TPointF; U: Single;
begin
  A:=V[I].Position; D:=V[I+1].Position;
  if V[I].OutgoingSegment=slskLine then
  begin P:=A+(D-A)*T; Derivative:=D-A; Exit; end;
  B:=A+V[I].OutgoingControl; C:=D+V[I+1].IncomingControl; U:=1-T;
  P:=A*(U*U*U)+B*(3*U*U*T)+C*(3*U*T*T)+D*(T*T*T);
  Derivative:=(B-A)*(3*U*U)+(C-B)*(6*U*T)+(D-C)*(3*T*T);
end;

function NearestMapRouteSnap(Document: TVectArtDocument; const Position: TPointF;
  Zoom: Single; out Snap: TMapRakuRouteSnap; Ignore: TVectArtPathLayer): Boolean;
var I: Integer; Best: Single; Found: TMapRakuRouteSnap;
  procedure Visit(Layer: TVectArtLayer);
  var J,K,N: Integer; Candidate: TVectArtPathLayer;
    V: TArray<TMapRakuVertex>; P,Q,Delta: TPointF;
    T,LowT,HighT,T1,T2,D1,D2,LocalBest,BestT,Dist,LengthSquared: Single;
  begin
    if (Layer=Ignore) or not Layer.Visible or (Layer.Opacity<=0) then Exit;
    if Layer is TMapRakuGroupLayer then
    begin
      for J:=0 to TMapRakuGroupLayer(Layer).ChildCount-1 do
        Visit(TMapRakuGroupLayer(Layer)[J]);
      Exit;
    end;
    if not (Layer is TVectArtPathLayer) then Exit;
    Candidate:=TVectArtPathLayer(Layer);
    if (Candidate.MapElement<>'road') and (Candidate.MapElement<>'jr') and
      (Candidate.MapElement<>'rail') and (Candidate.MapElement<>'river') then Exit;
    V:=CloneMapRakuPathVertices(Candidate.Vertices);
    for J:=0 to High(V) do
    begin
      P:=Candidate.Transform.Map(V[J].Position);
      V[J].IncomingControl:=Candidate.Transform.Map(V[J].Position+V[J].IncomingControl)-P;
      V[J].OutgoingControl:=Candidate.Transform.Map(V[J].Position+V[J].OutgoingControl)-P;
      V[J].Position:=P;
    end;
    for J:=0 to High(V)-1 do
    begin
      if V[J].OutgoingSegment=slskLine then
      begin
        Delta:=V[J+1].Position-V[J].Position;
        LengthSquared:=Sqr(Delta.X)+Sqr(Delta.Y);
        if LengthSquared<1E-12 then T:=0
        else T:=EnsureRange(((Position.X-V[J].Position.X)*Delta.X+
          (Position.Y-V[J].Position.Y)*Delta.Y)/LengthSquared,0.0,1.0);
      end
      else
      begin
        LocalBest:=MaxSingle; BestT:=0;
        for K:=0 to 64 do
        begin
          RouteCurve(V,J,K/64,P,Q); Dist:=Sqr(P.X-Position.X)+Sqr(P.Y-Position.Y);
          if Dist<LocalBest then begin LocalBest:=Dist; BestT:=K/64; end;
        end;
        LowT:=Max(0,BestT-1/64); HighT:=Min(1,BestT+1/64);
        for N:=1 to 24 do
        begin
          T1:=LowT+(HighT-LowT)/3; T2:=HighT-(HighT-LowT)/3;
          RouteCurve(V,J,T1,P,Q); D1:=Sqr(P.X-Position.X)+Sqr(P.Y-Position.Y);
          RouteCurve(V,J,T2,P,Q); D2:=Sqr(P.X-Position.X)+Sqr(P.Y-Position.Y);
          if D1<D2 then HighT:=T2 else LowT:=T1;
        end;
        T:=(LowT+HighT)/2;
        RouteCurve(V,J,T,P,Q);
        if LocalBest<Sqr(P.X-Position.X)+Sqr(P.Y-Position.Y) then T:=BestT;
      end;
      RouteCurve(V,J,T,P,Q); Dist:=Hypot(P.X-Position.X,P.Y-Position.Y);
      if Dist<=Best then
      begin
        Best:=Dist; Found.PathId:=Candidate.PersistentId; Found.Vertices:=V;
        Found.Segment:=J; Found.Parameter:=T; Found.Point:=P;
      end;
    end;
  end;
begin
  Snap:=Default(TMapRakuRouteSnap); Found:=Snap;
  if (Document=nil) or (Zoom<=0) then Exit(False);
  Best:=MAP_ROUTE_SNAP_PIXELS/Zoom;
  for I:=1 to Document.LayerCount-1 do Visit(Document[I]);
  Snap:=Found; Result:=Snap.PathId<>'';
end;

function NearestMapRouteTarget(Document: TVectArtDocument; const Position: TPointF;
  Zoom: Single; out Point: TPointF; Ignore: TVectArtPathLayer): Boolean;
var Snap: TMapRakuRouteSnap;
begin
  Result:=NearestMapRouteSnap(Document,Position,Zoom,Snap,Ignore);
  if Result then Point:=Snap.Point else Point:=Position;
end;

function MapRouteSection(const First, Last: TMapRakuRouteSnap): TArray<TMapRakuVertex>;
var A,B: TMapRakuRouteSnap; V,Forward: TArray<TMapRakuVertex>;
  I,J: Integer; T0,T1: Single; P,Q,DP,DQ: TPointF;
  StartV,EndV: TMapRakuVertex; Reverse: Boolean;
begin
  Result:=nil;
  if (First.PathId='') or (First.PathId<>Last.PathId) or
    not MapRakuPathVerticesEqual(First.Vertices,Last.Vertices) then Exit;
  Reverse:=First.Segment+First.Parameter>Last.Segment+Last.Parameter;
  if Reverse then begin A:=Last; B:=First; end else begin A:=First; B:=Last; end;
  V:=A.Vertices;
  for I:=A.Segment to B.Segment do
  begin
    T0:=0; T1:=1;
    if I=A.Segment then T0:=A.Parameter;
    if I=B.Segment then T1:=B.Parameter;
    if T1-T0<1E-7 then Continue;
    RouteCurve(V,I,T0,P,DP); RouteCurve(V,I,T1,Q,DQ);
    StartV:=Default(TMapRakuVertex); EndV:=StartV;
    StartV.Position:=P; EndV.Position:=Q;
    StartV.OutgoingSegment:=V[I].OutgoingSegment;
    if StartV.OutgoingSegment=slskCubicBezier then
    begin
      StartV.Kind:=slvkBezier; EndV.Kind:=slvkBezier;
      StartV.OutgoingControl:=DP*((T1-T0)/3);
      EndV.IncomingControl:=DQ*(-(T1-T0)/3);
    end;
    if Length(Result)=0 then Result:=[StartV]
    else begin
      J:=High(Result); Result[J].OutgoingControl:=StartV.OutgoingControl;
      Result[J].OutgoingSegment:=StartV.OutgoingSegment;
      if StartV.Kind=slvkBezier then Result[J].Kind:=slvkBezier;
    end;
    Result:=Result+[EndV];
  end;
  if Reverse then
  begin
    Forward:=Result; Result:=nil; SetLength(Result,Length(Forward));
    for I:=0 to High(Result) do
    begin
      J:=High(Forward)-I; Result[I]:=Forward[J];
      Result[I].IncomingControl:=Forward[J].OutgoingControl;
      Result[I].OutgoingControl:=Forward[J].IncomingControl;
      if J>0 then Result[I].OutgoingSegment:=Forward[J-1].OutgoingSegment;
    end;
  end;
end;

function BuildMapRouteFollowing(const Base: TArray<TMapRakuVertex>;
  const Snaps: TArray<TMapRakuRouteSnap>): TArray<TMapRakuVertex>;
var I,J: Integer; V,Part: TArray<TMapRakuVertex>;
begin
  V:=CloneMapRakuPathVertices(Base); Result:=nil;
  if Length(V)=0 then Exit;
  for I:=0 to Min(High(V),High(Snaps)) do
    if Snaps[I].PathId<>'' then V[I].Position:=Snaps[I].Point;
  Result:=[V[0]];
  for I:=0 to High(V)-1 do
  begin
    Part:=nil;
    if I+1<Length(Snaps) then Part:=MapRouteSection(Snaps[I],Snaps[I+1]);
    if Length(Part)<2 then Part:=[V[I],V[I+1]];
    J:=High(Result); Result[J].OutgoingControl:=Part[0].OutgoingControl;
    Result[J].OutgoingSegment:=Part[0].OutgoingSegment;
    if Part[0].Kind=slvkBezier then Result[J].Kind:=slvkBezier;
    for J:=1 to High(Part) do Result:=Result+[Part[J]];
  end;
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
