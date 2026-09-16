// ストレートアルファRGBA8の保管・透明度調整・合成を担う。文書やUIには依存しない。
unit MapRakuRenderBuffer;
interface

type
  TVectArtRgbaPixel = packed record
    R: Byte; // ストレートアルファ合成前の赤成分。
    G: Byte; // ストレートアルファ合成前の緑成分。
    B: Byte; // ストレートアルファ合成前の青成分。
    A: Byte; // 0を透明、255を不透明とするアルファ成分。
  end;
  PVectArtRgbaPixel = ^TVectArtRgbaPixel;

  TVectArtRenderBuffer = class
  private
    FHeight: Integer;
    FPixels: TArray<TVectArtRgbaPixel>;
    FWidth: Integer;
    function GetData: PVectArtRgbaPixel;
    function GetPixelCount: NativeInt;
    function GetStride: NativeInt;
  public
    procedure Clear;
    procedure SetSize(AWidth, AHeight: Integer);
    property Data: PVectArtRgbaPixel read GetData;
    property Height: Integer read FHeight;
    property PixelCount: NativeInt read GetPixelCount;
    property Pixels: TArray<TVectArtRgbaPixel> read FPixels;
    property Stride: NativeInt read GetStride;
    property Width: Integer read FWidth;
  end;

// ストレートアルファRGBA8同士をSource-overで合成する。
procedure CompositeVectArtRgba(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height: Integer);
// Sourceを整数ピクセルだけ移動してSource-over合成する。領域外は切り捨てる。
procedure CompositeVectArtRgbaOffset(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height, OffsetX,
  OffsetY: Integer);

// 不透明度はアルファ成分だけへ適用し、未乗算RGBを維持する。
procedure MultiplyMapRakuBufferOpacity(Target: TVectArtRenderBuffer; Opacity: Single);
implementation
uses System.SysUtils, System.Math;
const MAX_RENDER_DIMENSION = 16384;

procedure TVectArtRenderBuffer.Clear;
begin
  if Length(FPixels) > 0 then
    FillChar(FPixels[0], Length(FPixels) * SizeOf(TVectArtRgbaPixel), 0);
end;

function TVectArtRenderBuffer.GetData: PVectArtRgbaPixel;
begin
  if Length(FPixels) = 0 then
    Result := nil
  else
    Result := @FPixels[0];
end;

function TVectArtRenderBuffer.GetPixelCount: NativeInt;
begin
  Result := Length(FPixels);
end;

function TVectArtRenderBuffer.GetStride: NativeInt;
begin
  Result := NativeInt(FWidth) * SizeOf(TVectArtRgbaPixel);
end;

procedure TVectArtRenderBuffer.SetSize(AWidth, AHeight: Integer);
var
  Count: Int64;
begin
  if (AWidth < 0) or (AHeight < 0) or
    (AWidth > MAX_RENDER_DIMENSION) or (AHeight > MAX_RENDER_DIMENSION) then
    // 不正な寸法による過大確保と、後続の画素数計算の破綻を防ぐ。
    raise EArgumentOutOfRangeException.Create('Invalid render dimensions');
  Count := Int64(AWidth) * AHeight;
  if Count > MaxInt then
    raise EArgumentOutOfRangeException.Create('Render buffer is too large');
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FPixels, NativeInt(Count));
end;

procedure MultiplyMapRakuBufferOpacity(Target: TVectArtRenderBuffer;
  Opacity: Single);
var
  I: Integer;
begin
  if Target = nil then
    Exit;
  Opacity := EnsureRange(Opacity, 0.0, 1.0);
  if Opacity >= 1.0 then
    Exit;
  for I := 0 to Target.PixelCount - 1 do
    Target.Pixels[I].A := EnsureRange(
      Round(Target.Pixels[I].A * Opacity), 0, 255);
end;

procedure CompositeVectArtRgba(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height: Integer);
var
  AlphaDenominator: Cardinal;
  DestinationAlpha: Cardinal;
  DestinationPixel: PVectArtRgbaPixel;
  I: NativeInt;
  PixelCount: NativeInt;
  SourceAlpha: Cardinal;
  SourcePixel: PVectArtRgbaPixel;
begin
  if (Source = nil) or (Destination = nil) or
    (Source.Width <> Width) or (Source.Height <> Height) then
    Exit;
  PixelCount := NativeInt(Width) * Height;
  SourcePixel := Source.Data;
  DestinationPixel := Destination;
  for I := 0 to PixelCount - 1 do
  begin
    SourceAlpha := SourcePixel^.A;
    if SourceAlpha = 255 then
      DestinationPixel^ := SourcePixel^
    else if SourceAlpha <> 0 then
    begin
      DestinationAlpha := DestinationPixel^.A;
      AlphaDenominator := SourceAlpha * 255 +
        DestinationAlpha * (255 - SourceAlpha);
      if AlphaDenominator <> 0 then
      begin
        DestinationPixel^.R :=
          (Cardinal(SourcePixel^.R) * SourceAlpha * 255 +
           Cardinal(DestinationPixel^.R) * DestinationAlpha *
             (255 - SourceAlpha) + AlphaDenominator div 2) div
          AlphaDenominator;
        DestinationPixel^.G :=
          (Cardinal(SourcePixel^.G) * SourceAlpha * 255 +
           Cardinal(DestinationPixel^.G) * DestinationAlpha *
             (255 - SourceAlpha) + AlphaDenominator div 2) div
          AlphaDenominator;
        DestinationPixel^.B :=
          (Cardinal(SourcePixel^.B) * SourceAlpha * 255 +
           Cardinal(DestinationPixel^.B) * DestinationAlpha *
             (255 - SourceAlpha) + AlphaDenominator div 2) div
          AlphaDenominator;
        DestinationPixel^.A := (AlphaDenominator + 127) div 255;
      end;
    end;
    Inc(SourcePixel);
    Inc(DestinationPixel);
  end;
end;

procedure CompositeVectArtRgbaOffset(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height, OffsetX,
  OffsetY: Integer);
var
  AlphaDenominator: Cardinal;
  DestinationAlpha: Cardinal;
  DestinationPixel: PVectArtRgbaPixel;
  DestinationY: Integer;
  EndX: Integer;
  SourceAlpha: Cardinal;
  SourcePixel: PVectArtRgbaPixel;
  SourceX: Integer;
  SourceY: Integer;
  StartX: Integer;
begin
  if (Source = nil) or (Destination = nil) or
    (Source.Width <> Width) or (Source.Height <> Height) then
    Exit;
  StartX := Max(0, -OffsetX);
  EndX := Min(Width - 1, Width - 1 - OffsetX);
  if StartX > EndX then
    Exit;
  for SourceY := 0 to Height - 1 do
  begin
    DestinationY := SourceY + OffsetY;
    if (DestinationY < 0) or (DestinationY >= Height) then
      Continue;
    SourcePixel := Source.Data;
    Inc(SourcePixel, NativeInt(SourceY) * Width + StartX);
    DestinationPixel := Destination;
    Inc(DestinationPixel, NativeInt(DestinationY) * Width +
      StartX + OffsetX);
    for SourceX := StartX to EndX do
    begin
      SourceAlpha := SourcePixel^.A;
      if SourceAlpha = 255 then
        DestinationPixel^ := SourcePixel^
      else if SourceAlpha <> 0 then
      begin
        DestinationAlpha := DestinationPixel^.A;
        AlphaDenominator := SourceAlpha * 255 +
          DestinationAlpha * (255 - SourceAlpha);
        if AlphaDenominator <> 0 then
        begin
          DestinationPixel^.R :=
            (Cardinal(SourcePixel^.R) * SourceAlpha * 255 +
             Cardinal(DestinationPixel^.R) * DestinationAlpha *
               (255 - SourceAlpha) + AlphaDenominator div 2) div
            AlphaDenominator;
          DestinationPixel^.G :=
            (Cardinal(SourcePixel^.G) * SourceAlpha * 255 +
             Cardinal(DestinationPixel^.G) * DestinationAlpha *
               (255 - SourceAlpha) + AlphaDenominator div 2) div
            AlphaDenominator;
          DestinationPixel^.B :=
            (Cardinal(SourcePixel^.B) * SourceAlpha * 255 +
             Cardinal(DestinationPixel^.B) * DestinationAlpha *
               (255 - SourceAlpha) + AlphaDenominator div 2) div
            AlphaDenominator;
          DestinationPixel^.A := (AlphaDenominator + 127) div 255;
        end;
      end;
      Inc(SourcePixel);
      Inc(DestinationPixel);
    end;
  end;
end;

end.
