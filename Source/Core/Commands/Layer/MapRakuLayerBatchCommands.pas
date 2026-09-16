// 同種レイヤーの一括挿入を1回のUndo／Redoとして管理する。
unit MapRakuLayerBatchCommands;

interface

uses
  MapRakuDocument, MapRakuEditCommands;

type
  TVectArtInsertRectanglesCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TArray<TVectArtRectangleData>;
    FDocument: TVectArtDocument;
    FStartIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; StartIndex: Integer;
      const Data: TArray<TVectArtRectangleData>; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtInsertImagesCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TArray<TVectArtImageData>;
    FDocument: TVectArtDocument;
    FStartIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; StartIndex: Integer;
      const Data: TArray<TVectArtImageData>; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtInsertPathsCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TArray<TVectArtPathData>;
    FDocument: TVectArtDocument;
    FStartIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; StartIndex: Integer;
      const Data: TArray<TVectArtPathData>; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

{ TVectArtInsertPathsCommand }

constructor TVectArtInsertPathsCommand.Create(ADocument: TVectArtDocument;
  StartIndex: Integer; const Data: TArray<TVectArtPathData>;
  const BeforeSelection, AfterSelection: TArray<Integer>);
var
  I: Integer;
begin
  inherited Create;
  FDocument := ADocument;
  FStartIndex := StartIndex;
  FData := Copy(Data);
  for I := 0 to High(FData) do
    FData[I].Vertices := Copy(Data[I].Vertices);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtInsertPathsCommand.Execute;
var
  I: Integer;
begin
  if FDocument = nil then
    Exit;
  for I := 0 to High(FData) do
    FDocument.InsertPath(FStartIndex + I, FData[I]);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtInsertPathsCommand.Undo;
var
  I: Integer;
  RemovedData: TVectArtPathData;
begin
  if FDocument = nil then
    Exit;
  for I := High(FData) downto 0 do
    FDocument.RemovePath(FStartIndex + I, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtInsertImagesCommand }

constructor TVectArtInsertImagesCommand.Create(ADocument: TVectArtDocument;
  StartIndex: Integer; const Data: TArray<TVectArtImageData>;
  const BeforeSelection, AfterSelection: TArray<Integer>);
var
  I: Integer;
begin
  inherited Create;
  FDocument := ADocument;
  FStartIndex := StartIndex;
  FData := Copy(Data);
  for I := 0 to High(FData) do
    FData[I].PngData := Copy(Data[I].PngData);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtInsertImagesCommand.Execute;
var
  I: Integer;
begin
  if FDocument = nil then
    Exit;
  for I := 0 to High(FData) do
    FDocument.InsertImage(FStartIndex + I, FData[I]);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtInsertImagesCommand.Undo;
var
  I: Integer;
  RemovedData: TVectArtImageData;
begin
  if FDocument = nil then
    Exit;
  for I := High(FData) downto 0 do
    FDocument.RemoveImage(FStartIndex + I, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

constructor TVectArtInsertRectanglesCommand.Create(
  ADocument: TVectArtDocument; StartIndex: Integer;
  const Data: TArray<TVectArtRectangleData>; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FStartIndex := StartIndex;
  FData := Copy(Data);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtInsertRectanglesCommand.Execute;
var
  I: Integer;
begin
  if FDocument = nil then
    Exit;
  for I := 0 to High(FData) do
    FDocument.InsertRectangle(FStartIndex + I, FData[I]);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtInsertRectanglesCommand.Undo;
var
  I: Integer;
  RemovedData: TVectArtRectangleData;
begin
  if FDocument = nil then
    Exit;
  for I := High(FData) downto 0 do
    FDocument.RemoveRectangle(FStartIndex + I, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

end.
