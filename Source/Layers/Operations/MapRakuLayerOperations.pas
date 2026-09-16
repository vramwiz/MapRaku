// レイヤー操作バーから実行する追加・複製・複数削除・複数積層移動を提供する。
unit MapRakuLayerOperations;

interface

uses
  System.Types, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState;

type
  TVectArtLayerAction = (vlaAdd, vlaDuplicate, vlaDelete,
    vlaMoveForward, vlaMoveBackward, vlaMoveToFront, vlaMoveToBack,
    vlaRotateLeft90, vlaRotateRight90);

  TVectArtLayerOperations = class
  private
    FDocument   : TVectArtDocument;    // 操作対象。所有しない。
    FEditHistory: TVectArtEditHistory; // 操作のUndo／Redo記録先。
    FEditorState: TVectArtEditorState; // グループ内の選択と作成既定を参照する。
    procedure AddRectangle;
    function CanMove(Delta: Integer): Boolean;
    procedure DeleteSelectedLayers;
    procedure MoveSelectedLayers(Delta: Integer; ToEdge: Boolean = False);
    procedure RotateSelectedLayers(Degrees: Single);
    function NextRectangleName: string;
    function SelectedLayersEditable: Boolean;
  public
    // 現在の階層・選択・ロック状態で操作可能かを返す。
    function CanExecute(Action: TVectArtLayerAction): Boolean;
    // 操作可能な場合だけ文書へ反映し、変更を編集履歴へ記録する。
    procedure Execute(Action: TVectArtLayerAction);
    property Document: TVectArtDocument read FDocument write FDocument;
    property EditHistory: TVectArtEditHistory read FEditHistory write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState write FEditorState;
  end;

implementation

uses
  System.Math, System.SysUtils, System.Generics.Collections, Vcl.Graphics,
  MapRakuEditCommands, MapRakuDeleteLayersCommand,
  MapRakuGroupCommands, MapRakuGroupTransformCommands,
  MapRakuLayerDuplication,
  MapRakuLayerGeometry, MapRakuLayerStructureCommands,
  MapRakuTextCommands;

const
  DEFAULT_RECTANGLE_WIDTH = 320;
  DEFAULT_RECTANGLE_HEIGHT= 240;
  DEFAULT_RECTANGLE_COLOR = TColor($00E2904A);

procedure TVectArtLayerOperations.AddRectangle;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtRectangleData;
  Index: Integer;
  Left: Single;
  Top: Single;
begin
  Left := -DEFAULT_RECTANGLE_WIDTH / 2;
  Top := -DEFAULT_RECTANGLE_HEIGHT / 2;
  Data.Bounds := TRectF.Create(Left, Top, Left + DEFAULT_RECTANGLE_WIDTH,
    Top + DEFAULT_RECTANGLE_HEIGHT);
  if FEditorState <> nil then
    Data.FillColor := FEditorState.RectangleFillColor
  else
    Data.FillColor := DEFAULT_RECTANGLE_COLOR;
  Data.Locked := False;
  Data.Name := NextRectangleName;
  if FEditorState <> nil then
    Data.Opacity := FEditorState.RectangleOpacity
  else
    Data.Opacity := 1.0;
  Data.RotationDegrees := 0.0;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertRectangle(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtInsertRectangleCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

function TVectArtLayerOperations.CanExecute(
  Action: TVectArtLayerAction): Boolean;
begin
  Result := FDocument <> nil;
  if not Result or (Action = vlaAdd) then
    Exit;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
    not CanEditOpenGroupChild(FEditorState) then Exit(False);
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
    FEditorState.OpenGroup.Locked then Exit(False);
  case Action of
    vlaDuplicate:
      if CanEditOpenGroupChild(FEditorState) then
        Result := True
      else
        Result := CanDuplicateSelectedGroups(FDocument) or
          CanDuplicateSelectedLayers(FDocument);
    vlaDelete:
      if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
        Result := CanEditOpenGroupChild(FEditorState)
      else Result := SelectedLayersEditable;
    vlaMoveForward, vlaMoveToFront:
      if CanEditOpenGroupChild(FEditorState) then
        Result := CanMoveOpenGroupChild(FEditorState, 1)
      else
        Result := SelectedLayersEditable and CanMove(1);
    vlaMoveBackward, vlaMoveToBack:
      if CanEditOpenGroupChild(FEditorState) then
        Result := CanMoveOpenGroupChild(FEditorState, -1)
      else
        Result := SelectedLayersEditable and CanMove(-1);
    vlaRotateLeft90, vlaRotateRight90:
      if CanEditOpenGroupChild(FEditorState) then
        Result := True
      else
        Result := SelectedLayersEditable;
  end;
end;

function TVectArtLayerOperations.CanMove(Delta: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) then
    begin
      if (Delta > 0) and (I < FDocument.LayerCount - 1) and
        not FDocument.IsLayerSelected(I + 1) then
        Exit(True);
      if (Delta < 0) and (I > 1) and
        not FDocument.IsLayerSelected(I - 1) then
        Exit(True);
    end;
end;

procedure TVectArtLayerOperations.DeleteSelectedLayers;
var
  BeforeSelection: TArray<Integer>;
  Command: TMapRakuDeleteLayersCommand;
  SelectedIndices: TArray<Integer>;
begin
  SelectedIndices := FDocument.GetSelectedLayerIndices;
  if Length(SelectedIndices) = 0 then Exit;
  BeforeSelection := Copy(SelectedIndices);
  TArray.Sort<Integer>(SelectedIndices);
  Command := TMapRakuDeleteLayersCommand.Create(FDocument,
    SelectedIndices, BeforeSelection);
  Command.Execute;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure TVectArtLayerOperations.Execute(Action: TVectArtLayerAction);
begin
  if not CanExecute(Action) then
    Exit;
  case Action of
    vlaAdd: AddRectangle;
    vlaDuplicate:
      if CanEditOpenGroupChild(FEditorState) then
        DuplicateOpenGroupChild(FDocument, FEditHistory, FEditorState)
      else if CanDuplicateSelectedGroups(FDocument) then
        DuplicateSelectedGroups(FDocument, FEditHistory)
      else
        DuplicateSelectedLayers(FDocument, FEditHistory);
    vlaDelete:
      if CanEditOpenGroupChild(FEditorState) then
        DeleteOpenGroupChild(FDocument, FEditHistory, FEditorState)
      else
        DeleteSelectedLayers;
    vlaMoveForward:
      if CanEditOpenGroupChild(FEditorState) then
        MoveOpenGroupChild(FDocument, FEditHistory, FEditorState, 1)
      else
        MoveSelectedLayers(1);
    vlaMoveBackward:
      if CanEditOpenGroupChild(FEditorState) then
        MoveOpenGroupChild(FDocument, FEditHistory, FEditorState, -1)
      else
        MoveSelectedLayers(-1);
    vlaMoveToFront:
      if CanEditOpenGroupChild(FEditorState) then
        MoveOpenGroupChild(FDocument, FEditHistory, FEditorState,
          FEditorState.OpenGroup.ChildCount)
      else
        MoveSelectedLayers(1, True);
    vlaMoveToBack:
      if CanEditOpenGroupChild(FEditorState) then
        MoveOpenGroupChild(FDocument, FEditHistory, FEditorState,
          -FEditorState.OpenGroup.ChildCount)
      else
        MoveSelectedLayers(-1, True);
    vlaRotateLeft90: RotateSelectedLayers(-90);
    vlaRotateRight90: RotateSelectedLayers(90);
  end;
end;

procedure TVectArtLayerOperations.MoveSelectedLayers(Delta: Integer;
  ToEdge: Boolean);
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Command: TVectArtCompoundCommand;
  I: Integer;
begin
  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  repeat
    if Delta > 0 then
    begin
      for I := FDocument.LayerCount - 2 downto 1 do
        if FDocument.IsLayerSelected(I) and
          not FDocument.IsLayerSelected(I + 1) then
        begin
          BeforeSelection := FDocument.GetSelectedLayerIndices;
          FDocument.MoveLayer(I, I + 1);
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TVectArtMoveLayerCommand.Create(FDocument, I, I + 1,
              BeforeSelection, AfterSelection));
        end;
    end
    else
    begin
      for I := 2 to FDocument.LayerCount - 1 do
        if FDocument.IsLayerSelected(I) and
          not FDocument.IsLayerSelected(I - 1) then
        begin
          BeforeSelection := FDocument.GetSelectedLayerIndices;
          FDocument.MoveLayer(I, I - 1);
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TVectArtMoveLayerCommand.Create(FDocument, I, I - 1,
              BeforeSelection, AfterSelection));
        end;
    end;
  until not ToEdge or not CanMove(Delta);
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure TVectArtLayerOperations.RotateSelectedLayers(Degrees: Single);
var
  Bounds: TRectF;
  CandidateBounds: TRectF;
  Center: TPointF;
  Command: TVectArtCompoundCommand;
  I: Integer;
  Indices: TArray<Integer>;
  Layers: TArray<TVectArtLayer>;
  RotateCommand: TMapRakuRotateLayerCommand;
begin
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
    Layers := FEditorState.GetOpenGroupChildren
  else
  begin
    Indices := FDocument.GetSelectedLayerIndices;
    SetLength(Layers, Length(Indices));
    for I := 0 to High(Indices) do Layers[I] := FDocument[Indices[I]];
  end;
  if Length(Layers) = 0 then Exit;
  if not TryGetMapRakuLayerBounds(Layers[0], Bounds) then Exit;
  for I := 1 to High(Layers) do
    if TryGetMapRakuLayerBounds(Layers[I], CandidateBounds) then
      Bounds := TRectF.Union(Bounds, CandidateBounds);
  Center := Bounds.CenterPoint;
  Command := TVectArtCompoundCommand.Create;
  for I := 0 to High(Layers) do
  begin
    RotateCommand := TMapRakuRotateLayerCommand.Create(FDocument,
      Layers[I], Center, Degrees);
    RotateCommand.Execute;
    Command.Add(RotateCommand);
  end;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
end;

function TVectArtLayerOperations.NextRectangleName: string;
var
  Candidate: string;
  Found: Boolean;
  I: Integer;
  Number: Integer;
begin
  Number := 1;
  repeat
    Candidate := 'Rectangle ' + Number.ToString;
    Found := False;
    for I := 1 to FDocument.LayerCount - 1 do
      if SameText(FDocument[I].Name, Candidate) then
      begin
        Found := True;
        Break;
      end;
    Inc(Number);
  until not Found;
  Result := Candidate;
end;

function TVectArtLayerOperations.SelectedLayersEditable: Boolean;
var
  I: Integer;
begin
  Result := FDocument.SelectionCount > 0;
  if not Result then
    Exit;
  for I := 0 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and
      ((I = 0) or FDocument[I].Locked) then
      Exit(False);
end;

end.
