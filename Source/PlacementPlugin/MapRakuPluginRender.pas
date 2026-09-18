// 地図の背景色を含めたRGBAを作り、共通レンダラーの出力を映像用にまとめる。
unit MapRakuPluginRender;
interface
uses MapRakuDocument, MapRakuRenderer;
procedure RenderMapRakuPlugin(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer);
implementation
uses Vcl.Graphics, Winapi.Windows;
procedure RenderMapRakuPlugin(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer);
var Layers: TVectArtRenderBuffer; Pixel: PVectArtRgbaPixel;
  Color: COLORREF; I: NativeInt;
begin
  Layers := TVectArtRenderBuffer.Create;
  try
    RenderVectArtDocument(Document, Layers, Width, Height);
    Target.SetSize(Width, Height);
    Target.Clear;
    if Document.CanvasLayer.Visible and not Document.CanvasLayer.Transparent then
    begin
      Color := ColorToRGB(Document.CanvasLayer.BackgroundColor);
      Pixel := Target.Data;
      for I := 0 to Target.PixelCount - 1 do
      begin
        Pixel^.R := GetRValue(Color);
        Pixel^.G := GetGValue(Color);
        Pixel^.B := GetBValue(Color);
        Pixel^.A := 255;
        Inc(Pixel);
      end;
    end;
    CompositeVectArtRgba(Layers, Target.Data, Width, Height);
  finally
    Layers.Free;
  end;
end;
end.
