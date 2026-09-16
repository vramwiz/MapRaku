// 図形作成ツールの入力状態、プレビュー、新規レイヤー確定を管理する。
unit MapRakuShapeCreation;

interface

uses
  System.Classes, System.Types, Vcl.Controls, MapRakuDocument,
  MapRakuEditorState, MapRakuEditHistory,
  MapRakuSnapGeometry;

type
  TVectArtShapeCreation = class
  private
    FActive: Boolean;
    FCanvasBounds: TRect;
    FCreationTool: TVectArtEditorTool;
    FCreatedTextPathBeforeSelection: TArray<Integer>;
    FCreatedTextPathIndex: Integer;
    FCurrentPoint: TPoint;
    FDeferTextPathHistory: Boolean;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FEditHistory: TVectArtEditHistory;
    FModifiers: TShiftState;
    FPathPoints: TArray<TPoint>;
    FPathPressures: TArray<Single>;
    FPressureCaptured: Boolean;
    FInputPressure: Single;
    FInputPressureAvailable: Boolean;
    FVertexKinds: TArray<TMapRakuVertexKind>; // 確定済みPath／Shape頂点の種別。
    FNextVertexKind: TMapRakuVertexKind;      // 次のクリックへ適用する種別。
    FStartPoint: TPoint;
    FSnapGuides: TArray<TMapRakuSnapGuide>;
    FZoom: Single;
    function AdjustInputPoint(const PointValue: TPoint;
      Shift: TShiftState; ConstrainToPrevious: Boolean): TPoint;
    // 始点の近傍では両軸を同じ頂点へ吸着し、閉じ位置を示すガイドを更新する。
    function SnapToPathStart(var PointValue: TPoint; Shift: TShiftState): Boolean;
    function ClampToCanvas(const Point: TPoint): TPoint;
    procedure CreateArc;
    procedure CreateArcShape;
    procedure CreateEllipse;
    procedure CreateEllipseLine;
    procedure CreateLine;
    procedure CreatePath(Closed: Boolean; const BaseName: string = 'Path');
    procedure CreateTextPath;
    procedure CreateRectangle;
    procedure CreateRectangleLine;
    procedure CreateRoundedRectangle;
    procedure CreateRoundedRectangleLine;
    procedure CreateShape;
    function BuildFreehandPathVertices: TArray<TMapRakuVertex>;
    function BuildFreehandWidthPoints:
      TArray<TMapRakuStrokeWidthPoint>;
    function BuildPathVertices: TArray<TMapRakuVertex>;
    function BuildOpenPathPreview(out Points: TArray<TPoint>): Boolean;
    function BuildShapePreview(out Points: TArray<TPoint>): Boolean;
  public
    // 新規図形入力に必要なDocument、履歴、ツール、表示座標系を設定する。
    procedure Configure(ADocument: TVectArtDocument;
      AEditHistory: TVectArtEditHistory; AEditorState: TVectArtEditorState;
      const ACanvasBounds: TRect; AZoom: Single);
    // 現在の作成ツールに応じて入力開始または頂点追加を行う。
    function MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer): Boolean;
    // 作成中プレビューの終点を更新する。
    function MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
    // ドラッグ作成中の図形を確定し、DocumentとUndo履歴へ反映する。
    function MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer): Boolean;
    // 確定前のPath／Shape頂点列を破棄する。
    procedure CancelPath;
    // 頂点が足りる場合にPathまたはShapeを確定し、成功時にTrueを返す。
    function FinishPath(Closed: Boolean): Boolean;
    // 作成中のPath／Shapeプレビュー頂点を返す。
    function PreviewPath(out Points: TArray<TPoint>): Boolean;
    // Returns pressure scales aligned with the current freehand preview points.
    function PreviewWidthScales: TArray<Single>;
    // ドラッグ作成中の矩形プレビュー範囲を返す。
    function PreviewRect: TRect;
    // 配置中の既定上半円を画面座標の折れ線として返す。
    function PreviewArc(out Points: TArray<TPoint>): Boolean;
    // ドラッグ作成中の直線プレビュー端点を返す。
    function PreviewLine(out StartPoint, EndPoint: TPoint): Boolean;
    // 頂点種別ショートカットを含むキーは、呼び出し側の通常入力へ渡す。
    function KeyDown(Key: Word; Shift: TShiftState): Boolean;
    // Canvasが初回文字入力を完了するまで履歴確定を保留した文字パスを受け取る。
    function TakeCreatedTextPath(out LayerIndex: Integer;
      out BeforeSelection: TArray<Integer>): Boolean;
    // Supplies the latest pen pressure; unavailable input produces uniform width.
    procedure SetInputPressure(Value: Single; Available: Boolean);
    property Active: Boolean read FActive;
    property DeferTextPathHistory: Boolean read FDeferTextPathHistory
      write FDeferTextPathHistory;
    // 作成中に一致した対象と座標をキャンバスへ表示する論理ガイド線。
    property SnapGuides: TArray<TMapRakuSnapGuide> read FSnapGuides;
  end;

implementation

uses
  System.Math, Vcl.Graphics,
  MapRakuMapCommands, MapRakuGeometry, MapRakuLayerStructureCommands,
  MapRakuLayerNaming, MapRakuPathOperations,
  MapRakuShapeOperations, MapRakuTextCommands;

const
  MIN_DRAG_SIZE               = 3;
  FREEHAND_SAMPLE_DISTANCE    = 2;   // 入力点を追加する最小画面距離（px）。
  FREEHAND_SIMPLIFY_TOLERANCE = 1.5; // 簡略化で許容する画面距離（px）。
  FREEHAND_WIDTH_SAMPLE_DISTANCE = 8; // 幅情報を保存する最小画面距離（px）。
  FREEHAND_WIDTH_CHANGE = 0.025;      // 短い区間でも保持する筆圧変化量。
  PATH_CLOSE_DISTANCE         = 8;   // 始点への吸着と図形確定に使う画面距離（px）。
  SHAPE_PREVIEW_CURVE_STEPS   = 16;

procedure ConfigureShapeContourSegments(var Contour: TMapRakuContour);
var
  I: Integer;
  NextIndex: Integer;
begin
  RecalculateMapRakuSmoothContour(Contour);
  for I := 0 to High(Contour.Vertices) do
  begin
    NextIndex := (I + 1) mod Length(Contour.Vertices);
    if (Contour.Vertices[I].Kind = slvkBezier) or
      (Contour.Vertices[NextIndex].Kind = slvkBezier) then
      Contour.Vertices[I].OutgoingSegment := slskCubicBezier
    else
      Contour.Vertices[I].OutgoingSegment := slskLine;
  end;
end;

function ShapeCubicPoint(const StartPoint, Control1, Control2,
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

procedure TVectArtShapeCreation.CancelPath;
begin
  FActive := False;
  FCreationTool := vetSelect;
  FSnapGuides := nil;
  SetLength(FPathPoints, 0);
  SetLength(FPathPressures, 0);
  FPressureCaptured := False;
  SetLength(FVertexKinds, 0);
  FNextVertexKind := slvkSharp;
end;

function PointAtScreenAngle(const Anchor, PointValue: TPoint;
  AngleDegrees: Single): TPoint;
var
  Distance: Single;
  Radians: Single;
begin
  Distance := Hypot(PointValue.X - Anchor.X, PointValue.Y - Anchor.Y);
  Radians := DegToRad(AngleDegrees);
  Result := Point(Round(Anchor.X + Cos(Radians) * Distance),
    Round(Anchor.Y + Sin(Radians) * Distance));
end;

function TVectArtShapeCreation.SnapToPathStart(var PointValue: TPoint; Shift: TShiftState): Boolean;
var
  Guide: TMapRakuSnapGuide;
  Start: TPointF;
  Radius: Single;
begin
  Result := False;
  if (Length(FPathPoints) < 2) or (ssAlt in Shift) or (ssShift in Shift) then
    Exit;
  if Hypot(PointValue.X - FPathPoints[0].X, PointValue.Y - FPathPoints[0].Y) > PATH_CLOSE_DISTANCE then
    Exit;
  PointValue := FPathPoints[0];
  Start := TPointF.Create(
    ScreenToLogicalX(PointValue.X, FCanvasBounds, FZoom, FDocument.CanvasLayer.Width),
    ScreenToLogicalY(PointValue.Y, FCanvasBounds, FZoom, FDocument.CanvasLayer.Height));
  Radius := PATH_CLOSE_DISTANCE / FZoom;
  Guide := Default(TMapRakuSnapGuide);
  Guide.Axis := slsaX;
  Guide.StartPoint := TPointF.Create(Start.X, Start.Y - Radius);
  Guide.EndPoint := TPointF.Create(Start.X, Start.Y + Radius);
  FSnapGuides := [Guide];
  Guide.Axis := slsaY;
  Guide.StartPoint := TPointF.Create(Start.X - Radius, Start.Y);
  Guide.EndPoint := TPointF.Create(Start.X + Radius, Start.Y);
  FSnapGuides := FSnapGuides + [Guide];
  Result := True;
end;

function TVectArtShapeCreation.AdjustInputPoint(const PointValue: TPoint;
  Shift: TShiftState; ConstrainToPrevious: Boolean): TPoint;
var
  Anchor: TPoint;
  AngleGuide: TMapRakuSnapGuide;
  AngleSnapped: Boolean;
  CandidatePoints: TArray<TPointF>;
  ConstrainHorizontal: Boolean;
  Guide: TMapRakuSnapGuide;
  HasXGuide: Boolean;
  HasYGuide: Boolean;
  I: Integer;
  LogicalPoint: TPointF;
  MatchingGuideFound: Boolean;
  NearExistingPoint: Boolean;
  PointBeforeAngleProjection: TPoint;
  ProposedAngle: Single;
  SnappedAngle: Single;
  SnappedPoint: TPointF;
begin
  Result := ClampToCanvas(PointValue);
  // 始点への点吸着を、角度・グリッド・他オブジェクトの軸吸着より優先する。
  if ConstrainToPrevious and SnapToPathStart(Result, Shift) then
    Exit;
  AngleSnapped := False;
  ConstrainHorizontal := False;
  if ConstrainToPrevious then
  begin
    if Length(FPathPoints) > 0 then
      Anchor := FPathPoints[High(FPathPoints)]
    else
      Anchor := FStartPoint;
    if ssShift in Shift then
    begin
      ConstrainHorizontal := Abs(Result.X - Anchor.X) >=
        Abs(Result.Y - Anchor.Y);
      if ConstrainHorizontal then
        Result.Y := Anchor.Y
      else
        Result.X := Anchor.X;
    end
    else if not (ssAlt in Shift) and
      ((Result.X <> Anchor.X) or (Result.Y <> Anchor.Y)) then
    begin
      NearExistingPoint := False;
      for I := 0 to High(FPathPoints) do
        if Hypot(Result.X - FPathPoints[I].X,
          Result.Y - FPathPoints[I].Y) <= PATH_CLOSE_DISTANCE then
        begin
          NearExistingPoint := True;
          Break;
        end;
      if not NearExistingPoint then
      begin
        ProposedAngle := RadToDeg(ArcTan2(Result.Y - Anchor.Y,
          Result.X - Anchor.X));
        AngleSnapped := SnapMapRakuAngle(ProposedAngle, SnappedAngle);
        if AngleSnapped then
          Result := PointAtScreenAngle(Anchor, Result, SnappedAngle);
      end;
    end;
  end;
  FSnapGuides := nil;
  if not (ssAlt in Shift) then
  begin
    LogicalPoint := TPointF.Create(
      ScreenToLogicalX(Result.X, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Width),
      ScreenToLogicalY(Result.Y, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Height));
    CandidatePoints := nil;
    for I := 0 to High(FPathPoints) do
      CandidatePoints := CandidatePoints + [TPointF.Create(
        ScreenToLogicalX(FPathPoints[I].X, FCanvasBounds, FZoom,
          FDocument.CanvasLayer.Width),
        ScreenToLogicalY(FPathPoints[I].Y, FCanvasBounds, FZoom,
          FDocument.CanvasLayer.Height))];
    if SnapMapRakuPointWithCandidates(FDocument, LogicalPoint,
      FZoom, False, CandidatePoints, SnappedPoint, FSnapGuides) then
    begin
      Result := Point(
        LogicalToScreenX(SnappedPoint.X, FCanvasBounds, FZoom,
          FDocument.CanvasLayer.Width),
        LogicalToScreenY(SnappedPoint.Y, FCanvasBounds, FZoom,
          FDocument.CanvasLayer.Height));
      HasXGuide := False;
      HasYGuide := False;
      for Guide in FSnapGuides do
      begin
        HasXGuide := HasXGuide or (Guide.Axis = slsaX);
        HasYGuide := HasYGuide or (Guide.Axis = slsaY);
      end;
      if HasXGuide and HasYGuide then
        AngleSnapped := False;
      if ConstrainToPrevious and (ssShift in Shift) then
      begin
        if ConstrainHorizontal then
          Result.Y := Anchor.Y
        else
          Result.X := Anchor.X;
        MatchingGuideFound := False;
        for I := 0 to High(FSnapGuides) do
        begin
          Guide := FSnapGuides[I];
          if (ConstrainHorizontal and (Guide.Axis = slsaX)) or
            ((not ConstrainHorizontal) and (Guide.Axis = slsaY)) then
          begin
            FSnapGuides := [Guide];
            MatchingGuideFound := True;
            Break;
          end;
        end;
        if not MatchingGuideFound then
          FSnapGuides := nil;
      end;
    end;
  end;
  Result := ClampToCanvas(Result);
  if AngleSnapped then
  begin
    PointBeforeAngleProjection := Result;
    Result := ClampToCanvas(PointAtScreenAngle(Anchor, Result,
      SnappedAngle));
    AngleGuide.Axis := slsaAngle;
    AngleGuide.StartPoint := TPointF.Create(
      ScreenToLogicalX(Anchor.X, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Width),
      ScreenToLogicalY(Anchor.Y, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Height));
    AngleGuide.EndPoint := TPointF.Create(
      ScreenToLogicalX(Result.X, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Width),
      ScreenToLogicalY(Result.Y, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Height));
    AngleGuide.TargetBounds := TRectF.Empty;
    AngleGuide.HighlightTarget := False;
    if PointBeforeAngleProjection <> Result then
      FSnapGuides := [AngleGuide]
    else
      FSnapGuides := FSnapGuides + [AngleGuide];
  end;
end;

procedure TVectArtShapeCreation.CreateShape;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TMapRakuShapeData;
  I: Integer;
  Index: Integer;
begin
  if Length(FPathPoints) < 3 then
    Exit;
  SetLength(Data.Contours, 1);
  SetLength(Data.Contours[0].Vertices, Length(FPathPoints));
  for I := 0 to High(FPathPoints) do
  begin
    Data.Contours[0].Vertices[I].Position := TPointF.Create(
      ScreenToLogicalX(FPathPoints[I].X, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Width),
      ScreenToLogicalY(FPathPoints[I].Y, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Height));
    if I <= High(FVertexKinds) then
      Data.Contours[0].Vertices[I].Kind := FVertexKinds[I]
    else
      Data.Contours[0].Vertices[I].Kind := slvkSharp;
  end;
  ConfigureShapeContourSegments(Data.Contours[0]);
  Data.FillColor := FEditorState.CreationColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.FillRule := slfrEvenOdd;
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, 'Shape');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.StrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertShape(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuInsertShapeCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreateLine;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtPathData;
  Index: Integer;
begin
  if Hypot(FCurrentPoint.X - FStartPoint.X,
    FCurrentPoint.Y - FStartPoint.Y) < MIN_DRAG_SIZE then
    Exit;
  SetLength(Data.Vertices, 2);
  Data.Vertices[0].Position := TPointF.Create(
    ScreenToLogicalX(FStartPoint.X, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(FStartPoint.Y, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Data.Vertices[1].Position := TPointF.Create(
    ScreenToLogicalX(FCurrentPoint.X, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(FCurrentPoint.Y, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Data.Vertices[0].OutgoingSegment := slskLine;
  Data.Vertices[0].Kind := slvkSharp;
  Data.Vertices[1].OutgoingSegment := slskLine;
  Data.Vertices[1].Kind := slvkSharp;
  if FEditorState.StrokeWidthMode = slwmVariable then
    Data.WidthPoints := UniformMapRakuStrokeWidthPoints
  else
    Data.WidthPoints := nil;
  Data.Closed := False;
  Data.MapElement := FEditorState.MapElement;
  Data.Locked := False;
  Data.LineCap := FEditorState.LineCap;
  Data.Name := NextMapRakuLayerName(FDocument, 'Line');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.MifStrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.Visible := True;
  if Data.MapElement <> '' then
  begin
    Data.Name := Data.MapElement;
    InsertMapPath(FDocument, FEditHistory, Data);
    FEditorState.CurrentTool := vetSelect;
    Exit;
  end;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertPath(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtInsertPathCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreatePath(Closed: Boolean;
  const BaseName: string);
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtPathData;
  Index: Integer;
begin
  if Length(FPathPoints) < 2 then
    Exit;
  if Closed and (Length(FPathPoints) < 3) then
    Closed := False;
  if FCreationTool = vetFreehand then
  begin
    Data.Vertices := BuildFreehandPathVertices;
    if FEditorState.StrokeWidthMode = slwmVariable then
    begin
      Data.WidthPoints := BuildFreehandWidthPoints;
      if Length(Data.WidthPoints) = 0 then
        Data.WidthPoints := UniformMapRakuStrokeWidthPoints;
    end
    else
      Data.WidthPoints := nil;
  end
  else
  begin
    Data.Vertices := BuildPathVertices;
    if not Closed and (FEditorState.StrokeWidthMode = slwmVariable) then
      Data.WidthPoints := UniformMapRakuStrokeWidthPoints
    else
      Data.WidthPoints := nil;
  end;
  Data.MapElement := FEditorState.MapElement;
  Data.Closed := Closed;
  Data.LineCap := FEditorState.LineCap;
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, BaseName);
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.MifStrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.Visible := True;
  if Data.MapElement <> '' then
  begin
    Data.Name := Data.MapElement;
    InsertMapPath(FDocument, FEditHistory, Data);
    Exit;
  end;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertPath(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtInsertPathCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

function TVectArtShapeCreation.BuildPathVertices:
  TArray<TMapRakuVertex>;
var
  I: Integer;
begin
  SetLength(Result, Length(FPathPoints));
  for I := 0 to High(FPathPoints) do
  begin
    Result[I].Position := TPointF.Create(
      ScreenToLogicalX(FPathPoints[I].X, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Width),
      ScreenToLogicalY(FPathPoints[I].Y, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Height));
    if I <= High(FVertexKinds) then
      Result[I].Kind := FVertexKinds[I]
    else
      Result[I].Kind := slvkSharp;
  end;
  ConfigureMapRakuOpenPath(Result);
end;

procedure TVectArtShapeCreation.CreateTextPath;
const
  DEFAULT_FONT_FAMILY = 'Yu Gothic UI';
  DEFAULT_FONT_SIZE = 32.0;
  DEFAULT_TEXT = 'Text';
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Bounds: TRectF;
  Index: Integer;
  Layer: TMapRakuTextPathLayer;
  Vertices: TArray<TMapRakuVertex>;
begin
  if Length(FPathPoints) < 2 then
    Exit;
  Vertices := BuildPathVertices;
  Bounds := MapRakuPathVerticesBounds(Vertices);
  Bounds.Top := Bounds.Top - DEFAULT_FONT_SIZE;
  if Bounds.Width < 1.0 then
    Bounds.Right := Bounds.Left + 1.0;
  Layer := TMapRakuTextPathLayer.Create(
    NextMapRakuLayerName(FDocument, 'Text Path'), Bounds,
    DEFAULT_TEXT, DEFAULT_FONT_FAMILY, DEFAULT_FONT_SIZE,
    Max(Bounds.Width, 1.0), FEditorState.CreationColor, Vertices);
  Layer.Opacity := FEditorState.RectangleOpacity;
  Layer.PaintStyle := FEditorState.CreationPaintStyle;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertLayer(FDocument.LayerCount, Layer);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FDeferTextPathHistory then
  begin
    FCreatedTextPathIndex := Index;
    FCreatedTextPathBeforeSelection := Copy(BeforeSelection);
  end
  else if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuInsertTextPathCommand.Create(
      FDocument, Index, Layer, BeforeSelection, AfterSelection));
end;

function TVectArtShapeCreation.TakeCreatedTextPath(out LayerIndex: Integer;
  out BeforeSelection: TArray<Integer>): Boolean;
begin
  Result := FCreatedTextPathIndex > 0;
  if not Result then
  begin
    LayerIndex := -1;
    BeforeSelection := nil;
    Exit;
  end;
  LayerIndex := FCreatedTextPathIndex;
  BeforeSelection := Copy(FCreatedTextPathBeforeSelection);
  FCreatedTextPathIndex := -1;
  SetLength(FCreatedTextPathBeforeSelection, 0);
end;

function TVectArtShapeCreation.ClampToCanvas(const Point: TPoint): TPoint;
begin
  Result.X := EnsureRange(Point.X, FCanvasBounds.Left,
    FCanvasBounds.Right);
  Result.Y := EnsureRange(Point.Y, FCanvasBounds.Top,
    FCanvasBounds.Bottom);
end;

procedure TVectArtShapeCreation.Configure(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory; AEditorState: TVectArtEditorState;
  const ACanvasBounds: TRect; AZoom: Single);
begin
  if (Length(FPathPoints) > 0) and ((AEditorState = nil) or
    (AEditorState.CurrentTool <> FCreationTool)) then
    CancelPath;
  FDocument := ADocument;
  FEditHistory := AEditHistory;
  FEditorState := AEditorState;
  if FEditorState <> nil then
    FNextVertexKind := FEditorState.NextVertexKind;
  FCanvasBounds := ACanvasBounds;
  FZoom := AZoom;
end;

procedure TVectArtShapeCreation.CreateRectangle;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtRectangleData;
  Index: Integer;
  LogicalBottom: Single;
  LogicalLeft: Single;
  LogicalRight: Single;
  LogicalTop: Single;
  ScreenBounds: TRect;
begin
  ScreenBounds := PreviewRect;
  if (ScreenBounds.Width < MIN_DRAG_SIZE) or
    (ScreenBounds.Height < MIN_DRAG_SIZE) then
    Exit;
  LogicalLeft := ScreenToLogicalX(ScreenBounds.Left, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
  LogicalTop := ScreenToLogicalY(ScreenBounds.Top, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
  LogicalRight := ScreenToLogicalX(ScreenBounds.Right, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
  LogicalBottom := ScreenToLogicalY(ScreenBounds.Bottom, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
  Data.Bounds := TRectF.Create(LogicalLeft, LogicalTop, LogicalRight,
    LogicalBottom);
  Data.FillColor := FEditorState.RectangleFillColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, 'Rectangle');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.RotationDegrees := 0.0;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertRectangle(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtInsertRectangleCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreateRectangleLine;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TMapRakuRectangleLineData;
  Index: Integer;
  ScreenBounds: TRect;
begin
  ScreenBounds := PreviewRect;
  if (ScreenBounds.Width < MIN_DRAG_SIZE) or
    (ScreenBounds.Height < MIN_DRAG_SIZE) then
    Exit;
  Data.Bounds := TRectF.Create(
    ScreenToLogicalX(ScreenBounds.Left, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Top, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height),
    ScreenToLogicalX(ScreenBounds.Right, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Bottom, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, 'Rectangle Line');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.RotationDegrees := 0.0;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.StrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertRectangleLine(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuInsertRectangleLineCommand.Create(
      FDocument, Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreateArc;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TMapRakuArcData;
  Index: Integer;
  ScreenBounds: TRect;
begin
  ScreenBounds := PreviewRect;
  if (ScreenBounds.Width < MIN_DRAG_SIZE) or
    (ScreenBounds.Height < MIN_DRAG_SIZE) then
    Exit;
  Data.Bounds := TRectF.Create(
    ScreenToLogicalX(ScreenBounds.Left, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Top, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height),
    ScreenToLogicalX(ScreenBounds.Right, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Bottom, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Data.LineCap := FEditorState.LineCap;
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, 'Arc');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.RotationDegrees := 0.0;
  Data.StartAngleDegrees := 180.0;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.StrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.SweepAngleDegrees := 180.0;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertArc(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuInsertArcCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreateArcShape;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TMapRakuEllipseArcShapeData;
  Index: Integer;
  ScreenBounds: TRect;
begin
  ScreenBounds := PreviewRect;
  if (ScreenBounds.Width < MIN_DRAG_SIZE) or
    (ScreenBounds.Height < MIN_DRAG_SIZE) then
    Exit;
  Data.Bounds := TRectF.Create(
    ScreenToLogicalX(ScreenBounds.Left, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Top, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height),
    ScreenToLogicalX(ScreenBounds.Right, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Bottom, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Data.FillColor := FEditorState.RectangleFillColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, 'Arc Shape');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.RotationDegrees := 0.0;
  Data.StartAngleDegrees := 180.0;
  Data.SweepAngleDegrees := 180.0;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertEllipseArcShape(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuInsertEllipseArcShapeCommand.Create(
      FDocument, Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreateEllipse;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TMapRakuEllipseData;
  Index: Integer;
  LogicalBottom: Single;
  LogicalLeft: Single;
  LogicalRight: Single;
  LogicalTop: Single;
  ScreenBounds: TRect;
begin
  ScreenBounds := PreviewRect;
  if (ScreenBounds.Width < MIN_DRAG_SIZE) or
    (ScreenBounds.Height < MIN_DRAG_SIZE) then
    Exit;
  LogicalLeft := ScreenToLogicalX(ScreenBounds.Left, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
  LogicalTop := ScreenToLogicalY(ScreenBounds.Top, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
  LogicalRight := ScreenToLogicalX(ScreenBounds.Right, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
  LogicalBottom := ScreenToLogicalY(ScreenBounds.Bottom, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
  Data.Bounds := TRectF.Create(LogicalLeft, LogicalTop, LogicalRight,
    LogicalBottom);
  Data.FillColor := FEditorState.RectangleFillColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, 'Ellipse');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.RotationDegrees := 0.0;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertEllipse(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuInsertEllipseCommand.Create(
      FDocument, Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreateEllipseLine;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TMapRakuEllipseLineData;
  Index: Integer;
  ScreenBounds: TRect;
begin
  ScreenBounds := PreviewRect;
  if (ScreenBounds.Width < MIN_DRAG_SIZE) or
    (ScreenBounds.Height < MIN_DRAG_SIZE) then
    Exit;
  Data.Bounds := TRectF.Create(
    ScreenToLogicalX(ScreenBounds.Left, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Top, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height),
    ScreenToLogicalX(ScreenBounds.Right, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Bottom, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, 'Ellipse Line');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.RotationDegrees := 0.0;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.StrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertEllipseLine(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuInsertEllipseLineCommand.Create(
      FDocument, Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreateRoundedRectangle;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TMapRakuRoundedRectangleData;
  Index: Integer;
  LogicalBottom: Single;
  LogicalLeft: Single;
  LogicalRight: Single;
  LogicalTop: Single;
  Radius: Single;
  ScreenBounds: TRect;
begin
  ScreenBounds := PreviewRect;
  if (ScreenBounds.Width < MIN_DRAG_SIZE) or
    (ScreenBounds.Height < MIN_DRAG_SIZE) then
    Exit;
  LogicalLeft := ScreenToLogicalX(ScreenBounds.Left, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
  LogicalTop := ScreenToLogicalY(ScreenBounds.Top, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
  LogicalRight := ScreenToLogicalX(ScreenBounds.Right, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
  LogicalBottom := ScreenToLogicalY(ScreenBounds.Bottom, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
  Data.Bounds := TRectF.Create(LogicalLeft, LogicalTop, LogicalRight,
    LogicalBottom);
  Radius := Min(Data.Bounds.Width, Data.Bounds.Height) * 0.2;
  Data.CornerRadii := UniformMapRakuCornerRadii(Radius);
  Data.FillColor := FEditorState.RectangleFillColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, 'Rounded Rectangle');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.RotationDegrees := 0.0;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertRoundedRectangle(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuInsertRoundedRectangleCommand.Create(
      FDocument, Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreateRoundedRectangleLine;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TMapRakuRoundedRectangleLineData;
  Index: Integer;
  Radius: Single;
  ScreenBounds: TRect;
begin
  ScreenBounds := PreviewRect;
  if (ScreenBounds.Width < MIN_DRAG_SIZE) or
    (ScreenBounds.Height < MIN_DRAG_SIZE) then
    Exit;
  Data.Bounds := TRectF.Create(
    ScreenToLogicalX(ScreenBounds.Left, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Top, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height),
    ScreenToLogicalX(ScreenBounds.Right, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ScreenBounds.Bottom, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Radius := Min(Data.Bounds.Width, Data.Bounds.Height) * 0.2;
  Data.CornerRadii := UniformMapRakuCornerRadii(Radius);
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument,
    'Rounded Rectangle Line');
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.RotationDegrees := 0.0;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.PaintStyle := FEditorState.CreationPaintStyle;
  Data.StrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertRoundedRectangleLine(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(
      TMapRakuInsertRoundedRectangleLineCommand.Create(FDocument,
        Index, Data, BeforeSelection, AfterSelection));
end;

function TVectArtShapeCreation.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer): Boolean;
var
  PointValue: TPoint;
begin
  Result := (Button = mbLeft) and (FDocument <> nil) and
    (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetRectangleLine, vetRectangle,
      vetRoundedRectangleLine,
      vetRoundedRectangle, vetEllipseLine,
      vetEllipse, vetArc, vetArcShape, vetLine, vetFreehand, vetPath, vetShape,
      vetTextPath]) and
    (FZoom > 0) and
    PtInRect(FCanvasBounds, Point(X, Y));
  if not Result then
    Exit;
  if FEditorState.CurrentTool = vetFreehand then
  begin
    PointValue := ClampToCanvas(Point(X, Y));
    FActive := True;
    FCreationTool := vetFreehand;
    FPathPoints := [PointValue];
    FPathPressures := [EnsureRange(FInputPressure, 0.0, 1.0)];
    FPressureCaptured := FInputPressureAvailable;
    FVertexKinds := [slvkSharp];
    FCurrentPoint := PointValue;
    FDocument.SetSelectedLayers([]);
    Exit;
  end;
  PointValue := AdjustInputPoint(Point(X, Y), Shift,
    FActive and (FEditorState.CurrentTool in [vetPath, vetShape,
      vetTextPath]));
  if not FActive then
    FDocument.SetSelectedLayers([]);
  if FEditorState.CurrentTool in [vetPath, vetShape, vetTextPath] then
  begin
    if (ssDouble in Shift) and
      (((FEditorState.CurrentTool = vetShape) and
        (Length(FPathPoints) >= 3)) or
       ((FEditorState.CurrentTool in [vetPath, vetTextPath]) and
        (Length(FPathPoints) >= 2))) then
    begin
      FinishPath(FEditorState.CurrentTool = vetShape);
      Exit;
    end;
    if not FActive then
    begin
      FActive := True;
      FCreationTool := FEditorState.CurrentTool;
      FPathPoints := [PointValue];
      FVertexKinds := [FNextVertexKind];
    end
    else if (FCreationTool = vetShape) and (Length(FPathPoints) >= 3) and
      (Hypot(PointValue.X - FPathPoints[0].X,
        PointValue.Y - FPathPoints[0].Y) <= PATH_CLOSE_DISTANCE) then
      FinishPath(True)
    else
    begin
      SetLength(FPathPoints, Length(FPathPoints) + 1);
      FPathPoints[High(FPathPoints)] := PointValue;
      SetLength(FVertexKinds, Length(FPathPoints));
      FVertexKinds[High(FVertexKinds)] := FNextVertexKind;
    end;
    FCurrentPoint := PointValue;
    Exit;
  end;
  FActive := True;
  FStartPoint := PointValue;
  FCurrentPoint := FStartPoint;
  FModifiers := Shift;
end;

function TVectArtShapeCreation.KeyDown(Key: Word;
  Shift: TShiftState): Boolean;
begin
  Result := False;
end;

function TVectArtShapeCreation.MouseMove(Shift: TShiftState;
  X, Y: Integer): Boolean;
begin
  Result := FActive;
  if not FActive then
    Exit;
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetFreehand) then
  begin
    if not (ssLeft in Shift) then
      Exit;
    FCurrentPoint := ClampToCanvas(Point(X, Y));
    if (Length(FPathPoints) = 0) or
      (Hypot(FCurrentPoint.X - FPathPoints[High(FPathPoints)].X,
        FCurrentPoint.Y - FPathPoints[High(FPathPoints)].Y) >=
        FREEHAND_SAMPLE_DISTANCE) then
      FPathPoints := FPathPoints + [FCurrentPoint];
    if Length(FPathPressures) < Length(FPathPoints) then
    begin
      FPathPressures := FPathPressures +
        [EnsureRange(FInputPressure, 0.0, 1.0)];
      FPressureCaptured := FPressureCaptured or FInputPressureAvailable;
    end;
    Exit;
  end;
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape, vetTextPath]) then
  begin
    FCurrentPoint := AdjustInputPoint(Point(X, Y), Shift, True);
    Exit;
  end;
  if not (ssLeft in Shift) then
  begin
    FActive := False;
    FSnapGuides := nil;
    Exit;
  end;
  FCurrentPoint := AdjustInputPoint(Point(X, Y), Shift,
    FEditorState.CurrentTool = vetLine);
  FModifiers := Shift;
end;

function TVectArtShapeCreation.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer): Boolean;
begin
  if FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape, vetTextPath]) then
    Exit(False);
  Result := (Button = mbLeft) and FActive;
  if not Result then
    Exit;
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetFreehand) then
  begin
    FCurrentPoint := ClampToCanvas(Point(X, Y));
    if (Length(FPathPoints) = 0) or
      (Hypot(FCurrentPoint.X - FPathPoints[High(FPathPoints)].X,
        FCurrentPoint.Y - FPathPoints[High(FPathPoints)].Y) >=
        FREEHAND_SAMPLE_DISTANCE) then
      FPathPoints := FPathPoints + [FCurrentPoint];
    if Length(FPathPressures) < Length(FPathPoints) then
    begin
      FPathPressures := FPathPressures +
        [EnsureRange(FInputPressure, 0.0, 1.0)];
      FPressureCaptured := FPressureCaptured or FInputPressureAvailable;
    end;
    CreatePath(False);
    CancelPath;
    Exit(True);
  end;
  FCurrentPoint := AdjustInputPoint(Point(X, Y), Shift,
    FEditorState.CurrentTool = vetLine);
  FModifiers := Shift;
  if FEditorState.CurrentTool = vetLine then
    CreateLine
  else if FEditorState.CurrentTool = vetArc then
    CreateArc
  else if FEditorState.CurrentTool = vetArcShape then
    CreateArcShape
  else if FEditorState.CurrentTool = vetEllipse then
    CreateEllipse
  else if FEditorState.CurrentTool = vetEllipseLine then
    CreateEllipseLine
  else if FEditorState.CurrentTool = vetRectangleLine then
    CreateRectangleLine
  else if FEditorState.CurrentTool = vetRoundedRectangleLine then
    CreateRoundedRectangleLine
  else if FEditorState.CurrentTool = vetRoundedRectangle then
    CreateRoundedRectangle
  else
    CreateRectangle;
  FActive := False;
  FSnapGuides := nil;
end;

function TVectArtShapeCreation.BuildFreehandPathVertices:
  TArray<TMapRakuVertex>;
var
  I: Integer;
  RawPoints: TArray<TPointF>;
  SimplifiedPoints: TArray<TPointF>;
begin
  SetLength(RawPoints, Length(FPathPoints));
  for I := 0 to High(FPathPoints) do
    RawPoints[I] := TPointF.Create(
      ScreenToLogicalX(FPathPoints[I].X, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Width),
      ScreenToLogicalY(FPathPoints[I].Y, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Height));
  SimplifiedPoints := SimplifyMapRakuPolyline(RawPoints,
    FREEHAND_SIMPLIFY_TOLERANCE / Max(FZoom, 0.001));
  SetLength(Result, Length(SimplifiedPoints));
  for I := 0 to High(SimplifiedPoints) do
  begin
    Result[I].Position := SimplifiedPoints[I];
    Result[I].Kind := slvkBezier;
  end;
  ConfigureMapRakuOpenPath(Result);
end;

function TVectArtShapeCreation.BuildFreehandWidthPoints:
  TArray<TMapRakuStrokeWidthPoint>;
var
  Cumulative: TArray<Single>;
  I: Integer;
  LastSavedDistance: Single;
  LastSavedPressure: Single;
  OutputCount: Integer;
  Pressure: Single;
  TotalDistance: Single;
begin
  Result := nil;
  if not FPressureCaptured or (Length(FPathPoints) < 2) or
    (Length(FPathPressures) <> Length(FPathPoints)) then
    Exit;
  SetLength(Cumulative, Length(FPathPoints));
  for I := 1 to High(FPathPoints) do
    Cumulative[I] := Cumulative[I - 1] + Hypot(
      FPathPoints[I].X - FPathPoints[I - 1].X,
      FPathPoints[I].Y - FPathPoints[I - 1].Y);
  TotalDistance := Cumulative[High(Cumulative)];
  if TotalDistance <= 0 then
    Exit;
  SetLength(Result, Length(FPathPoints));
  OutputCount := 1;
  Result[0].Offset := 0;
  Result[0].LeftScale := EnsureRange(FPathPressures[0], 0.0, 1.0);
  Result[0].RightScale := Result[0].LeftScale;
  LastSavedDistance := 0;
  LastSavedPressure := Result[0].LeftScale;
  for I := 1 to High(FPathPoints) - 1 do
  begin
    Pressure := EnsureRange(FPathPressures[I], 0.0, 1.0);
    if (Cumulative[I] - LastSavedDistance >=
      FREEHAND_WIDTH_SAMPLE_DISTANCE) or
      (Abs(Pressure - LastSavedPressure) >= FREEHAND_WIDTH_CHANGE) then
    begin
      Result[OutputCount].Offset := Cumulative[I] / TotalDistance;
      Result[OutputCount].LeftScale := Pressure;
      Result[OutputCount].RightScale := Pressure;
      Inc(OutputCount);
      LastSavedDistance := Cumulative[I];
      LastSavedPressure := Pressure;
    end;
  end;
  Result[OutputCount].Offset := 1;
  Result[OutputCount].LeftScale := EnsureRange(
    FPathPressures[High(FPathPressures)], 0.0, 1.0);
  Result[OutputCount].RightScale := Result[OutputCount].LeftScale;
  Inc(OutputCount);
  SetLength(Result, OutputCount);
end;

function TVectArtShapeCreation.PreviewWidthScales: TArray<Single>;
begin
  if FActive and (FCreationTool = vetFreehand) and FPressureCaptured and
    (FEditorState <> nil) and
    (FEditorState.StrokeWidthMode = slwmVariable) then
    Result := Copy(FPathPressures)
  else
    Result := nil;
end;

procedure TVectArtShapeCreation.SetInputPressure(Value: Single;
  Available: Boolean);
begin
  FInputPressure := EnsureRange(Value, 0.0, 1.0);
  FInputPressureAvailable := Available;
end;

function TVectArtShapeCreation.FinishPath(Closed: Boolean): Boolean;
begin
  Result := FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape, vetTextPath]) and
    (Length(FPathPoints) >= 2);
  if not Result then
    Exit;
  if FEditorState.CurrentTool = vetShape then
  begin
    if Length(FPathPoints) < 3 then
      Exit(False);
    CreateShape;
  end
  else if FEditorState.CurrentTool = vetTextPath then
    CreateTextPath
  else
    CreatePath(Closed);
  CancelPath;
  if FEditorState.MapElement <> '' then FEditorState.CurrentTool := vetSelect;
end;


function TVectArtShapeCreation.PreviewPath(
  out Points: TArray<TPoint>): Boolean;
begin
  if FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetFreehand) then
  begin
    Points := Copy(FPathPoints);
    Exit(Length(Points) > 0);
  end;
  Result := FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape, vetTextPath]) and
    (Length(FPathPoints) > 0);
  if not Result then
  begin
    Points := nil;
    Exit;
  end;
  if FEditorState.CurrentTool = vetShape then
    Exit(BuildShapePreview(Points));
  Result := BuildOpenPathPreview(Points);
end;

function TVectArtShapeCreation.BuildOpenPathPreview(
  out Points: TArray<TPoint>): Boolean;
var
  Control1: TPointF;
  Control2: TPointF;
  EndPoint: TPointF;
  I: Integer;
  OutputIndex: Integer;
  Parameter: Single;
  PreviewPoint: TPointF;
  StartPoint: TPointF;
  Step: Integer;
  Vertices: TArray<TMapRakuVertex>;
begin
  Result := FActive and (Length(FPathPoints) > 0);
  if not Result then
  begin
    Points := nil;
    Exit;
  end;
  SetLength(Vertices, Length(FPathPoints) + 1);
  for I := 0 to High(FPathPoints) do
  begin
    Vertices[I].Position := TPointF.Create(FPathPoints[I].X,
      FPathPoints[I].Y);
    if I <= High(FVertexKinds) then
      Vertices[I].Kind := FVertexKinds[I]
    else
      Vertices[I].Kind := slvkSharp;
  end;
  Vertices[High(Vertices)].Position := TPointF.Create(FCurrentPoint.X,
    FCurrentPoint.Y);
  Vertices[High(Vertices)].Kind := FNextVertexKind;
  ConfigureMapRakuOpenPath(Vertices);
  SetLength(Points, 1 + High(Vertices) * SHAPE_PREVIEW_CURVE_STEPS);
  OutputIndex := 0;
  Points[OutputIndex] := Point(Round(Vertices[0].Position.X),
    Round(Vertices[0].Position.Y));
  for I := 0 to High(Vertices) - 1 do
  begin
    StartPoint := Vertices[I].Position;
    EndPoint := Vertices[I + 1].Position;
    if Vertices[I].OutgoingSegment = slskLine then
    begin
      Inc(OutputIndex);
      Points[OutputIndex] := Point(Round(EndPoint.X), Round(EndPoint.Y));
      Continue;
    end;
    Control1 := TPointF.Create(StartPoint.X +
      Vertices[I].OutgoingControl.X, StartPoint.Y +
      Vertices[I].OutgoingControl.Y);
    Control2 := TPointF.Create(EndPoint.X +
      Vertices[I + 1].IncomingControl.X, EndPoint.Y +
      Vertices[I + 1].IncomingControl.Y);
    for Step := 1 to SHAPE_PREVIEW_CURVE_STEPS do
    begin
      Parameter := Step / SHAPE_PREVIEW_CURVE_STEPS;
      PreviewPoint := ShapeCubicPoint(StartPoint, Control1, Control2,
        EndPoint, Parameter);
      Inc(OutputIndex);
      Points[OutputIndex] := Point(Round(PreviewPoint.X),
        Round(PreviewPoint.Y));
    end;
  end;
  SetLength(Points, OutputIndex + 1);
end;

function TVectArtShapeCreation.BuildShapePreview(
  out Points: TArray<TPoint>): Boolean;
var
  Control1: TPointF;
  Control2: TPointF;
  Contour: TMapRakuContour;
  EndPoint: TPointF;
  I: Integer;
  NextIndex: Integer;
  OutputIndex: Integer;
  Parameter: Single;
  PreviewPoint: TPointF;
  StartPoint: TPointF;
  Step: Integer;
begin
  Result := FActive and (Length(FPathPoints) > 0);
  if not Result then
  begin
    Points := nil;
    Exit;
  end;
  SetLength(Contour.Vertices, Length(FPathPoints) + 1);
  for I := 0 to High(FPathPoints) do
  begin
    Contour.Vertices[I].Position := TPointF.Create(FPathPoints[I].X,
      FPathPoints[I].Y);
    if I <= High(FVertexKinds) then
      Contour.Vertices[I].Kind := FVertexKinds[I]
    else
      Contour.Vertices[I].Kind := slvkSharp;
  end;
  Contour.Vertices[High(Contour.Vertices)].Position :=
    TPointF.Create(FCurrentPoint.X, FCurrentPoint.Y);
  Contour.Vertices[High(Contour.Vertices)].Kind := FNextVertexKind;
  ConfigureShapeContourSegments(Contour);
  SetLength(Points, 1 + High(Contour.Vertices) *
    SHAPE_PREVIEW_CURVE_STEPS);
  OutputIndex := 0;
  Points[OutputIndex] := Point(Round(Contour.Vertices[0].Position.X),
    Round(Contour.Vertices[0].Position.Y));
  for I := 0 to High(Contour.Vertices) - 1 do
  begin
    NextIndex := I + 1;
    StartPoint := Contour.Vertices[I].Position;
    EndPoint := Contour.Vertices[NextIndex].Position;
    if Contour.Vertices[I].OutgoingSegment = slskLine then
    begin
      Inc(OutputIndex);
      Points[OutputIndex] := Point(Round(EndPoint.X), Round(EndPoint.Y));
      Continue;
    end;
    Control1 := TPointF.Create(StartPoint.X +
      Contour.Vertices[I].OutgoingControl.X, StartPoint.Y +
      Contour.Vertices[I].OutgoingControl.Y);
    Control2 := TPointF.Create(EndPoint.X +
      Contour.Vertices[NextIndex].IncomingControl.X, EndPoint.Y +
      Contour.Vertices[NextIndex].IncomingControl.Y);
    for Step := 1 to SHAPE_PREVIEW_CURVE_STEPS do
    begin
      Parameter := Step / SHAPE_PREVIEW_CURVE_STEPS;
      PreviewPoint := ShapeCubicPoint(StartPoint, Control1, Control2,
        EndPoint, Parameter);
      Inc(OutputIndex);
      Points[OutputIndex] := Point(Round(PreviewPoint.X),
        Round(PreviewPoint.Y));
    end;
  end;
  SetLength(Points, OutputIndex + 1);
end;

function TVectArtShapeCreation.PreviewLine(out StartPoint,
  EndPoint: TPoint): Boolean;
begin
  Result := FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetLine);
  if not Result then
    Exit;
  StartPoint := FStartPoint;
  EndPoint := FCurrentPoint;
end;

function TVectArtShapeCreation.PreviewArc(
  out Points: TArray<TPoint>): Boolean;
const
  PREVIEW_SEGMENTS = 24;
var
  Angle: Single;
  Bounds: TRect;
  CenterX: Single;
  CenterY: Single;
  I: Integer;
  RadiusX: Single;
  RadiusY: Single;
begin
  Result := FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetArc);
  if not Result then
  begin
    Points := nil;
    Exit;
  end;
  Bounds := PreviewRect;
  CenterX := (Bounds.Left + Bounds.Right) * 0.5;
  CenterY := (Bounds.Top + Bounds.Bottom) * 0.5;
  RadiusX := Bounds.Width * 0.5;
  RadiusY := Bounds.Height * 0.5;
  SetLength(Points, PREVIEW_SEGMENTS + 1);
  for I := 0 to PREVIEW_SEGMENTS do
  begin
    Angle := DegToRad(180.0 + 180.0 * I / PREVIEW_SEGMENTS);
    Points[I] := Point(Round(CenterX + RadiusX * Cos(Angle)),
      Round(CenterY + RadiusY * Sin(Angle)));
  end;
end;


function TVectArtShapeCreation.PreviewRect: TRect;
var
  DeltaX: Integer;
  DeltaY: Integer;
  HalfHeight: Integer;
  HalfWidth: Integer;
  MaxHalfHeight: Integer;
  MaxHalfWidth: Integer;
  Size: Integer;
  TargetX: Integer;
  TargetY: Integer;
begin
  if not FActive or (FEditorState = nil) or
    not (FEditorState.CurrentTool in [vetRectangleLine, vetRectangle,
      vetRoundedRectangleLine,
      vetRoundedRectangle, vetEllipseLine, vetEllipse, vetArc,
      vetArcShape]) then
    Exit(TRect.Empty);
  DeltaX := FCurrentPoint.X - FStartPoint.X;
  DeltaY := FCurrentPoint.Y - FStartPoint.Y;
  if ssAlt in FModifiers then
  begin
    MaxHalfWidth := Min(FStartPoint.X - FCanvasBounds.Left,
      FCanvasBounds.Right - FStartPoint.X);
    MaxHalfHeight := Min(FStartPoint.Y - FCanvasBounds.Top,
      FCanvasBounds.Bottom - FStartPoint.Y);
    HalfWidth := Min(Abs(DeltaX), MaxHalfWidth);
    HalfHeight := Min(Abs(DeltaY), MaxHalfHeight);
    if ssShift in FModifiers then
    begin
      Size := Min(Max(HalfWidth, HalfHeight),
        Min(MaxHalfWidth, MaxHalfHeight));
      HalfWidth := Size;
      HalfHeight := Size;
    end;
    Exit(Rect(FStartPoint.X - HalfWidth, FStartPoint.Y - HalfHeight,
      FStartPoint.X + HalfWidth, FStartPoint.Y + HalfHeight));
  end;
  TargetX := FCurrentPoint.X;
  TargetY := FCurrentPoint.Y;
  if ssShift in FModifiers then
  begin
    Size := Max(Abs(DeltaX), Abs(DeltaY));
    if DeltaX < 0 then
      Size := Min(Size, FStartPoint.X - FCanvasBounds.Left)
    else
      Size := Min(Size, FCanvasBounds.Right - FStartPoint.X);
    if DeltaY < 0 then
      Size := Min(Size, FStartPoint.Y - FCanvasBounds.Top)
    else
      Size := Min(Size, FCanvasBounds.Bottom - FStartPoint.Y);
    if DeltaX < 0 then
      TargetX := FStartPoint.X - Size
    else
      TargetX := FStartPoint.X + Size;
    if DeltaY < 0 then
      TargetY := FStartPoint.Y - Size
    else
      TargetY := FStartPoint.Y + Size;
  end;
  Result := Rect(Min(FStartPoint.X, TargetX),
    Min(FStartPoint.Y, TargetY), Max(FStartPoint.X, TargetX),
    Max(FStartPoint.Y, TargetY));
end;

end.
