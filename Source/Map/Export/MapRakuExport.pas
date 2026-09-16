// 画面と共通の描画をSVG／PNGへ出力する。SVG文字は字形パス、画像は埋込み。
unit MapRakuExport;
interface
uses MapRakuDocument;
procedure ExportMapSvg(Document: TVectArtDocument; const FileName: string);
procedure ExportMapPng(Document: TVectArtDocument; const FileName: string);
implementation
uses System.Classes, System.SysUtils, System.Types, System.UITypes,
  System.Skia, System.Generics.Collections, Vcl.Graphics, MapRakuRenderer;
procedure CollectMapLeaves(Layer: TVectArtLayer; Leaves: TList<TVectArtLayer>);
var I: Integer;
begin
  if not Layer.Visible then Exit;
  if Layer is TMapRakuGroupLayer then
    for I := 0 to TMapRakuGroupLayer(Layer).ChildCount - 1 do
      CollectMapLeaves(TMapRakuGroupLayer(Layer)[I], Leaves)
  else Leaves.Add(Layer);
end;
procedure DrawTree(Layer: TVectArtLayer; const Canvas: ISkCanvas;
  W, H: Integer; Opacity: Single);
var I: Integer; G: TMapRakuGroupLayer; Leaves: TList<TVectArtLayer>;
begin
  if not Layer.Visible then Exit;
  if Layer is TMapRakuGroupLayer then begin
    G := TMapRakuGroupLayer(Layer);
    if G.MapSurface then begin
      Leaves := TList<TVectArtLayer>.Create;
      try
        CollectMapLeaves(G, Leaves);
        RenderMapLayersToCanvas(Leaves.ToArray, Canvas, W, H, Opacity * G.Opacity, 1);
        RenderMapLayersToCanvas(Leaves.ToArray, Canvas, W, H, Opacity * G.Opacity, 2);
      finally Leaves.Free; end;
    end else
      for I := 0 to G.ChildCount - 1 do DrawTree(G[I], Canvas, W, H, Opacity * G.Opacity);
  end else RenderMapLayersToCanvas([Layer], Canvas, W, H, Opacity);
end;
procedure DrawDocument(Document: TVectArtDocument; const Canvas: ISkCanvas);
var I: Integer; C: TColor; P: ISkPaint;
begin
  if not Document.CanvasLayer.Transparent then begin
    C := ColorToRGB(Document.CanvasLayer.BackgroundColor);
    P := TSkPaint.Create;
    P.Color := $FF000000 or (Cardinal(C and $FF) shl 16) or Cardinal(C and $FF00) or
      (Cardinal(C shr 16) and $FF);
    Canvas.DrawRect(TRectF.Create(0, 0, Document.CanvasLayer.Width, Document.CanvasLayer.Height), P);
  end;
  for I := 1 to Document.LayerCount - 1 do
    DrawTree(Document[I], Canvas, Document.CanvasLayer.Width, Document.CanvasLayer.Height, 1);
  RenderMapRakuCrossingExpressionsToCanvas(Document,Canvas);
end;
procedure ExportMapSvg(Document: TVectArtDocument; const FileName: string);
var Stream: TFileStream; Canvas: ISkCanvas;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Canvas := TSkSVGCanvas.Make(TRectF.Create(0, 0, Document.CanvasLayer.Width,
      Document.CanvasLayer.Height), Stream, [TSkSVGCanvasFlag.ConvertTextToPaths]);
    if Canvas = nil then raise EInvalidOp.Create('SVG出力を開始できません');
    try DrawDocument(Document, Canvas); finally Canvas := nil; end;
  finally Stream.Free; end;
end;
procedure ExportMapPng(Document: TVectArtDocument; const FileName: string);
var Surface: ISkSurface;
begin
  Surface := TSkSurface.MakeRaster(Document.CanvasLayer.Width, Document.CanvasLayer.Height);
  if Surface = nil then raise EInvalidOp.Create('PNG出力領域を作成できません');
  Surface.Canvas.Clear(TAlphaColorRec.Null);
  DrawDocument(Document, Surface.Canvas);
  Surface.MakeImageSnapshot.EncodeToFile(FileName, TSkEncodedImageFormat.PNG);
end;
end.
