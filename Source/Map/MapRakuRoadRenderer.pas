// 道路の縁と本体を分離描画し、同層では縁→本体の順に合成する。
unit MapRakuRoadRenderer;
interface
uses System.Skia, System.UITypes, Vcl.Graphics, MapRakuDocument;
procedure DrawMapRoad(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single; Pass: Integer);
implementation
uses System.Math, MapRakuVariableWidthRenderer;
procedure StrokeRoad(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; const Paint: ISkPaint);
var Outline: ISkPath;
begin
  if Layer.LineCap = vlcTriangle then begin
    Outline := BuildMapRakuVariableWidthPath(Path, UniformMapRakuStrokeWidthPoints,
      Paint.StrokeWidth, Layer.LineCap, Layer.Vertices);
    Paint.Style := TSkPaintStyle.Fill;
    Canvas.DrawPath(Outline, Paint);
    Paint.Style := TSkPaintStyle.Stroke;
  end else Canvas.DrawPath(Path, Paint);
end;
procedure DrawMapRoad(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single; Pass: Integer);
var P: ISkPaint; C, Edge: TAlphaColor; RGB: TColor;
begin
  RGB := ColorToRGB(Layer.StrokeColor);
  C := $FF000000 or (Cardinal(RGB and $FF) shl 16) or
    Cardinal(RGB and $FF00) or (Cardinal(RGB shr 16) and $FF);
  if ((RGB and $FF) + ((RGB shr 8) and $FF) + ((RGB shr 16) and $FF)) > 384 then
    Edge := $FF555555 else Edge := $FFD0D0D0;
  P := TSkPaint.Create(TSkPaintStyle.Stroke);
  P.AntiAlias := True;
  P.StrokeJoin := TSkStrokeJoin.Round;
  if Layer.LineCap = vlcRound then P.StrokeCap := TSkStrokeCap.Round
  else P.StrokeCap := TSkStrokeCap.Square;
  if Pass <> 2 then begin
    P.Color := Edge; P.AlphaF := EnsureRange(Opacity, 0.0, 1.0);
    P.StrokeWidth := Layer.StrokeWidth + 2;
    StrokeRoad(Canvas, Path, Layer, P);
  end;
  if Pass <> 1 then begin
    P.Color := C; P.AlphaF := EnsureRange(Opacity, 0.0, 1.0);
    P.StrokeWidth := Layer.StrokeWidth;
    StrokeRoad(Canvas, Path, Layer, P);
  end;
end;
end.
