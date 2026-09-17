// 地図経路の挿入とグループからの取り出しを、オブジェクトの寿命を保って履歴化する。
unit MapRakuMapCommands;
interface
uses Vcl.Graphics, MapRakuDocument, MapRakuEditHistory, MapRakuEditorState;
procedure InsertMapPath(Document: TVectArtDocument; History: TVectArtEditHistory;
  const Data: TVectArtPathData; ConnectStart: Boolean = False;
  ConnectEnd: Boolean = False; EndpointTolerance: Single = 0);
procedure InsertMapLevelBoundary(Document:TVectArtDocument; History:TVectArtEditHistory);
procedure SetMapCrossingRelation(Document:TVectArtDocument;
  History:TVectArtEditHistory; const ObjectAId,ObjectBId:string;
  Kind:TMapRakuCrossingKind; const UpperObjectId:string;
  RangeMargin:Single=-1);
procedure SetMapStairStepCount(Document:TVectArtDocument;
  History:TVectArtEditHistory; Layer:TVectArtPathLayer; StepCount:Integer);
procedure DetachMapChild(Document: TVectArtDocument; History: TVectArtEditHistory;
  State: TVectArtEditorState);
// 選択中の道路・川の色を配置プリセットへ登録し、必要なら同種の既存経路へ一括適用する。
procedure ApplyMapColorPreset(Document: TVectArtDocument;
  History: TVectArtEditHistory; Source: TVectArtPathLayer;
  ApplyExisting: Boolean);
procedure SetMapPlacementPreset(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Kind: string; Color: TColor;
  ApplyExisting: Boolean = False);
procedure SetMapRailPalette(Document: TVectArtDocument;
  History: TVectArtEditHistory; JrPrimary, JrSecondary,
  RailPrimary, RailSecondary: TColor);
function IsMapTree(Layer: TVectArtLayer): Boolean;
implementation
uses System.SysUtils, System.Math, System.Types,
  MapRakuEditCommands, MapRakuPathEditSession, MapRakuPathSnap;
type
  TInsertMap = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
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
  TInsertBoundary=class(TVectArtEditCommand)
  private FDocument:TVectArtDocument; FLayer:TMapRakuLevelBoundaryLayer;
    FIndex:Integer; FApplied:Boolean;
  public constructor Create(Document:TVectArtDocument; Index:Integer);
    destructor Destroy; override; procedure Execute; override; procedure Undo; override;
  end;
  TSetCrossingRelation=class(TVectArtEditCommand)
  private FDocument:TVectArtDocument; FA,FB,FUpper:string;
    FKind:TMapRakuCrossingKind; FMargin:Single; FHadOld:Boolean; FOldKind:TMapRakuCrossingKind;
    FOldUpper:string; FOldMargin:Single;
  public constructor Create(Document:TVectArtDocument; const A,B:string;
    Kind:TMapRakuCrossingKind; const Upper:string; RangeMargin:Single);
    procedure Execute; override; procedure Undo; override;
  end;
  TSetStairSteps=class(TVectArtEditCommand)
  private FDocument:TVectArtDocument; FLayer:TVectArtPathLayer; FOld,FNew:Integer;
  public constructor Create(Document:TVectArtDocument; Layer:TVectArtPathLayer;
    StepCount:Integer); procedure Execute; override; procedure Undo; override;
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
  TMapColorSnapshot = record
    Path: TVectArtPathLayer;
    Color: TColor;
    OverrideColor: Boolean;
  end;
  TMapColorPresetCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FKind: string;
    FOldPreset, FNewPreset: TColor;
    FItems: TArray<TMapColorSnapshot>;
    procedure Collect(Layer: TVectArtLayer);
  public
    constructor Create(Document: TVectArtDocument; const Kind: string;
      Color: TColor; ApplyExisting: Boolean);
    procedure Execute; override;
    procedure Undo; override;
  end;
  TMapRailPaletteCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FOld, FNew: array[0..3] of TColor;
    procedure Apply(const Colors: array of TColor);
  public
    constructor Create(Document: TVectArtDocument; JrPrimary, JrSecondary,
      RailPrimary, RailSecondary: TColor);
    procedure Execute; override;
    procedure Undo; override;
  end;

constructor TMapRailPaletteCommand.Create(Document: TVectArtDocument;
  JrPrimary, JrSecondary, RailPrimary, RailSecondary: TColor);
begin
  inherited Create;
  FDocument := Document;
  FOld[0] := Document.CanvasLayer.JrPrimaryColor;
  FOld[1] := Document.CanvasLayer.JrSecondaryColor;
  FOld[2] := Document.CanvasLayer.RailPrimaryColor;
  FOld[3] := Document.CanvasLayer.RailSecondaryColor;
  FNew[0] := JrPrimary; FNew[1] := JrSecondary;
  FNew[2] := RailPrimary; FNew[3] := RailSecondary;
end;

procedure TMapRailPaletteCommand.Apply(const Colors: array of TColor);
begin
  FDocument.CanvasLayer.JrPrimaryColor := Colors[0];
  FDocument.CanvasLayer.JrSecondaryColor := Colors[1];
  FDocument.CanvasLayer.RailPrimaryColor := Colors[2];
  FDocument.CanvasLayer.RailSecondaryColor := Colors[3];
  FDocument.Changed;
end;

procedure TMapRailPaletteCommand.Execute;
begin Apply(FNew); end;

procedure TMapRailPaletteCommand.Undo;
begin Apply(FOld); end;

procedure SetMapRailPalette(Document: TVectArtDocument;
  History: TVectArtEditHistory; JrPrimary, JrSecondary,
  RailPrimary, RailSecondary: TColor);
var Command: TMapRailPaletteCommand;
begin
  if Document = nil then Exit;
  if (Document.CanvasLayer.JrPrimaryColor = JrPrimary) and
    (Document.CanvasLayer.JrSecondaryColor = JrSecondary) and
    (Document.CanvasLayer.RailPrimaryColor = RailPrimary) and
    (Document.CanvasLayer.RailSecondaryColor = RailSecondary) then Exit;
  Command := TMapRailPaletteCommand.Create(Document,JrPrimary,JrSecondary,
    RailPrimary,RailSecondary);
  Command.Execute;
  if History <> nil then History.AddApplied(Command) else Command.Free;
end;

constructor TMapColorPresetCommand.Create(Document: TVectArtDocument;
  const Kind: string; Color: TColor; ApplyExisting: Boolean);
var I: Integer;
begin
  inherited Create;
  FDocument:=Document;
  FKind:=Kind;
  FNewPreset:=Color;
  if FKind='road' then FOldPreset:=Document.CanvasLayer.RoadPresetColor
  else FOldPreset:=Document.CanvasLayer.RiverPresetColor;
  if ApplyExisting then
    for I:=1 to Document.LayerCount-1 do Collect(Document[I]);
end;

procedure TMapColorPresetCommand.Collect(Layer: TVectArtLayer);
var I,N: Integer;
begin
  if Layer.Locked then Exit;
  if Layer is TMapRakuGroupLayer then begin
    for I:=0 to TMapRakuGroupLayer(Layer).ChildCount-1 do
      Collect(TMapRakuGroupLayer(Layer)[I]);
    Exit;
  end;
  if not (Layer is TVectArtPathLayer) or
    (TVectArtPathLayer(Layer).MapElement<>FKind) then Exit;
  N:=Length(FItems);
  SetLength(FItems,N+1);
  FItems[N].Path:=TVectArtPathLayer(Layer);
  FItems[N].Color:=FItems[N].Path.StrokeColor;
  FItems[N].OverrideColor:=FItems[N].Path.MapColorOverride;
end;

procedure TMapColorPresetCommand.Execute;
var Item: TMapColorSnapshot;
begin
  FDocument.BeginUpdate;
  try
    if FKind='road' then FDocument.CanvasLayer.RoadPresetColor:=FNewPreset
    else FDocument.CanvasLayer.RiverPresetColor:=FNewPreset;
    for Item in FItems do begin
      Item.Path.StrokeColor:=FNewPreset;
      Item.Path.MapColorOverride:=False;
    end;
    FDocument.Changed;
  finally FDocument.EndUpdate; end;
end;

procedure TMapColorPresetCommand.Undo;
var Item: TMapColorSnapshot;
begin
  FDocument.BeginUpdate;
  try
    if FKind='road' then FDocument.CanvasLayer.RoadPresetColor:=FOldPreset
    else FDocument.CanvasLayer.RiverPresetColor:=FOldPreset;
    for Item in FItems do begin
      Item.Path.StrokeColor:=Item.Color;
      Item.Path.MapColorOverride:=Item.OverrideColor;
    end;
    FDocument.Changed;
  finally FDocument.EndUpdate; end;
end;

procedure ApplyMapColorPreset(Document: TVectArtDocument;
  History: TVectArtEditHistory; Source: TVectArtPathLayer;
  ApplyExisting: Boolean);
var Command: TMapColorPresetCommand;
begin
  if (Document=nil) or (Source=nil) or Source.Locked or
    not ((Source.MapElement='road') or (Source.MapElement='river')) then Exit;
  if not ApplyExisting and
    (((Source.MapElement='road') and
      (Document.CanvasLayer.RoadPresetColor=Source.StrokeColor)) or
     ((Source.MapElement='river') and
      (Document.CanvasLayer.RiverPresetColor=Source.StrokeColor))) then Exit;
  Command:=TMapColorPresetCommand.Create(Document,Source.MapElement,
    Source.StrokeColor,ApplyExisting);
  Command.Execute;
  if History<>nil then History.AddApplied(Command) else Command.Free;
end;

procedure SetMapPlacementPreset(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Kind: string; Color: TColor;
  ApplyExisting: Boolean);
var Command: TMapColorPresetCommand;
begin
  if (Document=nil) or not ((Kind='road') or (Kind='river')) then Exit;
  if not ApplyExisting and
    (((Kind='road') and (Document.CanvasLayer.RoadPresetColor=Color)) or
     ((Kind='river') and (Document.CanvasLayer.RiverPresetColor=Color))) then Exit;
  Command:=TMapColorPresetCommand.Create(Document,Kind,Color,ApplyExisting);
  Command.Execute;
  if History<>nil then History.AddApplied(Command) else Command.Free;
end;

function NewMapPath(const Data:TVectArtPathData):TVectArtPathLayer;
begin
  Result:=TVectArtPathLayer.Create(Data.Name,Data.Vertices,Data.Closed);
  Result.MapElement:=Data.MapElement; Result.StrokeWidth:=Data.StrokeWidth;
  Result.MapColorOverride:=Data.MapColorOverride;
  Result.MapStepCount:=Data.MapStepCount;
  Result.LineCap:=Data.LineCap; Result.StrokeColor:=Data.StrokeColor;
  Result.PaintStyle:=Data.PaintStyle; Result.Opacity:=Data.Opacity;
end;

function NewPedestrianBridge(const Data:TVectArtPathData):TMapRakuGroupLayer;
var D:TVectArtPathData; V:TArray<TMapRakuVertex>; A,B,Dir:TPointF; Len:Single;
begin
  Result:=TMapRakuGroupLayer.Create('歩道橋');
  V:=Data.Vertices;
  if Length(V)<2 then begin Result.AddChild(NewMapPath(Data)); Exit; end;
  A:=V[0].Position; B:=V[High(V)].Position;
  Dir:=TPointF.Create(B.X-A.X,B.Y-A.Y); Len:=Hypot(Dir.X,Dir.Y);
  if Len<=0 then begin Result.AddChild(NewMapPath(Data)); Exit; end;
  Dir:=TPointF.Create(Dir.X/Len,Dir.Y/Len);
  D:=Data; D.MapElement:='stairs-up'; D.MapStepCount:=6; D.Name:='階段（始点側）';
  D.Vertices:=Copy(Data.Vertices); SetLength(D.Vertices,2);
  D.Vertices[0].Position:=TPointF.Create(A.X-Dir.X*32,A.Y-Dir.Y*32);
  D.Vertices[1].Position:=A; D.StrokeWidth:=Max(Data.StrokeWidth,18);
  Result.AddChild(NewMapPath(D));
  D:=Data; D.MapElement:='pedestrian-bridge'; D.MapStepCount:=0; D.Name:='橋本体';
  D.Vertices:=Copy(Data.Vertices);
  Result.AddChild(NewMapPath(D));
  D:=Data; D.MapElement:='stairs-down'; D.MapStepCount:=6; D.Name:='階段（終点側）';
  D.Vertices:=Copy(Data.Vertices); SetLength(D.Vertices,2); D.Vertices[0].Position:=B;
  D.Vertices[1].Position:=TPointF.Create(B.X+Dir.X*32,B.Y+Dir.Y*32);
  D.StrokeWidth:=Max(Data.StrokeWidth,18); Result.AddChild(NewMapPath(D));
end;

function NewMapLayer(const Data:TVectArtPathData):TVectArtLayer;
begin
  if Data.MapElement='pedestrian-bridge' then Result:=NewPedestrianBridge(Data)
  else Result:=NewMapPath(Data);
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
  FLayer := NewMapLayer(Data);
  if FLayer is TVectArtPathLayer then
    if (TVectArtPathLayer(FLayer).MapElement='jr') or
      (TVectArtPathLayer(FLayer).MapElement='rail') then
      if Document.CanvasLayer.BackgroundColor=clBlack then
        TVectArtPathLayer(FLayer).StrokeColor:=clWhite
      else
        TVectArtPathLayer(FLayer).StrokeColor:=clBlack;
end;
destructor TInsertMap.Destroy;
begin
  if not FApplied then FLayer.Free;
  inherited;
end;
procedure TInsertMap.Execute;
begin
  FDocument.InsertLayer(FIndex, FLayer); FApplied := True;
  FDocument.SetSelectedLayers([FIndex]);
end;
procedure TInsertMap.Undo;
begin
  FDocument.ExtractLayer(FIndex); FApplied := False;
end;
procedure InsertMapPath(Document: TVectArtDocument; History: TVectArtEditHistory;
  const Data: TVectArtPathData; ConnectStart, ConnectEnd: Boolean;
  EndpointTolerance: Single);
var C: TInsertMap; Changes: TMapRakuPathEditSession;
  Combined: TVectArtCompoundCommand; Path: TVectArtPathLayer;
  Snap: TMapRakuEndpointSnap; P,T: TPointF; I, Endpoint: Integer;
  Connections: array[0..1] of TMapRakuEndpointSnap;
begin
  C:=TInsertMap.Create(Document,Data);
  C.Execute;
  if not (ConnectStart or ConnectEnd) or not (C.FLayer is TVectArtPathLayer) then begin
    if History<>nil then History.AddApplied(C) else C.Free;
    Exit;
  end;
  Combined:=TVectArtCompoundCommand.Create; Combined.Add(C);
  Changes:=TMapRakuPathEditSession.Create(Document);
  try
    if C.FLayer is TVectArtPathLayer then begin
      Path:=TVectArtPathLayer(C.FLayer); Changes.Track(Path);
      Connections[0]:=Default(TMapRakuEndpointSnap);
      Connections[1]:=Default(TMapRakuEndpointSnap);
      for I:=0 to 1 do begin
        if ((I=0) and not ConnectStart) or ((I=1) and not ConnectEnd) then Continue;
        if I=0 then Endpoint:=0 else Endpoint:=High(Path.Vertices);
        if Path.TryEndpoint(Endpoint,P,T) and
          NearestMapEndpoint(Document,P,EndpointTolerance,False,Path.MapElement,Snap,Path) then begin
          if Snap.CanAdjust then Changes.Track(Snap.Path);
          if Path.ConnectEndpoint(Endpoint,Snap.Path,Snap.Index,False,False) then
            Connections[I]:=Snap;
        end;
      end;
      // 両端の位置を確定してから接線をそろえる。後の端点吸着で直線の
      // 角度が変わり、先に調整した相手の曲線がずれることを防ぐ。
      for I:=0 to 1 do if Connections[I].Path<>nil then begin
        if I=0 then Endpoint:=0 else Endpoint:=High(Path.Vertices);
        Snap:=Connections[I];
        Path.ConnectEndpoint(Endpoint,Snap.Path,Snap.Index,Snap.CanAdjust);
      end;
    end;
    Combined.Add(Changes.CaptureCommand);
    Document.Changed;
    if History<>nil then History.AddApplied(Combined) else Combined.Free;
  finally Changes.Free; end;
end;

procedure InsertMapLevelBoundary(Document:TVectArtDocument; History:TVectArtEditHistory);
var Index:Integer; C:TInsertBoundary;
begin
  if Document=nil then Exit;
  Index:=Document.LayerCount;
  if Document.SelectionCount>0 then Index:=Document.SelectedIndex+1;
  C:=TInsertBoundary.Create(Document,Index); C.Execute;
  if History<>nil then History.AddApplied(C) else C.Free;
end;

procedure SetMapCrossingRelation(Document:TVectArtDocument;
  History:TVectArtEditHistory; const ObjectAId,ObjectBId:string;
  Kind:TMapRakuCrossingKind; const UpperObjectId:string;
  RangeMargin:Single);
var C:TSetCrossingRelation;
begin
  if Document=nil then Exit;
  C:=TSetCrossingRelation.Create(Document,ObjectAId,ObjectBId,Kind,
    UpperObjectId,RangeMargin);
  C.Execute;
  if History<>nil then History.AddApplied(C) else C.Free;
end;

procedure SetMapStairStepCount(Document:TVectArtDocument;
  History:TVectArtEditHistory; Layer:TVectArtPathLayer; StepCount:Integer);
var C:TSetStairSteps;
begin
  if (Document=nil) or (Layer=nil) then Exit;
  C:=TSetStairSteps.Create(Document,Layer,StepCount); C.Execute;
  if History<>nil then History.AddApplied(C) else C.Free;
end;

constructor TSetStairSteps.Create(Document:TVectArtDocument;
  Layer:TVectArtPathLayer; StepCount:Integer);
begin inherited Create; FDocument:=Document; FLayer:=Layer;
  FOld:=Layer.MapStepCount; FNew:=EnsureRange(StepCount,0,64); end;
procedure TSetStairSteps.Execute;
begin FLayer.MapStepCount:=FNew; FDocument.Changed; end;
procedure TSetStairSteps.Undo;
begin FLayer.MapStepCount:=FOld; FDocument.Changed; end;

constructor TSetCrossingRelation.Create(Document:TVectArtDocument;
  const A,B:string; Kind:TMapRakuCrossingKind; const Upper:string;
  RangeMargin:Single);
var R:TMapRakuCrossingRelation;
begin
  inherited Create; FDocument:=Document; FA:=A; FB:=B; FKind:=Kind; FUpper:=Upper;
  R:=Document.FindCrossingRelation(A,B); FHadOld:=R<>nil;
  if FHadOld then begin FOldKind:=R.Kind; FOldUpper:=R.UpperObjectId;
    FOldMargin:=R.RangeMargin; end;
  if RangeMargin>=0 then FMargin:=RangeMargin
  else if FHadOld then FMargin:=FOldMargin else FMargin:=12;
end;

procedure TSetCrossingRelation.Execute;
begin FDocument.SetCrossingRelation(FA,FB,FKind,FUpper,FMargin); end;

procedure TSetCrossingRelation.Undo;
begin
  if FHadOld then FDocument.SetCrossingRelation(FA,FB,FOldKind,FOldUpper,FOldMargin)
  else FDocument.RemoveCrossingRelation(FA,FB);
end;

constructor TInsertBoundary.Create(Document:TVectArtDocument; Index:Integer);
begin inherited Create; FDocument:=Document; FIndex:=Index;
  FLayer:=TMapRakuLevelBoundaryLayer.Create; end;
destructor TInsertBoundary.Destroy;
begin if not FApplied then FLayer.Free; inherited; end;
procedure TInsertBoundary.Execute;
begin FDocument.InsertLayer(FIndex,FLayer); FApplied:=True;
  FDocument.SetSelectedLayers([FIndex]); end;
procedure TInsertBoundary.Undo;
begin FDocument.ExtractLayer(FIndex); FApplied:=False; end;

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
