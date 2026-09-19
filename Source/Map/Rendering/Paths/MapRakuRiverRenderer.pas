// 川を中心経路に沿った一定幅の水色の帯として描画する。
unit MapRakuRiverRenderer;
interface
uses System.Skia, MapRakuDocument;
procedure DrawMapRiver(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single);
implementation
uses Vcl.Graphics, System.UITypes, MapRakuVariableWidthRenderer;
procedure DrawMapRiver(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single);
var P: ISkPaint; RGB: TColor; Outline: ISkPath;
begin
  P := TSkPaint.Create(TSkPaintStyle.Stroke);
  RGB := ColorToRGB(Layer.StrokeColor);
  P.AntiAlias := True;
  P.Color := $FF000000 or (Cardinal(RGB and $FF) shl 16) or
    Cardinal(RGB and $FF00) or (Cardinal(RGB shr 16) and $FF);
  P.AlphaF := Opacity;
  P.StrokeWidth := Layer.StrokeWidth;
  P.StrokeJoin := TSkStrokeJoin.Round;
  if Layer.LineCap = vlcTriangle then
  begin
    Outline := BuildMapRakuVariableWidthPath(Path, UniformMapRakuStrokeWidthPoints,
      P.StrokeWidth, Layer.LineCap, Layer.Vertices);
    P.Style := TSkPaintStyle.Fill;
    Canvas.DrawPath(Outline, P);
  end
  else
  begin
    if Layer.LineCap = vlcRound then P.StrokeCap := TSkStrokeCap.Round
    else P.StrokeCap := TSkStrokeCap.Square;
    Canvas.DrawPath(Path, P);
  end;
end;
end.
