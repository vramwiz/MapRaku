// AviUtl2の進行位置から共通ルートを辿り、内蔵プレビューマーカーをRGBA映像へ描画する。
unit MapRakuPluginRouteMarker;
interface
uses System.Types, System.UITypes, MapRakuDocument, MapRakuRenderBuffer;
type
  TMapRakuPluginRouteMotion = record
    ProgressPercent, MarkerOpacity, MarkerScale, MarkerOffsetX, MarkerOffsetY,
      RotationCorrection: Double;
    MarkerColor: TColor;
    MarkerRotation: Integer;
    MarkerImageAnchor: Integer;
    RouteDisplay: Integer;
    RouteColor: TColor;
    DisplayWidth, DisplayHeight, ScrollStartRate: Double;
    DrawMarker: Boolean;
    MarkerFileName: string;
  end;
procedure DrawMapRakuPluginRouteLayer(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; const Motion: TMapRakuPluginRouteMotion;
  LayerIndex: Integer; MarkerImage: TVectArtRenderBuffer);
function TryMapRakuPluginRoutePosition(Document: TVectArtDocument;
  ProgressPercent: Double; out Position: TPointF): Boolean;
implementation
uses System.Math, Vcl.Graphics, Winapi.Windows, MapRakuRouteProgress;
procedure BlendPixel(Target: TVectArtRenderBuffer; X,Y: Integer; Color:TColor; Alpha:Byte);
var D:PVectArtRgbaPixel; SA,DA,N:Cardinal; R,G,B:Byte;
begin
  if (X<0) or (Y<0) or (X>=Target.Width) or (Y>=Target.Height) or (Alpha=0) then Exit;
  D:=Target.Data; Inc(D,NativeInt(Y)*Target.Width+X); R:=GetRValue(ColorToRGB(Color)); G:=GetGValue(ColorToRGB(Color)); B:=GetBValue(ColorToRGB(Color));
  if Alpha=255 then begin D^.R:=R; D^.G:=G; D^.B:=B; D^.A:=255; Exit; end;
  SA:=Alpha; DA:=D^.A; N:=SA*255+DA*(255-SA); if N=0 then Exit;
  D^.R:=(Cardinal(R)*SA*255+Cardinal(D^.R)*DA*(255-SA)+N div 2) div N;
  D^.G:=(Cardinal(G)*SA*255+Cardinal(D^.G)*DA*(255-SA)+N div 2) div N;
  D^.B:=(Cardinal(B)*SA*255+Cardinal(D^.B)*DA*(255-SA)+N div 2) div N; D^.A:=(N+127) div 255;
end;
procedure BlendImagePixel(Target:TVectArtRenderBuffer; X,Y:Integer;
  const Source:TVectArtRgbaPixel; Opacity:Byte);
var D:PVectArtRgbaPixel; A:Byte;
begin
  A:=Round(Source.A*Opacity/255); if A=0 then Exit;
  if (X<0)or(Y<0)or(X>=Target.Width)or(Y>=Target.Height) then Exit;
  D:=Target.Data; Inc(D,NativeInt(Y)*Target.Width+X);
  if A=255 then begin D^:=Source; Exit; end;
  D^.R:=(Integer(Source.R)*A+Integer(D^.R)*(255-A)) div 255;
  D^.G:=(Integer(Source.G)*A+Integer(D^.G)*(255-A)) div 255;
  D^.B:=(Integer(Source.B)*A+Integer(D^.B)*(255-A)) div 255;
  D^.A:=Max(D^.A,A);
end;
procedure DrawImageMarker(Target,Image:TVectArtRenderBuffer; const Anchor:TPointF;
  Scale,Angle:Single; Opacity:Byte; ImageAnchor:Integer);
var X,Y,SX,SY:Integer; DX,DY,C,S,AnchorX,AnchorY:Single;
  Source:TVectArtRgbaPixel;
begin
  if (Image=nil)or(Image.Width<=0)or(Image.Height<=0) then Exit;
  // 画像座標のこの点をルート位置へ一致させる。回転時も同じ基準点のまま
  // 逆変換するため、下中央を選んだピンの先端が経路からずれない。
  AnchorX:=Image.Width*0.5;
  if ImageAnchor=1 then
    AnchorY:=Image.Height
  else
    AnchorY:=Image.Height*0.5;
  SinCos(DegToRad(-Angle),S,C);
  for Y:=Floor(Anchor.Y-Max(Image.Width,Image.Height)*Scale) to
    Ceil(Anchor.Y+Max(Image.Width,Image.Height)*Scale) do
    for X:=Floor(Anchor.X-Max(Image.Width,Image.Height)*Scale) to
      Ceil(Anchor.X+Max(Image.Width,Image.Height)*Scale) do begin
        DX:=X+0.5-Anchor.X; DY:=Y+0.5-Anchor.Y;
        SX:=Floor((DX*C-DY*S)/Scale+AnchorX);
        SY:=Floor((DX*S+DY*C)/Scale+AnchorY);
        if (SX>=0)and(SY>=0)and(SX<Image.Width)and(SY<Image.Height) then begin
          Source:=Image.Pixels[SY*Image.Width+SX]; BlendImagePixel(Target,X,Y,Source,Opacity);
        end;
      end;
end;
procedure Disc(Target:TVectArtRenderBuffer; C:TPointF; Radius:Single; Color:TColor; Alpha:Byte);
var X,Y:Integer; DX,DY:Single;
begin for Y:=Floor(C.Y-Radius) to Ceil(C.Y+Radius) do for X:=Floor(C.X-Radius) to Ceil(C.X+Radius) do begin DX:=X+0.5-C.X; DY:=Y+0.5-C.Y; if DX*DX+DY*DY<=Radius*Radius then BlendPixel(Target,X,Y,Color,Alpha); end; end;
function Edge(const A,B,P:TPointF):Single;
begin Result:=(P.X-A.X)*(B.Y-A.Y)-(P.Y-A.Y)*(B.X-A.X); end;
procedure Triangle(Target:TVectArtRenderBuffer; const A,B,C:TPointF; Color:TColor; Alpha:Byte);
var X,Y:Integer; P:TPointF; E1,E2,E3:Single;
begin for Y:=Floor(Min(A.Y,Min(B.Y,C.Y))) to Ceil(Max(A.Y,Max(B.Y,C.Y))) do for X:=Floor(Min(A.X,Min(B.X,C.X))) to Ceil(Max(A.X,Max(B.X,C.X))) do begin P:=PointF(X+0.5,Y+0.5); E1:=Edge(A,B,P); E2:=Edge(B,C,P); E3:=Edge(C,A,P); if ((E1>=0)and(E2>=0)and(E3>=0))or((E1<=0)and(E2<=0)and(E3<=0)) then BlendPixel(Target,X,Y,Color,Alpha); end; end;
function Rotate(const V,Center:TPointF; Degrees:Single):TPointF;
var S,C:Single;
begin SinCos(DegToRad(Degrees),S,C); Result:=PointF(Center.X+(V.X-Center.X)*C-(V.Y-Center.Y)*S,Center.Y+(V.X-Center.X)*S+(V.Y-Center.Y)*C); end;
function ToPixel(Document:TVectArtDocument; Target:TVectArtRenderBuffer;
  const Position:TPointF):TPointF;
begin
  Result:=PointF((Position.X+Document.CanvasLayer.Width*0.5)*Target.Width/
    Document.CanvasLayer.Width,(Position.Y+Document.CanvasLayer.Height*0.5)*
    Target.Height/Document.CanvasLayer.Height);
end;
procedure DrawRouteSegment(Target:TVectArtRenderBuffer; const A,B:TPointF;
  Radius:Single; Color:TColor);
var I,Steps:Integer; P:TPointF;
begin
  Steps:=Max(1,Ceil(Hypot(B.X-A.X,B.Y-A.Y)));
  for I:=0 to Steps do begin P:=A+(B-A)*(I/Steps); Disc(Target,P,Radius,Color,255); end;
end;
function DocumentLayerIndex(Document:TVectArtDocument; Path:TVectArtPathLayer):Integer;
var I:Integer;
begin
  Result:=-1;
  for I:=0 to Document.LayerCount-1 do if Document[I]=Path then Exit(I);
end;
procedure DrawRouteTrail(Document:TVectArtDocument; Target:TVectArtRenderBuffer;
  const Route:TMapRakuRouteProgressData; Progress:Single; const Current:TPointF;
  Color:TColor; LayerIndex:Integer);
var I:Integer; TargetDistance,Scale:Single; A,B:TPointF;
begin
  TargetDistance:=EnsureRange(Progress,0,100)*0.01*Route.TotalLength;
  Scale:=0.5*(Target.Width/Document.CanvasLayer.Width+
    Target.Height/Document.CanvasLayer.Height);
  for I:=1 to High(Route.Samples) do begin
    // 区間ごとの高さへ分配する前に、全ルート上の進行距離で終了を判定する。
    // これを後続区間の判定後にすると、未到達区間の始点から現在地へ誤った
    // 軌跡が引かれてしまう。
    if Route.Distances[I-1]>=TargetDistance then Exit;
    if DocumentLayerIndex(Document,Route.Samples[I].Path)=LayerIndex then begin
      A:=ToPixel(Document,Target,Route.Samples[I-1].Position);
      if Route.Distances[I]>=TargetDistance then
        B:=ToPixel(Document,Target,Current)
      else
        B:=ToPixel(Document,Target,Route.Samples[I].Position);
      DrawRouteSegment(Target,A,B,
        Max(1,Route.Samples[I].Path.StrokeWidth*Scale*0.5),Color);
    end;
    if Route.Distances[I]>=TargetDistance then Exit;
  end;
end;
procedure DrawMapRakuPluginRouteLayer(Document:TVectArtDocument; Target:TVectArtRenderBuffer; const Motion:TMapRakuPluginRouteMotion; LayerIndex:Integer; MarkerImage:TVectArtRenderBuffer);
var I:Integer; P,PP:TPointF; T:TPointF; L,Current:TVectArtPathLayer; R:TMapRakuRouteProgressData; E:string; Scale,Angle:Single; Alpha:Byte; A,B,C:TPointF;
begin
  if (Document=nil)or(Target=nil)or(Target.Width<=0)or(Target.Height<=0)or(Document.CanvasLayer.Width<=0)or(Document.CanvasLayer.Height<=0) then Exit;
  L:=nil; for I:=0 to Document.LayerCount-1 do if (Document[I] is TVectArtPathLayer)and(TVectArtPathLayer(Document[I]).MapElement='route') then begin L:=TVectArtPathLayer(Document[I]); Break; end;
  if (L=nil)or not TryBuildMapRakuRoute(Document,MapRakuRouteIdentifier(L),R,E)or not TryMapRakuRoutePosition(R,Motion.ProgressPercent,P,T,Current) then Exit;
  if Motion.RouteDisplay=1 then
    DrawRouteTrail(Document,Target,R,Motion.ProgressPercent,P,Motion.RouteColor,
      LayerIndex);
  if not Motion.DrawMarker then Exit;
  if DocumentLayerIndex(Document,Current)<>LayerIndex then Exit;
  PP:=ToPixel(Document,Target,P)+PointF(Motion.MarkerOffsetX,Motion.MarkerOffsetY);
  Scale:=Max(0.01,Motion.MarkerScale*0.01); Alpha:=EnsureRange(Round(Motion.MarkerOpacity*2.55),0,255); Angle:=0;
  if Motion.MarkerRotation<>0 then Angle:=RadToDeg(ArcTan2(T.Y,T.X))+90;
  if Motion.MarkerRotation=2 then Angle:=Angle+Motion.RotationCorrection;
  if (MarkerImage<>nil)and(MarkerImage.Width>0) then
    DrawImageMarker(Target,MarkerImage,PP,Scale,Angle,Alpha,
      Motion.MarkerImageAnchor)
  else begin
    A:=Rotate(PP+PointF(-9*Scale,-7*Scale),PP,Angle); B:=Rotate(PP+PointF(9*Scale,-7*Scale),PP,Angle); C:=Rotate(PP+PointF(0,10*Scale),PP,Angle);
    Triangle(Target,A,B,C,clBlack,Alpha); Triangle(Target,Rotate(PP+PointF(-7*Scale,-7*Scale),PP,Angle),Rotate(PP+PointF(7*Scale,-7*Scale),PP,Angle),C,Motion.MarkerColor,Alpha);
    Disc(Target,Rotate(PP+PointF(0,-10*Scale),PP,Angle),10*Scale,clBlack,Alpha); Disc(Target,Rotate(PP+PointF(0,-10*Scale),PP,Angle),8*Scale,Motion.MarkerColor,Alpha);
  end;
end;
function TryMapRakuPluginRoutePosition(Document:TVectArtDocument;
  ProgressPercent:Double; out Position:TPointF):Boolean;
var I:Integer; Path,Current:TVectArtPathLayer; Route:TMapRakuRouteProgressData;
  Tangent:TPointF; ErrorText:string;
begin
  Result:=False; Position:=PointF(0,0); Path:=nil;
  if Document=nil then Exit;
  for I:=0 to Document.LayerCount-1 do
    if (Document[I] is TVectArtPathLayer) and
       (TVectArtPathLayer(Document[I]).MapElement='route') then begin
      Path:=TVectArtPathLayer(Document[I]); Break;
    end;
  if (Path<>nil) and TryBuildMapRakuRoute(Document,
    MapRakuRouteIdentifier(Path),Route,ErrorText) then
    Result:=TryMapRakuRoutePosition(Route,ProgressPercent,Position,Tangent,
      Current);
end;
end.
