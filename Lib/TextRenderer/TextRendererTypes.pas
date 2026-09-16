// テキスト描画要求、出力画像、計測値のバックエンド共通データ型を定義する。
unit TextRendererTypes;

interface

uses
  System.SysUtils,
  System.Types,
  System.UITypes;

type
  TTextRenderFontStyleItem = (Bold, Italic);
  TTextRenderFontStyle = set of TTextRenderFontStyleItem;
  TTextRenderDirection = (Horizontal, Vertical);
  TTextRenderAlignment = (Leading, Center, Trailing);

  TTextRenderOutline = record
    BlurRadius: Single;  // 輪郭端へ適用するぼかし半径。
    Color: TAlphaColor;  // 輪郭のARGB色。
    Width: Single;       // 文字輪郭から外側へ広げる幅。
    // ぼかしなしの輪郭設定を生成する。
    class function Create(const AWidth: Single;
      const AColor: TAlphaColor): TTextRenderOutline; overload; static;
    // 幅とぼかし半径を指定した輪郭設定を生成する。
    class function Create(const AWidth, ABlurRadius: Single;
      const AColor: TAlphaColor): TTextRenderOutline; overload; static;
  end;

  TTextRenderShadow = record
    BlurRadius: Single;   // 影のぼかし半径。
    Color: TAlphaColor;   // 影のARGB色。
    Offset: TPointF;      // 本文から影をずらす描画座標量。
    SpreadRadius: Single; // ぼかす前に影を外側へ広げる半径。
  end;

  TTextRenderRequest = record
    Alignment: TTextRenderAlignment;     // 行送りと直交する方向の揃え方。
    CaptureTextUnits: Boolean;           // 文字・グリフ単位の画像も生成するか。
    Direction: TTextRenderDirection;     // 横書きまたは縦書き。
    FillColor: TAlphaColor;              // 本文のARGB色。
    FontFamilies: TArray<string>;        // 優先順のフォント候補。
    FontSize: Single;                    // 描画座標単位のフォントサイズ。
    FontStyle: TTextRenderFontStyle;     // 太字・斜体の指定。
    LetterSpacing: Single;               // 文字間へ加える距離。
    LineSpacing: Single;                 // 行間へ加える距離。
    MaxHeight: Single;                   // 配置領域の最大高。0は無制限。
    MaxWidth: Single;                    // 配置領域の最大幅。0は無制限。
    Outlines: TArray<TTextRenderOutline>; // 内側から順に描く輪郭群。
    Shadows: TArray<TTextRenderShadow>;  // 本文より先に描く影群。
    Text: string;                        // 描画対象のUnicode文字列。
    TrimTransparentBounds: Boolean;      // 透明な外周を出力から除くか。
    // 通常の横書きに適した初期値を返す。
    class function Default: TTextRenderRequest; static;
  end;

  TTextRenderPixel = packed record
    R: Byte; // 赤成分。
    G: Byte; // 緑成分。
    B: Byte; // 青成分。
    A: Byte; // アルファ成分。
  end;
  PTextRenderPixel = ^TTextRenderPixel;

  TTextRenderMetrics = record
    DrawMilliseconds: Double;                // ラスター描画に要した時間。
    LayoutMilliseconds: Double;              // 文字配置に要した時間。
    NonTransparentPixelCount: NativeUInt;    // アルファが0でない画素数。
    TotalMilliseconds: Double;               // Render全体に要した時間。
  end;

  TTextRenderImage = class
  private
    FBounds: TRect;
    FLayoutBounds: TRect;
    FLineLayoutBounds: TArray<TRect>;
    FPixels: TArray<TTextRenderPixel>;
    FTextUnitBounds: TArray<TRect>;
    FTextUnitImages: TArray<TTextRenderImage>;
    function GetHeight: Integer;
    function GetStride: NativeInt;
    function GetWidth: Integer;
  public
    // 描画範囲と配置範囲が同じ空画像を生成する。
    constructor Create(const ABounds: TRect); overload;
    // 描画範囲と元の配置範囲を分けて保持する空画像を生成する。
    constructor Create(const ABounds, ALayoutBounds: TRect); overload;
    destructor Destroy; override;
    // 画素と文字単位の付随データを透明な初期状態へ戻す。
    procedure Clear;
    // 連続した先頭画素へのポインタを返す。空画像ではnilを返す。
    function Data: PTextRenderPixel;
    // 幅または高さが0ならTrueを返す。
    function IsEmpty: Boolean;
    // 確保されている画素数を返す。
    function PixelCount: NativeInt;
    // 文字単位画像の所有権をこの画像へ移す。
    procedure SetTextUnitImages(const AImages: TArray<TTextRenderImage>);
    property Bounds: TRect read FBounds;
    property Height: Integer read GetHeight;
    property LayoutBounds: TRect read FLayoutBounds;
    property LineLayoutBounds: TArray<TRect> read FLineLayoutBounds
      write FLineLayoutBounds;
    property Pixels: TArray<TTextRenderPixel> read FPixels;
    property Stride: NativeInt read GetStride;
    // レンダラーが配置した文字・グリフ単位の実描画範囲。画像左上を原点とする。
    property TextUnitBounds: TArray<TRect> read FTextUnitBounds
      write FTextUnitBounds;
    // 各文字・グリフだけを描いた独立レイヤー。CaptureTextUnits要求時だけ生成する。
    property TextUnitImages: TArray<TTextRenderImage> read FTextUnitImages;
    property Width: Integer read GetWidth;
  end;

implementation

{ TTextRenderOutline }

class function TTextRenderOutline.Create(const AWidth: Single;
  const AColor: TAlphaColor): TTextRenderOutline;
begin
  Result.Width := AWidth;
  Result.BlurRadius := 0;
  Result.Color := AColor;
end;

class function TTextRenderOutline.Create(const AWidth,
  ABlurRadius: Single; const AColor: TAlphaColor): TTextRenderOutline;
begin
  Result.Width := AWidth;
  Result.BlurRadius := ABlurRadius;
  Result.Color := AColor;
end;

{ TTextRenderRequest }

class function TTextRenderRequest.Default: TTextRenderRequest;
begin
  Result := System.Default(TTextRenderRequest);
  Result.Alignment := TTextRenderAlignment.Leading;
  Result.Direction := TTextRenderDirection.Horizontal;
  Result.FillColor := TAlphaColorRec.White;
  Result.FontFamilies := ['Yu Gothic UI', 'Meiryo UI', 'Segoe UI'];
  Result.FontSize := 32;
  Result.TrimTransparentBounds := True;
end;

{ TTextRenderImage }

constructor TTextRenderImage.Create(const ABounds: TRect);
begin
  Create(ABounds, ABounds);
end;

constructor TTextRenderImage.Create(const ABounds,
  ALayoutBounds: TRect);
begin
  inherited Create;
  if (ABounds.Width < 0) or (ABounds.Height < 0) then
    raise EArgumentOutOfRangeException.Create('Image bounds must not have negative dimensions.');
  if (ALayoutBounds.Width < 0) or (ALayoutBounds.Height < 0) then
    raise EArgumentOutOfRangeException.Create(
      'Image layout bounds must not have negative dimensions.');
  FBounds := ABounds;
  FLayoutBounds := ALayoutBounds;
  SetLength(FPixels, NativeInt(ABounds.Width) * ABounds.Height);
end;

destructor TTextRenderImage.Destroy;
var
  Image: TTextRenderImage;
begin
  for Image in FTextUnitImages do
    Image.Free;
  inherited;
end;

procedure TTextRenderImage.Clear;
begin
  if Length(FPixels) > 0 then
    FillChar(FPixels[0], Length(FPixels) * SizeOf(TTextRenderPixel), 0);
end;

function TTextRenderImage.Data: PTextRenderPixel;
begin
  if Length(FPixels) = 0 then
    Result := nil
  else
    Result := @FPixels[0];
end;

function TTextRenderImage.GetHeight: Integer;
begin
  Result := FBounds.Height;
end;

function TTextRenderImage.GetStride: NativeInt;
begin
  Result := NativeInt(Width) * SizeOf(TTextRenderPixel);
end;

function TTextRenderImage.GetWidth: Integer;
begin
  Result := FBounds.Width;
end;

function TTextRenderImage.IsEmpty: Boolean;
begin
  Result := Length(FPixels) = 0;
end;

function TTextRenderImage.PixelCount: NativeInt;
begin
  Result := Length(FPixels);
end;

procedure TTextRenderImage.SetTextUnitImages(
  const AImages: TArray<TTextRenderImage>);
var
  Image: TTextRenderImage;
begin
  for Image in FTextUnitImages do
    Image.Free;
  FTextUnitImages := System.Copy(AImages, 0, Length(AImages));
end;

end.
