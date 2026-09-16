// 地図固有の経路・層・保存・描画・作図操作を実データで検証する。
unit MapRakuTestCases;
interface
procedure RunMapTests;
implementation
uses System.SysUtils, System.Types, System.Classes, System.IOUtils, System.JSON,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap,
  MapRakuDocument, MapRakuDocumentJson, MapRakuEditHistory, MapRakuEditorState,
  MapRakuMapCommands, MapRakuCrossings, MapRakuGroupCommands, MapRakuRenderer, MapRakuShapeCreation,
  MapRakuExport, MapRakuTheme, MapRakuSymbols, MapRakuFile, MapRakuPathSnap, MapRakuMainForm, MapRakuPathEditor;
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
      CrossingDoc[2].PersistentId,mckNone,CrossingDoc[2].PersistentId);
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
