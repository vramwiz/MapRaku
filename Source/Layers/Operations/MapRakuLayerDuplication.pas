// 選択レイヤーをフィルターを含む完全なオブジェクトとして複製する。
unit MapRakuLayerDuplication;

interface

uses
  MapRakuDocument, MapRakuEditHistory;

// 通常レイヤーだけの同種選択で、ロックされていない場合にTrueを返す。
function CanDuplicateSelectedLayers(ADocument: TVectArtDocument): Boolean;
// 選択レイヤーを24論理pxずらして完全複製し、操作を1履歴として追加する。
procedure DuplicateSelectedLayers(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory);

implementation

uses
  System.Classes, System.Generics.Collections, System.SysUtils,
  MapRakuEditCommands, MapRakuGroupCommands,
  MapRakuLayerGeometry;

const
  DUPLICATE_OFFSET= 24;

type
  TMapRakuDuplicateLayersCommand = class(TVectArtEditCommand)
  private
    FBeforeSelection     : TArray<Integer>;
    FDocument            : TVectArtDocument;
    FDuplicates          : TArray<TVectArtLayer>;
    FDuplicatesInDocument: Boolean;
    FIndices             : TArray<Integer>;
  public
    constructor Create(ADocument: TVectArtDocument;
      const BeforeSelection, Indices: TArray<Integer>;
      const Duplicates: TArray<TVectArtLayer>);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

function SupportedDuplicateKind(Layer: TVectArtLayer): Integer;
begin
  if Layer is TMapRakuEllipseArcShapeLayer then Exit(1);
  if Layer is TMapRakuEllipseLineLayer then Exit(2);
  if Layer is TMapRakuRoundedRectangleLineLayer then Exit(3);
  if Layer is TMapRakuRectangleLineLayer then Exit(4);
  if Layer is TMapRakuArcLayer then Exit(5);
  if Layer is TMapRakuEllipseLayer then Exit(6);
  if Layer is TMapRakuRoundedRectangleLayer then Exit(7);
  if Layer is TMapRakuTextLayer then Exit(8);
  if Layer is TVectArtRectangleLayer then Exit(9);
  if Layer is TVectArtImageLayer then Exit(10);
  if Layer is TVectArtPathLayer then Exit(11);
  Result := 0;
end;

function CanDuplicateSelectedLayers(ADocument: TVectArtDocument): Boolean;
var
  I: Integer;
  Kind: Integer;
  SelectedKind: Integer;
begin
  Result := (ADocument <> nil) and (ADocument.SelectionCount > 0);
  if not Result then Exit;
  SelectedKind := 0;
  for I := 0 to ADocument.LayerCount - 1 do
    if ADocument.IsLayerSelected(I) then
    begin
      if (I = 0) or ADocument[I].Locked then Exit(False);
      Kind := SupportedDuplicateKind(ADocument[I]);
      if Kind = 0 then Exit(False);
      if SelectedKind = 0 then
        SelectedKind := Kind
      else if SelectedKind <> Kind then
        Exit(False);
    end;
end;

function CopyName(const SourceName: string; UsedNames: TStrings): string;
var
  Number: Integer;
begin
  Result := SourceName + ' Copy';
  Number := 2;
  while UsedNames.IndexOf(Result) >= 0 do
  begin
    Result := SourceName + ' Copy ' + Number.ToString;
    Inc(Number);
  end;
  UsedNames.Add(Result);
end;

constructor TMapRakuDuplicateLayersCommand.Create(
  ADocument: TVectArtDocument; const BeforeSelection,
  Indices: TArray<Integer>; const Duplicates: TArray<TVectArtLayer>);
begin
  inherited Create;
  FDocument := ADocument;
  FBeforeSelection := Copy(BeforeSelection);
  FIndices := Copy(Indices);
  FDuplicates := Copy(Duplicates);
  FDuplicatesInDocument := False;
end;

destructor TMapRakuDuplicateLayersCommand.Destroy;
var
  Layer: TVectArtLayer;
begin
  if not FDuplicatesInDocument then
    for Layer in FDuplicates do Layer.Free;
  inherited Destroy;
end;

procedure TMapRakuDuplicateLayersCommand.Execute;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := 0 to High(FDuplicates) do
      FDocument.InsertLayer(FIndices[I], FDuplicates[I]);
    FDuplicatesInDocument := True;
    FDocument.SetSelectedLayers(FIndices);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuDuplicateLayersCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := High(FIndices) downto 0 do
      FDuplicates[I] := FDocument.ExtractLayer(FIndices[I]);
    FDuplicatesInDocument := False;
    FDocument.SetSelectedLayers(FBeforeSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure DuplicateSelectedLayers(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory);
var
  BeforeSelection: TArray<Integer>;
  Command: TMapRakuDuplicateLayersCommand;
  Duplicates: TList<TVectArtLayer>;
  I: Integer;
  Indices: TList<Integer>;
  UsedNames: TStringList;
begin
  if not CanDuplicateSelectedLayers(ADocument) then Exit;
  BeforeSelection := ADocument.GetSelectedLayerIndices;
  Duplicates := TList<TVectArtLayer>.Create;
  Indices := TList<Integer>.Create;
  UsedNames := TStringList.Create;
  try
    UsedNames.CaseSensitive := False;
    for I := 0 to ADocument.LayerCount - 1 do
      UsedNames.Add(ADocument[I].Name);
    for I := 1 to ADocument.LayerCount - 1 do
      if ADocument.IsLayerSelected(I) then
      begin
        Duplicates.Add(CloneMapRakuLayer(ADocument[I],
          CopyName(ADocument[I].Name, UsedNames)));
        TranslateMapRakuLayer(Duplicates.Last, DUPLICATE_OFFSET,
          DUPLICATE_OFFSET);
        Indices.Add(ADocument.LayerCount + Indices.Count);
      end;
    Command := TMapRakuDuplicateLayersCommand.Create(ADocument,
      BeforeSelection, Indices.ToArray, Duplicates.ToArray);
    Duplicates.Clear;
    Command.Execute;
    if AEditHistory <> nil then
      AEditHistory.AddApplied(Command)
    else
      Command.Free;
  finally
    for I := 0 to Duplicates.Count - 1 do Duplicates[I].Free;
    UsedNames.Free;
    Indices.Free;
    Duplicates.Free;
  end;
end;

end.
