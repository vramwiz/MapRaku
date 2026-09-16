// Shape論理演算による複数レイヤーから結果レイヤーへの置換をUndo／Redo可能にする。
unit MapRakuShapeBooleanCommands;

interface

uses
  MapRakuDocument, MapRakuEditCommands, MapRakuProjectiveTransform;

type
  TMapRakuShapeBooleanOriginalKind = (slsbokRectangle,
    slsbokRoundedRectangle, slsbokEllipse, slsbokEllipseArcShape,
    slsbokShape);

  TMapRakuShapeBooleanOriginal = record
    Transform: TArray<Double>; // Undoで元の表示変形を復元する。
    Kind: TMapRakuShapeBooleanOriginalKind;             // Undoで復元するレイヤー型。
    EllipseData: TMapRakuEllipseData;                   // 楕円だった場合の全属性。
    EllipseArcShapeData: TMapRakuEllipseArcShapeData;   // 楕円弧図形だった場合の全属性。
    RectangleData: TVectArtRectangleData;                    // 四角だった場合の全属性。
    RoundedRectangleData: TMapRakuRoundedRectangleData; // 角丸四角だった場合の全属性。
    ShapeData: TMapRakuShapeData;                        // Shapeだった場合の全属性と輪郭群。
  end;

  TMapRakuShapeBooleanCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;              // 結果レイヤーだけを選択した状態。
    FBeforeSelection: TArray<Integer>;             // 操作前の順序を含む選択状態。
    FDocument: TVectArtDocument;
    FOriginalData: TArray<TMapRakuShapeBooleanOriginal>; // Undoで元型を復元するデータ。
    FOriginalIndices: TArray<Integer>;             // 操作前の積層位置を昇順で保持する。
    FResultData: TMapRakuShapeData;
    FResultExists: Boolean;                        // 空演算では結果レイヤーを生成しない。
    FResultIndex: Integer;                         // 対象除去後の結果挿入位置。
    procedure CaptureOriginal(Index: Integer;
      out Original: TMapRakuShapeBooleanOriginal);
    procedure RemoveOriginals;
  public
    // 選択したShape／基本図形群と結果を独立して保持し、置換全体を1つの履歴項目にする。
    constructor Create(ADocument: TVectArtDocument;
      const SelectedIndices, BeforeSelection: TArray<Integer>;
      ResultOriginalIndex: Integer; const ResultData: TMapRakuShapeData;
      ResultExists: Boolean);
    // 元レイヤー群を結果Shapeへ置換し、空結果の場合は元レイヤー群の除去だけを行う。
    procedure Execute; override;
    // 結果Shapeを除去して元レイヤー群の型、積層位置、選択状態を復元する。
    procedure Undo; override;
  end;

implementation

uses
  MapRakuShapeOperations;

procedure CopyShapeData(const Source: TMapRakuShapeData;
  out Target: TMapRakuShapeData);
begin
  Target := Source;
  Target.Contours := CloneMapRakuShapeContours(Source.Contours);
end;

procedure TMapRakuShapeBooleanCommand.CaptureOriginal(Index: Integer;
  out Original: TMapRakuShapeBooleanOriginal);
var
  ArcShapeLayer: TMapRakuEllipseArcShapeLayer;
  EllipseLayer: TMapRakuEllipseLayer;
  RectangleLayer: TVectArtRectangleLayer;
  RoundedLayer: TMapRakuRoundedRectangleLayer;
  ShapeLayer: TMapRakuShapeLayer;
begin
  Original := Default(TMapRakuShapeBooleanOriginal);
  Original.Transform := FDocument[Index].Transform.ToArray;
  // 楕円弧図形はRectangle系の基底クラスなので、四角形より先に判定する。
  if FDocument[Index] is TMapRakuEllipseArcShapeLayer then
  begin
    Original.Kind := slsbokEllipseArcShape;
    ArcShapeLayer := TMapRakuEllipseArcShapeLayer(FDocument[Index]);
    Original.EllipseArcShapeData.Bounds := ArcShapeLayer.Bounds;
    Original.EllipseArcShapeData.FillColor := ArcShapeLayer.FillColor;
    Original.EllipseArcShapeData.Locked := ArcShapeLayer.Locked;
    Original.EllipseArcShapeData.Name := ArcShapeLayer.Name;
    Original.EllipseArcShapeData.Opacity := ArcShapeLayer.Opacity;
    Original.EllipseArcShapeData.RotationDegrees :=
      ArcShapeLayer.RotationDegrees;
    Original.EllipseArcShapeData.StartAngleDegrees :=
      ArcShapeLayer.StartAngleDegrees;
    Original.EllipseArcShapeData.SweepAngleDegrees :=
      ArcShapeLayer.SweepAngleDegrees;
    Original.EllipseArcShapeData.Visible := ArcShapeLayer.Visible;
    Exit;
  end;
  if FDocument[Index] is TMapRakuEllipseLayer then
  begin
    Original.Kind := slsbokEllipse;
    EllipseLayer := TMapRakuEllipseLayer(FDocument[Index]);
    Original.EllipseData.Bounds := EllipseLayer.Bounds;
    Original.EllipseData.FillColor := EllipseLayer.FillColor;
    Original.EllipseData.Locked := EllipseLayer.Locked;
    Original.EllipseData.Name := EllipseLayer.Name;
    Original.EllipseData.Opacity := EllipseLayer.Opacity;
    Original.EllipseData.RotationDegrees := EllipseLayer.RotationDegrees;
    Original.EllipseData.Visible := EllipseLayer.Visible;
    Exit;
  end;
  if FDocument[Index] is TMapRakuRoundedRectangleLayer then
  begin
    Original.Kind := slsbokRoundedRectangle;
    RoundedLayer := TMapRakuRoundedRectangleLayer(FDocument[Index]);
    Original.RoundedRectangleData.Bounds := RoundedLayer.Bounds;
    Original.RoundedRectangleData.CornerRadii := RoundedLayer.CornerRadii;
    Original.RoundedRectangleData.FillColor := RoundedLayer.FillColor;
    Original.RoundedRectangleData.Locked := RoundedLayer.Locked;
    Original.RoundedRectangleData.Name := RoundedLayer.Name;
    Original.RoundedRectangleData.Opacity := RoundedLayer.Opacity;
    Original.RoundedRectangleData.RotationDegrees :=
      RoundedLayer.RotationDegrees;
    Original.RoundedRectangleData.Visible := RoundedLayer.Visible;
    Exit;
  end;
  if FDocument[Index] is TVectArtRectangleLayer then
  begin
    Original.Kind := slsbokRectangle;
    RectangleLayer := TVectArtRectangleLayer(FDocument[Index]);
    Original.RectangleData.Bounds := RectangleLayer.Bounds;
    Original.RectangleData.FillColor := RectangleLayer.FillColor;
    Original.RectangleData.Locked := RectangleLayer.Locked;
    Original.RectangleData.Name := RectangleLayer.Name;
    Original.RectangleData.Opacity := RectangleLayer.Opacity;
    Original.RectangleData.RotationDegrees :=
      RectangleLayer.RotationDegrees;
    Original.RectangleData.Visible := RectangleLayer.Visible;
    Exit;
  end;
  Original.Kind := slsbokShape;
  ShapeLayer := TMapRakuShapeLayer(FDocument[Index]);
  Original.ShapeData.Contours := ShapeLayer.Contours;
  Original.ShapeData.FillColor := ShapeLayer.FillColor;
  Original.ShapeData.FillRule := ShapeLayer.FillRule;
  Original.ShapeData.Locked := ShapeLayer.Locked;
  Original.ShapeData.Name := ShapeLayer.Name;
  Original.ShapeData.Opacity := ShapeLayer.Opacity;
  Original.ShapeData.StrokeColor := ShapeLayer.StrokeColor;
  Original.ShapeData.StrokeStyle := ShapeLayer.StrokeStyle;
  Original.ShapeData.StrokeWidth := ShapeLayer.StrokeWidth;
  Original.ShapeData.Visible := ShapeLayer.Visible;
  Original.ShapeData.Contours := CloneMapRakuShapeContours(
    Original.ShapeData.Contours);
end;

constructor TMapRakuShapeBooleanCommand.Create(
  ADocument: TVectArtDocument; const SelectedIndices,
  BeforeSelection: TArray<Integer>; ResultOriginalIndex: Integer;
  const ResultData: TMapRakuShapeData; ResultExists: Boolean);
var
  I: Integer;
begin
  inherited Create;
  FDocument := ADocument;
  FBeforeSelection := Copy(BeforeSelection);
  FOriginalIndices := Copy(SelectedIndices);
  SetLength(FOriginalData, Length(SelectedIndices));
  FResultIndex := ResultOriginalIndex;
  for I := 0 to High(SelectedIndices) do
  begin
    CaptureOriginal(SelectedIndices[I], FOriginalData[I]);
    if SelectedIndices[I] < ResultOriginalIndex then
      Dec(FResultIndex);
  end;
  CopyShapeData(ResultData, FResultData);
  FResultExists := ResultExists;
  if FResultExists then
    FAfterSelection := TArray<Integer>.Create(FResultIndex)
  else
    FAfterSelection := nil;
end;

procedure TMapRakuShapeBooleanCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FDocument.BeginUpdate;
  try
    RemoveOriginals;
    if FResultExists then
      FResultIndex := FDocument.InsertShape(FResultIndex, FResultData);
    FDocument.SetSelectedLayers(FAfterSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuShapeBooleanCommand.RemoveOriginals;
var
  EllipseArcShapeData: TMapRakuEllipseArcShapeData;
  EllipseData: TMapRakuEllipseData;
  I: Integer;
  RectangleData: TVectArtRectangleData;
  RemovedData: TMapRakuShapeData;
  RoundedRectangleData: TMapRakuRoundedRectangleData;
begin
  // 後方から除去すれば、まだ除去していない元のレイヤー番号がずれない。
  for I := High(FOriginalIndices) downto 0 do
    case FOriginalData[I].Kind of
      slsbokRectangle:
        FDocument.RemoveRectangle(FOriginalIndices[I], RectangleData);
      slsbokRoundedRectangle:
        FDocument.RemoveRoundedRectangle(FOriginalIndices[I],
          RoundedRectangleData);
      slsbokEllipse:
        FDocument.RemoveEllipse(FOriginalIndices[I], EllipseData);
      slsbokEllipseArcShape:
        FDocument.RemoveEllipseArcShape(FOriginalIndices[I],
          EllipseArcShapeData);
      slsbokShape:
        FDocument.RemoveShape(FOriginalIndices[I], RemovedData);
    end;
end;

procedure TMapRakuShapeBooleanCommand.Undo;
var
  I: Integer;
  RemovedData: TMapRakuShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.BeginUpdate;
  try
    if FResultExists then
      FDocument.RemoveShape(FResultIndex, RemovedData);
    // 前方から元位置へ挿入すると、後続レイヤーも操作前の番号へ自然に戻る。
    for I := 0 to High(FOriginalIndices) do
      case FOriginalData[I].Kind of
        slsbokRectangle:
          FOriginalIndices[I] := FDocument.InsertRectangle(
            FOriginalIndices[I], FOriginalData[I].RectangleData);
        slsbokRoundedRectangle:
          FOriginalIndices[I] := FDocument.InsertRoundedRectangle(
            FOriginalIndices[I], FOriginalData[I].RoundedRectangleData);
        slsbokEllipse:
          FOriginalIndices[I] := FDocument.InsertEllipse(
            FOriginalIndices[I], FOriginalData[I].EllipseData);
        slsbokEllipseArcShape:
          FOriginalIndices[I] := FDocument.InsertEllipseArcShape(
            FOriginalIndices[I], FOriginalData[I].EllipseArcShapeData);
        slsbokShape:
          FOriginalIndices[I] := FDocument.InsertShape(
            FOriginalIndices[I], FOriginalData[I].ShapeData);
      end;
    for I := 0 to High(FOriginalIndices) do
      FDocument[FOriginalIndices[I]].Transform := TMapRakuTransform.FromArray(FOriginalData[I].Transform);
    FDocument.SetSelectedLayers(FBeforeSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

end.
