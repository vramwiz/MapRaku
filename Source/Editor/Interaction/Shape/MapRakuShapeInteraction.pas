// 単一Shapeの頂点選択、区間分割、ベジェハンドル操作と表示用幾何を管理する。
unit MapRakuShapeInteraction;

interface

uses
  System.Classes, System.Types, Vcl.Controls, MapRakuDocument,
  MapRakuEditHistory;

type
  TMapRakuBezierHandleKind = (slbhNone, slbhIncoming, slbhOutgoing);

  TMapRakuBezierHandles = record
    IncomingPoint: TPoint; // 入力側制御点の画面座標。
    IncomingRect: TRect;   // 入力側制御点のクリック範囲。
    OutgoingPoint: TPoint; // 出力側制御点の画面座標。
    OutgoingRect: TRect;   // 出力側制御点のクリック範囲。
    VertexPoint: TPoint;   // 接線が通る選択頂点の画面座標。
  end;

  TMapRakuVertexKindButton = record
    Bounds: TRect;                  // クリック可能な画面座標範囲。
    Kind: TMapRakuVertexKind; // 選択時に設定する頂点種別。
    Selected: Boolean;             // 現在の頂点種別と一致する状態。
  end;

  TMapRakuShapeInteraction = class
  private
    FCanvasBounds: TRect;
    FDocument: TVectArtDocument;
    FDragBezierHandle: TMapRakuBezierHandleKind;
    FDragContourIndex: Integer;
    FDragLayerIndex: Integer;
    FDragStartContours: TArray<TMapRakuContour>;
    FDragVertexIndex: Integer;
    FEditHistory: TVectArtEditHistory;
    FSelectedContourIndex: Integer;
    FSelectedLayerIndex: Integer;
    FSelectedVertexIndex: Integer;
    FZoom: Single;
    procedure ApplySelectedVertexKind(Kind: TMapRakuVertexKind);
    function HitTestBezierHandle(X, Y: Integer;
      out HandleKind: TMapRakuBezierHandleKind): Boolean;
    function HitTestSegment(X, Y: Integer; out ContourIndex,
      SegmentIndex: Integer; out Parameter: Single): Boolean;
    function HitTestVertex(X, Y: Integer; out ContourIndex,
      VertexIndex: Integer): Boolean;
    function HitTestVertexKindButton(X, Y: Integer;
      out Kind: TMapRakuVertexKind): Boolean;
    function GetDragging: Boolean;
    procedure InsertVertex(ContourIndex, SegmentIndex: Integer;
      Parameter: Single);
    function SelectedShapeLayer(
      out ShapeLayer: TMapRakuShapeLayer): Boolean;
    function ToLogicalX(Value: Single): Single;
    function ToLogicalY(Value: Single): Single;
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
  public
    constructor Create;
    // Document、履歴、座標変換を更新し、単一選択レイヤーが変われば頂点選択を解除する。
    procedure Configure(ADocument: TVectArtDocument;
      AEditHistory: TVectArtEditHistory; const ACanvasBounds: TRect;
      AZoom: Single);
    // Shape以外の操作へ移るときに、種別ボタンを含む頂点選択を解除する。
    procedure ClearSelection;
    // 選択頂点のドラッグ結果を履歴へ登録し、ドラッグ状態を破棄する。
    procedure CommitDrag;
    // 履歴を作らずに進行中のShape頂点ドラッグ状態を破棄する。
    procedure EndDrag;
    // 右クリック位置の頂点を削除する。頂点を指していた場合にTrueを返す。
    function DeleteVertexAt(X, Y: Integer): Boolean;
    // 選択中の頂点に命中した場合だけ削除し、変更をUndo履歴へ記録する。
    function DeleteSelectedVertexAt(X, Y: Integer): Boolean;
    // 種別ボタン位置なら頂点種別を適用し、ボタンを指していた場合にTrueを返す。
    function ApplyVertexKindAt(X, Y: Integer): Boolean;
    // ベジェ制御点位置からドラッグを開始できた場合にTrueを返す。
    function BeginBezierHandleDragAt(X, Y: Integer): Boolean;
    // Shape頂点位置からドラッグを開始できた場合にTrueを返す。
    function BeginVertexDragAt(X, Y: Integer): Boolean;
    // Shape区間位置へ頂点を挿入し、区間を指していた場合にTrueを返す。
    function InsertVertexAt(X, Y: Integer): Boolean;
    // Shape編集要素に対応するカーソルを返し、要素上ならTrueを返す。
    function CursorAt(X, Y: Integer; out Cursor: TCursor): Boolean;
    // 進行中の頂点または制御点ドラッグを現在位置へ反映する。
    function DragTo(Shift: TShiftState; X, Y: Integer): Boolean;
    // ドラッグ中のアンカー以外にある同一Shape内の吸着候補を返す。
    function OtherDragVertexPositions: TArray<TPointF>;
    // 単一選択Shapeの全輪郭アンカーを画面座標の矩形列として返す。
    function SelectedVertexRects: TArray<TRect>;
    // 選択頂点の外側へ表示する鋭角／ベジェ種別ボタンを返す。
    function SelectedVertexKindButtons:
      TArray<TMapRakuVertexKindButton>;
    // 種別編集対象として選択されたShapeアンカーの画面座標を返す。
    function SelectedVertexRect(out VertexRect: TRect): Boolean;
    // 選択中のベジェ頂点について、接線と両側の制御ハンドルを返す。
    function SelectedBezierHandles(
      out Handles: TMapRakuBezierHandles): Boolean;
    property Dragging: Boolean read GetDragging;
  end;

// 表示矩形より広い範囲から最寄りのベジェ制御点を返す。
function MapRakuBezierHandleAt(const Handles: TMapRakuBezierHandles;
  const PointValue: TPoint): TMapRakuBezierHandleKind;

implementation

uses
  System.Math, MapRakuGeometry, MapRakuShapeEditCommands,
  MapRakuShapeOperations;

const
  VERTEX_HANDLE_SIZE           = 9;
  BEZIER_VERTEX_HIT_PADDING    = 6;
  BEZIER_CONTROL_HANDLE_SIZE   = 9;
  BEZIER_CONTROL_HIT_PADDING   = 6;
  VERTEX_KIND_BUTTON_GAP       = 4;
  VERTEX_KIND_BUTTON_OFFSET    = 34;
  VERTEX_KIND_BUTTON_SIZE      = 22;
  SEGMENT_HIT_DISTANCE         = 6.0;
  BEZIER_HIT_SUBDIVISIONS      = 32;

function MapRakuBezierHandleAt(const Handles: TMapRakuBezierHandles;
  const PointValue: TPoint): TMapRakuBezierHandleKind;
var
  IncomingCenter: TPoint;
  IncomingDistance: Single;
  IncomingHitRect: TRect;
  OutgoingCenter: TPoint;
  OutgoingDistance: Single;
  OutgoingHitRect: TRect;
begin
  Result := slbhNone;
  IncomingDistance := MaxSingle;
  if not Handles.IncomingRect.IsEmpty then
  begin
    IncomingHitRect := Handles.IncomingRect;
    InflateRect(IncomingHitRect, BEZIER_CONTROL_HIT_PADDING,
      BEZIER_CONTROL_HIT_PADDING);
    if PtInRect(IncomingHitRect, PointValue) then
    begin
      IncomingCenter := Handles.IncomingRect.CenterPoint;
      IncomingDistance := Sqr(PointValue.X - IncomingCenter.X) +
        Sqr(PointValue.Y - IncomingCenter.Y);
      Result := slbhIncoming;
    end;
  end;
  if not Handles.OutgoingRect.IsEmpty then
  begin
    OutgoingHitRect := Handles.OutgoingRect;
    InflateRect(OutgoingHitRect, BEZIER_CONTROL_HIT_PADDING,
      BEZIER_CONTROL_HIT_PADDING);
    if PtInRect(OutgoingHitRect, PointValue) then
    begin
      OutgoingCenter := Handles.OutgoingRect.CenterPoint;
      OutgoingDistance := Sqr(PointValue.X - OutgoingCenter.X) +
        Sqr(PointValue.Y - OutgoingCenter.Y);
      if OutgoingDistance < IncomingDistance then
        Result := slbhOutgoing;
    end;
  end;
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

constructor TMapRakuShapeInteraction.Create;
begin
  inherited Create;
  FDragLayerIndex := -1;
  FSelectedLayerIndex := -1;
  ClearSelection;
  EndDrag;
end;

procedure TMapRakuShapeInteraction.Configure(
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

procedure TMapRakuShapeInteraction.ClearSelection;
begin
  FSelectedContourIndex := -1;
  FSelectedVertexIndex := -1;
end;

function TMapRakuShapeInteraction.GetDragging: Boolean;
begin
  Result := FDragLayerIndex > 0;
end;

function TMapRakuShapeInteraction.SelectedShapeLayer(
  out ShapeLayer: TMapRakuShapeLayer): Boolean;
begin
  ShapeLayer := nil;
  Result := (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is TMapRakuShapeLayer);
  if Result then
  begin
    ShapeLayer := TMapRakuShapeLayer(FDocument[FDocument.SelectedIndex]);
    Result := not ShapeLayer.Locked;
  end;
end;

function TMapRakuShapeInteraction.ToLogicalX(Value: Single): Single;
begin
  Result := ScreenToLogicalX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TMapRakuShapeInteraction.ToLogicalY(Value: Single): Single;
begin
  Result := ScreenToLogicalY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TMapRakuShapeInteraction.ToScreenX(Value: Single): Integer;
begin
  Result := LogicalToScreenX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TMapRakuShapeInteraction.ToScreenY(Value: Single): Integer;
begin
  Result := LogicalToScreenY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TMapRakuShapeInteraction.HitTestVertex(X, Y: Integer;
  out ContourIndex, VertexIndex: Integer): Boolean;
var
  CandidateDistance: Single;
  CenterX: Integer;
  CenterY: Integer;
  CurrentContourIndex: Integer;
  CurrentVertexIndex: Integer;
  Contours: TArray<TMapRakuContour>;
  HalfSize: Integer;
  HandleRect: TRect;
  NearestDistance: Single;
  ShapeLayer: TMapRakuShapeLayer;
begin
  Result := False;
  ContourIndex := -1;
  VertexIndex := -1;
  if not SelectedShapeLayer(ShapeLayer) then
    Exit;
  Contours := ShapeLayer.Contours;
  HalfSize := VERTEX_HANDLE_SIZE div 2;
  NearestDistance := MaxSingle;
  for CurrentContourIndex := 0 to High(Contours) do
    for CurrentVertexIndex := 0 to
      High(Contours[CurrentContourIndex].Vertices) do
    begin
      CenterX := ToScreenX(Contours[CurrentContourIndex].Vertices[
        CurrentVertexIndex].Position.X);
      CenterY := ToScreenY(Contours[CurrentContourIndex].Vertices[
        CurrentVertexIndex].Position.Y);
      HandleRect := Rect(CenterX - HalfSize, CenterY - HalfSize,
        CenterX - HalfSize + VERTEX_HANDLE_SIZE,
        CenterY - HalfSize + VERTEX_HANDLE_SIZE);
      if Contours[CurrentContourIndex].Vertices[
        CurrentVertexIndex].Kind = slvkBezier then
        InflateRect(HandleRect, BEZIER_VERTEX_HIT_PADDING,
          BEZIER_VERTEX_HIT_PADDING);
      if PtInRect(HandleRect, Point(X, Y)) then
      begin
        CandidateDistance := Sqr(X - CenterX) + Sqr(Y - CenterY);
        if CandidateDistance < NearestDistance then
        begin
          NearestDistance := CandidateDistance;
          ContourIndex := CurrentContourIndex;
          VertexIndex := CurrentVertexIndex;
          Result := True;
        end;
      end;
    end;
end;

function TMapRakuShapeInteraction.HitTestVertexKindButton(X,
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

function TMapRakuShapeInteraction.HitTestBezierHandle(X, Y: Integer;
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

function TMapRakuShapeInteraction.HitTestSegment(X, Y: Integer;
  out ContourIndex, SegmentIndex: Integer; out Parameter: Single): Boolean;
var
  BestDistance: Single;
  Contours: TArray<TMapRakuContour>;
  Control1: TPointF;
  Control2: TPointF;
  CurrentContourIndex: Integer;
  CurrentDistance: Single;
  CurrentParameter: Single;
  CurrentSegmentIndex: Integer;
  EndParameter: Single;
  EndPoint: TPointF;
  LocalParameter: Single;
  MousePoint: TPointF;
  NextIndex: Integer;
  ShapeLayer: TMapRakuShapeLayer;
  StartParameter: Single;
  StartPoint: TPointF;
  SubdivisionEnd: TPointF;
  SubdivisionIndex: Integer;
  SubdivisionStart: TPointF;
begin
  Result := False;
  ContourIndex := -1;
  SegmentIndex := -1;
  Parameter := 0;
  if not SelectedShapeLayer(ShapeLayer) then
    Exit;
  Contours := ShapeLayer.Contours;
  MousePoint := TPointF.Create(X, Y);
  BestDistance := 1.0E30;
  for CurrentContourIndex := 0 to High(Contours) do
    for CurrentSegmentIndex := 0 to
      High(Contours[CurrentContourIndex].Vertices) do
    begin
      NextIndex := (CurrentSegmentIndex + 1) mod
        Length(Contours[CurrentContourIndex].Vertices);
      StartPoint := TPointF.Create(ToScreenX(Contours[CurrentContourIndex].
        Vertices[CurrentSegmentIndex].Position.X),
        ToScreenY(Contours[CurrentContourIndex].Vertices[
        CurrentSegmentIndex].Position.Y));
      EndPoint := TPointF.Create(ToScreenX(Contours[CurrentContourIndex].
        Vertices[NextIndex].Position.X),
        ToScreenY(Contours[CurrentContourIndex].Vertices[
        NextIndex].Position.Y));
      if Contours[CurrentContourIndex].Vertices[
        CurrentSegmentIndex].OutgoingSegment = slskLine then
      begin
        CurrentDistance := DistanceToSegmentParameter(MousePoint,
          StartPoint, EndPoint, CurrentParameter);
        if CurrentDistance < BestDistance then
        begin
          BestDistance := CurrentDistance;
          ContourIndex := CurrentContourIndex;
          SegmentIndex := CurrentSegmentIndex;
          Parameter := CurrentParameter;
        end;
        Continue;
      end;
      Control1 := TPointF.Create(ToScreenX(Contours[CurrentContourIndex].
        Vertices[CurrentSegmentIndex].Position.X +
        Contours[CurrentContourIndex].Vertices[
        CurrentSegmentIndex].OutgoingControl.X),
        ToScreenY(Contours[CurrentContourIndex].Vertices[
        CurrentSegmentIndex].Position.Y + Contours[CurrentContourIndex].
        Vertices[CurrentSegmentIndex].OutgoingControl.Y));
      Control2 := TPointF.Create(ToScreenX(Contours[CurrentContourIndex].
        Vertices[NextIndex].Position.X + Contours[CurrentContourIndex].
        Vertices[NextIndex].IncomingControl.X),
        ToScreenY(Contours[CurrentContourIndex].Vertices[
        NextIndex].Position.Y + Contours[CurrentContourIndex].Vertices[
        NextIndex].IncomingControl.Y));
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
          ContourIndex := CurrentContourIndex;
          SegmentIndex := CurrentSegmentIndex;
          Parameter := (SubdivisionIndex + LocalParameter) /
            BEZIER_HIT_SUBDIVISIONS;
        end;
      end;
    end;
  Result := BestDistance <= SEGMENT_HIT_DISTANCE;
  if not Result then
  begin
    ContourIndex := -1;
    SegmentIndex := -1;
    Parameter := 0;
  end;
end;

procedure TMapRakuShapeInteraction.ApplySelectedVertexKind(
  Kind: TMapRakuVertexKind);
var
  NewContours: TArray<TMapRakuContour>;
  OldContours: TArray<TMapRakuContour>;
  ShapeLayer: TMapRakuShapeLayer;
begin
  if not SelectedShapeLayer(ShapeLayer) or (FSelectedContourIndex < 0) or
    (FSelectedVertexIndex < 0) then
    Exit;
  OldContours := ShapeLayer.Contours;
  if (FSelectedContourIndex > High(OldContours)) or
    (FSelectedVertexIndex >
    High(OldContours[FSelectedContourIndex].Vertices)) or
    (OldContours[FSelectedContourIndex].Vertices[
    FSelectedVertexIndex].Kind = Kind) then
    Exit;
  NewContours := CloneMapRakuShapeContours(OldContours);
  SetMapRakuShapeVertexKind(NewContours[FSelectedContourIndex],
    FSelectedVertexIndex, Kind);
  FDocument.SetShapeContours(FDocument.SelectedIndex, NewContours);
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuShapeContoursCommand.Create(
      FDocument, FDocument.SelectedIndex, OldContours, NewContours));
end;

function TMapRakuShapeInteraction.ApplyVertexKindAt(X,
  Y: Integer): Boolean;
var
  Kind: TMapRakuVertexKind;
begin
  Result := HitTestVertexKindButton(X, Y, Kind);
  if Result then
    ApplySelectedVertexKind(Kind);
end;

procedure TMapRakuShapeInteraction.InsertVertex(ContourIndex,
  SegmentIndex: Integer; Parameter: Single);
var
  NewContours: TArray<TMapRakuContour>;
  NewVertexIndex: Integer;
  OldContours: TArray<TMapRakuContour>;
  ShapeLayer: TMapRakuShapeLayer;
begin
  if not SelectedShapeLayer(ShapeLayer) then
    Exit;
  OldContours := ShapeLayer.Contours;
  if (ContourIndex < 0) or (ContourIndex > High(OldContours)) then
    Exit;
  NewContours := CloneMapRakuShapeContours(OldContours);
  NewVertexIndex := InsertMapRakuShapeVertex(NewContours[ContourIndex],
    SegmentIndex, Parameter);
  if NewVertexIndex < 0 then
    Exit;
  FDocument.SetShapeContours(FDocument.SelectedIndex, NewContours);
  FSelectedContourIndex := ContourIndex;
  FSelectedVertexIndex := NewVertexIndex;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuShapeContoursCommand.Create(
      FDocument, FDocument.SelectedIndex, OldContours, NewContours));
end;

function TMapRakuShapeInteraction.InsertVertexAt(X, Y: Integer): Boolean;
var
  ContourIndex: Integer;
  Parameter: Single;
  SegmentIndex: Integer;
begin
  Result := HitTestSegment(X, Y, ContourIndex, SegmentIndex, Parameter);
  if Result then
    InsertVertex(ContourIndex, SegmentIndex, Parameter);
end;

function TMapRakuShapeInteraction.DeleteSelectedVertexAt(X, Y: Integer): Boolean;
var
  ContourIndex: Integer;
  VertexIndex: Integer;
begin
  Result := HitTestVertex(X, Y, ContourIndex, VertexIndex) and
    (VertexIndex = FSelectedVertexIndex) and
    (ContourIndex = FSelectedContourIndex);
  if Result then
    Result := DeleteVertexAt(X, Y);
end;

function TMapRakuShapeInteraction.DeleteVertexAt(X, Y: Integer): Boolean;
var
  ContourIndex: Integer;
  NewContours: TArray<TMapRakuContour>;
  OldContours: TArray<TMapRakuContour>;
  ShapeLayer: TMapRakuShapeLayer;
  VertexIndex: Integer;
begin
  Result := HitTestVertex(X, Y, ContourIndex, VertexIndex);
  if not Result or not SelectedShapeLayer(ShapeLayer) then
    Exit;
  OldContours := ShapeLayer.Contours;
  NewContours := CloneMapRakuShapeContours(OldContours);
  if not DeleteMapRakuShapeVertex(NewContours[ContourIndex],
    VertexIndex) then
    Exit;
  FDocument.SetShapeContours(FDocument.SelectedIndex, NewContours);
  ClearSelection;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuShapeContoursCommand.Create(
      FDocument, FDocument.SelectedIndex, OldContours, NewContours));
end;

function TMapRakuShapeInteraction.BeginBezierHandleDragAt(X,
  Y: Integer): Boolean;
var
  HandleKind: TMapRakuBezierHandleKind;
  ShapeLayer: TMapRakuShapeLayer;
begin
  Result := HitTestBezierHandle(X, Y, HandleKind) and
    SelectedShapeLayer(ShapeLayer);
  if not Result then
    Exit;
  FDragBezierHandle := HandleKind;
  FDragContourIndex := FSelectedContourIndex;
  FDragVertexIndex := FSelectedVertexIndex;
  FDragLayerIndex := FDocument.SelectedIndex;
  FDragStartContours := CloneMapRakuShapeContours(ShapeLayer.Contours);
end;

function TMapRakuShapeInteraction.BeginVertexDragAt(X,
  Y: Integer): Boolean;
var
  ShapeLayer: TMapRakuShapeLayer;
begin
  Result := HitTestVertex(X, Y, FDragContourIndex, FDragVertexIndex) and
    SelectedShapeLayer(ShapeLayer);
  if not Result then
    Exit;
  FSelectedContourIndex := FDragContourIndex;
  FSelectedVertexIndex := FDragVertexIndex;
  FDragLayerIndex := FDocument.SelectedIndex;
  FDragStartContours := CloneMapRakuShapeContours(ShapeLayer.Contours);
  FDragBezierHandle := slbhNone;
end;

function TMapRakuShapeInteraction.DragTo(Shift: TShiftState;
  X, Y: Integer): Boolean;
var
  Angle: Single;
  ControlLength: Single;
  ControlVector: TPointF;
  NewContours: TArray<TMapRakuContour>;
  OppositeLength: Single;
begin
  Result := FDragLayerIndex > 0;
  if not Result or not (FDocument[FDragLayerIndex] is
    TMapRakuShapeLayer) then
    Exit;
  NewContours := CloneMapRakuShapeContours(FDragStartContours);
  if (FDragContourIndex < 0) or
    (FDragContourIndex > High(NewContours)) or (FDragVertexIndex < 0) or
    (FDragVertexIndex > High(NewContours[FDragContourIndex].Vertices)) then
    Exit;
  if FDragBezierHandle = slbhNone then
  begin
    NewContours[FDragContourIndex].Vertices[
      FDragVertexIndex].Position := TPointF.Create(
      EnsureRange(ToLogicalX(X), FDocument.CanvasLayer.Width * -0.5,
        FDocument.CanvasLayer.Width * 0.5),
      EnsureRange(ToLogicalY(Y), FDocument.CanvasLayer.Height * -0.5,
        FDocument.CanvasLayer.Height * 0.5));
    FDocument.SetShapeContours(FDragLayerIndex, NewContours);
    Exit;
  end;

  with NewContours[FDragContourIndex].Vertices[FDragVertexIndex] do
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
    OppositeLength := Hypot(FDragStartContours[FDragContourIndex].Vertices[
      FDragVertexIndex].OutgoingControl.X,
      FDragStartContours[FDragContourIndex].Vertices[
      FDragVertexIndex].OutgoingControl.Y);
    NewContours[FDragContourIndex].Vertices[
      FDragVertexIndex].IncomingControl := ControlVector;
    if ControlLength > 0.001 then
      NewContours[FDragContourIndex].Vertices[
        FDragVertexIndex].OutgoingControl := TPointF.Create(
        -ControlVector.X / ControlLength * OppositeLength,
        -ControlVector.Y / ControlLength * OppositeLength);
  end
  else
  begin
    OppositeLength := Hypot(FDragStartContours[FDragContourIndex].Vertices[
      FDragVertexIndex].IncomingControl.X,
      FDragStartContours[FDragContourIndex].Vertices[
      FDragVertexIndex].IncomingControl.Y);
    NewContours[FDragContourIndex].Vertices[
      FDragVertexIndex].OutgoingControl := ControlVector;
    if ControlLength > 0.001 then
      NewContours[FDragContourIndex].Vertices[
        FDragVertexIndex].IncomingControl := TPointF.Create(
        -ControlVector.X / ControlLength * OppositeLength,
        -ControlVector.Y / ControlLength * OppositeLength);
  end;
  FDocument.SetShapeContours(FDragLayerIndex, NewContours);
end;

function TMapRakuShapeInteraction.OtherDragVertexPositions:
  TArray<TPointF>;
var
  ContourIndex: Integer;
  VertexIndex: Integer;
begin
  Result := nil;
  if FDragBezierHandle <> slbhNone then
    Exit;
  for ContourIndex := 0 to High(FDragStartContours) do
    for VertexIndex := 0 to High(
      FDragStartContours[ContourIndex].Vertices) do
      if (ContourIndex <> FDragContourIndex) or
        (VertexIndex <> FDragVertexIndex) then
        Result := Result + [FDragStartContours[ContourIndex].Vertices[
          VertexIndex].Position];
end;

procedure TMapRakuShapeInteraction.CommitDrag;
var
  ShapeLayer: TMapRakuShapeLayer;
begin
  if (FEditHistory <> nil) and (FDragLayerIndex > 0) and
    (FDocument[FDragLayerIndex] is TMapRakuShapeLayer) then
  begin
    ShapeLayer := TMapRakuShapeLayer(FDocument[FDragLayerIndex]);
    if not MapRakuShapeContoursEqual(FDragStartContours,
      ShapeLayer.Contours) then
      FEditHistory.AddApplied(TMapRakuShapeContoursCommand.Create(
        FDocument, FDragLayerIndex, FDragStartContours,
        ShapeLayer.Contours));
  end;
  EndDrag;
end;

procedure TMapRakuShapeInteraction.EndDrag;
begin
  FDragLayerIndex := -1;
  FDragContourIndex := -1;
  FDragVertexIndex := -1;
  FDragBezierHandle := slbhNone;
  FDragStartContours := nil;
end;

function TMapRakuShapeInteraction.CursorAt(X, Y: Integer;
  out Cursor: TCursor): Boolean;
var
  ContourIndex: Integer;
  HandleKind: TMapRakuBezierHandleKind;
  Kind: TMapRakuVertexKind;
  Parameter: Single;
  SegmentIndex: Integer;
  VertexIndex: Integer;
begin
  Cursor := crDefault;
  if HitTestVertexKindButton(X, Y, Kind) then
    Cursor := crHandPoint
  else if HitTestBezierHandle(X, Y, HandleKind) or
    HitTestVertex(X, Y, ContourIndex, VertexIndex) then
    Cursor := crSizeAll
  else if HitTestSegment(X, Y, ContourIndex, SegmentIndex, Parameter) then
    Cursor := crCross;
  Result := Cursor <> crDefault;
end;

function TMapRakuShapeInteraction.SelectedVertexRects: TArray<TRect>;
var
  ContourIndex: Integer;
  Contours: TArray<TMapRakuContour>;
  HalfSize: Integer;
  ResultIndex: Integer;
  ShapeLayer: TMapRakuShapeLayer;
  VertexIndex: Integer;
  X: Integer;
  Y: Integer;
begin
  Result := nil;
  if not SelectedShapeLayer(ShapeLayer) then
    Exit;
  Contours := ShapeLayer.Contours;
  ResultIndex := 0;
  for ContourIndex := 0 to High(Contours) do
    Inc(ResultIndex, Length(Contours[ContourIndex].Vertices));
  SetLength(Result, ResultIndex);
  ResultIndex := 0;
  HalfSize := VERTEX_HANDLE_SIZE div 2;
  for ContourIndex := 0 to High(Contours) do
    for VertexIndex := 0 to High(Contours[ContourIndex].Vertices) do
    begin
      X := ToScreenX(Contours[ContourIndex].Vertices[VertexIndex].Position.X);
      Y := ToScreenY(Contours[ContourIndex].Vertices[VertexIndex].Position.Y);
      Result[ResultIndex] := Rect(X - HalfSize, Y - HalfSize,
        X - HalfSize + VERTEX_HANDLE_SIZE,
        Y - HalfSize + VERTEX_HANDLE_SIZE);
      Inc(ResultIndex);
    end;
end;

function TMapRakuShapeInteraction.SelectedVertexKindButtons:
  TArray<TMapRakuVertexKindButton>;
var
  Bounds: TRectF;
  ButtonCenterX: Single;
  ButtonCenterY: Single;
  ButtonIndex: Integer;
  CenterX: Integer;
  CenterY: Integer;
  Contours: TArray<TMapRakuContour>;
  DirectionLength: Single;
  DirectionX: Single;
  DirectionY: Single;
  HalfDistance: Single;
  HalfSize: Integer;
  ShapeLayer: TMapRakuShapeLayer;
  TangentX: Single;
  TangentY: Single;
  TargetX: Single;
  TargetY: Single;
  Vertex: TMapRakuVertex;
  VertexX: Integer;
  VertexY: Integer;
begin
  Result := nil;
  if not SelectedShapeLayer(ShapeLayer) or (FSelectedContourIndex < 0) or
    (FSelectedVertexIndex < 0) then
    Exit;
  Contours := ShapeLayer.Contours;
  if (FSelectedContourIndex > High(Contours)) or
    (FSelectedVertexIndex >
    High(Contours[FSelectedContourIndex].Vertices)) then
    Exit;
  Vertex := Contours[FSelectedContourIndex].Vertices[FSelectedVertexIndex];
  Bounds := MapRakuShapeContoursBounds(Contours);
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

function TMapRakuShapeInteraction.SelectedVertexRect(
  out VertexRect: TRect): Boolean;
var
  Contours: TArray<TMapRakuContour>;
  HalfSize: Integer;
  ShapeLayer: TMapRakuShapeLayer;
  Vertex: TMapRakuVertex;
  X: Integer;
  Y: Integer;
begin
  Result := False;
  VertexRect := TRect.Empty;
  if not SelectedShapeLayer(ShapeLayer) then
    Exit;
  Contours := ShapeLayer.Contours;
  if (FSelectedContourIndex < 0) or
    (FSelectedContourIndex > High(Contours)) or
    (FSelectedVertexIndex < 0) or (FSelectedVertexIndex >
    High(Contours[FSelectedContourIndex].Vertices)) then
    Exit;
  Vertex := Contours[FSelectedContourIndex].Vertices[FSelectedVertexIndex];
  X := ToScreenX(Vertex.Position.X);
  Y := ToScreenY(Vertex.Position.Y);
  HalfSize := VERTEX_HANDLE_SIZE div 2;
  VertexRect := Rect(X - HalfSize, Y - HalfSize,
    X - HalfSize + VERTEX_HANDLE_SIZE,
    Y - HalfSize + VERTEX_HANDLE_SIZE);
  Result := True;
end;

function TMapRakuShapeInteraction.SelectedBezierHandles(
  out Handles: TMapRakuBezierHandles): Boolean;
var
  Contours: TArray<TMapRakuContour>;
  HalfSize: Integer;
  ShapeLayer: TMapRakuShapeLayer;
  Vertex: TMapRakuVertex;
begin
  Result := False;
  Handles := Default(TMapRakuBezierHandles);
  if not SelectedShapeLayer(ShapeLayer) then
    Exit;
  Contours := ShapeLayer.Contours;
  if (FSelectedContourIndex < 0) or
    (FSelectedContourIndex > High(Contours)) or
    (FSelectedVertexIndex < 0) or (FSelectedVertexIndex >
    High(Contours[FSelectedContourIndex].Vertices)) then
    Exit;
  Vertex := Contours[FSelectedContourIndex].Vertices[FSelectedVertexIndex];
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
  Handles.IncomingRect := Rect(Handles.IncomingPoint.X - HalfSize,
    Handles.IncomingPoint.Y - HalfSize,
    Handles.IncomingPoint.X - HalfSize + BEZIER_CONTROL_HANDLE_SIZE,
    Handles.IncomingPoint.Y - HalfSize + BEZIER_CONTROL_HANDLE_SIZE);
  Handles.OutgoingRect := Rect(Handles.OutgoingPoint.X - HalfSize,
    Handles.OutgoingPoint.Y - HalfSize,
    Handles.OutgoingPoint.X - HalfSize + BEZIER_CONTROL_HANDLE_SIZE,
    Handles.OutgoingPoint.Y - HalfSize + BEZIER_CONTROL_HANDLE_SIZE);
  Result := True;
end;

end.
