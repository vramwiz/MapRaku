// グループまたはグループ内レイヤーの移動・拡大縮小・回転をUndo／Redo可能にする。
unit MapRakuGroupTransformCommands;

interface

uses
  System.Types, MapRakuDocument, MapRakuEditCommands;

type
  // 適用済みの平行移動量を保持し、同じレイヤーへ逆変換できるようにする。
  TMapRakuTranslateLayerCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FDX: Single;
    FDY: Single;
    FLayer: TVectArtLayer;
    procedure Translate(DX, DY: Single);
  public
    constructor Create(ADocument: TVectArtDocument; Layer: TVectArtLayer;
      DX, DY: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 選択全体の変形前後の外接範囲を使い、単一レイヤーの倍率を可逆にする。
  TMapRakuScaleLayerCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FSourceBounds: TRectF;
    FTargetBounds: TRectF;
    procedure Scale(const SourceBounds, TargetBounds: TRectF);
  public
    constructor Create(ADocument: TVectArtDocument; Layer: TVectArtLayer;
      const SourceBounds, TargetBounds: TRectF);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // グループ内Textの直接リサイズで選択した変形モードを可逆にする。
  TMapRakuTextTransformModeCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TMapRakuTextLayer;
    FNewMode: TMapRakuTextTransformMode;
    FOldMode: TMapRakuTextTransformMode;
    procedure Apply(Mode: TMapRakuTextTransformMode);
  public
    constructor Create(ADocument: TVectArtDocument;
      Layer: TMapRakuTextLayer; OldMode,
      NewMode: TMapRakuTextTransformMode);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 共通中心と回転量を保持し、グループ内レイヤーの回転を可逆にする。
  TMapRakuRotateLayerCommand = class(TVectArtEditCommand)
  private
    FCenter: TPointF;
    FDegrees: Single;
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    procedure Rotate(Degrees: Single);
  public
    constructor Create(ADocument: TVectArtDocument; Layer: TVectArtLayer;
      const Center: TPointF; Degrees: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // トップレベルで複数選択されたグループだけを一括移動する。
  TMapRakuTranslateGroupsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FDX: Single;
    FDY: Single;
    FLayerIndices: TArray<Integer>;
    procedure Translate(DX, DY: Single);
  public
    constructor Create(ADocument: TVectArtDocument;
      const LayerIndices: TArray<Integer>; DX, DY: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  MapRakuLayerGeometry;

constructor TMapRakuTranslateLayerCommand.Create(
  ADocument: TVectArtDocument; Layer: TVectArtLayer; DX, DY: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := Layer;
  FDX := DX;
  FDY := DY;
end;

procedure TMapRakuTranslateLayerCommand.Execute;
begin
  Translate(FDX, FDY);
end;

procedure TMapRakuTranslateLayerCommand.Translate(DX, DY: Single);
begin
  TranslateMapRakuLayer(FLayer, DX, DY);
  FDocument.Changed;
end;

procedure TMapRakuTranslateLayerCommand.Undo;
begin
  Translate(-FDX, -FDY);
end;

constructor TMapRakuScaleLayerCommand.Create(
  ADocument: TVectArtDocument; Layer: TVectArtLayer;
  const SourceBounds, TargetBounds: TRectF);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := Layer;
  FSourceBounds := SourceBounds;
  FTargetBounds := TargetBounds;
end;

procedure TMapRakuScaleLayerCommand.Execute;
begin
  Scale(FSourceBounds, FTargetBounds);
end;

procedure TMapRakuScaleLayerCommand.Scale(
  const SourceBounds, TargetBounds: TRectF);
begin
  ScaleMapRakuLayer(FLayer, SourceBounds, TargetBounds);
  FDocument.Changed;
end;

procedure TMapRakuScaleLayerCommand.Undo;
begin
  Scale(FTargetBounds, FSourceBounds);
end;

procedure TMapRakuTextTransformModeCommand.Apply(
  Mode: TMapRakuTextTransformMode);
begin
  if (FDocument = nil) or (FLayer = nil) then
    Exit;
  FLayer.TransformMode := Mode;
  FDocument.Changed;
end;

constructor TMapRakuTextTransformModeCommand.Create(
  ADocument: TVectArtDocument; Layer: TMapRakuTextLayer;
  OldMode, NewMode: TMapRakuTextTransformMode);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := Layer;
  FOldMode := OldMode;
  FNewMode := NewMode;
end;

procedure TMapRakuTextTransformModeCommand.Execute;
begin
  Apply(FNewMode);
end;

procedure TMapRakuTextTransformModeCommand.Undo;
begin
  Apply(FOldMode);
end;

constructor TMapRakuRotateLayerCommand.Create(
  ADocument: TVectArtDocument; Layer: TVectArtLayer;
  const Center: TPointF; Degrees: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := Layer;
  FCenter := Center;
  FDegrees := Degrees;
end;

procedure TMapRakuRotateLayerCommand.Execute;
begin
  Rotate(FDegrees);
end;

procedure TMapRakuRotateLayerCommand.Rotate(Degrees: Single);
begin
  RotateMapRakuLayer(FLayer, FCenter, Degrees);
  FDocument.Changed;
end;

procedure TMapRakuRotateLayerCommand.Undo;
begin
  Rotate(-FDegrees);
end;

constructor TMapRakuTranslateGroupsCommand.Create(
  ADocument: TVectArtDocument; const LayerIndices: TArray<Integer>;
  DX, DY: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndices := Copy(LayerIndices);
  FDX := DX;
  FDY := DY;
end;

procedure TMapRakuTranslateGroupsCommand.Execute;
begin
  Translate(FDX, FDY);
end;

procedure TMapRakuTranslateGroupsCommand.Translate(DX, DY: Single);
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := 0 to High(FLayerIndices) do
      if (FLayerIndices[I] > 0) and
        (FLayerIndices[I] < FDocument.LayerCount) and
        (FDocument[FLayerIndices[I]] is TMapRakuGroupLayer) then
        TranslateMapRakuLayer(FDocument[FLayerIndices[I]], DX, DY);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuTranslateGroupsCommand.Undo;
begin
  Translate(-FDX, -FDY);
end;

end.
