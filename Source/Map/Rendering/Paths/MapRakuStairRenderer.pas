// 2点以上の既存Pathを再利用し、歩道・駅構内でも使える階段を描画する。
unit MapRakuStairRenderer;
interface
uses System.Skia, MapRakuDocument;
procedure DrawMapStairs(const Canvas:ISkCanvas; const Path:ISkPath;
  Layer:TVectArtPathLayer; Opacity:Single);
procedure DrawPedestrianBridge(const Canvas:ISkCanvas; const Path:ISkPath;
  Layer:TVectArtPathLayer; Opacity:Single);
implementation
uses System.Math, System.Types, System.UITypes;
procedure DrawMapStairs(const Canvas:ISkCanvas; const Path:ISkPath;
  Layer:TVectArtPathLayer; Opacity:Single);
var Measure:ISkPathMeasure; Paint:ISkPaint; P,T,N,A,B:TPointF;
  I,Steps:Integer; Offset,Width,Direction:Single;
begin
  Measure:=TSkPathMeasure.Create(Path,False);
  if (Measure=nil) or (Measure.Length<=0) then Exit;
  Steps:=Layer.MapStepCount;
  if Steps<=0 then Steps:=EnsureRange(Round(Measure.Length/8),4,24)
  else Steps:=EnsureRange(Steps,2,64);
  Paint:=TSkPaint.Create(TSkPaintStyle.Stroke); Paint.AntiAlias:=True;
  Paint.StrokeCap:=TSkStrokeCap.Square;
  Paint.Color:=TAlphaColor((Cardinal(EnsureRange(Round(Opacity*255),0,255)) shl 24) or $FFFFFF);
  Paint.StrokeWidth:=Max(Layer.StrokeWidth,8);
  Canvas.DrawPath(Path,Paint);
  Paint.Color:=TAlphaColor((Cardinal(EnsureRange(Round(Opacity*255),0,255)) shl 24));
  Paint.StrokeWidth:=1.5;
  Direction:=1;
  if Layer.MapElement='stairs-down' then Direction:=-1;
  for I:=0 to Steps do
  begin
    Offset:=I/Steps;
    Measure.GetPositionAndTangent(Measure.Length*Offset,P,T);
    N:=TPointF.Create(-T.Y,T.X);
    if Direction>0 then Width:=Layer.StrokeWidth*(1-0.65*Offset)
    else Width:=Layer.StrokeWidth*(0.35+0.65*Offset);
    Width:=Max(Width,5);
    A:=TPointF.Create(P.X-N.X*Width*0.5,P.Y-N.Y*Width*0.5);
    B:=TPointF.Create(P.X+N.X*Width*0.5,P.Y+N.Y*Width*0.5);
    Canvas.DrawLine(A,B,Paint);
  end;
end;

procedure DrawPedestrianBridge(const Canvas:ISkCanvas; const Path:ISkPath;
  Layer:TVectArtPathLayer; Opacity:Single);
var Paint:ISkPaint; Alpha:Cardinal;
begin
  Alpha:=Cardinal(EnsureRange(Round(Opacity*255),0,255)) shl 24;
  Paint:=TSkPaint.Create(TSkPaintStyle.Stroke); Paint.AntiAlias:=True;
  Paint.StrokeCap:=TSkStrokeCap.Square; Paint.Color:=TAlphaColor(Alpha or $FFFFFF);
  Paint.StrokeWidth:=Max(Layer.StrokeWidth,14); Canvas.DrawPath(Path,Paint);
  Paint.Color:=TAlphaColor(Alpha); Paint.StrokeWidth:=2;
  // 中央線は橋面の方向を明瞭にし、両端階段との接続確認にも使う。
  Canvas.DrawPath(Path,Paint);
end;
end.
