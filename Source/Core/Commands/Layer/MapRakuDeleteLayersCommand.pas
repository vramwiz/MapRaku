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

uses System.Math, System.Generics.Collections, System.Generics.Defaults;

constructor TMapRakuDeleteLayersCommand.Create(
  ADocument: TVectArtDocument; const Indices,
  BeforeSelection: TArray<Integer>);
var I,J: Integer; Candidates: TList<Integer>; RouteId: string; HasRemaining: Boolean;
begin
  inherited Create;
  FDocument := ADocument;
  Candidates:=TList<Integer>.Create;
  try
    Candidates.AddRange(Indices);
    for I:=0 to High(Indices) do
      if (Indices[I]>=0) and (Indices[I]<ADocument.LayerCount) and
         (ADocument[Indices[I]] is TVectArtPathLayer) and
         (TVectArtPathLayer(ADocument[Indices[I]]).MapElement='route') then begin
        RouteId:=TVectArtPathLayer(ADocument[Indices[I]]).RouteId;
        if RouteId='' then RouteId:=ADocument[Indices[I]].PersistentId;
        // 複数区間の一部を削除しても、残る区間の開始・終了点は保持してエラーとして示す。
        HasRemaining:=False;
        for J:=0 to ADocument.LayerCount-1 do
          if (ADocument[J] is TVectArtPathLayer) and
             (TVectArtPathLayer(ADocument[J]).MapElement='route') and
             (J<>Indices[I]) and not Candidates.Contains(J) then begin
            if TVectArtPathLayer(ADocument[J]).RouteId<>'' then
              HasRemaining:=TVectArtPathLayer(ADocument[J]).RouteId=RouteId
            else
              HasRemaining:=ADocument[J].PersistentId=RouteId;
            if HasRemaining then Break;
          end;
        if not HasRemaining then
          for J:=0 to ADocument.LayerCount-1 do
            if (ADocument[J] is TMapRakuGroupLayer) and
               (TMapRakuGroupLayer(ADocument[J]).RoutePathId=RouteId) then
              Candidates.Add(J);
      end;
    Candidates.Sort(TComparer<Integer>.Default);
    for I:=Candidates.Count-1 downto 1 do
      if Candidates[I]=Candidates[I-1] then Candidates.Delete(I);
    FIndices:=Candidates.ToArray;
  finally Candidates.Free; end;
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
