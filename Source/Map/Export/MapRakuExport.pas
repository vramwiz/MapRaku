// 画面と共通の描画をSVG／PNGへ出力する。SVG文字は字形パス、画像は埋込み。
unit MapRakuExport;
interface
uses MapRakuDocument;
procedure ExportMapSvg(Document: TVectArtDocument; const FileName: string);
procedure ExportMapPng(Document: TVectArtDocument; const FileName: string);
procedure ExportMapPreviewPng(Document: TVectArtDocument; const FileName: string; MaxEdge: Integer);
implementation
uses System.Classes, System.SysUtils, System.Types, System.UITypes, System.Math,
  System.Skia, System.Generics.Collections, Vcl.Graphics, MapRakuRenderer;
procedure DrawDocument(Document: TVectArtDocument; const Canvas: ISkCanvas);
var C: TColor; P: ISkPaint;
begin
  if not Document.CanvasLayer.Transparent then begin
    C := ColorToRGB(Document.CanvasLayer.BackgroundColor);
    P := TSkPaint.Create;
    P.Color := $FF000000 or (Cardinal(C and $FF) shl 16) or Cardinal(C and $FF00) or
      (Cardinal(C shr 16) and $FF);
    Canvas.DrawRect(TRectF.Create(0, 0, Document.CanvasLayer.Width, Document.CanvasLayer.Height), P);
  end;
  RenderMapDocumentToCanvas(Document,Canvas);
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
procedure ExportMapPreviewPng(Document: TVectArtDocument; const FileName: string; MaxEdge: Integer);
var Surface: ISkSurface; Scale: Single;
begin
  Scale := Min(1,MaxEdge/Max(Document.CanvasLayer.Width,Document.CanvasLayer.Height));
  Surface := TSkSurface.MakeRaster(Max(1,Round(Document.CanvasLayer.Width*Scale)),
    Max(1,Round(Document.CanvasLayer.Height*Scale)));
  if Surface=nil then raise EInvalidOp.Create('プレビュー領域を作成できません');
  Surface.Canvas.Clear(TAlphaColorRec.Null); Surface.Canvas.Scale(Scale,Scale);
  DrawDocument(Document,Surface.Canvas);
  Surface.MakeImageSnapshot.EncodeToFile(FileName,TSkEncodedImageFormat.PNG);
end;
end.
