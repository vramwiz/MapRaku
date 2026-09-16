// スナップ候補の探索と、吸着理由を示すガイド線の論理座標を生成する。
unit MapRakuSnapGeometry;

interface

uses
  System.Types, MapRakuDocument;

type
  TMapRakuSnapAxis = (slsaX, slsaY, slsaAngle);

  TMapRakuSnapGuide = record
    Axis: TMapRakuSnapAxis; // 一致した座標軸。
    StartPoint: TPointF;         // 一致関係を示す論理座標上の線分始点。
    EndPoint: TPointF;           // 一致関係を示す論理座標上の線分終点。
    TargetBounds: TRectF;        // 他オブジェクトが対象の場合の外接範囲。
    HighlightTarget: Boolean;    // TargetBoundsを強調表示する場合にTrue。
  end;

// 点をキャンバス、他オブジェクト、不可視グリッドへ吸着する。
function SnapMapRakuPoint(Document: TVectArtDocument;
  const PointValue: TPointF; Zoom: Single; ExcludeSelected: Boolean;
  out SnappedPoint: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;

// 選択レイヤー内の移動対象以外の頂点を優先候補へ加えて点を吸着する。
function SnapMapRakuPointWithCandidates(Document: TVectArtDocument;
  const PointValue: TPointF; Zoom: Single; ExcludeSelected: Boolean;
  const CandidatePoints: TArray<TPointF>; out SnappedPoint: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;

// 移動前の外接範囲を基準に、移動量を各辺と中心の候補へ吸着する。
function SnapMapRakuMove(Document: TVectArtDocument;
  const MovingBounds: TRectF; const ProposedDelta: TPointF; Zoom: Single;
  out SnappedDelta: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;

// グループ内部などDocument選択外のレイヤーを除外して移動量を吸着する。
function SnapMapRakuMoveForLayers(Document: TVectArtDocument;
  const MovingBounds: TRectF; const ProposedDelta: TPointF; Zoom: Single;
  const ExcludedLayers: TArray<TVectArtLayer>; out SnappedDelta: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;

// 指定角度が30度系または45度系の主要角度に近い場合、最も近い候補へ吸着する。
function SnapMapRakuAngle(ProposedAngle: Single;
  out SnappedAngle: Single): Boolean;

implementation

uses
  System.Math, MapRakuPathSnap, MapRakuLayerGeometry;

const
  SNAP_DISTANCE_PIXELS = 6.0;
  GRID_TARGET_PIXELS = 48.0;

type
  TMapRakuBestSnap = record
    Found: Boolean;
    Adjustment: Single;
    TargetCoordinate: Single;
    SpanMinimum: Single;
    SpanMaximum: Single;
    TargetBounds: TRectF;
    HighlightTarget: Boolean;
  end;

function NormalizeAngleDelta(Value: Single): Single;
begin
  Result := Value;
  while Result > 180 do
    Result := Result - 360;
  while Result < -180 do
    Result := Result + 360;
end;

function SnapMapRakuAngle(ProposedAngle: Single;
  out SnappedAngle: Single): Boolean;
const
  ANGLE_30_INTERVAL = 30.0;
  ANGLE_45_INTERVAL = 45.0;
  ANGLE_TOLERANCE = 5.0;
var
  Adjustment30: Single;
  Adjustment45: Single;
  Candidate30: Single;
  Candidate45: Single;
begin
  Candidate30 := Round(ProposedAngle / ANGLE_30_INTERVAL) *
    ANGLE_30_INTERVAL;
  Candidate45 := Round(ProposedAngle / ANGLE_45_INTERVAL) *
    ANGLE_45_INTERVAL;
  Adjustment30 := NormalizeAngleDelta(Candidate30 - ProposedAngle);
  Adjustment45 := NormalizeAngleDelta(Candidate45 - ProposedAngle);
  if Abs(Adjustment30) < Abs(Adjustment45) then
    SnappedAngle := ProposedAngle + Adjustment30
  else
    SnappedAngle := ProposedAngle + Adjustment45;
  Result := Abs(NormalizeAngleDelta(SnappedAngle - ProposedAngle)) <=
    ANGLE_TOLERANCE;
  if not Result then
    SnappedAngle := ProposedAngle;
end;

procedure ConsiderSnap(var Best: TMapRakuBestSnap;
  SourceCoordinate, TargetCoordinate, Tolerance, SpanMinimum,
  SpanMaximum: Single; const TargetBounds: TRectF;
  HighlightTarget: Boolean);
var
  Adjustment: Single;
begin
  Adjustment := TargetCoordinate - SourceCoordinate;
  if Abs(Adjustment) > Tolerance then
    Exit;
  if Best.Found and (Abs(Best.Adjustment) <= Abs(Adjustment)) then
    Exit;
  Best.Found := True;
  Best.Adjustment := Adjustment;
  Best.TargetCoordinate := TargetCoordinate;
  Best.SpanMinimum := SpanMinimum;
  Best.SpanMaximum := SpanMaximum;
  Best.TargetBounds := TargetBounds;
  Best.HighlightTarget := HighlightTarget;
end;

function GridSpacing(Zoom: Single): Single;
var
  Magnitude: Single;
  Mantissa: Single;
  Wanted: Single;
begin
  Wanted := GRID_TARGET_PIXELS / Max(Zoom, 0.001);
  Magnitude := Power(10, Floor(Log10(Max(Wanted, 0.0001))));
  Mantissa := Wanted / Magnitude;
  if Mantissa < 1.5 then
    Result := Magnitude
  else if Mantissa < 3.5 then
    Result := 2 * Magnitude
  else if Mantissa < 7.5 then
    Result := 5 * Magnitude
  else
    Result := 10 * Magnitude;
end;

function LayerContainsAnyExcluded(Layer: TVectArtLayer;
  const ExcludedLayers: TArray<TVectArtLayer>): Boolean;
var
  ExcludedLayer: TVectArtLayer;
  GroupLayer: TMapRakuGroupLayer;
  I: Integer;
begin
  Result := False;
  for ExcludedLayer in ExcludedLayers do
    if Layer = ExcludedLayer then
      Exit(True);
  if not (Layer is TMapRakuGroupLayer) then
    Exit;
  GroupLayer := TMapRakuGroupLayer(Layer);
  for I := 0 to GroupLayer.ChildCount - 1 do
    if LayerContainsAnyExcluded(GroupLayer[I], ExcludedLayers) then
      Exit(True);
end;

procedure FindSemanticSnaps(Document: TVectArtDocument;
  const SourceX, SourceY: TArray<Single>; OffsetX, OffsetY, Tolerance: Single;
  ExcludeSelected: Boolean; const ExcludedLayers: TArray<TVectArtLayer>;
  var BestX, BestY: TMapRakuBestSnap);
var
  Bounds: TRectF;
  CanvasBounds: TRectF;
  I: Integer;
  TargetX: array[0..2] of Single;
  TargetY: array[0..2] of Single;

  procedure ConsiderBounds(const TargetBounds: TRectF;
    HighlightTarget: Boolean);
  var
    SourceValue: Single;
    TargetValue: Single;
  begin
    TargetX[0] := TargetBounds.Left;
    TargetX[1] := (TargetBounds.Left + TargetBounds.Right) * 0.5;
    TargetX[2] := TargetBounds.Right;
    TargetY[0] := TargetBounds.Top;
    TargetY[1] := (TargetBounds.Top + TargetBounds.Bottom) * 0.5;
    TargetY[2] := TargetBounds.Bottom;
    for SourceValue in SourceX do
      for TargetValue in TargetX do
        ConsiderSnap(BestX, SourceValue + OffsetX, TargetValue, Tolerance,
          TargetBounds.Top, TargetBounds.Bottom, TargetBounds,
          HighlightTarget);
    for SourceValue in SourceY do
      for TargetValue in TargetY do
        ConsiderSnap(BestY, SourceValue + OffsetY, TargetValue, Tolerance,
          TargetBounds.Left, TargetBounds.Right, TargetBounds,
          HighlightTarget);
  end;

begin
  if (Document = nil) or (Document.CanvasLayer = nil) then
    Exit;
  CanvasBounds := TRectF.Create(-Document.CanvasLayer.Width * 0.5,
    -Document.CanvasLayer.Height * 0.5, Document.CanvasLayer.Width * 0.5,
    Document.CanvasLayer.Height * 0.5);
  ConsiderBounds(CanvasBounds, False);
  for I := 1 to Document.LayerCount - 1 do
  begin
    if not Document[I].Visible or
      (ExcludeSelected and Document.IsLayerSelected(I)) or
      LayerContainsAnyExcluded(Document[I], ExcludedLayers) or
      not TryGetMapRakuLayerBounds(Document[I], Bounds) then
      Continue;
    ConsiderBounds(Bounds, True);
  end;
end;

procedure FindGridSnap(const Sources: TArray<Single>; Offset, Tolerance,
  Spacing: Single; var Best: TMapRakuBestSnap);
var
  Source: Single;
  Target: Single;
begin
  if Best.Found then
    Exit;
  for Source in Sources do
  begin
    Target := Round((Source + Offset) / Spacing) * Spacing;
    ConsiderSnap(Best, Source + Offset, Target, Tolerance, MaxSingle,
      -MaxSingle, TRectF.Empty, False);
  end;
end;

procedure FindPointSnaps(const PointValue: TPointF;
  const CandidatePoints: TArray<TPointF>; Tolerance: Single;
  var BestX, BestY: TMapRakuBestSnap);
var
  CandidatePoint: TPointF;
begin
  for CandidatePoint in CandidatePoints do
  begin
    ConsiderSnap(BestX, PointValue.X, CandidatePoint.X, Tolerance,
      CandidatePoint.Y, CandidatePoint.Y, TRectF.Empty, False);
    ConsiderSnap(BestY, PointValue.Y, CandidatePoint.Y, Tolerance,
      CandidatePoint.X, CandidatePoint.X, TRectF.Empty, False);
  end;
end;

function BuildGuide(Axis: TMapRakuSnapAxis;
  const Best: TMapRakuBestSnap; SourceMinimum,
  SourceMaximum, FallbackHalfLength: Single): TMapRakuSnapGuide;
var
  SpanMaximum: Single;
  SpanMinimum: Single;
begin
  Result.Axis := Axis;
  Result.TargetBounds := Best.TargetBounds;
  Result.HighlightTarget := Best.HighlightTarget;
  SpanMinimum := SourceMinimum;
  SpanMaximum := SourceMaximum;
  if Best.SpanMinimum <= Best.SpanMaximum then
  begin
    SpanMinimum := Min(SpanMinimum, Best.SpanMinimum);
    SpanMaximum := Max(SpanMaximum, Best.SpanMaximum);
  end;
  if SameValue(SpanMinimum, SpanMaximum) then
  begin
    SpanMinimum := SpanMinimum - FallbackHalfLength;
    SpanMaximum := SpanMaximum + FallbackHalfLength;
  end;
  if Axis = slsaX then
  begin
    Result.StartPoint := TPointF.Create(Best.TargetCoordinate,
      SpanMinimum);
    Result.EndPoint := TPointF.Create(Best.TargetCoordinate,
      SpanMaximum);
  end
  else
  begin
    Result.StartPoint := TPointF.Create(SpanMinimum,
      Best.TargetCoordinate);
    Result.EndPoint := TPointF.Create(SpanMaximum,
      Best.TargetCoordinate);
  end;
end;

function SnapMapRakuPointCore(Document: TVectArtDocument;
  const PointValue: TPointF; Zoom: Single; ExcludeSelected: Boolean;
  const CandidatePoints: TArray<TPointF>;
  out SnappedPoint: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;
var
  BestX: TMapRakuBestSnap;
  BestY: TMapRakuBestSnap;
  Spacing: Single;
  Tolerance: Single;
  Tangent: TPointF;
  Path: TVectArtPathLayer;
  Guide: TMapRakuSnapGuide;
begin
  BestX := Default(TMapRakuBestSnap);
  BestY := Default(TMapRakuBestSnap);
  SnappedPoint := PointValue;
  Guides := nil;
  if (Document = nil) or (Zoom <= 0) then
    Exit(False);
  Tolerance := SNAP_DISTANCE_PIXELS / Zoom;
  if NearestMapPath(Document, PointValue, Tolerance, ExcludeSelected, '', SnappedPoint, Tangent, Path) then
  begin
    Guide := Default(TMapRakuSnapGuide);
    Guide.Axis := slsaAngle; Guide.StartPoint := PointValue; Guide.EndPoint := SnappedPoint;
    Guides := [Guide];
    Exit(True);
  end;
  FindPointSnaps(PointValue, CandidatePoints, Tolerance, BestX, BestY);
  FindSemanticSnaps(Document, [PointValue.X], [PointValue.Y], 0, 0,
    Tolerance, ExcludeSelected, nil, BestX, BestY);
  Spacing := GridSpacing(Zoom);
  FindGridSnap([PointValue.X], 0, Tolerance, Spacing, BestX);
  FindGridSnap([PointValue.Y], 0, Tolerance, Spacing, BestY);
  if BestX.Found then
    SnappedPoint.X := SnappedPoint.X + BestX.Adjustment;
  if BestY.Found then
    SnappedPoint.Y := SnappedPoint.Y + BestY.Adjustment;
  if BestX.Found then
    Guides := Guides + [BuildGuide(slsaX, BestX, SnappedPoint.Y,
      SnappedPoint.Y, 8 / Zoom)];
  if BestY.Found then
    Guides := Guides + [BuildGuide(slsaY, BestY, SnappedPoint.X,
      SnappedPoint.X, 8 / Zoom)];
  Result := Length(Guides) > 0;
end;

function SnapMapRakuPoint(Document: TVectArtDocument;
  const PointValue: TPointF; Zoom: Single; ExcludeSelected: Boolean;
  out SnappedPoint: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;
begin
  Result := SnapMapRakuPointCore(Document, PointValue, Zoom,
    ExcludeSelected, nil, SnappedPoint, Guides);
end;

function SnapMapRakuPointWithCandidates(Document: TVectArtDocument;
  const PointValue: TPointF; Zoom: Single; ExcludeSelected: Boolean;
  const CandidatePoints: TArray<TPointF>; out SnappedPoint: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;
begin
  Result := SnapMapRakuPointCore(Document, PointValue, Zoom,
    ExcludeSelected, CandidatePoints, SnappedPoint, Guides);
end;

function SnapMapRakuMoveCore(Document: TVectArtDocument;
  const MovingBounds: TRectF; const ProposedDelta: TPointF; Zoom: Single;
  const ExcludedLayers: TArray<TVectArtLayer>;
  out SnappedDelta: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;
var
  BestX: TMapRakuBestSnap;
  BestY: TMapRakuBestSnap;
  MovedBounds: TRectF;
  SourceX: TArray<Single>;
  SourceY: TArray<Single>;
  Spacing: Single;
  Tolerance: Single;
begin
  BestX := Default(TMapRakuBestSnap);
  BestY := Default(TMapRakuBestSnap);
  SnappedDelta := ProposedDelta;
  Guides := nil;
  if (Document = nil) or (Zoom <= 0) or MovingBounds.IsEmpty then
    Exit(False);
  SourceX := [MovingBounds.Left,
    (MovingBounds.Left + MovingBounds.Right) * 0.5, MovingBounds.Right];
  SourceY := [MovingBounds.Top,
    (MovingBounds.Top + MovingBounds.Bottom) * 0.5, MovingBounds.Bottom];
  Tolerance := SNAP_DISTANCE_PIXELS / Zoom;
  FindSemanticSnaps(Document, SourceX, SourceY, ProposedDelta.X,
    ProposedDelta.Y, Tolerance, True, ExcludedLayers, BestX, BestY);
  Spacing := GridSpacing(Zoom);
  FindGridSnap(SourceX, ProposedDelta.X, Tolerance, Spacing, BestX);
  FindGridSnap(SourceY, ProposedDelta.Y, Tolerance, Spacing, BestY);
  if BestX.Found then
    SnappedDelta.X := SnappedDelta.X + BestX.Adjustment;
  if BestY.Found then
    SnappedDelta.Y := SnappedDelta.Y + BestY.Adjustment;
  MovedBounds := MovingBounds;
  MovedBounds.Offset(SnappedDelta.X, SnappedDelta.Y);
  if BestX.Found then
    Guides := Guides + [BuildGuide(slsaX, BestX, MovedBounds.Top,
      MovedBounds.Bottom, 8 / Zoom)];
  if BestY.Found then
    Guides := Guides + [BuildGuide(slsaY, BestY, MovedBounds.Left,
      MovedBounds.Right, 8 / Zoom)];
  Result := Length(Guides) > 0;
end;

function SnapMapRakuMove(Document: TVectArtDocument;
  const MovingBounds: TRectF; const ProposedDelta: TPointF; Zoom: Single;
  out SnappedDelta: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;
begin
  Result := SnapMapRakuMoveCore(Document, MovingBounds, ProposedDelta,
    Zoom, nil, SnappedDelta, Guides);
end;

function SnapMapRakuMoveForLayers(Document: TVectArtDocument;
  const MovingBounds: TRectF; const ProposedDelta: TPointF; Zoom: Single;
  const ExcludedLayers: TArray<TVectArtLayer>; out SnappedDelta: TPointF;
  out Guides: TArray<TMapRakuSnapGuide>): Boolean;
begin
  Result := SnapMapRakuMoveCore(Document, MovingBounds, ProposedDelta,
    Zoom, ExcludedLayers, SnappedDelta, Guides);
end;

end.
