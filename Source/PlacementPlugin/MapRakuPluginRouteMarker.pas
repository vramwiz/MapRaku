// AviUtl2の進行位置から共通ルートを辿り、内蔵プレビューマーカーをRGBA映像へ描画する。
unit MapRakuPluginRouteMarker;
interface
uses System.Types, System.UITypes, MapRakuDocument, MapRakuRenderBuffer;
type
  TMapRakuPluginRouteMotion = record
    ProgressPercent, MarkerTransparency, MarkerUnderpassTransparency, MarkerScale, MarkerOffsetX, MarkerOffsetY,
      RotationCorrection: Double;
    MarkerColor: TColor;
    MarkerRotation: Integer;
    MarkerImageAnchor: Integer;
    PointerKind: Integer;
    PointerColor: TColor;
    PointerSize: Double;
    AnimationMode: Integer;
    AnimationAmount, AnimationSpeed, AnimationAux, AnimationTime: Double;
    RouteDisplay: Integer;
    RouteColor: TColor;
    DisplayWidth, DisplayHeight, ScrollStartRate: Double;
    DrawMarker: Boolean;
    MarkerFileName: string;
  end;
procedure DrawMapRakuPluginRouteLayer(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; const Motion: TMapRakuPluginRouteMotion;
  LayerIndex: Integer; MarkerImage: TVectArtRenderBuffer;
  ClipMask: TVectArtRenderBuffer = nil);
function TryMapRakuPluginRoutePosition(Document: TVectArtDocument;
  ProgressPercent: Double; out Position: TPointF): Boolean;
// 基本位置・角度へ揺れ補正を加える。開始／終了位置では必ず補正を0にする。
procedure ApplyMapRakuPluginMarkerAnimation(
  const Motion: TMapRakuPluginRouteMotion; const BasePosition: TPointF;
  BaseAngle: Single; out Position: TPointF; out Angle: Single);
implementation
uses System.Math, Vcl.Graphics, Winapi.Windows, MapRakuRouteProgress, MapRakuCrossingRenderer;
type
  TRouteRaster = record
    Buffer, Mask: TVectArtRenderBuffer;
    NormalOpacity, LowerOpacity: Byte;
  end;
procedure BlendPixel(Target: TRouteRaster; X,Y: Integer; Color:TColor; Alpha:Byte);
var D:PVectArtRgbaPixel; SA,DA,N,Coverage,Opacity:Cardinal; R,G,B:Byte;
begin
  if (X<0) or (Y<0) or (X>=Target.Buffer.Width) or (Y>=Target.Buffer.Height) or (Alpha=0) then Exit;
  Coverage:=255;
  if Target.Mask<>nil then Coverage:=Target.Mask.Pixels[Y*Target.Buffer.Width+X].A;
  // 境界の被覆率で通常／高架下の不透明度を補間する。片方をもう片方へ
  // 乗算しないため、通常が完全透明でも高架下だけを表示できる。
  Opacity:=(Target.NormalOpacity*Coverage+Target.LowerOpacity*(255-Coverage)+127) div 255;
  Alpha:=(Cardinal(Alpha)*Opacity+127) div 255;
  if Alpha=0 then Exit;
  D:=Target.Buffer.Data; Inc(D,NativeInt(Y)*Target.Buffer.Width+X); R:=GetRValue(ColorToRGB(Color)); G:=GetGValue(ColorToRGB(Color)); B:=GetBValue(ColorToRGB(Color));
  if Alpha=255 then begin D^.R:=R; D^.G:=G; D^.B:=B; D^.A:=255; Exit; end;
  SA:=Alpha; DA:=D^.A; N:=SA*255+DA*(255-SA); if N=0 then Exit;
  D^.R:=(Cardinal(R)*SA*255+Cardinal(D^.R)*DA*(255-SA)+N div 2) div N;
  D^.G:=(Cardinal(G)*SA*255+Cardinal(D^.G)*DA*(255-SA)+N div 2) div N;
  D^.B:=(Cardinal(B)*SA*255+Cardinal(D^.B)*DA*(255-SA)+N div 2) div N; D^.A:=(N+127) div 255;
end;
procedure BlendImagePixel(Target:TRouteRaster; X,Y:Integer;
  const Source:TVectArtRgbaPixel; Opacity:Byte);
begin
  BlendPixel(Target,X,Y,RGB(Source.R,Source.G,Source.B),
    (Integer(Source.A)*Opacity+127) div 255);
end;
procedure DrawImageMarker(Target:TRouteRaster; Image:TVectArtRenderBuffer; const Anchor:TPointF;
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
procedure Disc(Target:TRouteRaster; C:TPointF; Radius:Single; Color:TColor; Alpha:Byte);
var X,Y:Integer; DX,DY:Single;
begin for Y:=Floor(C.Y-Radius) to Ceil(C.Y+Radius) do for X:=Floor(C.X-Radius) to Ceil(C.X+Radius) do begin DX:=X+0.5-C.X; DY:=Y+0.5-C.Y; if DX*DX+DY*DY<=Radius*Radius then BlendPixel(Target,X,Y,Color,Alpha); end; end;
function Edge(const A,B,P:TPointF):Single;
begin Result:=(P.X-A.X)*(B.Y-A.Y)-(P.Y-A.Y)*(B.X-A.X); end;
procedure Triangle(Target:TRouteRaster; const A,B,C:TPointF; Color:TColor; Alpha:Byte);
var X,Y:Integer; P:TPointF; E1,E2,E3:Single;
begin for Y:=Floor(Min(A.Y,Min(B.Y,C.Y))) to Ceil(Max(A.Y,Max(B.Y,C.Y))) do for X:=Floor(Min(A.X,Min(B.X,C.X))) to Ceil(Max(A.X,Max(B.X,C.X))) do begin P:=PointF(X+0.5,Y+0.5); E1:=Edge(A,B,P); E2:=Edge(B,C,P); E3:=Edge(C,A,P); if ((E1>=0)and(E2>=0)and(E3>=0))or((E1<=0)and(E2<=0)and(E3<=0)) then BlendPixel(Target,X,Y,Color,Alpha); end; end;
function Rotate(const V,Center:TPointF; Degrees:Single):TPointF;
var S,C:Single;
begin SinCos(DegToRad(Degrees),S,C); Result:=PointF(Center.X+(V.X-Center.X)*C-(V.Y-Center.Y)*S,Center.Y+(V.X-Center.X)*S+(V.Y-Center.Y)*C); end;
function ToPixel(Document:TVectArtDocument; Target:TRouteRaster;
  const Position:TPointF):TPointF;
begin
  Result:=PointF((Position.X+Document.CanvasLayer.Width*0.5)*Target.Buffer.Width/
    Document.CanvasLayer.Width,(Position.Y+Document.CanvasLayer.Height*0.5)*
    Target.Buffer.Height/Document.CanvasLayer.Height);
end;
procedure ApplyMapRakuPluginMarkerAnimation(
  const Motion: TMapRakuPluginRouteMotion; const BasePosition: TPointF;
  BaseAngle: Single; out Position: TPointF; out Angle: Single);
var Progress, Envelope, Phase: Double;
begin
  Position:=BasePosition;
  Angle:=BaseAngle;
  Progress:=EnsureRange(Motion.ProgressPercent,0,100)*0.01;
  // 完全に停止した始点・終点で姿勢が残ると、配置位置とマーカーの接続が
  // 見た目にもずれる。位相に関係なくゼロ補正を優先する。
  if (Motion.AnimationMode=0) or (Progress<=0) or (Progress>=1) then Exit;
  Envelope:=Sin(Pi*Progress);
  Phase:=DegToRad(Motion.AnimationAux);
  case Motion.AnimationMode of
    1,3: Phase:=Phase+2*Pi*Motion.AnimationSpeed*Motion.AnimationTime;
    2,4: Phase:=Phase+2*Pi*Motion.AnimationSpeed*Progress;
  end;
  case Motion.AnimationMode of
    // バウンドはルートより下へ潜らせず、乗り物が地面を通り抜けないようにする。
    1,2: Position.Y:=Position.Y-Abs(Sin(Phase))*Motion.AnimationAmount*Envelope;
    // 振り子は既存の固定／進行方向角度へ加算する補正として扱う。
    3,4: Angle:=Angle+Sin(Phase)*Motion.AnimationAmount*Envelope;
  end;
end;
procedure DrawRouteSegment(Target:TRouteRaster; const A,B:TPointF;
  Radius:Single; Color:TColor);
var I,Steps:Integer; P:TPointF;
begin
  Steps:=Max(1,Ceil(Hypot(B.X-A.X,B.Y-A.Y)));
  for I:=0 to Steps do begin P:=A+(B-A)*(I/Steps); Disc(Target,P,Radius,Color,255); end;
end;
procedure DrawDirectionPointer(Document:TVectArtDocument;
  Target:TRouteRaster; MarkerImage:TVectArtRenderBuffer; const Motion:TMapRakuPluginRouteMotion;
  const MarkerAnchor,Tangent:TPointF; MarkerScale,MarkerAngle:Single;
  Opacity:Byte);
var Forward,Perpendicular,Center,Offset,A,B,C:TPointF;
  Length,HalfWidth,HalfHeight,Extent,Size,Sine,Cosine,AnchorY:Single;
begin
  if Motion.PointerKind<>1 then Exit;
  // Document座標の接線を出力ピクセル座標へ直す。表示の縦横比が異なっても
  // ポインターだけが斜めにずれないよう、画面上の方向で外周を求める。
  Forward:=PointF(Tangent.X*Target.Buffer.Width/Document.CanvasLayer.Width,
    Tangent.Y*Target.Buffer.Height/Document.CanvasLayer.Height);
  Length:=Hypot(Forward.X,Forward.Y);
  if Length<=0 then Exit;
  Forward:=Forward*(1/Length);
  Perpendicular:=PointF(-Forward.Y,Forward.X);
  if (MarkerImage<>nil) and (MarkerImage.Width>0) and
     (MarkerImage.Height>0) then begin
    HalfWidth:=MarkerImage.Width*MarkerScale*0.5;
    HalfHeight:=MarkerImage.Height*MarkerScale*0.5;
    if Motion.MarkerImageAnchor=1 then
      AnchorY:=MarkerImage.Height
    else
      AnchorY:=MarkerImage.Height*0.5;
    Offset:=Rotate(PointF(0,(MarkerImage.Height*0.5-AnchorY)*MarkerScale),
      PointF(0,0),MarkerAngle);
  end else begin
    // 内蔵ピンの描画範囲（-20～10px）を使い、見た目の外側から出す。
    HalfWidth:=10*MarkerScale;
    HalfHeight:=15*MarkerScale;
    Offset:=Rotate(PointF(0,-5*MarkerScale),PointF(0,0),MarkerAngle);
  end;
  Center:=MarkerAnchor+Offset;
  SinCos(DegToRad(MarkerAngle),Sine,Cosine);
  Extent:=Abs(Forward.X*Cosine+Forward.Y*Sine)*HalfWidth+
    Abs(-Forward.X*Sine+Forward.Y*Cosine)*HalfHeight;
  Size:=Max(1,Motion.PointerSize);
  Center:=Center+Forward*(Extent+Size*0.75);
  A:=Center+Forward*Size;
  B:=Center-Forward*(Size*0.6)+Perpendicular*(Size*0.6);
  C:=Center-Forward*(Size*0.6)-Perpendicular*(Size*0.6);
  Triangle(Target,A,B,C,Motion.PointerColor,Opacity);
end;
function DocumentLayerIndex(Document:TVectArtDocument; Path:TVectArtPathLayer):Integer;
var I:Integer;
begin
  Result:=-1;
  for I:=0 to Document.LayerCount-1 do if Document[I]=Path then Exit(I);
end;
procedure DrawRouteTrail(Document:TVectArtDocument; Target:TRouteRaster;
  const Route:TMapRakuRouteProgressData; Progress:Single; const Current:TPointF;
  Color:TColor; LayerIndex:Integer);
var I:Integer; TargetDistance,Scale:Single; A,B:TPointF;
begin
  TargetDistance:=EnsureRange(Progress,0,100)*0.01*Route.TotalLength;
  Scale:=0.5*(Target.Buffer.Width/Document.CanvasLayer.Width+
    Target.Buffer.Height/Document.CanvasLayer.Height);
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
procedure DrawRouteLayer(Document:TVectArtDocument; Target:TRouteRaster; const Motion:TMapRakuPluginRouteMotion; LayerIndex:Integer; MarkerImage:TVectArtRenderBuffer);
var I:Integer; P,PP:TPointF; T:TPointF; L,Current:TVectArtPathLayer; R:TMapRakuRouteProgressData; E:string; Scale,Angle:Single; Alpha:Byte; A,B,C:TPointF; MarkerRaster:TRouteRaster;
  X,Y:Integer; Pixel:PVectArtRgbaPixel;
begin
  if (Document=nil)or(Target.Buffer=nil)or(Target.Buffer.Width<=0)or(Target.Buffer.Height<=0)or(Document.CanvasLayer.Width<=0)or(Document.CanvasLayer.Height<=0) then Exit;
  L:=nil; for I:=0 to Document.LayerCount-1 do if (Document[I] is TVectArtPathLayer)and(TVectArtPathLayer(Document[I]).MapElement='route') then begin L:=TVectArtPathLayer(Document[I]); Break; end;
  if (L=nil)or not TryBuildMapRakuRoute(Document,MapRakuRouteIdentifier(L),R,E)or not TryMapRakuRoutePosition(R,Motion.ProgressPercent,P,T,Current) then Exit;
  if Motion.RouteDisplay=1 then
    DrawRouteTrail(Document,Target,R,Motion.ProgressPercent,P,Motion.RouteColor,
      LayerIndex);
  if not Motion.DrawMarker then Exit;
  if DocumentLayerIndex(Document,Current)<>LayerIndex then Exit;
  PP:=ToPixel(Document,Target,P)+PointF(Motion.MarkerOffsetX,Motion.MarkerOffsetY);
  Scale:=Max(0.01,Motion.MarkerScale*0.01); Alpha:=255; Angle:=0;
  Target.NormalOpacity:=EnsureRange(Round((100-Motion.MarkerTransparency)*255/100),0,255);
  Target.LowerOpacity:=EnsureRange(Round((100-Motion.MarkerUnderpassTransparency)*255/100),0,255);
  if Motion.MarkerRotation<>0 then Angle:=RadToDeg(ArcTan2(T.Y,T.X))+90;
  if Motion.MarkerRotation=2 then Angle:=Angle+Motion.RotationCorrection;
  ApplyMapRakuPluginMarkerAnimation(Motion,PP,Angle,PP,Angle);
  MarkerRaster.Buffer:=TVectArtRenderBuffer.Create;
  MarkerRaster.Mask:=nil;
  MarkerRaster.NormalOpacity:=255;
  MarkerRaster.LowerOpacity:=0;
  try
    MarkerRaster.Buffer.SetSize(Target.Buffer.Width,Target.Buffer.Height);
    MarkerRaster.Buffer.Clear;
    if (MarkerImage<>nil)and(MarkerImage.Width>0) then
      DrawImageMarker(MarkerRaster,MarkerImage,PP,Scale,Angle,Alpha,
        Motion.MarkerImageAnchor)
    else begin
      A:=Rotate(PP+PointF(-9*Scale,-7*Scale),PP,Angle); B:=Rotate(PP+PointF(9*Scale,-7*Scale),PP,Angle); C:=Rotate(PP+PointF(0,10*Scale),PP,Angle);
      Triangle(MarkerRaster,A,B,C,clBlack,Alpha); Triangle(MarkerRaster,Rotate(PP+PointF(-7*Scale,-7*Scale),PP,Angle),Rotate(PP+PointF(7*Scale,-7*Scale),PP,Angle),C,Motion.MarkerColor,Alpha);
      Disc(MarkerRaster,Rotate(PP+PointF(0,-10*Scale),PP,Angle),10*Scale,clBlack,Alpha); Disc(MarkerRaster,Rotate(PP+PointF(0,-10*Scale),PP,Angle),8*Scale,Motion.MarkerColor,Alpha);
    end;
    DrawDirectionPointer(Document,MarkerRaster,MarkerImage,Motion,PP,T,Scale,Angle,
      Alpha);
    // ピンの縁・本体や画像・ポインターの重なりで透明度が変わらないよう、
    // マーカー全体を組み立ててから一度だけ透明度と交差マスクを適用する。
    Pixel:=MarkerRaster.Buffer.Data;
    for Y:=0 to Target.Buffer.Height-1 do
      for X:=0 to Target.Buffer.Width-1 do begin
        if Pixel^.A<>0 then BlendImagePixel(Target,X,Y,Pixel^,255);
        Inc(Pixel);
      end;
  finally MarkerRaster.Buffer.Free; end;
end;
procedure DrawMapRakuPluginRouteLayer(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; const Motion: TMapRakuPluginRouteMotion;
  LayerIndex: Integer; MarkerImage: TVectArtRenderBuffer;
  ClipMask: TVectArtRenderBuffer);
var Raster: TRouteRaster; OwnedMask: TVectArtRenderBuffer;
  Crossings: TMapCrossingRenderContext;
begin
  if (Document=nil) or (Target=nil) or (Target.Width<=0) or
    (Target.Height<=0) or (LayerIndex<1) or
    (LayerIndex>=Document.LayerCount) or
    (Document.CanvasLayer.Width<=0) or (Document.CanvasLayer.Height<=0) then Exit;
  Raster.Buffer:=Target;
  Raster.Mask:=ClipMask;
  // 軌跡は従来どおり高架下を切り抜き、マーカー描画時だけ設定値へ切り替える。
  Raster.NormalOpacity:=255;
  Raster.LowerOpacity:=0;
  OwnedMask:=nil;
  try
    if Raster.Mask=nil then begin
      OwnedMask:=TVectArtRenderBuffer.Create;
      Crossings:=TMapCrossingRenderContext.Create(Document);
      try
        Crossings.RenderLowerMask(OwnedMask,Document[LayerIndex],
          Target.Width,Target.Height,TRectF.Create(-Document.CanvasLayer.Width*0.5,
          -Document.CanvasLayer.Height*0.5,Document.CanvasLayer.Width*0.5,
          Document.CanvasLayer.Height*0.5));
      finally Crossings.Free; end;
      Raster.Mask:=OwnedMask;
    end;
    DrawRouteLayer(Document,Raster,Motion,LayerIndex,MarkerImage);
  finally OwnedMask.Free; end;
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
