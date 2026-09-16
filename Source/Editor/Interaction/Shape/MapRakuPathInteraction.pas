// 単一Pathの頂点選択、区間分割、ベジェハンドル操作と表示用幾何を管理する。
unit MapRakuPathInteraction;

interface

uses
  System.Classes, System.Types, Vcl.Controls, MapRakuDocument,
  MapRakuEditHistory, MapRakuShapeInteraction;

type
  TMapRakuPathWidthHandleSide = (slwhNone, slwhLeft, slwhRight);

  TMapRakuPathWidthHandle = record
    PointIndex: Integer; // WidthPoints内の編集対象番号。
    CenterPoint: TPoint; // 中心Path上の幅点位置。
    LeftPoint: TPoint;   // 進行方向左側の幅倍率ハンドル。
    RightPoint: TPoint;  // 進行方向右側の幅倍率ハンドル。
    CenterRect: TRect;   // 幅点の削除操作に使う中心範囲。
    LeftRect: TRect;     // 左幅のドラッグ範囲。
    RightRect: TRect;    // 右幅のドラッグ範囲。
  end;

  TMapRakuPathInteraction = class
  private
    FCanvasBounds: TRect;
    FDocument: TVectArtDocument;
    FDragBezierHandle: TMapRakuBezierHandleKind;
    FDragLayerIndex: Integer;
    FDragStartVertices: TArray<TMapRakuVertex>;
    FDragStartWidthPoints: TArray<TMapRakuStrokeWidthPoint>;
    FDragVertexIndex: Integer;
    FDragWidthPointIndex: Integer;
    FDragWidthSide: TMapRakuPathWidthHandleSide;
    FEditHistory: TVectArtEditHistory;
    FSelectedLayerIndex: Integer;
    FSelectedVertexIndex: Integer;
    FZoom: Single;
    procedure ApplySelectedVertexKind(Kind: TMapRakuVertexKind);
    function HitTestBezierHandle(X, Y: Integer;
      out HandleKind: TMapRakuBezierHandleKind): Boolean;
    function HitTestSegment(X, Y: Integer; out SegmentIndex: Integer;
      out Parameter: Single): Boolean;
    function HitTestVertex(X, Y: Integer; out VertexIndex: Integer): Boolean;
    function HitTestVertexKindButton(X, Y: Integer;
      out Kind: TMapRakuVertexKind): Boolean;
    function HitTestWidthHandle(X, Y: Integer; out PointIndex: Integer;
      out Side: TMapRakuPathWidthHandleSide): Boolean;
    function SelectedPathLayer(out PathLayer: TVectArtLayer): Boolean;
    function SelectedVariablePath(out PathLayer: TVectArtPathLayer): Boolean;
    function WidthPointFrame(PointIndex: Integer; out Center,
      Normal: TPointF): Boolean;
    function ToLogicalX(Value: Single): Single;
    function ToLogicalY(Value: Single): Single;
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
  public
    // 選択を持たない入力管理オブジェクトを生成する。
    constructor Create;
    // 操作対象、履歴、表示座標変換に必要な現在のキャンバス状態を設定する。
    procedure Configure(ADocument: TVectArtDocument;
      AEditHistory: TVectArtEditHistory; const ACanvasBounds: TRect;
      AZoom: Single);
    // 選択頂点と進行中の頂点ドラッグを破棄する。
    procedure ClearSelection;
    // 頂点ドラッグの前後差分を1件のUndo履歴として確定する。
    procedure CommitDrag;
    // 履歴を追加せず、進行中のドラッグ状態だけを終了する。
    procedure EndDrag;
    // 指定位置の頂点を削除し、成功時はUndo履歴へ記録する。
    function DeleteVertexAt(X, Y: Integer): Boolean;
    // 選択中の頂点に命中した場合だけ削除し、変更をUndo履歴へ記録する。
    function DeleteSelectedVertexAt(X, Y: Integer): Boolean;
    // 指定位置の頂点種別ボタンを適用し、成功時はUndo履歴へ記録する。
    function ApplyVertexKindAt(X, Y: Integer): Boolean;
    // 指定位置のベジェ制御点を捕捉し、ドラッグを開始できた場合にTrueを返す。
    function BeginBezierHandleDragAt(X, Y: Integer): Boolean;
    // 指定位置のアンカーを選択し、ドラッグを開始できた場合にTrueを返す。
    function BeginVertexDragAt(X, Y: Integer): Boolean;
    // 可変幅Pathの左右ハンドルを捕捉し、幅倍率のドラッグを開始する。
    function BeginWidthHandleDragAt(X, Y: Integer): Boolean;
    // 指定位置に最も近い区間を分割し、成功時はUndo履歴へ記録する。
    function InsertVertexAt(X, Y: Integer): Boolean;
    // 中心線上へ現在幅を補間した幅点を追加する。
    function InsertWidthPointAt(X, Y: Integer): Boolean;
    // 両端以外の中心ハンドルにある幅点を削除する。
    function DeleteWidthPointAt(X, Y: Integer): Boolean;
    // Path編集要素に対応するカーソルがあればCursorへ設定してTrueを返す。
    function CursorAt(X, Y: Integer; out Cursor: TCursor): Boolean;
    // 進行中のアンカーまたは制御点ドラッグをDocumentへ反映する。
    function DragTo(Shift: TShiftState; X, Y: Integer): Boolean;
    // 捕捉中の左右幅倍率を現在位置へ更新する。
    function DragWidthTo(X, Y: Integer): Boolean;
    // ドラッグ中のアンカー以外にある同一Path内の吸着候補を返す。
    function OtherDragVertexPositions: TArray<TPointF>;
    // 選択中Pathの全アンカーを画面座標の矩形列として返す。
    function SelectedVertexRects: TArray<TRect>;
    // 選択中Pathを直線・ベジェ共通の画面座標点列へ展開して返す。
    function SelectedPathPoints: TArray<TPoint>;
    // 選択中の可変幅Pathについて中心、左、右の編集ハンドルを返す。
    function SelectedWidthHandles: TArray<TMapRakuPathWidthHandle>;
    // 幅ハンドルに対応するカーソルがあればCursorへ設定する。
    function WidthCursorAt(X, Y: Integer; out Cursor: TCursor): Boolean;
    // 選択アンカーの外側へ表示する鋭角／ベジェ種別ボタンを返す。
    function SelectedVertexKindButtons:
      TArray<TMapRakuVertexKindButton>;
    // 選択アンカーの現在の鋭角／ベジェ種別を返す。
    function SelectedVertexKind(out Kind: TMapRakuVertexKind): Boolean;
    // 選択アンカーへ鋭角／ベジェ種別を適用し、対象があればTrueを返す。
    function SetSelectedVertexKind(
      Kind: TMapRakuVertexKind): Boolean;
    // 現在選択しているアンカーの画面範囲を返す。
    function SelectedVertexRect(out VertexRect: TRect): Boolean;
    // 選択中のベジェ頂点について、接線と両側の制御ハンドルを返す。
    function SelectedBezierHandles(
      out Handles: TMapRakuBezierHandles): Boolean;
  end;

implementation

uses
  System.Math, MapRakuEditCommands, MapRakuGeometry,
  MapRakuShapeEditCommands, MapRakuPathOperations;

const
  VERTEX_HANDLE_SIZE           = 9;
  BEZIER_VERTEX_HIT_PADDING    = 6;
  BEZIER_CONTROL_HANDLE_SIZE   = 9;
  VERTEX_KIND_BUTTON_GAP       = 4;
  VERTEX_KIND_BUTTON_OFFSET    = 34;
  VERTEX_KIND_BUTTON_SIZE      = 22;
  SEGMENT_HIT_DISTANCE         = 6.0;
  BEZIER_HIT_SUBDIVISIONS      = 32;
  WIDTH_HANDLE_SIZE            = 9;
  WIDTH_CENTER_HANDLE_SIZE     = 7;

function PolylineFrameAtOffset(const Points: TArray<TPointF>;
  Offset: Single; out Center, Normal: TPointF): Boolean;
var
  Distance: Single;
  I: Integer;
  Ratio: Single;
  SegmentLength: Single;
  TargetDistance: Single;
  TotalLength: Single;
begin
  Result := False;
  Center := TPointF.Zero;
  Normal := TPointF.Zero;
  if Length(Points) < 2 then
    Exit;
  TotalLength := 0;
  for I := 0 to High(Points) - 1 do
    TotalLength := TotalLength + Hypot(Points[I + 1].X - Points[I].X,
      Points[I + 1].Y - Points[I].Y);
  if TotalLength <= 0.0001 then
    Exit;
  TargetDistance := EnsureRange(Offset, 0.0, 1.0) * TotalLength;
  Distance := 0;
  for I := 0 to High(Points) - 1 do
  begin
    SegmentLength := Hypot(Points[I + 1].X - Points[I].X,
      Points[I + 1].Y - Points[I].Y);
    if SegmentLength <= 0.0001 then
      Continue;
    if (Distance + SegmentLength >= TargetDistance) or
      (I = High(Points) - 1) then
    begin
      Ratio := EnsureRange((TargetDistance - Distance) / SegmentLength,
        0.0, 1.0);
      Center := TPointF.Create(
        Points[I].X + (Points[I + 1].X - Points[I].X) * Ratio,
        Points[I].Y + (Points[I + 1].Y - Points[I].Y) * Ratio);
      Normal := TPointF.Create(
        -(Points[I + 1].Y - Points[I].Y) / SegmentLength,
        (Points[I + 1].X - Points[I].X) / SegmentLength);
      Exit(True);
    end;
    Distance := Distance + SegmentLength;
  end;
end;

function WidthPointsEqual(const A,
  B: TArray<TMapRakuStrokeWidthPoint>): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
    Exit;
  for I := 0 to High(A) do
    if not SameValue(A[I].Offset, B[I].Offset) or
      not SameValue(A[I].LeftScale, B[I].LeftScale) or
      not SameValue(A[I].RightScale, B[I].RightScale) then
      Exit(False);
end;

procedure WidthScalesAt(const Points: TArray<TMapRakuStrokeWidthPoint>;
  Offset: Single; out LeftScale, RightScale: Single);
var
  I: Integer;
  Ratio: Single;
begin
  LeftScale := 1;
  RightScale := 1;
  if Length(Points) < 2 then
    Exit;
  I := 0;
  while (I < High(Points) - 1) and (Offset > Points[I + 1].Offset) do
    Inc(I);
  if Points[I + 1].Offset <= Points[I].Offset then
    Ratio := 0
  else
    Ratio := EnsureRange((Offset - Points[I].Offset) /
      (Points[I + 1].Offset - Points[I].Offset), 0.0, 1.0);
  LeftScale := Points[I].LeftScale +
    (Points[I + 1].LeftScale - Points[I].LeftScale) * Ratio;
  RightScale := Points[I].RightScale +
    (Points[I + 1].RightScale - Points[I].RightScale) * Ratio;
end;

function DistanceToSegmentParameter(const PointValue, StartPoint,
  EndPoint: TPointF; out Parameter: Single): Single;
var
  DX: Single;
  DY: Single;
  Projection: Single;
  SegmentLengthSquared: Single;
begin
  DX := EndPoint.X - StartPoint.X;
  DY := EndPoint.Y - StartPoint.Y;
  SegmentLengthSquared := DX * DX + DY * DY;
  if SegmentLengthSquared > 0 then
    Projection := EnsureRange(((PointValue.X - StartPoint.X) * DX +
      (PointValue.Y - StartPoint.Y) * DY) / SegmentLengthSquared, 0.0, 1.0)
  else
    Projection := 0;
  Result := Hypot(PointValue.X - (StartPoint.X + Projection * DX),
    PointValue.Y - (StartPoint.Y + Projection * DY));
  Parameter := Projection;
end;

function CubicBezierPoint(const StartPoint, Control1, Control2,
  EndPoint: TPointF; Parameter: Single): TPointF;
var
  Inverse: Single;
begin
  Inverse := 1 - Parameter;
  Result := TPointF.Create(
    Inverse * Inverse * Inverse * StartPoint.X +
      3 * Inverse * Inverse * Parameter * Control1.X +
      3 * Inverse * Parameter * Parameter * Control2.X +
      Parameter * Parameter * Parameter * EndPoint.X,
    Inverse * Inverse * Inverse * StartPoint.Y +
      3 * Inverse * Inverse * Parameter * Control1.Y +
      3 * Inverse * Parameter * Parameter * Control2.Y +
      Parameter * Parameter * Parameter * EndPoint.Y);
end;

constructor TMapRakuPathInteraction.Create;
begin
  inherited Create;
  FSelectedLayerIndex := -1;
  ClearSelection;
  EndDrag;
end;

procedure TMapRakuPathInteraction.Configure(
  ADocument: TVectArtDocument; AEditHistory: TVectArtEditHistory;
  const ACanvasBounds: TRect; AZoom: Single);
var
  SelectedLayerIndex: Integer;
begin
  SelectedLayerIndex := -1;
  if (ADocument <> nil) and (ADocument.SelectionCount = 1) then
    SelectedLayerIndex := ADocument.SelectedIndex;
  if (ADocument <> FDocument) or
    (SelectedLayerIndex <> FSelectedLayerIndex) then
    ClearSelection;
  FDocument := ADocument;
  FEditHistory := AEditHistory;
  FCanvasBounds := ACanvasBounds;
  FZoom := AZoom;
  FSelectedLayerIndex := SelectedLayerIndex;
end;

procedure TMapRakuPathInteraction.ClearSelection;
begin
  FSelectedVertexIndex := -1;
end;

function TMapRakuPathInteraction.SelectedPathLayer(
  out PathLayer: TVectArtLayer): Boolean;
begin
  PathLayer := nil;
  Result := (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    FDocument[FDocument.SelectedIndex].SupportsPathEditing;
  if Result then
  begin
    PathLayer := FDocument[FDocument.SelectedIndex];
    Result := not PathLayer.Locked;
  end;
end;

function TMapRakuPathInteraction.SelectedVariablePath(
  out PathLayer: TVectArtPathLayer): Boolean;
var
  Layer: TVectArtLayer;
begin
  PathLayer := nil;
  Result := SelectedPathLayer(Layer) and (Layer is TVectArtPathLayer) and
    not TVectArtPathLayer(Layer).Closed and
    (Length(TVectArtPathLayer(Layer).WidthPoints) >= 2);
  if Result then
    PathLayer := TVectArtPathLayer(Layer);
end;

function TMapRakuPathInteraction.WidthPointFrame(PointIndex: Integer;
  out Center, Normal: TPointF): Boolean;
var
  LogicalPoints: TArray<TPointF>;
  PathLayer: TVectArtPathLayer;
  WidthPoints: TArray<TMapRakuStrokeWidthPoint>;
begin
  Result := SelectedVariablePath(PathLayer);
  if not Result then
    Exit;
  WidthPoints := PathLayer.WidthPoints;
  if not InRange(PointIndex, 0, High(WidthPoints)) then
    Exit(False);
  LogicalPoints := FlattenMapRakuPathVertices(PathLayer.Vertices);
  Result := PolylineFrameAtOffset(LogicalPoints,
    WidthPoints[PointIndex].Offset, Center, Normal);
end;

function TMapRakuPathInteraction.ToLogicalX(Value: Single): Single;
begin
  Result := ScreenToLogicalX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TMapRakuPathInteraction.ToLogicalY(Value: Single): Single;
begin
  Result := ScreenToLogicalY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TMapRakuPathInteraction.ToScreenX(Value: Single): Integer;
begin
  Result := LogicalToScreenX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TMapRakuPathInteraction.ToScreenY(Value: Single): Integer;
begin
  Result := LogicalToScreenY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TMapRakuPathInteraction.HitTestVertex(X, Y: Integer;
  out VertexIndex: Integer): Boolean;
var
  CandidateDistance: Single;
  CenterX: Integer;
  CenterY: Integer;
  HalfSize: Integer;
  HandleRect: TRect;
  I: Integer;
  NearestDistance: Single;
  PathLayer: TVectArtLayer;
  Vertices: TArray<TMapRakuVertex>;
begin
  Result := False;
  VertexIndex := -1;
  if not SelectedPathLayer(PathLayer) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  HalfSize := VERTEX_HANDLE_SIZE div 2;
  NearestDistance := MaxSingle;
  for I := 0 to High(Vertices) do
  begin
    CenterX := ToScreenX(Vertices[I].Position.X);
    CenterY := ToScreenY(Vertices[I].Position.Y);
    HandleRect := Rect(CenterX - HalfSize, CenterY - HalfSize,
      CenterX - HalfSize + VERTEX_HANDLE_SIZE,
      CenterY - HalfSize + VERTEX_HANDLE_SIZE);
    if Vertices[I].Kind = slvkBezier then
      InflateRect(HandleRect, BEZIER_VERTEX_HIT_PADDING,
        BEZIER_VERTEX_HIT_PADDING);
    if PtInRect(HandleRect, Point(X, Y)) then
    begin
      CandidateDistance := Sqr(X - CenterX) + Sqr(Y - CenterY);
      if CandidateDistance < NearestDistance then
      begin
        NearestDistance := CandidateDistance;
        VertexIndex := I;
        Result := True;
      end;
    end;
  end;
end;

function TMapRakuPathInteraction.HitTestVertexKindButton(X,
  Y: Integer; out Kind: TMapRakuVertexKind): Boolean;
var
  ButtonInfo: TMapRakuVertexKindButton;
begin
  Result := False;
  Kind := slvkSharp;
  for ButtonInfo in SelectedVertexKindButtons do
    if PtInRect(ButtonInfo.Bounds, Point(X, Y)) then
    begin
      Kind := ButtonInfo.Kind;
      Exit(True);
    end;
end;

function TMapRakuPathInteraction.HitTestBezierHandle(X, Y: Integer;
  out HandleKind: TMapRakuBezierHandleKind): Boolean;
var
  Handles: TMapRakuBezierHandles;
  VertexRect: TRect;
begin
  Result := False;
  HandleKind := slbhNone;
  if not SelectedBezierHandles(Handles) then
    Exit;
  HandleKind := MapRakuBezierHandleAt(Handles, Point(X, Y));
  if (HandleKind <> slbhNone) and
    (((HandleKind = slbhIncoming) and
      not PtInRect(Handles.IncomingRect, Point(X, Y))) or
     ((HandleKind = slbhOutgoing) and
      not PtInRect(Handles.OutgoingRect, Point(X, Y)))) and
    SelectedVertexRect(VertexRect) and PtInRect(VertexRect, Point(X, Y)) then
    HandleKind := slbhNone;
  Result := HandleKind <> slbhNone;
end;

function TMapRakuPathInteraction.HitTestSegment(X, Y: Integer;
  out SegmentIndex: Integer; out Parameter: Single): Boolean;
var
  BestDistance: Single;
  Control1: TPointF;
  Control2: TPointF;
  CurrentDistance: Single;
  CurrentParameter: Single;
  EndParameter: Single;
  EndPoint: TPointF;
  I: Integer;
  LocalParameter: Single;
  MousePoint: TPointF;
  PathLayer: TVectArtLayer;
  StartParameter: Single;
  StartPoint: TPointF;
  SubdivisionEnd: TPointF;
  SubdivisionIndex: Integer;
  SubdivisionStart: TPointF;
  Vertices: TArray<TMapRakuVertex>;
begin
  Result := False;
  SegmentIndex := -1;
  Parameter := 0;
  if not SelectedPathLayer(PathLayer) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  MousePoint := TPointF.Create(X, Y);
  BestDistance := 1.0E30;
  for I := 0 to High(Vertices) - 1 do
  begin
    StartPoint := TPointF.Create(ToScreenX(Vertices[I].Position.X),
      ToScreenY(Vertices[I].Position.Y));
    EndPoint := TPointF.Create(ToScreenX(Vertices[I + 1].Position.X),
      ToScreenY(Vertices[I + 1].Position.Y));
    if Vertices[I].OutgoingSegment = slskLine then
    begin
      CurrentDistance := DistanceToSegmentParameter(MousePoint,
        StartPoint, EndPoint, CurrentParameter);
      if CurrentDistance < BestDistance then
      begin
        BestDistance := CurrentDistance;
        SegmentIndex := I;
        Parameter := CurrentParameter;
      end;
      Continue;
    end;
    Control1 := TPointF.Create(ToScreenX(Vertices[I].Position.X +
      Vertices[I].OutgoingControl.X), ToScreenY(Vertices[I].Position.Y +
      Vertices[I].OutgoingControl.Y));
    Control2 := TPointF.Create(ToScreenX(Vertices[I + 1].Position.X +
      Vertices[I + 1].IncomingControl.X),
      ToScreenY(Vertices[I + 1].Position.Y +
      Vertices[I + 1].IncomingControl.Y));
    for SubdivisionIndex := 0 to BEZIER_HIT_SUBDIVISIONS - 1 do
    begin
      StartParameter := SubdivisionIndex / BEZIER_HIT_SUBDIVISIONS;
      EndParameter := (SubdivisionIndex + 1) / BEZIER_HIT_SUBDIVISIONS;
      SubdivisionStart := CubicBezierPoint(StartPoint, Control1, Control2,
        EndPoint, StartParameter);
      SubdivisionEnd := CubicBezierPoint(StartPoint, Control1, Control2,
        EndPoint, EndParameter);
      CurrentDistance := DistanceToSegmentParameter(MousePoint,
        SubdivisionStart, SubdivisionEnd, LocalParameter);
      if CurrentDistance < BestDistance then
      begin
        BestDistance := CurrentDistance;
        SegmentIndex := I;
        Parameter := (SubdivisionIndex + LocalParameter) /
          BEZIER_HIT_SUBDIVISIONS;
      end;
    end;
  end;
  Result := BestDistance <= SEGMENT_HIT_DISTANCE;
  if not Result then
  begin
    SegmentIndex := -1;
    Parameter := 0;
  end;
end;

procedure TMapRakuPathInteraction.ApplySelectedVertexKind(
  Kind: TMapRakuVertexKind);
var
  NewVertices: TArray<TMapRakuVertex>;
  OldVertices: TArray<TMapRakuVertex>;
  PathLayer: TVectArtLayer;
begin
  if not SelectedPathLayer(PathLayer) or (FSelectedVertexIndex < 0) then
    Exit;
  OldVertices := PathLayer.EditablePathVertices;
  if (FSelectedVertexIndex > High(OldVertices)) or
    (OldVertices[FSelectedVertexIndex].Kind = Kind) then
    Exit;
  NewVertices := CloneMapRakuPathVertices(OldVertices);
  SetMapRakuPathVertexKind(NewVertices, FSelectedVertexIndex, Kind);
  ApplyMapRakuPathVertices(FDocument, FDocument.SelectedIndex,
    NewVertices, True);
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuPathVerticesCommand.Create(
      FDocument, FDocument.SelectedIndex, OldVertices, NewVertices, True));
end;

function TMapRakuPathInteraction.ApplyVertexKindAt(X,
  Y: Integer): Boolean;
var
  Kind: TMapRakuVertexKind;
begin
  Result := HitTestVertexKindButton(X, Y, Kind);
  if Result then
    ApplySelectedVertexKind(Kind);
end;

function TMapRakuPathInteraction.InsertVertexAt(X,
  Y: Integer): Boolean;
var
  NewVertexIndex: Integer;
  NewVertices: TArray<TMapRakuVertex>;
  OldVertices: TArray<TMapRakuVertex>;
  Parameter: Single;
  PathLayer: TVectArtLayer;
  SegmentIndex: Integer;
begin
  Result := HitTestSegment(X, Y, SegmentIndex, Parameter);
  if not Result or not SelectedPathLayer(PathLayer) then
    Exit;
  OldVertices := PathLayer.EditablePathVertices;
  NewVertices := CloneMapRakuPathVertices(OldVertices);
  NewVertexIndex := InsertMapRakuPathVertex(NewVertices, SegmentIndex,
    Parameter);
  if NewVertexIndex < 0 then
    Exit(False);
  ApplyMapRakuPathVertices(FDocument, FDocument.SelectedIndex,
    NewVertices, True);
  FSelectedVertexIndex := NewVertexIndex;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuPathVerticesCommand.Create(
      FDocument, FDocument.SelectedIndex, OldVertices, NewVertices, True));
end;

function TMapRakuPathInteraction.DeleteSelectedVertexAt(X, Y: Integer): Boolean;
var
  VertexIndex: Integer;
begin
  Result := HitTestVertex(X, Y, VertexIndex) and
    (VertexIndex = FSelectedVertexIndex);
  if Result then
    Result := DeleteVertexAt(X, Y);
end;

function TMapRakuPathInteraction.DeleteVertexAt(X,
  Y: Integer): Boolean;
var
  NewVertices: TArray<TMapRakuVertex>;
  OldVertices: TArray<TMapRakuVertex>;
  PathLayer: TVectArtLayer;
  VertexIndex: Integer;
begin
  Result := HitTestVertex(X, Y, VertexIndex);
  if not Result or not SelectedPathLayer(PathLayer) then
    Exit;
  OldVertices := PathLayer.EditablePathVertices;
  NewVertices := CloneMapRakuPathVertices(OldVertices);
  if not DeleteMapRakuPathVertex(NewVertices, VertexIndex) then
    Exit;
  ApplyMapRakuPathVertices(FDocument, FDocument.SelectedIndex,
    NewVertices, True);
  ClearSelection;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuPathVerticesCommand.Create(
      FDocument, FDocument.SelectedIndex, OldVertices, NewVertices, True));
end;

function TMapRakuPathInteraction.BeginBezierHandleDragAt(X,
  Y: Integer): Boolean;
var
  HandleKind: TMapRakuBezierHandleKind;
  PathLayer: TVectArtLayer;
begin
  Result := HitTestBezierHandle(X, Y, HandleKind) and
    SelectedPathLayer(PathLayer);
  if not Result then
    Exit;
  FDragBezierHandle := HandleKind;
  FDragVertexIndex := FSelectedVertexIndex;
  FDragLayerIndex := FDocument.SelectedIndex;
  FDragStartVertices := PathLayer.EditablePathVertices;
end;

function TMapRakuPathInteraction.BeginVertexDragAt(X,
  Y: Integer): Boolean;
var
  PathLayer: TVectArtLayer;
begin
  Result := HitTestVertex(X, Y, FDragVertexIndex) and
    SelectedPathLayer(PathLayer);
  if not Result then
    Exit;
  FSelectedVertexIndex := FDragVertexIndex;
  FDragLayerIndex := FDocument.SelectedIndex;
  FDragStartVertices := PathLayer.EditablePathVertices;
  FDragBezierHandle := slbhNone;
end;

function TMapRakuPathInteraction.DeleteWidthPointAt(X,
  Y: Integer): Boolean;
var
  Handle: TMapRakuPathWidthHandle;
  I: Integer;
  NewPoints: TArray<TMapRakuStrokeWidthPoint>;
  OldPoints: TArray<TMapRakuStrokeWidthPoint>;
  PathLayer: TVectArtPathLayer;
begin
  Result := False;
  if not SelectedVariablePath(PathLayer) then
    Exit;
  OldPoints := PathLayer.WidthPoints;
  for Handle in SelectedWidthHandles do
  begin
    if (Handle.PointIndex <= 0) or
      (Handle.PointIndex >= High(OldPoints)) or
      not PtInRect(Handle.CenterRect, Point(X, Y)) then
      Continue;
    SetLength(NewPoints, Length(OldPoints) - 1);
    for I := 0 to High(NewPoints) do
      if I < Handle.PointIndex then
        NewPoints[I] := OldPoints[I]
      else
        NewPoints[I] := OldPoints[I + 1];
    FDocument.SetPathWidthPoints(FDocument.SelectedIndex, NewPoints);
    if FEditHistory <> nil then
      FEditHistory.AddApplied(TMapRakuPathWidthPointsCommand.Create(
        FDocument, FDocument.SelectedIndex, OldPoints, NewPoints));
    Exit(True);
  end;
end;

function TMapRakuPathInteraction.InsertWidthPointAt(X,
  Y: Integer): Boolean;
var
  BestDistance: Single;
  BestOffset: Single;
  CurrentDistance: Single;
  I: Integer;
  InsertIndex: Integer;
  LeftScale: Single;
  LocalParameter: Single;
  LogicalLength: Single;
  LogicalPoints: TArray<TPointF>;
  NewPoints: TArray<TMapRakuStrokeWidthPoint>;
  OldPoints: TArray<TMapRakuStrokeWidthPoint>;
  PathLayer: TVectArtPathLayer;
  RightScale: Single;
  SegmentLength: Single;
  StartDistance: Single;
  TotalLength: Single;
begin
  Result := False;
  if not SelectedVariablePath(PathLayer) then
    Exit;
  LogicalPoints := FlattenMapRakuPathVertices(PathLayer.Vertices);
  if Length(LogicalPoints) < 2 then
    Exit;
  TotalLength := 0;
  for I := 0 to High(LogicalPoints) - 1 do
    TotalLength := TotalLength + Hypot(
      LogicalPoints[I + 1].X - LogicalPoints[I].X,
      LogicalPoints[I + 1].Y - LogicalPoints[I].Y);
  if TotalLength <= 0.0001 then
    Exit;
  BestDistance := MaxSingle;
  BestOffset := 0;
  StartDistance := 0;
  for I := 0 to High(LogicalPoints) - 1 do
  begin
    SegmentLength := Hypot(LogicalPoints[I + 1].X - LogicalPoints[I].X,
      LogicalPoints[I + 1].Y - LogicalPoints[I].Y);
    CurrentDistance := DistanceToSegmentParameter(TPointF.Create(X, Y),
      TPointF.Create(ToScreenX(LogicalPoints[I].X),
        ToScreenY(LogicalPoints[I].Y)),
      TPointF.Create(ToScreenX(LogicalPoints[I + 1].X),
        ToScreenY(LogicalPoints[I + 1].Y)), LocalParameter);
    if CurrentDistance < BestDistance then
    begin
      BestDistance := CurrentDistance;
      LogicalLength := StartDistance + SegmentLength * LocalParameter;
      BestOffset := LogicalLength / TotalLength;
    end;
    StartDistance := StartDistance + SegmentLength;
  end;
  if (BestDistance > SEGMENT_HIT_DISTANCE) or
    (BestOffset <= 0.005) or (BestOffset >= 0.995) then
    Exit;
  OldPoints := PathLayer.WidthPoints;
  InsertIndex := 1;
  while (InsertIndex < Length(OldPoints)) and
    (OldPoints[InsertIndex].Offset < BestOffset) do
    Inc(InsertIndex);
  if (InsertIndex < Length(OldPoints)) and
    (Abs(OldPoints[InsertIndex].Offset - BestOffset) <= 0.005) then
    Exit;
  WidthScalesAt(OldPoints, BestOffset, LeftScale, RightScale);
  SetLength(NewPoints, Length(OldPoints) + 1);
  for I := 0 to High(NewPoints) do
    if I < InsertIndex then
      NewPoints[I] := OldPoints[I]
    else if I = InsertIndex then
    begin
      NewPoints[I].Offset := BestOffset;
      NewPoints[I].LeftScale := LeftScale;
      NewPoints[I].RightScale := RightScale;
    end
    else
      NewPoints[I] := OldPoints[I - 1];
  FDocument.SetPathWidthPoints(FDocument.SelectedIndex, NewPoints);
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuPathWidthPointsCommand.Create(
      FDocument, FDocument.SelectedIndex, OldPoints, NewPoints));
  Result := True;
end;

function TMapRakuPathInteraction.BeginWidthHandleDragAt(X,
  Y: Integer): Boolean;
var
  PathLayer: TVectArtPathLayer;
begin
  Result := HitTestWidthHandle(X, Y, FDragWidthPointIndex,
    FDragWidthSide) and SelectedVariablePath(PathLayer);
  if not Result then
    Exit;
  FDragLayerIndex := FDocument.SelectedIndex;
  FDragStartWidthPoints := PathLayer.WidthPoints;
end;

function TMapRakuPathInteraction.DragWidthTo(X, Y: Integer): Boolean;
var
  Center: TPointF;
  MousePoint: TPointF;
  Normal: TPointF;
  PathLayer: TVectArtPathLayer;
  Scale: Single;
  WidthPoints: TArray<TMapRakuStrokeWidthPoint>;
begin
  Result := (FDragLayerIndex > 0) and
    (FDragWidthSide <> slwhNone) and
    (FDocument[FDragLayerIndex] is TVectArtPathLayer);
  if not Result then
    Exit;
  PathLayer := TVectArtPathLayer(FDocument[FDragLayerIndex]);
  WidthPoints := PathLayer.WidthPoints;
  if not InRange(FDragWidthPointIndex, 0, High(WidthPoints)) or
    not WidthPointFrame(FDragWidthPointIndex, Center, Normal) then
    Exit(False);
  MousePoint := TPointF.Create(ToLogicalX(X), ToLogicalY(Y));
  if FDragWidthSide = slwhLeft then
    Scale := ((MousePoint.X - Center.X) * Normal.X +
      (MousePoint.Y - Center.Y) * Normal.Y) /
      Max(PathLayer.StrokeWidth * 0.5, 0.05)
  else
    Scale := -((MousePoint.X - Center.X) * Normal.X +
      (MousePoint.Y - Center.Y) * Normal.Y) /
      Max(PathLayer.StrokeWidth * 0.5, 0.05);
  Scale := EnsureRange(Scale, 0.0, 1.0);
  if FDragWidthSide = slwhLeft then
    WidthPoints[FDragWidthPointIndex].LeftScale := Scale
  else
    WidthPoints[FDragWidthPointIndex].RightScale := Scale;
  FDocument.SetPathWidthPoints(FDragLayerIndex, WidthPoints);
end;

function TMapRakuPathInteraction.DragTo(Shift: TShiftState;
  X, Y: Integer): Boolean;
var
  Angle: Single;
  ControlLength: Single;
  ControlVector: TPointF;
  NewVertices: TArray<TMapRakuVertex>;
  OppositeLength: Single;
begin
  Result := (FDragLayerIndex > 0) and
    FDocument[FDragLayerIndex].SupportsPathEditing;
  if not Result then
    Exit;
  NewVertices := CloneMapRakuPathVertices(FDragStartVertices);
  if (FDragVertexIndex < 0) or
    (FDragVertexIndex > High(NewVertices)) then
    Exit;
  if FDragBezierHandle = slbhNone then
  begin
    NewVertices[FDragVertexIndex].Position := TPointF.Create(
      EnsureRange(ToLogicalX(X), FDocument.CanvasLayer.Width * -0.5,
        FDocument.CanvasLayer.Width * 0.5),
      EnsureRange(ToLogicalY(Y), FDocument.CanvasLayer.Height * -0.5,
        FDocument.CanvasLayer.Height * 0.5));
    ApplyMapRakuPathVertices(FDocument, FDragLayerIndex,
      NewVertices, True);
    Exit;
  end;
  with NewVertices[FDragVertexIndex] do
    ControlVector := TPointF.Create(ToLogicalX(X) - Position.X,
      ToLogicalY(Y) - Position.Y);
  ControlLength := Hypot(ControlVector.X, ControlVector.Y);
  if (ssShift in Shift) and (ControlLength > 0.001) then
  begin
    Angle := ArcTan2(ControlVector.Y, ControlVector.X);
    Angle := Round(Angle / (Pi / 12)) * (Pi / 12);
    ControlVector := TPointF.Create(Cos(Angle) * ControlLength,
      Sin(Angle) * ControlLength);
  end;
  if FDragBezierHandle = slbhIncoming then
  begin
    OppositeLength := Hypot(FDragStartVertices[
      FDragVertexIndex].OutgoingControl.X, FDragStartVertices[
      FDragVertexIndex].OutgoingControl.Y);
    NewVertices[FDragVertexIndex].IncomingControl := ControlVector;
    if ControlLength > 0.001 then
      NewVertices[FDragVertexIndex].OutgoingControl := TPointF.Create(
        -ControlVector.X / ControlLength * OppositeLength,
        -ControlVector.Y / ControlLength * OppositeLength);
  end
  else
  begin
    OppositeLength := Hypot(FDragStartVertices[
      FDragVertexIndex].IncomingControl.X, FDragStartVertices[
      FDragVertexIndex].IncomingControl.Y);
    NewVertices[FDragVertexIndex].OutgoingControl := ControlVector;
    if ControlLength > 0.001 then
      NewVertices[FDragVertexIndex].IncomingControl := TPointF.Create(
        -ControlVector.X / ControlLength * OppositeLength,
        -ControlVector.Y / ControlLength * OppositeLength);
  end;
  ApplyMapRakuPathVertices(FDocument, FDragLayerIndex,
    NewVertices, True);
end;

function TMapRakuPathInteraction.OtherDragVertexPositions:
  TArray<TPointF>;
var
  I: Integer;
begin
  Result := nil;
  if FDragBezierHandle <> slbhNone then
    Exit;
  for I := 0 to High(FDragStartVertices) do
    if I <> FDragVertexIndex then
      Result := Result + [FDragStartVertices[I].Position];
end;

procedure TMapRakuPathInteraction.CommitDrag;
var
  PathLayer: TVectArtLayer;
begin
  if (FEditHistory <> nil) and (FDragLayerIndex > 0) and
    (FDragWidthSide <> slwhNone) and
    (FDocument[FDragLayerIndex] is TVectArtPathLayer) then
  begin
    if not WidthPointsEqual(FDragStartWidthPoints,
      TVectArtPathLayer(FDocument[FDragLayerIndex]).WidthPoints) then
      FEditHistory.AddApplied(TMapRakuPathWidthPointsCommand.Create(
        FDocument, FDragLayerIndex, FDragStartWidthPoints,
        TVectArtPathLayer(FDocument[FDragLayerIndex]).WidthPoints));
    EndDrag;
    Exit;
  end;
  if (FEditHistory <> nil) and (FDragLayerIndex > 0) and
    FDocument[FDragLayerIndex].SupportsPathEditing then
  begin
    PathLayer := FDocument[FDragLayerIndex];
    if not MapRakuPathVerticesEqual(FDragStartVertices,
      PathLayer.EditablePathVertices) then
      FEditHistory.AddApplied(TMapRakuPathVerticesCommand.Create(
        FDocument, FDragLayerIndex, FDragStartVertices,
        PathLayer.EditablePathVertices, True));
  end;
  EndDrag;
end;

procedure TMapRakuPathInteraction.EndDrag;
begin
  FDragLayerIndex := -1;
  FDragVertexIndex := -1;
  FDragBezierHandle := slbhNone;
  FDragStartVertices := nil;
  FDragWidthPointIndex := -1;
  FDragWidthSide := slwhNone;
  FDragStartWidthPoints := nil;
end;

function TMapRakuPathInteraction.CursorAt(X, Y: Integer;
  out Cursor: TCursor): Boolean;
var
  HandleKind: TMapRakuBezierHandleKind;
  Parameter: Single;
  SegmentIndex: Integer;
  VertexIndex: Integer;
begin
  Cursor := crDefault;
  if HitTestBezierHandle(X, Y, HandleKind) or
    HitTestVertex(X, Y, VertexIndex) then
    Cursor := crSizeAll
  else if HitTestSegment(X, Y, SegmentIndex, Parameter) then
    Cursor := crCross;
  Result := Cursor <> crDefault;
end;

function TMapRakuPathInteraction.SelectedVertexKind(
  out Kind: TMapRakuVertexKind): Boolean;
var
  PathLayer: TVectArtLayer;
  Vertices: TArray<TMapRakuVertex>;
begin
  Kind := slvkSharp;
  Result := SelectedPathLayer(PathLayer) and
    (FSelectedVertexIndex >= 0);
  if not Result then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  Result := FSelectedVertexIndex <= High(Vertices);
  if Result then
    Kind := Vertices[FSelectedVertexIndex].Kind;
end;

function TMapRakuPathInteraction.SetSelectedVertexKind(
  Kind: TMapRakuVertexKind): Boolean;
var
  CurrentKind: TMapRakuVertexKind;
begin
  Result := SelectedVertexKind(CurrentKind);
  if Result and (CurrentKind <> Kind) then
    ApplySelectedVertexKind(Kind);
end;

function TMapRakuPathInteraction.SelectedVertexRects: TArray<TRect>;
var
  HalfSize: Integer;
  I: Integer;
  PathLayer: TVectArtLayer;
  Vertices: TArray<TMapRakuVertex>;
  X: Integer;
  Y: Integer;
begin
  Result := nil;
  if not SelectedPathLayer(PathLayer) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  SetLength(Result, Length(Vertices));
  HalfSize := VERTEX_HANDLE_SIZE div 2;
  for I := 0 to High(Vertices) do
  begin
    X := ToScreenX(Vertices[I].Position.X);
    Y := ToScreenY(Vertices[I].Position.Y);
    Result[I] := Rect(X - HalfSize, Y - HalfSize,
      X - HalfSize + VERTEX_HANDLE_SIZE,
      Y - HalfSize + VERTEX_HANDLE_SIZE);
  end;
end;

function TMapRakuPathInteraction.SelectedPathPoints: TArray<TPoint>;
var
  I: Integer;
  Layer: TVectArtLayer;
  LogicalPoints: TArray<TPointF>;
begin
  Result := nil;
  if not SelectedPathLayer(Layer) then
    Exit;
  LogicalPoints := FlattenMapRakuPathVertices(
    Layer.EditablePathVertices);
  SetLength(Result, Length(LogicalPoints));
  for I := 0 to High(LogicalPoints) do
    Result[I] := Point(ToScreenX(LogicalPoints[I].X),
      ToScreenY(LogicalPoints[I].Y));
end;

function TMapRakuPathInteraction.SelectedWidthHandles:
  TArray<TMapRakuPathWidthHandle>;
var
  Center: TPointF;
  CenterHalf: Integer;
  HandleHalf: Integer;
  I: Integer;
  LeftLogical: TPointF;
  Normal: TPointF;
  PathLayer: TVectArtPathLayer;
  RightLogical: TPointF;
  WidthPoints: TArray<TMapRakuStrokeWidthPoint>;
begin
  Result := nil;
  if not SelectedVariablePath(PathLayer) then
    Exit;
  WidthPoints := PathLayer.WidthPoints;
  SetLength(Result, Length(WidthPoints));
  HandleHalf := WIDTH_HANDLE_SIZE div 2;
  CenterHalf := WIDTH_CENTER_HANDLE_SIZE div 2;
  for I := 0 to High(WidthPoints) do
  begin
    if not WidthPointFrame(I, Center, Normal) then
      Continue;
    LeftLogical := TPointF.Create(
      Center.X + Normal.X * PathLayer.StrokeWidth * 0.5 *
        WidthPoints[I].LeftScale,
      Center.Y + Normal.Y * PathLayer.StrokeWidth * 0.5 *
        WidthPoints[I].LeftScale);
    RightLogical := TPointF.Create(
      Center.X - Normal.X * PathLayer.StrokeWidth * 0.5 *
        WidthPoints[I].RightScale,
      Center.Y - Normal.Y * PathLayer.StrokeWidth * 0.5 *
        WidthPoints[I].RightScale);
    Result[I].PointIndex := I;
    Result[I].CenterPoint := Point(ToScreenX(Center.X), ToScreenY(Center.Y));
    Result[I].LeftPoint := Point(ToScreenX(LeftLogical.X),
      ToScreenY(LeftLogical.Y));
    Result[I].RightPoint := Point(ToScreenX(RightLogical.X),
      ToScreenY(RightLogical.Y));
    with Result[I] do
    begin
      CenterRect := Rect(CenterPoint.X - CenterHalf,
        CenterPoint.Y - CenterHalf, CenterPoint.X + CenterHalf + 1,
        CenterPoint.Y + CenterHalf + 1);
      LeftRect := Rect(LeftPoint.X - HandleHalf, LeftPoint.Y - HandleHalf,
        LeftPoint.X + HandleHalf + 1, LeftPoint.Y + HandleHalf + 1);
      RightRect := Rect(RightPoint.X - HandleHalf,
        RightPoint.Y - HandleHalf, RightPoint.X + HandleHalf + 1,
        RightPoint.Y + HandleHalf + 1);
    end;
  end;
end;

function TMapRakuPathInteraction.HitTestWidthHandle(X, Y: Integer;
  out PointIndex: Integer;
  out Side: TMapRakuPathWidthHandleSide): Boolean;
var
  Handle: TMapRakuPathWidthHandle;
begin
  PointIndex := -1;
  Side := slwhNone;
  for Handle in SelectedWidthHandles do
  begin
    if PtInRect(Handle.LeftRect, Point(X, Y)) then
      Side := slwhLeft
    else if PtInRect(Handle.RightRect, Point(X, Y)) then
      Side := slwhRight
    else
      Continue;
    PointIndex := Handle.PointIndex;
    Exit(True);
  end;
  Result := False;
end;

function TMapRakuPathInteraction.WidthCursorAt(X, Y: Integer;
  out Cursor: TCursor): Boolean;
var
  PointIndex: Integer;
  Side: TMapRakuPathWidthHandleSide;
begin
  Result := HitTestWidthHandle(X, Y, PointIndex, Side);
  if Result then
    Cursor := crSizeAll
  else
    Cursor := crDefault;
end;

function TMapRakuPathInteraction.SelectedVertexKindButtons:
  TArray<TMapRakuVertexKindButton>;
var
  Bounds: TRectF;
  ButtonCenterX: Single;
  ButtonCenterY: Single;
  ButtonIndex: Integer;
  CenterX: Integer;
  CenterY: Integer;
  DirectionLength: Single;
  DirectionX: Single;
  DirectionY: Single;
  HalfDistance: Single;
  HalfSize: Integer;
  PathLayer: TVectArtLayer;
  TangentX: Single;
  TangentY: Single;
  TargetX: Single;
  TargetY: Single;
  Vertex: TMapRakuVertex;
  Vertices: TArray<TMapRakuVertex>;
  VertexX: Integer;
  VertexY: Integer;
begin
  Result := nil;
  if not SelectedPathLayer(PathLayer) or (FSelectedVertexIndex < 0) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  if FSelectedVertexIndex > High(Vertices) then
    Exit;
  Vertex := Vertices[FSelectedVertexIndex];
  Bounds := MapRakuPathVerticesBounds(Vertices);
  VertexX := ToScreenX(Vertex.Position.X);
  VertexY := ToScreenY(Vertex.Position.Y);
  CenterX := ToScreenX((Bounds.Left + Bounds.Right) * 0.5);
  CenterY := ToScreenY((Bounds.Top + Bounds.Bottom) * 0.5);
  DirectionX := VertexX - CenterX;
  DirectionY := VertexY - CenterY;
  DirectionLength := Hypot(DirectionX, DirectionY);
  if DirectionLength < 0.001 then
  begin
    DirectionX := 0;
    DirectionY := -1;
  end
  else
  begin
    DirectionX := DirectionX / DirectionLength;
    DirectionY := DirectionY / DirectionLength;
  end;
  TargetX := VertexX + DirectionX * VERTEX_KIND_BUTTON_OFFSET;
  TargetY := VertexY + DirectionY * VERTEX_KIND_BUTTON_OFFSET;
  TangentX := -DirectionY;
  TangentY := DirectionX;
  HalfDistance := (VERTEX_KIND_BUTTON_SIZE + VERTEX_KIND_BUTTON_GAP) * 0.5;
  HalfSize := VERTEX_KIND_BUTTON_SIZE div 2;
  SetLength(Result, 2);
  for ButtonIndex := 0 to High(Result) do
  begin
    if ButtonIndex = 0 then
    begin
      Result[ButtonIndex].Kind := slvkSharp;
      ButtonCenterX := TargetX - TangentX * HalfDistance;
      ButtonCenterY := TargetY - TangentY * HalfDistance;
    end
    else
    begin
      Result[ButtonIndex].Kind := slvkBezier;
      ButtonCenterX := TargetX + TangentX * HalfDistance;
      ButtonCenterY := TargetY + TangentY * HalfDistance;
    end;
    Result[ButtonIndex].Bounds := Rect(Round(ButtonCenterX) - HalfSize,
      Round(ButtonCenterY) - HalfSize, Round(ButtonCenterX) + HalfSize,
      Round(ButtonCenterY) + HalfSize);
    Result[ButtonIndex].Selected := Result[ButtonIndex].Kind = Vertex.Kind;
  end;
end;

function TMapRakuPathInteraction.SelectedVertexRect(
  out VertexRect: TRect): Boolean;
var
  HalfSize: Integer;
  PathLayer: TVectArtLayer;
  Vertex: TMapRakuVertex;
  Vertices: TArray<TMapRakuVertex>;
  X: Integer;
  Y: Integer;
begin
  Result := False;
  VertexRect := TRect.Empty;
  if not SelectedPathLayer(PathLayer) or (FSelectedVertexIndex < 0) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  if FSelectedVertexIndex > High(Vertices) then
    Exit;
  Vertex := Vertices[FSelectedVertexIndex];
  X := ToScreenX(Vertex.Position.X);
  Y := ToScreenY(Vertex.Position.Y);
  HalfSize := VERTEX_HANDLE_SIZE div 2;
  VertexRect := Rect(X - HalfSize, Y - HalfSize,
    X - HalfSize + VERTEX_HANDLE_SIZE,
    Y - HalfSize + VERTEX_HANDLE_SIZE);
  Result := True;
end;

function TMapRakuPathInteraction.SelectedBezierHandles(
  out Handles: TMapRakuBezierHandles): Boolean;
var
  HalfSize: Integer;
  PathLayer: TVectArtLayer;
  Vertex: TMapRakuVertex;
  Vertices: TArray<TMapRakuVertex>;
begin
  Result := False;
  Handles := Default(TMapRakuBezierHandles);
  if not SelectedPathLayer(PathLayer) or (FSelectedVertexIndex < 0) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  if FSelectedVertexIndex > High(Vertices) then
    Exit;
  Vertex := Vertices[FSelectedVertexIndex];
  if Vertex.Kind <> slvkBezier then
    Exit;
  Handles.VertexPoint := Point(ToScreenX(Vertex.Position.X),
    ToScreenY(Vertex.Position.Y));
  Handles.IncomingPoint := Point(ToScreenX(Vertex.Position.X +
    Vertex.IncomingControl.X), ToScreenY(Vertex.Position.Y +
    Vertex.IncomingControl.Y));
  Handles.OutgoingPoint := Point(ToScreenX(Vertex.Position.X +
    Vertex.OutgoingControl.X), ToScreenY(Vertex.Position.Y +
    Vertex.OutgoingControl.Y));
  HalfSize := BEZIER_CONTROL_HANDLE_SIZE div 2;
  if FSelectedVertexIndex > 0 then
    Handles.IncomingRect := Rect(Handles.IncomingPoint.X - HalfSize,
      Handles.IncomingPoint.Y - HalfSize,
      Handles.IncomingPoint.X - HalfSize + BEZIER_CONTROL_HANDLE_SIZE,
      Handles.IncomingPoint.Y - HalfSize + BEZIER_CONTROL_HANDLE_SIZE);
  if FSelectedVertexIndex < High(Vertices) then
    Handles.OutgoingRect := Rect(Handles.OutgoingPoint.X - HalfSize,
      Handles.OutgoingPoint.Y - HalfSize,
      Handles.OutgoingPoint.X - HalfSize + BEZIER_CONTROL_HANDLE_SIZE,
      Handles.OutgoingPoint.Y - HalfSize + BEZIER_CONTROL_HANDLE_SIZE);
  Result := True;
end;

end.
