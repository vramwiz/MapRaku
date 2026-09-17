// Documentの表示オブジェクトを、各ホストで共有できる透明RGBA8画像へ描画する。
// 描画スタイルのシェーダー生成はMapRakuPaintRendererへ委譲する。
unit MapRakuRenderer;

interface

uses
  System.Skia, System.SysUtils, System.Types, System.UITypes, Vcl.Graphics,
  MapRakuDocument, MapRakuRenderBuffer;

type
  // 既存利用側の型名を保ち、画素の管理責務はバッファユニットへ集約する。
  TVectArtRgbaPixel = MapRakuRenderBuffer.TVectArtRgbaPixel;
  PVectArtRgbaPixel = MapRakuRenderBuffer.PVectArtRgbaPixel;
  TVectArtRenderBuffer = MapRakuRenderBuffer.TVectArtRenderBuffer;

// Canvas背景を含めず、図形だけを透明RGBA8へ描画する。
// MinimumStrokeWidthは編集補助用の論理座標幅で、0ならDocumentの線幅を変更しない。
procedure RenderVectArtDocument(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  MinimumStrokeWidth: Single = 0.0;
  InputTextLayer: TMapRakuTextLayer = nil;
  InputTextOutlineColor: TColor = clNone);
// Document直下の指定範囲だけを、元の重なり順とグループ合成を保って描画する。
// 移動プレビューでは下層・選択層・上層を一度ずつ保持するために使用する。
procedure RenderVectArtDocumentRange(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height, FirstLayerIndex,
  LastLayerIndex: Integer; MinimumStrokeWidth: Single = 0.0);
// 単体レイヤーまたはグループ子孫を、通常描画と同じ処理でサムネイルへ収める。
procedure RenderVectArtLayerThumbnail(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; Width, Height: Integer);
// ストレートアルファRGBA8同士をSource-overで合成する。
procedure CompositeVectArtRgba(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height: Integer);
// Sourceを整数ピクセルだけ移動してSource-over合成する。領域外は切り捨てる。
procedure CompositeVectArtRgbaOffset(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height, OffsetX,
  OffsetY: Integer);

// SVGと画面で共通の描画処理を使用する。Canvasは呼び出し元が所有する。
procedure RenderMapLayersToCanvas(const Layers: TArray<TVectArtLayer>;
  const Canvas: ISkCanvas; Width, Height: Integer; Opacity: Single; MapPass: Integer = 0);
// 画面・PNG・SVGで層ごとの道路合成と下側経路の切り抜きを共用する。
procedure RenderMapDocumentToCanvas(Document: TVectArtDocument;
  const Canvas: ISkCanvas);
implementation

uses
  System.Generics.Collections, System.Math, System.Math.Vectors,
  TextRendererSkiaRuntime, Winapi.Windows,
  MapRakuEllipseGeometry, MapRakuGeometry,
  MapRakuFilters, MapRakuLayerGeometry, MapRakuPathOperations,
  MapRakuPaintRenderer, MapRakuPatternRenderer,
  MapRakuPathRenderer, MapRakuRailRenderer, MapRakuShapePath, MapRakuTextGeometry,
  MapRakuTextPathGeometry, MapRakuVariableWidthRenderer, MapRakuCrossingRenderer;

const
  SKIA_DEFAULT_STROKE_MITER_LIMIT = 4.0;

function BuildMapRakuImageFilter(
  Filter: TMapRakuFilter; ScaleX: Single = 1.0;
  ScaleY: Single = 1.0): ISkImageFilter;
var
  ColorizedOutline: ISkImageFilter;
  DilatedOutline: ISkImageFilter;
  OutlineFilter: TMapRakuOutlineFilter;
  ShadowFilter: TMapRakuShadowFilter;
begin
  Result := nil;
  if (Filter = nil) or not Filter.Enabled then
    Exit;
  ScaleX := Max(Abs(ScaleX), 0.0);
  ScaleY := Max(Abs(ScaleY), 0.0);
  case Filter.Kind of
    slfkOutline:
    begin
      OutlineFilter := TMapRakuOutlineFilter(Filter);
      if OutlineFilter.Width <= 0 then
        Exit;
      DilatedOutline := TSkImageFilter.MakeDilate(
        OutlineFilter.Width * ScaleX, OutlineFilter.Width * ScaleY);
      ColorizedOutline := TSkImageFilter.MakeColorFilter(
        TSkColorFilter.MakeBlend(
          VclColorToAlphaColor(OutlineFilter.Color, 1.0),
          TSkBlendMode.SrcIn), DilatedOutline);
      // Paint the original input over the expanded, colorized alpha mask.
      Result := TSkImageFilter.MakeBlend(TSkBlendMode.SrcOver,
        ColorizedOutline);
    end;
    slfkShadow:
    begin
      ShadowFilter := TMapRakuShadowFilter(Filter);
      Result := TSkImageFilter.MakeDropShadow(
        ShadowFilter.OffsetX * ScaleX, ShadowFilter.OffsetY * ScaleY,
        Max(ShadowFilter.BlurRadius * ScaleX, 0.0),
        Max(ShadowFilter.BlurRadius * ScaleY, 0.0),
        VclColorToAlphaColor(ShadowFilter.Color,
          EnsureRange(ShadowFilter.Opacity, 0.0, 1.0)));
    end;
    slfkBlur:
      if TMapRakuBlurFilter(Filter).Radius > 0 then
        Result := TSkImageFilter.MakeBlur(
          TMapRakuBlurFilter(Filter).Radius * ScaleX,
          TMapRakuBlurFilter(Filter).Radius * ScaleY);
  end;
end;

procedure RenderVectArtLayerTree(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  const LogicalBounds: TRectF; MinimumStrokeWidth,
  OpacityMultiplier: Single; InputTextLayer: TMapRakuTextLayer;
  InputTextOutlineColor: TColor;
  Crossings: TMapCrossingRenderContext = nil;
  const OutputCanvas: ISkCanvas = nil); forward;
procedure RenderVectArtLayers(const RenderLayers: TArray<TVectArtLayer>;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  const LogicalBounds: TRectF; MinimumStrokeWidth,
  OpacityMultiplier: Single; InputTextLayer: TMapRakuTextLayer;
  InputTextOutlineColor: TColor; MapPass: Integer = 0;
  const OutputCanvas: ISkCanvas = nil;
  Crossings: TMapCrossingRenderContext = nil); forward;

procedure RenderVectArtLevelRanges(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height, FirstLayerIndex,
  LastLayerIndex: Integer; const LogicalBounds: TRectF;
  MinimumStrokeWidth: Single; InputTextLayer: TMapRakuTextLayer;
  InputTextOutlineColor: TColor; const OutputCanvas: ISkCanvas = nil);
var
  Batch: TList<TVectArtLayer>;
  Crossings: TMapCrossingRenderContext;
  HasMapPath: Boolean;
  I: Integer;
  LayerBuffer: TVectArtRenderBuffer;
  function CanBatchMap(Layer: TVectArtLayer): Boolean;
  var K: Integer;
  begin
    if Layer is TMapRakuGroupLayer then begin
      if (Layer.Opacity<>1) or (Layer.FilterCount<>0) then Exit(False);
      for K:=0 to TMapRakuGroupLayer(Layer).ChildCount-1 do
        if not CanBatchMap(TMapRakuGroupLayer(Layer)[K]) then Exit(False);
      Exit(True);
    end;
    Result:=(Layer is TVectArtPathLayer) and
      (TVectArtPathLayer(Layer).MapElement<>'');
  end;
  procedure AddMapLeaves(Layer: TVectArtLayer);
  var K: Integer;
  begin
    if not Layer.Visible then Exit;
    if Layer is TMapRakuGroupLayer then
      for K:=0 to TMapRakuGroupLayer(Layer).ChildCount-1 do
        AddMapLeaves(TMapRakuGroupLayer(Layer)[K])
    else begin Batch.Add(Layer); HasMapPath:=True; end;
  end;
  procedure FlushBatch;
  begin
    if Batch.Count = 0 then Exit;
    if HasMapPath then
    begin
      RenderVectArtLayers(Batch.ToArray, LayerBuffer, Width, Height,
        LogicalBounds, MinimumStrokeWidth, 1.0, InputTextLayer,
        InputTextOutlineColor, 1, OutputCanvas, Crossings);
      if OutputCanvas=nil then CompositeVectArtRgba(LayerBuffer, Target.Data, Width, Height);
      RenderVectArtLayers(Batch.ToArray, LayerBuffer, Width, Height,
        LogicalBounds, MinimumStrokeWidth, 1.0, InputTextLayer,
        InputTextOutlineColor, 2, OutputCanvas, Crossings);
      if OutputCanvas=nil then CompositeVectArtRgba(LayerBuffer, Target.Data, Width, Height);
    end
    else
    begin
      RenderVectArtLayers(Batch.ToArray, LayerBuffer, Width, Height,
        LogicalBounds, MinimumStrokeWidth, 1.0, InputTextLayer,
        InputTextOutlineColor, 0, OutputCanvas, Crossings);
      if OutputCanvas=nil then CompositeVectArtRgba(LayerBuffer, Target.Data, Width, Height);
    end;
    Batch.Clear;
    HasMapPath := False;
  end;
begin
  Target.SetSize(Width, Height);
  Target.Clear;
  Batch := TList<TVectArtLayer>.Create;
  HasMapPath := False;
  LayerBuffer := TVectArtRenderBuffer.Create;
  Crossings := TMapCrossingRenderContext.Create(Document);
  try
    for I := FirstLayerIndex to LastLayerIndex do
    begin
      if Document[I] is TMapRakuLevelBoundaryLayer then
      begin
        FlushBatch;
        Continue;
      end;
      if not Document[I].Visible then Continue;
      if Document[I] is TMapRakuGroupLayer then
      begin
        // 整理用グループを高さの境界として扱わない。
        if CanBatchMap(Document[I]) then begin
          AddMapLeaves(Document[I]); Continue;
        end;
        FlushBatch;
        RenderVectArtLayerTree(Document[I], LayerBuffer, Width, Height,
          LogicalBounds, MinimumStrokeWidth, 1.0, InputTextLayer,
          InputTextOutlineColor, Crossings, OutputCanvas);
        if OutputCanvas=nil then
          CompositeVectArtRgba(LayerBuffer, Target.Data, Width, Height);
      end
      else
      begin
        Batch.Add(Document[I]);
        HasMapPath := HasMapPath or ((Document[I] is TVectArtPathLayer) and
          (TVectArtPathLayer(Document[I]).MapElement <> ''));
      end;
    end;
    FlushBatch;
  finally
    Crossings.Free;
    LayerBuffer.Free;
    Batch.Free;
  end;
end;

procedure RenderVectArtDocumentRange(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height, FirstLayerIndex,
  LastLayerIndex: Integer; MinimumStrokeWidth: Single);
var
  CanvasLayer: TVectArtCanvasLayer;
  LogicalBounds: TRectF;
  PatternScope: IInterface;
begin
  if Document = nil then
    raise EArgumentNilException.Create('Document');
  if Target = nil then
    raise EArgumentNilException.Create('Target');
  CanvasLayer := Document.CanvasLayer;
  if CanvasLayer = nil then
    raise EInvalidOp.Create('Document canvas is missing');
  LogicalBounds := TRectF.Create(-CanvasLayer.Width * 0.5,
    -CanvasLayer.Height * 0.5, CanvasLayer.Width * 0.5,
    CanvasLayer.Height * 0.5);
  Target.SetSize(Width, Height);
  Target.Clear;
  FirstLayerIndex := Max(FirstLayerIndex, 1);
  LastLayerIndex := Min(LastLayerIndex, Document.LayerCount - 1);
  if FirstLayerIndex > LastLayerIndex then
    Exit;

  PatternScope := BeginMapRakuPatternRender(Max(
    Width / Max(LogicalBounds.Width, 1),
    Height / Max(LogicalBounds.Height, 1)));
  RenderVectArtLevelRanges(Document, Target, Width, Height,
    FirstLayerIndex, LastLayerIndex, LogicalBounds, MinimumStrokeWidth,
    nil, clNone);
end;

procedure InflateMapRakuBounds(var Bounds: TRectF; X, Y: Single);
begin
  Bounds.Left := Bounds.Left - Max(X, 0.0);
  Bounds.Top := Bounds.Top - Max(Y, 0.0);
  Bounds.Right := Bounds.Right + Max(X, 0.0);
  Bounds.Bottom := Bounds.Bottom + Max(Y, 0.0);
end;

procedure ExpandMapRakuFilterBounds(Layer: TVectArtLayer;
  var Bounds: TRectF);
var
  Blur: Single;
  EffectBounds: TRectF;
  Filter: TMapRakuFilter;
  I: Integer;
  Shadow: TMapRakuShadowFilter;
begin
  for I := 0 to Layer.FilterCount - 1 do
  begin
    Filter := Layer.Filters[I];
    if not Filter.Enabled then
      Continue;
    case Filter.Kind of
      slfkOutline:
        InflateMapRakuBounds(Bounds,
          TMapRakuOutlineFilter(Filter).Width,
          TMapRakuOutlineFilter(Filter).Width);
      slfkShadow:
      begin
        Shadow := TMapRakuShadowFilter(Filter);
        EffectBounds := Bounds;
        EffectBounds.Offset(Shadow.OffsetX, Shadow.OffsetY);
        Blur := Max(Shadow.BlurRadius, 0.0) * 3.0;
        InflateMapRakuBounds(EffectBounds, Blur, Blur);
        Bounds.Left := Min(Bounds.Left, EffectBounds.Left);
        Bounds.Top := Min(Bounds.Top, EffectBounds.Top);
        Bounds.Right := Max(Bounds.Right, EffectBounds.Right);
        Bounds.Bottom := Max(Bounds.Bottom, EffectBounds.Bottom);
      end;
      slfkBlur:
      begin
        Blur := Max(TMapRakuBlurFilter(Filter).Radius, 0.0) * 3.0;
        InflateMapRakuBounds(Bounds, Blur, Blur);
      end;
    end;
  end;
end;

function TryGetMapRakuPaintBounds(Layer: TVectArtLayer;
  MinimumStrokeWidth: Single; out Bounds: TRectF; SourceSpace: Boolean = False): Boolean;
var
  StrokeMargin: Single;
  StrokeWidth: Single;
begin
  if SourceSpace then Result := TryGetMapRakuLayerSourceBounds(Layer, Bounds)
  else Result := TryGetMapRakuLayerBounds(Layer, Bounds);
  if not Result then
    Exit;
  StrokeMargin := 0.0;
  if Layer is TMapRakuShapeLayer then
  begin
    StrokeWidth := Max(TMapRakuShapeLayer(Layer).StrokeWidth,
      MinimumStrokeWidth);
    StrokeMargin := StrokeWidth * 0.5 * SKIA_DEFAULT_STROKE_MITER_LIMIT;
  end
  else if Layer is TMapRakuRectangleLineLayer then
  begin
    StrokeWidth := Max(TMapRakuRectangleLineLayer(Layer).StrokeWidth,
      MinimumStrokeWidth);
    StrokeMargin := StrokeWidth * 0.5 * SKIA_DEFAULT_STROKE_MITER_LIMIT;
  end
  else if Layer is TMapRakuArcLayer then
    StrokeMargin := Max(TMapRakuArcLayer(Layer).StrokeWidth,
      MinimumStrokeWidth) * Sqrt(0.5)
  else if Layer is TVectArtPathLayer then
  begin
    StrokeWidth := Max(TVectArtPathLayer(Layer).StrokeWidth,
      MinimumStrokeWidth);
    // Skiaの既定マイター上限まで確保し、鋭角の線がフィルター用
    // SaveLayerの境界で先に切り落とされないようにする。
    StrokeMargin := StrokeWidth * 0.5 * SKIA_DEFAULT_STROKE_MITER_LIMIT;
  end;
  InflateMapRakuBounds(Bounds, StrokeMargin, StrokeMargin);
  ExpandMapRakuFilterBounds(Layer, Bounds);
end;

procedure DrawTriangleLineCap(const Canvas: ISkCanvas; const Position: TPointF;
  OutwardDirection: TPointF; HalfWidth: Single; const Paint: ISkPaint);
var
  DirectionLength: Single;
  Normal: TPointF;
  PathBuilder: ISkPathBuilder;
  Tip: TPointF;
begin
  DirectionLength := Hypot(OutwardDirection.X, OutwardDirection.Y);
  if DirectionLength <= 0.0001 then
    Exit;
  OutwardDirection := TPointF.Create(OutwardDirection.X / DirectionLength,
    OutwardDirection.Y / DirectionLength);
  Normal := TPointF.Create(-OutwardDirection.Y * HalfWidth,
    OutwardDirection.X * HalfWidth);
  Tip := TPointF.Create(Position.X + OutwardDirection.X * HalfWidth,
    Position.Y + OutwardDirection.Y * HalfWidth);
  PathBuilder := TSkPathBuilder.Create;
  PathBuilder.MoveTo(TPointF.Create(Position.X + Normal.X,
    Position.Y + Normal.Y));
  PathBuilder.LineTo(Tip);
  PathBuilder.LineTo(TPointF.Create(Position.X - Normal.X,
    Position.Y - Normal.Y));
  PathBuilder.Close;
  Canvas.DrawPath(PathBuilder.Detach, Paint);
end;

procedure DrawPathTriangleCaps(const Canvas: ISkCanvas;
  const Vertices: TArray<TMapRakuVertex>; StrokeWidth: Single;
  const Paint: ISkPaint);
var
  Direction: TPointF;
  LastIndex: Integer;
begin
  if Length(Vertices) < 2 then
    Exit;
  LastIndex := High(Vertices);
  if (Vertices[0].OutgoingSegment = slskCubicBezier) and
    not IsZero(Hypot(Vertices[0].OutgoingControl.X,
      Vertices[0].OutgoingControl.Y)) then
    Direction := Vertices[0].OutgoingControl
  else
    Direction := TPointF.Create(Vertices[1].Position.X -
      Vertices[0].Position.X, Vertices[1].Position.Y -
      Vertices[0].Position.Y);
  DrawTriangleLineCap(Canvas, Vertices[0].Position,
    TPointF.Create(-Direction.X, -Direction.Y), StrokeWidth * 0.5, Paint);

  if (Vertices[LastIndex - 1].OutgoingSegment = slskCubicBezier) and
    not IsZero(Hypot(Vertices[LastIndex].IncomingControl.X,
      Vertices[LastIndex].IncomingControl.Y)) then
    Direction := TPointF.Create(-Vertices[LastIndex].IncomingControl.X,
      -Vertices[LastIndex].IncomingControl.Y)
  else
    Direction := TPointF.Create(Vertices[LastIndex].Position.X -
      Vertices[LastIndex - 1].Position.X,
      Vertices[LastIndex].Position.Y -
      Vertices[LastIndex - 1].Position.Y);
  DrawTriangleLineCap(Canvas, Vertices[LastIndex].Position, Direction,
    StrokeWidth * 0.5, Paint);
end;

function BuildRoundedRectanglePath(const Bounds: TRectF;
  const SourceRadii: TMapRakuCornerRadii): ISkPath;
const
  KAPPA = 0.5522847498;
var
  Builder: ISkPathBuilder;
  Radii: TMapRakuCornerRadii;
begin
  Radii := ClampMapRakuCornerRadii(Bounds, SourceRadii);
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(Bounds.Left + Radii.TopLeft, Bounds.Top);
  Builder.LineTo(Bounds.Right - Radii.TopRight, Bounds.Top);
  if Radii.TopRight > 0 then
    Builder.CubicTo(
      TPointF.Create(Bounds.Right - Radii.TopRight * (1 - KAPPA),
        Bounds.Top),
      TPointF.Create(Bounds.Right,
        Bounds.Top + Radii.TopRight * (1 - KAPPA)),
      TPointF.Create(Bounds.Right, Bounds.Top + Radii.TopRight));
  Builder.LineTo(Bounds.Right, Bounds.Bottom - Radii.BottomRight);
  if Radii.BottomRight > 0 then
    Builder.CubicTo(
      TPointF.Create(Bounds.Right,
        Bounds.Bottom - Radii.BottomRight * (1 - KAPPA)),
      TPointF.Create(Bounds.Right - Radii.BottomRight * (1 - KAPPA),
        Bounds.Bottom),
      TPointF.Create(Bounds.Right - Radii.BottomRight, Bounds.Bottom));
  Builder.LineTo(Bounds.Left + Radii.BottomLeft, Bounds.Bottom);
  if Radii.BottomLeft > 0 then
    Builder.CubicTo(
      TPointF.Create(Bounds.Left + Radii.BottomLeft * (1 - KAPPA),
        Bounds.Bottom),
      TPointF.Create(Bounds.Left,
        Bounds.Bottom - Radii.BottomLeft * (1 - KAPPA)),
      TPointF.Create(Bounds.Left, Bounds.Bottom - Radii.BottomLeft));
  Builder.LineTo(Bounds.Left, Bounds.Top + Radii.TopLeft);
  if Radii.TopLeft > 0 then
    Builder.CubicTo(
      TPointF.Create(Bounds.Left,
        Bounds.Top + Radii.TopLeft * (1 - KAPPA)),
      TPointF.Create(Bounds.Left + Radii.TopLeft * (1 - KAPPA),
        Bounds.Top),
      TPointF.Create(Bounds.Left + Radii.TopLeft, Bounds.Top));
  Builder.Close;
  Result := Builder.Detach;
end;

{ TVectArtRenderBuffer }

procedure DrawMapRakuTextLine(const Canvas: ISkCanvas;
  const Text: string; const Font: ISkFont; const Paint: ISkPaint;
  X, BaselineY, LetterSpacing, FontSize: Single;
  const IndividualLetterSpacingRatios: TArray<Single>;
  GapOffset: Integer);
var
  GapIndex: Integer;
  I: Integer;
  UnitLength: Integer;
  UnitText: string;
begin
  if SameValue(LetterSpacing, 0) and
    (Length(IndividualLetterSpacingRatios) = 0) then
  begin
    Canvas.DrawSimpleText(Text, X, BaselineY, Font, Paint);
    Exit;
  end;
  I := 1;
  GapIndex := GapOffset;
  while I <= Length(Text) do
  begin
    UnitLength := MapRakuTextUnitLengthAt(Text, I);
    UnitText := Copy(Text, I, UnitLength);
    Canvas.DrawSimpleText(UnitText, X, BaselineY, Font, Paint);
    X := X + Font.MeasureText(UnitText);
    Inc(I, UnitLength);
    if I <= Length(Text) then
    begin
      X := X + LetterSpacing;
      if (GapIndex >= 0) and
        (GapIndex < Length(IndividualLetterSpacingRatios)) then
        X := X + FontSize * IndividualLetterSpacingRatios[GapIndex];
      Inc(GapIndex);
    end;
  end;
end;

procedure DrawMapRakuTextOnPath(const Canvas: ISkCanvas;
  Layer: TMapRakuTextPathLayer; const Font: ISkFont;
  const Paint: ISkPaint);
var
  I: Integer;
  ScaleY: Single;
  Placements: TArray<TMapRakuTextPathPlacement>;
begin
  Placements := BuildMapRakuTextPathPlacements(Layer, Font);
  for I := 0 to High(Placements) do
  begin
    Canvas.Save;
    try
      Canvas.Translate(Placements[I].Anchor.X, Placements[I].Anchor.Y);
      Canvas.Rotate(Placements[I].AngleDegrees);
      if Layer.FlipHorizontal xor Layer.FlipVertical then
        ScaleY := -Placements[I].Scale
      else
        ScaleY := Placements[I].Scale;
      Canvas.Scale(Placements[I].Scale, ScaleY);
      Canvas.DrawSimpleText(Placements[I].TextUnit,
        Placements[I].TextOrigin.X, Placements[I].TextOrigin.Y, Font, Paint);
    finally
      Canvas.Restore;
    end;
  end;
end;

procedure ApplyMapRakuLayerFilters(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; ScaleX, ScaleY: Single);
var
  Canvas: ISkCanvas;
  FilterImage: ISkImageFilter;
  FilterPaint: ISkPaint;
  I: Integer;
  ImageInfo: TSkImageInfo;
  InputImage: ISkImage;
  InputSurface: ISkSurface;
  OutputSurface: ISkSurface;
  Scratch: TVectArtRenderBuffer;
begin
  if (Layer = nil) or (Target = nil) or (Target.PixelCount = 0) then
    Exit;
  Scratch := TVectArtRenderBuffer.Create;
  try
    Scratch.SetSize(Target.Width, Target.Height);
    ImageInfo := TSkImageInfo.Create(Target.Width, Target.Height,
      TSkColorType.RGBA8888, TSkAlphaType.Unpremul);
    for I := 0 to Layer.FilterCount - 1 do
    begin
      FilterImage := BuildMapRakuImageFilter(Layer.Filters[I],
        ScaleX, ScaleY);
      if FilterImage = nil then
        Continue;
      InputSurface := TSkSurface.MakeRasterDirect(ImageInfo, Target.Data,
        Target.Stride);
      if InputSurface = nil then
        raise EInvalidOp.Create('Cannot create filter input surface');
      InputSurface.Flush;
      InputImage := InputSurface.MakeImageSnapshot;
      Scratch.Clear;
      OutputSurface := TSkSurface.MakeRasterDirect(ImageInfo, Scratch.Data,
        Scratch.Stride);
      if OutputSurface = nil then
        raise EInvalidOp.Create('Cannot create filter output surface');
      Canvas := OutputSurface.Canvas;
      Canvas.Clear(TAlphaColorRec.Null);
      FilterPaint := TSkPaint.Create;
      FilterPaint.ImageFilter := FilterImage;
      Canvas.DrawImage(InputImage, 0, 0, FilterPaint);
      OutputSurface.Flush;
      Canvas := nil;
      OutputSurface := nil;
      InputImage := nil;
      InputSurface := nil;
      Move(Scratch.Data^, Target.Data^,
        Target.PixelCount * SizeOf(TVectArtRgbaPixel));
    end;
  finally
    Scratch.Free;
  end;
end;

procedure RenderMapDocumentToCanvas(Document: TVectArtDocument;
  const Canvas: ISkCanvas);
var Bounds: TRectF; Buffer: TVectArtRenderBuffer;
begin
  if (Document=nil) or (Canvas=nil) then Exit;
  Bounds:=TRectF.Create(-Document.CanvasLayer.Width*0.5,
    -Document.CanvasLayer.Height*0.5,Document.CanvasLayer.Width*0.5,
    Document.CanvasLayer.Height*0.5);
  Buffer:=TVectArtRenderBuffer.Create;
  try
    RenderVectArtLevelRanges(Document,Buffer,Document.CanvasLayer.Width,
      Document.CanvasLayer.Height,1,Document.LayerCount-1,Bounds,0,nil,clNone,Canvas);
  finally Buffer.Free; end;
end;
procedure RenderVectArtDocument(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  MinimumStrokeWidth: Single;
  InputTextLayer: TMapRakuTextLayer;
  InputTextOutlineColor: TColor);
var
  CanvasLayer: TVectArtCanvasLayer;
  LogicalBounds: TRectF;
  PatternScope: IInterface; // この文書描画だけでタイルを共有し、終了時に全画像を解放する。
begin
  if Document = nil then
    raise EArgumentNilException.Create('Document');
  CanvasLayer := Document.CanvasLayer;
  if CanvasLayer = nil then
    raise EInvalidOp.Create('Document canvas is missing');
  LogicalBounds := TRectF.Create(-CanvasLayer.Width * 0.5,
    -CanvasLayer.Height * 0.5, CanvasLayer.Width * 0.5,
    CanvasLayer.Height * 0.5);
  if Target = nil then
    raise EArgumentNilException.Create('Target');
  PatternScope := BeginMapRakuPatternRender(Max(Width / Max(LogicalBounds.Width, 1),
    Height / Max(LogicalBounds.Height, 1)));
  RenderVectArtLevelRanges(Document, Target, Width, Height, 1,
    Document.LayerCount - 1, LogicalBounds, MinimumStrokeWidth,
    InputTextLayer, InputTextOutlineColor);

end;

function FitMapRakuThumbnailBounds(const ContentBounds: TRectF;
  Width, Height: Integer; Margin: Integer; out LogicalBounds: TRectF;
  out Scale: Single): Boolean;
var
  AvailableHeight: Integer;
  AvailableWidth: Integer;
  Center: TPointF;
  ContentHeight: Single;
  ContentWidth: Single;
  LogicalHeight: Single;
  LogicalWidth: Single;
begin
  Result := False;
  AvailableWidth := Width - Margin * 2;
  AvailableHeight := Height - Margin * 2;
  if (AvailableWidth <= 0) or (AvailableHeight <= 0) then
    Exit;
  ContentWidth := Max(ContentBounds.Width, 1.0);
  ContentHeight := Max(ContentBounds.Height, 1.0);
  Scale := Min(AvailableWidth / ContentWidth,
    AvailableHeight / ContentHeight);
  if Scale <= 0 then
    Exit;
  LogicalWidth := Width / Scale;
  LogicalHeight := Height / Scale;
  Center := ContentBounds.CenterPoint;
  LogicalBounds := TRectF.Create(Center.X - LogicalWidth * 0.5,
    Center.Y - LogicalHeight * 0.5, Center.X + LogicalWidth * 0.5,
    Center.Y + LogicalHeight * 0.5);
  Result := True;
end;

procedure RenderVectArtLayerThumbnail(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; Width, Height: Integer);
const
  THUMBNAIL_MARGIN = 5;
  THUMBNAIL_MINIMUM_STROKE_WIDTH = 1.0;
var
  ContentBounds: TRectF;
  LogicalBounds: TRectF;
  OpacityMultiplier: Single;
  Scale: Single;
  PatternScope: IInterface; // サムネイル倍率で生成した一時画像の所有者。
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  if Target = nil then
    raise EArgumentNilException.Create('Target');
  Target.SetSize(Width, Height);
  Target.Clear;
  if not TryGetMapRakuLayerBounds(Layer, ContentBounds) or
    not FitMapRakuThumbnailBounds(ContentBounds, Width, Height,
      THUMBNAIL_MARGIN, LogicalBounds, Scale) then
    Exit;
  if Layer.Visible then
    OpacityMultiplier := 1.0
  else
    OpacityMultiplier := 0.35;
  PatternScope := BeginMapRakuPatternRender(Scale);
  RenderVectArtLayerTree(Layer, Target, Width, Height, LogicalBounds,
    THUMBNAIL_MINIMUM_STROKE_WIDTH / Scale, OpacityMultiplier, nil, clNone);
end;

procedure RenderVectArtLayers(const RenderLayers: TArray<TVectArtLayer>;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  const LogicalBounds: TRectF; MinimumStrokeWidth,
  OpacityMultiplier: Single;
  InputTextLayer: TMapRakuTextLayer;
  InputTextOutlineColor: TColor; MapPass: Integer; const OutputCanvas: ISkCanvas;
  Crossings: TMapCrossingRenderContext);
var
  CanvasSettings: TVectArtCanvasLayer;
  ArcEndPoint: TPointF;
  ArcEndTangent: TPointF;
  ArcLayer: TMapRakuArcLayer;
  ArcStartPoint: TPointF;
  ArcStartTangent: TPointF;
  Canvas: ISkCanvas;
  DashIntervals: TArray<Single>;
  EllipseLayer: TMapRakuEllipseLayer;
  EllipseLine: TMapRakuEllipseLineLayer;
  EllipseArcShape: TMapRakuEllipseArcShapeLayer;
  I: Integer;
  J: Integer;
  ImageInfo: TSkImageInfo;
  ImageLayer: TVectArtImageLayer;
  ImagePaint: ISkPaint;
  Font: ISkFont;
  FilterImage: ISkImageFilter;
  FilterPaint: ISkPaint;
  FilterSaveCount: Integer;
  FilterBounds: TRectF;
  RasterImage: ISkImage;
  EdgeWidth: Single;
  SignedHeight: Single;
  RotationDegrees: Single;
  Layer: TVectArtLayer;
  Paint: ISkPaint;
  Path: ISkPath;
  PathBuilder: ISkPathBuilder;
  PathLayer: TVectArtPathLayer;
  PathSegmentCount: Integer;
  PathVertices: TArray<TMapRakuVertex>;
  RectangleLayer: TVectArtRectangleLayer;
  RectangleLine: TMapRakuRectangleLineLayer;
  RectangleLineCorners: TVectArtQuad;
  RoundedRectangleLayer: TMapRakuRoundedRectangleLayer;
  RoundedRectangleLine: TMapRakuRoundedRectangleLineLayer;
  ScaleX: Single;
  ScaleY: Single;
  StrokeWidth: Single;
  StrokePaint: ISkPaint;
  Surface: ISkSurface;
  ShapeLayer: TMapRakuShapeLayer;
  TextLayer: TMapRakuTextLayer;
  TextDecorationPaint: ISkPaint;
  TextOutlinePaint: ISkPaint;
  TextLayout: TMapRakuTextLayout;
  TextRenderScaleX: Single;
  TextRenderScaleY: Single;
  TextWidth: Single;
  TextX: Single;
  LetterSpacing: Single;
  IndividualLetterSpacingRatios: TArray<Single>;
  TransformMatrix: TMatrix;
  VariableWidthPath: ISkPath;
  WidthPoints: TArray<TMapRakuStrokeWidthPoint>;

begin
  if Target = nil then
    raise EArgumentNilException.Create('Target');
  if not TTextRendererSkiaRuntime.IsAcquired then
    raise EInvalidOp.Create('Skia runtime is not acquired');
  if (Width <= 0) or (Height <= 0) then
    raise EArgumentOutOfRangeException.Create('Render dimensions must be positive');
  if (LogicalBounds.Width <= 0) or (LogicalBounds.Height <= 0) then
    raise EArgumentOutOfRangeException.Create('Logical bounds must be positive');

  if OutputCanvas = nil then begin
  Target.SetSize(Width, Height);
  Target.Clear;
  ImageInfo := TSkImageInfo.Create(Width, Height, TSkColorType.RGBA8888,
    TSkAlphaType.Unpremul);
  Surface := TSkSurface.MakeRasterDirect(ImageInfo, Target.Data,
    Target.Stride);
  if Surface = nil then
    raise EInvalidOp.Create('Cannot create VectArt raster surface');
  Canvas := Surface.Canvas;
  Canvas.Clear(TAlphaColorRec.Null);
  end else Canvas := OutputCanvas;
  Canvas.Save;
  try
  ScaleX := Width / LogicalBounds.Width;
  ScaleY := Height / LogicalBounds.Height;
  MinimumStrokeWidth := Max(MinimumStrokeWidth, 0.0);
  OpacityMultiplier := EnsureRange(OpacityMultiplier, 0.0, 1.0);
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  StrokePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  StrokePaint.AntiAlias := True;
  TextDecorationPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  TextDecorationPaint.AntiAlias := True;
  TextOutlinePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  TextOutlinePaint.AntiAlias := True;
  ImagePaint := TSkPaint.Create;
  ImagePaint.AntiAlias := True;
  Canvas.Scale(ScaleX, ScaleY);
  Canvas.Translate(-LogicalBounds.Left, -LogicalBounds.Top);
  for I := 0 to High(RenderLayers) do
  begin
    Layer := RenderLayers[I];
    Canvas.Save;
    if Crossings<>nil then Crossings.ClipLower(Canvas,Layer);
    Canvas.Save;
    TransformMatrix := Layer.Transform.Matrix;
    Canvas.Concat(TransformMatrix);
    Paint.Shader := nil;
    StrokePaint.Shader := nil;
    FilterSaveCount := 0;
    if not TryGetMapRakuPaintBounds(Layer, MinimumStrokeWidth,
      FilterBounds, True) then
      FilterBounds := LogicalBounds;
    // Save in reverse so Restore applies the stack in list order.
    for J := Layer.FilterCount - 1 downto 0 do
    begin
      FilterImage := BuildMapRakuImageFilter(Layer.Filters[J]);
      if FilterImage = nil then
        Continue;
      FilterPaint := TSkPaint.Create;
      FilterPaint.ImageFilter := FilterImage;
      Canvas.SaveLayer(FilterBounds, FilterPaint);
      Inc(FilterSaveCount);
    end;
    try
    if Layer is TVectArtImageLayer then
    begin
      ImageLayer := TVectArtImageLayer(Layer);
      RasterImage := TSkImage.MakeFromEncoded(ImageLayer.PngData);
      if (RasterImage = nil) or (RasterImage.Width <= 0) or
        (RasterImage.Height <= 0) then
        Continue;
      EdgeWidth := Hypot(
        ImageLayer.Points[1].X - ImageLayer.Points[0].X,
        ImageLayer.Points[1].Y - ImageLayer.Points[0].Y);
      if EdgeWidth <= 0 then
        Continue;
      SignedHeight := (
        (ImageLayer.Points[1].X - ImageLayer.Points[0].X) *
          (ImageLayer.Points[3].Y - ImageLayer.Points[0].Y) -
        (ImageLayer.Points[1].Y - ImageLayer.Points[0].Y) *
          (ImageLayer.Points[3].X - ImageLayer.Points[0].X)) / EdgeWidth;
      if Abs(SignedHeight) <= 0 then
        Continue;
      RotationDegrees := RadToDeg(ArcTan2(
        ImageLayer.Points[1].Y - ImageLayer.Points[0].Y,
        ImageLayer.Points[1].X - ImageLayer.Points[0].X));
      ImagePaint.AlphaF := EnsureRange(ImageLayer.Opacity *
        OpacityMultiplier, 0.0, 1.0);
      Canvas.Save;
      try
        Canvas.Translate(ImageLayer.Points[0].X, ImageLayer.Points[0].Y);
        Canvas.Rotate(RotationDegrees);
        Canvas.Scale(EdgeWidth / RasterImage.Width,
          SignedHeight / RasterImage.Height);
        Canvas.DrawImage(RasterImage, 0, 0, TSkSamplingOptions.Medium,
          ImagePaint);
      finally
        Canvas.Restore;
      end;
      Continue;
    end;
    if (Layer is TMapRakuTextPathLayer) and
      (Layer <> InputTextLayer) then
    begin
      TextLayer := TMapRakuTextLayer(Layer);
      if TextLayer.Text = '' then
        Continue;
      Font := CreateMapRakuTextFont(TextLayer.FontFamily,
        TextLayer.FontSize, TextLayer.FontStyle);
      ApplyMapRakuPaintStyle(Paint, TextLayer, TextLayer.FillColor,
        TextLayer.Opacity * OpacityMultiplier);
      Paint.Style := TSkPaintStyle.Fill;
      DrawMapRakuTextOnPath(Canvas,
        TMapRakuTextPathLayer(Layer), Font, Paint);
      Continue;
    end;
    if Layer is TMapRakuTextLayer then
    begin
      TextLayer := TMapRakuTextLayer(Layer);
      if TextLayer.Text = '' then
        Continue;
      if TextLayer is TMapRakuTextPathLayer then
        IndividualLetterSpacingRatios := nil
      else
        IndividualLetterSpacingRatios :=
          TextLayer.IndividualLetterSpacingRatios;
      TextLayout := BuildMapRakuTextLayout(TextLayer.Text,
        TextLayer.FontFamily, TextLayer.FontSize, TextLayer.WrapWidth,
        TextLayer.FontStyle,
        IfThen(TextLayer is TMapRakuTextPathLayer, 0.0,
          TextLayer.LetterSpacingRatio),
        TextLayer.LineSpacingRatio, IndividualLetterSpacingRatios);
      if (TextLayout.Width <= 0) or (TextLayout.Height <= 0) then
        Continue;
      Font := CreateMapRakuTextFont(TextLayer.FontFamily,
        TextLayer.FontSize, TextLayer.FontStyle);
      if (Layer = InputTextLayer) and (InputTextOutlineColor <> clNone) then
        Paint.Color := VclColorToAlphaColor(clBlack,
          TextLayer.Opacity * OpacityMultiplier)
      else
        ApplyMapRakuPaintStyle(Paint, TextLayer, TextLayer.FillColor,
          TextLayer.Opacity * OpacityMultiplier);
      Paint.Style := TSkPaintStyle.Fill;
      TextDecorationPaint.Color := Paint.Color;
      TextDecorationPaint.StrokeWidth := Max(TextLayer.FontSize / 16, 1.0);
      if TextLayer is TMapRakuTextPathLayer then
      begin
        LetterSpacing := 0;
        TextRenderScaleX := 1.0;
        TextRenderScaleY := 1.0;
      end
      else
      begin
        LetterSpacing := TextLayer.FontSize * TextLayer.LetterSpacingRatio;
        TextRenderScaleX := TextLayer.Bounds.Width / TextLayout.Width;
        TextRenderScaleY := TextLayer.Bounds.Height / TextLayout.Height;
      end;
      if (Layer = InputTextLayer) and (InputTextOutlineColor <> clNone) then
      begin
        TextOutlinePaint.Color := VclColorToAlphaColor(
          InputTextOutlineColor, TextLayer.Opacity * OpacityMultiplier);
        TextOutlinePaint.StrokeWidth := 1.5 / Max(Min(
          Abs(ScaleX * TextRenderScaleX),
          Abs(ScaleY * TextRenderScaleY)), 0.01);
      end;
      Canvas.Save;
      try
        Canvas.Translate(TextLayer.Bounds.CenterPoint.X,
          TextLayer.Bounds.CenterPoint.Y);
        Canvas.Rotate(TextLayer.RotationDegrees);
        Canvas.Scale(IfThen(TextLayer.FlipHorizontal, -1.0, 1.0),
          IfThen(TextLayer.FlipVertical, -1.0, 1.0));
        Canvas.Translate(-TextLayer.Bounds.CenterPoint.X,
          -TextLayer.Bounds.CenterPoint.Y);
        Canvas.Translate(TextLayer.Bounds.Left, TextLayer.Bounds.Top);
        Canvas.Scale(TextRenderScaleX, TextRenderScaleY);
        if not ((Layer = InputTextLayer) and
          (InputTextOutlineColor <> clNone)) then
          ApplyMapRakuPaintStyleLocal(Paint, TextLayer,
            TextLayer.FillColor, TextLayer.Opacity * OpacityMultiplier,
            TRectF.Create(0.0, 0.0, TextLayout.Width,
              TextLayout.Height));
        for J := 0 to High(TextLayout.Lines) do
        begin
          TextWidth := MeasureMapRakuText(TextLayout.Lines[J], Font,
            LetterSpacing, TextLayer.FontSize,
            IndividualLetterSpacingRatios,
            TextLayout.LineGapOffsets[J]);
          case Ord(TextLayer.Alignment) mod 3 of
            1: TextX := (TextLayout.Width - TextWidth) * 0.5;
            2: TextX := TextLayout.Width - TextWidth;
          else
            TextX := 0;
          end;
          if (Layer = InputTextLayer) and
            (InputTextOutlineColor <> clNone) then
            DrawMapRakuTextLine(Canvas, TextLayout.Lines[J], Font,
              TextOutlinePaint, TextX,
              TextLayout.Ascent + J * TextLayout.LineHeight,
              LetterSpacing, TextLayer.FontSize,
              IndividualLetterSpacingRatios,
              TextLayout.LineGapOffsets[J]);
          DrawMapRakuTextLine(Canvas, TextLayout.Lines[J], Font, Paint,
            TextX, TextLayout.Ascent + J * TextLayout.LineHeight,
            LetterSpacing, TextLayer.FontSize,
            IndividualLetterSpacingRatios,
            TextLayout.LineGapOffsets[J]);
          if (TextWidth > 0) and (fsUnderline in TextLayer.FontStyle) then
            Canvas.DrawLine(TPointF.Create(TextX, TextLayout.Ascent +
              J * TextLayout.LineHeight + TextLayer.FontSize * 0.08),
              TPointF.Create(TextX + TextWidth, TextLayout.Ascent +
              J * TextLayout.LineHeight + TextLayer.FontSize * 0.08),
              TextDecorationPaint);
          if (TextWidth > 0) and (fsStrikeOut in TextLayer.FontStyle) then
            Canvas.DrawLine(TPointF.Create(TextX, TextLayout.Ascent +
              J * TextLayout.LineHeight - TextLayer.FontSize * 0.3),
              TPointF.Create(TextX + TextWidth, TextLayout.Ascent +
              J * TextLayout.LineHeight - TextLayer.FontSize * 0.3),
              TextDecorationPaint);
        end;
      finally
        Canvas.Restore;
      end;
      Continue;
    end;
    if Layer is TMapRakuShapeLayer then
    begin
      ShapeLayer := TMapRakuShapeLayer(Layer);
      Path := BuildMapRakuShapePath(ShapeLayer);
      Paint.AntiAlias := True;
      ApplyMapRakuPaintStyle(Paint, ShapeLayer, ShapeLayer.FillColor,
        ShapeLayer.Opacity * OpacityMultiplier);
      Canvas.DrawPath(Path, Paint);
      if ShapeLayer.StrokeWidth > 0 then
      begin
        StrokeWidth := Max(ShapeLayer.StrokeWidth, MinimumStrokeWidth);
        StrokePaint.AntiAlias := True;
        StrokePaint.Shader := nil;
        StrokePaint.Color := VclColorToAlphaColor(ShapeLayer.StrokeColor,
          ShapeLayer.Opacity * OpacityMultiplier);
        StrokePaint.StrokeWidth := StrokeWidth;
        DashIntervals := VectArtStrokeDashIntervals(ShapeLayer.StrokeStyle,
          StrokeWidth);
        if Length(DashIntervals) > 0 then
          StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0)
        else
          StrokePaint.PathEffect := nil;
        Canvas.DrawPath(Path, StrokePaint);
      end;
      Continue;
    end;
    if Layer is TMapRakuRectangleLineLayer then
    begin
      RectangleLine := TMapRakuRectangleLineLayer(Layer);
      if Layer is TMapRakuEllipseLineLayer then
      begin
        EllipseLine := TMapRakuEllipseLineLayer(Layer);
        Path := BuildMapRakuEllipseLinePath(EllipseLine);
      end
      else if Layer is TMapRakuRoundedRectangleLineLayer then
      begin
        RoundedRectangleLine := TMapRakuRoundedRectangleLineLayer(Layer);
        Path := BuildRoundedRectanglePath(RoundedRectangleLine.Bounds,
          RoundedRectangleLine.CornerRadii);
      end
      else
      begin
        RectangleLineCorners := RectangleCorners(RectangleLine.Bounds,
          RectangleLine.RotationDegrees);
        PathBuilder := TSkPathBuilder.Create;
        PathBuilder.MoveTo(RectangleLineCorners[0].X,
          RectangleLineCorners[0].Y);
        for J := 1 to High(RectangleLineCorners) do
          PathBuilder.LineTo(RectangleLineCorners[J].X,
            RectangleLineCorners[J].Y);
        PathBuilder.Close;
        Path := PathBuilder.Detach;
      end;
      StrokeWidth := Max(RectangleLine.StrokeWidth, MinimumStrokeWidth);
      if Layer is TMapRakuRoundedRectangleLineLayer then
        ApplyMapRakuPaintStyleLocal(StrokePaint, RectangleLine,
          RectangleLine.StrokeColor,
          RectangleLine.Opacity * OpacityMultiplier, RectangleLine.Bounds)
      else
        ApplyMapRakuPaintStyle(StrokePaint, RectangleLine,
          RectangleLine.StrokeColor,
          RectangleLine.Opacity * OpacityMultiplier);
      ApplyMapRakuStrokeGradient(StrokePaint, RectangleLine, Path,
        RectangleLine.Opacity * OpacityMultiplier, StrokeWidth);
      StrokePaint.StrokeWidth := StrokeWidth;
      StrokePaint.StrokeCap := TSkStrokeCap.Butt;
      DashIntervals := VectArtStrokeDashIntervals(RectangleLine.StrokeStyle,
        StrokeWidth);
      if Length(DashIntervals) > 0 then
        StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0)
      else
        StrokePaint.PathEffect := nil;
      if Layer is TMapRakuRoundedRectangleLineLayer then
      begin
        Canvas.Save;
        try
          Canvas.Rotate(RectangleLine.RotationDegrees,
            (RectangleLine.Bounds.Left + RectangleLine.Bounds.Right) * 0.5,
            (RectangleLine.Bounds.Top + RectangleLine.Bounds.Bottom) * 0.5);
          Canvas.DrawPath(Path, StrokePaint);
        finally
          Canvas.Restore;
        end;
      end
      else
        Canvas.DrawPath(Path, StrokePaint);
      Continue;
    end;
    if Layer is TMapRakuArcLayer then
    begin
      ArcLayer := TMapRakuArcLayer(Layer);
      Path := BuildMapRakuArcPath(ArcLayer);
      StrokeWidth := Max(ArcLayer.StrokeWidth, MinimumStrokeWidth);
      ApplyMapRakuPaintStyle(StrokePaint, ArcLayer, ArcLayer.StrokeColor,
        ArcLayer.Opacity * OpacityMultiplier);
      ApplyMapRakuStrokeGradient(StrokePaint, ArcLayer, Path,
        ArcLayer.Opacity * OpacityMultiplier, StrokeWidth);
      StrokePaint.StrokeWidth := StrokeWidth;
      DashIntervals := VectArtStrokeDashIntervals(ArcLayer.StrokeStyle,
        StrokeWidth);
      if Length(DashIntervals) > 0 then
        StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0)
      else
        StrokePaint.PathEffect := nil;
      case ArcLayer.LineCap of
        vlcRound: StrokePaint.StrokeCap := TSkStrokeCap.Round;
        vlcTriangle: StrokePaint.StrokeCap := TSkStrokeCap.Butt;
      else
        StrokePaint.StrokeCap := TSkStrokeCap.Square;
      end;
      Canvas.DrawPath(Path, StrokePaint);
      if ArcLayer.LineCap = vlcTriangle then
      begin
        ArcStartPoint := MapRakuEllipsePoint(ArcLayer.Bounds,
          ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees);
        ArcEndPoint := MapRakuArcEndPoint(ArcLayer.Bounds,
          ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees,
          ArcLayer.SweepAngleDegrees);
        ArcStartTangent := MapRakuEllipseTangent(ArcLayer.Bounds,
          ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees);
        ArcEndTangent := MapRakuEllipseTangent(ArcLayer.Bounds,
          ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees +
          ArcLayer.SweepAngleDegrees);
        Paint.Color := StrokePaint.Color;
        Paint.Shader := StrokePaint.Shader;
        Paint.Style := TSkPaintStyle.Fill;
        DrawTriangleLineCap(Canvas, ArcStartPoint,
          TPointF.Create(-ArcStartTangent.X, -ArcStartTangent.Y),
          StrokeWidth * 0.5, Paint);
        DrawTriangleLineCap(Canvas, ArcEndPoint, ArcEndTangent,
          StrokeWidth * 0.5, Paint);
      end;
      Continue;
    end;
    if Layer is TVectArtPathLayer then
    begin
      PathLayer := TVectArtPathLayer(Layer);
      Paint.AntiAlias := True;
      StrokePaint.AntiAlias := True;
      PathVertices := PathLayer.Vertices;
      if Length(PathVertices) < 2 then
        Continue;
      PathBuilder := TSkPathBuilder.Create;
      PathBuilder.MoveTo(PathVertices[0].Position);
      if PathLayer.Closed then
        PathSegmentCount := Length(PathVertices)
      else
        PathSegmentCount := Length(PathVertices) - 1;
      for J := 0 to PathSegmentCount - 1 do
        if PathVertices[J].OutgoingSegment = slskCubicBezier then
          PathBuilder.CubicTo(TPointF.Create(
            PathVertices[J].Position.X +
              PathVertices[J].OutgoingControl.X,
            PathVertices[J].Position.Y +
              PathVertices[J].OutgoingControl.Y),
            TPointF.Create(
              PathVertices[(J + 1) mod Length(PathVertices)].Position.X +
                PathVertices[(J + 1) mod Length(PathVertices)].IncomingControl.X,
              PathVertices[(J + 1) mod Length(PathVertices)].Position.Y +
                PathVertices[(J + 1) mod Length(PathVertices)].IncomingControl.Y),
            PathVertices[(J + 1) mod Length(PathVertices)].Position)
        else
          PathBuilder.LineTo(
            PathVertices[(J + 1) mod Length(PathVertices)].Position);
      if PathLayer.Closed then
        PathBuilder.Close;
      Path := PathBuilder.Detach;
      if Crossings <> nil then CanvasSettings := Crossings.CanvasSettings
      else CanvasSettings := nil;
      if DrawMapPath(Canvas, Path, PathLayer, CanvasSettings,
        PathLayer.Opacity * OpacityMultiplier, MapPass) then
        Continue;
      StrokeWidth := Max(PathLayer.StrokeWidth, MinimumStrokeWidth);
      ApplyMapRakuPaintStyle(StrokePaint, PathLayer,
        PathLayer.StrokeColor, PathLayer.Opacity * OpacityMultiplier);
      ApplyMapRakuStrokeGradient(StrokePaint, PathLayer, Path,
        PathLayer.Opacity * OpacityMultiplier, StrokeWidth);
      StrokePaint.StrokeWidth := StrokeWidth;
      WidthPoints := PathLayer.WidthPoints;
      VariableWidthPath := nil;
      if not PathLayer.Closed and
        (PathLayer.MifStrokeStyle = vssSolid) then
      begin
        if Length(WidthPoints) < 2 then
          WidthPoints := UniformMapRakuStrokeWidthPoints;
        VariableWidthPath := BuildMapRakuVariableWidthPath(Path,
          WidthPoints, StrokeWidth, PathLayer.LineCap, PathVertices);
      end;
      if VariableWidthPath <> nil then
      begin
        StrokePaint.PathEffect := nil;
        StrokePaint.Style := TSkPaintStyle.Fill;
        Canvas.DrawPath(VariableWidthPath, StrokePaint);
        StrokePaint.Style := TSkPaintStyle.Stroke;
        Continue;
      end;
      DashIntervals := VectArtStrokeDashIntervals(PathLayer.MifStrokeStyle,
        StrokeWidth);
      if Length(DashIntervals) > 0 then
        StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0)
      else
        StrokePaint.PathEffect := nil;
      case PathLayer.LineCap of
        vlcRound: StrokePaint.StrokeCap := TSkStrokeCap.Round;
        vlcTriangle: StrokePaint.StrokeCap := TSkStrokeCap.Butt;
      else
        StrokePaint.StrokeCap := TSkStrokeCap.Square;
      end;
      Canvas.DrawPath(Path, StrokePaint);
      if not PathLayer.Closed and (PathLayer.LineCap = vlcTriangle) then
      begin
        Paint.Color := StrokePaint.Color;
        Paint.Shader := StrokePaint.Shader;
        Paint.Style := TSkPaintStyle.Fill;
        DrawPathTriangleCaps(Canvas, PathVertices, StrokeWidth, Paint);
      end;
      Continue;
    end;
    if Layer is TMapRakuEllipseArcShapeLayer then
    begin
      EllipseArcShape := TMapRakuEllipseArcShapeLayer(Layer);
      Paint.AntiAlias := True;
      ApplyMapRakuPaintStyle(Paint, EllipseArcShape,
        EllipseArcShape.FillColor, EllipseArcShape.Opacity * OpacityMultiplier);
      Canvas.DrawPath(BuildMapRakuEllipseArcShapePath(EllipseArcShape),
        Paint);
      Continue;
    end;
    if Layer is TMapRakuEllipseLayer then
    begin
      EllipseLayer := TMapRakuEllipseLayer(Layer);
      Paint.AntiAlias := True;
      ApplyMapRakuPaintStyle(Paint, EllipseLayer, EllipseLayer.FillColor,
        EllipseLayer.Opacity * OpacityMultiplier);
      Canvas.DrawPath(BuildMapRakuEllipsePath(EllipseLayer), Paint);
      Continue;
    end;
    if Layer is TMapRakuRoundedRectangleLayer then
    begin
      RoundedRectangleLayer := TMapRakuRoundedRectangleLayer(Layer);
      Paint.AntiAlias := True;
      ApplyMapRakuPaintStyleLocal(Paint, RoundedRectangleLayer,
        RoundedRectangleLayer.FillColor,
        RoundedRectangleLayer.Opacity * OpacityMultiplier,
        RoundedRectangleLayer.Bounds);
      Canvas.Save;
      try
        Canvas.Rotate(RoundedRectangleLayer.RotationDegrees,
          (RoundedRectangleLayer.Bounds.Left +
            RoundedRectangleLayer.Bounds.Right) * 0.5,
          (RoundedRectangleLayer.Bounds.Top +
            RoundedRectangleLayer.Bounds.Bottom) * 0.5);
        Canvas.DrawPath(BuildRoundedRectanglePath(RoundedRectangleLayer.Bounds,
          RoundedRectangleLayer.CornerRadii), Paint);
      finally
        Canvas.Restore;
      end;
      Continue;
    end;
    if not (Layer is TVectArtRectangleLayer) then
      Continue;
    RectangleLayer := TVectArtRectangleLayer(Layer);
    Paint.AntiAlias := True;
    ApplyMapRakuPaintStyleLocal(Paint, RectangleLayer,
      RectangleLayer.FillColor, RectangleLayer.Opacity * OpacityMultiplier,
      RectangleLayer.Bounds);
    Canvas.Save;
    try
      Canvas.Rotate(RectangleLayer.RotationDegrees,
        (RectangleLayer.Bounds.Left + RectangleLayer.Bounds.Right) * 0.5,
        (RectangleLayer.Bounds.Top + RectangleLayer.Bounds.Bottom) * 0.5);
      Canvas.DrawRect(RectangleLayer.Bounds, Paint);
    finally
      Canvas.Restore;
    end;
    finally
      while FilterSaveCount > 0 do
      begin
        Canvas.Restore;
        Dec(FilterSaveCount);
      end;
      Canvas.Restore;
      if (Crossings<>nil) and (MapPass<>1) then
        Crossings.DrawMarks(Canvas,Layer,OpacityMultiplier);
      Canvas.Restore;
    end;
  end;
  finally Canvas.Restore; end;
  if Surface <> nil then Surface.Flush;
end;

procedure RenderVectArtLayerTree(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  const LogicalBounds: TRectF; MinimumStrokeWidth,
  OpacityMultiplier: Single;
  InputTextLayer: TMapRakuTextLayer;
  InputTextOutlineColor: TColor; Crossings: TMapCrossingRenderContext;
  const OutputCanvas: ISkCanvas);
var
  ChildBuffer: TVectArtRenderBuffer;
  GroupLayer: TMapRakuGroupLayer;
  I: Integer;
  Flat: TList<TVectArtLayer>;
  GroupPaint: ISkPaint;
  procedure Collect(L: TVectArtLayer);
  var K: Integer;
  begin
    if not L.Visible then Exit;
    if L is TMapRakuGroupLayer then
      for K := 0 to TMapRakuGroupLayer(L).ChildCount - 1 do Collect(TMapRakuGroupLayer(L)[K])
    else Flat.Add(L);
  end;
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  if not (Layer is TMapRakuGroupLayer) then
  begin
    RenderVectArtLayers([Layer], Target, Width, Height, LogicalBounds,
      MinimumStrokeWidth, OpacityMultiplier, InputTextLayer,
      InputTextOutlineColor,0,OutputCanvas,Crossings);
    Exit;
  end;

  Target.SetSize(Width, Height);
  Target.Clear;
  GroupLayer := TMapRakuGroupLayer(Layer);
  if OutputCanvas<>nil then begin
    GroupPaint:=TSkPaint.Create;
    GroupPaint.AlphaF:=Layer.Opacity*OpacityMultiplier;
    OutputCanvas.SaveLayer(GroupPaint);
  end;
  try
  if GroupLayer.MapSurface then
  begin
    Flat := TList<TVectArtLayer>.Create;
    ChildBuffer := TVectArtRenderBuffer.Create;
    try
      Collect(GroupLayer);
      RenderVectArtLayers(Flat.ToArray, Target, Width, Height, LogicalBounds, MinimumStrokeWidth, 1, nil, clNone, 1,OutputCanvas,Crossings);
      RenderVectArtLayers(Flat.ToArray, ChildBuffer, Width, Height, LogicalBounds, MinimumStrokeWidth, 1, nil, clNone, 2,OutputCanvas,Crossings);
      if OutputCanvas=nil then CompositeVectArtRgba(ChildBuffer, Target.Data, Width, Height);
      MultiplyMapRakuBufferOpacity(Target,Layer.Opacity*OpacityMultiplier);
    finally ChildBuffer.Free; Flat.Free; end;
    Exit;
  end;
  ChildBuffer := TVectArtRenderBuffer.Create;
  try
    for I := 0 to GroupLayer.ChildCount - 1 do
      if GroupLayer[I].Visible then
      begin
        RenderVectArtLayerTree(GroupLayer[I], ChildBuffer, Width, Height,
          LogicalBounds, MinimumStrokeWidth, 1.0, InputTextLayer,
          InputTextOutlineColor,Crossings,OutputCanvas);
        if OutputCanvas=nil then CompositeVectArtRgba(ChildBuffer, Target.Data, Width, Height);
      end;
  finally
    ChildBuffer.Free;
  end;
  ApplyMapRakuLayerFilters(Layer, Target,
    Width / LogicalBounds.Width, Height / LogicalBounds.Height);
  MultiplyMapRakuBufferOpacity(Target,
    Layer.Opacity * OpacityMultiplier);
  finally
    if OutputCanvas<>nil then OutputCanvas.Restore;
  end;
end;

procedure CompositeVectArtRgba(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height: Integer);
begin
  MapRakuRenderBuffer.CompositeVectArtRgba(Source,Destination,Width,Height);
end;

procedure CompositeVectArtRgbaOffset(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height, OffsetX, OffsetY: Integer);
begin
  MapRakuRenderBuffer.CompositeVectArtRgbaOffset(Source,Destination,Width,Height,OffsetX,OffsetY);
end;

procedure RenderMapLayersToCanvas(const Layers: TArray<TVectArtLayer>;
  const Canvas: ISkCanvas; Width, Height: Integer; Opacity: Single; MapPass: Integer);
var Buffer: TVectArtRenderBuffer;
begin
  Buffer := TVectArtRenderBuffer.Create;
  try
    RenderVectArtLayers(Layers, Buffer, Width, Height,
      TRectF.Create(-Width * 0.5, -Height * 0.5, Width * 0.5, Height * 0.5),
      0, Opacity, nil, clNone, MapPass, Canvas);
  finally Buffer.Free; end;
end;
end.
