// AviUtl2の合成済みフレームバッファを編集画面用RGBAイメージとして保持する。
unit MapRakuFrameCapture;

interface

uses
  AviUtl2FilterTypes, System.SysUtils, Winapi.Windows;

type
  TMapRakuFrameCapture = class
  private
    FDevice: IInterface;
    FFormat: Integer;
    FHeight: Integer;
    FInitialized: Boolean;
    FLock: TRTLCriticalSection;
    FPixels: TBytes;
    FStagingTexture: IInterface;
    FStatus: string;
    FWidth: Integer;
    procedure ClearImage(const StatusText: string);
    procedure ResetGpuResources;
  public
    constructor Create;
    destructor Destroy; override;
    // 現在の合成済みフレームをCPUから参照できるRGBA8配列へ複製する。
    procedure Capture(Video: PFILTER_PROC_VIDEO);
    // 保持中の画像を呼び出し側所有の配列として複製する。
    function CopyRgba(out Pixels: TBytes; out Width, Height: Integer;
      out Status: string): Boolean;
  end;

implementation

uses
  System.Math, Winapi.D3D11, Winapi.DXGIFormat;

const
  MAX_CAPTURE_DIMENSION = 16384;

type
  TPixelWords = array[0..3] of Word;
  PPixelWords = ^TPixelWords;

function BytesPerPixel(Format: DXGI_FORMAT): Integer;
begin
  case Format of
    DXGI_FORMAT_R8G8B8A8_UNORM,
    DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
    DXGI_FORMAT_B8G8R8A8_UNORM,
    DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
      Result := 4;
    DXGI_FORMAT_R16G16B16A16_UNORM,
    DXGI_FORMAT_R16G16B16A16_FLOAT:
      Result := 8;
  else
    Result := 0;
  end;
end;

function HalfToSingle(Value: Word): Single;
var
  Exponent: Integer;
  Mantissa: Cardinal;
  ResultBits: Cardinal;
  SignBits: Cardinal;
begin
  SignBits := Cardinal(Value and $8000) shl 16;
  Exponent := (Value shr 10) and $1F;
  Mantissa := Value and $03FF;
  if Exponent = 0 then
  begin
    if Mantissa = 0 then
      ResultBits := SignBits
    else
    begin
      Exponent := -14;
      while (Mantissa and $0400) = 0 do
      begin
        Mantissa := Mantissa shl 1;
        Dec(Exponent);
      end;
      Mantissa := Mantissa and $03FF;
      ResultBits := SignBits or Cardinal(Exponent + 127) shl 23 or
        Mantissa shl 13;
    end;
  end
  else if Exponent = $1F then
    ResultBits := SignBits or $7F800000 or Mantissa shl 13
  else
    ResultBits := SignBits or Cardinal(Exponent + 112) shl 23 or
      Mantissa shl 13;
  Result := PSingle(@ResultBits)^;
end;

function FloatToByte(Value: Single): Byte;
begin
  if IsNan(Value) or (Value <= 0) then
    Exit(0);
  if Value >= 1 then
    Exit(255);
  Result := Round(Value * 255);
end;

constructor TMapRakuFrameCapture.Create;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FInitialized := True;
  FStatus := 'No framebuffer has been captured.';
end;

destructor TMapRakuFrameCapture.Destroy;
begin
  if FInitialized then
  begin
    EnterCriticalSection(FLock);
    try
      ResetGpuResources;
      FPixels := nil;
    finally
      LeaveCriticalSection(FLock);
    end;
    DeleteCriticalSection(FLock);
  end;
  inherited Destroy;
end;

procedure TMapRakuFrameCapture.ResetGpuResources;
begin
  FStagingTexture := nil;
  FDevice := nil;
end;

procedure TMapRakuFrameCapture.ClearImage(const StatusText: string);
begin
  FPixels := nil;
  FWidth := 0;
  FHeight := 0;
  FStatus := StatusText;
end;

procedure TMapRakuFrameCapture.Capture(Video: PFILTER_PROC_VIDEO);
var
  Context: ID3D11DeviceContext;
  Destination: PByte;
  Device: ID3D11Device;
  TextureFormat: DXGI_FORMAT;
  Height: Integer;
  I: Integer;
  Mapped: D3D11_MAPPED_SUBRESOURCE;
  PixelCount: NativeInt;
  Source: PByte;
  SourceDesc: D3D11_TEXTURE2D_DESC;
  SourcePointer: Pointer;
  SourceTexture: ID3D11Texture2D;
  SourceWords: PPixelWords;
  StagingDesc: D3D11_TEXTURE2D_DESC;
  StagingTexture: ID3D11Texture2D;
  Width: Integer;
  X: Integer;
  Y: Integer;
begin
  if not FInitialized then
    Exit;
  EnterCriticalSection(FLock);
  try
    try
      if (Video = nil) or not Assigned(Video^.GetFramebufferTexture2D) then
      begin
        ClearImage('Framebuffer callback is unavailable.');
        Exit;
      end;
      SourcePointer := Video^.GetFramebufferTexture2D();
      if SourcePointer = nil then
      begin
        ClearImage('Framebuffer texture is unavailable.');
        Exit;
      end;

      SourceTexture := ID3D11Texture2D(SourcePointer);
      SourceTexture.GetDesc(SourceDesc);
      Width := SourceDesc.Width;
      Height := SourceDesc.Height;
      TextureFormat := SourceDesc.Format;
      if (Width <= 0) or (Height <= 0) or
        (Width > MAX_CAPTURE_DIMENSION) or
        (Height > MAX_CAPTURE_DIMENSION) then
      begin
        ClearImage(System.SysUtils.Format('Invalid framebuffer size: %d x %d.',
          [Width, Height]));
        Exit;
      end;
      if BytesPerPixel(TextureFormat) = 0 then
      begin
        ClearImage(System.SysUtils.Format(
          'Unsupported framebuffer DXGI format: %d.',
          [Ord(TextureFormat)]));
        Exit;
      end;
      if SourceDesc.SampleDesc.Count <> 1 then
      begin
        ClearImage(System.SysUtils.Format(
          'Unsupported framebuffer sample count: %d.',
          [SourceDesc.SampleDesc.Count]));
        Exit;
      end;

      SourceTexture.GetDevice(Device);
      if Device = nil then
      begin
        ClearImage('Framebuffer device is unavailable.');
        Exit;
      end;
      if (FStagingTexture = nil) or
        (Pointer(FDevice) <> Pointer(Device)) or
        (FWidth <> Width) or (FHeight <> Height) or
        (FFormat <> Ord(TextureFormat)) then
      begin
        ResetGpuResources;
        StagingDesc := SourceDesc;
        StagingDesc.MipLevels := 1;
        StagingDesc.ArraySize := 1;
        StagingDesc.Usage := D3D11_USAGE_STAGING;
        StagingDesc.BindFlags := 0;
        StagingDesc.CPUAccessFlags := D3D11_CPU_ACCESS_READ;
        StagingDesc.MiscFlags := 0;
        if Device.CreateTexture2D(StagingDesc, nil, StagingTexture) < 0 then
        begin
          ClearImage('Could not create the framebuffer staging texture.');
          Exit;
        end;
        FStagingTexture := StagingTexture;
        FDevice := Device;
      end
      else
        StagingTexture := ID3D11Texture2D(FStagingTexture);

      Device.GetImmediateContext(Context);
      if Context = nil then
      begin
        ClearImage('D3D11 immediate context is unavailable.');
        Exit;
      end;
      Context.CopyResource(StagingTexture, SourceTexture);
      FillChar(Mapped, SizeOf(Mapped), 0);
      if Context.Map(StagingTexture, 0, D3D11_MAP_READ, 0, Mapped) < 0 then
      begin
        ClearImage('Could not map the framebuffer staging texture.');
        Exit;
      end;
      try
        PixelCount := NativeInt(Width) * Height;
        SetLength(FPixels, PixelCount * 4);
        Destination := @FPixels[0];
        for Y := 0 to Height - 1 do
        begin
          Source := PByte(Mapped.pData) + NativeInt(Y) * Mapped.RowPitch;
          case TextureFormat of
            DXGI_FORMAT_R8G8B8A8_UNORM,
            DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
              Move(Source^, Destination^, NativeInt(Width) * 4);
            DXGI_FORMAT_B8G8R8A8_UNORM,
            DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
              for X := 0 to Width - 1 do
              begin
                Destination[X * 4] := Source[X * 4 + 2];
                Destination[X * 4 + 1] := Source[X * 4 + 1];
                Destination[X * 4 + 2] := Source[X * 4];
                Destination[X * 4 + 3] := Source[X * 4 + 3];
              end;
            DXGI_FORMAT_R16G16B16A16_UNORM,
            DXGI_FORMAT_R16G16B16A16_FLOAT:
              begin
                SourceWords := PPixelWords(Source);
                for X := 0 to Width - 1 do
                begin
                  I := X * 4;
                  if TextureFormat = DXGI_FORMAT_R16G16B16A16_UNORM then
                  begin
                    Destination[I] := SourceWords[0] div 257;
                    Destination[I + 1] := SourceWords[1] div 257;
                    Destination[I + 2] := SourceWords[2] div 257;
                    Destination[I + 3] := SourceWords[3] div 257;
                  end
                  else
                  begin
                    Destination[I] := FloatToByte(HalfToSingle(SourceWords[0]));
                    Destination[I + 1] := FloatToByte(HalfToSingle(SourceWords[1]));
                    Destination[I + 2] := FloatToByte(HalfToSingle(SourceWords[2]));
                    Destination[I + 3] := Round(EnsureRange(
                      HalfToSingle(SourceWords[3]), 0.0, 1.0) * 255);
                  end;
                  Inc(SourceWords);
                end;
              end;
          end;
          Inc(Destination, NativeInt(Width) * 4);
        end;
      finally
        Context.Unmap(StagingTexture, 0);
      end;
      FWidth := Width;
      FHeight := Height;
      FFormat := Ord(TextureFormat);
      FStatus := System.SysUtils.Format(
        'Framebuffer: %d x %d, DXGI format %d.',
        [Width, Height, Ord(TextureFormat)]);
    except
      on E: Exception do
        ClearImage('Framebuffer capture failed: ' + E.Message);
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TMapRakuFrameCapture.CopyRgba(out Pixels: TBytes;
  out Width, Height: Integer; out Status: string): Boolean;
begin
  Pixels := nil;
  Width := 0;
  Height := 0;
  Status := '';
  if not FInitialized then
    Exit(False);
  EnterCriticalSection(FLock);
  try
    Status := FStatus;
    Result := (FWidth > 0) and (FHeight > 0) and
      (Length(FPixels) = NativeInt(FWidth) * FHeight * 4);
    if Result then
    begin
      Pixels := Copy(FPixels);
      Width := FWidth;
      Height := FHeight;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

end.
