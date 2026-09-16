// 鉄道をJRの帯模様または私鉄の枕木として描画する。
unit MapRakuRailRenderer;
interface
uses System.Skia, MapRakuDocument;
procedure DrawMapRail(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single);
implementation
uses System.Math, System.Types, System.UITypes, Vcl.Graphics;
procedure DrawMapRail(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single);
var P: ISkPaint; W: Single; Primary, Secondary: TAlphaColor; RGB: TColor;
begin
  W := Max(2, Layer.StrokeWidth);
  RGB:=ColorToRGB(Layer.StrokeColor);
  if ((RGB and 255)+((RGB shr 8) and 255)+((RGB shr 16) and 255))>384 then begin Primary:=$FFFFFFFF; Secondary:=$FF222222; end
  else begin Primary:=$FF222222; Secondary:=$FFFFFFFF; end;
  P := TSkPaint.Create(TSkPaintStyle.Stroke);
  P.AntiAlias := True; P.Color := Primary; P.AlphaF := Opacity;
  P.StrokeWidth := W; P.StrokeJoin := TSkStrokeJoin.Round;
  if Layer.MapElement = 'jr' then begin
    Canvas.DrawPath(Path, P);
    P.StrokeWidth := Max(1, W - 2); P.Color := Secondary; P.AlphaF := Opacity;
    P.PathEffect := TSkPathEffect.MakeDash([W * 1.5, W * 1.5], 0);
    Canvas.DrawPath(Path, P);
  end else begin
    P.StrokeWidth := Max(1, W * 0.15);
    Canvas.DrawPath(Path, P);
    P.StrokeWidth := W;
    P.PathEffect := TSkPathEffect.MakeDash([1.5, Max(3, W * 0.8)], 0);
    Canvas.DrawPath(Path, P);
  end;
end;
end.
