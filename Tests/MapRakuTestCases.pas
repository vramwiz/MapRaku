// 地図固有の経路・層・保存・描画・作図操作を実データで検証する。
unit MapRakuTestCases;
interface
procedure RunMapTests;
procedure RunRouteDiagnostic(const FileName: string);
implementation
uses System.SysUtils, System.Types, System.Classes, System.IOUtils, System.JSON,
  System.Skia, System.UITypes, System.Math,
  Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  Vcl.Imaging.pngimage,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap,
  MapRakuDocument, MapRakuDocumentJson, MapRakuEditHistory, MapRakuEditorState,
  MapRakuMapCommands, MapRakuCrossings, MapRakuGroupCommands, MapRakuRenderer, MapRakuShapeCreation,
  MapRakuExport, MapRakuTheme, MapRakuSymbols, MapRakuMapPanel,
  MapRakuFile, MapRakuPathSnap, MapRakuLayerGeometry, MapRakuRouteProgress,
  MapRakuTextGeometry, MapRakuMainForm, MapRakuPathEditor, MapRakuPathOperations,
  MapRakuRecentFiles, MapRakuLayerList, MapRakuLayerRenderer,
  MapRakuPresetThumbnail,
  MapRakuProjectiveTransform, MapRakuSelectionGeometry, MapRakuTestSupport,
  MapRakuConnectionTests, MapRakuCrossingTests, MapRakuGenerationViewTests, MapRakuEditorRefreshTests;
type
  TTestLayerList = class(TVectArtLayerListControl)
  public
    procedure RightClickLayer(Layer: TVectArtLayer);
  end;
  TTestExceptionSink = class
    procedure HandleException(Sender: TObject; E: Exception);
  end;
procedure RunRouteDiagnostic(const FileName: string);
var D: TVectArtDocument; R: TMapRakuRouteProgressData;
  I: Integer; Error, RouteId: string; Valid: Boolean;
begin
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  D:=TVectArtDocument.Create;
  try
    Check(TryDeserializeVectArtDocument(TFile.ReadAllText(FileName,TEncoding.UTF8),D,Error),Error);
    for I:=1 to D.LayerCount-1 do
      if (D[I] is TVectArtPathLayer) and (TVectArtPathLayer(D[I]).MapElement='route') then
      begin
        RouteId:=MapRakuRouteIdentifier(TVectArtPathLayer(D[I]));
        Valid:=TryBuildMapRakuRoute(D,RouteId,R,Error);
        WriteMapRakuRouteDiagnostic(D,RouteId,Error);
        Writeln(Format('route=%s valid=%s %s',[RouteId,BoolToStr(Valid,True),Error]));
      end;
  finally D.Free; TTextRendererSkiaRuntime.Release; end;
end;
procedure TTestLayerList.RightClickLayer(Layer: TVectArtLayer);
var Renderer: TVectArtLayerRenderer; I: Integer; Bounds: TRect;
begin
  Renderer := TVectArtLayerRenderer.Create;
  try
    Renderer.Document := Document;
    Renderer.EditorState := EditorState;
    Renderer.PPI := CurrentPPI;
    Renderer.LayerIndexAt(ClientRect, 0);
    for I := 1 to 20 do
      if Renderer.LayerAt(I) = Layer then
      begin
        Bounds := Renderer.LayerItemRect(ClientRect, I);
        MouseDown(mbRight, [], 100, (Bounds.Top + Bounds.Bottom) div 2);
        MouseUp(mbRight, [], 100, (Bounds.Top + Bounds.Bottom) div 2);
        Exit;
      end;
    Check(False, 'Context menu test layer must have a visible row');
  finally
    Renderer.Free;
  end;
end;

procedure CheckContextMenuSelection;
var D: TVectArtDocument; S: TVectArtEditorState; Host: TForm;
  List: TTestLayerList; Group: TMapRakuGroupLayer;
begin
  D := TVectArtDocument.Create;
  S := TVectArtEditorState.Create;
  Host := TForm.CreateNew(nil);
  try
    List := TTestLayerList.Create(Host);
    List.Parent := Host;
    List.SetBounds(0, 0, 400, 800);
    List.Document := D;
    List.EditorState := S;
    D.InsertLayer(D.LayerCount, TVectArtRectangleLayer.Create('A', RectF(0,0,20,20), 0));
    D.InsertLayer(D.LayerCount, TVectArtRectangleLayer.Create('B', RectF(30,0,50,20), 0));
    D.InsertLayer(D.LayerCount, TVectArtRectangleLayer.Create('C', RectF(60,0,80,20), 0));
    D.SetSelectedLayers([1, 2]);
    Check(CanGroupCurrentSelection(D,S), 'Ctrl+G available before right click');
    List.RightClickLayer(D[1]);
    Check((D.SelectionCount=2) and CanGroupCurrentSelection(D,S),
      'Right click on selected row must preserve grouping selection');
    List.RightClickLayer(D[3]);
    Check((D.SelectionCount=1) and D.IsLayerSelected(3),
      'Right click on unselected row must select its target');
    Group := TMapRakuGroupLayer.Create('Group');
    Group.AddChild(TVectArtRectangleLayer.Create('Child A', RectF(0,0,20,20), 0));
    Group.AddChild(TVectArtRectangleLayer.Create('Child B', RectF(30,0,50,20), 0));
    Group.AddChild(TVectArtRectangleLayer.Create('Child C', RectF(60,0,80,20), 0));
    D.InsertLayer(D.LayerCount, Group);
    S.OpenGroup := Group;
    D.SetSelectedLayers([]);
    S.SetOpenGroupChildren([Group[0], Group[1]]);
    List.RightClickLayer(Group[0]);
    Check((S.OpenGroupChildCount=2) and CanGroupCurrentSelection(D,S),
      'Right click inside group must preserve grouping selection');
    List.RightClickLayer(Group[2]);
    Check((S.OpenGroupChildCount=1) and (S.OpenGroupChild=Group[2]),
      'Right click on unselected child must select its target');
  finally
    Host.Free;
    S.Free;
    D.Free;
  end;
end;

procedure TTestExceptionSink.HandleException(Sender: TObject; E: Exception);
begin
  Writeln('FAIL (VCL): ' + E.ClassName + ': ' + E.Message);
  Halt(1);
end;

procedure CheckRouteGapTolerance;
var D:TVectArtDocument; H:TVectArtEditHistory; Data:TVectArtPathData;
  Route:TMapRakuRouteProgressData; Error,Before:string;
  P,T:TPointF; Path:TVectArtPathLayer; V:TArray<TMapRakuVertex>;
begin
  D:=TVectArtDocument.Create; H:=TVectArtEditHistory.Create;
  try
    Data:=Road('route',PointF(-100,0),PointF(0,0)); Data.RouteId:='gap-test';
    D.InsertPath(1,Data);
    Data:=Road('route',PointF(8,0),PointF(100,0)); Data.RouteId:='gap-test';
    D.InsertPath(2,Data);
    PlaceMapSymbol(D,H,10,'start',PointF(-100,0),True);
    PlaceMapSymbol(D,H,11,'end',PointF(100,0),True);
    Before:=SerializeVectArtDocument(D);
    Check(TryBuildMapRakuRoute(D,'gap-test',Route,Error),'8px gap must connect: '+Error);
    Check(Length(Route.Samples)=4,'Both sides of gap must remain in the samples');
    Check(TryMapRakuRoutePosition(Route,52,P,T,Path) and (Abs(P.X-4)<0.001),
      'Preview interpolates smoothly across the gap');
    Check(SerializeVectArtDocument(D)=Before,'Route gap tolerance never changes document');
    V:=TVectArtPathLayer(D[2]).Vertices; V[0].Position:=PointF(12,0);
    TVectArtPathLayer(D[2]).Vertices:=V;
    Check(TryBuildMapRakuRoute(D,'gap-test',Route,Error),'12px boundary connects');
    V[0].Position:=PointF(12.1,0); TVectArtPathLayer(D[2]).Vertices:=V;
    Check(not TryBuildMapRakuRoute(D,'gap-test',Route,Error),'Distant paths stay disconnected');
    // 遠い候補を先に並べても、後にある完全一致の区間を優先する。
    V[0].Position:=PointF(4,0); TVectArtPathLayer(D[2]).Vertices:=V;
    Data:=Road('route',PointF(0,0),PointF(100,0)); Data.RouteId:='gap-test';
    D.InsertPath(D.LayerCount,Data);
    Path:=TVectArtPathLayer(D[D.LayerCount-1]);
    Check(TryBuildMapRakuRoute(D,'gap-test',Route,Error),'Multiple nearby candidates');
    Check(Route.Samples[High(Route.Samples)].Path=Path,'Exact endpoint beats earlier nearby path');
    Writeln('PASS: route gaps, 12px boundary, interpolation, nearest-first, no document changes');
  finally H.Free; D.Free; end;
end;
procedure CheckRouteFollowing;
const Kinds: array[0..3] of string = ('road','jr','rail','river');
var D: TVectArtDocument; S: TVectArtEditorState; H: TVectArtEditHistory;
  Creation: TVectArtShapeCreation; Data: TVectArtPathData;
  Source, Route: TVectArtPathLayer; Kind: string;
  Original, Section, Created: TArray<TMapRakuVertex>; A,B: TMapRakuRouteSnap;
  Preview: TArray<TPoint>; P,Q: TPointF; I,Direction: Integer; FoundCorner: Boolean;
  function CurvePoint(const V: TArray<TMapRakuVertex>; T: Single): TPointF;
  var U: Single;
  begin
    U:=1-T;
    Result:=V[0].Position*(U*U*U)+
      (V[0].Position+V[0].OutgoingControl)*(3*U*U*T)+
      (V[1].Position+V[1].IncomingControl)*(3*U*T*T)+V[1].Position*(T*T*T);
  end;
begin
  // 部分ベジェを近似折れ線にせず、同じ曲線として切り出す。
  Data:=Road('road',PointF(-100,0),PointF(100,0));
  Data.Vertices[0].OutgoingSegment:=slskCubicBezier;
  Data.Vertices[0].Kind:=slvkBezier; Data.Vertices[1].Kind:=slvkBezier;
  Data.Vertices[0].OutgoingControl:=PointF(40,120);
  Data.Vertices[1].IncomingControl:=PointF(-40,120);
  A:=Default(TMapRakuRouteSnap); A.PathId:='curve'; A.Vertices:=Data.Vertices;
  A.Parameter:=0.25; A.Point:=CurvePoint(A.Vertices,A.Parameter);
  B:=A; B.Parameter:=0.75; B.Point:=CurvePoint(B.Vertices,B.Parameter);
  for Direction:=0 to 1 do
  begin
    if Direction=0 then Section:=MapRouteSection(A,B) else Section:=MapRouteSection(B,A);
    Check((Length(Section)=2) and (Section[0].OutgoingSegment=slskCubicBezier),
      'Following retains a partial cubic segment');
    for I:=0 to 20 do
    begin
      P:=CurvePoint(Section,I/20);
      if Direction=0 then Q:=CurvePoint(Data.Vertices,0.25+0.5*I/20)
      else Q:=CurvePoint(Data.Vertices,0.75-0.5*I/20);
      Check(Hypot(P.X-Q.X,P.Y-Q.Y)<0.001,'Partial/reversed cubic must preserve geometry');
    end;
  end;
  B.PathId:='another-road';
  Check(Length(MapRouteSection(A,B))=0,'Different paths do not auto-follow');
  for Kind in Kinds do
  begin
    D:=TVectArtDocument.Create; S:=TVectArtEditorState.Create;
    H:=TVectArtEditHistory.Create; Creation:=TVectArtShapeCreation.Create;
    try
      D.CanvasLayer.Width:=800; D.CanvasLayer.Height:=600;
      Data:=Road(Kind,PointF(-100,-100),PointF(100,-100));
      SetLength(Data.Vertices,3);
      Data.Vertices[1].Position:=PointF(0,100);
      Data.Vertices[2].Position:=PointF(100,-100);
      D.InsertPath(1,Data); Source:=TVectArtPathLayer(D[1]);
      Original:=CloneMapRakuPathVertices(Source.Vertices);
      for Direction:=0 to 1 do
      begin
        S.MapElement:='route'; S.CurrentTool:=vetPath; S.NextVertexKind:=slvkSharp;
        Creation.Configure(D,H,S,Rect(0,0,800,600),1);
        if Direction=0 then
        begin
          Creation.MouseDown(mbLeft,[],300,200);
          Creation.MouseMove([],500,200);
        end
        else begin
          Creation.MouseDown(mbLeft,[],500,200);
          Creation.MouseMove([],300,200);
        end;
        Check(Creation.PreviewPath(Preview),'Following preview exists');
        FoundCorner:=False;
        for I:=0 to High(Preview) do
          if (Preview[I].X=400) and (Preview[I].Y=400) then FoundCorner:=True;
        Check(FoundCorner,'Preview follows intermediate road corner');
        if Direction=0 then Creation.MouseDown(mbLeft,[],500,200)
        else Creation.MouseDown(mbLeft,[],300,200);
        Check(Creation.FinishPath(False),'Finish following route');
        Route:=TVectArtPathLayer(D[2]);
        Check((Length(Route.Vertices)=3) and
          (Route.Vertices[1].Position=PointF(0,100)),Kind+': route follows source corner');
        Check(MapRakuPathVerticesEqual(Source.Vertices,Original),'Source remains unchanged');
        Created:=CloneMapRakuPathVertices(Route.Vertices);
        H.Undo; Check(D.LayerCount=2,'Following route undone in one operation');
        H.Redo; Check(D.LayerCount=3,'Following route redo');
        Check(MapRakuPathVerticesEqual(TVectArtPathLayer(D[2]).Vertices,Created),
          'Redo restores following geometry');
        H.Undo;
      end;
      S.MapElement:='route'; S.CurrentTool:=vetPath;
      Creation.Configure(D,H,S,Rect(0,0,800,600),1);
      Creation.MouseDown(mbLeft,[],300,200);
      Creation.MouseMove([ssAlt],500,200);
      Check(Creation.PreviewPath(Preview),'Alt preview exists');
      Check(Length(Preview)=2,'Alt preview is free straight segment');
      Creation.MouseDown(mbLeft,[ssAlt],500,200);
      Creation.FinishPath(False);
      Check(Length(TVectArtPathLayer(D[2]).Vertices)=2,'Alt disables following');
      H.Undo;
      Data:=Road(Kind,PointF(-100,0),PointF(100,0));
      Data.Vertices[0].OutgoingSegment:=slskCubicBezier;
      Data.Vertices[0].Kind:=slvkBezier; Data.Vertices[1].Kind:=slvkBezier;
      Data.Vertices[0].OutgoingControl:=PointF(40,120);
      Data.Vertices[1].IncomingControl:=PointF(-40,120);
      Source.Vertices:=Data.Vertices;
      Creation.MouseDown(mbLeft,[],300,300);
      Creation.MouseDown(mbLeft,[],400,390);
      Creation.MouseMove([],500,300);
      Check(Creation.PreviewPath(Preview) and (Length(Preview)>3),
        'Cubic following preview includes the actual curve');
      Creation.MouseDown(mbLeft,[],500,300);
      Check(Creation.FinishPath(False),'Finish multi-click cubic following');
      Route:=TVectArtPathLayer(D[2]);
      Check((Length(Route.Vertices)=3) and
        (Route.Vertices[0].OutgoingSegment=slskCubicBezier) and
        (Route.Vertices[1].OutgoingSegment=slskCubicBezier),
        'Successive snapped clicks retain split cubic segments');
      for P in FlattenMapRakuPathVertices(Route.Vertices,32) do
        Check(MapRakuPathDistanceToPoint(Data.Vertices,P)<0.5,
          'Created cubic route follows source');
      H.Undo;
      D.InsertPath(2,Road(Kind,PointF(-100,-180),PointF(100,-180)));
      Creation.MouseDown(mbLeft,[],300,300);
      Creation.MouseDown(mbLeft,[],500,120);
      Creation.FinishPath(False);
      Check((Length(TVectArtPathLayer(D[3]).Vertices)=2) and
        (TVectArtPathLayer(D[3]).Vertices[0].OutgoingSegment=slskLine),
        'Switching target objects uses normal route drawing');
    finally Creation.Free; H.Free; S.Free; D.Free; end;
  end;
  Writeln('PASS: route following, exact partial/reversed cubic, preview, four kinds, Alt, Undo/Redo');
end;

procedure CheckRouteSnapping;
const Kinds: array[0..3] of string = ('road','jr','rail','river');
var D: TVectArtDocument; S: TVectArtEditorState; H: TVectArtEditHistory;
  Editor: TMapPathEditor; Creation: TVectArtShapeCreation;
  Data: TVectArtPathData; Target, Route: TVectArtPathLayer;
  P: TPointF; Kind: string;
begin
  for Kind in Kinds do
  begin
    D:=TVectArtDocument.Create; S:=TVectArtEditorState.Create;
    H:=TVectArtEditHistory.Create; Editor:=TMapPathEditor.Create;
    Creation:=TVectArtShapeCreation.Create;
    try
      D.CanvasLayer.Width:=800; D.CanvasLayer.Height:=600;
      D.InsertPath(1,Road(Kind,PointF(-200,0),PointF(200,0)));
      Target:=TVectArtPathLayer(D[1]); Target.Locked:=True;
      Check(NearestMapRouteTarget(D,PointF(0,20),1,P) and (Abs(P.Y)<0.01),
        Kind+': route snaps to locked target centerline');
      Check(not NearestMapRouteTarget(D,PointF(0,25),1,P), 'Route snap limit');
      Check(NearestMapRouteTarget(D,PointF(0,40),0.5,P), 'Route snap zoom out');
      Check(not NearestMapRouteTarget(D,PointF(0,13),2,P), 'Route snap zoom in');
      Target.Visible:=False;
      Check(not NearestMapRouteTarget(D,PointF(0,10),1,P), 'Hidden target excluded');
      Target.Visible:=True; Target.Opacity:=0;
      Check(not NearestMapRouteTarget(D,PointF(0,10),1,P), 'Transparent target excluded');
      Target.Opacity:=1;
      Data:=Road(Kind,PointF(-200,0),PointF(200,0));
      Data.Vertices[0].Kind:=slvkBezier;
      Data.Vertices[1].Kind:=slvkBezier;
      Data.Vertices[0].OutgoingSegment:=slskCubicBezier;
      Data.Vertices[0].OutgoingControl:=PointF(133,80);
      Data.Vertices[1].IncomingControl:=PointF(-133,80);
      Target.Vertices:=Data.Vertices;
      Check(NearestMapRouteTarget(D,PointF(0,78),1,P) and
        (Abs(P.X)<1) and (Abs(P.Y-60)<1),'Route snaps to curved centerline');
      Data:=Road(Kind,PointF(-200,0),PointF(200,0));
      Target.Vertices:=Data.Vertices;
      S.MapElement:='route'; S.CurrentTool:=vetLine;
      Creation.Configure(D,H,S,Rect(0,0,800,600),1);
      Creation.MouseDown(mbLeft,[],350,320);
      Creation.MouseUp(mbLeft,[],450,320);
      Check(D.LayerCount=3,'Route created');
      Route:=TVectArtPathLayer(D[2]);
      Check((Abs(Route.Vertices[0].Position.Y)<0.01) and
        (Abs(Route.Vertices[1].Position.Y)<0.01),'Created route follows centerline');
      D.SelectedIndex:=2; S.CurrentTool:=vetSelect;
      Editor.Configure(D,S,H,Rect(0,0,800,600),1);
      Check(Editor.MouseDown(mbLeft,[],450,300),'Pick route endpoint');
      Editor.MouseMove([],500,320); Editor.MouseUp;
      Check(Abs(Route.Vertices[1].Position.Y)<0.01,'Dragged route snaps');
      H.Undo;
      Check(Abs(Route.Vertices[1].Position.X-50)<0.01,'Route snap undo');
      Editor.Configure(D,S,H,Rect(0,0,800,600),1);
      Check(Editor.MouseDown(mbLeft,[],450,300),'Pick route for Alt drag');
      Editor.MouseMove([ssAlt],500,320); Editor.MouseUp;
      Check(Abs(Route.Vertices[1].Position.Y-20)<0.01,'Alt bypasses route snap');
      Check((Target.Vertices[0].Position.X=-200) and
        (Target.Vertices[1].Position.X=200),'Route snapping never edits target');
      Target.Visible:=False;
      Check(not NearestMapRouteTarget(D,PointF(0,0),1,P),'Other routes excluded');
    finally
      Creation.Free; Editor.Free; H.Free; S.Free; D.Free;
    end;
  end;
  Writeln('PASS: route centerline snapping, four target kinds, zoom, visibility, Alt, creation, drag, Undo');
end;

procedure CheckPresetThumbnailOrientation;
var Layer: TMapRakuGroupLayer; Buffer: TVectArtRenderBuffer;
  Bitmap: TBitmap; Pixel: TVectArtRgbaPixel; Expected: TColor;
  Symbol, X, Y: Integer; A: Cardinal;
begin
  Buffer := TVectArtRenderBuffer.Create;
  try
    for Symbol := 0 to 9 do
    begin
      Layer := CreateMapSymbol(Symbol, MapSymbolDefaultLabel(Symbol));
      try
        RenderVectArtLayerThumbnail(Layer, Buffer, 64, 42);
        Bitmap := CreateMapPresetThumbnail(Layer, 64, 42, clWhite);
        try
          for Y := 0 to 41 do
            for X := 0 to 63 do
            begin
              Pixel := Buffer.Pixels[Y * 64 + X];
              A := Pixel.A;
              Expected := ((Cardinal(Pixel.R)*A + 255*(255-A) + 127) div 255) or
                (((Cardinal(Pixel.G)*A + 255*(255-A) + 127) div 255) shl 8) or
                (((Cardinal(Pixel.B)*A + 255*(255-A) + 127) div 255) shl 16);
              Check(ColorToRGB(Bitmap.Canvas.Pixels[X,Y]) = Expected,
                Format('Symbol %d thumbnail orientation at %d,%d', [Symbol,X,Y]));
            end;
        finally Bitmap.Free; end;
      finally Layer.Free; end;
    end;
    Writeln('PASS: all symbol thumbnails match renderer orientation and colors');
  finally Buffer.Free; end;
end;

procedure CheckRiverLineCaps;
var D: TVectArtDocument; B: TVectArtRenderBuffer; Data: TVectArtPathData;
  Cap: TVectArtLineCap; Info: TSkImageInfo; Image: ISkImage;
  Svg: ISkSVGDOM; Surface: ISkSurface; FileName: string;
  procedure CheckPixels(const Output: string);
  var X: Integer;
  begin
    Check((B.Pixels[100*300+150].A>=126) and
      (B.Pixels[100*300+150].A<=129), Output+': river opacity');
    for X in [62, 237] do
      Check((B.Pixels[82*300+X].A>100) = (Cap=vlcSquare),
        Output+': square river cap corners');
    for X in [66, 233] do
      Check((B.Pixels[90*300+X].A>100) = (Cap<>vlcTriangle),
        Output+': round versus triangular river cap');
    for X in [65, 234] do
      Check(B.Pixels[100*300+X].A>100, Output+': river cap tip');
  end;
begin
  D:=TVectArtDocument.Create; B:=TVectArtRenderBuffer.Create;
  try
    D.CanvasLayer.Width:=300; D.CanvasLayer.Height:=200;
    D.CanvasLayer.Transparent:=True;
    Data:=Road('river', PointF(-70,0), PointF(70,0));
    Data.StrokeWidth:=40; Data.Opacity:=0.5;
    D.InsertPath(1,Data);
    B.SetSize(300,200);
    Info:=TSkImageInfo.Create(300,200,TSkColorType.RGBA8888,TSkAlphaType.Unpremul);
    for Cap:=Low(TVectArtLineCap) to High(TVectArtLineCap) do
    begin
      TVectArtPathLayer(D[1]).LineCap:=Cap;
      RenderVectArtDocument(D,B,300,200); CheckPixels('screen');
      FileName:='TestOutput/river-cap-'+IntToStr(Ord(Cap));
      ExportMapPng(D,FileName+'.png'); ExportMapSvg(D,FileName+'.svg');
      Image:=TSkImage.MakeFromEncodedFile(FileName+'.png');
      Check(Image.ReadPixels(Info,B.Data,B.Stride),'Read river PNG');
      CheckPixels('PNG');
      Svg:=TSkSVGDOM.MakeFromFile(FileName+'.svg');
      Surface:=TSkSurface.MakeRaster(300,200);
      Surface.Canvas.Clear(TAlphaColorRec.Null); Svg.Render(Surface.Canvas);
      Check(Surface.ReadPixels(Info,B.Data,B.Stride),'Read river SVG');
      CheckPixels('SVG');
    end;
    Writeln('PASS: river square/round/triangle caps, both endpoints, opacity, screen/PNG/SVG');
  finally
    B.Free; D.Free;
  end;
end;

procedure RunMapTests;
var D, Restored, CrossingDoc, ColorDoc, ColorRestored, PaletteDoc: TVectArtDocument; H, LocalHistory: TVectArtEditHistory; S: TVectArtEditorState;
  R: TVectArtPathData; J, E: string;
  Creation: TVectArtShapeCreation; Buffer: TVectArtRenderBuffer; P: TVectArtRgbaPixel;
  I: Integer;
  ExceptionSink: TTestExceptionSink; Form: TMainForm; Bitmap: TBitmap; Png: TPngImage;
  Editor: TMapPathEditor; SnapPoint, Tangent: TPointF; SnapPath: TVectArtPathLayer;
  VertexIndex, SegmentIndex: Integer; SegmentT: Single;
  Crossings: TArray<TMapRakuCrossing>;
  CrossingGroups: TArray<TMapRakuCrossingGroup>;
  SavedId: string;
  PlainSvg: string;
  CrossingImageHash,PlainImageHash: UInt64;
  FromSelectedObject: Boolean;
  SymbolLayer: TMapRakuGroupLayer;
  SymbolBounds: TRectF;
  RouteLayer: TVectArtPathLayer;
  RouteMarker: TMapRakuGroupLayer;
  RouteProgress: TMapRakuRouteProgressData;
  PixelIndex: Integer;
  HasSymbolPixels: Boolean;
  SelectionGeometry: TVectArtSelectionGeometry;
  PanelDoc: TVectArtDocument;
  PanelState: TVectArtEditorState;
  PanelForm: TForm;
  Panel: TMapToolsPanel;
  CategoryBox: TComboBox;
  Gallery: TScrollBox;
  FirstPresetButton: TMapPresetButton;
  WheelHandled: Boolean;
  RecentFiles, ReloadedRecentFiles: TMapRakuRecentFiles;
  RecentIni, MovedRecentFile: string;
begin
  ExceptionSink := TTestExceptionSink.Create;
  Application.OnException := ExceptionSink.HandleException;
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  TDirectory.CreateDirectory('TestOutput');
  CheckContextMenuSelection;
  CheckRiverLineCaps;
  CheckPresetThumbnailOrientation;
  CheckRouteSnapping;
  CheckRouteFollowing;
  CheckRouteGapTolerance;
  CheckGenerationReferenceView;
  CheckEditorRefresh;
  RecentIni := TPath.GetFullPath('TestOutput/recent-files-test.ini');
  RecentFiles := TMapRakuRecentFiles.Create;
  ReloadedRecentFiles := TMapRakuRecentFiles.Create;
  try
    for I := 0 to 11 do
      RecentFiles.Touch(TPath.Combine('TestOutput',
        'recent-' + IntToStr(I) + '.mapraku'));
    Check((RecentFiles.Count = 10) and
      RecentFiles[0].EndsWith('recent-11.mapraku'),
      'Recent files must keep the latest ten');
    MovedRecentFile := RecentFiles[5];
    RecentFiles.Touch(MovedRecentFile);
    Check((RecentFiles.Count = 10) and
      SameText(RecentFiles[0], MovedRecentFile),
      'Opening a recent file must move it to the top');
    RecentFiles.Save(RecentIni);
    ReloadedRecentFiles.Load(RecentIni);
    Check((ReloadedRecentFiles.Count = 10) and
      SameText(ReloadedRecentFiles[0], MovedRecentFile),
      'Recent files must survive application restart');
  finally
    RecentFiles.Free;
    ReloadedRecentFiles.Free;
    if TFile.Exists(RecentIni) then TFile.Delete(RecentIni);
  end;
  SelectionGeometry := BuildSelectionGeometry(Rect(100,100,200,180),
    SelectionFrameOffset(0,1));
  Check(HitTestSelectionHandle(Point(94,135),SelectionGeometry)=vshLeft,
    'Selection frame edge must resize');
  Check(HitTestSelectionHandle(Point(100,135),SelectionGeometry)=vshNone,
    'Object edge must not resize');
  Check(HitTestSelectionHandle(Point(94,94),SelectionGeometry)=vshTopLeft,
    'Selection frame corner must resize');
  PanelForm:=TForm.CreateNew(nil);
  PanelForm.SetBounds(0,0,500,400);
  PanelDoc:=TVectArtDocument.Create;
  PanelState:=TVectArtEditorState.Create;
  try
    Panel:=TMapToolsPanel.CreateTools(PanelForm,PanelDoc,PanelState,nil,PanelForm);
    CategoryBox:=nil; Gallery:=nil;
    for I:=0 to Panel.ControlCount-1 do begin
      if Panel.Controls[I] is TComboBox then CategoryBox:=TComboBox(Panel.Controls[I]);
      if Panel.Controls[I] is TScrollBox then Gallery:=TScrollBox(Panel.Controls[I]);
    end;
    Check((CategoryBox<>nil) and (Gallery<>nil),'Placement category controls');
    Check((CategoryBox.ItemIndex=0) and (Gallery.ControlCount>40) and
      (PanelState.ActiveMapPreset=0) and (PanelState.MapElement='road'),
      'All category must show every preset and activate the first');
    FirstPresetButton:=nil;
    for I:=0 to Gallery.ControlCount-1 do
      if Gallery.Controls[I] is TMapPresetButton then begin
        FirstPresetButton:=TMapPresetButton(Gallery.Controls[I]);
        Break;
      end;
    Check(FirstPresetButton<>nil,'Placement preset button');
    WheelHandled:=False;
    FirstPresetButton.OnMouseWheel(FirstPresetButton,[],-120,
      Point(0,0),WheelHandled);
    Check(WheelHandled and (Gallery.VertScrollBar.Position>0) and
      (PanelState.ActiveMapPreset=0),
      'Wheel over a preset must scroll the gallery');
    CategoryBox.ItemIndex:=2;
    CategoryBox.OnChange(CategoryBox);
    Check((PanelState.ActiveMapPreset=10) and (PanelState.MapElement='jr'),
      'Rail category must activate its first preset');
  finally
    PanelForm.Free; PanelState.Free; PanelDoc.Free;
  end;
  CheckEndpointConnections;
  WriteConnectionExamples;
  CheckJoinedBridges;
  CheckCrossingGaps;
  CheckCrossingAnglesAndSamples;
  D := TVectArtDocument.Create; Restored := TVectArtDocument.Create;
  CrossingDoc := TVectArtDocument.Create;
  H := TVectArtEditHistory.Create; LocalHistory:=TVectArtEditHistory.Create;
  S := TVectArtEditorState.Create;
  Creation := TVectArtShapeCreation.Create; Buffer := TVectArtRenderBuffer.Create;
  try
    ColorDoc := TVectArtDocument.Create;
    ColorRestored := TVectArtDocument.Create;
    try
      R := Road('road',PointF(0,0),PointF(10,0));
      InsertMapPath(ColorDoc,LocalHistory,R);
      R := Road('road',PointF(0,10),PointF(10,10));
      InsertMapPath(ColorDoc,LocalHistory,R);
      R := Road('river',PointF(0,20),PointF(10,20));
      InsertMapPath(ColorDoc,LocalHistory,R);
      S.CurrentTool := vetLine;
      S.MapElement := 'road';
      S.CreationColor := clBlack;
      ColorDoc.SetSelectedLayers([]);
      Check(S.MapPlacementColor(ColorDoc,FromSelectedObject) =
        ColorDoc.CanvasLayer.RoadPresetColor,
        'Road placement must ignore shared creation color');
      TVectArtPathLayer(ColorDoc[1]).StrokeColor := clRed;
      TVectArtPathLayer(ColorDoc[1]).MapColorOverride := True;
      ColorDoc.SetSelectedLayers([1]);
      Check((S.MapPlacementColor(ColorDoc,FromSelectedObject) = clRed) and
        FromSelectedObject,'Selected custom road color');
      Creation.Configure(ColorDoc,LocalHistory,S,Rect(0,0,800,600),1);
      Check(Creation.MouseDown(mbLeft,[],100,100),'Custom road start');
      Check((S.MapPlacementColor(ColorDoc,FromSelectedObject) = clRed) and
        FromSelectedObject,'Road preview must retain the source color');
      Check(Creation.MouseUp(mbLeft,[],200,100),'Custom road finish');
      Check((TVectArtPathLayer(ColorDoc[ColorDoc.LayerCount-1]).StrokeColor =
        clRed) and TVectArtPathLayer(ColorDoc[ColorDoc.LayerCount-1]).MapColorOverride,
        'New road must inherit selected custom color');
      Check((S.CurrentTool = vetLine) and (ColorDoc.SelectionCount = 0),
        'Road placement must continue without selecting the completed road');
      Check(Creation.MouseDown(mbLeft,[],100,130),'Second custom road start');
      Check(Creation.MouseUp(mbLeft,[],200,130),'Second custom road finish');
      Check((TVectArtPathLayer(ColorDoc[ColorDoc.LayerCount-1]).StrokeColor =
        clRed) and TVectArtPathLayer(ColorDoc[ColorDoc.LayerCount-1]).MapColorOverride,
        'Continued road placement must retain the inherited color');
      S.SetMapPlacementColor(clBlue);
      Check((S.MapPlacementColor(ColorDoc,FromSelectedObject) = clBlue) and
        not FromSelectedObject,'Picker color must replace inherited placement color');
      ColorDoc.SetSelectedLayers([1]);
      S.CurrentTool := vetLine;
      S.MapElement := 'river';
      Check((S.MapPlacementColor(ColorDoc,FromSelectedObject) =
        ColorDoc.CanvasLayer.RiverPresetColor) and not FromSelectedObject,
        'Road color must not leak into river placement');
      S.MapElement := 'road';
      ApplyMapColorPreset(ColorDoc,LocalHistory,
        TVectArtPathLayer(ColorDoc[1]),True);
      Check((ColorDoc.CanvasLayer.RoadPresetColor = clRed) and
        (TVectArtPathLayer(ColorDoc[2]).StrokeColor = clRed) and
        not TVectArtPathLayer(ColorDoc[1]).MapColorOverride and
        (TVectArtPathLayer(ColorDoc[3]).StrokeColor <> clRed),
        'Road preset bulk apply');
      Check(TryDeserializeVectArtDocument(
        SerializeVectArtDocument(ColorDoc),ColorRestored,E),
        'Color preset JSON: '+E);
      Check((ColorRestored.CanvasLayer.RoadPresetColor = clRed) and
        (ColorRestored.CanvasLayer.RiverPresetColor =
          ColorDoc.CanvasLayer.RiverPresetColor) and
        not TVectArtPathLayer(ColorRestored[1]).MapColorOverride,
        'Color preset JSON values');
      LocalHistory.Undo;
      Check((ColorDoc.CanvasLayer.RoadPresetColor <> clRed) and
        (TVectArtPathLayer(ColorDoc[2]).StrokeColor <> clRed) and
        TVectArtPathLayer(ColorDoc[1]).MapColorOverride,
        'Road preset bulk undo');
      LocalHistory.Redo;
      Check((ColorDoc.CanvasLayer.RoadPresetColor = clRed) and
        (TVectArtPathLayer(ColorDoc[2]).StrokeColor = clRed),
        'Road preset bulk redo');
      SetMapPlacementPreset(ColorDoc,LocalHistory,'river',clBlue);
      Check((ColorDoc.CanvasLayer.RiverPresetColor = clBlue) and
        (ColorDoc.CanvasLayer.RoadPresetColor = clRed) and
        (TVectArtPathLayer(ColorDoc[3]).StrokeColor <> clBlue),
        'River preset changes future placement only');
      LocalHistory.Undo;
      Check(ColorDoc.CanvasLayer.RiverPresetColor <> clBlue,
        'River preset undo');
      S.MapElement := '';
      S.CurrentTool := vetSelect;
    finally
      ColorRestored.Free;
      ColorDoc.Free;
      LocalHistory.Clear;
    end;
    PaletteDoc := TVectArtDocument.Create;
    try
      R := Road('jr',PointF(-60,0),PointF(60,0));
      InsertMapPath(PaletteDoc,LocalHistory,R);
      RenderVectArtDocument(PaletteDoc,Buffer,200,100);
      CrossingImageHash := 0;
      for I := 0 to Buffer.PixelCount-1 do
        CrossingImageHash := CrossingImageHash +
          Buffer.Pixels[I].R*3 + Buffer.Pixels[I].G*5 +
          Buffer.Pixels[I].B*7 + Buffer.Pixels[I].A;
      SetMapRailPalette(PaletteDoc,LocalHistory,clRed,clGreen,clBlue,clYellow);
      Check(TVectArtPathLayer(PaletteDoc[1]).StrokeColor = clBlack,
        'Global railway palette must preserve path color data');
      RenderVectArtDocument(PaletteDoc,Buffer,200,100);
      PlainImageHash := 0;
      for I := 0 to Buffer.PixelCount-1 do
        PlainImageHash := PlainImageHash +
          Buffer.Pixels[I].R*3 + Buffer.Pixels[I].G*5 +
          Buffer.Pixels[I].B*7 + Buffer.Pixels[I].A;
      Check(CrossingImageHash <> PlainImageHash,'JR palette must affect drawing');
      TVectArtPathLayer(PaletteDoc[1]).StrokeColor := clRed;
      Check(TryDeserializeVectArtDocument(
        SerializeVectArtDocument(PaletteDoc),Restored,E),
        'Rail palette JSON: '+E);
      Check((Restored.CanvasLayer.JrPrimaryColor = clRed) and
        (Restored.CanvasLayer.JrSecondaryColor = clGreen) and
        (Restored.CanvasLayer.RailPrimaryColor = clBlue) and
        (Restored.CanvasLayer.RailSecondaryColor = clYellow) and
        (TVectArtPathLayer(Restored[1]).StrokeColor = clRed),
        'Rail palette JSON values');
      ApplyMapTheme(PaletteDoc,LocalHistory,True);
      Check((PaletteDoc.CanvasLayer.JrPrimaryColor = clRed) and
        (PaletteDoc.CanvasLayer.RailSecondaryColor = clYellow),
        'Theme must preserve custom railway colors');
      LocalHistory.Undo;
      LocalHistory.Undo;
      Check(PaletteDoc.CanvasLayer.JrPrimaryColor = $00222222,
        'Rail palette undo');
      ApplyMapTheme(PaletteDoc,LocalHistory,True);
      Check((PaletteDoc.CanvasLayer.JrPrimaryColor = clWhite) and
        (PaletteDoc.CanvasLayer.JrSecondaryColor = $00222222) and
        (PaletteDoc.CanvasLayer.RailPrimaryColor = clWhite),
        'Theme must switch untouched railway defaults');
      LocalHistory.Undo;
      LocalHistory.Clear;
      PaletteDoc.RemovePath(1,R);
      R := Road('river',PointF(-60,0),PointF(60,0));
      R.StrokeColor := clBlue;
      InsertMapPath(PaletteDoc,LocalHistory,R);
      RenderVectArtDocument(PaletteDoc,Buffer,200,100);
      CrossingImageHash := 0;
      for I := 0 to Buffer.PixelCount-1 do
        CrossingImageHash := CrossingImageHash +
          Buffer.Pixels[I].R*3 + Buffer.Pixels[I].G*5 +
          Buffer.Pixels[I].B*7 + Buffer.Pixels[I].A;
      TVectArtPathLayer(PaletteDoc[1]).StrokeColor := clRed;
      RenderVectArtDocument(PaletteDoc,Buffer,200,100);
      PlainImageHash := 0;
      for I := 0 to Buffer.PixelCount-1 do
        PlainImageHash := PlainImageHash +
          Buffer.Pixels[I].R*3 + Buffer.Pixels[I].G*5 +
          Buffer.Pixels[I].B*7 + Buffer.Pixels[I].A;
      Check(CrossingImageHash <> PlainImageHash,
        'River renderer must use path color');
    finally
      LocalHistory.Clear;
      PaletteDoc.Free;
    end;
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
      Check(not Editor.MouseDown(mbLeft,[],400,300),
        'Road segment click must remain available for dragging');
      Check(Length(TVectArtPathLayer(D[1]).Vertices)=2,
        'Segment click must not insert a point');
      Check(Editor.ContextTarget(400,300,SnapPath,VertexIndex,
        SegmentIndex,SegmentT) and (SegmentIndex=0) and
        (VertexIndex<0),'Road segment menu target');
      Check(Editor.ExecuteContextEdit(SnapPath,VertexIndex,SegmentIndex,
        SegmentT,False),'Insert road vertex from menu');
      Check(Length(TVectArtPathLayer(D[1]).Vertices)=3,'Point not inserted');
      Check(Editor.KeyDown(Ord('P')),'Point Bezier mode');
      Check(TVectArtPathLayer(D[1]).Vertices[1].Kind=slvkBezier,'Bezier data');
      Check(not Editor.MouseDown(mbRight,[],400,300),
        'Right click must open the context menu');
      Check(Length(TVectArtPathLayer(D[1]).Vertices)=3,
        'Right click must not delete a point');
      Check(Editor.ContextTarget(400,300,SnapPath,VertexIndex,
        SegmentIndex,SegmentT) and (VertexIndex=1),
        'Road vertex menu target');
      Check(Editor.ExecuteContextEdit(SnapPath,VertexIndex,SegmentIndex,
        SegmentT,True),'Delete road vertex from menu');
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
    for I := 0 to 9 do begin
      SymbolLayer := CreateMapSymbol(I, MapSymbolDefaultLabel(I));
      try
        RenderVectArtLayerThumbnail(SymbolLayer, Buffer, 64, 42);
        HasSymbolPixels := False;
        for PixelIndex := 0 to Buffer.PixelCount - 1 do
          if Buffer.Pixels[PixelIndex].A <> 0 then begin
            HasSymbolPixels := True;
            Break;
          end;
        Check(HasSymbolPixels, 'Empty symbol thumbnail: '+IntToStr(I));
      finally
        SymbolLayer.Free;
      end;
      InsertMapSymbol(D,H,I,IntToStr(I+1)); H.Undo;
    end;
    R := Road('jr',PointF(-180,-100),PointF(180,-100)); InsertMapPath(D,H,R);
    R := Road('road',PointF(-180,-94),PointF(180,-94)); R.StrokeWidth:=40;
    InsertMapPath(D,H,R);
    PlaceMapSymbol(D,H,0,'駅',PointF(0,-94),True);
    Check(TryGetMapRakuLayerBounds(D[D.LayerCount-1],SymbolBounds) and
      (Abs(SymbolBounds.CenterPoint.Y+100)<0.5),
      'Station must snap to railway, not the nearer road');
    PlaceMapSymbol(D,H,2,'横断歩道',PointF(0,-94),True);
    Check(TryGetMapRakuLayerBounds(D[D.LayerCount-1],SymbolBounds) and
      (Abs(SymbolBounds.CenterPoint.Y+94)<0.5),
      'Crosswalk must snap to road');
    PlaceMapSymbol(D,H,3,'歩道橋',PointF(0,-94),True);
    Check(TryGetMapRakuLayerBounds(D[D.LayerCount-1],SymbolBounds) and
      (SymbolBounds.Height>=100) and (SymbolBounds.Width<=27),
      'Pedestrian bridge must cross and span the road');
    R := Road('route',PointF(-180,120),PointF(180,120));
    R.RouteId:='route-progress-test';
    InsertMapPath(D,H,R);
    RouteLayer := TVectArtPathLayer(D[D.LayerCount-1]);
    R := Road('route',PointF(180,120),PointF(360,120));
    R.RouteId:='route-progress-test';
    InsertMapPath(D,H,R);
    I:=D.LayerCount;
    PlaceMapSymbol(D,H,10,'開始点',PointF(0,120),True);
    Check(D.LayerCount=I,'Route marker must not be placed on a route interior');
    PlaceMapSymbol(D,H,10,'開始点',PointF(-180,120),True);
    PlaceMapSymbol(D,H,11,'終了点',PointF(360,120),True);
    Check(ValidateRouteMarkers(D,E),'Route markers: '+E);
    I:=D.LayerCount;
    PlaceMapSymbol(D,H,10,'開始点',PointF(-180,120),True);
    Check(D.LayerCount=I,'Duplicate route start must be ignored');
    RouteMarker:=nil;
    for I:=0 to D.LayerCount-1 do
      if (D[I] is TMapRakuGroupLayer) and
         (TMapRakuGroupLayer(D[I]).RouteMarkerKind='start') then
        RouteMarker:=TMapRakuGroupLayer(D[I]);
    Check((RouteMarker<>nil) and (RouteMarker.RoutePathId=RouteLayer.RouteId),
      'Route start marker association');
    Check(TryBuildMapRakuRoute(D,'route-progress-test',RouteProgress,E),
      'Build logical route: '+E);
    Check(TryMapRakuRoutePosition(RouteProgress,50,SnapPoint,Tangent,SnapPath) and
      (Abs(SnapPoint.X-90)<0.5) and
      (Abs(SnapPoint.Y-120)<0.5),'Distance-based route midpoint');
    J:=SerializeVectArtDocument(D);
    Check(TryDeserializeVectArtDocument(J,Restored,E),'Route marker JSON: '+E);
    Check(ValidateRouteMarkers(Restored,E),'Restored route markers: '+E);
    RouteMarker:=nil;
    for I:=0 to Restored.LayerCount-1 do
      if (Restored[I] is TMapRakuGroupLayer) and
         (TMapRakuGroupLayer(Restored[I]).RouteMarkerKind='start') then
        RouteMarker:=TMapRakuGroupLayer(Restored[I]);
    Check((RouteMarker<>nil) and RouteMarker.HasRouteMarkerPosition and
      (Abs(RouteMarker.RouteMarkerPosition.X+180)<0.5) and
      (Abs(RouteMarker.RouteMarkerPosition.Y-120)<0.5),
      'Route marker position must survive JSON');
    S.MapElement := 'jr'; S.CurrentTool := vetPath; S.LineStrokeWidth := 12;
    Creation.Configure(D,H,S,Rect(0,0,800,600),1);
    Creation.MouseDown(mbLeft,[],100,200); Creation.MouseDown(mbLeft,[],240,200);
    S.NextVertexKind := slvkBezier;
    Creation.MouseDown(mbLeft,[],350,150);
    Check(Creation.FinishPath(False),'Path finish');
    Check(S.CurrentTool=vetPath,'Map tool must remain active');
    Check(D.SelectionCount=0,'Continued placement must not select a layer');
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
