// 共通ハンドルによる自由変形、せん断、遠近変形を開始時の状態から計算する。
unit MapRakuTransformInteraction;

interface

uses
  System.Classes, System.Types, Vcl.Controls, MapRakuDocument,
  MapRakuEditorState, MapRakuEditHistory,
  MapRakuSelectionGeometry, MapRakuProjectiveTransform;

type
  TMapRakuTransformInteraction = class
  private
    FDocument                 : TVectArtDocument;               // 操作対象を所有する文書。
    FEditorState              : TVectArtEditorState;            // 選択とグループ編集状態の参照元。
    FHistory                  : TVectArtEditHistory;             // 確定した変形を登録する履歴。
    FCanvasBounds             : TRect;                           // Document座標変換に使う表示領域。
    FZoom                     : Single;                          // Document座標変換に使う表示倍率。
    FLayers                   : TArray<TVectArtLayer>;           // グループを展開した実際の変形対象。
    FOriginal                 : TArray<TMapRakuTransform>; // ドラッグ開始時の各対象の変形。
    FStartQuad                : TMapRakuQuad;               // ドラッグ開始時の選択四辺形。
    FCurrentQuad              : TMapRakuQuad;               // 現在表示する選択四辺形。
    FStart                    : TPointF;                          // ドラッグ開始位置のDocument座標。
    FHandle                   : TVectArtSelectionHandle;         // 操作中の選択ハンドル。
    FMode                     : Integer;                         // 0:停止、1:ハンドル、2:移動、3:回転。
    FDistort                  : Boolean;                         // Ctrlで角移動または辺せん断を選んだ状態。
    FDeferredMoveNotification : Boolean;                         // 移動通知を確定まで保留している状態。
    FUniform                  : Boolean;                         // 通常文字の均等拡縮を維持する状態。
    function SelectedLayers: TArray<TVectArtLayer>;
    function LogicalPoint(X, Y: Integer): TPointF;
  public
    destructor Destroy; override;
    // 操作対象と画面・文書座標の対応を設定する。
    procedure Configure(Document: TVectArtDocument;
      History: TVectArtEditHistory; EditorState: TVectArtEditorState;
      const CanvasBounds: TRect; Zoom: Single);
    // 現在の選択について表示と入力で共有する枠を返す。
    function Geometry(out Value: TVectArtSelectionGeometry): Boolean;
    // 修飾付きハンドルと変形済み選択の操作を開始する。
    function MouseDown(Shift: TShiftState; X, Y: Integer): Boolean;
    // 開始時からの変形をプレビューへ適用する。
    function MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
    // 確定時は1件の履歴、キャンセル時は開始前の状態へ戻す。
    function Finish(Cancel: Boolean = False): Boolean;
    // ドラッグ中だけTrue。
    function Active: Boolean;
    // 変形済み選択を枠内から移動している間だけTrue。
    function Moving: Boolean;
    // 選択に非恒等変換が含まれるかを返す。
    function HasTransformedSelection: Boolean;
  end;

implementation

uses
  System.Math, System.Generics.Collections, MapRakuLayerGeometry,
  MapRakuLayerTransformCommands;

destructor TMapRakuTransformInteraction.Destroy;
begin
  if FDeferredMoveNotification and (FDocument <> nil) then
    FDocument.EndDeferredNotification;
  inherited Destroy;
end;

procedure AppendLeaves(Layer: TVectArtLayer; List: TList<TVectArtLayer>);
var I: Integer;
begin
  if Layer is TMapRakuGroupLayer then
    for I := 0 to TMapRakuGroupLayer(Layer).ChildCount-1 do
      AppendLeaves(TMapRakuGroupLayer(Layer)[I], List)
  else List.Add(Layer);
end;

function TMapRakuTransformInteraction.SelectedLayers: TArray<TVectArtLayer>;
var I: Integer;
begin
  Result := nil;
  if FDocument = nil then Exit;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
    Exit(FEditorState.GetOpenGroupChildren);
  for I := 1 to FDocument.LayerCount-1 do
    if FDocument.IsLayerSelected(I) then Result := Result + [FDocument[I]];
end;

function LayerTransformed(Layer: TVectArtLayer): Boolean;
var I: Integer;
begin
  if not Layer.Transform.IsIdentity then Exit(True);
  if Layer is TMapRakuGroupLayer then
    for I := 0 to TMapRakuGroupLayer(Layer).ChildCount-1 do
      if LayerTransformed(TMapRakuGroupLayer(Layer)[I]) then Exit(True);
  Result := False;
end;

function TMapRakuTransformInteraction.HasTransformedSelection: Boolean;
var Layer: TVectArtLayer;
begin
  for Layer in SelectedLayers do if LayerTransformed(Layer) then Exit(True);
  Result := False;
end;

procedure TMapRakuTransformInteraction.Configure(Document: TVectArtDocument;
  History: TVectArtEditHistory; EditorState: TVectArtEditorState;
  const CanvasBounds: TRect; Zoom: Single);
begin
  FDocument := Document; FHistory := History; FEditorState := EditorState;
  FCanvasBounds := CanvasBounds; FZoom := Zoom;
end;

function TMapRakuTransformInteraction.LogicalPoint(X, Y: Integer): TPointF;
begin
  Result := TPointF.Create((X-FCanvasBounds.Left)/FZoom - FDocument.CanvasLayer.Width*0.5,
    (Y-FCanvasBounds.Top)/FZoom - FDocument.CanvasLayer.Height*0.5);
end;

function TMapRakuTransformInteraction.Geometry(out Value: TVectArtSelectionGeometry): Boolean;
var Layers: TArray<TVectArtLayer>; Q: TMapRakuQuad;
  Bounds, B: TRectF; ScreenQuad: TVectArtScreenQuad; I, FrameOffset: Integer;
  StrokeWidth: Single; Layer: TVectArtLayer;
begin
  Result := False;
  if (FDocument = nil) or (FZoom <= 0) then Exit;
  Layers := SelectedLayers;
  if Length(Layers) = 0 then Exit;
  if Active then Q := FCurrentQuad
  else if Length(Layers) = 1 then
  begin
    if not TryGetMapRakuLayerQuad(Layers[0], Q) then Exit;
  end
  else
  begin
    if not TryGetMapRakuLayerBounds(Layers[0], Bounds) then Exit;
    for I := 1 to High(Layers) do
      if TryGetMapRakuLayerBounds(Layers[I], B) then Bounds := TRectF.Union(Bounds, B);
    Q := MapRakuRectQuad(Bounds);
  end;
  if not Active then FCurrentQuad := Q;
  for I := 0 to 3 do
    ScreenQuad[I] := Point(FCanvasBounds.Left + Round((Q[I].X + FDocument.CanvasLayer.Width*0.5)*FZoom),
      FCanvasBounds.Top + Round((Q[I].Y + FDocument.CanvasLayer.Height*0.5)*FZoom));
  Bounds := MapRakuQuadBounds(Q);
  if (Bounds.Width < 0.001) or (Bounds.Height < 0.001) then Exit;
  FrameOffset := SelectionFrameOffset(0, FZoom);
  if not Active and not HasTransformedSelection then
    for Layer in Layers do
    begin
      StrokeWidth := 0;
      if Layer is TMapRakuRectangleLineLayer then StrokeWidth := TMapRakuRectangleLineLayer(Layer).StrokeWidth
      else if Layer is TMapRakuArcLayer then StrokeWidth := TMapRakuArcLayer(Layer).StrokeWidth
      else if Layer is TMapRakuShapeLayer then StrokeWidth := TMapRakuShapeLayer(Layer).StrokeWidth
      else if (Layer is TVectArtPathLayer) and not TVectArtPathLayer(Layer).Closed then
        StrokeWidth := TVectArtPathLayer(Layer).StrokeWidth;
      FrameOffset := Max(FrameOffset, SelectionFrameOffset(StrokeWidth,FZoom));
    end;
  Value := BuildRotatedSelectionGeometry(ScreenQuad, FrameOffset);
  Result := True;
end;

function TMapRakuTransformInteraction.MouseDown(Shift: TShiftState; X, Y: Integer): Boolean;
var G: TVectArtSelectionGeometry; Selected: TArray<TVectArtLayer>;
  List: TList<TVectArtLayer>; Layer: TVectArtLayer; I: Integer; B: TRectF;
begin
  Result := False;
  if Active or (ssDouble in Shift) or not Geometry(G) then Exit;
  if (FEditorState <> nil) and (FEditorState.CurrentTool <> vetSelect) then Exit;
  Selected := SelectedLayers;
  for Layer in Selected do if Layer.Locked then Exit;
  FHandle := HitTestSelectionHandle(Point(X,Y), G);
  FMode := 0;
  if (FHandle <> vshNone) and
    ((ssCtrl in Shift) or (ssAlt in Shift) or (ssShift in Shift) or HasTransformedSelection) then
    FMode := 1
  else if HasTransformedSelection and HitTestRotationHandle(Point(X,Y), G) then FMode := 3
  else if HasTransformedSelection and not (ssCtrl in Shift) then
  begin
    B := MapRakuQuadBounds(FCurrentQuad);
    if B.Contains(LogicalPoint(X,Y)) then FMode := 2;
  end;
  if FMode = 0 then Exit;
  List := TList<TVectArtLayer>.Create;
  try
    for Layer in Selected do AppendLeaves(Layer, List);
    FLayers := List.ToArray;
  finally List.Free end;
  for Layer in FLayers do if Layer.Locked then begin FMode := 0; Exit end;
  SetLength(FOriginal, Length(FLayers));
  for I := 0 to High(FLayers) do FOriginal[I] := FLayers[I].Transform;
  FStartQuad := FCurrentQuad;
  FStart := LogicalPoint(X,Y);
  FDistort := ssCtrl in Shift;
  FUniform := (Length(Selected) = 1) and (Selected[0] is TMapRakuTextLayer) and
    (TMapRakuTextLayer(Selected[0]).TransformMode = slttmUniformScale);
  if FMode = 2 then
  begin
    FDocument.BeginDeferredNotification;
    FDeferredMoveNotification := True;
  end;
  Result := True;
end;

function TMapRakuTransformInteraction.MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
const UnitBounds: TRectF = (Left:0; Top:0; Right:1; Bottom:1);
var Q: TMapRakuQuad; Delta, P, A, H, V, Center: TPointF;
  T, Local, Inverse: TMapRakuTransform;
  I, Corner, NextCorner, Other: Integer; SX, SY, Angle, Distance, Dot: Double;
  Uniform: Boolean;
begin
  Result := Active;
  if not Result then Exit;
  Delta := LogicalPoint(X,Y)-FStart;
  Q := FStartQuad;
  if FMode = 2 then
    for I := 0 to 3 do Q[I] := Q[I]+Delta
  else if FMode = 3 then
  begin
    Center := (Q[0]+Q[2])*0.5;
    P := LogicalPoint(X,Y)-Center; V := FStart-Center;
    Angle := ArcTan2(P.Y,P.X)-ArcTan2(V.Y,V.X);
    if ssShift in Shift then Angle := DegToRad(Round(RadToDeg(Angle)/15)*15);
    for I := 0 to 3 do
    begin
      V := Q[I]-Center;
      Q[I] := Center+TPointF.Create(V.X*Cos(Angle)-V.Y*Sin(Angle), V.X*Sin(Angle)+V.Y*Cos(Angle));
    end;
  end
  else if FDistort then
  begin
    if ssShift in Shift then
    begin
      Angle := Round(ArcTan2(Delta.Y,Delta.X)/(Pi/4))*(Pi/4);
      Distance := Delta.X*Cos(Angle)+Delta.Y*Sin(Angle);
      Delta := TPointF.Create(Distance*Cos(Angle),Distance*Sin(Angle));
    end;
    Corner := (Ord(FHandle)-1) div 2;
    if Odd(Ord(FHandle)) then
    begin
      Q[Corner] := Q[Corner]+Delta;
      if ssAlt in Shift then
      begin
        // 水平方向は同じ上下辺、垂直方向は同じ左右辺の反対の角を連動させる。
        if Abs(Delta.X) >= Abs(Delta.Y) then Other := Corner xor 1
        else Other := 3-Corner;
        Q[Other] := Q[Other]-Delta;
      end;
    end
    else
    begin
      NextCorner := (Corner+1) mod 4;
      V := Q[NextCorner]-Q[Corner];
      Dot := (Delta.X*V.X+Delta.Y*V.Y)/Max(V.X*V.X+V.Y*V.Y, 1E-9);
      Delta := V*Dot;
      Q[Corner] := Q[Corner]+Delta; Q[NextCorner] := Q[NextCorner]+Delta;
    end;
  end
  else
  begin
    if not TryMapRakuQuadTransform(MapRakuRectQuad(UnitBounds), Q, Local) or
      not Local.Inverse(Inverse) then Exit;
    Corner := (Ord(FHandle)-1) div 2;
    if Odd(Ord(FHandle)) then H := MapRakuRectQuad(UnitBounds)[Corner]
    else H := (MapRakuRectQuad(UnitBounds)[Corner]+MapRakuRectQuad(UnitBounds)[(Corner+1) mod 4])*0.5;
    P := Inverse.Map(Local.Map(H)+Delta);
    A := TPointF.Create(1-H.X,1-H.Y);
    if ssAlt in Shift then A := TPointF.Create(0.5,0.5);
    SX := 1; SY := 1;
    if Abs(H.X-A.X) > 0.001 then SX := Max((P.X-A.X)/(H.X-A.X),0.01);
    if Abs(H.Y-A.Y) > 0.001 then SY := Max((P.Y-A.Y)/(H.Y-A.Y),0.01);
    Uniform := FUniform or (ssShift in Shift);
    if Uniform then
    begin
      if Abs(H.X-A.X) < 0.001 then SX := SY
      else if Abs(H.Y-A.Y) < 0.001 then SY := SX
      else begin SX := (SX+SY)*0.5; SY := SX end;
    end;
    for I := 0 to 3 do
    begin
      P := MapRakuRectQuad(UnitBounds)[I];
      Q[I] := Local.Map(TPointF.Create(A.X+(P.X-A.X)*SX,A.Y+(P.Y-A.Y)*SY));
    end;
  end;
  if not TryMapRakuQuadTransform(FStartQuad,Q,T) then Exit;
  for I := 0 to High(FLayers) do FLayers[I].Transform := FOriginal[I].ThenApply(T);
  FCurrentQuad := Q;
  FDocument.Changed;
end;

function TMapRakuTransformInteraction.Finish(Cancel: Boolean): Boolean;
var After: TArray<TMapRakuTransform>; I, J: Integer; Changed: Boolean;
begin
  Result := Active;
  if not Result then Exit;
  SetLength(After, Length(FLayers)); Changed := False;
  for I := 0 to High(FLayers) do
  begin
    After[I] := FLayers[I].Transform;
    for J := 0 to 8 do if Abs(After[I].Values[J]-FOriginal[I].Values[J]) > 1E-9 then Changed := True;
    if Cancel then FLayers[I].Transform := FOriginal[I];
  end;
  if Changed and not Cancel and (FHistory <> nil) then
    FHistory.AddApplied(CreateMapRakuLayerTransformCommand(FDocument,
      FLayers, FOriginal, After));
  FDocument.Changed;
  FMode := 0; FLayers := nil; FOriginal := nil;
  if FDeferredMoveNotification then
  begin
    FDeferredMoveNotification := False;
    FDocument.EndDeferredNotification;
  end;
end;

function TMapRakuTransformInteraction.Active: Boolean;
begin
  Result := FMode <> 0;
end;

function TMapRakuTransformInteraction.Moving: Boolean;
begin
  Result := FMode = 2;
end;

end.
