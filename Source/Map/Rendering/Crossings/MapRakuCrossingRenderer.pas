// 立体交差の切り抜きと記号を画面・PNG・SVGへ共通に提供する。
unit MapRakuCrossingRenderer;

interface
uses System.Skia, System.Types, System.UITypes, MapRakuDocument, MapRakuCrossings, MapRakuBridgeSpans;

type
  // Cutは下側に残す領域、Marksは上側に描く記号。対象IDを分けて無関係な層を保護する。
  TMapCrossingVisual = record
    UpperId, LowerId: string;
    Cut: ISkPath;
    Marks: ISkPath;
  end;
  // 1回の文書描画中だけ使用する。文書・レイヤーの所有権は呼び出し元に残す。
  TMapCrossingRenderContext = class
  private
    FVisuals: TArray<TMapCrossingVisual>;
    FMarkColor: TAlphaColor;
    FCanvasPath: ISkPath;
    procedure AddRailCrossing(Upper: TVectArtPathLayer; V: TMapCrossingVisual; UW: Single);
    procedure AddTunnel(Lower: TVectArtPathLayer; V: TMapCrossingVisual;
      UW, LW, Sine, Cosine, Margin, LowerDistance: Single);
    procedure AddBridge(Upper: TVectArtPathLayer; V: TMapCrossingVisual;
      UW, LW, Sine, Cosine, Margin, Distance: Single; Underpass: Boolean;
      var BridgeSpans: TArray<TMapRakuBridgeSpan>);
    procedure AddBridgeMarks(Upper: TVectArtPathLayer; const BridgeSpan: TMapRakuBridgeSpan);
    procedure AddCrossing(Document: TVectArtDocument; const C: TMapRakuCrossing;
      var BridgeSpans: TArray<TMapRakuBridgeSpan>);
  public
    // 現在形状から切り抜きと連結側線を作る。編集後は新しいコンテキストを作成する。
    constructor Create(Document: TVectArtDocument);
    // 呼び出し元のSave/Restore内で、対象レイヤーだけにクリップを適用する。
    procedure ClipLower(const Canvas: ISkCanvas; Layer: TVectArtLayer);
    // 上側本体と同じ不透明度で、統合済みの側線を一度だけ描く。
    procedure DrawMarks(const Canvas: ISkCanvas; Layer: TVectArtLayer;
      Opacity: Single);
  end;

implementation
uses System.Math, Vcl.Graphics, MapRakuCrossingGeometry;

// 平面交差は線路の模様だけを優先する。立体交差用の空白は付けない。
procedure TMapCrossingRenderContext.AddRailCrossing(Upper: TVectArtPathLayer;
  V: TMapCrossingVisual; UW: Single);
var Points: TArray<TPointF>; Builder: ISkPathBuilder; Stroke: ISkPaint; I: Integer;
begin
      // 平面の踏切は実際の線路模様だけを優先し、立体交差用の余白を作らない。
      // 全経路から模様を作ることでJRの白黒・枕木の位相も途中で変えない。
      if not ((Upper.MapElement='jr') or (Upper.MapElement='rail')) then Exit;
      Points:=MapCrossingPathSection(Upper,0,1E20);
      if Length(Points)<2 then Exit;
      Builder:=TSkPathBuilder.Create; Builder.MoveTo(Points[0]);
      for I:=1 to High(Points) do Builder.LineTo(Points[I]);
      Stroke:=TSkPaint.Create(TSkPaintStyle.Stroke);
      Stroke.StrokeWidth:=UW; Stroke.StrokeJoin:=TSkStrokeJoin.Round;
      if Upper.MapElement='rail' then Stroke.StrokeWidth:=Max(1,UW*0.15);
      V.Cut:=Stroke.GetFillPath(Builder.Snapshot);
      FVisuals:=FVisuals+[V];
      if Upper.MapElement='rail' then begin
        Stroke.StrokeWidth:=UW;
        Stroke.PathEffect:=TSkPathEffect.MakeDash([1.5,Max(3,UW*0.8)],0);
        V.Cut:=Stroke.GetFillPath(Builder.Detach);
        FVisuals:=FVisuals+[V];
      end;

end;

// 坑口は下側経路の端へ置くため、橋の側線統合には参加させない。
procedure TMapCrossingRenderContext.AddTunnel(Lower: TVectArtPathLayer;
  V: TMapCrossingVisual; UW, LW, Sine, Cosine, Margin, LowerDistance: Single);
var HalfLength, Len: Single; Points: TArray<TPointF>; P,T,N: TPointF;
  Builder,Marks: ISkPathBuilder; Stroke: ISkPaint; I,Side: Integer;
begin
      HalfLength:=((UW*0.5+10)+(LW*0.5+1)*Cosine)/Sine+Margin;
      Points:=MapCrossingPathSection(Lower,LowerDistance,HalfLength);
      if Length(Points)<2 then Exit;
      Builder:=TSkPathBuilder.Create; Builder.MoveTo(Points[0]);
      for I:=1 to High(Points) do Builder.LineTo(Points[I]);
      Stroke:=TSkPaint.Create(TSkPaintStyle.Stroke);
      Stroke.StrokeWidth:=LW+4; Stroke.StrokeCap:=TSkStrokeCap.Butt;
      Stroke.StrokeJoin:=TSkStrokeJoin.Round;
      V.Cut:=Stroke.GetFillPath(Builder.Detach);
      Marks:=TSkPathBuilder.Create;
      for Side:=0 to 1 do begin
        if Side=0 then begin P:=Points[0]; T:=Points[1]-P; end
        else begin P:=Points[High(Points)]; T:=Points[High(Points)-1]-P; end;
        Len:=Hypot(T.X,T.Y); if Len<1E-6 then Continue;
        T:=T/Len; N:=PointF(-T.Y,T.X)*(LW*0.5+4);
        Marks.MoveTo(P-N-T*2); Marks.QuadTo(P+T*6,P+N-T*2);
      end;
      V.Marks:=Marks.Detach; FVisuals:=FVisuals+[V]; Exit;

end;

// 切り抜きは交差ごと、側線は上側経路ごとに保持し、連結時も下側対象を混同しない。
procedure TMapCrossingRenderContext.AddBridge(Upper: TVectArtPathLayer;
  V: TMapCrossingVisual; UW, LW, Sine, Cosine, Margin, Distance: Single;
  Underpass: Boolean; var BridgeSpans: TArray<TMapRakuBridgeSpan>);
var HalfLength: Single; Points: TArray<TPointF>; Builder: ISkPathBuilder;
  Stroke: ISkPaint; I: Integer; BridgeSpan: TMapRakuBridgeSpan;
begin
    // 斜交・太い下側経路でも、縁が橋区間の端からはみ出さない長さ。
    HalfLength:=Max(12,((LW+2)*0.5+(UW*0.5+10)*Cosine)/Sine+Margin);
    Points:=MapCrossingPathSection(Upper,Distance,HalfLength);
    if Length(Points)<2 then Exit;
    Builder:=TSkPathBuilder.Create; Builder.MoveTo(Points[0]);
    for I:=1 to High(Points) do Builder.LineTo(Points[I]);
    Stroke:=TSkPaint.Create(TSkPaintStyle.Stroke);
    Stroke.StrokeWidth:=UW+20; Stroke.StrokeCap:=TSkStrokeCap.Butt;
    Stroke.StrokeJoin:=TSkStrokeJoin.Round;
    // 白塗りや全体消去ではなく、下側のレイヤーだけに差分クリップする。
    // 橋本体、側線、端の開きと余白を含め、透明背景でも切れ目を残す。
    V.Cut:=Stroke.GetFillPath(Builder.Detach);
    // 下側の切り抜きは対象ごとに保持し、橋の側線だけを上側経路の
    // 弧長区間でまとめる。連続する橋の内側に端の開きを描かない。
    FVisuals:=FVisuals+[V];
    BridgeSpan.UpperObjectId:=V.UpperId;
    BridgeSpan.StartDistance:=Distance-HalfLength;
    BridgeSpan.EndDistance:=Distance+HalfLength;
    BridgeSpan.Underpass:=Underpass;
    AddMapBridgeSpan(BridgeSpans,BridgeSpan);

end;

// 統合後の外端だけに開きを付け、半透明の側線も重複描画しない。
procedure TMapCrossingRenderContext.AddBridgeMarks(Upper: TVectArtPathLayer;
  const BridgeSpan: TMapRakuBridgeSpan);
var UW,Len,Offset: Single; Points: TArray<TPointF>; T,N,P: TPointF;
  V: TMapCrossingVisual; Marks: ISkPathBuilder; I,Side: Integer;
begin
    UW:=MapCrossingPathWidth(Upper);
    Points:=MapCrossingPathSection(Upper,
      (BridgeSpan.StartDistance+BridgeSpan.EndDistance)*0.5,
      (BridgeSpan.EndDistance-BridgeSpan.StartDistance)*0.5);
    if Length(Points)<2 then Exit;
    V:=Default(TMapCrossingVisual); V.UpperId:=BridgeSpan.UpperObjectId;
    Marks:=TSkPathBuilder.Create;
    for Side:=-1 to 1 do begin
      if Side=0 then Continue;
      for I:=0 to High(Points) do begin
        if I=High(Points) then T:=Points[I]-Points[I-1]
        else T:=Points[I+1]-Points[I];
        Len:=Hypot(T.X,T.Y); if Len<1E-6 then Continue;
        N:=PointF(-T.Y/Len,T.X/Len); Offset:=Side*(UW*0.5+4);
        P:=Points[I]+N*Offset;
        if I=0 then begin
          if BridgeSpan.Underpass then Marks.MoveTo(P)
          else begin Marks.MoveTo(P-T/Len*3+N*(Side*3)); Marks.LineTo(P); end;
        end else Marks.LineTo(P);
        if (I=High(Points)) and not BridgeSpan.Underpass then
          Marks.LineTo(P+T/Len*3+N*(Side*3));
      end;
    end;
    V.Marks:=Marks.Detach;
    FVisuals:=FVisuals+[V];

end;

// 永続IDからグループ内も探索し、レイヤーの並べ替え後も同じ対象を参照する。
function FindCrossingPath(Document: TVectArtDocument; const Id: string): TVectArtPathLayer;
var K: Integer;
  function FindIn(Layer: TVectArtLayer): TVectArtPathLayer;
  var J: Integer;
  begin
    Result:=nil;
    if (Layer is TVectArtPathLayer) and (Layer.PersistentId=Id) then
      Exit(TVectArtPathLayer(Layer));
    if Layer is TMapRakuGroupLayer then
      for J:=0 to TMapRakuGroupLayer(Layer).ChildCount-1 do begin
        Result:=FindIn(TMapRakuGroupLayer(Layer)[J]);
        if Result<>nil then Exit;
      end;
  end;
begin
  Result:=nil;
  for K:=1 to Document.LayerCount-1 do begin
    Result:=FindIn(Document[K]);
    if Result<>nil then Exit;
  end;
end;

procedure TMapCrossingRenderContext.AddCrossing(Document: TVectArtDocument;
  const C: TMapRakuCrossing; var BridgeSpans: TArray<TMapRakuBridgeSpan>);
var V: TMapCrossingVisual; Upper,Lower: TVectArtPathLayer; T,U: TPointF;
  Distance,LowerDistance,UW,LW,Sine,Cosine,Margin: Single;
  Relation: TMapRakuCrossingRelation;
begin
  if not (C.Kind in [mckBridge,mckOverpass,mckRailOverpass,
    mckUnderpass,mckTunnel,mckRailroadCrossing]) then Exit;
  V:=Default(TMapCrossingVisual); V.UpperId:=C.UpperObjectId;
  if C.UpperObjectId=C.ObjectAId then begin
    V.LowerId:=C.ObjectBId; T:=C.TangentA; U:=C.TangentB;
    Distance:=C.DistanceA; LowerDistance:=C.DistanceB;
  end else begin
    V.LowerId:=C.ObjectAId; T:=C.TangentB; U:=C.TangentA;
    Distance:=C.DistanceB; LowerDistance:=C.DistanceA;
  end;
  Upper:=FindCrossingPath(Document,V.UpperId);
  Lower:=FindCrossingPath(Document,V.LowerId);
  if (Upper=nil) or (Lower=nil) then Exit;
  UW:=MapCrossingPathWidth(Upper); LW:=MapCrossingPathWidth(Lower);
  if C.Kind=mckRailroadCrossing then begin AddRailCrossing(Upper,V,UW); Exit; end;
  Sine:=Max(1E-6,Abs(T.X*U.Y-T.Y*U.X));
  Cosine:=Abs(T.X*U.X+T.Y*U.Y); Margin:=12;
  Relation:=Document.FindCrossingRelation(C.ObjectAId,C.ObjectBId);
  if Relation<>nil then Margin:=Relation.RangeMargin;
  if C.Kind=mckTunnel then
    AddTunnel(Lower,V,UW,LW,Sine,Cosine,Margin,LowerDistance)
  else
    AddBridge(Upper,V,UW,LW,Sine,Cosine,Margin,Distance,C.Kind=mckUnderpass,BridgeSpans);
end;

constructor TMapCrossingRenderContext.Create(Document: TVectArtDocument);
var Builder: ISkPathBuilder; C: TMapRakuCrossing; I: Integer;
  BridgeSpans: TArray<TMapRakuBridgeSpan>; Span: TMapRakuBridgeSpan;
  Upper: TVectArtPathLayer;
begin
  inherited Create;
  Builder:=TSkPathBuilder.Create;
  Builder.AddRect(TRectF.Create(-Document.CanvasLayer.Width*0.5,
    -Document.CanvasLayer.Height*0.5,Document.CanvasLayer.Width*0.5,
    Document.CanvasLayer.Height*0.5));
  FCanvasPath:=Builder.Detach;
  FMarkColor:=TAlphaColorRec.Black;
  if ColorToRGB(Document.CanvasLayer.BackgroundColor)=clBlack then
    FMarkColor:=TAlphaColorRec.White;
  for C in CalculateMapRakuCrossings(Document) do AddCrossing(Document,C,BridgeSpans);
  for Span in BridgeSpans do begin
    Upper:=FindCrossingPath(Document,Span.UpperObjectId);
    if Upper<>nil then AddBridgeMarks(Upper,Span);
  end;
  // SVGの反転クリップを避け、残す領域は文書描画の準備時に一度だけ作る。
  for I:=0 to High(FVisuals) do
    if FVisuals[I].Cut<>nil then
      FVisuals[I].Cut:=FCanvasPath.Op(FVisuals[I].Cut,TSkPathOp.Difference);
end;

procedure TMapCrossingRenderContext.ClipLower(const Canvas: ISkCanvas;
  Layer: TVectArtLayer);
var V: TMapCrossingVisual;
begin
  for V in FVisuals do
    if (V.LowerId=Layer.PersistentId) and (V.Cut<>nil) then
      // SVGCanvasはDifferenceクリップを反転せず出力するため、先に
      // ベクターの差分を求め、残す領域を通常のIntersectで指定する。
      Canvas.ClipPath(V.Cut,TSkClipOp.Intersect,True);
end;

procedure TMapCrossingRenderContext.DrawMarks(const Canvas: ISkCanvas;
  Layer: TVectArtLayer; Opacity: Single);
var V: TMapCrossingVisual; Paint: ISkPaint;
begin
  Paint:=TSkPaint.Create(TSkPaintStyle.Stroke);
  Paint.Color:=FMarkColor; Paint.AlphaF:=Layer.Opacity*Opacity;
  Paint.StrokeWidth:=2; Paint.StrokeCap:=TSkStrokeCap.Butt;
  Paint.StrokeJoin:=TSkStrokeJoin.Round; Paint.AntiAlias:=True;
  for V in FVisuals do
    if (V.UpperId=Layer.PersistentId) and (V.Marks<>nil) then
      Canvas.DrawPath(V.Marks,Paint);
end;

end.
