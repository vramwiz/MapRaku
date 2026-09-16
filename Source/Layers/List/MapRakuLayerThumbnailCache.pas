// 文書Revision・DPI・画像寸法に対応するレイヤーサムネイルを生成し、画像の寿命を管理する。
unit MapRakuLayerThumbnailCache;

interface

uses
  System.Generics.Collections, System.Types, Vcl.Graphics,
  MapRakuDocument, MapRakuRenderer;

type
  TMapRakuLayerThumbnailCache = class
  private
    FDocument          : TVectArtDocument;                          // キャッシュの更新判定に使う文書。所有しない。
    FPPI               : Integer;                                   // 市松模様の画面DPI。
    FRenderedThumbnails: TObjectDictionary<TVectArtLayer, TBitmap>; // 生成済み画像の所有者。
    FThumbnailBitmap   : TBitmap;                                   // 市松背景への合成作業画像。
    FThumbnailBuffer   : TVectArtRenderBuffer;                      // 共通レンダラーが生成するRGBAバッファ。
    FThumbnailRevision : Int64;                                     // 生成済み画像が対応する文書Revision。
    function Scale(Value: Integer): Integer;
    procedure SyncThumbnailCache;
  public
    // 画像キャッシュと再利用する作業領域を生成する。
    constructor Create;
    // 所有するSkia描画バッファとGDI画像をすべて解放する。
    destructor Destroy; override;
    // 文書またはDPIが変わった画像を破棄し、現在Revisionへ同期する。
    procedure Configure(Document: TVectArtDocument; PPI: Integer);
    // 生成済み画像を破棄する。次の描画時に再生成する。
    procedure Clear;
    // 必要時だけ共通レンダラーで画像を生成し、指定した矩形へ描く。
    procedure Draw(ACanvas: TCustomCanvas; const ThumbnailRect: TRect; Layer: TVectArtLayer);
  end;

implementation

uses
  System.Math, Winapi.Windows, MapRakuLayerListStyle;

constructor TMapRakuLayerThumbnailCache.Create;
begin
  inherited Create;
  FRenderedThumbnails := TObjectDictionary<TVectArtLayer, Vcl.Graphics.TBitmap>.Create([doOwnsValues]);
  FThumbnailBitmap := Vcl.Graphics.TBitmap.Create;
  FThumbnailBuffer := TVectArtRenderBuffer.Create;
  FThumbnailRevision := -1;
  FPPI := 96;
end;

destructor TMapRakuLayerThumbnailCache.Destroy;
begin
  FThumbnailBuffer.Free;
  FThumbnailBitmap.Free;
  FRenderedThumbnails.Free;
  inherited Destroy;
end;

procedure TMapRakuLayerThumbnailCache.Clear;
begin
  FRenderedThumbnails.Clear;
  FThumbnailRevision := -1;
end;

function TMapRakuLayerThumbnailCache.Scale(Value: Integer): Integer;
begin
  Result := MulDiv(Value, FPPI, 96);
end;

procedure TMapRakuLayerThumbnailCache.Configure(Document: TVectArtDocument; PPI: Integer);
begin
  if (FDocument <> Document) or (FPPI <> PPI) then Clear;
  FDocument := Document;
  FPPI := Max(1, PPI);
  SyncThumbnailCache;
end;

procedure TMapRakuLayerThumbnailCache.Draw(
  ACanvas: TCustomCanvas; const ThumbnailRect: TRect;
  Layer: TVectArtLayer);
var
  Alpha: Cardinal;
  BackgroundColor: TColor;
  BackgroundValue: Cardinal;
  CachedBitmap: Vcl.Graphics.TBitmap;
  Destination: PByte;
  Source: PVectArtRgbaPixel;
  X: Integer;
  Y: Integer;
begin
  if (ACanvas = nil) or (Layer = nil) or
    (ThumbnailRect.Width <= 0) or (ThumbnailRect.Height <= 0) then
    Exit;
  if FRenderedThumbnails.TryGetValue(Layer, CachedBitmap) and
    (CachedBitmap.Width = ThumbnailRect.Width) and
    (CachedBitmap.Height = ThumbnailRect.Height) then
  begin
    ACanvas.Draw(ThumbnailRect.Left, ThumbnailRect.Top, CachedBitmap);
    Exit;
  end;
  FRenderedThumbnails.Remove(Layer);
  RenderVectArtLayerThumbnail(Layer, FThumbnailBuffer,
    ThumbnailRect.Width, ThumbnailRect.Height);
  FThumbnailBitmap.PixelFormat := pf32bit;
  FThumbnailBitmap.SetSize(ThumbnailRect.Width, ThumbnailRect.Height);
  Source := FThumbnailBuffer.Data;
  for Y := 0 to ThumbnailRect.Height - 1 do
  begin
    Destination := FThumbnailBitmap.ScanLine[Y];
    for X := 0 to ThumbnailRect.Width - 1 do
    begin
      if Odd((X div Scale(THUMBNAIL_CHECKER_SIZE)) +
        (Y div Scale(THUMBNAIL_CHECKER_SIZE))) then
        BackgroundColor := TColor($00B8B8B8)
      else
        BackgroundColor := clWhite;
      BackgroundValue := ColorToRGB(BackgroundColor);
      Alpha := Source^.A;
      Destination[0] := (Cardinal(Source^.B) * Alpha +
        Cardinal(GetBValue(BackgroundValue)) * (255 - Alpha) + 127) div 255;
      Destination[1] := (Cardinal(Source^.G) * Alpha +
        Cardinal(GetGValue(BackgroundValue)) * (255 - Alpha) + 127) div 255;
      Destination[2] := (Cardinal(Source^.R) * Alpha +
        Cardinal(GetRValue(BackgroundValue)) * (255 - Alpha) + 127) div 255;
      Destination[3] := 255;
      Inc(Destination, 4);
      Inc(Source);
    end;
  end;
  CachedBitmap := Vcl.Graphics.TBitmap.Create;
  CachedBitmap.Assign(FThumbnailBitmap);
  FRenderedThumbnails.Add(Layer, CachedBitmap);
  ACanvas.Draw(ThumbnailRect.Left, ThumbnailRect.Top, CachedBitmap);
end;

procedure TMapRakuLayerThumbnailCache.SyncThumbnailCache;
begin
  if FDocument = nil then
  begin
    FRenderedThumbnails.Clear;
    FThumbnailRevision := -1;
    Exit;
  end;
  if FThumbnailRevision = FDocument.Revision then
    Exit;
  FRenderedThumbnails.Clear;
  FThumbnailRevision := FDocument.Revision;
end;

end.
