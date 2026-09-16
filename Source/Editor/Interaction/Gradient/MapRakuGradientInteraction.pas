// グラデーションの方向ガイドを描画し、点編集とドラッグ操作をUndo履歴へ確定する。
unit MapRakuGradientInteraction;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Direct2D, Vcl.Graphics,
  MapRakuDocument, MapRakuEditHistory, MapRakuEditorState,
  MapRakuPaintStyles;

type
  TMapRakuGradientGuideHit = (slgghNone, slgghLine,
    slgghStartPoint, slgghMiddlePoint, slgghEndPoint, slgghAspect);

  TMapRakuGradientDragKind = (slgdkNone, slgdkPendingLine,
    slgdkLine, slgdkStartPoint, slgdkMiddlePoint, slgdkEndPoint, slgdkAspect);

  TMapRakuGradientInteraction = class
  private
    FCanvasBounds: TRect;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FEditHistory: TVectArtEditHistory;
    FZoom: Single;
    FDragKind: TMapRakuGradientDragKind;
    FDragLayer: TVectArtLayer;
    FDragOldStyle: TMapRakuPaintStyle;
    FDragStartMouse: TPoint;
    FDragStopId: Integer;
    FInteractiveUpdateActive: Boolean;
    procedure AddAppliedStyleCommand(Layer: TVectArtLayer;
      const OldStyle, NewStyle: TMapRakuPaintStyle);
    function AddStopAt(Layer: TVectArtLayer; X, Y: Integer): Boolean;
    function ActiveLayer(out Layer: TVectArtLayer): Boolean;
    procedure BeginDrag(Kind: TMapRakuGradientDragKind;
      Layer: TVectArtLayer; X, Y, StopId: Integer);
    procedure BeginInteractiveUpdate;
    procedure ClearDrag;
    function DistanceToSegment(X, Y: Integer; const A, B: TPoint): Single;
    procedure EndInteractiveUpdate;
    function GuidePointsForStyle(Layer: TVectArtLayer;
      const Style: TMapRakuPaintStyle; out StartPoint,
      EndPoint: TPoint): Boolean;
    function GetDragging: Boolean;
    function ProjectOffset(X, Y: Integer; const StartPoint,
      EndPoint: TPoint): Single;
    procedure RecordAppliedStyleCommand(Layer: TVectArtLayer;
      const OldStyle, NewStyle: TMapRakuPaintStyle);
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
    function StopPoint(Offset: Single; const StartPoint,
      EndPoint: TPoint): TPoint;
  public
    // 対話更新中ならDocument通知を閉じてから内部状態を破棄する。
    destructor Destroy; override;
    // ガイド座標と当たり判定に使うDocument、編集状態、表示領域を更新する。
    procedure Configure(Document: TVectArtDocument;
      EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
      const CanvasBounds: TRect; Zoom: Single);
    // 単一選択中のグラデーションガイドをGDIまたはDirect2Dへ描画する。
    procedure Draw(ACanvas: TCanvas); overload;
    procedure Draw(ACanvas: TDirect2DCanvas); overload;
    // クライアント座標にあるガイド要素を返し、詳細版では中間点IDも返す。
    function HitTest(X, Y: Integer): TMapRakuGradientGuideHit;
    function HitTestDetail(X, Y: Integer; out StopId: Integer):
      TMapRakuGradientGuideHit;
    // 点では移動、線では追加を示すカーソルを返す。
    function CursorAt(X, Y: Integer): TCursor;
    // レイヤーのローカル座標と回転を反映したガイド両端をクライアント座標で返す。
    function TryGetGuidePoints(out StartPoint, EndPoint: TPoint): Boolean;
    // 左操作をドラッグ候補として開始し、右操作では中間点を即時削除する。
    function MouseDown(Button: TMouseButton; X, Y: Integer): Boolean;
    // キャプチャ中の端点、中間点、またはガイド全体を更新する。
    function MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
    // クリックなら中間点追加、ドラッグなら変更全体を1件の履歴として確定する。
    function MouseUp(X, Y: Integer): Boolean;
    property Dragging: Boolean read GetDragging;
  end;

implementation

uses
  System.Math, MapRakuGeometry, MapRakuGradientOverlay,
  MapRakuLayerGeometry, MapRakuPaintCommands;

const
  GRADIENT_HANDLE_RADIUS = 6;
  GRADIENT_LINE_HIT_RADIUS = 6;
  GRADIENT_DRAG_THRESHOLD = 4;

function GradientAspectPoint(const A, B: TPoint; Aspect: Single): TPoint;
begin
  Result := Point(Round(A.X - (B.Y - A.Y) * Aspect), Round(A.Y + (B.X - A.X) * Aspect));
end;

procedure TMapRakuGradientInteraction.AddAppliedStyleCommand(
  Layer: TVectArtLayer; const OldStyle,
  NewStyle: TMapRakuPaintStyle);
begin
  Layer.PaintStyle := NewStyle;
  FDocument.Changed;
  RecordAppliedStyleCommand(Layer, OldStyle, NewStyle);
end;

function TMapRakuGradientInteraction.AddStopAt(Layer: TVectArtLayer;
  X, Y: Integer): Boolean;
var
  EndPoint: TPoint;
  NewStopId: Integer;
  NewStyle: TMapRakuPaintStyle;
  OldStyle: TMapRakuPaintStyle;
  StartPoint: TPoint;
begin
  Result := GuidePointsForStyle(Layer, Layer.PaintStyle, StartPoint,
    EndPoint);
  if not Result then
    Exit;
  OldStyle := Layer.PaintStyle;
  NewStyle := OldStyle;
  NewStopId := NewStyle.AddGradientStop(
    ProjectOffset(X, Y, StartPoint, EndPoint));
  AddAppliedStyleCommand(Layer, OldStyle, NewStyle);
  if FEditorState <> nil then
    FEditorState.SelectGradientStop(Layer, NewStopId);
end;

function TMapRakuGradientInteraction.ActiveLayer(
  out Layer: TVectArtLayer): Boolean;
var
  Selected: TArray<Integer>;
  Children: TArray<TVectArtLayer>;
begin
  Layer := nil;
  Result := (FDocument <> nil) and (FDocument.CanvasLayer <> nil) and
    (FEditorState <> nil) and (FEditorState.CurrentTool = vetSelect) and
    (FEditorState.SelectedFilter = nil);
  if not Result then
    Exit;
  if FEditorState.OpenGroup <> nil then
  begin
    Children := FEditorState.GetOpenGroupChildren;
    if Length(Children) = 1 then
      Layer := Children[0];
    Result := (Layer <> nil) and (Layer.PaintStyle.Kind = slpkGradient) and
      not (Layer.PaintStyle.GradientKind in [slgkAlongStroke, slgkAcrossStroke]);
    Exit;
  end;
  Selected := FDocument.GetSelectedLayerIndices;
  Result := (Length(Selected) = 1) and (Selected[0] > 0) and
    (Selected[0] < FDocument.LayerCount);
  if not Result then
    Exit;
  Layer := FDocument[Selected[0]];
  Result := (Layer <> nil) and
    (Layer.PaintStyle.Kind = slpkGradient) and
    not (Layer.PaintStyle.GradientKind in [slgkAlongStroke, slgkAcrossStroke]);
  if not Result then
    Layer := nil;
end;

procedure TMapRakuGradientInteraction.Configure(
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; const CanvasBounds: TRect; Zoom: Single);
begin
  FDocument := Document;
  FEditHistory := EditHistory;
  FEditorState := EditorState;
  FCanvasBounds := CanvasBounds;
  FZoom := Zoom;
end;

procedure TMapRakuGradientInteraction.BeginDrag(
  Kind: TMapRakuGradientDragKind; Layer: TVectArtLayer;
  X, Y, StopId: Integer);
begin
  FDragKind := Kind;
  FDragLayer := Layer;
  FDragOldStyle := Layer.PaintStyle;
  FDragStartMouse := Point(X, Y);
  FDragStopId := StopId;
  if Kind <> slgdkPendingLine then
    BeginInteractiveUpdate;
end;

procedure TMapRakuGradientInteraction.BeginInteractiveUpdate;
begin
  if FInteractiveUpdateActive or (FDocument = nil) then
    Exit;
  FDocument.BeginInteractiveUpdate;
  FInteractiveUpdateActive := True;
end;

procedure TMapRakuGradientInteraction.ClearDrag;
begin
  FDragKind := slgdkNone;
  FDragLayer := nil;
  FDragStopId := 0;
end;

destructor TMapRakuGradientInteraction.Destroy;
begin
  EndInteractiveUpdate;
  inherited Destroy;
end;

function TMapRakuGradientInteraction.CursorAt(X, Y: Integer): TCursor;
begin
  if FDragKind <> slgdkNone then
  begin
    if FDragKind = slgdkPendingLine then
      Exit(crCross);
    Exit(crSizeAll);
  end;
  case HitTest(X, Y) of
    slgghStartPoint, slgghMiddlePoint, slgghEndPoint, slgghAspect: Result := crSizeAll;
    slgghLine: Result := crCross;
  else
    Result := crDefault;
  end;
end;

function TMapRakuGradientInteraction.DistanceToSegment(X, Y: Integer;
  const A, B: TPoint): Single;
var
  DX: Single;
  DY: Single;
  T: Single;
  PX: Single;
  PY: Single;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  if SameValue(DX, 0.0) and SameValue(DY, 0.0) then
    Exit(Hypot(X - A.X, Y - A.Y));
  T := EnsureRange(((X - A.X) * DX + (Y - A.Y) * DY) /
    (DX * DX + DY * DY), 0.0, 1.0);
  PX := A.X + T * DX;
  PY := A.Y + T * DY;
  Result := Hypot(X - PX, Y - PY);
end;

procedure TMapRakuGradientInteraction.EndInteractiveUpdate;
begin
  if not FInteractiveUpdateActive then
    Exit;
  FInteractiveUpdateActive := False;
  if FDocument <> nil then
    FDocument.EndInteractiveUpdate;
end;

function TMapRakuGradientInteraction.GuidePointsForStyle(
  Layer: TVectArtLayer; const Style: TMapRakuPaintStyle;
  out StartPoint, EndPoint: TPoint): Boolean;
var
  Bounds: TRectF;
  EndValue: TPointF;
  RotationDegrees: Single;
  StartValue: TPointF;
begin
  Result := (Layer <> nil) and
    TryGetMapRakuLayerPaintGeometry(Layer, Bounds,
      RotationDegrees);
  if not Result then
  begin
    StartPoint := TPoint.Zero;
    EndPoint := TPoint.Zero;
    Exit;
  end;
  StartValue := MapRakuLayerPaintPoint(Bounds, RotationDegrees,
    Style.LinearStart);
  EndValue := MapRakuLayerPaintPoint(Bounds, RotationDegrees,
    Style.LinearEnd);
  StartPoint := Point(ToScreenX(StartValue.X), ToScreenY(StartValue.Y));
  EndPoint := Point(ToScreenX(EndValue.X), ToScreenY(EndValue.Y));
end;

function TMapRakuGradientInteraction.GetDragging: Boolean;
begin
  Result := FDragKind <> slgdkNone;
end;

procedure TMapRakuGradientInteraction.Draw(ACanvas: TCanvas);
var
  EndPoint: TPoint;
  Layer: TVectArtLayer;
  StartPoint: TPoint;
begin
  if not ActiveLayer(Layer) or
    not TryGetGuidePoints(StartPoint, EndPoint) then
    Exit;
  DrawMapRakuGradientGuide(ACanvas, Layer, FEditorState,
    StartPoint, EndPoint);
end;

procedure TMapRakuGradientInteraction.Draw(ACanvas: TDirect2DCanvas);
var
  EndPoint: TPoint;
  Layer: TVectArtLayer;
  StartPoint: TPoint;
begin
  if not ActiveLayer(Layer) or
    not TryGetGuidePoints(StartPoint, EndPoint) then
    Exit;
  DrawMapRakuGradientGuide(ACanvas, Layer, FEditorState,
    StartPoint, EndPoint);
end;

function TMapRakuGradientInteraction.HitTest(X,
  Y: Integer): TMapRakuGradientGuideHit;
var
  StopId: Integer;
begin
  Result := HitTestDetail(X, Y, StopId);
end;

function TMapRakuGradientInteraction.HitTestDetail(X, Y: Integer;
  out StopId: Integer): TMapRakuGradientGuideHit;
var
  EndPoint: TPoint;
  PointValue: TPoint;
  Layer: TVectArtLayer;
  StartPoint: TPoint;
  Stop: TMapRakuGradientStop;
begin
  Result := slgghNone;
  StopId := 0;
  if not ActiveLayer(Layer) or
    not GuidePointsForStyle(Layer, Layer.PaintStyle, StartPoint, EndPoint) then
    Exit;
  if Hypot(X - StartPoint.X, Y - StartPoint.Y) <=
    GRADIENT_HANDLE_RADIUS + 2 then
    Exit(slgghStartPoint);
  if Hypot(X - EndPoint.X, Y - EndPoint.Y) <=
    GRADIENT_HANDLE_RADIUS + 2 then
    Exit(slgghEndPoint);
  if Layer.PaintStyle.GradientKind in [slgkRadial, slgkRectangle, slgkSweep] then
  begin
    PointValue := GradientAspectPoint(StartPoint, EndPoint, Layer.PaintStyle.GradientAspect);
    if Hypot(X - PointValue.X, Y - PointValue.Y) <= GRADIENT_HANDLE_RADIUS + 2 then
      Exit(slgghAspect);
  end;
  for Stop in Layer.PaintStyle.GetGradientStops do
  begin
    PointValue := StopPoint(Stop.Offset, StartPoint, EndPoint);
    if Hypot(X - PointValue.X, Y - PointValue.Y) <=
      GRADIENT_HANDLE_RADIUS + 2 then
    begin
      StopId := Stop.Id;
      Exit(slgghMiddlePoint);
    end;
  end;
  if DistanceToSegment(X, Y, StartPoint, EndPoint) <=
    GRADIENT_LINE_HIT_RADIUS then
    Result := slgghLine;
end;

function TMapRakuGradientInteraction.MouseDown(Button: TMouseButton;
  X, Y: Integer): Boolean;
var
  EndPoint: TPoint;
  Hit: TMapRakuGradientGuideHit;
  Layer: TVectArtLayer;
  NewStyle: TMapRakuPaintStyle;
  OldStyle: TMapRakuPaintStyle;
  StartPoint: TPoint;
  StopId: Integer;
begin
  Result := False;
  if not ActiveLayer(Layer) or Layer.Locked or
    not TryGetGuidePoints(StartPoint, EndPoint) then
    Exit;
  Hit := HitTestDetail(X, Y, StopId);
  if Button = mbLeft then
  begin
    Result := Hit <> slgghNone;
    case Hit of
      slgghStartPoint:
        FEditorState.SelectGradientStop(Layer,
          SCREEN_LAYOUT_GRADIENT_START_STOP_ID);
      slgghMiddlePoint:
        FEditorState.SelectGradientStop(Layer, StopId);
      slgghEndPoint:
        FEditorState.SelectGradientStop(Layer,
          SCREEN_LAYOUT_GRADIENT_END_STOP_ID);
    end;
    case Hit of
      slgghAspect:
        BeginDrag(slgdkAspect, Layer, X, Y, 0);
      slgghLine:
        BeginDrag(slgdkPendingLine, Layer, X, Y, 0);
      slgghStartPoint:
        BeginDrag(slgdkStartPoint, Layer, X, Y, 0);
      slgghMiddlePoint:
        BeginDrag(slgdkMiddlePoint, Layer, X, Y, StopId);
      slgghEndPoint:
        BeginDrag(slgdkEndPoint, Layer, X, Y, 0);
    end;
    Exit;
  end
  else if Button = mbRight then
  begin
    Result := Hit in [slgghStartPoint, slgghMiddlePoint, slgghEndPoint];
    if Hit <> slgghMiddlePoint then
      Exit;
    OldStyle := Layer.PaintStyle;
    NewStyle := OldStyle;
    if not NewStyle.RemoveGradientStop(StopId) then
      Exit;
    FEditorState.SelectGradientStop(Layer,
      SCREEN_LAYOUT_GRADIENT_START_STOP_ID);
  end
  else
    Exit;
  AddAppliedStyleCommand(Layer, OldStyle, NewStyle);
end;

function TMapRakuGradientInteraction.MouseMove(Shift: TShiftState;
  X, Y: Integer): Boolean;
var
  Bounds: TRectF;
  EndPoint: TPoint;
  NewStyle: TMapRakuPaintStyle;
  Offset: Single;
  RotationDegrees: Single;
  StartPoint: TPoint;
  Value: TPointF;
begin
  Result := FDragKind <> slgdkNone;
  if not Result then
    Exit(CursorAt(X, Y) <> crDefault);
  if (FDragLayer = nil) or
    not TryGetMapRakuLayerPaintGeometry(FDragLayer, Bounds,
      RotationDegrees) or
    SameValue(Bounds.Width, 0.0) or SameValue(Bounds.Height, 0.0) then
    Exit;
  if FDragKind = slgdkPendingLine then
  begin
    if Hypot(X - FDragStartMouse.X, Y - FDragStartMouse.Y) <
      GRADIENT_DRAG_THRESHOLD then
      Exit;
    FDragKind := slgdkLine;
    BeginInteractiveUpdate;
  end;
  NewStyle := FDragOldStyle;
  case FDragKind of
    slgdkAspect:
    begin
      if not GuidePointsForStyle(FDragLayer, FDragOldStyle, StartPoint, EndPoint) then
        Exit;
      Offset := Sqr(EndPoint.X - StartPoint.X) + Sqr(EndPoint.Y - StartPoint.Y);
      if Offset < 1 then
        Exit;
      NewStyle.GradientAspect := EnsureRange(Abs((X - StartPoint.X) * (StartPoint.Y - EndPoint.Y) +
        (Y - StartPoint.Y) * (EndPoint.X - StartPoint.X)) / Offset, 0.01, 100.0);
    end;
    slgdkLine:
    begin
      Value := TPointF.Create(
        (X - FDragStartMouse.X) / Max(FZoom, 0.001) / Bounds.Width,
        (Y - FDragStartMouse.Y) / Max(FZoom, 0.001) / Bounds.Height);
      if not SameValue(RotationDegrees, 0.0) then
      begin
        Value := RotatePointAround(TPointF.Create(
          (X - FDragStartMouse.X) / Max(FZoom, 0.001),
          (Y - FDragStartMouse.Y) / Max(FZoom, 0.001)),
          TPointF.Zero, -RotationDegrees);
        Value := TPointF.Create(Value.X / Bounds.Width,
          Value.Y / Bounds.Height);
      end;
      NewStyle.LinearStart := TPointF.Create(
        FDragOldStyle.LinearStart.X + Value.X,
        FDragOldStyle.LinearStart.Y + Value.Y);
      NewStyle.LinearEnd := TPointF.Create(
        FDragOldStyle.LinearEnd.X + Value.X,
        FDragOldStyle.LinearEnd.Y + Value.Y);
    end;
    slgdkStartPoint, slgdkEndPoint:
    begin
      Value := TPointF.Create(
        ScreenToLogicalX(X, FCanvasBounds, FZoom,
          FDocument.CanvasLayer.Width),
        ScreenToLogicalY(Y, FCanvasBounds, FZoom,
          FDocument.CanvasLayer.Height));
      if not SameValue(RotationDegrees, 0.0) then
        Value := RotatePointAround(Value, Bounds.CenterPoint,
          -RotationDegrees);
      Value := TPointF.Create((Value.X - Bounds.Left) / Bounds.Width,
        (Value.Y - Bounds.Top) / Bounds.Height);
      if FDragKind = slgdkStartPoint then
      begin
        if NewStyle.GradientKind <> slgkLinear then
          NewStyle.LinearEnd := TPointF.Create(FDragOldStyle.LinearEnd.X + Value.X -
            FDragOldStyle.LinearStart.X, FDragOldStyle.LinearEnd.Y + Value.Y - FDragOldStyle.LinearStart.Y);
        NewStyle.LinearStart := Value;
      end
      else
        NewStyle.LinearEnd := Value;
    end;
    slgdkMiddlePoint:
    begin
      if not GuidePointsForStyle(FDragLayer, FDragOldStyle,
        StartPoint, EndPoint) then
        Exit;
      Offset := ProjectOffset(X, Y, StartPoint, EndPoint);
      if not NewStyle.MoveGradientStop(FDragStopId, Offset) then
        Exit;
    end;
  end;
  if NewStyle.SameAs(FDragLayer.PaintStyle) then
    Exit;
  FDragLayer.PaintStyle := NewStyle;
  FDocument.Changed;
end;

function TMapRakuGradientInteraction.MouseUp(X, Y: Integer): Boolean;
var
  NewStyle: TMapRakuPaintStyle;
begin
  Result := FDragKind <> slgdkNone;
  if not Result then
    Exit;
  if FDragKind = slgdkPendingLine then
  begin
    AddStopAt(FDragLayer, X, Y);
    ClearDrag;
    Exit;
  end;
  NewStyle := FDragLayer.PaintStyle;
  if not FDragOldStyle.SameAs(NewStyle) then
    RecordAppliedStyleCommand(FDragLayer, FDragOldStyle, NewStyle);
  ClearDrag;
  EndInteractiveUpdate;
end;

function TMapRakuGradientInteraction.ProjectOffset(X, Y: Integer;
  const StartPoint, EndPoint: TPoint): Single;
var
  DX: Single;
  DY: Single;
begin
  DX := EndPoint.X - StartPoint.X;
  DY := EndPoint.Y - StartPoint.Y;
  if SameValue(DX, 0.0) and SameValue(DY, 0.0) then
    Exit(0.5);
  Result := EnsureRange(((X - StartPoint.X) * DX +
    (Y - StartPoint.Y) * DY) / (DX * DX + DY * DY), 0.0, 1.0);
end;

procedure TMapRakuGradientInteraction.RecordAppliedStyleCommand(
  Layer: TVectArtLayer; const OldStyle,
  NewStyle: TMapRakuPaintStyle);
var
  Command: TMapRakuSetLayerPaintStyleCommand;
begin
  Command := TMapRakuSetLayerPaintStyleCommand.Create(FDocument,
    Layer, OldStyle, NewStyle);
  if FEditHistory <> nil then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
end;

function TMapRakuGradientInteraction.StopPoint(Offset: Single;
  const StartPoint, EndPoint: TPoint): TPoint;
begin
  Result := Point(
    Round(StartPoint.X + (EndPoint.X - StartPoint.X) * Offset),
    Round(StartPoint.Y + (EndPoint.Y - StartPoint.Y) * Offset));
end;

function TMapRakuGradientInteraction.ToScreenX(Value: Single): Integer;
begin
  Result := LogicalToScreenX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TMapRakuGradientInteraction.ToScreenY(Value: Single): Integer;
begin
  Result := LogicalToScreenY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TMapRakuGradientInteraction.TryGetGuidePoints(
  out StartPoint, EndPoint: TPoint): Boolean;
var
  Layer: TVectArtLayer;
begin
  Result := ActiveLayer(Layer) and
    GuidePointsForStyle(Layer, Layer.PaintStyle, StartPoint, EndPoint);
end;

end.
