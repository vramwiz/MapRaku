// 地図の背景色を含めたRGBAを作り、共通レンダラーの出力を映像用にまとめる。
unit MapRakuPluginRender;
interface
uses MapRakuDocument, MapRakuRenderer;
procedure RenderMapRakuPlugin(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer);
// ルート以外の指定Document直下レイヤーを透明バッファへ描く。
procedure RenderMapRakuPluginLayer(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height, LayerIndex: Integer);
procedure RenderMapRakuPluginRange(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height, FirstLayerIndex,
  LastLayerIndex: Integer);
// 指定経路より上の層だけを既存出力へ重ねる。移動体を同じ高さで描いてから
// 上層を再描画し、高架下を通るマーカー／軌跡を自然に隠す。
procedure CompositeMapRakuPluginUpperLevels(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  CurrentPath: TVectArtPathLayer);
implementation
uses Vcl.Graphics, Winapi.Windows;

function IsPluginHiddenGuide(Layer: TVectArtLayer): Boolean;
begin
  Result:=((Layer is TVectArtPathLayer) and
    (TVectArtPathLayer(Layer).MapElement='route')) or
    ((Layer is TMapRakuGroupLayer) and
      ((TMapRakuGroupLayer(Layer).RouteMarkerKind='start') or
       (TMapRakuGroupLayer(Layer).RouteMarkerKind='end')));
end;
procedure RenderMapRakuPlugin(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer);
var Layers: TVectArtRenderBuffer; Pixel: PVectArtRgbaPixel;
  Color: COLORREF; I: NativeInt; HiddenRoutes: TArray<TVectArtLayer>;
begin
  Layers := TVectArtRenderBuffer.Create;
  try
    // 動画用ルートはセレクタが担当する。通常の地図描画へ混ぜると「なし」でも
    // 未来の全区間が出るため、描画中だけ非表示にして必ず元の編集状態へ戻す。
    for I := 0 to Document.LayerCount - 1 do
      if IsPluginHiddenGuide(Document[I]) and Document[I].Visible then
      begin
        HiddenRoutes := HiddenRoutes + [Document[I]];
        Document[I].Visible := False;
      end;
    try
      RenderVectArtDocument(Document, Layers, Width, Height);
    finally
      for I := 0 to High(HiddenRoutes) do HiddenRoutes[I].Visible := True;
    end;
    Target.SetSize(Width, Height);
    Target.Clear;
    if Document.CanvasLayer.Visible and not Document.CanvasLayer.Transparent then
    begin
      Color := ColorToRGB(Document.CanvasLayer.BackgroundColor);
      Pixel := Target.Data;
      for I := 0 to Target.PixelCount - 1 do
      begin
        Pixel^.R := GetRValue(Color);
        Pixel^.G := GetGValue(Color);
        Pixel^.B := GetBValue(Color);
        Pixel^.A := 255;
        Inc(Pixel);
      end;
    end;
    CompositeVectArtRgba(Layers, Target.Data, Width, Height);
  finally
    Layers.Free;
  end;
end;

procedure RenderMapRakuPluginLayer(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height, LayerIndex: Integer);
begin
  RenderMapRakuPluginRange(Document,Target,Width,Height,LayerIndex,LayerIndex);
end;

procedure RenderMapRakuPluginRange(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height, FirstLayerIndex,
  LastLayerIndex: Integer);
var I:Integer; HiddenRoutes:TArray<TVectArtLayer>;
begin
  if (Document=nil) or (FirstLayerIndex<1) or
     (LastLayerIndex<FirstLayerIndex) then begin
    Target.SetSize(Width,Height); Target.Clear; Exit;
  end;
  for I:=0 to Document.LayerCount-1 do
    if IsPluginHiddenGuide(Document[I]) and Document[I].Visible then begin
      HiddenRoutes:=HiddenRoutes+[Document[I]]; Document[I].Visible:=False;
    end;
  try
    RenderVectArtDocumentRange(Document,Target,Width,Height,FirstLayerIndex,
      LastLayerIndex);
  finally
    for I:=0 to High(HiddenRoutes) do HiddenRoutes[I].Visible:=True;
  end;
end;

procedure CompositeMapRakuPluginUpperLevels(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  CurrentPath: TVectArtPathLayer);
var I, PathIndex, UpperStart: Integer; Upper: TVectArtRenderBuffer;
  HiddenRoutes: TArray<TVectArtLayer>;
begin
  if (Document=nil) or (Target=nil) or (CurrentPath=nil) then Exit;
  PathIndex:=-1;
  for I:=0 to Document.LayerCount-1 do
    if Document[I]=CurrentPath then begin PathIndex:=I; Break; end;
  if PathIndex<0 then Exit;
  UpperStart:=-1;
  for I:=PathIndex+1 to Document.LayerCount-1 do
    if Document[I] is TMapRakuLevelBoundaryLayer then begin UpperStart:=I+1; Break; end;
  if UpperStart>=Document.LayerCount then Exit;
  // 現在区間より後に層境界がない場合は、この高さより上の層が存在しない。
  if UpperStart<0 then Exit;
  Upper:=TVectArtRenderBuffer.Create;
  try
    for I:=0 to Document.LayerCount-1 do
      if IsPluginHiddenGuide(Document[I]) and Document[I].Visible then begin
        HiddenRoutes:=HiddenRoutes+[Document[I]]; Document[I].Visible:=False;
      end;
    try
      RenderVectArtDocumentRange(Document,Upper,Width,Height,UpperStart,
        Document.LayerCount-1);
    finally
      for I:=0 to High(HiddenRoutes) do HiddenRoutes[I].Visible:=True;
    end;
    CompositeVectArtRgba(Upper,Target.Data,Width,Height);
  finally Upper.Free; end;
end;
end.
