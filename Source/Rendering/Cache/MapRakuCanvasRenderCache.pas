// 編集キャンバスの文書画像と、移動中に再利用する階層別RGBA画像を保持する。
unit MapRakuCanvasRenderCache;

interface

uses
  System.Types, Vcl.Graphics, MapRakuDocument, MapRakuRenderer;

type
  TMapRakuCanvasRenderCache = class
  private
    FBitmap             : TBitmap;                // VCLキャンバスへ転送する乗算済みRGBA画像。
    FBuffer             : TVectArtRenderBuffer;   // 合成または通常描画の作業領域。
    FInputTextLayer     : TMapRakuTextLayer; // 前回描画時の編集中テキスト。
    FMoveActive         : Boolean;                // 階層別画像を移動プレビューへ利用できる状態。
    FMoveAttempted      : Boolean;                // 現在のドラッグで開始判定を済ませたことを示す。
    FMoveHeight         : Integer;                // 階層別画像を作成した表示高さ。
    FMoveLayerIndex     : Integer;                // Document直下にある移動対象の位置。
    FMoveLower          : TVectArtRenderBuffer;   // 移動対象より背面の合成画像。
    FMoveSelected       : TVectArtRenderBuffer;   // 平行移動して合成する対象画像。
    FMoveStartBounds    : TRectF;                 // ドラッグ開始時のDocument座標範囲。
    FMoveUpper          : TVectArtRenderBuffer;   // 移動対象より前面の合成画像。
    FMoveWidth          : Integer;                // 階層別画像を作成した表示幅。
    FOutlineColor       : TColor;                 // 前回描画へ使用した編集輪郭色。
    FPreviewStrokeWidth : Single;                 // 前回描画へ使用したプレビュー線幅。
    FRevision           : Int64;                  // Bitmapへ反映済みのDocument Revision。
    procedure CopyBufferToBitmap(Width, Height: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    // 単一選択を上下の積層から分離し、移動中の再描画を平行移動合成へ切り替える。
    procedure BeginMove(Document: TVectArtDocument; LayerIndex, Width,
      Height: Integer; PreviewStrokeWidth: Single);
    // 移動用の階層キャッシュを無効にし、次回開始を試行可能にする。
    procedure EndMove;
    // Document交換時に文書画像と移動状態を破棄する。
    procedure Reset;
    // 現在のDocumentを文書画像へ反映する。連続ズーム中は有効な直前画像を再利用する。
    procedure Update(Document: TVectArtDocument; Width, Height: Integer;
      PreviewStrokeWidth: Single; InputTextLayer: TMapRakuTextLayer;
      OutlineColor: TColor; AllowZoomReuse, Moving: Boolean);
    property Bitmap: TBitmap read FBitmap;
    property MoveAttempted: Boolean read FMoveAttempted;
  end;

implementation

uses
  System.Math, MapRakuLayerGeometry;

constructor TMapRakuCanvasRenderCache.Create;
begin
  inherited Create;
  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf32bit;
  FBuffer := TVectArtRenderBuffer.Create;
  FMoveLower := TVectArtRenderBuffer.Create;
  FMoveSelected := TVectArtRenderBuffer.Create;
  FMoveUpper := TVectArtRenderBuffer.Create;
  FMoveLayerIndex := -1;
  FPreviewStrokeWidth := -1;
  FRevision := -1;
end;

destructor TMapRakuCanvasRenderCache.Destroy;
begin
  FMoveUpper.Free;
  FMoveSelected.Free;
  FMoveLower.Free;
  FBuffer.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure TMapRakuCanvasRenderCache.BeginMove(
  Document: TVectArtDocument; LayerIndex, Width, Height: Integer;
  PreviewStrokeWidth: Single);
begin
  EndMove;
  FMoveAttempted := True;
  if (Document = nil) or (Document.CanvasLayer = nil) or
    (LayerIndex <= 0) or (LayerIndex >= Document.LayerCount) or
    not TryGetMapRakuLayerBounds(Document[LayerIndex],
      FMoveStartBounds) then
    Exit;
  RenderVectArtDocumentRange(Document, FMoveLower, Width, Height,
    1, LayerIndex - 1, PreviewStrokeWidth);
  RenderVectArtDocumentRange(Document, FMoveSelected, Width, Height,
    LayerIndex, LayerIndex, PreviewStrokeWidth);
  RenderVectArtDocumentRange(Document, FMoveUpper, Width, Height,
    LayerIndex + 1, Document.LayerCount - 1, PreviewStrokeWidth);
  FMoveLayerIndex := LayerIndex;
  FMoveWidth := Width;
  FMoveHeight := Height;
  FMoveActive := True;
end;

procedure TMapRakuCanvasRenderCache.CopyBufferToBitmap(
  Width, Height: Integer);
var
  Alpha: Integer;
  Destination: PByte;
  Source: PVectArtRgbaPixel;
  X: Integer;
  Y: Integer;
begin
  FBitmap.PixelFormat := pf32bit;
  FBitmap.SetSize(Width, Height);
  FBitmap.AlphaFormat := afPremultiplied;
  Source := FBuffer.Data;
  for Y := 0 to Height - 1 do
  begin
    Destination := FBitmap.ScanLine[Y];
    for X := 0 to Width - 1 do
    begin
      Alpha := Source^.A;
      Destination[0] := (Integer(Source^.B) * Alpha + 127) div 255;
      Destination[1] := (Integer(Source^.G) * Alpha + 127) div 255;
      Destination[2] := (Integer(Source^.R) * Alpha + 127) div 255;
      Destination[3] := Alpha;
      Inc(Destination, 4);
      Inc(Source);
    end;
  end;
end;

procedure TMapRakuCanvasRenderCache.EndMove;
begin
  FMoveActive := False;
  FMoveAttempted := False;
  FMoveLayerIndex := -1;
  FMoveWidth := 0;
  FMoveHeight := 0;
end;

procedure TMapRakuCanvasRenderCache.Reset;
begin
  EndMove;
  FBitmap.SetSize(0, 0);
  FInputTextLayer := nil;
  FOutlineColor := clNone;
  FPreviewStrokeWidth := -1;
  FRevision := -1;
end;

procedure TMapRakuCanvasRenderCache.Update(Document: TVectArtDocument;
  Width, Height: Integer; PreviewStrokeWidth: Single;
  InputTextLayer: TMapRakuTextLayer; OutlineColor: TColor;
  AllowZoomReuse, Moving: Boolean);
var
  CurrentBounds: TRectF;
  OffsetX: Integer;
  OffsetY: Integer;
  UsingMovePreview: Boolean;
begin
  if (Document = nil) or (Document.CanvasLayer = nil) then
  begin
    Reset;
    Exit;
  end;
  if AllowZoomReuse and (FBitmap.Width > 0) and (FBitmap.Height > 0) and
    (FRevision = Document.Revision) and
    (FInputTextLayer = InputTextLayer) and (FOutlineColor = OutlineColor) and
    SameValue(FPreviewStrokeWidth, PreviewStrokeWidth) then
    Exit;
  UsingMovePreview := FMoveActive and Moving and
    (FMoveLayerIndex > 0) and (FMoveLayerIndex < Document.LayerCount) and
    (FMoveWidth = Width) and (FMoveHeight = Height) and
    TryGetMapRakuLayerBounds(Document[FMoveLayerIndex], CurrentBounds);
  if FMoveActive and not UsingMovePreview then
    EndMove;
  if UsingMovePreview then
  begin
    FBuffer.SetSize(Width, Height);
    Move(FMoveLower.Data^, FBuffer.Data^,
      FBuffer.PixelCount * SizeOf(TVectArtRgbaPixel));
    OffsetX := Round((CurrentBounds.Left - FMoveStartBounds.Left) *
      Width / Document.CanvasLayer.Width);
    OffsetY := Round((CurrentBounds.Top - FMoveStartBounds.Top) *
      Height / Document.CanvasLayer.Height);
    CompositeVectArtRgbaOffset(FMoveSelected, FBuffer.Data,
      Width, Height, OffsetX, OffsetY);
    CompositeVectArtRgba(FMoveUpper, FBuffer.Data, Width, Height);
  end
  else if (FRevision = Document.Revision) and
    (FInputTextLayer = InputTextLayer) and (FOutlineColor = OutlineColor) and
    SameValue(FPreviewStrokeWidth, PreviewStrokeWidth) and
    (FBitmap.Width = Width) and (FBitmap.Height = Height) then
    Exit
  else
    RenderVectArtDocument(Document, FBuffer, Width, Height,
      PreviewStrokeWidth, InputTextLayer, OutlineColor);
  CopyBufferToBitmap(Width, Height);
  if not UsingMovePreview then
  begin
    FRevision := Document.Revision;
    FInputTextLayer := InputTextLayer;
    FOutlineColor := OutlineColor;
    FPreviewStrokeWidth := PreviewStrokeWidth;
  end;
end;

end.
