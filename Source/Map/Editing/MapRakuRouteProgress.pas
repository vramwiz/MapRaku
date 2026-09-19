// 論理ルートの区間接続、弧長進行、現在位置をアプリとプラグインで共用する。
unit MapRakuRouteProgress;
interface
uses System.Types, MapRakuDocument;
type
  TMapRakuRouteSample = record
    Position, Tangent: TPointF;
    Path: TVectArtPathLayer;
  end;
  TMapRakuRouteProgressData = record
    RouteId: string;
    Samples: TArray<TMapRakuRouteSample>;
    Distances: TArray<Single>;
    TotalLength: Single;
  end;

procedure WriteMapRakuRouteDiagnostic(Document: TVectArtDocument; const RouteId, ErrorText: string);
function MapRakuRouteIdentifier(Path: TVectArtPathLayer): string;
function TryBuildMapRakuRoute(Document: TVectArtDocument; const RouteId: string;
  out Route: TMapRakuRouteProgressData; out ErrorText: string): Boolean;
function TryMapRakuRoutePosition(const Route: TMapRakuRouteProgressData;
  ProgressPercent: Single; out Position, Tangent: TPointF;
  out Path: TVectArtPathLayer): Boolean;
implementation
uses System.Math, System.SysUtils, MapRakuLayerGeometry, MapRakuPathOperations
{$IFDEF DEBUG}
  , System.IOUtils, Winapi.Windows, MapRakuDocumentJson
{$ENDIF};
const
  // 地図座標の12px以内を接続とみなす。表示倍率には依存しない。
  ROUTE_ENDPOINT_TOLERANCE = 12.0;

procedure WriteMapRakuRouteDiagnostic(Document: TVectArtDocument; const RouteId, ErrorText: string);
{$IFDEF DEBUG}
var Text: string; I: Integer; Path: TVectArtPathLayer;
{$ENDIF}
begin
{$IFDEF DEBUG}
  if Document=nil then Exit;
  try
    Text:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz ',Now)+
      Format('DEBUG pid=%d route=%s tolerance=%.3f result=%s',
        [GetCurrentProcessId,RouteId,ROUTE_ENDPOINT_TOLERANCE,ErrorText])+sLineBreak;
    for I:=1 to Document.LayerCount-1 do
      if Document[I] is TVectArtPathLayer then
      begin
        Path:=TVectArtPathLayer(Document[I]);
        if Path.MapElement='route' then
          Text:=Text+Format('path=%s routeId=%s vertices=%d closed=%s',
            [Path.PersistentId,MapRakuRouteIdentifier(Path),Length(Path.Vertices),
             BoolToStr(Path.Closed,True)])+sLineBreak;
      end;
    TFile.AppendAllText(TPath.Combine(TPath.GetTempPath,'MapRakuRouteDiagnostic.log'),Text,TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(TPath.GetTempPath,
      Format('MapRakuRouteDiagnostic-%d.mapraku',[GetCurrentProcessId])),
      SerializeVectArtDocument(Document),TEncoding.UTF8);
    OutputDebugString(PChar(Text));
  except
    // 診断ファイルの書き込み失敗で編集を止めない。
  end;
{$ENDIF}
end;
function MapRakuRouteIdentifier(Path: TVectArtPathLayer): string;
begin
  if Path.RouteId<>'' then Result:=Path.RouteId else Result:=Path.PersistentId;
end;

function Distance(const A,B:TPointF): Single;
begin Result:=Hypot(A.X-B.X,A.Y-B.Y); end;

function MarkerPosition(Layer: TMapRakuGroupLayer; out Position: TPointF): Boolean;
var Bounds: TRectF;
begin
  // マーカーは通常の移動操作で子レイヤー座標が平行移動する。保存時点の
  // RouteMarkerPosition はその操作では更新されないため、常に表示中の記号中心を
  // 優先する。開始・終了記号は原点中心の円なので外接矩形の中心がスナップ位置になる。
  Result:=TryGetMapRakuLayerBounds(Layer,Bounds);
  if Result then begin
    Position:=Bounds.CenterPoint;
    Exit;
  end;
  // 壊れた記号など、表示領域を得られない場合だけ保存座標を使う。
  if Layer.HasRouteMarkerPosition then begin
    Position:=Layer.RouteMarkerPosition;
    Exit(True);
  end;
  Position:=PointF(0,0);
end;

procedure AddPathSamples(var Route:TMapRakuRouteProgressData;
  Path:TVectArtPathLayer; Forward:Boolean);
var Points:TArray<TPointF>; I,Index:Integer; Sample:TMapRakuRouteSample;
begin
  Points:=FlattenMapRakuPathVertices(Path.Vertices,64);
  if not Forward then
    for I:=0 to (Length(Points) div 2)-1 do begin
      Index:=High(Points)-I; Sample.Position:=Points[I];
      Points[I]:=Points[Index]; Points[Index]:=Sample.Position;
    end;
  for I:=0 to High(Points) do begin
    Points[I]:=Path.Transform.Map(Points[I]);
    if (Length(Route.Samples)>0) and (I=0) and
       (Distance(Route.Samples[High(Route.Samples)].Position,Points[I])<=1E-6) then
      Continue;
    Sample.Position:=Points[I]; Sample.Tangent:=PointF(0,0); Sample.Path:=Path;
    Route.Samples:=Route.Samples+[Sample];
  end;
end;

function TryBuildMapRakuRoute(Document: TVectArtDocument; const RouteId: string;
  out Route: TMapRakuRouteProgressData; out ErrorText: string): Boolean;
var Paths,AllPaths:TArray<TVectArtPathLayer>; Used:TArray<Boolean>; StartMarker,EndMarker,
  GlobalStartMarker,GlobalEndMarker:TMapRakuGroupLayer;
  StartPoint,EndPoint:TPointF; I,J,CurrentPath,EndpointIndex,
  GlobalStartCount,GlobalEndCount:Integer; Forward:Boolean;
  TraversalPaths,TraversalEndpoints:TArray<Integer>;
  function PathEndpoint(Path:TVectArtPathLayer; Index:Integer):TPointF;
  var Direction:TPointF;
  begin Path.TryEndpoint(Index,Result,Direction); end;
  function FindTraversal(const Position:TPointF; UsedCount:Integer):Boolean;
  var K,E,N,L,Code:Integer; P,NextPosition:TPointF; Gap:Single;
    Candidates:TArray<Integer>; Gaps:TArray<Single>;
  begin
    if (UsedCount>0) and (Distance(Position,EndPoint)<=ROUTE_ENDPOINT_TOLERANCE) then
      Exit(True);
    // 完全一致を含む近い端点から探索し、行き止まりの場合だけ次候補へ戻る。
    for K:=0 to High(Paths) do begin
      if Used[K] then Continue;
      for E:=0 to 1 do begin
        if E=0 then P:=PathEndpoint(Paths[K],0)
        else P:=PathEndpoint(Paths[K],High(Paths[K].Vertices));
        Gap:=Distance(P,Position);
        if Gap>ROUTE_ENDPOINT_TOLERANCE then Continue;
        N:=Length(Candidates); SetLength(Candidates,N+1); SetLength(Gaps,N+1);
        while (N>0) and (Gaps[N-1]>Gap) do begin
          Candidates[N]:=Candidates[N-1]; Gaps[N]:=Gaps[N-1]; Dec(N);
        end;
        Candidates[N]:=K*2+E; Gaps[N]:=Gap;
      end;
    end;
    for L:=0 to High(Candidates) do begin
      Code:=Candidates[L]; K:=Code div 2; E:=Code mod 2;
      Used[K]:=True;
      if E=0 then NextPosition:=PathEndpoint(Paths[K],High(Paths[K].Vertices))
      else NextPosition:=PathEndpoint(Paths[K],0);
      if FindTraversal(NextPosition,UsedCount+1) then begin
        TraversalPaths:=TraversalPaths+[K]; TraversalEndpoints:=TraversalEndpoints+[E];
        Exit(True);
      end;
      Used[K]:=False;
    end;
    Result:=False;
  end;
  function PointText(const P:TPointF): string;
  begin
    Result:=Format('(%.2f, %.2f)',[P.X,P.Y]);
  end;
  function RemainingPathsText: string;
  var K:Integer; FirstPoint,LastPoint:TPointF;
  begin
    Result:='';
    for K:=0 to High(Paths) do begin
      if Used[K] then Continue;
      FirstPoint:=PathEndpoint(Paths[K],0);
      LastPoint:=PathEndpoint(Paths[K],High(Paths[K].Vertices));
      if Result<>'' then Result:=Result+'; ';
      Result:=Result+Format('%d:%s→%s',[K,PointText(FirstPoint),PointText(LastPoint)]);
    end;
  end;
begin
  Route:=Default(TMapRakuRouteProgressData); ErrorText:=''; Result:=False;
  if (Document=nil) or (RouteId='') then begin ErrorText:='論理ルートIDがありません'; Exit; end;
  StartMarker:=nil; EndMarker:=nil;
  GlobalStartMarker:=nil; GlobalEndMarker:=nil; GlobalStartCount:=0; GlobalEndCount:=0;
  for I:=0 to Document.LayerCount-1 do begin
    if Document[I] is TVectArtPathLayer then begin
      if (TVectArtPathLayer(Document[I]).MapElement='route') and not
         TVectArtPathLayer(Document[I]).Closed then begin
        AllPaths:=AllPaths+[TVectArtPathLayer(Document[I])];
        if MapRakuRouteIdentifier(TVectArtPathLayer(Document[I]))=RouteId then
          Paths:=Paths+[TVectArtPathLayer(Document[I])];
      end;
    end;
    if Document[I] is TMapRakuGroupLayer then
      if TMapRakuGroupLayer(Document[I]).RouteMarkerKind='start' then begin
        Inc(GlobalStartCount); GlobalStartMarker:=TMapRakuGroupLayer(Document[I]);
        if TMapRakuGroupLayer(Document[I]).RoutePathId=RouteId then StartMarker:=GlobalStartMarker;
      end
      else if TMapRakuGroupLayer(Document[I]).RouteMarkerKind='end' then begin
        Inc(GlobalEndCount); GlobalEndMarker:=TMapRakuGroupLayer(Document[I]);
        if TMapRakuGroupLayer(Document[I]).RoutePathId=RouteId then EndMarker:=GlobalEndMarker;
      end;
  end;
  // 初期実装で描画種別ごとにIDが分かれたファイルは、開始・終了が1組なら端点列から復元する。
  if ((StartMarker=nil) or (EndMarker=nil)) and
     (GlobalStartCount=1) and (GlobalEndCount=1) then begin
    Paths:=AllPaths;
    StartMarker:=GlobalStartMarker;
    EndMarker:=GlobalEndMarker;
  end;
  if Length(Paths)=0 then begin ErrorText:='ルート区間がありません'; Exit; end;
  if (StartMarker=nil) or not MarkerPosition(StartMarker,StartPoint) then begin ErrorText:='開始点がありません'; Exit; end;
  if (EndMarker=nil) or not MarkerPosition(EndMarker,EndPoint) then begin ErrorText:='終了点がありません'; Exit; end;
  SetLength(Used,Length(Paths));
  if not FindTraversal(StartPoint,0) then begin
    ErrorText:=Format('開始点%sから終了点%sまで、12px以内でつながる端点がありません / 区間[%s]',
      [PointText(StartPoint),PointText(EndPoint),RemainingPathsText]);
    Exit;
  end;
  // 再帰の復帰順は逆順なので、先頭から逆にサンプルを追加する。
  for I:=High(TraversalPaths) downto 0 do begin
    CurrentPath:=TraversalPaths[I]; EndpointIndex:=TraversalEndpoints[I];
    Forward:=EndpointIndex=0;
    AddPathSamples(Route,Paths[CurrentPath],Forward);
  end;
  if Length(Route.Samples)<2 then begin ErrorText:='ルートの長さが不足しています'; Exit; end;
  SetLength(Route.Distances,Length(Route.Samples));
  for I:=1 to High(Route.Samples) do
    Route.Distances[I]:=Route.Distances[I-1]+Distance(Route.Samples[I-1].Position,Route.Samples[I].Position);
  Route.TotalLength:=Route.Distances[High(Route.Distances)];
  if Route.TotalLength<=1E-6 then begin ErrorText:='ルートの長さが0です'; Exit; end;
  for I:=0 to High(Route.Samples) do begin
    if I=High(Route.Samples) then J:=I-1 else J:=I+1;
    Route.Samples[I].Tangent:=Route.Samples[J].Position-Route.Samples[Max(0,I-1)].Position;
  end;
  Route.RouteId:=RouteId; Result:=True;
end;

function TryMapRakuRoutePosition(const Route: TMapRakuRouteProgressData;
  ProgressPercent: Single; out Position, Tangent: TPointF;
  out Path: TVectArtPathLayer): Boolean;
var Target,Span,T:Single; I:Integer;
begin
  Result:=False; Position:=PointF(0,0); Tangent:=PointF(1,0); Path:=nil;
  if (Length(Route.Samples)<2) or (Route.TotalLength<=0) then Exit;
  Target:=EnsureRange(ProgressPercent,0,100)*0.01*Route.TotalLength;
  I:=1; while (I<High(Route.Distances)) and (Route.Distances[I]<Target) do Inc(I);
  Span:=Route.Distances[I]-Route.Distances[I-1];
  if Span<=1E-6 then T:=0 else T:=(Target-Route.Distances[I-1])/Span;
  Position:=Route.Samples[I-1].Position+(Route.Samples[I].Position-Route.Samples[I-1].Position)*T;
  Tangent:=Route.Samples[I].Position-Route.Samples[I-1].Position;
  Path:=Route.Samples[I].Path; Result:=True;
end;
end.
