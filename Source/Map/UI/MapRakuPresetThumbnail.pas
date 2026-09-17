// 配置候補の実レイヤーを共通レンダラーで描き、一覧用の不透明画像へ変換する。
unit MapRakuPresetThumbnail;

interface

uses Vcl.Graphics, MapRakuDocument;

function CreateMapPresetThumbnail(Layer: TVectArtLayer; Width, Height: Integer;
  Background: TColor): Vcl.Graphics.TBitmap;

implementation

uses Winapi.Windows, MapRakuRenderer;

function CreateMapPresetThumbnail(Layer: TVectArtLayer; Width, Height: Integer;
  Background: TColor): Vcl.Graphics.TBitmap;
var
  Buffer: TVectArtRenderBuffer;
  Destination: PByte;
  Pixel: PVectArtRgbaPixel;
  BackgroundValue, Alpha: Cardinal;
  X, Y: Integer;
begin
  Result := Vcl.Graphics.TBitmap.Create;
  Buffer := TVectArtRenderBuffer.Create;
  try
    try
    RenderVectArtLayerThumbnail(Layer, Buffer, Width, Height);
    Result.PixelFormat := pf32bit;
    Result.SetSize(Width, Height);
    BackgroundValue := ColorToRGB(Background);
    Pixel := Buffer.Data;
    for Y := 0 to Height - 1 do
    begin
      Destination := Result.ScanLine[Height - 1 - Y];
      for X := 0 to Width - 1 do
      begin
        Alpha := Pixel^.A;
        Destination[0] := (Cardinal(Pixel^.B) * Alpha +
          Cardinal(GetBValue(BackgroundValue)) * (255 - Alpha) + 127) div 255;
        Destination[1] := (Cardinal(Pixel^.G) * Alpha +
          Cardinal(GetGValue(BackgroundValue)) * (255 - Alpha) + 127) div 255;
        Destination[2] := (Cardinal(Pixel^.R) * Alpha +
          Cardinal(GetRValue(BackgroundValue)) * (255 - Alpha) + 127) div 255;
        Destination[3] := 255;
        Inc(Destination, 4);
        Inc(Pixel);
      end;
    end;
    except
      Result.Free;
      raise;
    end;
  finally
    Buffer.Free;
  end;
end;

end.
