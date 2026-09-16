// テクスチャの埋め込み画像と配置を保存し、Documentを変更する前に入力全体を検証する。
unit MapRakuTextureJson;

interface

uses System.JSON, MapRakuTextureStyle;

// 所有権を呼び出し側へ渡すJSONオブジェクトを生成する。
function WriteMapRakuTexture(const Texture: TMapRakuTextureStyle): TJSONObject;
// 型、範囲、画像データを検証して返す。不正入力はEConvertErrorを送出する。
function ReadMapRakuTexture(Json: TJSONObject): TMapRakuTextureStyle;

implementation

uses System.SysUtils, System.Math, MapRakuTextureRenderer;

function TextureNumber(Json: TJSONObject; const Name: string; MinValue, MaxValue: Double): Double;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if not (Value is TJSONNumber) then
    raise EConvertError.Create('Invalid texture field: ' + Name);
  Result := TJSONNumber(Value).AsDouble;
  if IsNan(Result) or IsInfinite(Result) or (Result < MinValue) or (Result > MaxValue) then
    raise EConvertError.Create('Texture field out of range: ' + Name);
end;

function TextureString(Json: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if not (Value is TJSONString) then
    raise EConvertError.Create('Invalid texture field: ' + Name);
  Result := Value.Value;
end;

function TextureBoolean(Json: TJSONObject; const Name: string;
  DefaultValue: Boolean): Boolean;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if Value = nil then
    Exit(DefaultValue);
  if not (Value is TJSONBool) then
    raise EConvertError.Create('Invalid texture field: ' + Name);
  Result := TJSONBool(Value).AsBoolean;
end;

function WriteMapRakuTexture(const Texture: TMapRakuTextureStyle): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'texture');
  Result.AddPair('data', Texture.Data);
  Result.AddPair('fileName', Texture.FileName);
  Result.AddPair('fit', TJSONNumber.Create(Ord(Texture.Fit)));
  Result.AddPair('repeat', TJSONNumber.Create(Ord(Texture.RepeatMode)));
  Result.AddPair('scale', TJSONNumber.Create(Texture.Scale));
  Result.AddPair('offsetX', TJSONNumber.Create(Texture.OffsetX));
  Result.AddPair('offsetY', TJSONNumber.Create(Texture.OffsetY));
  Result.AddPair('angle', TJSONNumber.Create(Texture.Angle));
  Result.AddPair('flipHorizontal', TJSONBool.Create(Texture.FlipHorizontal));
  Result.AddPair('flipVertical', TJSONBool.Create(Texture.FlipVertical));
end;

function ReadMapRakuTexture(Json: TJSONObject): TMapRakuTextureStyle;
var
  N: Double;
begin
  Result := TMapRakuTextureStyle.DefaultStyle;
  Result.Data := TextureString(Json, 'data');
  Result.FileName := TextureString(Json, 'fileName');
  N := TextureNumber(Json, 'fit', 0, 3);
  if Frac(N) <> 0 then
    raise EConvertError.Create('Invalid texture fit');
  Result.Fit := TMapRakuTextureFit(Trunc(N));
  N := TextureNumber(Json, 'repeat', 0, 2);
  if Frac(N) <> 0 then
    raise EConvertError.Create('Invalid texture repeat');
  Result.RepeatMode := TMapRakuTextureRepeat(Trunc(N));
  Result.Scale := TextureNumber(Json, 'scale', 0.01, 100);
  Result.OffsetX := TextureNumber(Json, 'offsetX', -1000, 1000);
  Result.OffsetY := TextureNumber(Json, 'offsetY', -1000, 1000);
  Result.Angle := TextureNumber(Json, 'angle', -360, 360);
  Result.FlipHorizontal := TextureBoolean(Json, 'flipHorizontal', False);
  Result.FlipVertical := TextureBoolean(Json, 'flipVertical', False);
  DecodeMapRakuTexture(Result.Data);
end;

end.
