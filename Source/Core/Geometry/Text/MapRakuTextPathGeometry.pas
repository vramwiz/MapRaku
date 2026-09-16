// 文字パスを文字単位の配置セルへ展開し、描画と選択で共有する幾何情報を生成する。
unit MapRakuTextPathGeometry;

interface

uses
  System.Skia, System.Types, MapRakuDocument;

type
  TMapRakuTextPathQuad = array[0..3] of TPointF;

  TMapRakuTextPathPlacement = record
    CharacterIndex: Integer;                // 文字単位配列内の0基準位置。
    TextIndex: Integer;                     // 元文字列内のUTF-16開始位置。
    TextUnit: string;                       // サロゲートペアを分割しない描画単位。
    PathDistance: Single;                   // Path始点から接触面中央までの距離。
    Anchor: TPointF;                        // Path上に置く文字セル接触面の中央。
    Tangent: TPointF;                       // Anchor位置でのPath進行方向の単位ベクトル。
    AngleDegrees: Single;                   // 文字描画へ適用する文書座標上の角度。
    AdvanceWidth: Single;                   // フォントが返した文字セルの送り幅。
    PathAdvance: Single;                    // Path進行方向でこの文字セルが占める長さ。
    Scale: Single;                          // この文字セルへ適用した個別の均等倍率。
    CellHeight: Single;                     // ascentからdescentまでの文字セル高。
    LocalBounds: TRectF;                    // Anchor基準かつ個別倍率適用後の文字セル範囲。
    TextOrigin: TPointF;                    // 個別倍率適用前の文字描画ベースライン原点。
    TextXAxis: TPointF;                     // 文書座標上の文字セル右方向の単位ベクトル。
    TextYAxis: TPointF;                     // 文書座標上の文字セル下方向の単位ベクトル。
    CollisionAdjusted: Boolean;             // 直前文字との重なりを自動間隔で解消した場合にTrue。
    CollidesWithPrevious: Boolean;          // 手動位置またはPath端により重なりが残る場合にTrue。
    Corners: TMapRakuTextPathQuad;     // 左上から時計回りの文書座標四隅。
  end;

// 指定された文字セルの面中央をPath上へ置き、Pathに収まる文字の配置結果を返す。
function BuildMapRakuTextPathPlacements(
  Layer: TMapRakuTextPathLayer; const Font: ISkFont = nil):
  TArray<TMapRakuTextPathPlacement>;
// 配置済み文字セル全体の文書座標外接範囲を返す。
function TryGetMapRakuTextPathBounds(Layer: TMapRakuTextPathLayer;
  out Bounds: TRectF): Boolean;
// 配置済みのいずれかの文字セルに文書座標点が含まれるかを返す。
function PointInMapRakuTextPath(Layer: TMapRakuTextPathLayer;
  const Point: TPointF): Boolean;

implementation

uses
  System.Math, MapRakuGeometry, MapRakuPathOperations,
  MapRakuTextGeometry;

function TextPathQuadsOverlap(const Left,
  Right: TMapRakuTextPathQuad): Boolean;
const
  MINIMUM_OVERLAP = 0.01;
var
  AxisX: Single;
  AxisY: Single;
  EdgeIndex: Integer;
  I: Integer;
  LeftMaximum: Single;
  LeftMinimum: Single;
  Projection: Single;
  QuadIndex: Integer;
  RightMaximum: Single;
  RightMinimum: Single;
begin
  for QuadIndex := 0 to 1 do
    for EdgeIndex := 0 to 3 do
    begin
      if QuadIndex = 0 then
      begin
        AxisX := -(Left[(EdgeIndex + 1) mod 4].Y - Left[EdgeIndex].Y);
        AxisY := Left[(EdgeIndex + 1) mod 4].X - Left[EdgeIndex].X;
      end
      else
      begin
        AxisX := -(Right[(EdgeIndex + 1) mod 4].Y - Right[EdgeIndex].Y);
        AxisY := Right[(EdgeIndex + 1) mod 4].X - Right[EdgeIndex].X;
      end;
      LeftMinimum := MaxSingle;
      LeftMaximum := -MaxSingle;
      RightMinimum := MaxSingle;
      RightMaximum := -MaxSingle;
      for I := 0 to 3 do
      begin
        Projection := Left[I].X * AxisX + Left[I].Y * AxisY;
        LeftMinimum := Min(LeftMinimum, Projection);
        LeftMaximum := Max(LeftMaximum, Projection);
        Projection := Right[I].X * AxisX + Right[I].Y * AxisY;
        RightMinimum := Min(RightMinimum, Projection);
        RightMaximum := Max(RightMaximum, Projection);
      end;
      if Min(LeftMaximum, RightMaximum) -
        Max(LeftMinimum, RightMinimum) <= MINIMUM_OVERLAP then
        Exit(False);
    end;
  Result := True;
end;

function BuildMapRakuTextPathPlacements(
  Layer: TMapRakuTextPathLayer; const Font: ISkFont):
  TArray<TMapRakuTextPathPlacement>;
var
  ActiveFont: ISkFont;
  AngleDegrees: Single;
  CellHeight: Single;
  CharacterIndex: Integer;
  CharacterPathOffsets: TArray<Single>;
  CharacterPositionManual: TArray<Boolean>;
  CharacterScales: TArray<Single>;
  CollisionHigh: Single;
  CollisionLow: Single;
  CollisionStep: Single;
  CollisionTest: Single;
  CollisionTrial: Integer;
  CursorDistance: Single;
  FontMetrics: TSkFontMetrics;
  I: Integer;
  NaturalCursorDistance: Single;
  PathLength: Single;
  PathPoint: TPointF;
  PathPoints: TArray<TPointF>;
  Placement: TMapRakuTextPathPlacement;
  PlacementCursorDistance: Single;
  PreviousManual: Boolean;
  Tangent: TPointF;
  UnitLength: Integer;
  UnitManual: Boolean;
  UnitPathAdvance: Single;
  UnitPathDistance: Single;
  UnitPathOffset: Single;
  UnitScale: Single;
  UnitText: string;
  UnitWidth: Single;

  function TransformCellPoint(LocalX, LocalY: Single): TPointF;
  begin
    Result := TPointF.Create(PathPoint.X + Placement.TextXAxis.X * LocalX +
      Placement.TextYAxis.X * LocalY,
      PathPoint.Y + Placement.TextXAxis.Y * LocalX +
      Placement.TextYAxis.Y * LocalY);
  end;

  procedure UpdatePlacementAtDistance(Distance: Single);
  begin
    MapRakuPolylinePointAtDistance(PathPoints, Distance,
      PathPoint, Tangent);
    AngleDegrees := RadToDeg(ArcTan2(Tangent.Y, Tangent.X));
    case Layer.Attachment of
      sltpaTop:
        begin
          Placement.LocalBounds := TRectF.Create(-UnitWidth * 0.5, 0,
            UnitWidth * 0.5, Placement.CellHeight);
          Placement.TextOrigin := TPointF.Create(
            -UnitWidth / UnitScale * 0.5, -FontMetrics.Ascent);
        end;
      sltpaLeft:
        begin
          AngleDegrees := AngleDegrees + 90;
          Placement.LocalBounds := TRectF.Create(0,
            -Placement.CellHeight * 0.5, UnitWidth,
            Placement.CellHeight * 0.5);
          Placement.TextOrigin := TPointF.Create(0,
            -(FontMetrics.Ascent + FontMetrics.Descent) * 0.5);
        end;
      sltpaRight:
        begin
          AngleDegrees := AngleDegrees - 90;
          Placement.LocalBounds := TRectF.Create(-UnitWidth,
            -Placement.CellHeight * 0.5, 0,
            Placement.CellHeight * 0.5);
          Placement.TextOrigin := TPointF.Create(-UnitWidth / UnitScale,
            -(FontMetrics.Ascent + FontMetrics.Descent) * 0.5);
        end;
    else
      Placement.LocalBounds := TRectF.Create(-UnitWidth * 0.5,
        -Placement.CellHeight, UnitWidth * 0.5, 0);
      Placement.TextOrigin := TPointF.Create(
        -UnitWidth / UnitScale * 0.5, -FontMetrics.Descent);
    end;
    Placement.TextXAxis := TPointF.Create(Cos(DegToRad(AngleDegrees)),
      Sin(DegToRad(AngleDegrees)));
    Placement.TextYAxis := TPointF.Create(-Placement.TextXAxis.Y,
      Placement.TextXAxis.X);
    if Layer.FlipHorizontal xor Layer.FlipVertical then
      Placement.TextYAxis := TPointF.Create(-Placement.TextYAxis.X,
        -Placement.TextYAxis.Y);
    Placement.PathDistance := Distance;
    Placement.Anchor := PathPoint;
    Placement.Tangent := Tangent;
    Placement.AngleDegrees := AngleDegrees;
    Placement.Corners[0] := TransformCellPoint(Placement.LocalBounds.Left,
      Placement.LocalBounds.Top);
    Placement.Corners[1] := TransformCellPoint(Placement.LocalBounds.Right,
      Placement.LocalBounds.Top);
    Placement.Corners[2] := TransformCellPoint(Placement.LocalBounds.Right,
      Placement.LocalBounds.Bottom);
    Placement.Corners[3] := TransformCellPoint(Placement.LocalBounds.Left,
      Placement.LocalBounds.Bottom);
  end;

begin
  Result := nil;
  if (Layer = nil) or (Layer.Text = '') then
    Exit;
  ActiveFont := Font;
  if ActiveFont = nil then
    ActiveFont := CreateMapRakuTextFont(Layer.FontFamily,
      Layer.FontSize, Layer.FontStyle);
  if ActiveFont = nil then
    Exit;
  PathPoints := FlattenMapRakuPathVertices(
    Layer.EditablePathVertices, 32);
  PathLength := MapRakuPolylineLength(PathPoints);
  if PathLength <= 0 then
    Exit;
  ActiveFont.GetMetrics(FontMetrics);
  CellHeight := Max(FontMetrics.Descent - FontMetrics.Ascent, 1.0);
  CharacterPathOffsets := Layer.CharacterPathOffsets;
  CharacterPositionManual := Layer.CharacterPositionManual;
  CharacterScales := Layer.CharacterScales;
  CursorDistance := 0;
  NaturalCursorDistance := 0;
  CharacterIndex := 0;
  PreviousManual := False;
  I := 1;
  while I <= Length(Layer.Text) do
  begin
    UnitLength := MapRakuTextUnitLengthAt(Layer.Text, I);
    UnitText := Copy(Layer.Text, I, UnitLength);
    if CharacterIndex < Length(CharacterScales) then
      UnitScale := CharacterScales[CharacterIndex]
    else
      UnitScale := 1.0;
    if CharacterIndex < Length(CharacterPathOffsets) then
      UnitPathOffset := CharacterPathOffsets[CharacterIndex]
    else
      UnitPathOffset := 0;
    UnitManual := (CharacterIndex < Length(CharacterPositionManual)) and
      CharacterPositionManual[CharacterIndex];
    UnitWidth := ActiveFont.MeasureText(UnitText) * UnitScale;
    if UnitWidth <= 0 then
    begin
      Inc(I, UnitLength);
      Inc(CharacterIndex);
      Continue;
    end;
    if Layer.Attachment in [sltpaLeft, sltpaRight] then
      UnitPathAdvance := CellHeight * UnitScale
    else
      UnitPathAdvance := UnitWidth;
    if UnitManual then
      PlacementCursorDistance := NaturalCursorDistance
    else
      PlacementCursorDistance := CursorDistance;
    if PlacementCursorDistance + UnitPathAdvance > PathLength then
      Break;
    UnitPathDistance := EnsureRange(
      PlacementCursorDistance + UnitPathAdvance * 0.5 + UnitPathOffset,
      UnitPathAdvance * 0.5, PathLength - UnitPathAdvance * 0.5);
    Placement := Default(TMapRakuTextPathPlacement);
    Placement.CharacterIndex := CharacterIndex;
    Placement.TextIndex := I;
    Placement.TextUnit := UnitText;
    Placement.AdvanceWidth := UnitWidth;
    Placement.PathAdvance := UnitPathAdvance;
    Placement.Scale := UnitScale;
    Placement.CellHeight := CellHeight * UnitScale;
    UpdatePlacementAtDistance(UnitPathDistance);
    if Length(Result) > 0 then
    begin
      Placement.CollidesWithPrevious := TextPathQuadsOverlap(
        Result[High(Result)].Corners, Placement.Corners);
      if Placement.CollidesWithPrevious and
        not PreviousManual and not UnitManual then
      begin
        CollisionLow := UnitPathDistance;
        CollisionHigh := UnitPathDistance;
        CollisionStep := Max(UnitPathAdvance * 0.1, 0.5);
        while Placement.CollidesWithPrevious and
          (CollisionHigh < PathLength - UnitPathAdvance * 0.5) do
        begin
          CollisionHigh := Min(CollisionHigh + CollisionStep,
            PathLength - UnitPathAdvance * 0.5);
          UpdatePlacementAtDistance(CollisionHigh);
          Placement.CollidesWithPrevious := TextPathQuadsOverlap(
            Result[High(Result)].Corners, Placement.Corners);
        end;
        if not Placement.CollidesWithPrevious then
        begin
          for CollisionTrial := 1 to 12 do
          begin
            CollisionTest := (CollisionLow + CollisionHigh) * 0.5;
            UpdatePlacementAtDistance(CollisionTest);
            if TextPathQuadsOverlap(Result[High(Result)].Corners,
              Placement.Corners) then
              CollisionLow := CollisionTest
            else
              CollisionHigh := CollisionTest;
          end;
          UpdatePlacementAtDistance(CollisionHigh);
          Placement.CollisionAdjusted := True;
        end;
      end;
    end;
    Result := Result + [Placement];
    NaturalCursorDistance := NaturalCursorDistance + UnitPathAdvance;
    if UnitManual then
      CursorDistance := NaturalCursorDistance
    else if Placement.CollisionAdjusted then
      CursorDistance := Max(CursorDistance + UnitPathAdvance,
        Placement.PathDistance + UnitPathAdvance * 0.5)
    else
      CursorDistance := CursorDistance + UnitPathAdvance;
    PreviousManual := UnitManual;
    Inc(I, UnitLength);
    Inc(CharacterIndex);
  end;
end;

function TryGetMapRakuTextPathBounds(Layer: TMapRakuTextPathLayer;
  out Bounds: TRectF): Boolean;
var
  I: Integer;
  J: Integer;
  Placements: TArray<TMapRakuTextPathPlacement>;
begin
  Result := False;
  Bounds := TRectF.Empty;
  Placements := BuildMapRakuTextPathPlacements(Layer);
  for I := 0 to High(Placements) do
    for J := 0 to High(Placements[I].Corners) do
    begin
      if not Result then
      begin
        Bounds := TRectF.Create(Placements[I].Corners[J],
          Placements[I].Corners[J]);
        Result := True;
      end
      else
      begin
        Bounds.Left := Min(Bounds.Left, Placements[I].Corners[J].X);
        Bounds.Top := Min(Bounds.Top, Placements[I].Corners[J].Y);
        Bounds.Right := Max(Bounds.Right, Placements[I].Corners[J].X);
        Bounds.Bottom := Max(Bounds.Bottom, Placements[I].Corners[J].Y);
      end;
    end;
end;

function PointInMapRakuTextPath(Layer: TMapRakuTextPathLayer;
  const Point: TPointF): Boolean;
var
  I: Integer;
  Polygon: TArray<TPointF>;
  Placements: TArray<TMapRakuTextPathPlacement>;
begin
  Result := False;
  Placements := BuildMapRakuTextPathPlacements(Layer);
  SetLength(Polygon, 4);
  for I := 0 to High(Placements) do
  begin
    Polygon[0] := Placements[I].Corners[0];
    Polygon[1] := Placements[I].Corners[1];
    Polygon[2] := Placements[I].Corners[2];
    Polygon[3] := Placements[I].Corners[3];
    if PointInPolygon(Point, Polygon) then
      Exit(True);
  end;
end;

end.
