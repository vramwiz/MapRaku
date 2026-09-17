// 鉄道をJRの帯模様または私鉄の枕木として描画する。
unit MapRakuRailRenderer;
interface
uses System.Skia, MapRakuDocument;
procedure DrawMapRail(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Settings: TVectArtCanvasLayer; Opacity: Single);
implementation
uses System.Math, System.Types, System.UITypes, Vcl.Graphics;
procedure DrawMapRail(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Settings: TVectArtCanvasLayer; Opacity: Single);
var P: ISkPaint; W: Single; Primary, Secondary: TAlphaColor;
  function SkColor(Color: TColor): TAlphaColor;
  var RGB: TColor;
  begin
    RGB := ColorToRGB(Color);
    Result := $FF000000 or (Cardinal(RGB and $FF) shl 16) or
      Cardinal(RGB and $FF00) or (Cardinal(RGB shr 16) and $FF);
  end;
begin
  W := Max(2, Layer.StrokeWidth);
  if Settings = nil then
  begin
    if Layer.StrokeColor = clWhite then Primary := $FFFFFFFF
    else Primary := $FF222222;
    if Layer.MapElement = 'jr' then
    begin
      if Primary = $FFFFFFFF then Secondary := $FF222222
      else Secondary := $FFFFFFFF;
    end
    else Secondary := Primary;
  end
  else if Layer.MapElement = 'jr' then
  begin
    Primary := SkColor(Settings.JrPrimaryColor);
    Secondary := SkColor(Settings.JrSecondaryColor);
  end
  else
  begin
    Primary := SkColor(Settings.RailPrimaryColor);
    Secondary := SkColor(Settings.RailSecondaryColor);
  end;
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
    P.Color := Secondary;
    P.PathEffect := TSkPathEffect.MakeDash([1.5, Max(3, W * 0.8)], 0);
    Canvas.DrawPath(Path, P);
  end;
end;
end.
