// 貼り付けた一式の所有権と選択状態を、文書とUndo／Redo履歴の間で管理する。
unit MapRakuInsertObjectsCommand;

interface

uses
  MapRakuDocument, MapRakuEditorState, MapRakuEditCommands;

type
  TMapRakuInsertObjectsCommand = class(TVectArtEditCommand)
  private
    FDocument : TVectArtDocument;        // 非所有の編集対象。
    FState    : TVectArtEditorState;     // 選択と開いた階層の復元先。
    FParent   : TMapRakuGroupLayer; // nilなら文書直下。
    FLayers   : TArray<TVectArtLayer>;   // Undo中だけ履歴が所有する挿入物。
    FBefore   : TArray<TVectArtLayer>;   // グループ内の元選択。
    FSelection: TArray<Integer>;         // 文書直下の元選択。
    FIndex    : Integer;                 // 挿入開始位置。
    FInserted : Boolean;                 // 挿入物の所有権が文書にあるか。
  public
    // 挿入物の所有権を受け取り、元の階層・選択・挿入位置を記録する。
    constructor Create(Document: TVectArtDocument; State: TVectArtEditorState;
      const Layers: TArray<TVectArtLayer>);
    // Undo中に文書から取り外した挿入物だけを破棄する。
    destructor Destroy; override;
    // 保存した階層へ積層順に挿入し、挿入物を選択する。
    procedure Execute; override;
    // 挿入物を履歴側へ取り戻し、挿入前の選択を復元する。
    procedure Undo; override;
  end;

implementation

constructor TMapRakuInsertObjectsCommand.Create(Document: TVectArtDocument; State: TVectArtEditorState;
  const Layers: TArray<TVectArtLayer>);
begin
  inherited Create;
  FDocument := Document;
  FState := State;
  FLayers := Copy(Layers);
  FSelection := Document.GetSelectedLayerIndices;
  if State <> nil then FParent := State.OpenGroup;
  if FParent <> nil then
  begin
    FBefore := State.GetOpenGroupChildren;
    FIndex := FParent.ChildCount;
  end
  else FIndex := Document.LayerCount;
end;

destructor TMapRakuInsertObjectsCommand.Destroy;
var
  Layer: TVectArtLayer;
begin
  if not FInserted then
    for Layer in FLayers do Layer.Free;
  inherited Destroy;
end;

procedure TMapRakuInsertObjectsCommand.Execute;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  FDocument.BeginUpdate;
  try
    SetLength(Indices, Length(FLayers));
    for I := 0 to High(FLayers) do
    begin
      Indices[I] := FIndex + I;
      if FParent <> nil then FParent.InsertChild(Indices[I], FLayers[I])
      else FDocument.InsertLayer(Indices[I], FLayers[I]);
    end;
    FInserted := True;
    if FState <> nil then FState.OpenGroupInDocument(FDocument, FParent);
    if FParent <> nil then FState.SetOpenGroupChildren(FLayers)
    else FDocument.SetSelectedLayers(Indices);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuInsertObjectsCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := High(FLayers) downto 0 do
      if FParent <> nil then FLayers[I] := FParent.ExtractChild(FIndex + I)
      else FLayers[I] := FDocument.ExtractLayer(FIndex + I);
    FInserted := False;
    if FState <> nil then FState.OpenGroupInDocument(FDocument, FParent);
    if FParent <> nil then FState.SetOpenGroupChildren(FBefore)
    else FDocument.SetSelectedLayers(FSelection);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
end;

end.