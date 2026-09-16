// 図形レイヤーの挿入、削除、積層順変更をUndo／Redo可能にする。
unit MapRakuLayerStructureCommands;

interface

uses
  MapRakuDocument, MapRakuEditCommands;

type
  TVectArtInsertRectangleCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtRectangleData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtRectangleData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuInsertRoundedRectangleCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuRoundedRectangleData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuRoundedRectangleData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuInsertEllipseCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuEllipseData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuEllipseData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuInsertArcCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuArcData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuArcData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuInsertEllipseArcShapeCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuEllipseArcShapeData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuEllipseArcShapeData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuInsertRectangleLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuRectangleLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuRectangleLineData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuInsertRoundedRectangleLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuRoundedRectangleLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuRoundedRectangleLineData;
      const BeforeSelection, AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuInsertEllipseLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuEllipseLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuEllipseLineData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtInsertPathCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtPathData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtPathData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuInsertShapeCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuShapeData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    // Shape挿入の前後選択状態と独立した輪郭データを保持する。
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuShapeData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtDeleteRectangleCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtRectangleData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtRectangleData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuDeleteRoundedRectangleCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuRoundedRectangleData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuRoundedRectangleData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuDeleteEllipseCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuEllipseData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuEllipseData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuDeleteArcCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuArcData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuArcData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuDeleteEllipseArcShapeCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuEllipseArcShapeData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuEllipseArcShapeData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuDeleteRectangleLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuRectangleLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuRectangleLineData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuDeleteRoundedRectangleLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuRoundedRectangleLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuRoundedRectangleLineData;
      const BeforeSelection, AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuDeleteEllipseLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuEllipseLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuEllipseLineData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtDeletePathCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtPathData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtPathData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuDeleteShapeCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TMapRakuShapeData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    // Shape削除の前後選択状態と再挿入に必要な全データを保持する。
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TMapRakuShapeData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtDeleteImageCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtImageData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtImageData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtMoveLayerCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FDocument: TVectArtDocument;
    FNewIndex: Integer;
    FOldIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; OldIndex,
      NewIndex: Integer; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

procedure CopyShapeData(const Source: TMapRakuShapeData;
  out Target: TMapRakuShapeData);
var
  I: Integer;
begin
  Target := Source;
  SetLength(Target.Contours, Length(Source.Contours));
  for I := 0 to High(Source.Contours) do
    Target.Contours[I].Vertices := Copy(Source.Contours[I].Vertices);
end;

{ TMapRakuInsertShapeCommand }

constructor TMapRakuInsertShapeCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuShapeData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  CopyShapeData(Data, FData);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuInsertShapeCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertShape(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertShapeCommand.Undo;
var
  RemovedData: TMapRakuShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveShape(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuDeleteShapeCommand }

constructor TMapRakuDeleteShapeCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuShapeData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  CopyShapeData(Data, FData);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuDeleteShapeCommand.Execute;
var
  RemovedData: TMapRakuShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveShape(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuDeleteShapeCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertShape(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtInsertPathCommand }

constructor TVectArtInsertPathCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TVectArtPathData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FData.Vertices := Copy(Data.Vertices);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtInsertPathCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertPath(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtInsertPathCommand.Undo;
var
  RemovedData: TVectArtPathData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemovePath(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtInsertRectangleCommand }

constructor TVectArtInsertRectangleCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TVectArtRectangleData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtInsertRectangleCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRectangle(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtInsertRectangleCommand.Undo;
var
  RemovedData: TVectArtRectangleData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRectangle(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuInsertRoundedRectangleCommand }

constructor TMapRakuInsertRoundedRectangleCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuRoundedRectangleData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuInsertRoundedRectangleCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRoundedRectangle(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertRoundedRectangleCommand.Undo;
var
  RemovedData: TMapRakuRoundedRectangleData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRoundedRectangle(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuInsertEllipseCommand }

constructor TMapRakuInsertEllipseCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuEllipseData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuInsertEllipseCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipse(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertEllipseCommand.Undo;
var
  RemovedData: TMapRakuEllipseData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipse(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuInsertArcCommand }

constructor TMapRakuInsertArcCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TMapRakuArcData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuInsertArcCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertArc(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertArcCommand.Undo;
var
  RemovedData: TMapRakuArcData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveArc(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuInsertEllipseArcShapeCommand }

constructor TMapRakuInsertEllipseArcShapeCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuEllipseArcShapeData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuInsertEllipseArcShapeCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipseArcShape(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertEllipseArcShapeCommand.Undo;
var
  RemovedData: TMapRakuEllipseArcShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipseArcShape(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuInsertRectangleLineCommand }

constructor TMapRakuInsertRectangleLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuRectangleLineData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuInsertRectangleLineCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRectangleLine(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertRectangleLineCommand.Undo;
var
  RemovedData: TMapRakuRectangleLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRectangleLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuInsertRoundedRectangleLineCommand }

constructor TMapRakuInsertRoundedRectangleLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuRoundedRectangleLineData;
  const BeforeSelection, AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuInsertRoundedRectangleLineCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRoundedRectangleLine(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertRoundedRectangleLineCommand.Undo;
var
  RemovedData: TMapRakuRoundedRectangleLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRoundedRectangleLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuInsertEllipseLineCommand }

constructor TMapRakuInsertEllipseLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuEllipseLineData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuInsertEllipseLineCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipseLine(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuInsertEllipseLineCommand.Undo;
var
  RemovedData: TMapRakuEllipseLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipseLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtDeleteRectangleCommand }

constructor TVectArtDeletePathCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TVectArtPathData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FData.Vertices := Copy(Data.Vertices);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtDeletePathCommand.Execute;
var
  RemovedData: TVectArtPathData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemovePath(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtDeletePathCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertPath(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

constructor TVectArtDeleteImageCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TVectArtImageData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FData.PngData := Copy(Data.PngData);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtDeleteImageCommand.Execute;
var
  RemovedData: TVectArtImageData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveImage(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtDeleteImageCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertImage(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtDeleteRectangleCommand }

constructor TVectArtDeleteRectangleCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TVectArtRectangleData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtDeleteRectangleCommand.Execute;
var
  RemovedData: TVectArtRectangleData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRectangle(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtDeleteRectangleCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRectangle(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuDeleteRoundedRectangleCommand }

constructor TMapRakuDeleteRoundedRectangleCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuRoundedRectangleData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuDeleteRoundedRectangleCommand.Execute;
var
  RemovedData: TMapRakuRoundedRectangleData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRoundedRectangle(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuDeleteRoundedRectangleCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRoundedRectangle(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuDeleteEllipseCommand }

constructor TMapRakuDeleteEllipseCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuEllipseData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuDeleteEllipseCommand.Execute;
var
  RemovedData: TMapRakuEllipseData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipse(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuDeleteEllipseCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipse(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuDeleteArcCommand }

constructor TMapRakuDeleteArcCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TMapRakuArcData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuDeleteArcCommand.Execute;
var
  RemovedData: TMapRakuArcData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveArc(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuDeleteArcCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertArc(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuDeleteEllipseArcShapeCommand }

constructor TMapRakuDeleteEllipseArcShapeCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuEllipseArcShapeData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuDeleteEllipseArcShapeCommand.Execute;
var
  RemovedData: TMapRakuEllipseArcShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipseArcShape(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuDeleteEllipseArcShapeCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipseArcShape(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuDeleteRectangleLineCommand }

constructor TMapRakuDeleteRectangleLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuRectangleLineData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuDeleteRectangleLineCommand.Execute;
var
  RemovedData: TMapRakuRectangleLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRectangleLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuDeleteRectangleLineCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRectangleLine(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuDeleteRoundedRectangleLineCommand }

constructor TMapRakuDeleteRoundedRectangleLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuRoundedRectangleLineData;
  const BeforeSelection, AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuDeleteRoundedRectangleLineCommand.Execute;
var
  RemovedData: TMapRakuRoundedRectangleLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRoundedRectangleLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuDeleteRoundedRectangleLineCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRoundedRectangleLine(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TMapRakuDeleteEllipseLineCommand }

constructor TMapRakuDeleteEllipseLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TMapRakuEllipseLineData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TMapRakuDeleteEllipseLineCommand.Execute;
var
  RemovedData: TMapRakuEllipseLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipseLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TMapRakuDeleteEllipseLineCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipseLine(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtMoveLayerCommand }

constructor TVectArtMoveLayerCommand.Create(ADocument: TVectArtDocument;
  OldIndex, NewIndex: Integer; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FOldIndex := OldIndex;
  FNewIndex := NewIndex;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtMoveLayerCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FDocument.MoveLayer(FOldIndex, FNewIndex);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtMoveLayerCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FDocument.MoveLayer(FNewIndex, FOldIndex);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

end.
