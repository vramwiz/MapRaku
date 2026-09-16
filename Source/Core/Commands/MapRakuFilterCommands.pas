// フィルタースタックの構造と値を、所有権を保ちながらUndo／Redoする。
unit MapRakuFilterCommands;

interface

uses
  MapRakuDocument, MapRakuEditCommands, MapRakuFilters;

type
  // 新規フィルターを挿入し、Undo中だけコマンド側で所有する。
  TMapRakuAddFilterCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFilter: TMapRakuFilter;
    FInLayer: Boolean; // FFilterの所有者がFLayerならTrue。
    FIndex: Integer;
    FLayer: TVectArtLayer;
  public
    constructor Create(Document: TVectArtDocument; Layer: TVectArtLayer;
      Index: Integer; Filter: TMapRakuFilter);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 既存フィルターを取り外し、削除状態の間だけコマンド側で所有する。
  TMapRakuRemoveFilterCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFilter: TMapRakuFilter;
    FInLayer: Boolean; // FFilterの所有者がFLayerならTrue。
    FIndex: Integer;
    FLayer: TVectArtLayer;
  public
    constructor Create(Document: TVectArtDocument; Layer: TVectArtLayer;
      Index: Integer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 同一レイヤー内の順序だけを変更し、フィルター本体は移動しない。
  TMapRakuMoveFilterCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFromIndex: Integer;
    FLayer: TVectArtLayer;
    FToIndex: Integer;
  public
    constructor Create(Document: TVectArtDocument; Layer: TVectArtLayer;
      FromIndex, ToIndex: Integer);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 既存フィルターの有効状態を履歴化する。
  TMapRakuSetFilterEnabledCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFilter: TMapRakuFilter;
    FNewValue: Boolean;
    FOldValue: Boolean;
    procedure Apply(Value: Boolean);
  public
    constructor Create(Document: TVectArtDocument;
      Filter: TMapRakuFilter; OldValue, NewValue: Boolean);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 同じフィルターへスナップショットを適用し、ドラッグ全体を1履歴にする。
  TMapRakuSetFilterParametersCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFilter: TMapRakuFilter;
    FNewValue: TMapRakuFilter;
    FOldValue: TMapRakuFilter;
    procedure Apply(Source: TMapRakuFilter);
  public
    constructor Create(Document: TVectArtDocument;
      Filter, OldValue, NewValue: TMapRakuFilter);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  System.SysUtils;

{ TMapRakuAddFilterCommand }

constructor TMapRakuAddFilterCommand.Create(Document: TVectArtDocument;
  Layer: TVectArtLayer; Index: Integer; Filter: TMapRakuFilter);
begin
  inherited Create;
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  if Filter = nil then
    raise EArgumentNilException.Create('Filter');
  FDocument := Document;
  FLayer := Layer;
  FIndex := Index;
  FFilter := Filter;
  FInLayer := False;
end;

destructor TMapRakuAddFilterCommand.Destroy;
begin
  if not FInLayer then
    FFilter.Free;
  inherited Destroy;
end;

procedure TMapRakuAddFilterCommand.Execute;
begin
  if FInLayer then
    Exit;
  FLayer.InsertFilter(FIndex, FFilter);
  FInLayer := True;
  if FDocument <> nil then
    FDocument.Changed;
end;

procedure TMapRakuAddFilterCommand.Undo;
begin
  if not FInLayer then
    Exit;
  FFilter := FLayer.ExtractFilter(FIndex);
  FInLayer := False;
  if FDocument <> nil then
    FDocument.Changed;
end;

{ TMapRakuRemoveFilterCommand }

constructor TMapRakuRemoveFilterCommand.Create(
  Document: TVectArtDocument; Layer: TVectArtLayer; Index: Integer);
begin
  inherited Create;
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  if (Index < 0) or (Index >= Layer.FilterCount) then
    raise EArgumentOutOfRangeException.Create('Index');
  FDocument := Document;
  FLayer := Layer;
  FIndex := Index;
  FFilter := nil;
  FInLayer := True;
end;

destructor TMapRakuRemoveFilterCommand.Destroy;
begin
  if not FInLayer then
    FFilter.Free;
  inherited Destroy;
end;

procedure TMapRakuRemoveFilterCommand.Execute;
begin
  if not FInLayer then
    Exit;
  FFilter := FLayer.ExtractFilter(FIndex);
  FInLayer := False;
  if FDocument <> nil then
    FDocument.Changed;
end;

procedure TMapRakuRemoveFilterCommand.Undo;
begin
  if FInLayer then
    Exit;
  FLayer.InsertFilter(FIndex, FFilter);
  FInLayer := True;
  if FDocument <> nil then
    FDocument.Changed;
end;

{ TMapRakuMoveFilterCommand }

constructor TMapRakuMoveFilterCommand.Create(Document: TVectArtDocument;
  Layer: TVectArtLayer; FromIndex, ToIndex: Integer);
begin
  inherited Create;
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  FDocument := Document;
  FLayer := Layer;
  FFromIndex := FromIndex;
  FToIndex := ToIndex;
end;

procedure TMapRakuMoveFilterCommand.Execute;
begin
  FLayer.MoveFilter(FFromIndex, FToIndex);
  if FDocument <> nil then
    FDocument.Changed;
end;

procedure TMapRakuMoveFilterCommand.Undo;
begin
  FLayer.MoveFilter(FToIndex, FFromIndex);
  if FDocument <> nil then
    FDocument.Changed;
end;

{ TMapRakuSetFilterEnabledCommand }

procedure TMapRakuSetFilterEnabledCommand.Apply(Value: Boolean);
begin
  if FFilter.Enabled = Value then
    Exit;
  FFilter.Enabled := Value;
  if FDocument <> nil then
    FDocument.Changed;
end;

constructor TMapRakuSetFilterEnabledCommand.Create(
  Document: TVectArtDocument; Filter: TMapRakuFilter; OldValue,
  NewValue: Boolean);
begin
  inherited Create;
  if Filter = nil then
    raise EArgumentNilException.Create('Filter');
  FDocument := Document;
  FFilter := Filter;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TMapRakuSetFilterEnabledCommand.Execute;
begin
  Apply(FNewValue);
end;

procedure TMapRakuSetFilterEnabledCommand.Undo;
begin
  Apply(FOldValue);
end;

{ TMapRakuSetFilterParametersCommand }

procedure TMapRakuSetFilterParametersCommand.Apply(
  Source: TMapRakuFilter);
begin
  AssignMapRakuFilter(FFilter, Source);
  if FDocument <> nil then
    FDocument.Changed;
end;

constructor TMapRakuSetFilterParametersCommand.Create(
  Document: TVectArtDocument; Filter, OldValue,
  NewValue: TMapRakuFilter);
begin
  inherited Create;
  if (Filter = nil) or (OldValue = nil) or (NewValue = nil) then
    raise EArgumentNilException.Create('Filter');
  if (Filter.Kind <> OldValue.Kind) or (Filter.Kind <> NewValue.Kind) then
    raise EArgumentException.Create('Filter kinds do not match');
  FDocument := Document;
  FFilter := Filter;
  FOldValue := OldValue.Clone;
  FNewValue := NewValue.Clone;
end;

destructor TMapRakuSetFilterParametersCommand.Destroy;
begin
  FNewValue.Free;
  FOldValue.Free;
  inherited Destroy;
end;

procedure TMapRakuSetFilterParametersCommand.Execute;
begin
  Apply(FNewValue);
end;

procedure TMapRakuSetFilterParametersCommand.Undo;
begin
  Apply(FOldValue);
end;

end.
