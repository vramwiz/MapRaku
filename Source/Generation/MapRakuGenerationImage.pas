// 受信した元地図PNGを検査し、画像全体を保ったまま用紙の縦横比へ正規化する。
unit MapRakuGenerationImage;
interface
uses System.SysUtils, System.Skia, System.Types, MapRakuTraceOptions;
function NormalizeGenerationImage(const Bytes: TBytes; CanvasWidth, CanvasHeight: Integer): TBytes;
function GenerationImageHash(const Bytes: TBytes): string;
// Boundsが読み取り対象の枠。画面と送信用PNGは同じ変換・クリップを使う。
procedure DrawGenerationReference(const Canvas: ISkCanvas; const Image: ISkImage;
  const Bounds: TRectF; const Options: TMapRakuTraceOptions); overload;
// 周囲の画像も表示する場合だけClipBoundsを広げる。変換の基準は常にBounds。
procedure DrawGenerationReference(const Canvas: ISkCanvas; const Image: ISkImage;
  const Bounds, ClipBounds: TRectF; const Options: TMapRakuTraceOptions); overload;
function BuildGenerationReference(const Bytes: TBytes; const Options: TMapRakuTraceOptions): TBytes;
implementation
uses System.Classes, System.Math, System.Hash,
  System.UITypes, MapRakuAutomationValues;

function ReadBigEndian(const Bytes: TBytes; Offset: Integer): Cardinal;
begin
  Result := (Cardinal(Bytes[Offset]) shl 24) or (Cardinal(Bytes[Offset+1]) shl 16) or
    (Cardinal(Bytes[Offset+2]) shl 8) or Cardinal(Bytes[Offset+3]);
end;

function NormalizeGenerationImage(const Bytes: TBytes; CanvasWidth, CanvasHeight: Integer): TBytes;
var Image: ISkImage; Surface: ISkSurface; Stream: TBytesStream;
  W, H: Integer; Scale, ImageScale: Single; SourceWidth, SourceHeight: Cardinal;
begin
  Require((Length(Bytes)>=33) and (Length(Bytes)<=32*1024*1024), '元地図PNGの大きさが不正です。');
  Require((ReadBigEndian(Bytes,0)=$89504E47) and (ReadBigEndian(Bytes,4)=$0D0A1A0A) and
    (ReadBigEndian(Bytes,12)=$49484452), '元地図画像はPNGで渡してください。');
  // デコード前に寸法を制限し、巨大な展開領域を確保しない。
  SourceWidth := ReadBigEndian(Bytes,16); SourceHeight := ReadBigEndian(Bytes,20);
  Require((SourceWidth>0) and (SourceHeight>0) and (SourceWidth<=8192) and
    (SourceHeight<=8192) and (UInt64(SourceWidth)*SourceHeight<=33554432), '元地図画像の解像度が大きすぎます。');
  Require((CanvasWidth>=64) and (CanvasHeight>=64), '用紙寸法が不正です。');
  Image := TSkImage.MakeFromEncoded(Bytes); Require(Image<>nil, '元地図PNGを復号できません。');
  Scale := Min(1,2048/Max(CanvasWidth,CanvasHeight));
  W := Max(1,Round(CanvasWidth*Scale)); H := Max(1,Round(CanvasHeight*Scale));
  Surface := TSkSurface.MakeRaster(W,H); Require(Surface<>nil, '元地図画像の表示領域を作成できません。');
  Surface.Canvas.Clear(TAlphaColorRec.White);
  ImageScale := Min(W/Image.Width,H/Image.Height);
  Surface.Canvas.DrawImageRect(Image,TRectF.Create((W-Image.Width*ImageScale)/2,
    (H-Image.Height*ImageScale)/2,(W+Image.Width*ImageScale)/2,(H+Image.Height*ImageScale)/2));
  Stream := TBytesStream.Create;
  try
    Surface.MakeImageSnapshot.EncodeToStream(Stream);
    Result := Copy(Stream.Bytes,0,Stream.Size);
  finally Stream.Free; end;
end;

procedure DrawGenerationReference(const Canvas: ISkCanvas; const Image: ISkImage;
  const Bounds: TRectF; const Options: TMapRakuTraceOptions);
begin
  DrawGenerationReference(Canvas,Image,Bounds,Bounds,Options);
end;

procedure DrawGenerationReference(const Canvas: ISkCanvas; const Image: ISkImage;
  const Bounds, ClipBounds: TRectF; const Options: TMapRakuTraceOptions);
var Paint: ISkPaint; Scale: Single;
begin
  Canvas.Save;
  try
    Canvas.ClipRect(ClipBounds); Paint := TSkPaint.Create; Paint.Color := TAlphaColorRec.White;
    Canvas.DrawRect(ClipBounds,Paint);
    if Image=nil then Exit;
    Scale := Min(Bounds.Width/Image.Width,Bounds.Height/Image.Height)*Options.Zoom;
    Canvas.Translate(Bounds.CenterPoint.X+Options.PanX*Bounds.Width,
      Bounds.CenterPoint.Y+Options.PanY*Bounds.Height);
    Canvas.Rotate(Options.Rotation); Canvas.Scale(Scale,Scale);
    Canvas.DrawImage(Image,-Image.Width/2,-Image.Height/2);
  finally Canvas.Restore; end;
end;

function BuildGenerationReference(const Bytes: TBytes; const Options: TMapRakuTraceOptions): TBytes;
var Image: ISkImage; Surface: ISkSurface; Stream: TBytesStream;
begin
  if Options.IdentityView then Exit(Copy(Bytes));
  Image := TSkImage.MakeFromEncoded(Bytes); Require(Image<>nil,'参照画像を読み取れません。');
  Surface := TSkSurface.MakeRaster(Image.Width,Image.Height);
  Require(Surface<>nil,'参照範囲の画像を作成できません。');
  DrawGenerationReference(Surface.Canvas,Image,TRectF.Create(0,0,Image.Width,Image.Height),Options);
  Stream := TBytesStream.Create;
  try Surface.MakeImageSnapshot.EncodeToStream(Stream); Result := Copy(Stream.Bytes,0,Stream.Size);
  finally Stream.Free; end;
end;

function GenerationImageHash(const Bytes: TBytes): string;
var Hash: THashSHA2;
begin
  Hash := THashSHA2.Create; Hash.Update(Bytes); Result := LowerCase(Hash.HashAsString);
end;
end.
