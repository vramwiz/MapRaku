// 地図全体の表示倍率、ルート追従、表示枠の切り抜きを映像用に適用する。
unit MapRakuPluginViewport;

interface

uses MapRakuDocument, MapRakuRenderBuffer, MapRakuPluginRouteMarker;

procedure RenderMapRakuPluginViewport(Document: TVectArtDocument;
  Source, Target: TVectArtRenderBuffer; const Motion: TMapRakuPluginRouteMotion;
  RouteCache: PMapRakuRouteProgressData = nil);

implementation

uses System.Math, System.Types;

function SampleScaledPixel(Source: TVectArtRenderBuffer;
  SourceX, SourceY: Double): TVectArtRgbaPixel;
var
  BaseX, BaseY, DX, DY, X, Y: Integer;
  FractionX, FractionY, Weight, AlphaSum, RedSum, GreenSum, BlueSum: Double;
  Pixel: TVectArtRgbaPixel;
begin
  Result := Default(TVectArtRgbaPixel);
  BaseX := Floor(SourceX); BaseY := Floor(SourceY);
  FractionX := SourceX - BaseX; FractionY := SourceY - BaseY;
  AlphaSum := 0; RedSum := 0; GreenSum := 0; BlueSum := 0;
  for DY := 0 to 1 do
    for DX := 0 to 1 do
    begin
      X := BaseX + DX; Y := BaseY + DY;
      if (X < 0) or (X >= Source.Width) or
         (Y < 0) or (Y >= Source.Height) then Continue;
      if DX = 0 then Weight := 1 - FractionX else Weight := FractionX;
      if DY = 0 then Weight := Weight * (1 - FractionY)
      else Weight := Weight * FractionY;
      Pixel := Source.Pixels[NativeInt(Y) * Source.Width + X];
      Weight := Weight * Pixel.A;
      AlphaSum := AlphaSum + Weight;
      RedSum := RedSum + Pixel.R * Weight;
      GreenSum := GreenSum + Pixel.G * Weight;
      BlueSum := BlueSum + Pixel.B * Weight;
    end;
  if AlphaSum <= 0 then Exit;
  Result.A := EnsureRange(Round(AlphaSum), 0, 255);
  Result.R := EnsureRange(Round(RedSum / AlphaSum), 0, 255);
  Result.G := EnsureRange(Round(GreenSum / AlphaSum), 0, 255);
  Result.B := EnsureRange(Round(BlueSum / AlphaSum), 0, 255);
end;

procedure RenderMapRakuPluginViewport(Document: TVectArtDocument;
  Source, Target: TVectArtRenderBuffer; const Motion: TMapRakuPluginRouteMotion;
  RouteCache: PMapRakuRouteProgressData);
var
  Width, Height, DisplayWidth, DisplayHeight, DisplayX, DisplayY,
    Left, Top, Right, Bottom: Integer;
  OffsetX, OffsetY, X, Y: Integer;
  Scale, CenterX, CenterY, MapCenterX, MapCenterY,
    ScaledLeft, ScaledRight, ScaledTop,
    ScaledBottom, Threshold, SourceX, SourceY: Double;
  MarkerPosition: TPointF;
begin
  if (Document = nil) or (Source = nil) or (Target = nil) then Exit;
  Width := Source.Width; Height := Source.Height;
  Target.SetSize(Width, Height); Target.Clear;
  if (Width <= 0) or (Height <= 0) then Exit;
  if Motion.DisplayScale <= 0 then Scale := 1
  else Scale := EnsureRange(Motion.DisplayScale * 0.01, 0.1, 4.0);
  if Motion.DisplayWidth <= 0 then DisplayWidth := Width
  else DisplayWidth := EnsureRange(Round(Motion.DisplayWidth), 1, Width);
  if Motion.DisplayHeight <= 0 then DisplayHeight := Height
  else DisplayHeight := EnsureRange(Round(Motion.DisplayHeight), 1, Height);
  DisplayX := EnsureRange(Round(Motion.DisplayX), -16384, 16384);
  DisplayY := EnsureRange(Round(Motion.DisplayY), -16384, 16384);
  Left := (Width - DisplayWidth) div 2 + DisplayX;
  Top := (Height - DisplayHeight) div 2 + DisplayY;
  Right := Left + DisplayWidth; Bottom := Top + DisplayHeight;
  CenterX := Width * 0.5; CenterY := Height * 0.5;
  MapCenterX := CenterX + DisplayX;
  MapCenterY := CenterY + DisplayY;
  ScaledLeft := MapCenterX - CenterX * Scale;
  ScaledRight := MapCenterX + CenterX * Scale;
  ScaledTop := MapCenterY - CenterY * Scale;
  ScaledBottom := MapCenterY + CenterY * Scale;
  OffsetX := 0; OffsetY := 0;
  if TryMapRakuPluginRoutePosition(Document, Motion.ProgressPercent,
    MarkerPosition, RouteCache) then
  begin
    MarkerPosition.X := MapCenterX + Scale *
      ((MarkerPosition.X + Document.CanvasLayer.Width * 0.5) *
       Width / Document.CanvasLayer.Width - CenterX);
    MarkerPosition.Y := MapCenterY + Scale *
      ((MarkerPosition.Y + Document.CanvasLayer.Height * 0.5) *
       Height / Document.CanvasLayer.Height - CenterY);
    Threshold := EnsureRange(Motion.ScrollStartRate, 0.0, 50.0) * 0.01;
    if MarkerPosition.X < Left + DisplayWidth * Threshold then
      OffsetX := Round(Left + DisplayWidth * Threshold - MarkerPosition.X)
    else if MarkerPosition.X > Right - DisplayWidth * Threshold then
      OffsetX := Round(Right - DisplayWidth * Threshold - MarkerPosition.X);
    if MarkerPosition.Y < Top + DisplayHeight * Threshold then
      OffsetY := Round(Top + DisplayHeight * Threshold - MarkerPosition.Y)
    else if MarkerPosition.Y > Bottom - DisplayHeight * Threshold then
      OffsetY := Round(Bottom - DisplayHeight * Threshold - MarkerPosition.Y);
    // 地図が表示枠より小さい軸では中央を保ち、余白を無理に追従させない。
    if ScaledRight - ScaledLeft >= DisplayWidth then
      OffsetX := EnsureRange(OffsetX, Ceil(Right - ScaledRight),
        Floor(Left - ScaledLeft))
    else OffsetX := 0;
    if ScaledBottom - ScaledTop >= DisplayHeight then
      OffsetY := EnsureRange(OffsetY, Ceil(Bottom - ScaledBottom),
        Floor(Top - ScaledTop))
    else OffsetY := 0;
  end;
  if SameValue(Scale, 1.0) then
    CompositeVectArtRgbaOffset(Source, Target.Data, Width, Height,
      DisplayX + OffsetX, DisplayY + OffsetY)
  else
    for Y := Max(Top, 0) to Min(Bottom, Height) - 1 do
    begin
      SourceY := (Y + 0.5 - OffsetY - MapCenterY) / Scale + CenterY - 0.5;
      for X := Max(Left, 0) to Min(Right, Width) - 1 do
      begin
        SourceX := (X + 0.5 - OffsetX - MapCenterX) / Scale + CenterX - 0.5;
        Target.Pixels[NativeInt(Y) * Width + X] :=
          SampleScaledPixel(Source, SourceX, SourceY);
      end;
    end;
  if SameValue(Scale, 1.0) then
    for Y := 0 to Height - 1 do
      for X := 0 to Width - 1 do
        if (X < Left) or (X >= Right) or (Y < Top) or (Y >= Bottom) then
          Target.Pixels[NativeInt(Y) * Width + X] :=
            Default(TVectArtRgbaPixel);
end;

end.
