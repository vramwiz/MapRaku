// 開いたグループの子選択、当たり判定、ドラッグ変形と履歴確定を管理する。
unit MapRakuGroupInteraction;

interface

uses
  System.Classes, System.Types, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState, MapRakuSelectionGeometry,
  MapRakuSnapGeometry;

type
  TMapRakuGroupDragMode = (slgdmNone, slgdmMove, slgdmResize,
    slgdmRotate);

  TMapRakuGroupDrag = class
  private
    FCurrentBounds: TRectF;
    FDocument: TVectArtDocument;
    FDX: Single;
    FDY: Single;
    FLayers: TArray<TVectArtLayer>;
    FMode: TMapRakuGroupDragMode;
    FResizeHandle: TVectArtSelectionHandle;
    FRotationCenter: TPointF;
    FRotationDegrees: Single;
    FRotationStartAngle: Single;
    FSnapGuides: TArray<TMapRakuSnapGuide>;
    FStartBounds: TRectF;
    FStartPoint: TPoint;
    FTextLayer: TMapRakuTextLayer;
    FTextTransformModeStart: TMapRakuTextTransformMode;
    function GetActive: Boolean;
    procedure Reset;
  public
    // 選択子の移動を開始し、履歴確定に必要な開始状態を保持する。
    procedure BeginMove(Document: TVectArtDocument;
      const Layers: TArray<TVectArtLayer>; const StartPoint: TPoint);
    // 選択子全体の外接範囲を基準に拡大縮小を開始する。
    procedure BeginResize(Document: TVectArtDocument;
      const Layers: TArray<TVectArtLayer>; const StartPoint: TPoint;
      Handle: TVectArtSelectionHandle; const Bounds: TRectF);
    // 選択子全体を共通中心回りに回転する操作を開始する。
    procedure BeginRotate(Document: TVectArtDocument;
      const Layers: TArray<TVectArtLayer>; const Center: TPointF;
      StartAngle: Single);
    // 適用済みの変形量を1回のUndo単位として履歴へ確定する。
    function Finish(EditHistory: TVectArtEditHistory): Boolean;
    // 現在のマウス位置に対応する移動または拡大縮小をDocumentへ反映する。
    function UpdateMoveOrResize(Shift: TShiftState;
      X, Y: Integer; Zoom: Single): Boolean;
    // 現在角度に対応する回転差分をDocumentへ反映する。
    function UpdateRotation(CurrentAngle: Single;
      Shift: TShiftState): Boolean;
    property Active: Boolean read GetActive;
    property Mode: TMapRakuGroupDragMode read FMode;
    property ResizeHandle: TVectArtSelectionHandle read FResizeHandle;
    property RotationCenter: TPointF read FRotationCenter;
    property SnapGuides: TArray<TMapRakuSnapGuide> read FSnapGuides;
  end;

// グループ内の指定点で最前面にある表示中の直下レイヤーを返す。
function HitTestGroupChild(Group: TMapRakuGroupLayer;
  const LogicalPoint: TPointF): TVectArtLayer;
// 開いているグループで選択中の子全体を囲む外接範囲を返す。
function TryGetOpenGroupSelectionBounds(EditorState: TVectArtEditorState;
  out Bounds: TRectF): Boolean;
// 選択中のすべての子がロックされておらず変形可能ならTrueを返す。
function OpenGroupSelectionEditable(EditorState: TVectArtEditorState): Boolean;

implementation

uses
  System.Math, MapRakuEditCommands, MapRakuGroupTransformCommands,
  MapRakuLayerGeometry;

procedure TMapRakuGroupDrag.BeginMove(Document: TVectArtDocument;
  const Layers: TArray<TVectArtLayer>; const StartPoint: TPoint);
var
  Bounds: TRectF;
  BoundsInitialized: Boolean;
  I: Integer;
begin
  Reset;
  FDocument := Document;
  FLayers := Copy(Layers);
  FStartPoint := StartPoint;
  BoundsInitialized := False;
  for I := 0 to High(FLayers) do
    if TryGetMapRakuLayerBounds(FLayers[I], Bounds) then
      if not BoundsInitialized then
      begin
        FStartBounds := Bounds;
        BoundsInitialized := True;
      end
      else
        FStartBounds := TRectF.Union(FStartBounds, Bounds);
  FMode := slgdmMove;
end;

procedure TMapRakuGroupDrag.BeginResize(Document: TVectArtDocument;
  const Layers: TArray<TVectArtLayer>; const StartPoint: TPoint;
  Handle: TVectArtSelectionHandle; const Bounds: TRectF);
begin
  Reset;
  FDocument := Document;
  FLayers := Copy(Layers);
  FStartPoint := StartPoint;
  FResizeHandle := Handle;
  FStartBounds := Bounds;
  FCurrentBounds := Bounds;
  if (Length(FLayers) = 1) and
    (FLayers[0] is TMapRakuTextLayer) then
  begin
    FTextLayer := TMapRakuTextLayer(FLayers[0]);
    FTextTransformModeStart := FTextLayer.TransformMode;
  end;
  FMode := slgdmResize;
end;

procedure TMapRakuGroupDrag.BeginRotate(Document: TVectArtDocument;
  const Layers: TArray<TVectArtLayer>; const Center: TPointF;
  StartAngle: Single);
begin
  Reset;
  FDocument := Document;
  FLayers := Copy(Layers);
  FRotationCenter := Center;
  FRotationStartAngle := StartAngle;
  FMode := slgdmRotate;
end;

function TMapRakuGroupDrag.Finish(
  EditHistory: TVectArtEditHistory): Boolean;
var
  Command: TVectArtCompoundCommand;
  I: Integer;
begin
  Result := FMode <> slgdmNone;
  if not Result then
    Exit;
  if (EditHistory <> nil) and (Length(FLayers) > 0) then
  begin
    Command := TVectArtCompoundCommand.Create;
    case FMode of
      slgdmMove:
        if not SameValue(FDX, 0.0) or not SameValue(FDY, 0.0) then
          for I := 0 to High(FLayers) do
            Command.Add(TMapRakuTranslateLayerCommand.Create(
              FDocument, FLayers[I], FDX, FDY));
      slgdmResize:
      begin
        if not FStartBounds.EqualsTo(FCurrentBounds) then
          for I := 0 to High(FLayers) do
            Command.Add(TMapRakuScaleLayerCommand.Create(
              FDocument, FLayers[I], FStartBounds, FCurrentBounds));
        if (FTextLayer <> nil) and
          (FTextLayer.TransformMode <> FTextTransformModeStart) then
          Command.Add(TMapRakuTextTransformModeCommand.Create(
            FDocument, FTextLayer, FTextTransformModeStart,
            FTextLayer.TransformMode));
      end;
      slgdmRotate:
        if not SameValue(FRotationDegrees, 0.0) then
          for I := 0 to High(FLayers) do
            Command.Add(TMapRakuRotateLayerCommand.Create(
              FDocument, FLayers[I], FRotationCenter, FRotationDegrees));
    end;
    if Command.Count > 0 then
      EditHistory.AddApplied(Command)
    else
      Command.Free;
  end;
  Reset;
end;

function TMapRakuGroupDrag.GetActive: Boolean;
begin
  Result := FMode <> slgdmNone;
end;

procedure TMapRakuGroupDrag.Reset;
begin
  FDocument := nil;
  SetLength(FLayers, 0);
  FMode := slgdmNone;
  FDX := 0;
  FDY := 0;
  FResizeHandle := vshNone;
  FRotationDegrees := 0;
  FSnapGuides := nil;
  FTextLayer := nil;
end;

function TMapRakuGroupDrag.UpdateMoveOrResize(
  Shift: TShiftState; X, Y: Integer; Zoom: Single): Boolean;
var
  Anchor: TPointF;
  DX: Single;
  DY: Single;
  HandlePoint: TPointF;
  I: Integer;
  MinimumScale: Single;
  Scale: Single;
  SnappedDelta: TPointF;
  TargetBounds: TRectF;
  VectorX: Single;
  VectorY: Single;
begin
  Result := FMode in [slgdmMove, slgdmResize];
  if not Result then
    Exit;
  DX := (X - FStartPoint.X) / Zoom;
  DY := (Y - FStartPoint.Y) / Zoom;
  if FMode = slgdmMove then
  begin
    FSnapGuides := nil;
    if not (ssAlt in Shift) and not FStartBounds.IsEmpty and
      SnapMapRakuMoveForLayers(FDocument, FStartBounds,
        TPointF.Create(DX, DY), Zoom, FLayers, SnappedDelta,
        FSnapGuides) then
    begin
      DX := SnappedDelta.X;
      DY := SnappedDelta.Y;
    end;
    for I := 0 to High(FLayers) do
      TranslateMapRakuLayer(FLayers[I], DX - FDX, DY - FDY);
    FDX := DX;
    FDY := DY;
  end
  else
  begin
    FSnapGuides := nil;
    TargetBounds := FStartBounds;
    if FResizeHandle in [vshTopLeft, vshLeft, vshBottomLeft] then
      TargetBounds.Left := Min(FStartBounds.Right - 1,
        FStartBounds.Left + DX);
    if FResizeHandle in [vshTopRight, vshRight, vshBottomRight] then
      TargetBounds.Right := Max(FStartBounds.Left + 1,
        FStartBounds.Right + DX);
    if FResizeHandle in [vshTopLeft, vshTop, vshTopRight] then
      TargetBounds.Top := Min(FStartBounds.Bottom - 1,
        FStartBounds.Top + DY);
    if FResizeHandle in [vshBottomLeft, vshBottom, vshBottomRight] then
      TargetBounds.Bottom := Max(FStartBounds.Top + 1,
        FStartBounds.Bottom + DY);
    if FTextLayer <> nil then
    begin
      if ssCtrl in Shift then
        FTextLayer.TransformMode := slttmFrameFit
      else if ssShift in Shift then
        FTextLayer.TransformMode := slttmUniformScale;
      if FTextLayer.TransformMode = slttmUniformScale then
      begin
        case FResizeHandle of
          vshTopLeft:
          begin
            HandlePoint := FStartBounds.TopLeft;
            Anchor := FStartBounds.BottomRight;
          end;
          vshTop:
          begin
            HandlePoint := TPointF.Create(FStartBounds.CenterPoint.X,
              FStartBounds.Top);
            Anchor := TPointF.Create(FStartBounds.CenterPoint.X,
              FStartBounds.Bottom);
          end;
          vshTopRight:
          begin
            HandlePoint := TPointF.Create(FStartBounds.Right,
              FStartBounds.Top);
            Anchor := TPointF.Create(FStartBounds.Left,
              FStartBounds.Bottom);
          end;
          vshRight:
          begin
            HandlePoint := TPointF.Create(FStartBounds.Right,
              FStartBounds.CenterPoint.Y);
            Anchor := TPointF.Create(FStartBounds.Left,
              FStartBounds.CenterPoint.Y);
          end;
          vshBottomRight:
          begin
            HandlePoint := FStartBounds.BottomRight;
            Anchor := FStartBounds.TopLeft;
          end;
          vshBottom:
          begin
            HandlePoint := TPointF.Create(FStartBounds.CenterPoint.X,
              FStartBounds.Bottom);
            Anchor := TPointF.Create(FStartBounds.CenterPoint.X,
              FStartBounds.Top);
          end;
          vshBottomLeft:
          begin
            HandlePoint := TPointF.Create(FStartBounds.Left,
              FStartBounds.Bottom);
            Anchor := TPointF.Create(FStartBounds.Right,
              FStartBounds.Top);
          end;
        else
          HandlePoint := TPointF.Create(FStartBounds.Left,
            FStartBounds.CenterPoint.Y);
          Anchor := TPointF.Create(FStartBounds.Right,
            FStartBounds.CenterPoint.Y);
        end;
        VectorX := HandlePoint.X - Anchor.X;
        VectorY := HandlePoint.Y - Anchor.Y;
        Scale := ((HandlePoint.X + DX - Anchor.X) * VectorX +
          (HandlePoint.Y + DY - Anchor.Y) * VectorY) /
          Max(VectorX * VectorX + VectorY * VectorY, 0.001);
        MinimumScale := Max(1 / Max(FStartBounds.Width, 0.001),
          1 / Max(FStartBounds.Height, 0.001));
        Scale := Max(Scale, MinimumScale);
        TargetBounds := TRectF.Create(
          Anchor.X + (FStartBounds.Left - Anchor.X) * Scale,
          Anchor.Y + (FStartBounds.Top - Anchor.Y) * Scale,
          Anchor.X + (FStartBounds.Right - Anchor.X) * Scale,
          Anchor.Y + (FStartBounds.Bottom - Anchor.Y) * Scale);
      end;
    end;
    for I := 0 to High(FLayers) do
      ScaleMapRakuLayer(FLayers[I], FCurrentBounds, TargetBounds);
    FCurrentBounds := TargetBounds;
  end;
  FDocument.Changed;
end;

function TMapRakuGroupDrag.UpdateRotation(CurrentAngle: Single;
  Shift: TShiftState): Boolean;
var
  DesiredDegrees: Single;
  I: Integer;
  IncrementDegrees: Single;
begin
  Result := FMode = slgdmRotate;
  if not Result then
    Exit;
  DesiredDegrees := CurrentAngle - FRotationStartAngle;
  while DesiredDegrees > 180 do
    DesiredDegrees := DesiredDegrees - 360;
  while DesiredDegrees < -180 do
    DesiredDegrees := DesiredDegrees + 360;
  if ssShift in Shift then
    DesiredDegrees := Round(DesiredDegrees / 15) * 15;
  IncrementDegrees := DesiredDegrees - FRotationDegrees;
  for I := 0 to High(FLayers) do
    RotateMapRakuLayer(FLayers[I], FRotationCenter, IncrementDegrees);
  FRotationDegrees := DesiredDegrees;
  FDocument.Changed;
end;

function HitTestGroupChild(Group: TMapRakuGroupLayer;
  const LogicalPoint: TPointF): TVectArtLayer;
var
  Bounds: TRectF;
  I: Integer;
begin
  Result := nil;
  if Group = nil then
    Exit;
  for I := Group.ChildCount - 1 downto 0 do
    if Group[I].Visible and TryGetMapRakuLayerBounds(Group[I], Bounds) and
      Bounds.Contains(LogicalPoint) then
      Exit(Group[I]);
end;

function TryGetOpenGroupSelectionBounds(EditorState: TVectArtEditorState;
  out Bounds: TRectF): Boolean;
var
  ChildBounds: TRectF;
  Layer: TVectArtLayer;
begin
  Result := False;
  Bounds := TRectF.Empty;
  if EditorState = nil then
    Exit;
  for Layer in EditorState.GetOpenGroupChildren do
    if TryGetMapRakuLayerBounds(Layer, ChildBounds) then
    begin
      if not Result then
        Bounds := ChildBounds
      else
      begin
        Bounds.Left := Min(Bounds.Left, ChildBounds.Left);
        Bounds.Top := Min(Bounds.Top, ChildBounds.Top);
        Bounds.Right := Max(Bounds.Right, ChildBounds.Right);
        Bounds.Bottom := Max(Bounds.Bottom, ChildBounds.Bottom);
      end;
      Result := True;
    end;
end;

function OpenGroupSelectionEditable(EditorState: TVectArtEditorState): Boolean;
var
  Layer: TVectArtLayer;
begin
  Result := (EditorState <> nil) and (EditorState.OpenGroupChildCount > 0);
  if not Result then
    Exit;
  for Layer in EditorState.GetOpenGroupChildren do
    if Layer.Locked then
      Exit(False);
end;

end.
