// 同系列の端点スナップ、接線調整、Undoを実操作と保存データで検証する。
unit MapRakuConnectionTests;
interface
procedure CheckEndpointConnections;
procedure WriteConnectionExamples;
implementation
uses System.SysUtils, System.Types, System.Classes, System.IOUtils, System.JSON,
  System.Skia, System.UITypes, System.Math,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap,
  MapRakuDocument, MapRakuDocumentJson, MapRakuEditHistory, MapRakuEditorState,
  MapRakuMapCommands, MapRakuCrossings, MapRakuGroupCommands, MapRakuRenderer, MapRakuShapeCreation,
  MapRakuExport, MapRakuTheme, MapRakuSymbols, MapRakuFile, MapRakuPathSnap,
  MapRakuTextGeometry, MapRakuMainForm, MapRakuPathEditor, MapRakuPathOperations,
  MapRakuProjectiveTransform, MapRakuTestSupport, MapRakuBridgeSpans;
procedure CheckEndpointConnections;
const Elements: array[0..3] of string = ('road','jr','rail','river');
var D,Restored: TVectArtDocument; H: TVectArtEditHistory; S: TVectArtEditorState;
  Editor: TMapPathEditor; Creation: TVectArtShapeCreation;
  A,B: TVectArtPathLayer; Data: TVectArtPathData; Element,Error: string;
  I,J,Mode: Integer; V,W: TArray<TMapRakuVertex>; P,Q,T,U: TPointF;
  Snap: TMapRakuEndpointSnap; Len: Single; Transform: TMapRakuTransform;
  G: TMapRakuGroupLayer;
  function Curve(const Kind:string; Start,Finish:TPointF):TVectArtPathData;
  begin
    Result:=Road(Kind,Start,Finish);
    Result.Vertices[0].Kind:=slvkBezier; Result.Vertices[1].Kind:=slvkBezier;
    Result.Vertices[0].OutgoingSegment:=slskCubicBezier;
    Result.Vertices[0].OutgoingControl:=(Finish-Start)/3+PointF(0,25);
    Result.Vertices[1].IncomingControl:=(Start-Finish)/3+PointF(0,25);
  end;
  procedure CheckJoined(First,Second:TVectArtPathLayer; FirstEnd,SecondEnd:Integer);
  begin
    Check(First.TryEndpoint(FirstEnd,P,T) and Second.TryEndpoint(SecondEnd,Q,U),'Endpoint tangent');
    Check(Hypot(P.X-Q.X,P.Y-Q.Y)<1E-4,'Endpoint position must be exact');
    Check((Abs(T.X*U.Y-T.Y*U.X)<1E-4) and (T.X*U.X+T.Y*U.Y< -0.999),
      'Endpoint tangents must form a smooth continuation');
  end;
begin
  // 始点/終点の全組合せ、曲線→直線・直線→曲線・曲線→曲線を共通APIで検査。
  for Element in Elements do for I:=0 to 1 do for J:=0 to 1 do for Mode:=0 to 2 do begin
    if Mode=1 then Data:=Road(Element,PointF(-100,-70),PointF(-4,3))
    else Data:=Curve(Element,PointF(-100,-70),PointF(-4,3));
    A:=TVectArtPathLayer.Create('',Data.Vertices,False); A.MapElement:=Element;
    if Mode=0 then Data:=Road(Element,PointF(0.25,0.4),PointF(120,0.4))
    else Data:=Curve(Element,PointF(0.25,0.4),PointF(120,40));
    B:=TVectArtPathLayer.Create('',Data.Vertices,False); B.MapElement:=Element;
    try
      Len:=0;
      if Mode<>1 then begin
        if I=0 then P:=A.Vertices[I].OutgoingControl else P:=A.Vertices[I].IncomingControl;
        Len:=Hypot(P.X,P.Y);
      end;
      Check(A.ConnectEndpoint(I,B,J),'Compatible endpoint connection');
      CheckJoined(A,B,I,J);
      if Mode<>1 then begin
        if I=0 then P:=A.Vertices[I].OutgoingControl else P:=A.Vertices[I].IncomingControl;
        Check(Abs(Hypot(P.X,P.Y)-Len)<1E-3,'Endpoint alignment preserves handle length');
      end;
    finally B.Free; A.Free; end;
  end;
  D:=TVectArtDocument.Create; Restored:=TVectArtDocument.Create;
  H:=TVectArtEditHistory.Create; S:=TVectArtEditorState.Create;
  Editor:=TMapPathEditor.Create; Creation:=TVectArtShapeCreation.Create;
  try
    D.CanvasLayer.Width:=800; D.CanvasLayer.Height:=600;
    Data:=Curve('road',PointF(-120,-80),PointF(0.25,0.4)); D.InsertPath(1,Data);
    A:=TVectArtPathLayer(D[1]); V:=A.Vertices;
    Check(NearestMapEndpoint(D,PointF(-3,2),8,False,'road',Snap),'Endpoint acquisition');
    Check((Snap.Index=1) and (Snap.Point=V[1].Position),'Exact fractional endpoint');
    Check(NearestMapPath(D,PointF(-3,2),8,False,'road',P,T,B) and
      (P=V[1].Position),'Endpoint must beat closer interior of a curve');
    Check(not NearestMapEndpoint(D,PointF(0,0),8,False,'jr',Snap),'Different family rejected');
    Data:=Road('road',PointF(70,40),PointF(140,0)); D.InsertPath(2,Data);
    B:=TVectArtPathLayer(D[2]); W:=B.Vertices;
    D.SetSelectedLayers([1,2]); S.CurrentTool:=vetSelect;
    Editor.Configure(D,S,H,Rect(0,0,800,600),1);
    Check(Editor.MouseDown(mbLeft,[],470,340),'Pick moving straight endpoint');
    Check(Editor.MouseMove([],401,301),'Snap moving straight endpoint');
    CheckJoined(B,A,0,1);
    Check(Editor.MouseMove([],470,340),'Move away from endpoint');
    Check(MapRakuPathVerticesEqual(A.Vertices,V),'Leaving snap must restore target curve');
    Editor.MouseMove([],401,301); Editor.MouseUp;
    CheckJoined(B,A,0,1);
    H.Undo;
    Check(MapRakuPathVerticesEqual(A.Vertices,V) and MapRakuPathVerticesEqual(B.Vertices,W),
      'One Undo restores both paths');
    H.Redo; CheckJoined(B,A,0,1);
    Check(TryDeserializeVectArtDocument(SerializeVectArtDocument(D),Restored,Error),Error);
    CheckJoined(TVectArtPathLayer(Restored[2]),TVectArtPathLayer(Restored[1]),0,1);
    H.Undo;
    Editor.MouseDown(mbLeft,[],470,340); Editor.MouseMove([ssAlt],401,301); Editor.MouseUp;
    Check((B.Vertices[0].Position=PointF(1,1)) and MapRakuPathVerticesEqual(A.Vertices,V),
      'Alt disables both endpoint snap and target adjustment');
    H.Undo;
    A.Locked:=True;
    Editor.MouseDown(mbLeft,[],470,340); Editor.MouseMove([],401,301); Editor.MouseUp;
    Check(MapRakuPathVerticesEqual(A.Vertices,V),'Locked target curve unchanged');
    Check(B.Vertices[0].Position=A.Vertices[1].Position,'Locked target still permits position snap');
    H.Undo; A.Locked:=False;
    // 新規直線を既存曲線へ接続。挿入と相手の調整を一度にUndoする。
    S.CurrentTool:=vetLine; S.MapElement:='road'; S.LineStrokeWidth:=24;
    Creation.Configure(D,H,S,Rect(0,0,800,600),1);
    Creation.MouseDown(mbLeft,[],400,302); Creation.MouseUp(mbLeft,[],520,300);
    Check(D.LayerCount=4,'Connected line insertion');
    CheckJoined(TVectArtPathLayer(D[3]),A,0,1);
    H.Undo;
    Check((D.LayerCount=3) and MapRakuPathVerticesEqual(A.Vertices,V),'Insert Undo includes target curve');
    H.Redo; CheckJoined(TVectArtPathLayer(D[3]),A,0,1); H.Undo;
    // 縮小表示でも丸めた画面座標ではなく、実際の端点へ一致させる。
    S.CurrentTool:=vetPath; S.NextVertexKind:=slvkBezier;
    Creation.Configure(D,H,S,Rect(0,0,800,600),0.5);
    Creation.MouseDown(mbLeft,[],399,301); Creation.MouseDown(mbLeft,[],430,265);
    Check(Creation.FinishPath(False),'Connected Bezier insertion');
    CheckJoined(TVectArtPathLayer(D[3]),A,0,1); H.Undo;
    // JRと私鉄の系列判定は1か所。川・道路とは接続しない。
    A.MapElement:='jr'; B.MapElement:='rail'; Check(A.CanConnectTo(B),'Railway family');
    B.MapElement:='river'; Check(not A.CanConnectTo(B),'Railway and river are independent');
    B.MapElement:='jr'; A.Closed:=True;
    Check(not A.CanConnectTo(B) and not A.TryEndpoint(0,P,T),'Closed paths have no endpoints');
    A.Closed:=False;
    // 回転・拡大された相手の端点位置と接線を世界座標で取得する。
    Transform:=TMapRakuTransform.Identity;
    Transform.Values[0]:=0; Transform.Values[1]:=-2;
    Transform.Values[3]:=2; Transform.Values[4]:=0;
    Transform.Values[2]:=30; A.Transform:=Transform;
    Check(B.ConnectEndpoint(0,A,1),'Transformed target connection'); CheckJoined(B,A,0,1);
    // ゼロ長制御点も隣接区間から長さを補い、NaNや未調整の端点を残さない。
    A.Transform:=TMapRakuTransform.Identity; V:=A.Vertices;
    V[1].IncomingControl:=PointF(0,0); A.Vertices:=V;
    Check(B.ConnectEndpoint(0,A,1),'Zero-handle connection'); CheckJoined(B,A,0,1);
    Len:=Hypot(A.Vertices[1].IncomingControl.X,A.Vertices[1].IncomingControl.Y);
    Check(Len>0,'Zero handle gets a usable length');
  finally Creation.Free; Editor.Free; S.Free; H.Free; Restored.Free; D.Free; end;
  D:=TVectArtDocument.Create; H:=TVectArtEditHistory.Create;
  try
    D.InsertPath(1,Curve('road',PointF(-120,-70),PointF(0.25,0.4)));
    D.InsertPath(2,Curve('road',PointF(100.3,20.25),PointF(220,80)));
    A:=TVectArtPathLayer(D[1]); B:=TVectArtPathLayer(D[2]); V:=A.Vertices; W:=B.Vertices;
    Data:=Road('road',PointF(0,0),PointF(100,20));
    InsertMapPath(D,H,Data,True,True,0.75);
    CheckJoined(TVectArtPathLayer(D[3]),A,0,1);
    CheckJoined(TVectArtPathLayer(D[3]),B,1,0);
    H.Undo;
    Check((D.LayerCount=3) and MapRakuPathVerticesEqual(A.Vertices,V) and
      MapRakuPathVerticesEqual(B.Vertices,W),'Two-endpoint connection is one undo');
    H.Redo;
    CheckJoined(TVectArtPathLayer(D[3]),A,0,1);
    CheckJoined(TVectArtPathLayer(D[3]),B,1,0);
    H.Clear;
    // 入れ子の接続先と、その祖先のロック・表示状態も検査する。
    G:=TMapRakuGroupLayer.Create('接続先');
    G.AddChild(D.ExtractLayer(1));
    D.InsertLayer(D.LayerCount,G);
    Check(NearestMapEndpoint(D,PointF(0,0),8,False,'road',Snap) and
      (Snap.Path<>nil),'Grouped endpoint search');
    G.Locked:=True;
    Check(NearestMapEndpoint(D,PointF(-120,-70),8,False,'road',Snap) and
      not Snap.CanAdjust,'Locked ancestor prevents curve adjustment');
    G.Visible:=False;
    Check(not NearestMapEndpoint(D,PointF(-120,-70),8,False,'road',Snap),
      'Hidden group is excluded from endpoint snap');
  finally H.Free; D.Free; end;
  Writeln('PASS: shared endpoint snap/tangents, all endpoint directions/families, drag/creation, Alt, locks, Undo/Redo, JSON, transformed and zero handles');
end;

procedure WriteConnectionExamples;
var D: TVectArtDocument; Data: TVectArtPathData; Curve,Line: TVectArtPathLayer;
  Row,Column,I: Integer; X,Y: Single; LabelText,Element: string;
  Layout: TMapRakuTextLayout;
begin
  D:=TVectArtDocument.Create;
  try
    D.CanvasLayer.Width:=900; D.CanvasLayer.Height:=520;
    for Row:=0 to 1 do for Column:=0 to 1 do begin
      X:=-225+Column*450; Y:=-130+Row*260;
      if Row=0 then Element:='road' else Element:='jr';
      Data:=Road(Element,PointF(X-160,Y+75),PointF(X,Y));
      Data.Vertices[0].Kind:=slvkBezier; Data.Vertices[1].Kind:=slvkBezier;
      Data.Vertices[0].OutgoingSegment:=slskCubicBezier;
      Data.Vertices[0].OutgoingControl:=PointF(70,0);
      Data.Vertices[1].IncomingControl:=PointF(-45,50);
      if Row=1 then Data.StrokeColor:=clBlack;
      I:=D.InsertPath(D.LayerCount,Data); Curve:=TVectArtPathLayer(D[I]);
      Data:=Road(Element,PointF(X,Y),PointF(X+160,Y));
      if Row=1 then Data.StrokeColor:=clBlack;
      I:=D.InsertPath(D.LayerCount,Data); Line:=TVectArtPathLayer(D[I]);
      if Column=1 then Curve.ConnectEndpoint(1,Line,0);
      if Column=0 then LabelText:='角度調整前' else LabelText:='端点スナップ＋接線調整後';
      if Row=0 then LabelText:='道路：'+LabelText else LabelText:='線路：'+LabelText;
      Layout:=BuildMapRakuTextLayout(LabelText,'Yu Gothic UI',20,0);
      D.InsertLayer(D.LayerCount,TMapRakuTextLayer.Create('説明',
        TRectF.Create(X-Layout.Width*0.5,Y-100,X+Layout.Width*0.5,Y-100+Layout.Height),
        LabelText,'Yu Gothic UI',20,0,clBlack));
    end;
    ExportMapPng(D,'TestOutput/connection-examples.png');
    ExportMapSvg(D,'TestOutput/connection-examples.svg');
    SaveMapFile(D,'TestOutput/connection-examples.mapraku');
  finally D.Free; end;
end;

end.
