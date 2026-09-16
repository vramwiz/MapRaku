// 下側の切断と橋の連結を、画面・PNG・SVGの画素で検証する。
unit MapRakuCrossingTests;
interface
procedure CheckJoinedBridges;
procedure CheckCrossingGaps;
procedure CheckCrossingAnglesAndSamples;
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
procedure CheckJoinedBridges;
var Spans: TArray<TMapRakuBridgeSpan>; Span: TMapRakuBridgeSpan;
  D: TVectArtDocument; B,E: TVectArtRenderBuffer; Data: TVectArtPathData;
  Upper: TVectArtPathLayer; I: Integer; Info: TSkImageInfo;
  Surface: ISkSurface; Svg: ISkSVGDOM; Image: ISkImage;
  procedure CheckPixels(Buffer: TVectArtRenderBuffer; const Output: string);
  begin
    Check((Buffer.Pixels[200*500+266].A>=120) and
      (Buffer.Pixels[200*500+266].A<=136),Output+': one continuous side mark');
    Check(Buffer.Pixels[200*500+269].A=0,Output+': no interior bridge flare');
    Check(Buffer.Pixels[173*500+270].A=0,Output+': first lower road stays cut');
    Check(Buffer.Pixels[227*500+270].A=0,Output+': second lower road stays cut');
  end;
begin
  Span:=Default(TMapRakuBridgeSpan); Span.UpperObjectId:='upper';
  Span.StartDistance:=50; Span.EndDistance:=70; AddMapBridgeSpan(Spans,Span);
  Span.StartDistance:=0; Span.EndDistance:=20; AddMapBridgeSpan(Spans,Span);
  Span.StartDistance:=27; Span.EndDistance:=43; AddMapBridgeSpan(Spans,Span);
  Check((Length(Spans)=1) and (Spans[0].StartDistance=0) and
    (Spans[0].EndDistance=70),'Bridge intervals merge transitively in any order');
  Span.StartDistance:=100; Span.EndDistance:=120; AddMapBridgeSpan(Spans,Span);
  Check(Length(Spans)=2,'Distant bridges remain separate');
  Span.UpperObjectId:='another'; Span.StartDistance:=10; Span.EndDistance:=20;
  AddMapBridgeSpan(Spans,Span); Check(Length(Spans)=3,'Different upper paths remain separate');
  Span.UpperObjectId:='upper'; Span.Underpass:=True;
  AddMapBridgeSpan(Spans,Span); Check(Length(Spans)=4,'Different mark styles remain separate');
  D:=TVectArtDocument.Create; B:=TVectArtRenderBuffer.Create; E:=TVectArtRenderBuffer.Create;
  try
    D.CanvasLayer.Width:=500; D.CanvasLayer.Height:=400; D.CanvasLayer.Transparent:=True;
    D.InsertPath(1,Road('road',PointF(-210,-27),PointF(210,-27)));
    D.InsertPath(2,Road('road',PointF(-210,27),PointF(210,27)));
    Data:=Road('jr',PointF(0,-170),PointF(0,170)); Data.StrokeColor:=clBlack; Data.Opacity:=0.5;
    D.InsertPath(3,Data); Upper:=TVectArtPathLayer(D[3]);
    for I:=1 to 2 do D.SetCrossingRelation(D[I].PersistentId,Upper.PersistentId,
      mckRailOverpass,Upper.PersistentId);
    RenderVectArtDocument(D,B,500,400); CheckPixels(B,'screen');
    ExportMapPng(D,'TestOutput/joined-bridge-check.png');
    ExportMapSvg(D,'TestOutput/joined-bridge-check.svg');
    E.SetSize(500,400); Info:=TSkImageInfo.Create(500,400,TSkColorType.RGBA8888,TSkAlphaType.Unpremul);
    Image:=TSkImage.MakeFromEncodedFile('TestOutput/joined-bridge-check.png');
    Check(Image.ReadPixels(Info,E.Data,E.Stride),'Joined bridge PNG read'); CheckPixels(E,'PNG');
    Svg:=TSkSVGDOM.MakeFromFile('TestOutput/joined-bridge-check.svg');
    Surface:=TSkSurface.MakeRaster(500,400); Surface.Canvas.Clear(TAlphaColorRec.Null);
    Svg.Render(Surface.Canvas); Check(Surface.ReadPixels(Info,E.Data,E.Stride),'Joined bridge SVG read');
    CheckPixels(E,'SVG');
    Data:=Road('road',PointF(-210,100),PointF(210,100)); D.SetPathVertices(2,Data.Vertices);
    RenderVectArtDocument(D,B,500,400);
    Check(B.Pixels[210*500+266].A=0,'Moving a road apart separates bridge spans again');
    // 添付図に近い斜交の連続橋。元の経路を保持したまま側線を一続きにする。
    Data:=Road('road',PointF(-220,10),PointF(220,-78)); D.SetPathVertices(1,Data.Vertices);
    Data:=Road('road',PointF(-220,78),PointF(220,-10)); D.SetPathVertices(2,Data.Vertices);
    for I:=1 to 2 do begin TVectArtPathLayer(D[I]).StrokeWidth:=32;
      TVectArtPathLayer(D[I]).StrokeColor:=$00E0E0E0; end;
    Data:=Road('jr',PointF(-100,-180),PointF(100,180)); D.SetPathVertices(3,Data.Vertices);
    Upper.Opacity:=1; Upper.StrokeWidth:=18; D.CanvasLayer.Transparent:=False;
    ExportMapPng(D,'TestOutput/joined-bridges.png'); ExportMapSvg(D,'TestOutput/joined-bridges.svg');
    SaveMapFile(D,'TestOutput/joined-bridges.mapraku');
  finally E.Free; B.Free; D.Free; end;
  Writeln('PASS: continuous bridge sides, no interior flares, transitive joins, separate paths/styles, screen/PNG/SVG, lower gaps, moving apart');
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

end.
