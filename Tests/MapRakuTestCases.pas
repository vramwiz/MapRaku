// 地図固有の経路・層・保存・描画・作図操作を実データで検証する。
unit MapRakuTestCases;
interface
procedure RunMapTests;
implementation
uses System.SysUtils, System.Types, System.Classes, System.IOUtils, System.JSON,
  System.Skia, System.UITypes, System.Math,
  Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  Vcl.Imaging.pngimage,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap,
  MapRakuDocument, MapRakuDocumentJson, MapRakuEditHistory, MapRakuEditorState,
  MapRakuMapCommands, MapRakuCrossings, MapRakuGroupCommands, MapRakuRenderer, MapRakuShapeCreation,
  MapRakuExport, MapRakuTheme, MapRakuSymbols, MapRakuMapPanel,
  MapRakuFile, MapRakuPathSnap,
  MapRakuTextGeometry, MapRakuMainForm, MapRakuPathEditor, MapRakuPathOperations,
  MapRakuRecentFiles,
  MapRakuProjectiveTransform, MapRakuSelectionGeometry, MapRakuTestSupport,
  MapRakuConnectionTests, MapRakuCrossingTests;
type
  TTestExceptionSink = class
    procedure HandleException(Sender: TObject; E: Exception);
  end;
procedure TTestExceptionSink.HandleException(Sender: TObject; E: Exception);
begin
  Writeln('FAIL (VCL): ' + E.ClassName + ': ' + E.Message);
  Halt(1);
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
