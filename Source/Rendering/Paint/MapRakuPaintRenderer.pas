// レイヤー共通の単色、グラデーション、パターン、画像テクスチャをSkiaの描画設定へ変換する。
unit MapRakuPaintRenderer;

interface

uses
  System.Skia, System.Types, System.UITypes, Vcl.Graphics,
  MapRakuDocument;

// VCL色と0..1の不透明度をSkiaのアルファ色へ変換する。
function VclColorToAlphaColor(Color: TColor; Opacity: Single): TAlphaColor;
// レイヤー回転を含むDocument座標で描画スタイルをPaintへ設定する。
procedure ApplyMapRakuPaintStyle(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single);
// 呼び出し側のCanvas変換前座標で、指定範囲へ描画スタイルを設定する。
procedure ApplyMapRakuPaintStyleLocal(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single;
  const Bounds: TRectF);

// 線の中心経路を参照する種別だけ、距離に基づくシェーダーへ置き換える。
procedure ApplyMapRakuStrokeGradient(const Paint: ISkPaint; Layer: TVectArtLayer;
  const Path: ISkPath; Opacity, StrokeWidth: Single);

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, MapRakuLayerGeometry,
  MapRakuPaintStyles, MapRakuTextureRenderer, MapRakuPatternRenderer;

type
  TGradientUniforms = packed record
    Axis: array[0..3] of Single; // 始点XYと方向XY。SkSLのfloat4に対応。
    Options: array[0..1] of Single; // 副軸倍率と種別。SkSLのfloat2に対応。
  end;
  TStrokeUniforms = packed record
    Segments: array[0..63, 0..3] of Single; // 近似線分の始点XYと方向XY。
    Distances: array[0..63, 0..1] of Single; // 累積長と線分長。
    Options: array[0..3] of Single; // 線分数、総延長、線幅、種別。
  end;

function MakeGradientRamp(const Style: TMapRakuPaintStyle; Opacity: Single;
  const StartPoint, EndPoint: TPointF): ISkShader;
var
  Colors: TArray<TAlphaColor>;
  Positions: TArray<Single>;
  Stops: TArray<TMapRakuGradientStop>;
  I: Integer;
begin
  Stops := Style.GetGradientStops;
  SetLength(Colors, Length(Stops) + 2);
  SetLength(Positions, Length(Colors));
  Colors[0] := VclColorToAlphaColor(Style.GradientStartColor, Opacity * Style.GradientStartOpacity);
  Positions[0] := 0;
  for I := 0 to High(Stops) do
  begin
    Colors[I + 1] := VclColorToAlphaColor(Stops[I].Color, Opacity * Stops[I].Opacity);
    Positions[I + 1] := Stops[I].Offset;
  end;
  Colors[High(Colors)] := VclColorToAlphaColor(Style.GradientEndColor, Opacity * Style.GradientEndOpacity);
  Positions[High(Positions)] := 1;
  Result := TSkShader.MakeGradientLinear(StartPoint, EndPoint, Colors, Positions);
end;

procedure ApplyMapRakuStrokeGradient(const Paint: ISkPaint; Layer: TVectArtLayer;
  const Path: ISkPath; Opacity, StrokeWidth: Single);
const
  CODE = 'uniform shader ramp; uniform float4 segments[64]; uniform float2 distances[64]; ' +
    'uniform float4 options; half4 main(float2 p) { float best=1e30; float value=0; ' +
    'for (int i=0; i<64; ++i) { if (float(i)<options.x) { float2 d=segments[i].zw; ' +
    'float t=clamp(dot(p-segments[i].xy,d)/max(dot(d,d),0.000001),0.0,1.0); ' +
    'float2 delta=p-segments[i].xy-t*d; float dist=dot(delta,delta); ' +
    'if(dist<best) { best=dist; value=options.w<0.5 ? ' +
    '(distances[i].x+t*distances[i].y)/max(options.y,0.0001) : ' +
    '0.5+dot(delta,float2(-d.y,d.x))/max(length(d)*options.z,0.0001); } } } ' +
    'return ramp.eval(float2(value,0)); }';
var
  Effect: ISkRuntimeEffect;
  Builder: ISkRuntimeShaderBuilder;
  Measure: ISkPathMeasure;
  U: TStrokeUniforms;
  A, B, Tangent: TPointF;
  I: Integer;
  ErrorText: string;
begin
  if (Layer.PaintStyle.Kind <> slpkGradient) or
    not (Layer.PaintStyle.GradientKind in [slgkAlongStroke, slgkAcrossStroke]) then
    Exit;
  Measure := TSkPathMeasure.Create(Path, False);
  if Measure.Length < 0.0001 then
    Exit;
  U := Default(TStrokeUniforms);
  U.Options[0] := 64;
  U.Options[1] := Measure.Length;
  U.Options[2] := StrokeWidth;
  U.Options[3] := Ord(Layer.PaintStyle.GradientKind = slgkAcrossStroke);
  Measure.GetPositionAndTangent(0, A, Tangent);
  for I := 0 to 63 do
  begin
    Measure.GetPositionAndTangent(Measure.Length * (I + 1) / 64, B, Tangent);
    U.Segments[I, 0] := A.X;
    U.Segments[I, 1] := A.Y;
    U.Segments[I, 2] := B.X - A.X;
    U.Segments[I, 3] := B.Y - A.Y;
    U.Distances[I, 0] := Measure.Length * I / 64;
    U.Distances[I, 1] := Measure.Length / 64;
    A := B;
  end;
  Effect := TSkRuntimeEffect.MakeForShader(CODE, ErrorText);
  if Effect = nil then
    raise EInvalidOpException.Create('Stroke gradient: ' + ErrorText);
  Builder := TSkRuntimeShaderBuilder.Create(Effect);
  Builder.SetUniform('segments', U.Segments, SizeOf(U.Segments));
  Builder.SetUniform('distances', U.Distances, SizeOf(U.Distances));
  Builder.SetUniform('options', U.Options, SizeOf(U.Options));
  Builder.SetChild('ramp', MakeGradientRamp(Layer.PaintStyle, Opacity, TPointF.Zero, TPointF.Create(1, 0)));
  Paint.Shader := Builder.MakeShader;
  Paint.Color := TAlphaColorRec.White;
end;

procedure ApplyMapRakuPaintStyleBetween(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single;
  const StartPoint, EndPoint: TPointF);
const
  CODE = 'uniform shader ramp; uniform float4 axis; uniform float2 options; ' +
    'half4 main(float2 p) { float2 v=p-axis.xy; float2 d=axis.zw; ' +
    'float l=max(dot(d,d),0.000001); float x=dot(v,d)/l; ' +
    'float y=dot(v,float2(-d.y,d.x))/l/max(options.x,0.01); float t=x; ' +
    'if(options.y==1.0) t=length(float2(x,y)); ' +
    'if(options.y==2.0) t=max(abs(x),abs(y)); ' +
    'if(options.y==3.0) t=fract(atan(y,x)/6.28318530718+1.0); ' +
    'return ramp.eval(float2(t,0)); }';
var
  Style: TMapRakuPaintStyle;
  Effect: ISkRuntimeEffect;
  Builder: ISkRuntimeShaderBuilder;
  U: TGradientUniforms;
  ErrorText: string;
begin
  Paint.Shader := nil;
  if Layer = nil then
    Exit;
  Style := Layer.PaintStyle;
  if Style.Kind = slpkGradient then
  begin
    if Hypot(EndPoint.X - StartPoint.X, EndPoint.Y - StartPoint.Y) < 0.0001 then
    begin
      Paint.Color := VclColorToAlphaColor(Style.GradientEndColor, Opacity * Style.GradientEndOpacity);
      Exit;
    end;
    if Style.GradientKind in [slgkLinear, slgkAlongStroke, slgkAcrossStroke] then
    begin
      Paint.Shader := MakeGradientRamp(Style, Opacity, StartPoint, EndPoint);
      Paint.Color := TAlphaColorRec.White;
      Exit;
    end;
    U.Axis[0] := StartPoint.X;
    U.Axis[1] := StartPoint.Y;
    U.Axis[2] := EndPoint.X - StartPoint.X;
    U.Axis[3] := EndPoint.Y - StartPoint.Y;
    U.Options[0] := Style.GradientAspect;
    U.Options[1] := Ord(Style.GradientKind);
    Effect := TSkRuntimeEffect.MakeForShader(CODE, ErrorText);
    if Effect = nil then
      raise EInvalidOpException.Create('Gradient: ' + ErrorText);
    Builder := TSkRuntimeShaderBuilder.Create(Effect);
    Builder.SetUniform('axis', U.Axis, SizeOf(U.Axis));
    Builder.SetUniform('options', U.Options, SizeOf(U.Options));
    Builder.SetChild('ramp', MakeGradientRamp(Style, Opacity, TPointF.Zero, TPointF.Create(1, 0)));
    Paint.Shader := Builder.MakeShader;
    Paint.Color := TAlphaColorRec.White;
    Exit;
  end;
  Paint.Color := VclColorToAlphaColor(FallbackColor, Opacity);
end;

procedure ApplyMapRakuPaintStyle(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single);
var
  Bounds: TRectF;
  EndPoint: TPointF;
  RotationDegrees: Single;
  StartPoint: TPointF;
begin
  if (Layer <> nil) and
    TryGetMapRakuLayerPaintGeometry(Layer, Bounds,
      RotationDegrees) then
  begin
    if Layer.PaintStyle.Kind = slpkPattern then
    begin
      ApplyMapRakuPattern(Paint, Layer.PaintStyle.Pattern, Bounds, RotationDegrees, Opacity);
      Exit;
    end;
    if Layer.PaintStyle.Kind = slpkTexture then
    begin
      ApplyMapRakuTexture(Paint, Layer.PaintStyle.Texture, Bounds, RotationDegrees, Opacity);
      Exit;
    end;
    StartPoint := MapRakuLayerPaintPoint(Bounds, RotationDegrees,
      Layer.PaintStyle.LinearStart);
    EndPoint := MapRakuLayerPaintPoint(Bounds, RotationDegrees,
      Layer.PaintStyle.LinearEnd);
    ApplyMapRakuPaintStyleBetween(Paint, Layer, FallbackColor,
      Opacity, StartPoint, EndPoint);
  end
  else
  begin
    Paint.Shader := nil;
    Paint.Color := VclColorToAlphaColor(FallbackColor, Opacity);
  end;
end;

procedure ApplyMapRakuPaintStyleLocal(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single;
  const Bounds: TRectF);
var
  EndPoint: TPointF;
  StartPoint: TPointF;
begin
  if (Layer <> nil) and (Layer.PaintStyle.Kind = slpkPattern) then
  begin
    ApplyMapRakuPattern(Paint, Layer.PaintStyle.Pattern, Bounds, 0, Opacity);
    Exit;
  end;
  if (Layer <> nil) and (Layer.PaintStyle.Kind = slpkTexture) then
  begin
    ApplyMapRakuTexture(Paint, Layer.PaintStyle.Texture, Bounds, 0, Opacity);
    Exit;
  end;
  StartPoint := MapRakuLayerPaintPoint(Bounds, 0.0,
    Layer.PaintStyle.LinearStart);
  EndPoint := MapRakuLayerPaintPoint(Bounds, 0.0,
    Layer.PaintStyle.LinearEnd);
  ApplyMapRakuPaintStyleBetween(Paint, Layer, FallbackColor,
    Opacity, StartPoint, EndPoint);
end;

function VclColorToAlphaColor(Color: TColor; Opacity: Single): TAlphaColor;
var
  RGBColor: TColor;
begin
  RGBColor := ColorToRGB(Color);
  Result := TAlphaColor(
    (Cardinal(EnsureRange(Round(Opacity * 255), 0, 255)) shl 24) or
    (Cardinal(GetRValue(RGBColor)) shl 16) or
    (Cardinal(GetGValue(RGBColor)) shl 8) or
    Cardinal(GetBValue(RGBColor)));
end;

end.
