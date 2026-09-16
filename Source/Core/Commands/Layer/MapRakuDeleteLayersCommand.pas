// 文書直下の複数削除を、元の積層位置と所有権を保持してUndo／Redoする。
unit MapRakuDeleteLayersCommand;

interface

uses
  MapRakuDocument, MapRakuEditCommands;

type
  TMapRakuDeleteLayersCommand = class(TVectArtEditCommand)
  private
    FAfterSelection  : TArray<Integer>;       // 削除後に選択する残存行。
    FBeforeSelection : TArray<Integer>;       // Undoで復元する元の選択。
    FDeletedLayers   : TArray<TVectArtLayer>; // 削除中だけ履歴が所有するレイヤー。
    FDocument        : TVectArtDocument;      // 削除対象の文書。所有しない。
    FIndices         : TArray<Integer>;       // 昇順の元の挿入位置。
    FLayersInDocument: Boolean;               // レイヤーの所有権が文書にあるか。
  public
    // 昇順の削除位置と元の選択を保持する。作成時点では文書を変更しない。
    constructor Create(ADocument: TVectArtDocument;
      const Indices, BeforeSelection: TArray<Integer>);
    // 文書から取り外されたレイヤーだけを破棄する。
    destructor Destroy; override;
    // 後方から一括削除し、残存行へ選択を移す。
    procedure Execute; override;
    // 元の位置へレイヤーを戻し、削除前の選択を復元する。
    procedure Undo; override;
  end;

implementation

uses System.Math;

constructor TMapRakuDeleteLayersCommand.Create(
  ADocument: TVectArtDocument; const Indices,
  BeforeSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndices := Copy(Indices);
  FBeforeSelection := Copy(BeforeSelection);
  SetLength(FDeletedLayers, Length(FIndices));
  FLayersInDocument := True;
end;

destructor TMapRakuDeleteLayersCommand.Destroy;
var
  Layer: TVectArtLayer;
begin
  if not FLayersInDocument then
    for Layer in FDeletedLayers do
      Layer.Free;
  inherited Destroy;
end;

procedure TMapRakuDeleteLayersCommand.Execute;
var
  I: Integer;
  SelectionIndex: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := High(FIndices) downto 0 do
      FDeletedLayers[I] := FDocument.ExtractLayer(FIndices[I]);
    FLayersInDocument := False;
    if FDocument.LayerCount > 1 then
    begin
      SelectionIndex := Min(FIndices[0], FDocument.LayerCount - 1);
      FAfterSelection := [SelectionIndex];
    end
    else
      FAfterSelection := nil;
    FDocument.SetSelectedLayers(FAfterSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuDeleteLayersCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := 0 to High(FIndices) do
      FDocument.InsertLayer(FIndices[I], FDeletedLayers[I]);
    FLayersInDocument := True;
    FDocument.SetSelectedLayers(FBeforeSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

end.
