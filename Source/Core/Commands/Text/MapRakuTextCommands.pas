// 文字レイヤーの挿入、削除、編集セッションをUndo／Redo可能にする。
unit MapRakuTextCommands;

interface

uses
  MapRakuDocument, MapRakuEditCommands;

// 文字レイヤーの全永続属性を独立したデータへ写す。
function CaptureMapRakuTextData(
  Layer: TMapRakuTextLayer): TMapRakuTextData;

type
  TMapRakuInsertTextCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuTextData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuTextData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuInsertTextPathCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FDocument: TVectArtDocument;
    FInDocument: Boolean;
    FIndex: Integer;
    FLayer: TMapRakuTextPathLayer;
  public
    // 適用済み文字パスの所有権をDocumentとコマンドの間で移してUndo／Redoする。
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      Layer: TMapRakuTextPathLayer; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    // Undo後にコマンドが所有している文字パスだけを解放する。
    destructor Destroy; override;
    // 保持中の文字パスを元の積層位置へ戻して作成後の選択を復元する。
    procedure Execute; override;
    // 文字パスをDocumentから取り出して所有し、作成前の選択を復元する。
    procedure Undo; override;
  end;

  TMapRakuDeleteTextCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuTextData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuTextData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuTextDataCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TMapRakuTextLayer; // グループ内編集では積層番号の代わりに対象を保持する。
    FNewData: TMapRakuTextData;
    FOldData: TMapRakuTextData;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const OldData, NewData: TMapRakuTextData);
    // グループ内の既存文字を所有せず参照し、同じ編集履歴を適用する。
    constructor CreateForLayer(ADocument: TVectArtDocument;
      Layer: TMapRakuTextLayer; const OldData,
      NewData: TMapRakuTextData);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

constructor TMapRakuInsertTextPathCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  Layer: TMapRakuTextPathLayer; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FLayer := Layer;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
  FInDocument := True;
end;

destructor TMapRakuInsertTextPathCommand.Destroy;
begin
  if not FInDocument then
    FLayer.Free;
  inherited Destroy;
end;

procedure TMapRakuInsertTextPathCommand.Execute;
begin
  if (FDocument = nil) or FInDocument or (FLayer = nil) then
    Exit;
  FIndex := FDocument.InsertLayer(FIndex, FLayer);
  FInDocument := True;
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertTextPathCommand.Undo;
begin
  if (FDocument = nil) or not FInDocument then
    Exit;
  FLayer := TMapRakuTextPathLayer(FDocument.ExtractLayer(FIndex));
  FInDocument := False;
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

function CaptureMapRakuTextData(
  Layer: TMapRakuTextLayer): TMapRakuTextData;
begin
  Result := Default(TMapRakuTextData);
  if Layer = nil then
    Exit;
  Result.Alignment := Layer.Alignment;
  Result.Bounds := Layer.Bounds;
  if Layer is TMapRakuTextPathLayer then
  begin
    Result.TextPathAttachment :=
      TMapRakuTextPathLayer(Layer).Attachment;
    Result.CharacterPathOffsets :=
      TMapRakuTextPathLayer(Layer).CharacterPathOffsets;
    Result.CharacterPositionManual :=
      TMapRakuTextPathLayer(Layer).CharacterPositionManual;
    Result.CharacterScales :=
      TMapRakuTextPathLayer(Layer).CharacterScales;
  end;
  Result.FontFamily := Layer.FontFamily;
  Result.FontSize := Layer.FontSize;
  Result.FontStyle := Layer.FontStyle;
  Result.IndividualLetterSpacingRatios :=
    Layer.IndividualLetterSpacingRatios;
  Result.LetterSpacingRatio := Layer.LetterSpacingRatio;
  Result.LineSpacingRatio := Layer.LineSpacingRatio;
  Result.Locked := Layer.Locked;
  Result.Name := Layer.Name;
  Result.Opacity := Layer.Opacity;
  Result.RotationDegrees := Layer.RotationDegrees;
  Result.Text := Layer.Text;
  Result.TextColor := Layer.FillColor;
  Result.TransformMode := Layer.TransformMode;
  Result.Visible := Layer.Visible;
  Result.WrapWidth := Layer.WrapWidth;
end;

constructor TMapRakuInsertTextCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuTextData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuInsertTextCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertText(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertTextCommand.Undo;
var
  RemovedData: TMapRakuTextData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveText(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

constructor TMapRakuDeleteTextCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuTextData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuDeleteTextCommand.Execute;
var
  RemovedData: TMapRakuTextData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveText(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuDeleteTextCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertText(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

constructor TMapRakuTextDataCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const OldData, NewData: TMapRakuTextData);
begin
  inherited Create;
  FDocument := ADocument;
  if (ADocument <> nil) and (Index > 0) and
    (Index < ADocument.LayerCount) and
    (ADocument[Index] is TMapRakuTextLayer) then
    FLayer := TMapRakuTextLayer(ADocument[Index]);
  FOldData := OldData;
  FNewData := NewData;
  FOldData.IndividualLetterSpacingRatios :=
    Copy(OldData.IndividualLetterSpacingRatios);
  FNewData.IndividualLetterSpacingRatios :=
    Copy(NewData.IndividualLetterSpacingRatios);
  FOldData.CharacterPathOffsets := Copy(OldData.CharacterPathOffsets);
  FNewData.CharacterPathOffsets := Copy(NewData.CharacterPathOffsets);
  FOldData.CharacterPositionManual :=
    Copy(OldData.CharacterPositionManual);
  FNewData.CharacterPositionManual :=
    Copy(NewData.CharacterPositionManual);
  FOldData.CharacterScales := Copy(OldData.CharacterScales);
  FNewData.CharacterScales := Copy(NewData.CharacterScales);
end;

constructor TMapRakuTextDataCommand.CreateForLayer(
  ADocument: TVectArtDocument; Layer: TMapRakuTextLayer;
  const OldData, NewData: TMapRakuTextData);
begin
  Create(ADocument, -1, OldData, NewData);
  FLayer := Layer;
end;

procedure TMapRakuTextDataCommand.Execute;
begin
  if (FDocument <> nil) and (FLayer <> nil) then
    FDocument.SetTextLayerData(FLayer, FNewData);
end;

procedure TMapRakuTextDataCommand.Undo;
begin
  if (FDocument <> nil) and (FLayer <> nil) then
    FDocument.SetTextLayerData(FLayer, FOldData);
end;

end.
