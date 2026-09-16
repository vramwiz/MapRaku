// 地図経路の挿入とグループからの取り出しを、オブジェクトの寿命を保って履歴化する。
unit MapRakuMapCommands;
interface
uses MapRakuDocument, MapRakuEditHistory, MapRakuEditorState;
procedure InsertMapPath(Document: TVectArtDocument; History: TVectArtEditHistory;
  const Data: TVectArtPathData);
procedure DetachMapChild(Document: TVectArtDocument; History: TVectArtEditHistory;
  State: TVectArtEditorState);
function IsMapTree(Layer: TVectArtLayer): Boolean;
implementation
uses System.SysUtils, MapRakuEditCommands;
type
  TInsertMap = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FGroup: TMapRakuGroupLayer;
    FIndex: Integer;
    FApplied: Boolean;
  public
    constructor Create(Document: TVectArtDocument; const Data: TVectArtPathData);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;
  TDetachMap = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FParent: TMapRakuGroupLayer;
    FChild: TVectArtLayer;
    FChildIndex, FIndex: Integer;
  public
    constructor Create(Document: TVectArtDocument; Parent: TMapRakuGroupLayer; Child: TVectArtLayer);
    procedure Execute; override;
    procedure Undo; override;
  end;
  TAppendMap = class(TVectArtEditCommand)
  private
    FDocument:TVectArtDocument; FParent:TMapRakuGroupLayer;
    FPath:TVectArtPathLayer; FIndex, FParentIndex:Integer; FApplied:Boolean;
  public
    constructor Create(Document:TVectArtDocument; Parent:TMapRakuGroupLayer;
      ParentIndex:Integer; const Data:TVectArtPathData);
    destructor Destroy; override; procedure Execute; override; procedure Undo; override;
  end;

function NewMapPath(const Data:TVectArtPathData):TVectArtPathLayer;
begin
  Result:=TVectArtPathLayer.Create(Data.Name,Data.Vertices,Data.Closed);
  Result.MapElement:=Data.MapElement; Result.StrokeWidth:=Data.StrokeWidth;
  Result.LineCap:=Data.LineCap; Result.StrokeColor:=Data.StrokeColor;
  Result.PaintStyle:=Data.PaintStyle; Result.Opacity:=Data.Opacity;
end;
function IsMapTree(Layer: TVectArtLayer): Boolean;
var I: Integer;
begin
  if Layer is TVectArtPathLayer then Exit(TVectArtPathLayer(Layer).MapElement <> '');
  Result := (Layer is TMapRakuGroupLayer) and (TMapRakuGroupLayer(Layer).ChildCount > 0);
  if Result then for I := 0 to TMapRakuGroupLayer(Layer).ChildCount - 1 do
    if not IsMapTree(TMapRakuGroupLayer(Layer)[I]) then Exit(False);
end;
constructor TInsertMap.Create(Document: TVectArtDocument; const Data: TVectArtPathData);
begin
  inherited Create;
  FDocument := Document; FIndex := Document.LayerCount;
  FGroup := TMapRakuGroupLayer.Create(Data.MapElement + ' — 層');
  FGroup.MapSurface := True;
  FGroup.AddChild(NewMapPath(Data));
end;
destructor TInsertMap.Destroy;
begin
  if not FApplied then FGroup.Free;
  inherited;
end;
procedure TInsertMap.Execute;
begin
  FDocument.InsertLayer(FIndex, FGroup); FApplied := True;
  FDocument.SetSelectedLayers([FIndex]);
end;
procedure TInsertMap.Undo;
begin
  FDocument.ExtractLayer(FIndex); FApplied := False;
end;
procedure InsertMapPath(Document: TVectArtDocument; History: TVectArtEditHistory;
  const Data: TVectArtPathData);
var C: TVectArtEditCommand; G:TMapRakuGroupLayer; I, Selected:Integer; SameKind:Boolean;
begin
  G:=nil; Selected:=-1;
  if (Document<>nil) and (Document.SelectionCount=1) then begin
    Selected:=Document.SelectedIndex;
    if (Selected>0) and (Document[Selected] is TMapRakuGroupLayer) then begin
      G:=TMapRakuGroupLayer(Document[Selected]); SameKind:=G.MapSurface and (G.ChildCount>0);
      if SameKind then for I:=0 to G.ChildCount-1 do
        SameKind:=SameKind and (G[I] is TVectArtPathLayer) and
          (TVectArtPathLayer(G[I]).MapElement=Data.MapElement);
      if not SameKind then G:=nil;
    end;
  end;
  if G<>nil then C:=TAppendMap.Create(Document,G,Selected,Data)
  else C:=TInsertMap.Create(Document,Data);
  C.Execute;
  if History <> nil then History.AddApplied(C) else C.Free;
end;

constructor TAppendMap.Create(Document:TVectArtDocument; Parent:TMapRakuGroupLayer;
  ParentIndex:Integer; const Data:TVectArtPathData);
begin inherited Create; FDocument:=Document; FParent:=Parent; FParentIndex:=ParentIndex;
  FIndex:=Parent.ChildCount; FPath:=NewMapPath(Data); end;
destructor TAppendMap.Destroy;
begin if not FApplied then FPath.Free; inherited; end;
procedure TAppendMap.Execute;
begin FParent.InsertChild(FIndex,FPath); FApplied:=True;
  FDocument.SetSelectedLayers([FParentIndex]); FDocument.Changed; end;
procedure TAppendMap.Undo;
begin FParent.ExtractChild(FIndex); FApplied:=False;
  FDocument.SetSelectedLayers([FParentIndex]); FDocument.Changed; end;
constructor TDetachMap.Create(Document: TVectArtDocument; Parent: TMapRakuGroupLayer; Child: TVectArtLayer);
var I: Integer;
begin
  inherited Create;
  FDocument := Document; FParent := Parent; FChild := Child;
  FChildIndex := -1;
  for I := 0 to Parent.ChildCount - 1 do if Parent[I] = Child then FChildIndex := I;
  if FChildIndex < 0 then raise EArgumentException.Create('グループ内の要素を選択してください');
  FIndex := Document.LayerCount;
end;
procedure TDetachMap.Execute;
begin
  FDocument.BeginUpdate;
  try
    FParent.ExtractChild(FChildIndex);
    FDocument.InsertLayer(FIndex, FChild);
    FDocument.SetSelectedLayers([FIndex]);
  finally FDocument.EndUpdate; end;
end;
procedure TDetachMap.Undo;
begin
  FDocument.BeginUpdate;
  try
    FDocument.ExtractLayer(FIndex);
    FParent.InsertChild(FChildIndex, FChild);
    FDocument.Changed;
  finally FDocument.EndUpdate; end;
end;
procedure DetachMapChild(Document: TVectArtDocument; History: TVectArtEditHistory;
  State: TVectArtEditorState);
var C: TDetachMap;
begin
  if (State.OpenGroup = nil) or (State.OpenGroupChild = nil) or
    State.OpenGroupChild.Locked then Exit;
  C := TDetachMap.Create(Document, State.OpenGroup, State.OpenGroupChild);
  State.OpenGroup := nil;
  C.Execute;
  if History <> nil then History.AddApplied(C) else C.Free;
end;
end.
