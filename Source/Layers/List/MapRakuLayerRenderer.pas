// レイヤー一覧の表示階層、行配置、スクロールを管理し、各行の描画を専用Painterへ委譲する。
unit MapRakuLayerRenderer;

interface

uses
  System.Generics.Collections, System.Types, Vcl.Direct2D,
  Vcl.Graphics, MapRakuDocument, MapRakuEditorState,
  MapRakuLayerItemPainter;

type
  TMapRakuLayerListEntry = record
    Depth: Integer;                  // 範囲線のX位置に使う表示上の階層深度。
    GroupRangeStart: Integer;        // 展開子の先頭。子を持たない行は0。
    Layer: TVectArtLayer;            // この表示行が参照する非所有Layer。
    Parent: TMapRakuGroupLayer; // 最上位行はnil、子行は直接の親Group。
    SourceIndex: Integer;            // Parent内またはDocument内での積層位置。
  end;

  TVectArtLayerRenderer = class
  private
    FDocument         : TVectArtDocument;                    // 表示行を構築する文書。所有しない。
    FEditorState      : TVectArtEditorState;                 // 階層の展開状態と子選択を参照する。
    FEntries          : TArray<TMapRakuLayerListEntry>; // 画面下側から並ぶ表示行と実レイヤーの対応。
    FLastSelectedIndex: Integer;                             // 選択変更時のスクロール追従に使う前回の表示行。
    FScrollOffset     : Integer;                             // 一覧の下端を基準にしたスクロール量。
    FPPI              : Integer;                             // 行寸法とスクロールに適用するDPI。
    FItemPainter      : TMapRakuLayerItemPainter;       // 1行の描画とサムネイルを所有する。
    function Scale(Value: Integer): Integer;
    procedure SetPPI(const Value: Integer);
    procedure EnsureSelectionVisible(const Bounds: TRect);
    procedure ClampScrollOffset(const Bounds: TRect);
    function DisplayedLayerCount: Integer;
    function DisplayedSelectedIndex: Integer;
    procedure AppendGroupChildren(Group: TMapRakuGroupLayer;
      Depth: Integer; Entries: TList<TMapRakuLayerListEntry>);
    procedure AppendLayerEntry(Layer: TVectArtLayer;
      Parent: TMapRakuGroupLayer; SourceIndex, Depth: Integer;
      Entries: TList<TMapRakuLayerListEntry>);
    procedure DrawGroupRanges(ACanvas: TCanvas; const Bounds: TRect); overload;
    procedure DrawGroupRanges(ACanvas: TDirect2DCanvas; const Bounds: TRect); overload;
    procedure PreserveExpandedGroupPosition( const NewEntries: TArray<TMapRakuLayerListEntry>);
    procedure RebuildEntries;
    procedure SetDocument(const Value: TVectArtDocument);
  public
    // 行描画の委譲先を生成し、スクロールと選択追従の初期状態を設定する。
    constructor Create;
    // 非所有参照を破棄する前に、内部で所有する描画資源を解放する。
    destructor Destroy; override;
    // 表示中の行をGDI Canvasへ下層から上層の順で描画する。
    procedure DrawLayers(ACanvas: TCanvas; const Bounds: TRect); overload;
    // 表示中の行をDirect2D CanvasへGDI経路と同じ配置で描画する。
    procedure DrawLayers(ACanvas: TDirect2DCanvas; const Bounds: TRect); overload;
    // Y座標にある表示行の1基点Indexを返し、行外では-1を返す。
    function LayerIndexAt(const Bounds: TRect; Y: Integer): Integer;
    // 表示行Indexに対応する非所有Layerを返し、範囲外ではnilを返す。
    function LayerAt(Index: Integer): TVectArtLayer;
    // 表示行のグループ深度を返す。
    function LayerDepthAt(Index: Integer): Integer;
    // 表示行の直接の親Groupを返し、最上位行ではnilを返す。
    function LayerParentAt(Index: Integer): TMapRakuGroupLayer;
    // 表示行が属するDocumentまたは親Group内の積層Indexを返す。
    function LayerSourceIndexAt(Index: Integer): Integer;
    // スクロール量を反映した表示行の描画・当たり判定矩形を返す。
    function LayerItemRect(const Bounds: TRect; Index: Integer): TRect;
    // 現在の行数と表示高から有効な最大スクロール量を返す。
    function MaximumScrollOffset(const Bounds: TRect): Integer;
    // 1行と行間を合わせたホイール・ドラッグ用の移動量を返す。
    function ScrollStep: Integer;
    // 負値を0へ丸めてスクロール量を設定する。
    procedure SetScrollOffset(Value: Integer);
    // 各状態操作とグループ開閉で共有する当たり判定矩形を返す。
    function LockButtonRect(const ItemRect: TRect): TRect;
    // グループ開閉アイコンの描画と一致する当たり判定を返す。
    function ExpandButtonRect(const ItemRect: TRect): TRect;
    // 表示切り替えアイコンの描画と一致する当たり判定を返す。
    function VisibilityButtonRect(const ItemRect: TRect): TRect;
    // DocumentとEditorStateは非所有参照。Document交換時はサムネイルキャッシュを破棄する。
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditorState: TVectArtEditorState read FEditorState write FEditorState;
    // 現在の先頭側へのスクロール量。
    property ScrollOffset: Integer read FScrollOffset write SetScrollOffset;
    // 行、サムネイル、状態アイコン、当たり判定へ適用する画面DPI。
    property PPI: Integer read FPPI write SetPPI;
  end;

implementation

uses
  System.Math, Winapi.Windows, MapRakuLayerListStyle;

constructor TVectArtLayerRenderer.Create;
begin
  inherited Create;
  FItemPainter := TMapRakuLayerItemPainter.Create;
  FLastSelectedIndex := -2;
  FPPI := 96;
end;

function TVectArtLayerRenderer.Scale(Value: Integer): Integer;
begin
  Result := MulDiv(Value, FPPI, 96);
end;

procedure TVectArtLayerRenderer.SetPPI(const Value: Integer);
var
  NewPPI: Integer;
  OldPPI: Integer;
begin
  NewPPI := Value;
  if NewPPI <= 0 then
    NewPPI := 96;
  if FPPI = NewPPI then
    Exit;
  OldPPI := FPPI;
  FPPI := NewPPI;
  if OldPPI > 0 then
    FScrollOffset := MulDiv(FScrollOffset, NewPPI, OldPPI);
  FItemPainter.ResetCache;
  FLastSelectedIndex := -2;
end;

destructor TVectArtLayerRenderer.Destroy;
begin
  FItemPainter.Free;
  inherited Destroy;
end;

function TVectArtLayerRenderer.DisplayedLayerCount: Integer;
begin
  Result := Length(FEntries);
end;

function TVectArtLayerRenderer.DisplayedSelectedIndex: Integer;
var
  I: Integer;
begin
  Result := -1;
  if FDocument = nil then
    Exit;
  for I := 0 to High(FEntries) do
    if ((FEntries[I].Parent = nil) and
        FDocument.IsLayerSelected(FEntries[I].SourceIndex)) or
       ((FEditorState <> nil) and
        (FEntries[I].Parent = FEditorState.OpenGroup) and
        FEditorState.IsOpenGroupChildSelected(FEntries[I].Layer)) then
      if ((FEntries[I].Parent = nil) and
          (FDocument.SelectedIndex = FEntries[I].SourceIndex)) or
         ((FEditorState <> nil) and
          (FEditorState.OpenGroupChild = FEntries[I].Layer)) then
        Exit(I + 1);
end;

procedure TVectArtLayerRenderer.AppendGroupChildren(
  Group: TMapRakuGroupLayer; Depth: Integer;
  Entries: TList<TMapRakuLayerListEntry>);
var
  I: Integer;
begin
  for I := 0 to Group.ChildCount - 1 do
    AppendLayerEntry(Group[I], Group, I, Depth, Entries);
end;

procedure TVectArtLayerRenderer.AppendLayerEntry(Layer: TVectArtLayer;
  Parent: TMapRakuGroupLayer; SourceIndex, Depth: Integer;
  Entries: TList<TMapRakuLayerListEntry>);
var
  Entry: TMapRakuLayerListEntry;
  Group: TMapRakuGroupLayer;
begin
  Entry.GroupRangeStart := 0;
  if (Layer is TMapRakuGroupLayer) and (FEditorState <> nil) and
    FEditorState.IsGroupInOpenPath(TMapRakuGroupLayer(Layer)) then
  begin
    Group := TMapRakuGroupLayer(Layer);
    Entry.GroupRangeStart := Entries.Count + 1;
    AppendGroupChildren(Group, Depth + 1, Entries);
  end;
  Entry.Depth := Depth;
  Entry.Layer := Layer;
  Entry.Parent := Parent;
  Entry.SourceIndex := SourceIndex;
  Entries.Add(Entry);
end;

procedure TVectArtLayerRenderer.RebuildEntries;
var
  Entries: TList<TMapRakuLayerListEntry>;
  I: Integer;
  NewEntries: TArray<TMapRakuLayerListEntry>;
begin
  Entries := TList<TMapRakuLayerListEntry>.Create;
  try
    if FDocument <> nil then
      for I := 1 to FDocument.LayerCount - 1 do
        AppendLayerEntry(FDocument[I], nil, I, 0, Entries);
    NewEntries := Entries.ToArray;
    PreserveExpandedGroupPosition(NewEntries);
    FEntries := NewEntries;
  finally
    Entries.Free;
  end;
end;

procedure TVectArtLayerRenderer.PreserveExpandedGroupPosition(
  const NewEntries: TArray<TMapRakuLayerListEntry>);
var
  I: Integer;
  J: Integer;
  OldIndex: Integer;
  NewIndex: Integer;
begin
  if (Length(FEntries) = 0) or (Length(NewEntries) = 0) then
    Exit;
  OldIndex := -1;
  NewIndex := -1;
  // 展開時は新しく開いたグループ、折り畳み時は閉じたグループを基準行にする。
  for J := 0 to High(NewEntries) do
    if NewEntries[J].GroupRangeStart > 0 then
      for I := 0 to High(FEntries) do
        if (FEntries[I].Layer = NewEntries[J].Layer) and
          (FEntries[I].GroupRangeStart = 0) then
        begin
          OldIndex := I;
          NewIndex := J;
          Break;
        end;
  if OldIndex < 0 then
    for I := 0 to High(FEntries) do
      if FEntries[I].GroupRangeStart > 0 then
        for J := 0 to High(NewEntries) do
          if (NewEntries[J].Layer = FEntries[I].Layer) and
            (NewEntries[J].GroupRangeStart = 0) then
          begin
            OldIndex := I;
            NewIndex := J;
            Break;
          end;
  if (OldIndex >= 0) and (NewIndex >= 0) then
  begin
    Inc(FScrollOffset, (NewIndex - OldIndex) *
      Scale(LAYER_ROW_HEIGHT + LAYER_GAP));
    FLastSelectedIndex := -2;
  end;
end;

procedure TVectArtLayerRenderer.DrawGroupRanges(ACanvas: TCanvas;
  const Bounds: TRect);
var
  GroupRect: TRect;
  I: Integer;
  RangeRect: TRect;
  X: Integer;
begin
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := TColor($00806A48);
  for I := 1 to DisplayedLayerCount do
    if FEntries[I - 1].GroupRangeStart > 0 then
    begin
      GroupRect := LayerItemRect(Bounds, I);
      RangeRect := LayerItemRect(Bounds,
        FEntries[I - 1].GroupRangeStart);
      X := Bounds.Left + Scale(3 + FEntries[I - 1].Depth * 3);
      ACanvas.MoveTo(GroupRect.Left, GroupRect.Top);
      ACanvas.LineTo(X, GroupRect.Top);
      ACanvas.LineTo(X, RangeRect.Bottom);
      ACanvas.LineTo(RangeRect.Left, RangeRect.Bottom);
    end;
end;

procedure TVectArtLayerRenderer.DrawGroupRanges(
  ACanvas: TDirect2DCanvas; const Bounds: TRect);
var
  GroupRect: TRect;
  I: Integer;
  RangeRect: TRect;
  X: Integer;
begin
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := TColor($00806A48);
  for I := 1 to DisplayedLayerCount do
    if FEntries[I - 1].GroupRangeStart > 0 then
    begin
      GroupRect := LayerItemRect(Bounds, I);
      RangeRect := LayerItemRect(Bounds,
        FEntries[I - 1].GroupRangeStart);
      X := Bounds.Left + Scale(3 + FEntries[I - 1].Depth * 3);
      ACanvas.MoveTo(GroupRect.Left, GroupRect.Top);
      ACanvas.LineTo(X, GroupRect.Top);
      ACanvas.LineTo(X, RangeRect.Bottom);
      ACanvas.LineTo(RangeRect.Left, RangeRect.Bottom);
    end;
end;

procedure TVectArtLayerRenderer.EnsureSelectionVisible(
  const Bounds: TRect);
var
  ContentBottom: Integer;
  ContentTop: Integer;
  ItemRect: TRect;
  MaximumOffset: Integer;
  SelectedIndex: Integer;
begin
  if DisplayedLayerCount = 0 then
  begin
    FScrollOffset := 0;
    Exit;
  end;
  ContentTop := Bounds.Top + Scale(LAYER_LIST_PADDING);
  ContentBottom := Bounds.Bottom - Scale(LAYER_LIST_PADDING);
  MaximumOffset := MaximumScrollOffset(Bounds);
  FScrollOffset := EnsureRange(FScrollOffset, 0, MaximumOffset);
  SelectedIndex := DisplayedSelectedIndex;
  if SelectedIndex <= 0 then
    Exit;
  ItemRect := LayerItemRect(Bounds, SelectedIndex);
  if ItemRect.Top < ContentTop then
    Inc(FScrollOffset, ContentTop - ItemRect.Top)
  else if ItemRect.Bottom > ContentBottom then
    Dec(FScrollOffset, ItemRect.Bottom - ContentBottom);
  FScrollOffset := EnsureRange(FScrollOffset, 0, MaximumOffset);
end;

procedure TVectArtLayerRenderer.ClampScrollOffset(const Bounds: TRect);
begin
  FScrollOffset := EnsureRange(FScrollOffset, 0,
    MaximumScrollOffset(Bounds));
end;

procedure TVectArtLayerRenderer.SetDocument(const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  FDocument := Value;
  FItemPainter.ResetCache;
  FScrollOffset := 0;
  FLastSelectedIndex := -2;
end;

procedure TVectArtLayerRenderer.DrawLayers(ACanvas: TCanvas;
  const Bounds: TRect);
var
  I: Integer;
  ItemRect: TRect;
  Layer: TVectArtLayer;
  SelectedIndex: Integer;
begin
  RebuildEntries;
  FItemPainter.Configure(FDocument, FEditorState, FPPI);
  ClampScrollOffset(Bounds);
  SelectedIndex := DisplayedSelectedIndex;
  if FLastSelectedIndex <> SelectedIndex then
  begin
    EnsureSelectionVisible(Bounds);
    FLastSelectedIndex := SelectedIndex;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_LIST_BACKGROUND;
  ACanvas.FillRect(Bounds);
  if FDocument = nil then
    Exit;
  for I := 1 to DisplayedLayerCount do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if ItemRect.Top >= Bounds.Bottom then
      Continue;
    if ItemRect.Bottom <= Bounds.Top then
      Break;
    Layer := LayerAt(I);
    if LayerParentAt(I) <> nil then
      FItemPainter.DrawLayerItem(ACanvas, ItemRect, Layer,
        (FEditorState <> nil) and
          (LayerParentAt(I) = FEditorState.OpenGroup) and
          FEditorState.IsOpenGroupChildSelected(Layer),
        (FEditorState <> nil) and
          ((FEditorState.OpenGroupChild = Layer) or
           (FEditorState.OpenGroup = Layer)))
    else
      FItemPainter.DrawLayerItem(ACanvas, ItemRect, Layer,
        FDocument.IsLayerSelected(LayerSourceIndexAt(I)),
        (FDocument.SelectedIndex = LayerSourceIndexAt(I)) or
          ((FEditorState <> nil) and (FEditorState.OpenGroup = Layer)));
  end;
  DrawGroupRanges(ACanvas, Bounds);
end;

procedure TVectArtLayerRenderer.DrawLayers(ACanvas: TDirect2DCanvas;
  const Bounds: TRect);
var
  I: Integer;
  ItemRect: TRect;
  Layer: TVectArtLayer;
  SelectedIndex: Integer;
begin
  RebuildEntries;
  FItemPainter.Configure(FDocument, FEditorState, FPPI);
  ClampScrollOffset(Bounds);
  SelectedIndex := DisplayedSelectedIndex;
  if FLastSelectedIndex <> SelectedIndex then
  begin
    EnsureSelectionVisible(Bounds);
    FLastSelectedIndex := SelectedIndex;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_LIST_BACKGROUND;
  ACanvas.FillRect(Bounds);
  if FDocument = nil then
    Exit;
  for I := 1 to DisplayedLayerCount do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if ItemRect.Top >= Bounds.Bottom then
      Continue;
    if ItemRect.Bottom <= Bounds.Top then
      Break;
    Layer := LayerAt(I);
    if LayerParentAt(I) <> nil then
      FItemPainter.DrawLayerItem(ACanvas, ItemRect, Layer,
        (FEditorState <> nil) and
          (LayerParentAt(I) = FEditorState.OpenGroup) and
          FEditorState.IsOpenGroupChildSelected(Layer),
        (FEditorState <> nil) and
          ((FEditorState.OpenGroupChild = Layer) or
           (FEditorState.OpenGroup = Layer)))
    else
      FItemPainter.DrawLayerItem(ACanvas, ItemRect, Layer,
        FDocument.IsLayerSelected(LayerSourceIndexAt(I)),
        (FDocument.SelectedIndex = LayerSourceIndexAt(I)) or
          ((FEditorState <> nil) and (FEditorState.OpenGroup = Layer)));
  end;
  DrawGroupRanges(ACanvas, Bounds);
end;

function TVectArtLayerRenderer.LayerIndexAt(const Bounds: TRect;
  Y: Integer): Integer;
var
  I: Integer;
  ItemRect: TRect;
begin
  Result := -1;
  RebuildEntries;
  for I := 1 to DisplayedLayerCount do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if (Y >= ItemRect.Top) and (Y < ItemRect.Bottom) then
      Exit(I);
  end;
end;

function TVectArtLayerRenderer.LayerItemRect(const Bounds: TRect;
  Index: Integer): TRect;
var
  ItemBottom: Integer;
begin
  if Index <= 0 then
    Exit(TRect.Empty);
  ItemBottom := Bounds.Bottom - Scale(LAYER_LIST_PADDING) -
    (Index - 1) * Scale(LAYER_ROW_HEIGHT + LAYER_GAP) + FScrollOffset;
  Result := Rect(Bounds.Left + Scale(LAYER_LIST_PADDING),
    ItemBottom - Scale(LAYER_ROW_HEIGHT),
    Bounds.Right - Scale(LAYER_LIST_PADDING), ItemBottom);
end;

function TVectArtLayerRenderer.LayerAt(Index: Integer): TVectArtLayer;
begin
  Result := nil;
  if (Index <= 0) or (Index > DisplayedLayerCount) then
    Exit;
  Result := FEntries[Index - 1].Layer;
end;

function TVectArtLayerRenderer.LayerDepthAt(Index: Integer): Integer;
begin
  Result := 0;
  if (Index > 0) and (Index <= DisplayedLayerCount) then
    Result := FEntries[Index - 1].Depth;
end;

function TVectArtLayerRenderer.LayerParentAt(
  Index: Integer): TMapRakuGroupLayer;
begin
  Result := nil;
  if (Index > 0) and (Index <= DisplayedLayerCount) then
    Result := FEntries[Index - 1].Parent;
end;

function TVectArtLayerRenderer.LayerSourceIndexAt(Index: Integer): Integer;
begin
  Result := -1;
  if (Index > 0) and (Index <= DisplayedLayerCount) then
    Result := FEntries[Index - 1].SourceIndex;
end;

function TVectArtLayerRenderer.MaximumScrollOffset(
  const Bounds: TRect): Integer;
var
  ContentHeight: Integer;
  ItemCount: Integer;
begin
  RebuildEntries;
  ItemCount := DisplayedLayerCount;
  if ItemCount = 0 then
    Exit(0);
  ContentHeight := ItemCount * Scale(LAYER_ROW_HEIGHT) +
    Max(ItemCount - 1, 0) * Scale(LAYER_GAP) +
    2 * Scale(LAYER_LIST_PADDING);
  Result := Max(ContentHeight - Bounds.Height, 0);
end;

function TVectArtLayerRenderer.ScrollStep: Integer;
begin
  Result := Scale(LAYER_ROW_HEIGHT + LAYER_GAP);
end;

procedure TVectArtLayerRenderer.SetScrollOffset(Value: Integer);
begin
  FScrollOffset := Max(Value, 0);
end;

function TVectArtLayerRenderer.LockButtonRect(const ItemRect: TRect): TRect;
begin
  FItemPainter.Configure(FDocument, FEditorState, FPPI);
  Result := FItemPainter.LockButtonRect(ItemRect);
end;

function TVectArtLayerRenderer.ExpandButtonRect(const ItemRect: TRect): TRect;
begin
  FItemPainter.Configure(FDocument, FEditorState, FPPI);
  Result := FItemPainter.ExpandButtonRect(ItemRect);
end;

function TVectArtLayerRenderer.VisibilityButtonRect(const ItemRect: TRect): TRect;
begin
  FItemPainter.Configure(FDocument, FEditorState, FPPI);
  Result := FItemPainter.VisibilityButtonRect(ItemRect);
end;

end.
