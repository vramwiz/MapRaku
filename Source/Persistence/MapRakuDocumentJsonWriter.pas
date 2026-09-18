// Document JSONの書き込み処理を担当し、読み込み側の検証処理から分離する。
unit MapRakuDocumentJsonWriter;

interface

uses
  MapRakuDocument;

// 現行バージョンのDocumentを埋め込み用JSON文字列へ変換する。
function SerializeVectArtDocument(Document: TVectArtDocument): string;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.JSON, System.Math,
  System.SysUtils, System.Types, Vcl.Graphics, MapRakuFilters,
  MapRakuPaintStyles, MapRakuTextureJson, MapRakuPatternJson;

const
  DOCUMENT_FORMAT_VERSION = 1;
  DOCUMENT_COORDINATE_ORIGIN = 'center';

function TextAlignmentName(Value: TMapRakuTextAlignment): string;
const
  NAMES: array[TMapRakuTextAlignment] of string = ('topLeft',
    'topCenter', 'topRight', 'middleLeft', 'middleCenter', 'middleRight',
    'bottomLeft', 'bottomCenter', 'bottomRight');
begin
  Result := NAMES[Value];
end;

function TextTransformModeName(
  Value: TMapRakuTextTransformMode): string;
const
  NAMES: array[TMapRakuTextTransformMode] of string =
    ('uniformScale', 'frameFit');
begin
  Result := NAMES[Value];
end;

procedure AddLayerFilters(Layer: TVectArtLayer; LayerJson: TJSONObject);
var
  Blur: TMapRakuBlurFilter;
  Filter: TMapRakuFilter;
  FilterJson: TJSONObject;
  FiltersJson: TJSONArray;
  I: Integer;
  Outline: TMapRakuOutlineFilter;
  Shadow: TMapRakuShadowFilter;
  PaintJson: TJSONObject;
  PaintStyle: TMapRakuPaintStyle;
  Stop: TMapRakuGradientStop;
  StopJson: TJSONObject;
  StopsJson: TJSONArray;
  TransformJson: TJSONArray;
begin
  LayerJson.AddPair('id', Layer.PersistentId);
  if not Layer.Transform.IsIdentity then
  begin
    TransformJson := TJSONArray.Create;
    for I := 0 to 8 do TransformJson.Add(Layer.Transform.Values[I]);
    LayerJson.AddPair('transform', TransformJson);
  end;
  LayerJson.AddPair('flipHorizontal',
    TJSONBool.Create(Layer.FlipHorizontal));
  LayerJson.AddPair('flipVertical', TJSONBool.Create(Layer.FlipVertical));
  PaintStyle := Layer.PaintStyle;
  if PaintStyle.Kind = slpkPattern then
    LayerJson.AddPair('paint', WriteMapRakuPattern(PaintStyle.Pattern));
  if PaintStyle.Kind = slpkTexture then
    LayerJson.AddPair('paint', WriteMapRakuTexture(PaintStyle.Texture));
  if PaintStyle.Kind = slpkGradient then
  begin
    PaintJson := TJSONObject.Create;
    PaintJson.AddPair('type', SCREEN_LAYOUT_GRADIENT_KIND_NAMES[PaintStyle.GradientKind]);
    PaintJson.AddPair('startOpacity', TJSONNumber.Create(PaintStyle.GradientStartOpacity));
    PaintJson.AddPair('endOpacity', TJSONNumber.Create(PaintStyle.GradientEndOpacity));
    PaintJson.AddPair('aspect', TJSONNumber.Create(PaintStyle.GradientAspect));
    PaintJson.AddPair('startColor',
      TJSONNumber.Create(Integer(PaintStyle.GradientStartColor)));
    PaintJson.AddPair('endColor',
      TJSONNumber.Create(Integer(PaintStyle.GradientEndColor)));
    PaintJson.AddPair('startX', TJSONNumber.Create(PaintStyle.LinearStart.X));
    PaintJson.AddPair('startY', TJSONNumber.Create(PaintStyle.LinearStart.Y));
    PaintJson.AddPair('endX', TJSONNumber.Create(PaintStyle.LinearEnd.X));
    PaintJson.AddPair('endY', TJSONNumber.Create(PaintStyle.LinearEnd.Y));
    StopsJson := TJSONArray.Create;
    for Stop in PaintStyle.GetGradientStops do
    begin
      StopJson := TJSONObject.Create;
      StopJson.AddPair('id', TJSONNumber.Create(Stop.Id));
      StopJson.AddPair('offset', TJSONNumber.Create(Stop.Offset));
      StopJson.AddPair('color', TJSONNumber.Create(Integer(Stop.Color)));
      StopJson.AddPair('opacity', TJSONNumber.Create(Stop.Opacity));
      StopsJson.AddElement(StopJson);
    end;
    PaintJson.AddPair('stops', StopsJson);
    LayerJson.AddPair('paint', PaintJson);
  end;
  FiltersJson := TJSONArray.Create;
  LayerJson.AddPair('filters', FiltersJson);
  for I := 0 to Layer.FilterCount - 1 do
  begin
    Filter := Layer.Filters[I];
    FilterJson := TJSONObject.Create;
    FilterJson.AddPair('enabled', TJSONBool.Create(Filter.Enabled));
    case Filter.Kind of
      slfkOutline:
      begin
        Outline := TMapRakuOutlineFilter(Filter);
        FilterJson.AddPair('type', 'outline');
        FilterJson.AddPair('color',
          TJSONNumber.Create(Integer(Outline.Color)));
        FilterJson.AddPair('width', TJSONNumber.Create(Outline.Width));
      end;
      slfkShadow:
      begin
        Shadow := TMapRakuShadowFilter(Filter);
        FilterJson.AddPair('type', 'shadow');
        FilterJson.AddPair('color',
          TJSONNumber.Create(Integer(Shadow.Color)));
        FilterJson.AddPair('offsetX', TJSONNumber.Create(Shadow.OffsetX));
        FilterJson.AddPair('offsetY', TJSONNumber.Create(Shadow.OffsetY));
        FilterJson.AddPair('blurRadius',
          TJSONNumber.Create(Shadow.BlurRadius));
        FilterJson.AddPair('opacity', TJSONNumber.Create(Shadow.Opacity));
      end;
      slfkBlur:
      begin
        Blur := TMapRakuBlurFilter(Filter);
        FilterJson.AddPair('type', 'blur');
        FilterJson.AddPair('radius', TJSONNumber.Create(Blur.Radius));
      end;
    end;
    FiltersJson.AddElement(FilterJson);
  end;
end;

function TextPathAttachmentName(
  Value: TMapRakuTextPathAttachment): string;
const
  NAMES: array[TMapRakuTextPathAttachment] of string =
    ('bottom', 'top', 'left', 'right');
begin
  Result := NAMES[Value];
end;

procedure AddPathVertices(const Vertices: TArray<TMapRakuVertex>;
  LayerJson: TJSONObject);
var
  I: Integer;
  VertexJson: TJSONObject;
  VerticesJson: TJSONArray;
begin
  VerticesJson := TJSONArray.Create;
  for I := 0 to High(Vertices) do
  begin
    VertexJson := TJSONObject.Create;
    with Vertices[I] do
    begin
      VertexJson.AddPair('x', TJSONNumber.Create(Position.X));
      VertexJson.AddPair('y', TJSONNumber.Create(Position.Y));
      VertexJson.AddPair('incomingX',
        TJSONNumber.Create(IncomingControl.X));
      VertexJson.AddPair('incomingY',
        TJSONNumber.Create(IncomingControl.Y));
      VertexJson.AddPair('outgoingX',
        TJSONNumber.Create(OutgoingControl.X));
      VertexJson.AddPair('outgoingY',
        TJSONNumber.Create(OutgoingControl.Y));
      if Kind = slvkBezier then
        VertexJson.AddPair('kind', 'bezier')
      else
        VertexJson.AddPair('kind', 'sharp');
      if OutgoingSegment = slskCubicBezier then
        VertexJson.AddPair('outgoingSegment', 'cubicBezier')
      else
        VertexJson.AddPair('outgoingSegment', 'line');
    end;
    VerticesJson.AddElement(VertexJson);
  end;
  LayerJson.AddPair('vertices', VerticesJson);
end;

function SerializeVectArtDocument(Document: TVectArtDocument): string;
var
  Arc: TMapRakuArcLayer;
  ArcJson: TJSONObject;
  ArcShape: TMapRakuEllipseArcShapeLayer;
  ArcShapeJson: TJSONObject;
  Canvas: TVectArtCanvasLayer;
  CanvasJson: TJSONObject;
  ContourIndex: Integer;
  ContourJson: TJSONObject;
  ContoursJson: TJSONArray;
  Crossing: TMapRakuCrossingRelation;
  CrossingJson: TJSONObject;
  CrossingsJson: TJSONArray;
  Ellipse: TMapRakuEllipseLayer;
  EllipseJson: TJSONObject;
  EllipseLine: TMapRakuEllipseLineLayer;
  EllipseLineJson: TJSONObject;
  Group: TMapRakuGroupLayer;
  GroupJson: TJSONObject;
  GroupLayersJson: TJSONArray;
  ChildIndex: Integer;
  ChildLayer: TVectArtLayer;
  ChildInTemporaryDocument: Boolean;
  CharacterPathOffsetIndex: Integer;
  CharacterPathOffsets: TArray<Single>;
  CharacterPathOffsetsJson: TJSONArray;
  CharacterPositionManual: TArray<Boolean>;
  CharacterPositionManualIndex: Integer;
  CharacterPositionManualJson: TJSONArray;
  CharacterScaleIndex: Integer;
  CharacterScales: TArray<Single>;
  CharacterScalesJson: TJSONArray;
  I: Integer;
  Image: TVectArtImageLayer;
  ImageJson: TJSONObject;
  IndividualLetterSpacingIndex: Integer;
  IndividualLetterSpacingJson: TJSONArray;
  IndividualLetterSpacingRatios: TArray<Single>;
  Layer: TVectArtLayer;
  LayersJson: TJSONArray;
  Path: TVectArtPathLayer;
  PathJson: TJSONObject;
  PointIndex: Integer;
  PointJson: TJSONObject;
  PointsJson: TJSONArray;
  Rectangle: TVectArtRectangleLayer;
  RectangleJson: TJSONObject;
  RectangleLine: TMapRakuRectangleLineLayer;
  RectangleLineJson: TJSONObject;
  RoundedRectangle: TMapRakuRoundedRectangleLayer;
  RoundedRectangleJson: TJSONObject;
  RoundedRectangleLine: TMapRakuRoundedRectangleLineLayer;
  RoundedRectangleLineJson: TJSONObject;
  Root: TJSONObject;
  SerializedSelectedIndex: Integer;
  Shape: TMapRakuShapeLayer;
  ShapeContours: TArray<TMapRakuContour>;
  ShapeJson: TJSONObject;
  TextLayer: TMapRakuTextLayer;
  TextJson: TJSONObject;
  TemporaryDocument: TVectArtDocument;
  TemporaryJson: TJSONValue;
  TemporaryLayers: TJSONArray;
  TemporaryRoot: TJSONObject;
  TemporaryText: string;
  VertexIndex: Integer;
  VertexJson: TJSONObject;
  VerticesJson: TJSONArray;
  WidthPointIndex: Integer;
  WidthPointJson: TJSONObject;
  WidthPoints: TArray<TMapRakuStrokeWidthPoint>;
  WidthPointsJson: TJSONArray;
begin
  if Document = nil then
    raise EArgumentNilException.Create('Document');
  Canvas := Document.CanvasLayer;
  if Canvas = nil then
    raise EInvalidOp.Create('Document canvas is missing');

  Root := TJSONObject.Create;
  try
    SerializedSelectedIndex := -1;
    Root.AddPair('appId', 'MapRaku');
    Root.AddPair('version', TJSONNumber.Create(DOCUMENT_FORMAT_VERSION));
    CanvasJson := TJSONObject.Create;
    CanvasJson.AddPair('width', TJSONNumber.Create(Canvas.Width));
    CanvasJson.AddPair('height', TJSONNumber.Create(Canvas.Height));
    CanvasJson.AddPair('origin', DOCUMENT_COORDINATE_ORIGIN);
    CanvasJson.AddPair('backgroundColor',
      TJSONNumber.Create(Integer(Canvas.BackgroundColor)));
    CanvasJson.AddPair('transparent', TJSONBool.Create(Canvas.Transparent));
    CanvasJson.AddPair('roadPresetColor',
      TJSONNumber.Create(Integer(Canvas.RoadPresetColor)));
    CanvasJson.AddPair('riverPresetColor',
      TJSONNumber.Create(Integer(Canvas.RiverPresetColor)));
    CanvasJson.AddPair('routePresetColor',
      TJSONNumber.Create(Integer(Canvas.RoutePresetColor)));
    CanvasJson.AddPair('jrPrimaryColor',
      TJSONNumber.Create(Integer(Canvas.JrPrimaryColor)));
    CanvasJson.AddPair('jrSecondaryColor',
      TJSONNumber.Create(Integer(Canvas.JrSecondaryColor)));
    CanvasJson.AddPair('railPrimaryColor',
      TJSONNumber.Create(Integer(Canvas.RailPrimaryColor)));
    CanvasJson.AddPair('railSecondaryColor',
      TJSONNumber.Create(Integer(Canvas.RailSecondaryColor)));
    Root.AddPair('canvas', CanvasJson);

    LayersJson := TJSONArray.Create;
    Root.AddPair('layers', LayersJson);
    for I := 1 to Document.LayerCount - 1 do
    begin
      Layer := Document.Layers[I];
      if Layer is TMapRakuLevelBoundaryLayer then
      begin
        GroupJson := TJSONObject.Create;
        GroupJson.AddPair('type', 'mapLevelBoundary');
        GroupJson.AddPair('name', Layer.Name);
        GroupJson.AddPair('visible', TJSONBool.Create(Layer.Visible));
        GroupJson.AddPair('locked', TJSONBool.Create(Layer.Locked));
        AddLayerFilters(Layer, GroupJson);
        LayersJson.AddElement(GroupJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuGroupLayer then
      begin
        Group := TMapRakuGroupLayer(Layer);
        GroupJson := TJSONObject.Create;
        GroupJson.AddPair('type', 'group');
        GroupJson.AddPair('name', Group.Name);
        GroupJson.AddPair('mapSymbol', TJSONBool.Create(Group.MapSymbol));
        if Group.RouteMarkerKind<>'' then
          GroupJson.AddPair('routeMarkerKind', Group.RouteMarkerKind);
        if Group.RoutePathId<>'' then
          GroupJson.AddPair('routePathId', Group.RoutePathId);
        if Group.HasRouteMarkerPosition then begin
          GroupJson.AddPair('routeMarkerX',TJSONNumber.Create(Group.RouteMarkerPosition.X));
          GroupJson.AddPair('routeMarkerY',TJSONNumber.Create(Group.RouteMarkerPosition.Y));
        end;
        GroupJson.AddPair('mapSurface', TJSONBool.Create(Group.MapSurface));
        GroupJson.AddPair('opacity', TJSONNumber.Create(Group.Opacity));
        GroupJson.AddPair('visible', TJSONBool.Create(Group.Visible));
        GroupJson.AddPair('locked', TJSONBool.Create(Group.Locked));
        AddLayerFilters(Group, GroupJson);
        GroupLayersJson := TJSONArray.Create;
        GroupJson.AddPair('layers', GroupLayersJson);
        for ChildIndex := 0 to Group.ChildCount - 1 do
        begin
          ChildLayer := Group.ExtractChild(ChildIndex);
          TemporaryDocument := TVectArtDocument.Create;
          ChildInTemporaryDocument := False;
          try
            TemporaryDocument.InsertLayer(1, ChildLayer);
            ChildInTemporaryDocument := True;
            TemporaryText := SerializeVectArtDocument(TemporaryDocument);
            TemporaryJson := TJSONObject.ParseJSONValue(TemporaryText);
            try
              if not (TemporaryJson is TJSONObject) then
                raise EConvertError.Create('Cannot serialize group child');
              TemporaryRoot := TJSONObject(TemporaryJson);
              TemporaryLayers := TemporaryRoot.GetValue<TJSONArray>('layers');
              if (TemporaryLayers <> nil) and
                (TemporaryLayers.Count = 1) then
                GroupLayersJson.AddElement(TJSONObject.ParseJSONValue(
                  TemporaryLayers.Items[0].ToJSON));
            finally
              TemporaryJson.Free;
            end;
          finally
            if ChildInTemporaryDocument then
              ChildLayer := TemporaryDocument.ExtractLayer(1);
            TemporaryDocument.Free;
            Group.InsertChild(ChildIndex, ChildLayer);
          end;
        end;
        LayersJson.AddElement(GroupJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuTextLayer then
      begin
        TextLayer := TMapRakuTextLayer(Layer);
        TextJson := TJSONObject.Create;
        if Layer is TMapRakuTextPathLayer then
          TextJson.AddPair('type', 'textPath')
        else
          TextJson.AddPair('type', 'text');
        TextJson.AddPair('name', TextLayer.Name);
        TextJson.AddPair('text', TextLayer.Text);
        TextJson.AddPair('fontFamily', TextLayer.FontFamily);
        TextJson.AddPair('fontSize', TJSONNumber.Create(TextLayer.FontSize));
        if Layer is TMapRakuTextPathLayer then
        begin
          TextJson.AddPair('pathAttachment', TextPathAttachmentName(
            TMapRakuTextPathLayer(Layer).Attachment));
          CharacterPathOffsetsJson := TJSONArray.Create;
          CharacterPathOffsets :=
            TMapRakuTextPathLayer(Layer).CharacterPathOffsets;
          for CharacterPathOffsetIndex := 0 to
            High(CharacterPathOffsets) do
            CharacterPathOffsetsJson.Add(
              CharacterPathOffsets[CharacterPathOffsetIndex]);
          TextJson.AddPair('characterPathOffsets',
            CharacterPathOffsetsJson);
          CharacterPositionManualJson := TJSONArray.Create;
          CharacterPositionManual :=
            TMapRakuTextPathLayer(Layer).CharacterPositionManual;
          for CharacterPositionManualIndex := 0 to
            High(CharacterPositionManual) do
            CharacterPositionManualJson.Add(
              CharacterPositionManual[CharacterPositionManualIndex]);
          TextJson.AddPair('characterPositionManual',
            CharacterPositionManualJson);
          CharacterScalesJson := TJSONArray.Create;
          CharacterScales :=
            TMapRakuTextPathLayer(Layer).CharacterScales;
          for CharacterScaleIndex := 0 to High(CharacterScales) do
            CharacterScalesJson.Add(CharacterScales[CharacterScaleIndex]);
          TextJson.AddPair('characterScales', CharacterScalesJson);
        end;
        TextJson.AddPair('alignment',
          TextAlignmentName(TextLayer.Alignment));
        TextJson.AddPair('bold',
          TJSONBool.Create(fsBold in TextLayer.FontStyle));
        TextJson.AddPair('italic',
          TJSONBool.Create(fsItalic in TextLayer.FontStyle));
        TextJson.AddPair('underline',
          TJSONBool.Create(fsUnderline in TextLayer.FontStyle));
        TextJson.AddPair('strikeOut',
          TJSONBool.Create(fsStrikeOut in TextLayer.FontStyle));
        TextJson.AddPair('letterSpacingRatio',
          TJSONNumber.Create(TextLayer.LetterSpacingRatio));
        IndividualLetterSpacingJson := TJSONArray.Create;
        IndividualLetterSpacingRatios :=
          TextLayer.IndividualLetterSpacingRatios;
        for IndividualLetterSpacingIndex := 0 to
          High(IndividualLetterSpacingRatios) do
          IndividualLetterSpacingJson.Add(
            IndividualLetterSpacingRatios[IndividualLetterSpacingIndex]);
        TextJson.AddPair('individualLetterSpacingRatios',
          IndividualLetterSpacingJson);
        TextJson.AddPair('lineSpacingRatio',
          TJSONNumber.Create(TextLayer.LineSpacingRatio));
        TextJson.AddPair('transformMode',
          TextTransformModeName(TextLayer.TransformMode));
        TextJson.AddPair('wrapWidth', TJSONNumber.Create(TextLayer.WrapWidth));
        TextJson.AddPair('left', TJSONNumber.Create(TextLayer.Bounds.Left));
        TextJson.AddPair('top', TJSONNumber.Create(TextLayer.Bounds.Top));
        TextJson.AddPair('right', TJSONNumber.Create(TextLayer.Bounds.Right));
        TextJson.AddPair('bottom', TJSONNumber.Create(TextLayer.Bounds.Bottom));
        TextJson.AddPair('rotation',
          TJSONNumber.Create(TextLayer.RotationDegrees));
        TextJson.AddPair('textColor',
          TJSONNumber.Create(Integer(TextLayer.FillColor)));
        TextJson.AddPair('opacity', TJSONNumber.Create(TextLayer.Opacity));
        TextJson.AddPair('visible', TJSONBool.Create(TextLayer.Visible));
        TextJson.AddPair('locked', TJSONBool.Create(TextLayer.Locked));
        AddLayerFilters(TextLayer, TextJson);
        if Layer is TMapRakuTextPathLayer then
          AddPathVertices(
            TMapRakuTextPathLayer(Layer).EditablePathVertices,
            TextJson);
        LayersJson.AddElement(TextJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TVectArtImageLayer then
      begin
        Image := TVectArtImageLayer(Layer);
        if Image.SourceFileName = '' then
          Continue;
        ImageJson := TJSONObject.Create;
        ImageJson.AddPair('type', 'image');
        ImageJson.AddPair('name', Image.Name);
        if Image.SourceKind = visLogo then
          ImageJson.AddPair('sourceKind', 'logo')
        else
          ImageJson.AddPair('sourceKind', 'image');
        ImageJson.AddPair('sourceFile', Image.SourceFileName);
        ImageJson.AddPair('opacity', TJSONNumber.Create(Image.Opacity));
        ImageJson.AddPair('visible', TJSONBool.Create(Image.Visible));
        ImageJson.AddPair('locked', TJSONBool.Create(Image.Locked));
        AddLayerFilters(Image, ImageJson);
        PointsJson := TJSONArray.Create;
        for PointIndex := 0 to High(Image.Points) do
        begin
          PointJson := TJSONObject.Create;
          PointJson.AddPair('x', TJSONNumber.Create(
            Image.Points[PointIndex].X));
          PointJson.AddPair('y', TJSONNumber.Create(
            Image.Points[PointIndex].Y));
          PointsJson.AddElement(PointJson);
        end;
        ImageJson.AddPair('points', PointsJson);
        LayersJson.AddElement(ImageJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TVectArtPathLayer then
      begin
        Path := TVectArtPathLayer(Layer);
        PathJson := TJSONObject.Create;
        PathJson.AddPair('type', 'path');
        PathJson.AddPair('name', Path.Name);
        PathJson.AddPair('mapElement', Path.MapElement);
        if Path.RouteId<>'' then
          PathJson.AddPair('routeId', Path.RouteId);
        PathJson.AddPair('mapColorOverride',
          TJSONBool.Create(Path.MapColorOverride));
        PathJson.AddPair('mapStepCount',TJSONNumber.Create(Path.MapStepCount));
        PathJson.AddPair('closed', TJSONBool.Create(Path.Closed));
        PathJson.AddPair('opacity', TJSONNumber.Create(Path.Opacity));
        PathJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(Path.StrokeColor)));
        PathJson.AddPair('strokeWidth', TJSONNumber.Create(Path.StrokeWidth));
        PathJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(Path.MifStrokeStyle)));
        PathJson.AddPair('lineCap', TJSONNumber.Create(Ord(Path.LineCap)));
        PathJson.AddPair('visible', TJSONBool.Create(Path.Visible));
        PathJson.AddPair('locked', TJSONBool.Create(Path.Locked));
        AddLayerFilters(Path, PathJson);
        AddPathVertices(Path.Vertices, PathJson);
        WidthPoints := Path.WidthPoints;
        if Length(WidthPoints) > 0 then
        begin
          WidthPointsJson := TJSONArray.Create;
          for WidthPointIndex := 0 to High(WidthPoints) do
          begin
            WidthPointJson := TJSONObject.Create;
            WidthPointJson.AddPair('offset',
              TJSONNumber.Create(WidthPoints[WidthPointIndex].Offset));
            WidthPointJson.AddPair('leftScale',
              TJSONNumber.Create(WidthPoints[WidthPointIndex].LeftScale));
            WidthPointJson.AddPair('rightScale',
              TJSONNumber.Create(WidthPoints[WidthPointIndex].RightScale));
            WidthPointsJson.AddElement(WidthPointJson);
          end;
          PathJson.AddPair('widthPoints', WidthPointsJson);
        end;
        LayersJson.AddElement(PathJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuShapeLayer then
      begin
        Shape := TMapRakuShapeLayer(Layer);
        ShapeJson := TJSONObject.Create;
        ShapeJson.AddPair('type', 'shape');
        ShapeJson.AddPair('name', Shape.Name);
        ShapeJson.AddPair('opacity', TJSONNumber.Create(Shape.Opacity));
        ShapeJson.AddPair('fillColor',
          TJSONNumber.Create(Integer(Shape.FillColor)));
        ShapeJson.AddPair('fillRule',
          TJSONNumber.Create(Ord(Shape.FillRule)));
        ShapeJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(Shape.StrokeColor)));
        ShapeJson.AddPair('strokeWidth',
          TJSONNumber.Create(Shape.StrokeWidth));
        ShapeJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(Shape.StrokeStyle)));
        ShapeJson.AddPair('visible', TJSONBool.Create(Shape.Visible));
        ShapeJson.AddPair('locked', TJSONBool.Create(Shape.Locked));
        AddLayerFilters(Shape, ShapeJson);
        ContoursJson := TJSONArray.Create;
        ShapeContours := Shape.Contours;
        for ContourIndex := 0 to High(ShapeContours) do
        begin
          ContourJson := TJSONObject.Create;
          VerticesJson := TJSONArray.Create;
          for VertexIndex := 0 to
            High(ShapeContours[ContourIndex].Vertices) do
          begin
            VertexJson := TJSONObject.Create;
            with ShapeContours[ContourIndex].Vertices[VertexIndex] do
            begin
              VertexJson.AddPair('x', TJSONNumber.Create(Position.X));
              VertexJson.AddPair('y', TJSONNumber.Create(Position.Y));
              VertexJson.AddPair('incomingX',
                TJSONNumber.Create(IncomingControl.X));
              VertexJson.AddPair('incomingY',
                TJSONNumber.Create(IncomingControl.Y));
              VertexJson.AddPair('outgoingX',
                TJSONNumber.Create(OutgoingControl.X));
              VertexJson.AddPair('outgoingY',
                TJSONNumber.Create(OutgoingControl.Y));
              if Kind = slvkBezier then
                VertexJson.AddPair('kind', 'bezier')
              else
                VertexJson.AddPair('kind', 'sharp');
              if OutgoingSegment = slskCubicBezier then
                VertexJson.AddPair('outgoingSegment', 'cubicBezier')
              else
                VertexJson.AddPair('outgoingSegment', 'line');
            end;
            VerticesJson.AddElement(VertexJson);
          end;
          ContourJson.AddPair('vertices', VerticesJson);
          ContoursJson.AddElement(ContourJson);
        end;
        ShapeJson.AddPair('contours', ContoursJson);
        LayersJson.AddElement(ShapeJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuEllipseArcShapeLayer then
      begin
        ArcShape := TMapRakuEllipseArcShapeLayer(Layer);
        ArcShapeJson := TJSONObject.Create;
        ArcShapeJson.AddPair('type', 'ellipseArcShape');
        ArcShapeJson.AddPair('name', ArcShape.Name);
        ArcShapeJson.AddPair('left', TJSONNumber.Create(ArcShape.Bounds.Left));
        ArcShapeJson.AddPair('top', TJSONNumber.Create(ArcShape.Bounds.Top));
        ArcShapeJson.AddPair('right',
          TJSONNumber.Create(ArcShape.Bounds.Right));
        ArcShapeJson.AddPair('bottom',
          TJSONNumber.Create(ArcShape.Bounds.Bottom));
        ArcShapeJson.AddPair('rotation',
          TJSONNumber.Create(ArcShape.RotationDegrees));
        ArcShapeJson.AddPair('startAngle',
          TJSONNumber.Create(ArcShape.StartAngleDegrees));
        ArcShapeJson.AddPair('sweepAngle',
          TJSONNumber.Create(ArcShape.SweepAngleDegrees));
        ArcShapeJson.AddPair('fillColor',
          TJSONNumber.Create(Integer(ArcShape.FillColor)));
        ArcShapeJson.AddPair('opacity', TJSONNumber.Create(ArcShape.Opacity));
        ArcShapeJson.AddPair('visible', TJSONBool.Create(ArcShape.Visible));
        ArcShapeJson.AddPair('locked', TJSONBool.Create(ArcShape.Locked));
        AddLayerFilters(ArcShape, ArcShapeJson);
        LayersJson.AddElement(ArcShapeJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuEllipseLineLayer then
      begin
        EllipseLine := TMapRakuEllipseLineLayer(Layer);
        EllipseLineJson := TJSONObject.Create;
        EllipseLineJson.AddPair('type', 'ellipseLine');
        EllipseLineJson.AddPair('name', EllipseLine.Name);
        EllipseLineJson.AddPair('left',
          TJSONNumber.Create(EllipseLine.Bounds.Left));
        EllipseLineJson.AddPair('top',
          TJSONNumber.Create(EllipseLine.Bounds.Top));
        EllipseLineJson.AddPair('right',
          TJSONNumber.Create(EllipseLine.Bounds.Right));
        EllipseLineJson.AddPair('bottom',
          TJSONNumber.Create(EllipseLine.Bounds.Bottom));
        EllipseLineJson.AddPair('rotation',
          TJSONNumber.Create(EllipseLine.RotationDegrees));
        EllipseLineJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(EllipseLine.StrokeColor)));
        EllipseLineJson.AddPair('strokeWidth',
          TJSONNumber.Create(EllipseLine.StrokeWidth));
        EllipseLineJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(EllipseLine.StrokeStyle)));
        EllipseLineJson.AddPair('opacity',
          TJSONNumber.Create(EllipseLine.Opacity));
        EllipseLineJson.AddPair('visible',
          TJSONBool.Create(EllipseLine.Visible));
        EllipseLineJson.AddPair('locked',
          TJSONBool.Create(EllipseLine.Locked));
        AddLayerFilters(EllipseLine, EllipseLineJson);
        LayersJson.AddElement(EllipseLineJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuRoundedRectangleLineLayer then
      begin
        RoundedRectangleLine := TMapRakuRoundedRectangleLineLayer(Layer);
        RoundedRectangleLineJson := TJSONObject.Create;
        RoundedRectangleLineJson.AddPair('type', 'roundedRectangleLine');
        RoundedRectangleLineJson.AddPair('name', RoundedRectangleLine.Name);
        RoundedRectangleLineJson.AddPair('left',
          TJSONNumber.Create(RoundedRectangleLine.Bounds.Left));
        RoundedRectangleLineJson.AddPair('top',
          TJSONNumber.Create(RoundedRectangleLine.Bounds.Top));
        RoundedRectangleLineJson.AddPair('right',
          TJSONNumber.Create(RoundedRectangleLine.Bounds.Right));
        RoundedRectangleLineJson.AddPair('bottom',
          TJSONNumber.Create(RoundedRectangleLine.Bounds.Bottom));
        RoundedRectangleLineJson.AddPair('rotation',
          TJSONNumber.Create(RoundedRectangleLine.RotationDegrees));
        RoundedRectangleLineJson.AddPair('topLeftRadius',
          TJSONNumber.Create(RoundedRectangleLine.CornerRadii.TopLeft));
        RoundedRectangleLineJson.AddPair('topRightRadius',
          TJSONNumber.Create(RoundedRectangleLine.CornerRadii.TopRight));
        RoundedRectangleLineJson.AddPair('bottomRightRadius',
          TJSONNumber.Create(RoundedRectangleLine.CornerRadii.BottomRight));
        RoundedRectangleLineJson.AddPair('bottomLeftRadius',
          TJSONNumber.Create(RoundedRectangleLine.CornerRadii.BottomLeft));
        RoundedRectangleLineJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(RoundedRectangleLine.StrokeColor)));
        RoundedRectangleLineJson.AddPair('strokeWidth',
          TJSONNumber.Create(RoundedRectangleLine.StrokeWidth));
        RoundedRectangleLineJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(RoundedRectangleLine.StrokeStyle)));
        RoundedRectangleLineJson.AddPair('opacity',
          TJSONNumber.Create(RoundedRectangleLine.Opacity));
        RoundedRectangleLineJson.AddPair('visible',
          TJSONBool.Create(RoundedRectangleLine.Visible));
        RoundedRectangleLineJson.AddPair('locked',
          TJSONBool.Create(RoundedRectangleLine.Locked));
        AddLayerFilters(RoundedRectangleLine, RoundedRectangleLineJson);
        LayersJson.AddElement(RoundedRectangleLineJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuRectangleLineLayer then
      begin
        RectangleLine := TMapRakuRectangleLineLayer(Layer);
        RectangleLineJson := TJSONObject.Create;
        RectangleLineJson.AddPair('type', 'rectangleLine');
        RectangleLineJson.AddPair('name', RectangleLine.Name);
        RectangleLineJson.AddPair('left',
          TJSONNumber.Create(RectangleLine.Bounds.Left));
        RectangleLineJson.AddPair('top',
          TJSONNumber.Create(RectangleLine.Bounds.Top));
        RectangleLineJson.AddPair('right',
          TJSONNumber.Create(RectangleLine.Bounds.Right));
        RectangleLineJson.AddPair('bottom',
          TJSONNumber.Create(RectangleLine.Bounds.Bottom));
        RectangleLineJson.AddPair('rotation',
          TJSONNumber.Create(RectangleLine.RotationDegrees));
        RectangleLineJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(RectangleLine.StrokeColor)));
        RectangleLineJson.AddPair('strokeWidth',
          TJSONNumber.Create(RectangleLine.StrokeWidth));
        RectangleLineJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(RectangleLine.StrokeStyle)));
        RectangleLineJson.AddPair('opacity',
          TJSONNumber.Create(RectangleLine.Opacity));
        RectangleLineJson.AddPair('visible',
          TJSONBool.Create(RectangleLine.Visible));
        RectangleLineJson.AddPair('locked',
          TJSONBool.Create(RectangleLine.Locked));
        AddLayerFilters(RectangleLine, RectangleLineJson);
        LayersJson.AddElement(RectangleLineJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuArcLayer then
      begin
        Arc := TMapRakuArcLayer(Layer);
        ArcJson := TJSONObject.Create;
        ArcJson.AddPair('type', 'arc');
        ArcJson.AddPair('name', Arc.Name);
        ArcJson.AddPair('left', TJSONNumber.Create(Arc.Bounds.Left));
        ArcJson.AddPair('top', TJSONNumber.Create(Arc.Bounds.Top));
        ArcJson.AddPair('right', TJSONNumber.Create(Arc.Bounds.Right));
        ArcJson.AddPair('bottom', TJSONNumber.Create(Arc.Bounds.Bottom));
        ArcJson.AddPair('rotation',
          TJSONNumber.Create(Arc.RotationDegrees));
        ArcJson.AddPair('startAngle',
          TJSONNumber.Create(Arc.StartAngleDegrees));
        ArcJson.AddPair('sweepAngle',
          TJSONNumber.Create(Arc.SweepAngleDegrees));
        ArcJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(Arc.StrokeColor)));
        ArcJson.AddPair('strokeWidth',
          TJSONNumber.Create(Arc.StrokeWidth));
        ArcJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(Arc.StrokeStyle)));
        ArcJson.AddPair('lineCap', TJSONNumber.Create(Ord(Arc.LineCap)));
        ArcJson.AddPair('opacity', TJSONNumber.Create(Arc.Opacity));
        ArcJson.AddPair('visible', TJSONBool.Create(Arc.Visible));
        ArcJson.AddPair('locked', TJSONBool.Create(Arc.Locked));
        AddLayerFilters(Arc, ArcJson);
        LayersJson.AddElement(ArcJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuEllipseLayer then
      begin
        Ellipse := TMapRakuEllipseLayer(Layer);
        EllipseJson := TJSONObject.Create;
        EllipseJson.AddPair('type', 'ellipse');
        EllipseJson.AddPair('name', Ellipse.Name);
        EllipseJson.AddPair('left',
          TJSONNumber.Create(Ellipse.Bounds.Left));
        EllipseJson.AddPair('top',
          TJSONNumber.Create(Ellipse.Bounds.Top));
        EllipseJson.AddPair('right',
          TJSONNumber.Create(Ellipse.Bounds.Right));
        EllipseJson.AddPair('bottom',
          TJSONNumber.Create(Ellipse.Bounds.Bottom));
        EllipseJson.AddPair('fillColor',
          TJSONNumber.Create(Integer(Ellipse.FillColor)));
        EllipseJson.AddPair('opacity', TJSONNumber.Create(Ellipse.Opacity));
        EllipseJson.AddPair('rotation',
          TJSONNumber.Create(Ellipse.RotationDegrees));
        EllipseJson.AddPair('visible', TJSONBool.Create(Ellipse.Visible));
        EllipseJson.AddPair('locked', TJSONBool.Create(Ellipse.Locked));
        AddLayerFilters(Ellipse, EllipseJson);
        LayersJson.AddElement(EllipseJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TMapRakuRoundedRectangleLayer then
      begin
        RoundedRectangle := TMapRakuRoundedRectangleLayer(Layer);
        RoundedRectangleJson := TJSONObject.Create;
        RoundedRectangleJson.AddPair('type', 'roundedRectangle');
        RoundedRectangleJson.AddPair('name', RoundedRectangle.Name);
        RoundedRectangleJson.AddPair('left',
          TJSONNumber.Create(RoundedRectangle.Bounds.Left));
        RoundedRectangleJson.AddPair('top',
          TJSONNumber.Create(RoundedRectangle.Bounds.Top));
        RoundedRectangleJson.AddPair('right',
          TJSONNumber.Create(RoundedRectangle.Bounds.Right));
        RoundedRectangleJson.AddPair('bottom',
          TJSONNumber.Create(RoundedRectangle.Bounds.Bottom));
        RoundedRectangleJson.AddPair('topLeftRadius',
          TJSONNumber.Create(RoundedRectangle.CornerRadii.TopLeft));
        RoundedRectangleJson.AddPair('topRightRadius',
          TJSONNumber.Create(RoundedRectangle.CornerRadii.TopRight));
        RoundedRectangleJson.AddPair('bottomRightRadius',
          TJSONNumber.Create(RoundedRectangle.CornerRadii.BottomRight));
        RoundedRectangleJson.AddPair('bottomLeftRadius',
          TJSONNumber.Create(RoundedRectangle.CornerRadii.BottomLeft));
        RoundedRectangleJson.AddPair('fillColor',
          TJSONNumber.Create(Integer(RoundedRectangle.FillColor)));
        RoundedRectangleJson.AddPair('opacity',
          TJSONNumber.Create(RoundedRectangle.Opacity));
        RoundedRectangleJson.AddPair('rotation',
          TJSONNumber.Create(RoundedRectangle.RotationDegrees));
        RoundedRectangleJson.AddPair('visible',
          TJSONBool.Create(RoundedRectangle.Visible));
        RoundedRectangleJson.AddPair('locked',
          TJSONBool.Create(RoundedRectangle.Locked));
        AddLayerFilters(RoundedRectangle, RoundedRectangleJson);
        LayersJson.AddElement(RoundedRectangleJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if not (Layer is TVectArtRectangleLayer) then
        Continue;
      Rectangle := TVectArtRectangleLayer(Layer);
      RectangleJson := TJSONObject.Create;
      RectangleJson.AddPair('type', 'rectangle');
      RectangleJson.AddPair('name', Rectangle.Name);
      RectangleJson.AddPair('left',
        TJSONNumber.Create(Rectangle.Bounds.Left));
      RectangleJson.AddPair('top',
        TJSONNumber.Create(Rectangle.Bounds.Top));
      RectangleJson.AddPair('right',
        TJSONNumber.Create(Rectangle.Bounds.Right));
      RectangleJson.AddPair('bottom',
        TJSONNumber.Create(Rectangle.Bounds.Bottom));
      RectangleJson.AddPair('fillColor',
        TJSONNumber.Create(Integer(Rectangle.FillColor)));
      RectangleJson.AddPair('opacity', TJSONNumber.Create(Rectangle.Opacity));
      RectangleJson.AddPair('rotation',
        TJSONNumber.Create(Rectangle.RotationDegrees));
      RectangleJson.AddPair('visible', TJSONBool.Create(Rectangle.Visible));
      RectangleJson.AddPair('locked', TJSONBool.Create(Rectangle.Locked));
      AddLayerFilters(Rectangle, RectangleJson);
      LayersJson.AddElement(RectangleJson);
      if I = Document.SelectedIndex then
        SerializedSelectedIndex := LayersJson.Count;
    end;
    CrossingsJson := TJSONArray.Create;
    for I := 0 to Document.CrossingRelationCount - 1 do
    begin
      Crossing := Document.CrossingRelations[I];
      CrossingJson := TJSONObject.Create;
      CrossingJson.AddPair('objectAId', Crossing.ObjectAId);
      CrossingJson.AddPair('objectBId', Crossing.ObjectBId);
      CrossingJson.AddPair('kind', TJSONNumber.Create(Ord(Crossing.Kind)));
      CrossingJson.AddPair('upperObjectId', Crossing.UpperObjectId);
      CrossingJson.AddPair('rangeMargin', TJSONNumber.Create(Crossing.RangeMargin));
      CrossingsJson.AddElement(CrossingJson);
    end;
    Root.AddPair('crossingRelations', CrossingsJson);
    Root.AddPair('selectedIndex',
      TJSONNumber.Create(SerializedSelectedIndex));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
