// AI向けの背景・合成画像を通常レンダラーで生成し、座標対応とともに返す。
// Document、選択、Undoを変更せず、PNGをパイプ転送用のメモリへ保存する。
unit MapRakuAutomationVisuals;

interface

uses
  System.JSON, Vcl.Graphics, MapRakuDocument;

// 呼出側へJSON所有権を渡す。背景はCanvasから複写した呼出側所有の画像。
function BuildMapRakuAutomationImages(Document: TVectArtDocument;
  Background: Vcl.Graphics.TBitmap; MaxEdge: Integer): TJSONObject;

implementation

uses
  System.SysUtils, System.Classes, System.Math, Winapi.Windows,
  Vcl.Imaging.pngimage, MapRakuRenderer, MapRakuAutomationSession;

procedure ReleaseImages(Images: TJSONObject);
var Pair: TJSONPair; Request: TJSONObject; Value: TJSONValue;
begin
  // 途中の描画失敗でも転送領域を占有し続けないよう、既に生成した画像だけを解放する。
  for Pair in Images do
    if Pair.JsonValue is TJSONObject then begin
      Value := TJSONObject(Pair.JsonValue).GetValue('blob_id');
      if Value = nil then Continue;
      Request := TJSONObject.Create;
      try
        Request.AddPair('blob_id',Value.Value);
        AutomationSession.Blobs.Handle('release_blob',Request).Free;
      finally Request.Free; end;
    end;
end;

function BufferPng(Buffer: TVectArtRenderBuffer): TJSONObject;
var
  Png: TPngImage;
  Row, Alpha: PByte;
  Pixel: PVectArtRgbaPixel;
  X, Y: Integer;
  Stream: TBytesStream;
begin
  Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, Buffer.Width, Buffer.Height);
  try
    Pixel := Buffer.Data;
    for Y := 0 to Buffer.Height - 1 do
    begin
      Row := Png.Scanline[Y];
      Alpha := PByte(Png.AlphaScanline[Y]);
      for X := 0 to Buffer.Width - 1 do
      begin
        Row[X * 3] := Pixel.B;
        Row[X * 3 + 1] := Pixel.G;
        Row[X * 3 + 2] := Pixel.R;
        Alpha[X] := Pixel.A;
        Inc(Pixel);
      end;
    end;
    Stream := TBytesStream.Create;
    try
      Png.SaveToStream(Stream);
      Result := AutomationSession.Blobs.Store(Copy(Stream.Bytes,0,Stream.Size),'image/png');
    finally
      Stream.Free;
    end;
  finally
    Png.Free;
  end;
end;

function BuildMapRakuAutomationImages(Document: TVectArtDocument;
  Background: Vcl.Graphics.TBitmap; MaxEdge: Integer): TJSONObject;
var
  Base, Overlay: TVectArtRenderBuffer;
  Pixel: PVectArtRgbaPixel;
  Row: PByte;
  X, Y, SX, SY, W, H, CW, CH: Integer;
  Color: COLORREF;
  Scale: Double;
  Mapping: TJSONObject;
begin
  if (MaxEdge < 64) or (MaxEdge > 2048) then
    raise EArgumentException.Create('max_edge must be an integer from 64 to 2048.');
  CW := Document.CanvasLayer.Width;
  CH := Document.CanvasLayer.Height;
  if (CW <= 0) or (CH <= 0) then
    raise EArgumentException.Create('Canvas dimensions must be positive.');
  Scale := Min(1.0, MaxEdge / Max(CW, CH));
  W := Max(1, Round(CW * Scale));
  H := Max(1, Round(CH * Scale));
  Base := TVectArtRenderBuffer.Create;
  Overlay := TVectArtRenderBuffer.Create;
  Result := TJSONObject.Create;
  try
    Base.SetSize(W, H);
    Base.Clear;
    Pixel := Base.Data;
    Color := ColorToRGB(Document.CanvasLayer.BackgroundColor);
    for Y := 0 to H - 1 do
    begin
      Row := nil;
      if (Background.Width > 0) and (Background.Height > 0) then
      begin
        SY := Min(Background.Height - 1, Y * Background.Height div H);
        Row := Background.ScanLine[SY];
      end;
      for X := 0 to W - 1 do
      begin
        if Row <> nil then
        begin
          SX := Min(Background.Width - 1, X * Background.Width div W);
          Pixel.R := Row[SX * 4 + 2];
          Pixel.G := Row[SX * 4 + 1];
          Pixel.B := Row[SX * 4];
          Pixel.A := 255;
        end
        else if Document.CanvasLayer.Visible and not Document.CanvasLayer.Transparent then
        begin
          Pixel.R := GetRValue(Color);
          Pixel.G := GetGValue(Color);
          Pixel.B := GetBValue(Color);
          Pixel.A := 255;
        end;
        Inc(Pixel);
      end;
    end;
    Result.AddPair('base_image', BufferPng(Base));
    RenderVectArtDocument(Document, Overlay, W, H);
    Result.AddPair('overlay_image', BufferPng(Overlay));
    CompositeVectArtRgba(Overlay, Base.Data, W, H);
    Result.AddPair('composite_image', BufferPng(Base));
    Result.AddPair('has_reference_background', TJSONBool.Create(Background.Width > 0));
    Result.AddPair('pixel_width', TJSONNumber.Create(W));
    Result.AddPair('pixel_height', TJSONNumber.Create(H));
    Result.AddPair('canvas_width', TJSONNumber.Create(CW));
    Result.AddPair('canvas_height', TJSONNumber.Create(CH));
    Mapping := TJSONObject.Create;
    Mapping.AddPair('origin', 'canvas_center');
    Mapping.AddPair('x_axis', 'right');
    Mapping.AddPair('y_axis', 'down');
    Mapping.AddPair('pixel_origin', 'top_left_edge');
    Mapping.AddPair('document_x_per_pixel', TJSONNumber.Create(CW / W));
    Mapping.AddPair('document_y_per_pixel', TJSONNumber.Create(CH / H));
    Mapping.AddPair('document_x_offset', TJSONNumber.Create(-CW / 2));
    Mapping.AddPair('document_y_offset', TJSONNumber.Create(-CH / 2));
    Result.AddPair('mapping', Mapping);
  except
    ReleaseImages(Result);
    Result.Free;
    Overlay.Free;
    Base.Free;
    raise;
  end;
  Overlay.Free;
  Base.Free;
end;

end.
