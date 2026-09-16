// 地図固有の経路・層・保存・描画・作図操作を実データで検証する。
unit MapRakuTestCases;
interface
procedure RunMapTests;
implementation
uses System.SysUtils, System.Types, System.Classes, System.IOUtils, System.JSON,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap,
  MapRakuDocument, MapRakuDocumentJson, MapRakuEditHistory, MapRakuEditorState,
  MapRakuMapCommands, MapRakuGroupCommands, MapRakuRenderer, MapRakuShapeCreation,
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
var D, Restored: TVectArtDocument; H: TVectArtEditHistory; S: TVectArtEditorState;
  R: TVectArtPathData; J, E: string; G: TMapRakuGroupLayer;
  Creation: TVectArtShapeCreation; Buffer: TVectArtRenderBuffer; P: TVectArtRgbaPixel;
  I: Integer;
  ExceptionSink: TTestExceptionSink; Form: TMainForm; Bitmap: TBitmap; Png: TPngImage;
  Editor: TMapPathEditor; SnapPoint, Tangent: TPointF; SnapPath: TVectArtPathLayer;
begin
  ExceptionSink := TTestExceptionSink.Create;
  Application.OnException := ExceptionSink.HandleException;
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  D := TVectArtDocument.Create; Restored := TVectArtDocument.Create;
  H := TVectArtEditHistory.Create; S := TVectArtEditorState.Create;
  Creation := TVectArtShapeCreation.Create; Buffer := TVectArtRenderBuffer.Create;
  try
    D.CanvasLayer.Width := 800; D.CanvasLayer.Height := 600;
    R := Road('road', PointF(-300,0), PointF(300,0));
    InsertMapPath(D,H,R);
    Check((D.LayerCount=2) and (D[1] is TMapRakuGroupLayer), 'Road must create a group');
    H.Undo; Check(D.LayerCount=1,'Insert undo'); H.Redo;
    Check(TVectArtPathLayer(TMapRakuGroupLayer(D[1])[0]).MapElement='road','Redo metadata');
    S.OpenGroup:=TMapRakuGroupLayer(D[1]); S.OpenGroupChild:=S.OpenGroup[0];
    Editor:=TMapPathEditor.Create;
    try
      Editor.Configure(D,S,H,Rect(0,0,800,600),1);
      Check(Editor.MouseDown(mbLeft,[],400,300),'Insert vertex in group');
      Check(Length(TVectArtPathLayer(S.OpenGroupChild).Vertices)=3,'Point not inserted');
      Check(Editor.KeyDown(Ord('P')),'Point Bezier mode');
      Check(TVectArtPathLayer(S.OpenGroupChild).Vertices[1].Kind=slvkBezier,'Bezier data');
      Check(Editor.MouseDown(mbRight,[],400,300),'Delete vertex in group');
      Check(Length(TVectArtPathLayer(S.OpenGroupChild).Vertices)=2,'Point not removed');
      H.Undo; Check(Length(TVectArtPathLayer(S.OpenGroupChild).Vertices)=3,'Point deletion undo');
      H.Undo; H.Undo;
    finally Editor.Free; S.OpenGroup:=nil; end;
    D.SetSelectedLayers([]);
    R := Road('road',PointF(0,-200),PointF(0,200)); InsertMapPath(D,H,R);
    D.SetSelectedLayers([1,2]); GroupSelectedLayers(D,H);
    G := TMapRakuGroupLayer(D[1]); Check(G.MapSurface,'Merged map surface');
    RenderVectArtDocument(D,Buffer,800,600);
    P := Buffer.Pixels[300*800+412];
    Check((P.R>230) and (P.G>230),'Same-layer junction must not have a seam');
    H.Undo; Check(D.LayerCount=3,'Group undo');
    RenderVectArtDocument(D,Buffer,800,600); P := Buffer.Pixels[300*800+412];
    Check(P.R<180,'Separate layers must have visible edge'); H.Redo;
    J := SerializeVectArtDocument(D);
    Check(TryDeserializeVectArtDocument(J,Restored,E),'JSON: '+E);
    Check(TMapRakuGroupLayer(Restored[1]).MapSurface,'JSON group role');
    Check(not TryDeserializeVectArtDocument(StringReplace(J,'"MapRaku"','"Other"',[]),Restored,E),'Foreign app accepted');
    Check(Restored.LayerCount=2,'Invalid load must preserve document');
    J := StringReplace(J,'"road"','"invalid"',[rfReplaceAll]);
    Check(not TryDeserializeVectArtDocument(J,Restored,E),'Invalid road kind accepted');
    G := TMapRakuGroupLayer(D[1]); S.OpenGroup := G;
    S.OpenGroupChild := G[0]; DetachMapChild(D,H,S);
    Check(D.LayerCount=3,'Detach child'); H.Undo; Check(D.LayerCount=2,'Detach undo');
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
    G := TMapRakuGroupLayer(D[D.LayerCount-1]);
    Check(TVectArtPathLayer(G[0]).MapElement='jr','Rail kind lost');
    R := Road('river',PointF(-250,-250),PointF(180,220)); InsertMapPath(D,H,R);
    InsertMapSymbol(D,H,0,'千里丘');
    ExportMapSvg(D,'TestOutput/map-scene.svg');
    ExportMapPng(D,'TestOutput/map-scene.png');
    J := TFile.ReadAllText('TestOutput/map-scene.svg', TEncoding.UTF8);
    Check(J.Contains('<svg') and J.Contains('<path'),'SVG vectors missing');
    Check(not J.Contains('<text'),'SVG text must be paths');
    SaveMapFile(D,'TestOutput/map-scene.mapraku');
    Check(NearestMapPath(D,PointF(120,3),8,False,'road',SnapPoint,Tangent,SnapPath),'Road snap');
    Check(Abs(SnapPoint.Y)<0.1,'Road snap must reach center path');
    Form := TMainForm.Create(nil);
    try
      Form.SetBounds(0,0,1440,900); Form.EnableStandaloneFileActions;
      Check(TryDeserializeVectArtDocument(SerializeVectArtDocument(D),Form.Document,E),'UI document');
      Check(Form.CloseQuery, 'Debug close must not prompt for unsaved changes');
      Form.HandleNeeded;
      Bitmap := TBitmap.Create; Png := TPngImage.Create;
      try
        Bitmap.SetSize(Form.ClientWidth,Form.ClientHeight);
        Form.PaintTo(Bitmap.Canvas.Handle,0,0);
        Png.Assign(Bitmap); Png.SaveToFile('TestOutput/editor.png');
      finally Png.Free; Bitmap.Free; end;
    finally Form.Free; end;
    Writeln('PASS: insertion, undo/redo, same-layer junction, separate-layer edge, grouping, detach, JSON validation, themes, symbols, path finish, SVG/PNG');
  finally
    Buffer.Free; Creation.Free; S.Free; H.Free; Restored.Free; D.Free;
    TTextRendererSkiaRuntime.Release;
    Application.OnException := nil; ExceptionSink.Free;
  end;
end;
end.
