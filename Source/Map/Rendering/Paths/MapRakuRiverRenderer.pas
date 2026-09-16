// 川を中心経路に沿った一定幅の水色の帯として描画する。
unit MapRakuRiverRenderer;
interface
uses System.Skia, MapRakuDocument;
procedure DrawMapRiver(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single);
implementation
procedure DrawMapRiver(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single);
var P: ISkPaint;
begin
  P := TSkPaint.Create(TSkPaintStyle.Stroke);
  P.AntiAlias := True; P.Color := $FF48BCE8; P.AlphaF := Opacity;
  P.StrokeWidth := Layer.StrokeWidth;
  P.StrokeCap := TSkStrokeCap.Round; P.StrokeJoin := TSkStrokeJoin.Round;
  Canvas.DrawPath(Path, P);
end;
end.
