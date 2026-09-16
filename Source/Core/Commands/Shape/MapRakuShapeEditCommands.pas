// Shape輪郭とPath頂点列の置換をUndo／Redo履歴へ記録する。
unit MapRakuShapeEditCommands;

interface

uses
  MapRakuDocument, MapRakuEditCommands;

// 共通のPath頂点更新を行い、必要な場合だけ文字パスの表示枠も追従させる。
procedure ApplyMapRakuPathVertices(Document: TVectArtDocument;
  LayerIndex: Integer; const Vertices: TArray<TMapRakuVertex>;
  UpdateTextPathBounds: Boolean = False);

type
  TMapRakuPathVerticesCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewVertices: TArray<TMapRakuVertex>;
    FOldVertices: TArray<TMapRakuVertex>;
    FUpdateTextPathBounds: Boolean;
    procedure ApplyVertices(const Vertices: TArray<TMapRakuVertex>);
  public
    // 適用済みPath編集の前後の頂点列を独立して保持する。
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldVertices, NewVertices: TArray<TMapRakuVertex>;
      UpdateTextPathBounds: Boolean = False);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuShapeContoursCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewContours: TArray<TMapRakuContour>;
    FOldContours: TArray<TMapRakuContour>;
    procedure ApplyContours(const Contours: TArray<TMapRakuContour>);
  public
    // 適用済み編集の前後の輪郭を独立して保持し、後続編集による配列共有を防ぐ。
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldContours, NewContours: TArray<TMapRakuContour>);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  System.Math, System.Types, MapRakuGeometry,
  MapRakuPathOperations, MapRakuShapeOperations;

procedure ApplyMapRakuPathVertices(Document: TVectArtDocument;
  LayerIndex: Integer; const Vertices: TArray<TMapRakuVertex>;
  UpdateTextPathBounds: Boolean);
var
  Bounds: TRectF;
  Center: TPointF;
  LocalVertices: TArray<TMapRakuVertex>;
  TextPathLayer: TMapRakuTextPathLayer;
begin
  if Document = nil then
    Exit;
  Document.BeginUpdate;
  try
    Document.SetPathVertices(LayerIndex, Vertices);
    if UpdateTextPathBounds and (Length(Vertices) > 0) and
      (LayerIndex > 0) and (LayerIndex < Document.LayerCount) and
      (Document[LayerIndex] is TMapRakuTextPathLayer) then
    begin
      TextPathLayer := TMapRakuTextPathLayer(Document[LayerIndex]);
      if SameValue(TextPathLayer.RotationDegrees, 0.0) then
        Bounds := MapRakuPathVerticesBounds(Vertices)
      else
      begin
        LocalVertices := RotateMapRakuPathVertices(Vertices,
          TPointF.Zero, -TextPathLayer.RotationDegrees);
        Bounds := MapRakuPathVerticesBounds(LocalVertices);
      end;
      Bounds.Top := Bounds.Top - Max(TextPathLayer.FontSize, 1.0);
      if Bounds.Width < 1.0 then
        Bounds.Right := Bounds.Left + 1.0;
      if not SameValue(TextPathLayer.RotationDegrees, 0.0) then
      begin
        Center := RotatePointAround(Bounds.CenterPoint, TPointF.Zero,
          TextPathLayer.RotationDegrees);
        Bounds := TRectF.Create(Center.X - Bounds.Width * 0.5,
          Center.Y - Bounds.Height * 0.5,
          Center.X + Bounds.Width * 0.5,
          Center.Y + Bounds.Height * 0.5);
      end;
      TextPathLayer.Bounds := Bounds;
      TextPathLayer.WrapWidth := 0;
      Document.Changed;
    end;
  finally
    Document.EndUpdate;
  end;
end;

procedure TMapRakuPathVerticesCommand.ApplyVertices(
  const Vertices: TArray<TMapRakuVertex>);
begin
  if FDocument <> nil then
    ApplyMapRakuPathVertices(FDocument, FLayerIndex, Vertices,
      FUpdateTextPathBounds);
end;

constructor TMapRakuPathVerticesCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer; const OldVertices,
  NewVertices: TArray<TMapRakuVertex>;
  UpdateTextPathBounds: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldVertices := CloneMapRakuPathVertices(OldVertices);
  FNewVertices := CloneMapRakuPathVertices(NewVertices);
  FUpdateTextPathBounds := UpdateTextPathBounds;
end;

procedure TMapRakuPathVerticesCommand.Execute;
begin
  ApplyVertices(FNewVertices);
end;

procedure TMapRakuPathVerticesCommand.Undo;
begin
  ApplyVertices(FOldVertices);
end;

procedure TMapRakuShapeContoursCommand.ApplyContours(
  const Contours: TArray<TMapRakuContour>);
begin
  if FDocument <> nil then
    FDocument.SetShapeContours(FLayerIndex, Contours);
end;

constructor TMapRakuShapeContoursCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer; const OldContours,
  NewContours: TArray<TMapRakuContour>);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldContours := CloneMapRakuShapeContours(OldContours);
  FNewContours := CloneMapRakuShapeContours(NewContours);
end;

procedure TMapRakuShapeContoursCommand.Execute;
begin
  ApplyContours(FNewContours);
end;

procedure TMapRakuShapeContoursCommand.Undo;
begin
  ApplyContours(FOldContours);
end;

end.
