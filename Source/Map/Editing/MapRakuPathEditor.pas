// 同層グループ内の地図経路を直接点編集する。入力・補助表示・1操作分の履歴だけを担当する。
unit MapRakuPathEditor;
interface
uses System.Classes, System.Types, Vcl.Controls, Vcl.Graphics, MapRakuDocument,
  MapRakuEditorState, MapRakuEditHistory, MapRakuEditCommands, MapRakuPathEditSession;
type
  TMapPathEditor = class
  private
    FDocument: TVectArtDocument;
    FHistory: TVectArtEditHistory;
    FLayer: TVectArtPathLayer;
    FCandidates:TArray<TVectArtPathLayer>;
    FEditSession: TMapRakuPathEditSession;
    FBounds: TRect;
    FZoom: Single;
    FVertex, FHandle: Integer;
    FHoverVertex:Integer;
    FHoverLayer:TVectArtPathLayer;
    FDragging: Boolean;
    function ScreenPoint(const P: TPointF): TPoint;
    function LogicalPoint(X,Y: Integer): TPointF;
    procedure Commit;
    procedure BeginEdit;
    function PickLayer(X,Y:Integer):TVectArtPathLayer;
  public
    destructor Destroy; override;
    procedure Configure(Document: TVectArtDocument; State: TVectArtEditorState;
      History: TVectArtEditHistory; const Bounds: TRect; Zoom: Single);
    function MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer): Boolean;
    function MouseMove(Shift: TShiftState; X,Y: Integer): Boolean;
    function MouseUp: Boolean;
    function KeyDown(Key: Word): Boolean;
    // 右クリック地点の頂点または区間を特定し、メニュー実行まで対象を固定する。
    function ContextTarget(X,Y: Integer; out Layer: TVectArtPathLayer;
      out VertexIndex, SegmentIndex: Integer; out SegmentT: Single): Boolean;
    function ExecuteContextEdit(Layer: TVectArtPathLayer;
      VertexIndex, SegmentIndex: Integer; SegmentT: Single;
      DeleteVertex: Boolean): Boolean;
    procedure Draw(Canvas: TCustomCanvas);
  end;
implementation
uses Vcl.Direct2D, System.Math, System.SysUtils, MapRakuPathOperations, MapRakuPathSnap;
destructor TMapPathEditor.Destroy;
begin FEditSession.Free; inherited; end;

procedure TMapPathEditor.BeginEdit;
begin
  FreeAndNil(FEditSession);
  FEditSession:=TMapRakuPathEditSession.Create(FDocument);
  FEditSession.Track(FLayer);
end;
procedure TMapPathEditor.Configure(Document: TVectArtDocument; State: TVectArtEditorState;
  History: TVectArtEditHistory; const Bounds: TRect; Zoom: Single);
var L: TVectArtLayer; I:Integer; OldLayer:TVectArtPathLayer;
  procedure AddPaths(Item:TVectArtLayer);
  var J:Integer; Group:TMapRakuGroupLayer;
  begin
    if not Item.Visible or Item.Locked then Exit;
    if (Item is TVectArtPathLayer) and (TVectArtPathLayer(Item).MapElement<>'') and
      not Item.Locked and Item.Transform.IsIdentity then
      FCandidates:=FCandidates+[TVectArtPathLayer(Item)]
    else if Item is TMapRakuGroupLayer then begin Group:=TMapRakuGroupLayer(Item);
      for J:=0 to Group.ChildCount-1 do AddPaths(Group[J]); end;
  end;
begin
  FDocument:=Document; FHistory:=History; FBounds:=Bounds; FZoom:=Max(Zoom,0.001);
  OldLayer:=FLayer; FCandidates:=nil;
  if (State<>nil) and (Document<>nil) and (State.CurrentTool=vetSelect) then begin
    if (State.OpenGroup<>nil) and (State.OpenGroupChildCount>0) then
      for L in State.GetOpenGroupChildren do AddPaths(L)
    else for I in Document.GetSelectedLayerIndices do AddPaths(Document[I]);
  end;
  FLayer:=nil;
  for I:=0 to High(FCandidates) do if FCandidates[I]=OldLayer then FLayer:=OldLayer;
  if (FLayer=nil) and (Length(FCandidates)>0) then FLayer:=FCandidates[0];
  if FLayer<>OldLayer then begin FVertex:=-1; FDragging:=False; end;
end;

function TMapPathEditor.PickLayer(X,Y:Integer):TVectArtPathLayer;
var Path:TVectArtPathLayer; V:TArray<TMapRakuVertex>; I,J:Integer; P,Q:TPoint;
  Points:TArray<TPointF>; Pair:TArray<TMapRakuVertex>; A:TPointF; D,Best:Single;
begin Result:=nil; Best:=14;
  if (FLayer<>nil) and (FVertex>=0) and (FVertex<Length(FLayer.Vertices)) and
    (FLayer.Vertices[FVertex].Kind=slvkBezier) then begin
    V:=FLayer.Vertices;
    P:=ScreenPoint(V[FVertex].Position+V[FVertex].IncomingControl);
    if Hypot(X-P.X,Y-P.Y)<7 then Exit(FLayer);
    P:=ScreenPoint(V[FVertex].Position+V[FVertex].OutgoingControl);
    if Hypot(X-P.X,Y-P.Y)<7 then Exit(FLayer);
  end;
  for Path in FCandidates do begin V:=Path.Vertices;
    for I:=0 to High(V) do begin P:=ScreenPoint(V[I].Position); D:=Hypot(X-P.X,Y-P.Y);
      if D<Best then begin Best:=D; Result:=Path; end; end;
  end;
  if Result<>nil then Exit;
  Best:=7;
  for Path in FCandidates do begin V:=Path.Vertices;
    for I:=0 to High(V)-1 do begin Pair:=[V[I],V[I+1]]; Points:=FlattenMapRakuPathVertices(Pair,32);
      for J:=0 to High(Points)-1 do begin P:=ScreenPoint(Points[J]); Q:=ScreenPoint(Points[J+1]);
        A:=PointF(Q.X-P.X,Q.Y-P.Y); D:=EnsureRange(((X-P.X)*A.X+(Y-P.Y)*A.Y)/Max(1,Sqr(A.X)+Sqr(A.Y)),0.0,1.0);
        D:=Hypot(X-P.X-D*A.X,Y-P.Y-D*A.Y); if D<Best then begin Best:=D; Result:=Path; end;
      end; end;
  end;
end;
function TMapPathEditor.ScreenPoint(const P:TPointF):TPoint;
begin Result:=Point(Round(FBounds.CenterPoint.X+P.X*FZoom),Round(FBounds.CenterPoint.Y+P.Y*FZoom)); end;
function TMapPathEditor.LogicalPoint(X,Y:Integer):TPointF;
begin Result:=PointF((X-FBounds.CenterPoint.X)/FZoom,(Y-FBounds.CenterPoint.Y)/FZoom); end;
procedure TMapPathEditor.Commit;
var Command: TVectArtEditCommand;
begin
  if FEditSession<>nil then begin
    Command:=FEditSession.CaptureCommand;
    if Command<>nil then begin
      if FHistory<>nil then FHistory.AddApplied(Command) else Command.Free;
      FDocument.Changed;
    end;
    FreeAndNil(FEditSession);
  end;
end;
function TMapPathEditor.MouseDown(Button:TMouseButton; Shift:TShiftState; X,Y:Integer):Boolean;
var V:TArray<TMapRakuVertex>; I:Integer; P:TPoint; A:TPointF;
  L:TVectArtPathLayer;
begin
  Result:=False; if Length(FCandidates)=0 then Exit;
  if Button<>mbLeft then Exit;
  if not FDragging then begin
    L:=PickLayer(X,Y); if L=nil then Exit;
    if L<>FLayer then FVertex:=-1;
    FLayer:=L;
  end;
  V:=FLayer.Vertices; FHandle:=0;
  if (FVertex>=0) and (FVertex<Length(V)) then
    for I:=1 to 2 do begin
      if I=1 then A:=V[FVertex].Position+V[FVertex].IncomingControl
      else A:=V[FVertex].Position+V[FVertex].OutgoingControl;
      P:=ScreenPoint(A);
      if (V[FVertex].Kind=slvkBezier) and
        (Hypot(A.X-V[FVertex].Position.X,A.Y-V[FVertex].Position.Y)>1E-6) and
        (((I=1) and (FVertex>0)) or ((I=2) and (FVertex<High(V)))) and
        (Hypot(X-P.X,Y-P.Y)<7) then begin
        BeginEdit; FHandle:=I; FDragging:=True; Exit(True);
      end;
    end;
  for I:=0 to High(V) do begin
    P:=ScreenPoint(V[I].Position);
    if Hypot(X-P.X,Y-P.Y)<14 then begin
      FVertex:=I;
      BeginEdit; FDragging:=True;
      Exit(True);
    end;
  end;
end;

function TMapPathEditor.ContextTarget(X,Y: Integer;
  out Layer: TVectArtPathLayer; out VertexIndex, SegmentIndex: Integer;
  out SegmentT: Single): Boolean;
var
  V:TArray<TMapRakuVertex>; I,J:Integer; P,Q:TPoint; A:TPointF;
  Points:TArray<TPointF>; Pair:TArray<TMapRakuVertex>; D,Best,U:Single;
begin
  Layer:=PickLayer(X,Y); VertexIndex:=-1; SegmentIndex:=-1; SegmentT:=0;
  Result:=Layer<>nil;
  if not Result then Exit;
  V:=Layer.Vertices; Best:=14;
  for I:=0 to High(V) do begin
    P:=ScreenPoint(V[I].Position); D:=Hypot(X-P.X,Y-P.Y);
    if D<Best then begin Best:=D; VertexIndex:=I; end;
  end;
  if VertexIndex>=0 then Exit;
  Best:=7;
  for I:=0 to High(V)-1 do begin
    Pair:=[V[I],V[I+1]]; Points:=FlattenMapRakuPathVertices(Pair,64);
    for J:=0 to High(Points)-1 do begin
      P:=ScreenPoint(Points[J]); Q:=ScreenPoint(Points[J+1]);
      A:=PointF(Q.X-P.X,Q.Y-P.Y);
      U:=EnsureRange(((X-P.X)*A.X+(Y-P.Y)*A.Y)/
        Max(1,Sqr(A.X)+Sqr(A.Y)),0.0,1.0);
      D:=Hypot(X-P.X-U*A.X,Y-P.Y-U*A.Y);
      if D<Best then begin
        Best:=D; SegmentIndex:=I;
        SegmentT:=(J+U)/Max(1,Length(Points)-1);
      end;
    end;
  end;
  Result:=SegmentIndex>=0;
  if not Result then Layer:=nil;
end;

function TMapPathEditor.ExecuteContextEdit(Layer: TVectArtPathLayer;
  VertexIndex, SegmentIndex: Integer; SegmentT: Single;
  DeleteVertex: Boolean): Boolean;
var
  I:Integer; V:TArray<TMapRakuVertex>;
begin
  Result:=False;
  if (Layer=nil) or Layer.Locked or not Layer.Transform.IsIdentity then Exit;
  for I:=0 to High(FCandidates) do
    if FCandidates[I]=Layer then begin Result:=True; Break; end;
  if not Result then Exit;
  Result:=False; V:=Layer.Vertices;
  if DeleteVertex then begin
    if (VertexIndex<0) or (Length(V)<=2) then Exit;
  end else if (SegmentIndex<0) or (SegmentIndex>=High(V)) then Exit;
  FLayer:=Layer; BeginEdit;
  if DeleteVertex then Result:=DeleteMapRakuPathVertex(V,VertexIndex)
  else begin
    FVertex:=InsertMapRakuPathVertex(V,SegmentIndex,SegmentT);
    Result:=FVertex>=0;
  end;
  if Result then begin
    Layer.Vertices:=V;
    if DeleteVertex then FVertex:=-1;
    Commit;
  end else FreeAndNil(FEditSession);
end;
function TMapPathEditor.MouseMove(Shift:TShiftState; X,Y:Integer):Boolean;
var V:TArray<TMapRakuVertex>; P,T,Snapped:TPointF; Path,NewHoverLayer:TVectArtPathLayer;
  I,NewHoverVertex:Integer; Q:TPoint; D,Best:Single;
  Endpoint: TMapRakuEndpointSnap;
begin
  if not FDragging then begin
    NewHoverLayer:=nil; NewHoverVertex:=-1; Best:=14;
    for Path in FCandidates do begin V:=Path.Vertices;
      for I:=0 to High(V) do begin Q:=ScreenPoint(V[I].Position);
        D:=Hypot(X-Q.X,Y-Q.Y); if D<Best then begin Best:=D;
          NewHoverLayer:=Path; NewHoverVertex:=I; end;
      end;
    end;
    Result:=(NewHoverLayer<>FHoverLayer) or (NewHoverVertex<>FHoverVertex);
    FHoverLayer:=NewHoverLayer; FHoverVertex:=NewHoverVertex; Exit;
  end;
  Result:=FLayer<>nil; if not Result then Exit;
  if FEditSession<>nil then FEditSession.Restore;
  V:=FLayer.Vertices; if (FVertex<0) or (FVertex>=Length(V)) then Exit(False);
  P:=LogicalPoint(X,Y);
  if FHandle=1 then V[FVertex].IncomingControl:=P-V[FVertex].Position
  else if FHandle=2 then V[FVertex].OutgoingControl:=P-V[FVertex].Position
  else begin
    if not (ssAlt in Shift) then begin
      if FLayer.IsEndpoint(FVertex) and
        NearestMapEndpoint(FDocument,P,MAP_PATH_ENDPOINT_SNAP_PIXELS/FZoom,
          False,FLayer.ConnectionFamily,Endpoint,FLayer) then begin
        if Endpoint.CanAdjust then FEditSession.Track(Endpoint.Path);
        FLayer.ConnectEndpoint(FVertex,Endpoint.Path,Endpoint.Index,Endpoint.CanAdjust);
        FDocument.Changed; Exit(True);
      end;
      if NearestMapPath(FDocument,P,6/FZoom,False,FLayer.MapElement,Snapped,T,Path,FLayer) then P:=Snapped;
    end;
    V[FVertex].Position:=P;
  end;
  FLayer.Vertices:=V; FDocument.Changed;
end;
function TMapPathEditor.MouseUp:Boolean;
begin Result:=FDragging; if Result then begin FDragging:=False; Commit; end; end;
function TMapPathEditor.KeyDown(Key:Word):Boolean;
var V:TArray<TMapRakuVertex>; K:TMapRakuVertexKind;
begin
  Result:=(FLayer<>nil) and (FVertex>=0) and (Key=Ord('P'));
  if not Result then Exit;
  V:=FLayer.Vertices; BeginEdit;
  if V[FVertex].Kind=slvkSharp then K:=slvkBezier else K:=slvkSharp;
  SetMapRakuPathVertexKind(V,FVertex,K); FLayer.Vertices:=V; Commit;
end;
procedure TMapPathEditor.Draw(Canvas:TCustomCanvas);
var V:TArray<TMapRakuVertex>; I:Integer; P,Q:TPoint; Path:TVectArtPathLayer;
begin
  if Length(FCandidates)=0 then Exit;
  if Canvas is TCanvas then begin
    TCanvas(Canvas).Pen.Color:=clBlack; TCanvas(Canvas).Pen.Width:=1; TCanvas(Canvas).Brush.Color:=clWhite;
  end else if Canvas is TDirect2DCanvas then begin
    TDirect2DCanvas(Canvas).Pen.Color:=clBlack; TDirect2DCanvas(Canvas).Pen.Width:=1; TDirect2DCanvas(Canvas).Brush.Color:=clWhite;
  end;
  for Path in FCandidates do begin
   V:=Path.Vertices;
   for I:=0 to High(V) do begin
    P:=ScreenPoint(V[I].Position);
    if (Path=FHoverLayer) and (I=FHoverVertex) then begin
      if Canvas is TCanvas then TCanvas(Canvas).Brush.Color:=$000080FF
      else if Canvas is TDirect2DCanvas then TDirect2DCanvas(Canvas).Brush.Color:=$000080FF;
      Canvas.Rectangle(P.X-7,P.Y-7,P.X+8,P.Y+8);
      if Canvas is TCanvas then TCanvas(Canvas).Brush.Color:=clWhite
      else if Canvas is TDirect2DCanvas then TDirect2DCanvas(Canvas).Brush.Color:=clWhite;
    end else Canvas.Rectangle(P.X-4,P.Y-4,P.X+5,P.Y+5);
    if (Path=FLayer) and (I=FVertex) and (V[I].Kind=slvkBezier) then begin
      Q:=ScreenPoint(V[I].Position+V[I].IncomingControl); Canvas.MoveTo(P.X,P.Y); Canvas.LineTo(Q.X,Q.Y);
      Canvas.Ellipse(Q.X-4,Q.Y-4,Q.X+5,Q.Y+5);
      Q:=ScreenPoint(V[I].Position+V[I].OutgoingControl); Canvas.MoveTo(P.X,P.Y); Canvas.LineTo(Q.X,Q.Y);
      Canvas.Ellipse(Q.X-4,Q.Y-4,Q.X+5,Q.Y+5);
    end;
   end;
  end;
end;
end.
