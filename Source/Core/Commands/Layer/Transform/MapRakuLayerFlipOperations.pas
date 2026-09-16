// 現在選択を共通軸で左右・上下反転し、全レイヤー型を1件のUndo／Redoとして扱う。
unit MapRakuLayerFlipOperations;

interface

uses
  MapRakuDocument, MapRakuEditHistory, MapRakuEditorState;

type
  TMapRakuFlipDirection = (slfdHorizontal, slfdVertical);

// トップレベルまたは開いたグループの現在選択を反転できる場合にTrueを返す。
function CanFlipMapRakuSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): Boolean;
// 選択全体の外接範囲中央を軸に反転し、履歴へ適用済みコマンドを追加する。
procedure FlipMapRakuSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Direction: TMapRakuFlipDirection);

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils, System.Types,
  MapRakuEditCommands, MapRakuFilters, MapRakuGroupCommands,
  MapRakuLayerGeometry, MapRakuPaintStyles,
  MapRakuPatternStyle, MapRakuTextureStyle, MapRakuProjectiveTransform;

type
  TMapRakuFlipLayersCommand = class(TVectArtEditCommand)
  private
    FAfter: TObjectList<TVectArtLayer>;
    FBefore: TObjectList<TVectArtLayer>;
    FDocument: TVectArtDocument;
    FTargets: TArray<TVectArtLayer>;
    procedure Apply(const Values: TObjectList<TVectArtLayer>);
  public
    constructor Create(ADocument: TVectArtDocument;
      const Targets: TArray<TVectArtLayer>; const AxisCenter: TPointF;
      Direction: TMapRakuFlipDirection);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

function ReflectPoint(const Point, AxisCenter: TPointF;
  Direction: TMapRakuFlipDirection): TPointF;
begin
  Result := Point;
  if Direction = slfdHorizontal then
    Result.X := 2 * AxisCenter.X - Point.X
  else
    Result.Y := 2 * AxisCenter.Y - Point.Y;
end;

procedure ReflectBoundsCenter(var Bounds: TRectF; const AxisCenter: TPointF;
  Direction: TMapRakuFlipDirection);
var
  Center: TPointF;
  ReflectedCenter: TPointF;
begin
  Center := Bounds.CenterPoint;
  ReflectedCenter := ReflectPoint(Center, AxisCenter, Direction);
  Bounds.Offset(ReflectedCenter.X - Center.X, ReflectedCenter.Y - Center.Y);
end;

procedure ReflectCornerRadii(var Radii: TMapRakuCornerRadii;
  Direction: TMapRakuFlipDirection);
var
  Value: Single;
begin
  if Direction = slfdHorizontal then
  begin
    Value := Radii.TopLeft;
    Radii.TopLeft := Radii.TopRight;
    Radii.TopRight := Value;
    Value := Radii.BottomLeft;
    Radii.BottomLeft := Radii.BottomRight;
    Radii.BottomRight := Value;
  end
  else
  begin
    Value := Radii.TopLeft;
    Radii.TopLeft := Radii.BottomLeft;
    Radii.BottomLeft := Value;
    Value := Radii.TopRight;
    Radii.TopRight := Radii.BottomRight;
    Radii.BottomRight := Value;
  end;
end;

procedure ReflectPaintStyle(var Style: TMapRakuPaintStyle;
  Direction: TMapRakuFlipDirection);
var
  Pattern: TMapRakuPatternStyle;
  PointValue: TPointF;
  Texture: TMapRakuTextureStyle;
begin
  PointValue := Style.LinearStart;
  if Direction = slfdHorizontal then
    PointValue.X := 1 - PointValue.X
  else
    PointValue.Y := 1 - PointValue.Y;
  Style.LinearStart := PointValue;
  PointValue := Style.LinearEnd;
  if Direction = slfdHorizontal then
    PointValue.X := 1 - PointValue.X
  else
    PointValue.Y := 1 - PointValue.Y;
  Style.LinearEnd := PointValue;

  Pattern := Style.Pattern;
  if Direction = slfdHorizontal then
    Pattern.FlipHorizontal := not Pattern.FlipHorizontal
  else
    Pattern.FlipVertical := not Pattern.FlipVertical;
  Style.Pattern := Pattern;

  Texture := Style.Texture;
  if Direction = slfdHorizontal then
    Texture.FlipHorizontal := not Texture.FlipHorizontal
  else
    Texture.FlipVertical := not Texture.FlipVertical;
  Style.Texture := Texture;
end;

procedure ReflectLayerFilters(Layer: TVectArtLayer;
  Direction: TMapRakuFlipDirection);
var
  I: Integer;
  Shadow: TMapRakuShadowFilter;
begin
  for I := 0 to Layer.FilterCount - 1 do
    if Layer.Filters[I] is TMapRakuShadowFilter then
    begin
      Shadow := TMapRakuShadowFilter(Layer.Filters[I]);
      if Direction = slfdHorizontal then
        Shadow.OffsetX := -Shadow.OffsetX
      else
        Shadow.OffsetY := -Shadow.OffsetY;
    end;
end;

procedure ReflectVertices(var Vertices: TArray<TMapRakuVertex>;
  const AxisCenter: TPointF; Direction: TMapRakuFlipDirection);
var
  I: Integer;
begin
  Vertices := Copy(Vertices);
  for I := 0 to High(Vertices) do
  begin
    Vertices[I].Position := ReflectPoint(Vertices[I].Position,
      AxisCenter, Direction);
    if Direction = slfdHorizontal then
    begin
      Vertices[I].IncomingControl.X := -Vertices[I].IncomingControl.X;
      Vertices[I].OutgoingControl.X := -Vertices[I].OutgoingControl.X;
    end
    else
    begin
      Vertices[I].IncomingControl.Y := -Vertices[I].IncomingControl.Y;
      Vertices[I].OutgoingControl.Y := -Vertices[I].OutgoingControl.Y;
    end;
  end;
end;

procedure ReflectLayer(Layer: TVectArtLayer; const AxisCenter: TPointF;
  Direction: TMapRakuFlipDirection);
var
  Transform: TMapRakuTransform;
  Arc: TMapRakuArcLayer;
  ArcShape: TMapRakuEllipseArcShapeLayer;
  Bounds: TRectF;
  Contours: TArray<TMapRakuContour>;
  Group: TMapRakuGroupLayer;
  I: Integer;
  Image: TVectArtImageLayer;
  Points: TVectArtImagePoints;
  Radii: TMapRakuCornerRadii;
  Rectangle: TVectArtRectangleLayer;
  RectangleLine: TMapRakuRectangleLineLayer;
  Style: TMapRakuPaintStyle;
  Text: TMapRakuTextLayer;
  TextPath: TMapRakuTextPathLayer;
  WidthPoints: TArray<TMapRakuStrokeWidthPoint>;
  WidthScale: Single;
  Vertices: TArray<TMapRakuVertex>;
begin
  if Layer = nil then
    Exit;
  if not Layer.Transform.IsIdentity then
  begin
    Transform := TMapRakuTransform.Identity;
    if Direction = slfdHorizontal then
    begin Transform.Values[0] := -1; Transform.Values[2] := 2*AxisCenter.X end
    else begin Transform.Values[4] := -1; Transform.Values[5] := 2*AxisCenter.Y end;
    Layer.Transform := Layer.Transform.ThenApply(Transform);
    Exit;
  end;
  ReflectLayerFilters(Layer, Direction);
  if Layer is TMapRakuGroupLayer then
  begin
    Group := TMapRakuGroupLayer(Layer);
    for I := 0 to Group.ChildCount - 1 do
      ReflectLayer(Group[I], AxisCenter, Direction);
    Exit;
  end;

  if Layer is TMapRakuTextPathLayer then
  begin
    TextPath := TMapRakuTextPathLayer(Layer);
    Vertices := TextPath.EditablePathVertices;
    ReflectVertices(Vertices, AxisCenter, Direction);
    TextPath.AssignEditablePathVertices(Vertices);
    Bounds := TextPath.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    TextPath.Bounds := Bounds;
    TextPath.RotationDegrees := -TextPath.RotationDegrees;
    if Direction = slfdHorizontal then
      TextPath.FlipHorizontal := not TextPath.FlipHorizontal
    else
      TextPath.FlipVertical := not TextPath.FlipVertical;
    Style := TextPath.PaintStyle;
    ReflectPaintStyle(Style, Direction);
    TextPath.PaintStyle := Style;
    Exit;
  end;

  if Layer is TMapRakuTextLayer then
  begin
    Text := TMapRakuTextLayer(Layer);
    Bounds := Text.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    Text.Bounds := Bounds;
    Text.RotationDegrees := -Text.RotationDegrees;
    if Direction = slfdHorizontal then
      Text.FlipHorizontal := not Text.FlipHorizontal
    else
      Text.FlipVertical := not Text.FlipVertical;
    Exit;
  end;

  Style := Layer.PaintStyle;
  ReflectPaintStyle(Style, Direction);
  Layer.PaintStyle := Style;

  if Layer is TVectArtImageLayer then
  begin
    Image := TVectArtImageLayer(Layer);
    Points := Image.Points;
    for I := 0 to High(Points) do
      Points[I] := ReflectPoint(Points[I], AxisCenter, Direction);
    Image.Points := Points;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Vertices := TVectArtPathLayer(Layer).Vertices;
    ReflectVertices(Vertices, AxisCenter, Direction);
    TVectArtPathLayer(Layer).Vertices := Vertices;
    WidthPoints := TVectArtPathLayer(Layer).WidthPoints;
    for I := 0 to High(WidthPoints) do
    begin
      WidthScale := WidthPoints[I].LeftScale;
      WidthPoints[I].LeftScale := WidthPoints[I].RightScale;
      WidthPoints[I].RightScale := WidthScale;
    end;
    TVectArtPathLayer(Layer).WidthPoints := WidthPoints;
  end
  else if Layer is TMapRakuShapeLayer then
  begin
    Contours := TMapRakuShapeLayer(Layer).Contours;
    for I := 0 to High(Contours) do
      ReflectVertices(Contours[I].Vertices, AxisCenter, Direction);
    TMapRakuShapeLayer(Layer).Contours := Contours;
  end
  else if Layer is TMapRakuArcLayer then
  begin
    Arc := TMapRakuArcLayer(Layer);
    Bounds := Arc.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    Arc.Bounds := Bounds;
    Arc.RotationDegrees := -Arc.RotationDegrees;
    if Direction = slfdHorizontal then
      Arc.StartAngleDegrees := 180 - Arc.StartAngleDegrees -
        Arc.SweepAngleDegrees
    else
      Arc.StartAngleDegrees := -Arc.StartAngleDegrees -
        Arc.SweepAngleDegrees;
  end
  else if Layer is TMapRakuRectangleLineLayer then
  begin
    RectangleLine := TMapRakuRectangleLineLayer(Layer);
    Bounds := RectangleLine.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    RectangleLine.Bounds := Bounds;
    RectangleLine.RotationDegrees := -RectangleLine.RotationDegrees;
    if Layer is TMapRakuRoundedRectangleLineLayer then
    begin
      Radii := TMapRakuRoundedRectangleLineLayer(Layer).CornerRadii;
      ReflectCornerRadii(Radii, Direction);
      TMapRakuRoundedRectangleLineLayer(Layer).CornerRadii := Radii;
    end;
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    Rectangle := TVectArtRectangleLayer(Layer);
    Bounds := Rectangle.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    Rectangle.Bounds := Bounds;
    Rectangle.RotationDegrees := -Rectangle.RotationDegrees;
    if Layer is TMapRakuRoundedRectangleLayer then
    begin
      Radii := TMapRakuRoundedRectangleLayer(Layer).CornerRadii;
      ReflectCornerRadii(Radii, Direction);
      TMapRakuRoundedRectangleLayer(Layer).CornerRadii := Radii;
    end;
    if Layer is TMapRakuEllipseArcShapeLayer then
    begin
      ArcShape := TMapRakuEllipseArcShapeLayer(Layer);
      if Direction = slfdHorizontal then
        ArcShape.StartAngleDegrees := 180 - ArcShape.StartAngleDegrees -
          ArcShape.SweepAngleDegrees
      else
        ArcShape.StartAngleDegrees := -ArcShape.StartAngleDegrees -
          ArcShape.SweepAngleDegrees;
    end;
  end;
end;

procedure AssignTransformValues(Source, Target: TVectArtLayer);
var
  I: Integer;
begin
  Target.Transform := Source.Transform;
  Target.FlipHorizontal := Source.FlipHorizontal;
  Target.FlipVertical := Source.FlipVertical;
  Target.PaintStyle := Source.PaintStyle;
  for I := 0 to Min(Source.FilterCount, Target.FilterCount) - 1 do
    if (Source.Filters[I] is TMapRakuShadowFilter) and
      (Target.Filters[I] is TMapRakuShadowFilter) then
    begin
      TMapRakuShadowFilter(Target.Filters[I]).OffsetX :=
        TMapRakuShadowFilter(Source.Filters[I]).OffsetX;
      TMapRakuShadowFilter(Target.Filters[I]).OffsetY :=
        TMapRakuShadowFilter(Source.Filters[I]).OffsetY;
    end;
  if (Source is TMapRakuGroupLayer) and
    (Target is TMapRakuGroupLayer) then
  begin
    for I := 0 to Min(TMapRakuGroupLayer(Source).ChildCount,
      TMapRakuGroupLayer(Target).ChildCount) - 1 do
      AssignTransformValues(TMapRakuGroupLayer(Source)[I],
        TMapRakuGroupLayer(Target)[I]);
    Exit;
  end;
  if (Source is TMapRakuTextPathLayer) and
    (Target is TMapRakuTextPathLayer) then
    TMapRakuTextPathLayer(Target).AssignEditablePathVertices(
      TMapRakuTextPathLayer(Source).EditablePathVertices);
  if (Source is TVectArtImageLayer) and (Target is TVectArtImageLayer) then
    TVectArtImageLayer(Target).Points := TVectArtImageLayer(Source).Points
  else if (Source is TVectArtPathLayer) and (Target is TVectArtPathLayer) then
  begin
    TVectArtPathLayer(Target).Vertices := TVectArtPathLayer(Source).Vertices;
    TVectArtPathLayer(Target).WidthPoints :=
      TVectArtPathLayer(Source).WidthPoints;
  end
  else if (Source is TMapRakuShapeLayer) and
    (Target is TMapRakuShapeLayer) then
    TMapRakuShapeLayer(Target).Contours :=
      TMapRakuShapeLayer(Source).Contours
  else if (Source is TMapRakuArcLayer) and
    (Target is TMapRakuArcLayer) then
  begin
    TMapRakuArcLayer(Target).Bounds := TMapRakuArcLayer(Source).Bounds;
    TMapRakuArcLayer(Target).RotationDegrees :=
      TMapRakuArcLayer(Source).RotationDegrees;
    TMapRakuArcLayer(Target).StartAngleDegrees :=
      TMapRakuArcLayer(Source).StartAngleDegrees;
    TMapRakuArcLayer(Target).SweepAngleDegrees :=
      TMapRakuArcLayer(Source).SweepAngleDegrees;
  end
  else if (Source is TMapRakuRectangleLineLayer) and
    (Target is TMapRakuRectangleLineLayer) then
  begin
    TMapRakuRectangleLineLayer(Target).Bounds :=
      TMapRakuRectangleLineLayer(Source).Bounds;
    TMapRakuRectangleLineLayer(Target).RotationDegrees :=
      TMapRakuRectangleLineLayer(Source).RotationDegrees;
    if (Source is TMapRakuRoundedRectangleLineLayer) and
      (Target is TMapRakuRoundedRectangleLineLayer) then
      TMapRakuRoundedRectangleLineLayer(Target).CornerRadii :=
        TMapRakuRoundedRectangleLineLayer(Source).CornerRadii;
  end
  else if (Source is TVectArtRectangleLayer) and
    (Target is TVectArtRectangleLayer) then
  begin
    TVectArtRectangleLayer(Target).Bounds := TVectArtRectangleLayer(Source).Bounds;
    TVectArtRectangleLayer(Target).RotationDegrees :=
      TVectArtRectangleLayer(Source).RotationDegrees;
    if (Source is TMapRakuRoundedRectangleLayer) and
      (Target is TMapRakuRoundedRectangleLayer) then
      TMapRakuRoundedRectangleLayer(Target).CornerRadii :=
        TMapRakuRoundedRectangleLayer(Source).CornerRadii;
    if (Source is TMapRakuEllipseArcShapeLayer) and
      (Target is TMapRakuEllipseArcShapeLayer) then
    begin
      TMapRakuEllipseArcShapeLayer(Target).StartAngleDegrees :=
        TMapRakuEllipseArcShapeLayer(Source).StartAngleDegrees;
      TMapRakuEllipseArcShapeLayer(Target).SweepAngleDegrees :=
        TMapRakuEllipseArcShapeLayer(Source).SweepAngleDegrees;
    end;
  end;
end;

function SelectedLayers(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): TArray<TVectArtLayer>;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) then
    Exit(EditorState.GetOpenGroupChildren);
  Result := nil;
  if Document = nil then
    Exit;
  Indices := Document.GetSelectedLayerIndices;
  SetLength(Result, Length(Indices));
  for I := 0 to High(Indices) do
    Result[I] := Document[Indices[I]];
end;

function CanFlipMapRakuSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): Boolean;
var
  Layer: TVectArtLayer;
  Layers: TArray<TVectArtLayer>;
begin
  Layers := SelectedLayers(Document, EditorState);
  Result := Length(Layers) > 0;
  if not Result then
    Exit;
  for Layer in Layers do
    if (Layer = nil) or Layer.Locked or
      (Layer is TVectArtCanvasLayer) then
      Exit(False);
end;

function SelectionCenter(const Layers: TArray<TVectArtLayer>): TPointF;
var
  Bounds: TRectF;
  I: Integer;
  LayerBounds: TRectF;
  Valid: Boolean;
begin
  Bounds := TRectF.Empty;
  Valid := False;
  for I := 0 to High(Layers) do
    if TryGetMapRakuLayerBounds(Layers[I], LayerBounds) then
    begin
      if not Valid then
      begin
        Bounds := LayerBounds;
        Valid := True;
      end
      else
        Bounds := TRectF.Union(Bounds, LayerBounds);
    end;
  if Valid then
    Result := Bounds.CenterPoint
  else
    Result := TPointF.Zero;
end;

constructor TMapRakuFlipLayersCommand.Create(ADocument: TVectArtDocument;
  const Targets: TArray<TVectArtLayer>; const AxisCenter: TPointF;
  Direction: TMapRakuFlipDirection);
var
  AfterLayer: TVectArtLayer;
  I: Integer;
begin
  inherited Create;
  FDocument := ADocument;
  FTargets := Copy(Targets);
  FBefore := TObjectList<TVectArtLayer>.Create(True);
  FAfter := TObjectList<TVectArtLayer>.Create(True);
  for I := 0 to High(FTargets) do
  begin
    FBefore.Add(CloneMapRakuLayer(FTargets[I], FTargets[I].Name));
    AfterLayer := CloneMapRakuLayer(FTargets[I], FTargets[I].Name);
    ReflectLayer(AfterLayer, AxisCenter, Direction);
    FAfter.Add(AfterLayer);
  end;
end;

destructor TMapRakuFlipLayersCommand.Destroy;
begin
  FAfter.Free;
  FBefore.Free;
  inherited Destroy;
end;

procedure TMapRakuFlipLayersCommand.Apply(
  const Values: TObjectList<TVectArtLayer>);
var
  I: Integer;
begin
  if FDocument = nil then
    Exit;
  FDocument.BeginUpdate;
  try
    for I := 0 to Min(High(FTargets), Values.Count - 1) do
      AssignTransformValues(Values[I], FTargets[I]);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuFlipLayersCommand.Execute;
begin
  Apply(FAfter);
end;

procedure TMapRakuFlipLayersCommand.Undo;
begin
  Apply(FBefore);
end;

procedure FlipMapRakuSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Direction: TMapRakuFlipDirection);
var
  Command: TMapRakuFlipLayersCommand;
  Layers: TArray<TVectArtLayer>;
begin
  if not CanFlipMapRakuSelection(Document, EditorState) then
    Exit;
  Layers := SelectedLayers(Document, EditorState);
  Command := TMapRakuFlipLayersCommand.Create(Document, Layers,
    SelectionCenter(Layers), Direction);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

end.
