// 編集ツールなど、複数の編集UIが共有する一時状態を管理する。
unit MapRakuEditorState;

interface

uses
  System.Classes, System.Generics.Collections, Vcl.Graphics,
  MapRakuDocument, MapRakuFilters, MapRakuPaintStyles;

type
  TVectArtEditorTool = (vetSelect, vetRectangleLine, vetRectangle,
    vetRoundedRectangleLine, vetRoundedRectangle,
    vetEllipseLine, vetEllipse, vetArc, vetArcShape, vetLine, vetFreehand,
    vetPath, vetShape, vetText, vetTextPath);

  TVectArtEditorState = class
  private
    FPendingSymbolLabel: string;
    FPendingSymbol: Integer;
    FActiveMapPreset: Integer; // 地図パネルで最後に選んだ配置ツール。-1は通常ツール。
    FMapElement: string;
    FMapPlacementActive: Boolean;
    FMapPlacementColor: TColor;
    FMapPlacementKind: string;
    FMapPlacementOverride: Boolean;
    FCreationPaintStyle: TMapRakuPaintStyle;
    FCurrentTool: TVectArtEditorTool;
    FLineCap: TVectArtLineCap;
    FLineMifStrokeStyle: TVectArtMifStrokeStyle;
    FLineStrokeWidth: Single;
    FStrokeWidthMode: TMapRakuStrokeWidthMode;
    FNextVertexKind: TMapRakuVertexKind;
    FOnChanged: TNotifyEvent;
    FOpenGroup: TMapRakuGroupLayer;
    FOpenGroupChild: TVectArtLayer;
    FOpenGroupChildren: TList<TVectArtLayer>;
    FOpenGroupPath: TList<TMapRakuGroupLayer>;
    FRectangleOpacity: Single;
    FSelectedGradientLayer: TVectArtLayer;
    FSelectedGradientStopId: Integer;
    FSelectedFilter: TMapRakuFilter;
    FSelectedFilterLayer: TVectArtLayer;
    function GetCreationColor: TColor;
    procedure SetCreationColor(const Value: TColor);
    procedure SetCreationPaintStyle(const Value: TMapRakuPaintStyle);
    procedure SetCurrentTool(const Value: TVectArtEditorTool);
    procedure SetActiveMapPreset(const Value: Integer);
    procedure SetLineCap(const Value: TVectArtLineCap);
    procedure SetLineMifStrokeStyle(const Value: TVectArtMifStrokeStyle);
    procedure SetLineStrokeWidth(const Value: Single);
    procedure SetStrokeWidthMode(const Value: TMapRakuStrokeWidthMode);
    procedure SetNextVertexKind(const Value: TMapRakuVertexKind);
    procedure SetOpenGroup(const Value: TMapRakuGroupLayer);
    procedure SetOpenGroupChild(const Value: TVectArtLayer);
    procedure SetRectangleOpacity(const Value: Single);
  public
    constructor Create;
    destructor Destroy; override;
    // ツールを選択し、選択済みの組み合わせツールでは線／図形または頂点種別を切り替える。
    procedure ActivateTool(const Value: TVectArtEditorTool);
    // 道路・川は専用プリセットを優先し、同種の個別色を1件だけ選択中なら引き継ぐ。
    function MapPlacementColor(Document: TVectArtDocument;
      out FromSelectedObject: Boolean): TColor;
    procedure BeginMapPlacement(Document: TVectArtDocument);
    procedure EndMapPlacement;
    procedure SetMapPlacementColor(const Value: TColor);
    function GetOpenGroupChildren: TArray<TVectArtLayer>;
    function IsGroupInOpenPath(Group: TMapRakuGroupLayer): Boolean;
    function IsOpenGroupChildSelected(Layer: TVectArtLayer): Boolean;
    // 現在のグループ直下にある子グループへ編集対象を移す。
    procedure OpenChildGroup(Value: TMapRakuGroupLayer);
    // Document内に実在する任意のグループまでの編集パスを復元する。
    procedure OpenGroupInDocument(Document: TVectArtDocument;
      Value: TMapRakuGroupLayer);
    // 最上位を1とする現在のグループ編集深度を返す。
    function OpenGroupDepth: Integer;
    // 親へ1階層戻り、最上位ではグループ編集を閉じる。
    procedure OpenParentGroup;
    // レイヤー一覧で開状態を示す最上位グループを返す。
    function RootOpenGroup: TMapRakuGroupLayer;
    procedure SetOpenGroupChildren(const Layers: TArray<TVectArtLayer>);
    // Selects one filter for direct manipulation on the editing canvas.
    procedure SelectFilter(Layer: TVectArtLayer;
      Filter: TMapRakuFilter);
    // Selects a stable gradient stop so the shared color picker edits that stop.
    procedure SelectGradientStop(Layer: TVectArtLayer; StopId: Integer);
    procedure ToggleOpenGroupChild(Layer: TVectArtLayer);
    // Document変更後に編集パスと直下選択を実在する階層まで復旧する。
    procedure ValidateOpenGroupPath(Document: TVectArtDocument);
    procedure ValidateSelectedGradientStop(Document: TVectArtDocument);
    procedure ValidateSelectedFilter(Document: TVectArtDocument);
    function OpenGroupChildCount: Integer;
    property PendingSymbolLabel: string read FPendingSymbolLabel write FPendingSymbolLabel;
    property PendingSymbol: Integer read FPendingSymbol write FPendingSymbol;
    property ActiveMapPreset: Integer read FActiveMapPreset
      write SetActiveMapPreset;
    property MapElement: string read FMapElement write FMapElement;
    property CurrentTool: TVectArtEditorTool read FCurrentTool
      write SetCurrentTool;
    // 新規配置へ値として複製する、各描画モード共通の作成スタイル。
    property CreationPaintStyle: TMapRakuPaintStyle
      read FCreationPaintStyle write SetCreationPaintStyle;
    property CreationColor: TColor read GetCreationColor
      write SetCreationColor;
    property LineCap: TVectArtLineCap read FLineCap write SetLineCap;
    // 既存の作成・プレビュー処理から共通作成色を参照する互換プロパティ。
    property LineStrokeColor: TColor read GetCreationColor
      write SetCreationColor;
    property LineMifStrokeStyle: TVectArtMifStrokeStyle read FLineMifStrokeStyle
      write SetLineMifStrokeStyle;
    property LineStrokeWidth: Single read FLineStrokeWidth
      write SetLineStrokeWidth;
    property StrokeWidthMode: TMapRakuStrokeWidthMode
      read FStrokeWidthMode write SetStrokeWidthMode;
    property NextVertexKind: TMapRakuVertexKind read FNextVertexKind
      write SetNextVertexKind;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    // 解除せず内部編集対象として開いているグループ。所有権はDocumentが保持する。
    property OpenGroup: TMapRakuGroupLayer read FOpenGroup
      write SetOpenGroup;
    property OpenGroupChild: TVectArtLayer read FOpenGroupChild
      write SetOpenGroupChild;
    property RectangleFillColor: TColor read GetCreationColor
      write SetCreationColor;
    property RectangleOpacity: Single read FRectangleOpacity
      write SetRectangleOpacity;
    property SelectedGradientLayer: TVectArtLayer
      read FSelectedGradientLayer;
    property SelectedGradientStopId: Integer read FSelectedGradientStopId;
    property SelectedFilter: TMapRakuFilter read FSelectedFilter;
    property SelectedFilterLayer: TVectArtLayer read FSelectedFilterLayer;
  end;

implementation

uses
  System.Math;

const
  DEFAULT_RECTANGLE_COLOR = TColor($00E2904A);

function FindOpenGroupPath(Layer: TVectArtLayer;
  Target: TMapRakuGroupLayer;
  Path: TList<TMapRakuGroupLayer>): Boolean;
var
  Group: TMapRakuGroupLayer;
  I: Integer;
begin
  Result := False;
  if not (Layer is TMapRakuGroupLayer) then
    Exit;
  Group := TMapRakuGroupLayer(Layer);
  Path.Add(Group);
  if Group = Target then
    Exit(True);
  for I := 0 to Group.ChildCount - 1 do
    if FindOpenGroupPath(Group[I], Target, Path) then
      Exit(True);
  Path.Delete(Path.Count - 1);
end;

function LayerContainsFilter(Layer: TVectArtLayer;
  Filter: TMapRakuFilter): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (Layer = nil) or (Filter = nil) then
    Exit;
  for I := 0 to Layer.FilterCount - 1 do
    if Layer.Filters[I] = Filter then
      Exit(True);
end;

function DocumentContainsLayer(Document: TVectArtDocument;
  Target: TVectArtLayer): Boolean;

  function ContainsInTree(Layer: TVectArtLayer): Boolean;
  var
    Group: TMapRakuGroupLayer;
    I: Integer;
  begin
    Result := Layer = Target;
    if Result or not (Layer is TMapRakuGroupLayer) then
      Exit;
    Group := TMapRakuGroupLayer(Layer);
    for I := 0 to Group.ChildCount - 1 do
      if ContainsInTree(Group[I]) then
        Exit(True);
  end;

var
  I: Integer;
begin
  Result := False;
  if (Document = nil) or (Target = nil) then
    Exit;
  for I := 1 to Document.LayerCount - 1 do
    if ContainsInTree(Document[I]) then
      Exit(True);
end;

constructor TVectArtEditorState.Create;
begin
  inherited Create;
  FPendingSymbol := -1;
  FActiveMapPreset := -1;
  FOpenGroupChildren := TList<TVectArtLayer>.Create;
  FOpenGroupPath := TList<TMapRakuGroupLayer>.Create;
  FCurrentTool := vetSelect;
  FLineCap := vlcSquare;
  FCreationPaintStyle := TMapRakuPaintStyle.Solid(
    DEFAULT_RECTANGLE_COLOR);
  FLineMifStrokeStyle := vssSolid;
  FLineStrokeWidth := 1.0;
  FStrokeWidthMode := slwmUniform;
  FNextVertexKind := slvkSharp;
  FRectangleOpacity := 1.0;
  FSelectedGradientStopId := SCREEN_LAYOUT_GRADIENT_STOP_NONE;
end;

function TVectArtEditorState.GetCreationColor: TColor;
begin
  Result := FCreationPaintStyle.SolidColor;
end;

function TVectArtEditorState.MapPlacementColor(Document: TVectArtDocument;
  out FromSelectedObject: Boolean): TColor;
var
  Indices: TArray<Integer>;
  Layers: TArray<TVectArtLayer>;
  Path: TVectArtPathLayer;
begin
  FromSelectedObject := False;
  Result := CreationColor;
  if (Document = nil) or (Document.CanvasLayer = nil) then Exit;
  if FMapElement = 'road' then
    Result := Document.CanvasLayer.RoadPresetColor
  else if FMapElement = 'river' then
    Result := Document.CanvasLayer.RiverPresetColor
  else Exit;
  if FMapPlacementActive and (FMapPlacementKind = FMapElement) then
  begin
    Result := FMapPlacementColor;
    FromSelectedObject := FMapPlacementOverride;
    Exit;
  end;
  if FCurrentTool = vetSelect then Exit;
  if (FOpenGroup <> nil) and (OpenGroupChildCount > 0) then
    Layers := GetOpenGroupChildren
  else begin
    Indices := Document.GetSelectedLayerIndices;
    if Length(Indices) <> 1 then Exit;
    Layers := [Document[Indices[0]]];
  end;
  if (Length(Layers) <> 1) or not (Layers[0] is TVectArtPathLayer) then Exit;
  Path := TVectArtPathLayer(Layers[0]);
  if (Path.MapElement <> FMapElement) or not Path.MapColorOverride then Exit;
  Result := Path.StrokeColor;
  FromSelectedObject := True;
end;

procedure TVectArtEditorState.BeginMapPlacement(Document: TVectArtDocument);
begin
  // 連続配置では最初に引き継いだ色を、選択解除後の次の1本にも使う。
  if FMapPlacementActive and (FMapPlacementKind = FMapElement) then Exit;
  FMapPlacementActive := False;
  FMapPlacementKind := FMapElement;
  FMapPlacementColor := MapPlacementColor(Document,FMapPlacementOverride);
  FMapPlacementActive := True;
end;

procedure TVectArtEditorState.EndMapPlacement;
begin
  FMapPlacementActive := False;
end;

procedure TVectArtEditorState.SetMapPlacementColor(const Value: TColor);
begin
  FMapPlacementColor := Value;
  FMapPlacementOverride := False;
  FMapPlacementKind := FMapElement;
  FMapPlacementActive := True;
  CreationColor := Value;
end;

destructor TVectArtEditorState.Destroy;
begin
  FOpenGroupPath.Free;
  FOpenGroupChildren.Free;
  inherited Destroy;
end;

function TVectArtEditorState.GetOpenGroupChildren: TArray<TVectArtLayer>;
begin
  Result := FOpenGroupChildren.ToArray;
end;

function TVectArtEditorState.IsOpenGroupChildSelected(
  Layer: TVectArtLayer): Boolean;
begin
  Result := (Layer <> nil) and (FOpenGroupChildren.IndexOf(Layer) >= 0);
end;

function TVectArtEditorState.OpenGroupChildCount: Integer;
begin
  Result := FOpenGroupChildren.Count;
end;

procedure TVectArtEditorState.OpenChildGroup(
  Value: TMapRakuGroupLayer);
var
  I: Integer;
begin
  if (Value = nil) or (FOpenGroup = nil) or (FOpenGroup = Value) then
    Exit;
  for I := 0 to FOpenGroup.ChildCount - 1 do
    if FOpenGroup[I] = Value then
    begin
      FOpenGroupPath.Add(Value);
      FOpenGroup := Value;
      FOpenGroupChild := nil;
      FOpenGroupChildren.Clear;
      if Assigned(FOnChanged) then
        FOnChanged(Self);
      Exit;
    end;
end;

function TVectArtEditorState.IsGroupInOpenPath(
  Group: TMapRakuGroupLayer): Boolean;
begin
  Result := (Group <> nil) and (FOpenGroupPath.IndexOf(Group) >= 0);
end;

procedure TVectArtEditorState.OpenGroupInDocument(
  Document: TVectArtDocument; Value: TMapRakuGroupLayer);
var
  Found: Boolean;
  I: Integer;
  Path: TList<TMapRakuGroupLayer>;
begin
  if Value = nil then
  begin
    OpenGroup := nil;
    Exit;
  end;
  Path := TList<TMapRakuGroupLayer>.Create;
  try
    Found := False;
    if Document <> nil then
      for I := 1 to Document.LayerCount - 1 do
        if FindOpenGroupPath(Document[I], Value, Path) then
        begin
          Found := True;
          Break;
        end;
    if not Found then
      Exit;
    FOpenGroupPath.Clear;
    FOpenGroupPath.AddRange(Path);
    FOpenGroup := Value;
    FOpenGroupChild := nil;
    FOpenGroupChildren.Clear;
    if Assigned(FOnChanged) then
      FOnChanged(Self);
  finally
    Path.Free;
  end;
end;

function TVectArtEditorState.OpenGroupDepth: Integer;
begin
  Result := FOpenGroupPath.Count;
end;

procedure TVectArtEditorState.OpenParentGroup;
begin
  if FOpenGroupPath.Count <= 1 then
  begin
    OpenGroup := nil;
    Exit;
  end;
  FOpenGroupPath.Delete(FOpenGroupPath.Count - 1);
  FOpenGroup := FOpenGroupPath.Last;
  FOpenGroupChild := nil;
  FOpenGroupChildren.Clear;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TVectArtEditorState.RootOpenGroup: TMapRakuGroupLayer;
begin
  if FOpenGroupPath.Count > 0 then
    Result := FOpenGroupPath.First
  else
    Result := nil;
end;

procedure TVectArtEditorState.ValidateOpenGroupPath(
  Document: TVectArtDocument);
var
  Changed: Boolean;
  ChildIndex: Integer;
  Found: Boolean;
  I: Integer;
  Parent: TMapRakuGroupLayer;
  ValidCount: Integer;
begin
  Changed := False;
  ValidCount := 0;
  if (Document <> nil) and (FOpenGroupPath.Count > 0) then
    for I := 1 to Document.LayerCount - 1 do
      if Document[I] = FOpenGroupPath[0] then
      begin
        ValidCount := 1;
        Break;
      end;
  while (ValidCount > 0) and (ValidCount < FOpenGroupPath.Count) do
  begin
    Parent := FOpenGroupPath[ValidCount - 1];
    Found := False;
    for ChildIndex := 0 to Parent.ChildCount - 1 do
      if Parent[ChildIndex] = FOpenGroupPath[ValidCount] then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Break;
    Inc(ValidCount);
  end;
  while FOpenGroupPath.Count > ValidCount do
  begin
    FOpenGroupPath.Delete(FOpenGroupPath.Count - 1);
    Changed := True;
  end;
  if FOpenGroupPath.Count > 0 then
    FOpenGroup := FOpenGroupPath.Last
  else
    FOpenGroup := nil;
  for I := FOpenGroupChildren.Count - 1 downto 0 do
  begin
    Found := False;
    if FOpenGroup <> nil then
      for ChildIndex := 0 to FOpenGroup.ChildCount - 1 do
        if FOpenGroup[ChildIndex] = FOpenGroupChildren[I] then
        begin
          Found := True;
          Break;
        end;
    if not Found then
    begin
      FOpenGroupChildren.Delete(I);
      Changed := True;
    end;
  end;
  if FOpenGroupChildren.Count > 0 then
    FOpenGroupChild := FOpenGroupChildren.Last
  else if FOpenGroupChild <> nil then
  begin
    FOpenGroupChild := nil;
    Changed := True;
  end;
  if Changed and Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.ValidateSelectedFilter(
  Document: TVectArtDocument);
begin
  if (FSelectedFilter = nil) and (FSelectedFilterLayer = nil) then
    Exit;
  if not DocumentContainsLayer(Document, FSelectedFilterLayer) or
    not LayerContainsFilter(FSelectedFilterLayer, FSelectedFilter) or
    not (((FOpenGroup <> nil) and (OpenGroupChildCount = 1) and
      IsOpenGroupChildSelected(FSelectedFilterLayer)) or
      ((FOpenGroup = nil) and (Document <> nil) and
      (Document.SelectionCount = 1) and (Document.SelectedIndex > 0) and
      (Document[Document.SelectedIndex] = FSelectedFilterLayer))) then
    SelectFilter(nil, nil);
end;

procedure TVectArtEditorState.SetOpenGroupChildren(
  const Layers: TArray<TVectArtLayer>);
var
  Layer: TVectArtLayer;
begin
  FOpenGroupChildren.Clear;
  for Layer in Layers do
    if (Layer <> nil) and (FOpenGroupChildren.IndexOf(Layer) < 0) then
      FOpenGroupChildren.Add(Layer);
  if FOpenGroupChildren.Count > 0 then
    FOpenGroupChild := FOpenGroupChildren.Last
  else
    FOpenGroupChild := nil;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SelectFilter(Layer: TVectArtLayer;
  Filter: TMapRakuFilter);
begin
  if not LayerContainsFilter(Layer, Filter) then
  begin
    Layer := nil;
    Filter := nil;
  end;
  if (FSelectedFilterLayer = Layer) and (FSelectedFilter = Filter) then
    Exit;
  FSelectedFilterLayer := Layer;
  FSelectedFilter := Filter;
  if Filter <> nil then
  begin
    FSelectedGradientLayer := nil;
    FSelectedGradientStopId := SCREEN_LAYOUT_GRADIENT_STOP_NONE;
  end;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.ValidateSelectedGradientStop(
  Document: TVectArtDocument);
var
  Color: TColor;
begin
  if FSelectedGradientLayer = nil then
    Exit;
  if not DocumentContainsLayer(Document, FSelectedGradientLayer) or
    not (((FOpenGroup <> nil) and (OpenGroupChildCount = 1) and
      IsOpenGroupChildSelected(FSelectedGradientLayer)) or
      ((FOpenGroup = nil) and (Document.SelectionCount = 1) and
      (Document.SelectedIndex > 0) and (Document[Document.SelectedIndex] = FSelectedGradientLayer))) or
    (FSelectedGradientLayer.PaintStyle.Kind <> slpkGradient) then
  begin
    SelectGradientStop(nil, SCREEN_LAYOUT_GRADIENT_STOP_NONE);
    Exit;
  end;
  if not FSelectedGradientLayer.PaintStyle.GetGradientStopColor(
    FSelectedGradientStopId, Color) then
    SelectGradientStop(FSelectedGradientLayer,
      SCREEN_LAYOUT_GRADIENT_START_STOP_ID);
end;

procedure TVectArtEditorState.SelectGradientStop(Layer: TVectArtLayer;
  StopId: Integer);
var
  Color: TColor;
begin
  if (Layer = nil) or (Layer.PaintStyle.Kind <> slpkGradient) or
    not Layer.PaintStyle.GetGradientStopColor(StopId, Color) then
  begin
    Layer := nil;
    StopId := SCREEN_LAYOUT_GRADIENT_STOP_NONE;
  end;
  if (FSelectedGradientLayer = Layer) and
    (FSelectedGradientStopId = StopId) then
    Exit;
  FSelectedGradientLayer := Layer;
  FSelectedGradientStopId := StopId;
  if Layer <> nil then
  begin
    FSelectedFilter := nil;
    FSelectedFilterLayer := nil;
  end;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.ToggleOpenGroupChild(Layer: TVectArtLayer);
var
  Index: Integer;
begin
  if Layer = nil then
    Exit;
  Index := FOpenGroupChildren.IndexOf(Layer);
  if Index >= 0 then
    FOpenGroupChildren.Delete(Index)
  else
    FOpenGroupChildren.Add(Layer);
  if FOpenGroupChildren.Count > 0 then
    FOpenGroupChild := FOpenGroupChildren.Last
  else
    FOpenGroupChild := nil;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.ActivateTool(const Value: TVectArtEditorTool);
begin
  if (Value in [vetRectangleLine, vetRectangle]) and
    (FCurrentTool in [vetRectangleLine, vetRectangle]) then
  begin
    if FCurrentTool = vetRectangleLine then
      CurrentTool := vetRectangle
    else
      CurrentTool := vetRectangleLine;
  end
  else if (Value in [vetRoundedRectangleLine, vetRoundedRectangle]) and
    (FCurrentTool in [vetRoundedRectangleLine, vetRoundedRectangle]) then
  begin
    if FCurrentTool = vetRoundedRectangleLine then
      CurrentTool := vetRoundedRectangle
    else
      CurrentTool := vetRoundedRectangleLine;
  end
  else if (Value in [vetEllipseLine, vetEllipse]) and
    (FCurrentTool in [vetEllipseLine, vetEllipse]) then
  begin
    if FCurrentTool = vetEllipseLine then
      CurrentTool := vetEllipse
    else
      CurrentTool := vetEllipseLine;
  end
  else if (Value in [vetArc, vetArcShape]) and
    (FCurrentTool in [vetArc, vetArcShape]) then
  begin
    if FCurrentTool = vetArc then
      CurrentTool := vetArcShape
    else
      CurrentTool := vetArc;
  end
  else if (Value in [vetPath, vetShape]) and (FCurrentTool = Value) then
  begin
    if FNextVertexKind = slvkSharp then
      NextVertexKind := slvkBezier
    else
      NextVertexKind := slvkSharp;
  end
  else if (Value = vetText) and
    (FCurrentTool in [vetText, vetTextPath]) then
  begin
    if FCurrentTool = vetText then
      CurrentTool := vetTextPath
    else
      CurrentTool := vetText;
  end
  else
    CurrentTool := Value;
end;

procedure TVectArtEditorState.SetNextVertexKind(
  const Value: TMapRakuVertexKind);
begin
  if FNextVertexKind = Value then
    Exit;
  FNextVertexKind := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetOpenGroup(
  const Value: TMapRakuGroupLayer);
begin
  if FOpenGroup = Value then
    Exit;
  FOpenGroupPath.Clear;
  if Value <> nil then
    FOpenGroupPath.Add(Value);
  FOpenGroup := Value;
  FOpenGroupChild := nil;
  FOpenGroupChildren.Clear;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetOpenGroupChild(const Value: TVectArtLayer);
begin
  if (FOpenGroupChild = Value) and
    (((Value = nil) and (FOpenGroupChildren.Count = 0)) or
     ((Value <> nil) and (FOpenGroupChildren.Count = 1))) then
    Exit;
  FOpenGroupChildren.Clear;
  if Value <> nil then
    FOpenGroupChildren.Add(Value);
  FOpenGroupChild := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineCap(const Value: TVectArtLineCap);
begin
  if FLineCap = Value then
    Exit;
  FLineCap := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetCreationColor(const Value: TColor);
var
  NewStyle: TMapRakuPaintStyle;
begin
  NewStyle := FCreationPaintStyle;
  NewStyle.Kind := slpkSolid;
  NewStyle.SolidColor := Value;
  SetCreationPaintStyle(NewStyle);
end;

procedure TVectArtEditorState.SetCreationPaintStyle(
  const Value: TMapRakuPaintStyle);
begin
  if FCreationPaintStyle.SameAs(Value) then
    Exit;
  FCreationPaintStyle := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineMifStrokeStyle(
  const Value: TVectArtMifStrokeStyle);
begin
  if FLineMifStrokeStyle = Value then
    Exit;
  FLineMifStrokeStyle := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineStrokeWidth(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := Max(Value, 0.1);
  if SameValue(FLineStrokeWidth, NewValue) then
    Exit;
  FLineStrokeWidth := NewValue;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetStrokeWidthMode(
  const Value: TMapRakuStrokeWidthMode);
begin
  if FStrokeWidthMode = Value then
    Exit;
  FStrokeWidthMode := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetCurrentTool(const Value: TVectArtEditorTool);
begin
  if FCurrentTool = Value then
    Exit;
  FCurrentTool := Value;
  if Value = vetSelect then
  begin
    FActiveMapPreset := -1;
    FMapPlacementActive := False;
  end;
  if Value <> vetSelect then
  begin
    FSelectedFilter := nil;
    FSelectedFilterLayer := nil;
    FSelectedGradientLayer := nil;
    FSelectedGradientStopId := SCREEN_LAYOUT_GRADIENT_STOP_NONE;
  end;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetActiveMapPreset(const Value: Integer);
begin
  if FActiveMapPreset = Value then
    Exit;
  FActiveMapPreset := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetRectangleOpacity(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := EnsureRange(Value, 0.0, 1.0);
  if SameValue(FRectangleOpacity, NewValue) then
    Exit;
  FRectangleOpacity := NewValue;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

end.
