// 地図固有の経路・層・保存・描画・作図操作を実データで検証する。
unit MapRakuTestCases;
interface
procedure RunMapTests;
implementation
uses System.SysUtils, System.Types, System.Classes, System.IOUtils, System.JSON,
  System.Skia, System.UITypes, System.Math,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap,
  MapRakuDocument, MapRakuDocumentJson, MapRakuEditHistory, MapRakuEditorState,
  MapRakuMapCommands, MapRakuCrossings, MapRakuGroupCommands, MapRakuRenderer, MapRakuShapeCreation,
  MapRakuExport, MapRakuTheme, MapRakuSymbols, MapRakuFile, MapRakuPathSnap,
  MapRakuTextGeometry, MapRakuMainForm, MapRakuPathEditor;
type
  TTestExceptionSink = class
    procedure HandleException(Sender: TObject; E: Exception);
  end;
procedure TTestExceptionSink.HandleException(Sender: TObject; E: Exception);
begin
  Writeln('FAIL (VCL): ' + E.ClassName + ': ' + E.Message);
  Halt(1);
end;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); end;
function Road(const Kind: string; A, B: TPointF): TVectArtPathData;
begin
  Result := Default(TVectArtPathData);
  Result.MapElement := Kind; Result.Name := Kind; Result.Visible := True;
  Result.Opacity := 1; Result.StrokeWidth := 24; Result.StrokeColor := clWhite;
  Result.LineCap := vlcRound;
  SetLength(Result.Vertices, 2);
  Result.Vertices[0].Position := A; Result.Vertices[1].Position := B;
end;
procedure CheckCrossingGaps;
const Kinds: array[0..4] of TMapRakuCrossingKind =
  (mckOverpass,mckBridge,mckRailOverpass,mckUnderpass,mckTunnel);
  Elements: array[0..2] of string = ('road','jr','rail');
var D, Restored: TVectArtDocument; B, Exported: TVectArtRenderBuffer;
  Lower, Upper: TVectArtPathLayer; Data: TVectArtPathData;
  Kind: TMapRakuCrossingKind; Element: string; Reverse: Integer;
  Image: ISkImage; Surface: ISkSurface; Svg: ISkSVGDOM; Info: TSkImageInfo;
  FileName, Error: string; Group: TMapRakuGroupLayer;
  procedure VerifyPixels(Buffer: TVectArtRenderBuffer; const LabelText: string);
  var X: Integer;
  begin
    for X in [-20,20] do
      Check(Buffer.Pixels[150*400+200+X].A=0,LabelText+': lower path gap');
    Check(Buffer.Pixels[150*400+260].A>240,LabelText+': lower path resumes');
    Check((Buffer.Pixels[150*400+200].A>=185) and
      (Buffer.Pixels[150*400+200].A<=200),
      LabelText+': no lower paint behind translucent upper path');
  end;
begin
  B:=TVectArtRenderBuffer.Create; Exported:=TVectArtRenderBuffer.Create;
  try
    for Kind in Kinds do for Element in Elements do for Reverse:=0 to 1 do begin
      D:=TVectArtDocument.Create; Restored:=TVectArtDocument.Create;
      try
        D.CanvasLayer.Width:=400; D.CanvasLayer.Height:=300;
        D.CanvasLayer.Transparent:=True;
        Data:=Road(Element,PointF(-160,0),PointF(160,0));
        Data.StrokeColor:=clRed; D.InsertPath(1,Data);
        Lower:=TVectArtPathLayer(D[1]);
        Data:=Road('road',PointF(0,-120),PointF(0,120));
        Data.Opacity:=0.5;
        if Reverse=0 then D.InsertPath(2,Data) else D.InsertPath(1,Data);
        Upper:=TVectArtPathLayer(D[2-Reverse]);
        D.SetCrossingRelation(Lower.PersistentId,Upper.PersistentId,Kind,Upper.PersistentId);
        RenderVectArtDocument(D,B,400,300);
        VerifyPixels(B,'screen '+IntToStr(Ord(Kind))+' '+Element);
        Check(TryDeserializeVectArtDocument(SerializeVectArtDocument(D),Restored,Error),Error);
        RenderVectArtDocument(Restored,B,400,300); VerifyPixels(B,'JSON');
        FileName:='TestOutput/crossing-'+IntToStr(Ord(Kind))+'-'+Element+'-'+IntToStr(Reverse);
        ExportMapPng(D,FileName+'.png'); ExportMapSvg(D,FileName+'.svg');
        Exported.SetSize(400,300);
        Info:=TSkImageInfo.Create(400,300,TSkColorType.RGBA8888,TSkAlphaType.Unpremul);
        Image:=TSkImage.MakeFromEncodedFile(FileName+'.png');
        Check(Image.ReadPixels(Info,Exported.Data,Exported.Stride),'PNG read');
        VerifyPixels(Exported,'PNG');
        Svg:=TSkSVGDOM.MakeFromFile(FileName+'.svg');
        Check(Svg<>nil,'SVG parse');
        Surface:=TSkSurface.MakeRaster(400,300); Surface.Canvas.Clear(TAlphaColorRec.Null);
        Svg.Render(Surface.Canvas);
        Check(Surface.ReadPixels(Info,Exported.Data,Exported.Stride),'SVG read');
        VerifyPixels(Exported,'SVG');
        Check(not TFile.ReadAllText(FileName+'.svg').Contains('<image'),
          'Crossing SVG must remain vector data');
        // 関係がなくなった・上側が非表示になったとき、古い切れ目を残さない。
        Upper.Visible:=False; RenderVectArtDocument(D,B,400,300);
        Check(B.Pixels[150*400+200].A>240,'Hidden upper must not cut lower');
        Upper.Visible:=True;
        Data:=Road('road',PointF(180,-120),PointF(180,120));
        D.SetPathVertices(2-Reverse,Data.Vertices);
        RenderVectArtDocument(D,B,400,300);
        Check(B.Pixels[150*400+200].A>240,'Moved crossing must release old gap');
      finally Restored.Free; D.Free; end;
    end;
    // 道路が線路の下になる場合も、線路の描画順に依存せず道路を切る。
    for Element in ['jr','rail'] do begin
      D:=TVectArtDocument.Create;
      try
        D.CanvasLayer.Width:=400; D.CanvasLayer.Height:=300;
        Data:=Road(Element,PointF(0,-120),PointF(0,120)); Data.StrokeColor:=clBlack;
        D.InsertPath(1,Data); Upper:=TVectArtPathLayer(D[1]);
        D.InsertPath(2,Road('road',PointF(-160,0),PointF(160,0)));
        Lower:=TVectArtPathLayer(D[2]);
        D.SetCrossingRelation(Upper.PersistentId,Lower.PersistentId,mckUnderpass,Upper.PersistentId);
        RenderVectArtDocument(D,B,400,300);
        Check(B.Pixels[150*400+220].A=0,'Road under railway must stop outside bridge mark');
        Check(B.Pixels[150*400+200].A>240,'Upper railway must remain continuous');
        // 背景を塗り潰さず、関係のない下層の図形を残す。
        Data:=Road('unrelated',PointF(-160,0),PointF(160,0));
        Data.MapElement:=''; Data.StrokeColor:=clBlue; D.InsertPath(1,Data);
        RenderVectArtDocument(D,B,400,300);
        Check((B.Pixels[150*400+220].B>240) and
          (B.Pixels[150*400+220].R<10),'Gap must preserve unrelated background');
      finally D.Free; end;
    end;
    // グループ内の経路も同じ永続IDで交差対象にする。
    D:=TVectArtDocument.Create;
    try
      D.CanvasLayer.Width:=400; D.CanvasLayer.Height:=300;
      D.InsertPath(1,Road('road',PointF(-160,0),PointF(160,0)));
      D.InsertPath(2,Road('road',PointF(0,-120),PointF(0,120)));
      Lower:=TVectArtPathLayer(D[1]); Upper:=TVectArtPathLayer(D[2]);
      D.SetCrossingRelation(Lower.PersistentId,Upper.PersistentId,mckOverpass,Upper.PersistentId);
      D.SetSelectedLayers([1,2]); GroupSelectedLayers(D,nil);
      Check(D[1] is TMapRakuGroupLayer,'Crossing group');
      Group:=TMapRakuGroupLayer(D[1]);
      RenderVectArtDocument(D,B,400,300);
      Check(B.Pixels[150*400+220].A=0,'Grouped crossing gap');
      D.RemoveCrossingRelation(Lower.PersistentId,Upper.PersistentId);
      RenderVectArtDocument(D,B,400,300);
      Check(B.Pixels[150*400+212].R>230,'Grouped same-level roads must join');
      Group.Visible:=False;
      Check(Length(CalculateMapRakuCrossings(D))=0,'Hidden group crossings');
    finally D.Free; end;
    Writeln('PASS: lower crossing gaps, both layer orders, transparent upper, PNG/SVG, JSON, hidden/moved paths, groups');
  finally Exported.Free; B.Free; end;
end;

procedure CheckCrossingAnglesAndSamples;
const Titles: array[0..5] of string = ('道路の平面交差','踏切（平面交差）',
  '道路が線路の上','道路が線路の下','道路同士の立体交差','トンネル');
var D: TVectArtDocument; B: TVectArtRenderBuffer; Data: TVectArtPathData;
  I, A, K: Integer; X,Y: Single; Lower,Upper: TVectArtPathLayer;
  Kind: TMapRakuCrossingKind;
  Layout: TMapRakuTextLayout;
begin
  B:=TVectArtRenderBuffer.Create; D:=TVectArtDocument.Create;
  try
    D.CanvasLayer.Width:=400; D.CanvasLayer.Height:=300;
    Data:=Road('road',PointF(-160,0),PointF(160,0)); Data.StrokeWidth:=80;
    D.InsertPath(1,Data); Lower:=TVectArtPathLayer(D[1]);
    Data:=Road('road',PointF(-120,-120),PointF(120,120)); D.InsertPath(2,Data);
    Upper:=TVectArtPathLayer(D[2]);
    D.SetCrossingRelation(Lower.PersistentId,Upper.PersistentId,mckOverpass,Upper.PersistentId);
    RenderVectArtDocument(D,B,400,300);
    Check(B.Pixels[150*400+228].A=0,'Wide oblique lower road gap');
    Check(B.Pixels[150*400+280].A>240,'Oblique lower road resumes');
    Data:=Road('road',PointF(0,-120),PointF(0,120));
    Data.Vertices[0].OutgoingSegment:=slskCubicBezier;
    Data.Vertices[0].OutgoingControl:=PointF(80,80);
    Data.Vertices[1].IncomingControl:=PointF(-80,-80);
    D.SetPathVertices(2,Data.Vertices);
    RenderVectArtDocument(D,B,400,300);
    Check(B.Pixels[150*400+220].A=0,'Curved upper road gap');
    Check(B.Pixels[150*400+200].A>240,'Curved upper road continuous');
    ExportMapPng(D,'TestOutput/crossing-curved.png');
    ExportMapSvg(D,'TestOutput/crossing-curved.svg');
    // 境界による自動判定とテーマ変更でも切り抜きを維持する。
    D.RemoveCrossingRelation(Lower.PersistentId,Upper.PersistentId);
    D.SetSelectedLayers([1]); InsertMapLevelBoundary(D,nil);
    ApplyMapTheme(D,nil,True);
    RenderVectArtDocument(D,B,400,300);
    Check(B.Pixels[150*400+220].A=0,'Automatic crossing on dark theme');
    ExportMapPng(D,'TestOutput/crossing-curved-dark.png');
  finally D.Free; B.Free; end;
  D:=TVectArtDocument.Create;
  try
    D.CanvasLayer.Width:=1080; D.CanvasLayer.Height:=660;
    for I:=0 to 5 do begin
      X:=-360+(I mod 3)*360; Y:=-140+(I div 3)*310;
      Data:=Road('road',PointF(X-135,Y),PointF(X+135,Y));
      if I=2 then begin Data.MapElement:='jr'; Data.StrokeColor:=clBlack; end;
      A:=D.InsertPath(D.LayerCount,Data); Lower:=TVectArtPathLayer(D[A]);
      Data:=Road('road',PointF(X,Y-100),PointF(X,Y+100));
      if I in [1,3,5] then begin Data.MapElement:='jr'; Data.StrokeColor:=clBlack; end;
      K:=D.InsertPath(D.LayerCount,Data); Upper:=TVectArtPathLayer(D[K]);
      case I of
        0: Kind:=mckNormal;
        1: Kind:=mckRailroadCrossing;
        3: Kind:=mckUnderpass;
        5: Kind:=mckTunnel;
      else Kind:=mckOverpass;
      end;
      D.SetCrossingRelation(Lower.PersistentId,Upper.PersistentId,Kind,Upper.PersistentId);
      Layout:=BuildMapRakuTextLayout(Titles[I],'Yu Gothic UI',22,0);
      D.InsertLayer(D.LayerCount,TMapRakuTextLayer.Create('説明',
        TRectF.Create(X-Layout.Width*0.5,Y-145,X+Layout.Width*0.5,Y-145+Layout.Height),
        Titles[I],'Yu Gothic UI',22,0,clBlack));
    end;
    ExportMapPng(D,'TestOutput/crossing-examples.png');
    ExportMapSvg(D,'TestOutput/crossing-examples.svg');
    SaveMapFile(D,'TestOutput/crossing-examples.mapraku');
  finally D.Free; end;
  Writeln('PASS: wide/oblique/curved paths, automatic crossings, dark theme');
end;

procedure RunMapTests;
var D, Restored, CrossingDoc: TVectArtDocument; H, LocalHistory: TVectArtEditHistory; S: TVectArtEditorState;
  R: TVectArtPathData; J, E: string;
  Creation: TVectArtShapeCreation; Buffer: TVectArtRenderBuffer; P: TVectArtRgbaPixel;
  I: Integer;
  ExceptionSink: TTestExceptionSink; Form: TMainForm; Bitmap: TBitmap; Png: TPngImage;
  Editor: TMapPathEditor; SnapPoint, Tangent: TPointF; SnapPath: TVectArtPathLayer;
  Crossings: TArray<TMapRakuCrossing>;
  CrossingGroups: TArray<TMapRakuCrossingGroup>;
  SavedId: string;
  PlainSvg: string;
  CrossingImageHash,PlainImageHash: UInt64;
begin
  ExceptionSink := TTestExceptionSink.Create;
  Application.OnException := ExceptionSink.HandleException;
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  CheckCrossingGaps;
  CheckCrossingAnglesAndSamples;
  D := TVectArtDocument.Create; Restored := TVectArtDocument.Create;
  CrossingDoc := TVectArtDocument.Create;
  H := TVectArtEditHistory.Create; LocalHistory:=TVectArtEditHistory.Create;
  S := TVectArtEditorState.Create;
  Creation := TVectArtShapeCreation.Create; Buffer := TVectArtRenderBuffer.Create;
  try
    D.CanvasLayer.Width := 800; D.CanvasLayer.Height := 600;
    R := Road('road', PointF(-300,0), PointF(300,0));
    InsertMapPath(D,H,R);
    Check((D.LayerCount=2) and (D[1] is TVectArtPathLayer), 'Road must create a path layer');
    H.Undo; Check(D.LayerCount=1,'Insert undo'); H.Redo;
    Check(TVectArtPathLayer(D[1]).MapElement='road','Redo metadata');
    D.SetSelectedLayers([1]);
    Editor:=TMapPathEditor.Create;
    try
      Editor.Configure(D,S,H,Rect(0,0,800,600),1);
      Check(Editor.MouseDown(mbLeft,[],400,300),'Insert road vertex');
      Check(Length(TVectArtPathLayer(D[1]).Vertices)=3,'Point not inserted');
      Check(Editor.KeyDown(Ord('P')),'Point Bezier mode');
      Check(TVectArtPathLayer(D[1]).Vertices[1].Kind=slvkBezier,'Bezier data');
      Check(Editor.MouseDown(mbRight,[],400,300),'Delete road vertex');
      Check(Length(TVectArtPathLayer(D[1]).Vertices)=2,'Point not removed');
      H.Undo; Check(Length(TVectArtPathLayer(D[1]).Vertices)=3,'Point deletion undo');
      H.Undo; H.Undo;
    finally Editor.Free; end;
    D.SetSelectedLayers([]);
    R := Road('road',PointF(0,-200),PointF(0,200)); InsertMapPath(D,H,R);
    Crossings := CalculateMapRakuCrossings(D);
    Check((Length(Crossings)=1) and (Crossings[0].Kind=mckNormal),
      'Same-level road crossing relation');
    RenderVectArtDocument(D,Buffer,800,600);
    P := Buffer.Pixels[300*800+412];
    Check((P.R>230) and (P.G>230),'Same-layer junction must not have a seam');
    D.SetSelectedLayers([1]); InsertMapLevelBoundary(D,H);
    Check((D.LayerCount=4) and (D[2] is TMapRakuLevelBoundaryLayer),
      'Boundary insertion');
    Crossings := CalculateMapRakuCrossings(D);
    Check((Length(Crossings)=1) and (Crossings[0].Kind=mckOverpass),
      'Different-level overpass relation');
    RenderVectArtDocument(D,Buffer,800,600);
    Check(Buffer.Pixels[300*800+400].R>230,
      'Automatic bridge marks must not cut the upper road body');
    CrossingImageHash:=0;
    for I:=0 to Buffer.PixelCount-1 do
      CrossingImageHash:=CrossingImageHash+Buffer.Pixels[I].R*3+
        Buffer.Pixels[I].G*5+Buffer.Pixels[I].B*7+Buffer.Pixels[I].A;
    D.SetCrossingRelation(D[1].PersistentId,D[3].PersistentId,mckNone,
      D[3].PersistentId);
    RenderVectArtDocument(D,Buffer,800,600); P := Buffer.Pixels[300*800+412];
    PlainImageHash:=0;
    for I:=0 to Buffer.PixelCount-1 do
      PlainImageHash:=PlainImageHash+Buffer.Pixels[I].R*3+
        Buffer.Pixels[I].G*5+Buffer.Pixels[I].B*7+Buffer.Pixels[I].A;
    // 上側経路本体は通常のレイヤー描画で連続させたまま、その外側に
    // 短い橋パーツだけを追加する。
    Check(CrossingImageHash<>PlainImageHash,
      'Automatic overpass must add bridge side marks');
    Check(P.R<180,'Separate levels must have visible edge');
    Crossings:=CalculateMapRakuCrossings(D);
    Check((Length(Crossings)=1) and (Crossings[0].Kind=mckNone),
      'Crossing expression override');
    SetMapCrossingRelation(D,H,D[1].PersistentId,D[3].PersistentId,
      mckBridge,D[3].PersistentId);
    Check(D.CrossingRelations[0].Kind=mckBridge,'Crossing command');
    H.Undo;
    Check(D.CrossingRelations[0].Kind=mckNone,'Crossing command undo');
    SavedId := D[1].PersistentId;
    J := SerializeVectArtDocument(D);
    Check(TryDeserializeVectArtDocument(J,Restored,E),'JSON: '+E);
    Check(Restored[2] is TMapRakuLevelBoundaryLayer,'JSON boundary role');
    Check(Restored[1].PersistentId=SavedId,'Persistent layer ID');
    Check((Restored.CrossingRelationCount=1) and
      (Restored.CrossingRelations[0].Kind=mckNone),
      'Persistent crossing relation');
    CrossingDoc.InsertPath(1, Road('road',PointF(-250,0),PointF(250,0)));
    InsertMapPath(CrossingDoc,nil,
      Road('jr',PointF(-60,-150),PointF(-60,150)));
    InsertMapPath(CrossingDoc,nil,
      Road('rail',PointF(60,-150),PointF(60,150)));
    Check(TVectArtPathLayer(CrossingDoc[2]).StrokeColor=clBlack,
      'JR initial color must match the light canvas theme');
    RenderVectArtDocument(CrossingDoc,Buffer,800,600);
    Check((Buffer.Pixels[244*800+371].A>0) and
      (Buffer.Pixels[244*800+371].R<160),
      'JR outer band must remain visible');
    Crossings := CalculateMapRakuCrossings(CrossingDoc);
    CrossingGroups := GroupMapRakuRailCrossings(Crossings);
    Check((Length(Crossings)=2) and (Length(CrossingGroups)=1) and
      (Length(CrossingGroups[0].TargetIds)=2), 'Grouped multi-track crossing');
    R := Road('rail',PointF(300,-150),PointF(300,150));
    CrossingDoc.SetPathVertices(3,R.Vertices);
    Crossings := CalculateMapRakuCrossings(CrossingDoc);
    Check(Length(Crossings)=1,'Crossing relation must disappear after edit');
    CrossingDoc.SetCrossingRelation(CrossingDoc[1].PersistentId,
      CrossingDoc[2].PersistentId,mckRailOverpass,
      CrossingDoc[1].PersistentId);
    RenderVectArtDocument(CrossingDoc,Buffer,800,600);
    Check(Buffer.Pixels[296*800+375].R>220,
      'Road over rail must retain the full road width');
    CrossingDoc.RemoveCrossingRelation(CrossingDoc[1].PersistentId,
      CrossingDoc[2].PersistentId);
    RenderVectArtDocument(CrossingDoc,Buffer,800,600);
    CrossingImageHash:=0;
    for I:=0 to Buffer.PixelCount-1 do
      CrossingImageHash:=CrossingImageHash+Buffer.Pixels[I].R*3+
        Buffer.Pixels[I].G*5+Buffer.Pixels[I].B*7+Buffer.Pixels[I].A;
    CrossingDoc.SetCrossingRelation(CrossingDoc[1].PersistentId,
      CrossingDoc[2].PersistentId,mckRailOverpass,CrossingDoc[2].PersistentId);
    RenderVectArtDocument(CrossingDoc,Buffer,800,600);
    PlainImageHash:=0;
    for I:=0 to Buffer.PixelCount-1 do
      PlainImageHash:=PlainImageHash+Buffer.Pixels[I].R*3+
        Buffer.Pixels[I].G*5+Buffer.Pixels[I].B*7+Buffer.Pixels[I].A;
    Check(CrossingImageHash<>PlainImageHash,'Crossing expression rendering');
    R:=Road('stairs-up',PointF(-120,180),PointF(120,180));
    R.StrokeWidth:=18; CrossingDoc.InsertPath(CrossingDoc.LayerCount,R);
    RenderVectArtDocument(CrossingDoc,Buffer,800,600);
    P:=Buffer.Pixels[400*800+400];
    Check(P.A>0,'Stair rendering');
    Check(TryDeserializeVectArtDocument(SerializeVectArtDocument(CrossingDoc),
      Restored,E),'Stair JSON: '+E);
    Check((Restored[Restored.LayerCount-1] is TVectArtPathLayer) and
      (TVectArtPathLayer(Restored[Restored.LayerCount-1]).MapElement='stairs-up'),
      'Stair type persistence');
    SetMapStairStepCount(CrossingDoc,LocalHistory,
      TVectArtPathLayer(CrossingDoc[4]),10);
    Check(TVectArtPathLayer(CrossingDoc[4]).MapStepCount=10,'Manual stair steps');
    LocalHistory.Undo;
    Check(TVectArtPathLayer(CrossingDoc[4]).MapStepCount=0,'Stair steps undo');
    R:=Road('pedestrian-bridge',PointF(-160,260),PointF(160,260));
    R.StrokeWidth:=18; InsertMapPath(CrossingDoc,nil,R);
    Check((CrossingDoc[5] is TMapRakuGroupLayer) and
      (TMapRakuGroupLayer(CrossingDoc[5]).ChildCount=3),
      'Pedestrian bridge composite');
    Check(TVectArtPathLayer(TMapRakuGroupLayer(CrossingDoc[5])[0]).MapElement=
      'stairs-up','Bridge start stairs');
    Check(TVectArtPathLayer(TMapRakuGroupLayer(CrossingDoc[5])[2]).MapElement=
      'stairs-down','Bridge end stairs');
    Check(Abs(TVectArtPathLayer(TMapRakuGroupLayer(CrossingDoc[5])[1]).Vertices[0].Position.X+160)<0.1,
      'Bridge body geometry');
    Check(TryDeserializeVectArtDocument(SerializeVectArtDocument(CrossingDoc),
      Restored,E),'Bridge JSON: '+E);
    Check(Restored[Restored.LayerCount-1] is TMapRakuGroupLayer,
      'Bridge group persistence');
    Check(not TryDeserializeVectArtDocument(StringReplace(J,'"MapRaku"','"Other"',[]),Restored,E),'Foreign app accepted');
    Check(Restored.LayerCount=6,'Invalid load must preserve document');
    J := StringReplace(J,'"road"','"invalid"',[rfReplaceAll]);
    Check(not TryDeserializeVectArtDocument(J,Restored,E),'Invalid road kind accepted');
    H.Undo; Check(D.LayerCount=3,'Boundary undo');
    H.Redo; Check(D[2] is TMapRakuLevelBoundaryLayer,'Boundary redo');
    ApplyMapTheme(D,H,True); Check(D.CanvasLayer.BackgroundColor=clBlack,'Dark theme');
    H.Undo; Check(D.CanvasLayer.BackgroundColor=clWhite,'Theme undo'); H.Redo;
    for I := 0 to 9 do begin InsertMapSymbol(D,H,I,IntToStr(I+1)); H.Undo; end;
    S.MapElement := 'jr'; S.CurrentTool := vetPath; S.LineStrokeWidth := 12;
    Creation.Configure(D,H,S,Rect(0,0,800,600),1);
    Creation.MouseDown(mbLeft,[],100,200); Creation.MouseDown(mbLeft,[],240,200);
    S.NextVertexKind := slvkBezier;
    Creation.MouseDown(mbLeft,[],350,150);
    Check(Creation.FinishPath(False),'Path finish');
    Check(S.CurrentTool=vetSelect,'Map tool must deselect');
    Check(TVectArtPathLayer(D[D.LayerCount-1]).MapElement='jr','Rail kind lost');
    R := Road('river',PointF(-250,-250),PointF(180,220)); InsertMapPath(D,H,R);
    InsertMapSymbol(D,H,0,'千里丘');
    ExportMapSvg(D,'TestOutput/map-scene-plain.svg');
    PlainSvg:=TFile.ReadAllText('TestOutput/map-scene-plain.svg',TEncoding.UTF8);
    SetMapCrossingRelation(D,H,D[1].PersistentId,D[3].PersistentId,
      mckBridge,D[3].PersistentId,24);
    ExportMapSvg(D,'TestOutput/map-scene.svg');
    ExportMapPng(D,'TestOutput/map-scene.png');
    J := TFile.ReadAllText('TestOutput/map-scene.svg', TEncoding.UTF8);
    Check(J.Contains('<svg') and J.Contains('<path'),'SVG vectors missing');
    Check(Length(J)<>Length(PlainSvg),'SVG crossing expression missing');
    Check(not J.Contains('<text'),'SVG text must be paths');
    SaveMapFile(D,'TestOutput/map-scene.mapraku');
    Check(NearestMapPath(D,PointF(120,3),8,False,'road',SnapPoint,Tangent,SnapPath),'Road snap');
    Check(Abs(SnapPoint.Y)<0.1,'Road snap must reach center path');
    Form := TMainForm.Create(nil);
    try
      Form.SetBounds(0,0,1440,900); Form.EnableStandaloneFileActions;
      Check(TryDeserializeVectArtDocument(SerializeVectArtDocument(D),Form.Document,E),'UI document: '+E);
      Check(Form.CloseQuery, 'Debug close must not prompt for unsaved changes');
      Form.HandleNeeded;
      Bitmap := TBitmap.Create; Png := TPngImage.Create;
      try
        Bitmap.SetSize(Form.ClientWidth,Form.ClientHeight);
        Form.PaintTo(Bitmap.Canvas.Handle,0,0);
        Png.Assign(Bitmap); Png.SaveToFile('TestOutput/editor.png');
      finally Png.Free; Bitmap.Free; end;
    finally Form.Free; end;
    Writeln('PASS: insertion, undo/redo, same-level junction, level boundary, crossing relations, stairs, JSON validation, themes, symbols, path finish, SVG/PNG');
  finally
    Buffer.Free; Creation.Free; S.Free; LocalHistory.Free; H.Free; CrossingDoc.Free;
    Restored.Free; D.Free;
    TTextRendererSkiaRuntime.Release;
    Application.OnException := nil; ExceptionSink.Free;
  end;
end;
end.
