// 文字パス上の文字選択、個別移動、個別拡縮と履歴確定を管理する。
unit MapRakuTextPathCharacterInteraction;

interface

uses
  System.Classes, System.Types, Vcl.Controls, MapRakuDocument,
  MapRakuEditHistory, MapRakuSelectionGeometry;

type
  // 文字単位ドラッグで、位置と倍率のどちらを変更しているかを表す。
  TMapRakuTextPathCharacterDragMode = (sltpcdmNone, sltpcdmMove,
    sltpcdmResize);

  // 文字パスの選択文字だけに閉じた入力状態を保持し、Document更新とUndo確定を行う。
  TMapRakuTextPathCharacterInteraction = class
  private
    FAdvanceWidthStart: Single;
    FAnchor: TPoint;
    FCanvasBounds: TRect;
    FDocument: TVectArtDocument;
    FDragHandle: TVectArtSelectionHandle;
    FDragLayerIndex: Integer;
    FDragMode: TMapRakuTextPathCharacterDragMode;
    FDragStartMouse: TPoint;
    FEditHistory: TVectArtEditHistory;
    FMousePathDistanceStart: Single;
    FOffsetStart: Single;
    FPathDistanceStart: Single;
    FScaleStart: Single;
    FSelectedCharacter: Integer;
    FSelectionLayerIndex: Integer;
    FStartData: TMapRakuTextData;
    FZoom: Single;
    function HitTestExpandedHandle(const PointValue: TPoint;
      const Geometry: TVectArtSelectionGeometry): TVectArtSelectionHandle;
    function ToLogicalX(Value: Single): Single;
    function ToLogicalY(Value: Single): Single;
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
  public
    // 未選択かつドラッグしていない初期状態を作成する。
    constructor Create;
    // 操作対象と座標変換を更新し、単一選択レイヤーが変われば文字選択を解除する。
    procedure Configure(ADocument: TVectArtDocument;
      AEditHistory: TVectArtEditHistory; const ACanvasBounds: TRect;
      AZoom: Single);
    // 画面位置にある文字セルを拡張判定で返し、該当しなければ-1を返す。
    function CharacterAt(X, Y: Integer): Integer;
    // 選択文字上の個別移動または個別拡縮を開始し、開始した方式を返す。
    function BeginDragAt(X, Y: Integer): TMapRakuTextPathCharacterDragMode;
    // 進行中の個別編集をDocumentへ反映する。
    function DragTo(Shift: TShiftState; X, Y: Integer): Boolean;
    // 個別編集の前後差分を1件のUndo履歴として確定する。
    procedure CommitDrag;
    // 履歴を追加せず、進行中のドラッグ状態だけを終了する。
    procedure EndDrag;
    // 現在位置が選択文字の操作領域なら対応カーソルを返す。
    function CursorAt(X, Y: Integer; out Cursor: TCursor): Boolean;
    // 選択文字セルの回転済み枠と四隅ハンドルを返す。
    function SelectedGeometry(out Geometry: TVectArtSelectionGeometry): Boolean;
    // ドラッグ開始時に確定した四隅ハンドルを返す。
    property DragHandle: TVectArtSelectionHandle read FDragHandle;
    // 現在の文字単位ドラッグ方式を返す。
    property DragMode: TMapRakuTextPathCharacterDragMode read FDragMode;
    // 選択中のUTF-16文字位置。未選択は-1を指定する。
    property SelectedCharacter: Integer read FSelectedCharacter
      write FSelectedCharacter;
  end;

implementation

uses
  System.Math, MapRakuGeometry, MapRakuPathOperations,
  MapRakuTextCommands, MapRakuTextPathGeometry;

const
  CHARACTER_HIT_PADDING = 6;

function SameSingleArrays(const Left, Right: TArray<Single>): Boolean;
var
  I: Integer;
begin
  if Length(Left) <> Length(Right) then
    Exit(False);
  for I := 0 to High(Left) do
    if not SameValue(Left[I], Right[I]) then
      Exit(False);
  Result := True;
end;

function SameBooleanArrays(const Left, Right: TArray<Boolean>): Boolean;
var
  I: Integer;
begin
  if Length(Left) <> Length(Right) then
    Exit(False);
  for I := 0 to High(Left) do
    if Left[I] <> Right[I] then
      Exit(False);
  Result := True;
end;

constructor TMapRakuTextPathCharacterInteraction.Create;
begin
  inherited Create;
  FDragLayerIndex := -1;
  FSelectedCharacter := -1;
  FSelectionLayerIndex := -1;
end;

procedure TMapRakuTextPathCharacterInteraction.Configure(
  ADocument: TVectArtDocument; AEditHistory: TVectArtEditHistory;
  const ACanvasBounds: TRect; AZoom: Single);
var
  SelectedLayerIndex: Integer;
begin
  SelectedLayerIndex := -1;
  if (ADocument <> nil) and (ADocument.SelectionCount = 1) then
    SelectedLayerIndex := ADocument.SelectedIndex;
  if (ADocument <> FDocument) or
    (SelectedLayerIndex <> FSelectionLayerIndex) then
  begin
    FSelectedCharacter := -1;
    FSelectionLayerIndex := SelectedLayerIndex;
    EndDrag;
  end;
  FDocument := ADocument;
  FEditHistory := AEditHistory;
  FCanvasBounds := ACanvasBounds;
  FZoom := AZoom;
end;

function TMapRakuTextPathCharacterInteraction.ToLogicalX(
  Value: Single): Single;
begin
  Result := ScreenToLogicalX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TMapRakuTextPathCharacterInteraction.ToLogicalY(
  Value: Single): Single;
begin
  Result := ScreenToLogicalY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TMapRakuTextPathCharacterInteraction.ToScreenX(
  Value: Single): Integer;
begin
  Result := LogicalToScreenX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TMapRakuTextPathCharacterInteraction.ToScreenY(
  Value: Single): Integer;
begin
  Result := LogicalToScreenY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TMapRakuTextPathCharacterInteraction.HitTestExpandedHandle(
  const PointValue: TPoint; const Geometry: TVectArtSelectionGeometry):
  TVectArtSelectionHandle;
var
  Center: TPoint;
  DistanceSquared: Single;
  Handle: TVectArtSelectionHandle;
  HitRect: TRect;
  NearestDistanceSquared: Single;
begin
  Result := vshNone;
  NearestDistanceSquared := MaxSingle;
  for Handle := vshTopLeft to vshLeft do
    if not Geometry.Handles[Handle].IsEmpty then
    begin
      HitRect := Geometry.Handles[Handle];
      InflateRect(HitRect, CHARACTER_HIT_PADDING, CHARACTER_HIT_PADDING);
      if PtInRect(HitRect, PointValue) then
      begin
        Center := Geometry.Handles[Handle].CenterPoint;
        DistanceSquared := Sqr(PointValue.X - Center.X) +
          Sqr(PointValue.Y - Center.Y);
        if DistanceSquared < NearestDistanceSquared then
        begin
          Result := Handle;
          NearestDistanceSquared := DistanceSquared;
        end;
      end;
    end;
end;

function TMapRakuTextPathCharacterInteraction.CharacterAt(X,
  Y: Integer): Integer;
var
  CandidateDistance: Single;
  Delta: TPointF;
  HitPadding: Single;
  I: Integer;
  Layer: TMapRakuTextPathLayer;
  LocalX: Single;
  LocalY: Single;
  NearestDistance: Single;
  Placements: TArray<TMapRakuTextPathPlacement>;
  PointValue: TPointF;
begin
  Result := -1;
  if (FDocument = nil) or (FZoom <= 0) or
    (FDocument.SelectionCount <> 1) or
    (FDocument.SelectedIndex <= 0) or
    not (FDocument[FDocument.SelectedIndex] is
      TMapRakuTextPathLayer) then
    Exit;
  Layer := TMapRakuTextPathLayer(FDocument[FDocument.SelectedIndex]);
  Placements := BuildMapRakuTextPathPlacements(Layer);
  PointValue := TPointF.Create(ToLogicalX(X), ToLogicalY(Y));
  HitPadding := CHARACTER_HIT_PADDING / FZoom;
  NearestDistance := MaxSingle;
  for I := 0 to High(Placements) do
  begin
    Delta := TPointF.Create(PointValue.X - Placements[I].Anchor.X,
      PointValue.Y - Placements[I].Anchor.Y);
    LocalX := Delta.X * Placements[I].TextXAxis.X +
      Delta.Y * Placements[I].TextXAxis.Y;
    LocalY := Delta.X * Placements[I].TextYAxis.X +
      Delta.Y * Placements[I].TextYAxis.Y;
    if (LocalX >= Placements[I].LocalBounds.Left - HitPadding) and
      (LocalX <= Placements[I].LocalBounds.Right + HitPadding) and
      (LocalY >= Placements[I].LocalBounds.Top - HitPadding) and
      (LocalY <= Placements[I].LocalBounds.Bottom + HitPadding) then
    begin
      CandidateDistance := Sqr(LocalX -
        (Placements[I].LocalBounds.Left +
         Placements[I].LocalBounds.Right) * 0.5) +
        Sqr(LocalY - (Placements[I].LocalBounds.Top +
         Placements[I].LocalBounds.Bottom) * 0.5);
      if CandidateDistance < NearestDistance then
      begin
        Result := Placements[I].CharacterIndex;
        NearestDistance := CandidateDistance;
      end;
    end;
  end;
end;

function TMapRakuTextPathCharacterInteraction.SelectedGeometry(
  out Geometry: TVectArtSelectionGeometry): Boolean;
var
  I: Integer;
  J: Integer;
  Layer: TMapRakuTextPathLayer;
  Placements: TArray<TMapRakuTextPathPlacement>;
  ScreenQuad: TVectArtScreenQuad;
begin
  Result := False;
  Geometry := Default(TVectArtSelectionGeometry);
  if (FSelectedCharacter < 0) or (FDocument = nil) or
    (FDocument.SelectionCount <> 1) or (FDocument.SelectedIndex <= 0) or
    not (FDocument[FDocument.SelectedIndex] is
      TMapRakuTextPathLayer) then
    Exit;
  Layer := TMapRakuTextPathLayer(FDocument[FDocument.SelectedIndex]);
  Placements := BuildMapRakuTextPathPlacements(Layer);
  for I := 0 to High(Placements) do
    if Placements[I].CharacterIndex = FSelectedCharacter then
    begin
      for J := 0 to High(ScreenQuad) do
        ScreenQuad[J] := Point(ToScreenX(Placements[I].Corners[J].X),
          ToScreenY(Placements[I].Corners[J].Y));
      Geometry := BuildRotatedSelectionGeometry(ScreenQuad,
        SelectionFrameOffset(0, FZoom));
      Geometry.Handles[vshTop] := TRect.Empty;
      Geometry.Handles[vshRight] := TRect.Empty;
      Geometry.Handles[vshBottom] := TRect.Empty;
      Geometry.Handles[vshLeft] := TRect.Empty;
      Geometry.PrimaryRotationHandle := TRect.Empty;
      Geometry.RotationStem[0] := TPoint.Zero;
      Geometry.RotationStem[1] := TPoint.Zero;
      Exit(True);
    end;
  FSelectedCharacter := -1;
end;

function TMapRakuTextPathCharacterInteraction.BeginDragAt(X,
  Y: Integer): TMapRakuTextPathCharacterDragMode;
var
  CharacterScales: TArray<Single>;
  Geometry: TVectArtSelectionGeometry;
  I: Integer;
  J: Integer;
  Layer: TMapRakuTextPathLayer;
  NaturalPathDistance: Single;
  PathDistance: Single;
  PathPoints: TArray<TPointF>;
  Placements: TArray<TMapRakuTextPathPlacement>;
begin
  Result := sltpcdmNone;
  if not SelectedGeometry(Geometry) or
    FDocument[FDocument.SelectedIndex].Locked then
    Exit;
  FDragHandle := HitTestSelectionHandle(Point(X, Y), Geometry);
  if (FDragHandle = vshNone) and
    (CharacterAt(X, Y) <> FSelectedCharacter) then
    FDragHandle := HitTestExpandedHandle(Point(X, Y), Geometry);
  Layer := TMapRakuTextPathLayer(FDocument[FDocument.SelectedIndex]);
  Placements := BuildMapRakuTextPathPlacements(Layer);
  if FDragHandle <> vshNone then
  begin
    FDragMode := sltpcdmResize;
    FDragLayerIndex := FDocument.SelectedIndex;
    FStartData := CaptureMapRakuTextData(Layer);
    CharacterScales := FStartData.CharacterScales;
    if FSelectedCharacter < Length(CharacterScales) then
      FScaleStart := CharacterScales[FSelectedCharacter]
    else
      FScaleStart := 1.0;
    for I := 0 to High(Placements) do
      if Placements[I].CharacterIndex = FSelectedCharacter then
      begin
        FAnchor := Point(ToScreenX(Placements[I].Anchor.X),
          ToScreenY(Placements[I].Anchor.Y));
        Break;
      end;
    FDragStartMouse := Point(X, Y);
    Exit(FDragMode);
  end;
  if CharacterAt(X, Y) <> FSelectedCharacter then
    Exit;
  PathPoints := FlattenMapRakuPathVertices(
    Layer.EditablePathVertices, 32);
  if not MapRakuPolylineNearestDistance(PathPoints,
    TPointF.Create(ToLogicalX(X), ToLogicalY(Y)), PathDistance) then
    Exit;
  for I := 0 to High(Placements) do
    if Placements[I].CharacterIndex = FSelectedCharacter then
    begin
      FDragMode := sltpcdmMove;
      FDragLayerIndex := FDocument.SelectedIndex;
      FStartData := CaptureMapRakuTextData(Layer);
      FAdvanceWidthStart := Placements[I].PathAdvance;
      FPathDistanceStart := Placements[I].PathDistance;
      NaturalPathDistance := FAdvanceWidthStart * 0.5;
      for J := 0 to I - 1 do
        NaturalPathDistance := NaturalPathDistance +
          Placements[J].PathAdvance;
      // 手動化すると配置基準が自然位置へ戻るため、表示中の実位置を
      // 個別オフセットへ変換して最初のMouseMoveで跳ばないようにする。
      FOffsetStart := FPathDistanceStart - NaturalPathDistance;
      FMousePathDistanceStart := PathDistance;
      FDragStartMouse := Point(X, Y);
      Exit(FDragMode);
    end;
end;

function TMapRakuTextPathCharacterInteraction.DragTo(
  Shift: TShiftState; X, Y: Integer): Boolean;
var
  CharacterPathOffsets: TArray<Single>;
  CharacterPositionManual: TArray<Boolean>;
  CharacterScales: TArray<Single>;
  CurrentDistance: Single;
  DeltaRatio: Single;
  I: Integer;
  Layer: TMapRakuTextPathLayer;
  PathDistance: Single;
  PathLength: Single;
  PathPoints: TArray<TPointF>;
  StartDistance: Single;
  TextData: TMapRakuTextData;
begin
  Result := False;
  if (FDragMode = sltpcdmNone) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or
    not (FDocument[FDragLayerIndex] is TMapRakuTextPathLayer) then
    Exit;
  if FDragMode = sltpcdmMove then
  begin
    Layer := TMapRakuTextPathLayer(FDocument[FDragLayerIndex]);
    PathPoints := FlattenMapRakuPathVertices(
      Layer.EditablePathVertices, 32);
    if not MapRakuPolylineNearestDistance(PathPoints,
      TPointF.Create(ToLogicalX(X), ToLogicalY(Y)), PathDistance) then
      Exit(False);
    PathLength := MapRakuPolylineLength(PathPoints);
    PathDistance := EnsureRange(FPathDistanceStart + PathDistance -
      FMousePathDistanceStart, FAdvanceWidthStart * 0.5,
      PathLength - FAdvanceWidthStart * 0.5);
    TextData := FStartData;
    CharacterPathOffsets := Copy(TextData.CharacterPathOffsets);
    I := Length(CharacterPathOffsets);
    if I <= FSelectedCharacter then
    begin
      SetLength(CharacterPathOffsets, FSelectedCharacter + 1);
      while I < Length(CharacterPathOffsets) do
      begin
        CharacterPathOffsets[I] := 0;
        Inc(I);
      end;
    end;
    CharacterPathOffsets[FSelectedCharacter] := FOffsetStart +
      PathDistance - FPathDistanceStart;
    TextData.CharacterPathOffsets := CharacterPathOffsets;
    CharacterPositionManual := Copy(TextData.CharacterPositionManual);
    I := Length(CharacterPositionManual);
    if I <= FSelectedCharacter then
    begin
      SetLength(CharacterPositionManual, FSelectedCharacter + 1);
      while I < Length(CharacterPositionManual) do
      begin
        CharacterPositionManual[I] := False;
        Inc(I);
      end;
    end;
    CharacterPositionManual[FSelectedCharacter] := True;
    TextData.CharacterPositionManual := CharacterPositionManual;
    FDocument.SetTextData(FDragLayerIndex, TextData);
    Exit(True);
  end;
  StartDistance := Hypot(FDragStartMouse.X - FAnchor.X,
    FDragStartMouse.Y - FAnchor.Y);
  CurrentDistance := Hypot(X - FAnchor.X, Y - FAnchor.Y);
  if StartDistance <= 0.001 then
    Exit(False);
  DeltaRatio := CurrentDistance / StartDistance;
  if ssShift in Shift then
    DeltaRatio := 1.0 + (DeltaRatio - 1.0) * 0.1;
  TextData := FStartData;
  CharacterScales := Copy(TextData.CharacterScales);
  I := Length(CharacterScales);
  if I <= FSelectedCharacter then
  begin
    SetLength(CharacterScales, FSelectedCharacter + 1);
    while I < Length(CharacterScales) do
    begin
      CharacterScales[I] := 1.0;
      Inc(I);
    end;
  end;
  CharacterScales[FSelectedCharacter] := EnsureRange(
    FScaleStart * DeltaRatio,
    SCREEN_LAYOUT_TEXT_PATH_CHARACTER_SCALE_MIN,
    SCREEN_LAYOUT_TEXT_PATH_CHARACTER_SCALE_MAX);
  TextData.CharacterScales := CharacterScales;
  FDocument.SetTextData(FDragLayerIndex, TextData);
  Result := True;
end;

procedure TMapRakuTextPathCharacterInteraction.CommitDrag;
var
  NewData: TMapRakuTextData;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or
    not (FDocument[FDragLayerIndex] is TMapRakuTextPathLayer) then
    Exit;
  NewData := CaptureMapRakuTextData(
    TMapRakuTextPathLayer(FDocument[FDragLayerIndex]));
  if SameSingleArrays(FStartData.CharacterPathOffsets,
      NewData.CharacterPathOffsets) and
    SameBooleanArrays(FStartData.CharacterPositionManual,
      NewData.CharacterPositionManual) and
    SameSingleArrays(FStartData.CharacterScales,
      NewData.CharacterScales) then
    Exit;
  FEditHistory.AddApplied(TMapRakuTextDataCommand.Create(FDocument,
    FDragLayerIndex, FStartData, NewData));
end;

procedure TMapRakuTextPathCharacterInteraction.EndDrag;
begin
  FDragMode := sltpcdmNone;
  FDragHandle := vshNone;
  FDragLayerIndex := -1;
end;

function TMapRakuTextPathCharacterInteraction.CursorAt(X,
  Y: Integer; out Cursor: TCursor): Boolean;
var
  Geometry: TVectArtSelectionGeometry;
  Handle: TVectArtSelectionHandle;
begin
  Cursor := crDefault;
  if FDragMode = sltpcdmMove then
    Cursor := crSizeAll
  else if FDragMode = sltpcdmResize then
    Cursor := SelectionHandleCursor(FDragHandle)
  else if SelectedGeometry(Geometry) and
    not FDocument[FDocument.SelectedIndex].Locked then
  begin
    Handle := HitTestSelectionHandle(Point(X, Y), Geometry);
    if Handle <> vshNone then
      Cursor := SelectionHandleCursor(Handle)
    else if CharacterAt(X, Y) = FSelectedCharacter then
      Cursor := crSizeAll
    else
    begin
      Handle := HitTestExpandedHandle(Point(X, Y), Geometry);
      if Handle <> vshNone then
        Cursor := SelectionHandleCursor(Handle);
    end;
  end;
  Result := Cursor <> crDefault;
end;

end.
