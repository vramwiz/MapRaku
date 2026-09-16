// キャンバス上のオブジェクト用ダークメニューを構成し、表示要求をメニューライブラリへ橋渡しする。
// 共通項目を持ち、対象固有の項目と編集コマンドは登録された提供者へ委譲する。
unit MapRakuObjectContextMenu;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.Types,
  Vcl.Controls, Vcl.ExtCtrls, MapRakuDocument, MapRakuEditorState,
  VectArtDarkMenuGroup, VectArtDarkPopupMenu, MapRakuEditHistory;

type
  // 表示直前の選択を固定し、項目の適用判定と実行対象を提供者へ渡す。
  TMapRakuObjectMenuContext = record
    Document: TVectArtDocument;       // トップレベル選択と編集対象を所有するDocument。
    EditorState: TVectArtEditorState; // 開いたグループとその直下選択を保持する状態。
    Layers: TArray<TVectArtLayer>;    // 右クリック後に確定した実際の選択レイヤー。
    function SelectionCount: Integer;
    function SingleLayer: TVectArtLayer;
  end;

  // 提供者が座標やPopup高さを管理せず、項目とサブメニューだけを宣言するための構築窓口。
  TMapRakuObjectMenuBuilder = class
  private
    FHost: TWinControl;
    FMenu: TVectArtDarkPopupMenu;
    FNextTop: Integer;
    FOwnedBuilders: TObjectList<TMapRakuObjectMenuBuilder>;
    FOwnedSubMenus: TObjectList<TVectArtDarkPopupMenu>;
  public
    constructor Create(Menu: TVectArtDarkPopupMenu; Host: TWinControl);
    destructor Destroy; override;
    function AddItem(const Caption: string; ClickHandler: TNotifyEvent;
      Enabled: Boolean = True): TPanel; overload;
    function AddItem(const Caption, Shortcut: string;
      ClickHandler: TNotifyEvent; Enabled: Boolean = True): TPanel; overload;
    function AddSubMenu(const Caption: string;
      Width: Integer = 160): TMapRakuObjectMenuBuilder;
    procedure AddSeparator;
  end;

  // 別ユニットから対象固有の項目を追加する拡張点。登録後の所有権はメニューへ移る。
  TMapRakuObjectMenuContributor = class
  public
    function AppliesTo(const Context: TMapRakuObjectMenuContext): Boolean;
      virtual; abstract;
    procedure BuildMenu(const Context: TMapRakuObjectMenuContext;
      Builder: TMapRakuObjectMenuBuilder); virtual; abstract;
  end;

  TMapRakuObjectContextMenu = class(TComponent)
  private
    FBuilder: TMapRakuObjectMenuBuilder;
    FContributors: TObjectList<TMapRakuObjectMenuContributor>;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FEditHistory: TVectArtEditHistory;
    FHitLayerIndices: TArray<Integer>;
    FHost: TWinControl;
    FMenu: TVectArtDarkPopupMenu;
    procedure EditObjectClick(Sender: TObject);
    procedure GroupObjectClick(Sender: TObject);
    function CaptureContext: TMapRakuObjectMenuContext;
    procedure Rebuild(const Context: TMapRakuObjectMenuContext);
    procedure SelectHitLayer(Sender: TObject);
  public
    // Host上へルートメニューを生成し、現在の選択を取得するモデルを非所有参照で保持する。
    constructor Create(AOwner: TComponent; Host: TWinControl;
      MenuGroup: TVectArtDarkMenuGroup; Document: TVectArtDocument;
      EditorState: TVectArtEditorState); reintroduce;
    destructor Destroy; override;
    // 提供者の所有権を受け取り、以後の表示時に適用判定と項目構築を呼び出す。
    procedure RegisterContributor(
      Contributor: TMapRakuObjectMenuContributor);
    // Canvasの通知座標へ、現在の選択に適用できる項目を構築してメニューを開く。
    procedure ShowForObject(Sender: TObject; const ScreenPoint: TPoint);
      overload;
    procedure ShowForObject(Sender: TObject; const ScreenPoint: TPoint;
      const LayerIndices: TArray<Integer>); overload;
    // 実行済み項目からポップアップと開いている子メニューを閉じる。
    procedure Close;
    property EditHistory: TVectArtEditHistory read FEditHistory write FEditHistory;
    property Menu: TVectArtDarkPopupMenu read FMenu;
  end;

implementation

uses
  MapRakuGroupCommands, MapRakuLayerOperations,
  MapRakuObjectClipboard, MapRakuMapCommands;

const
  MENU_ITEM_HEIGHT = 32;
  MENU_SEPARATOR_HEIGHT = 8;

{ TMapRakuObjectMenuContext }

function TMapRakuObjectMenuContext.SelectionCount: Integer;
begin
  Result := Length(Layers);
end;

function TMapRakuObjectMenuContext.SingleLayer: TVectArtLayer;
begin
  if Length(Layers) = 1 then
    Result := Layers[0]
  else
    Result := nil;
end;

{ TMapRakuObjectMenuBuilder }

function TMapRakuObjectMenuBuilder.AddItem(const Caption: string;
  ClickHandler: TNotifyEvent; Enabled: Boolean): TPanel;
begin
  Result := FMenu.AddItem(Caption, FNextTop, ClickHandler);
  FMenu.SetItemEnabled(Result, Enabled);
  Inc(FNextTop, MENU_ITEM_HEIGHT);
  FMenu.PopupHeight := FNextTop;
end;

function TMapRakuObjectMenuBuilder.AddItem(const Caption,
  Shortcut: string; ClickHandler: TNotifyEvent; Enabled: Boolean): TPanel;
begin
  Result := FMenu.AddItem(Caption, Shortcut, FNextTop, ClickHandler);
  FMenu.SetItemEnabled(Result, Enabled);
  Inc(FNextTop, MENU_ITEM_HEIGHT);
  FMenu.PopupHeight := FNextTop;
end;

procedure TMapRakuObjectMenuBuilder.AddSeparator;
begin
  if FNextTop = 0 then
    Exit;
  FMenu.AddSeparator(FNextTop, MENU_SEPARATOR_HEIGHT);
  Inc(FNextTop, MENU_SEPARATOR_HEIGHT);
  FMenu.PopupHeight := FNextTop;
end;

function TMapRakuObjectMenuBuilder.AddSubMenu(const Caption: string;
  Width: Integer): TMapRakuObjectMenuBuilder;
var
  SubMenu: TVectArtDarkPopupMenu;
begin
  SubMenu := TVectArtDarkPopupMenu.CreatePopup(nil, FHost, Width, 1);
  FOwnedSubMenus.Add(SubMenu);
  FMenu.AddSubMenu(Caption, FNextTop, SubMenu);
  Inc(FNextTop, MENU_ITEM_HEIGHT);
  FMenu.PopupHeight := FNextTop;
  Result := TMapRakuObjectMenuBuilder.Create(SubMenu, FHost);
  FOwnedBuilders.Add(Result);
end;

constructor TMapRakuObjectMenuBuilder.Create(
  Menu: TVectArtDarkPopupMenu; Host: TWinControl);
begin
  inherited Create;
  FMenu := Menu;
  FHost := Host;
  FOwnedBuilders := TObjectList<TMapRakuObjectMenuBuilder>.Create(True);
  FOwnedSubMenus := TObjectList<TVectArtDarkPopupMenu>.Create(True);
end;

destructor TMapRakuObjectMenuBuilder.Destroy;
begin
  FOwnedBuilders.Free;
  FOwnedSubMenus.Free;
  FMenu.ClearItems;
  inherited Destroy;
end;

{ TMapRakuObjectContextMenu }

function TMapRakuObjectContextMenu.CaptureContext:
  TMapRakuObjectMenuContext;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  Result := Default(TMapRakuObjectMenuContext);
  Result.Document := FDocument;
  Result.EditorState := FEditorState;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
    (FEditorState.OpenGroupChildCount > 0) then
  begin
    Result.Layers := FEditorState.GetOpenGroupChildren;
    Exit;
  end;
  if FDocument = nil then
    Exit;
  Indices := FDocument.GetSelectedLayerIndices;
  SetLength(Result.Layers, Length(Indices));
  for I := 0 to High(Indices) do
    Result.Layers[I] := FDocument[Indices[I]];
end;

constructor TMapRakuObjectContextMenu.Create(AOwner: TComponent;
  Host: TWinControl; MenuGroup: TVectArtDarkMenuGroup;
  Document: TVectArtDocument; EditorState: TVectArtEditorState);
begin
  inherited Create(AOwner);
  FHost := Host;
  FDocument := Document;
  FEditorState := EditorState;
  FContributors := TObjectList<TMapRakuObjectMenuContributor>.Create(True);
  FMenu := TVectArtDarkPopupMenu.CreatePopup(Self, Host, 208, 1);
  if MenuGroup <> nil then
    MenuGroup.RegisterMenu(FMenu);
end;

procedure TMapRakuObjectContextMenu.Close;
begin
  FMenu.Close;
end;

destructor TMapRakuObjectContextMenu.Destroy;
begin
  FBuilder.Free;
  FContributors.Free;
  inherited Destroy;
end;

procedure TMapRakuObjectContextMenu.Rebuild(
  const Context: TMapRakuObjectMenuContext);
var
  Contributor: TMapRakuObjectMenuContributor;
  I: Integer;
  LayerBuilder: TMapRakuObjectMenuBuilder;
  GroupBuilder: TMapRakuObjectMenuBuilder;
  OrderBuilder: TMapRakuObjectMenuBuilder;
  Panel: TPanel;
  Operations: TVectArtLayerOperations;
  DetachEnabled: Boolean;
begin
  FreeAndNil(FBuilder);
  FBuilder := TMapRakuObjectMenuBuilder.Create(FMenu, FHost);
  Operations := TVectArtLayerOperations.Create;
  try
    Operations.Document := FDocument;
    Operations.EditorState := FEditorState;
    FBuilder.AddItem('切り取り', 'Ctrl+X', EditObjectClick, Operations.CanExecute(vlaDelete)).Tag := 1;
    FBuilder.AddItem('コピー', 'Ctrl+C', EditObjectClick,
      Length(ClipboardSelection(FDocument, FEditorState)) > 0).Tag := 2;
    FBuilder.AddItem('貼り付け', 'Ctrl+V', EditObjectClick, CanPasteObjects(FEditorState)).Tag := 3;
    FBuilder.AddItem('複製', 'Ctrl+D', EditObjectClick, Operations.CanExecute(vlaDuplicate)).Tag := 4;
    FBuilder.AddItem('削除', 'Delete', EditObjectClick, Operations.CanExecute(vlaDelete)).Tag := 5;
  finally
    Operations.Free;
  end;
  OrderBuilder := FBuilder.AddSubMenu('重なり');
  Operations := TVectArtLayerOperations.Create;
  try
    Operations.Document := FDocument;
    Operations.EditorState := FEditorState;
    OrderBuilder.AddItem('最前面へ', 'Ctrl+Shift+]', EditObjectClick,
      Operations.CanExecute(vlaMoveToFront)).Tag := 11;
    OrderBuilder.AddItem('最背面へ', 'Ctrl+Shift+[', EditObjectClick,
      Operations.CanExecute(vlaMoveToBack)).Tag := 12;
    OrderBuilder.AddItem('前面へ', 'Ctrl+]', EditObjectClick,
      Operations.CanExecute(vlaMoveForward)).Tag := 13;
    OrderBuilder.AddItem('背面へ', 'Ctrl+[', EditObjectClick,
      Operations.CanExecute(vlaMoveBackward)).Tag := 14;
  finally
    Operations.Free;
  end;
  // ショートカットと同じ既存コマンドへ接続し、メニュー固有の編集処理は持たせない。
  GroupBuilder := FBuilder.AddSubMenu('グループ');
  GroupBuilder.AddItem('グループ化', 'Ctrl+G', GroupObjectClick,
    CanGroupCurrentSelection(FDocument, FEditorState)).Tag := 1;
  GroupBuilder.AddItem('グループ化解除', 'Ctrl+Shift+G', GroupObjectClick,
    CanUngroupCurrentSelection(FDocument, FEditorState)).Tag := 2;
  DetachEnabled := (FEditorState <> nil) and
    (FEditorState.OpenGroup <> nil) and
    (FEditorState.OpenGroupChild <> nil) and
    not FEditorState.OpenGroupChild.Locked and
    IsMapTree(FEditorState.OpenGroupChild);
  GroupBuilder.AddItem('選択要素を層から外す', GroupObjectClick,
    DetachEnabled).Tag := 4;
  if (Length(FHitLayerIndices) > 1) and
    ((FEditorState = nil) or (FEditorState.OpenGroup = nil)) then
  begin
    FBuilder.AddSeparator;
    LayerBuilder := FBuilder.AddSubMenu('この位置のレイヤー', 208);
    for I := 0 to High(FHitLayerIndices) do
      if (FHitLayerIndices[I] > 0) and
        (FHitLayerIndices[I] < FDocument.LayerCount) then
      begin
        Panel := LayerBuilder.AddItem(
          FDocument[FHitLayerIndices[I]].Name, SelectHitLayer);
        Panel.Tag := FHitLayerIndices[I];
      end;
  end;
  for Contributor in FContributors do
    if Contributor.AppliesTo(Context) then
    begin
      FBuilder.AddSeparator;
      Contributor.BuildMenu(Context, FBuilder);
    end;
end;

procedure TMapRakuObjectContextMenu.GroupObjectClick(Sender: TObject);
begin
  if not (Sender is TPanel) then Exit;
  case TPanel(Sender).Tag of
    1:
      GroupCurrentSelection(FDocument, FEditHistory, FEditorState);
    2:
      UngroupCurrentSelection(FDocument, FEditHistory, FEditorState);
    4:
      DetachMapChild(FDocument, FEditHistory, FEditorState);
  end;
  Close;
end;

procedure TMapRakuObjectContextMenu.EditObjectClick(Sender: TObject);
var
  Operations: TVectArtLayerOperations;
begin
  if not (Sender is TPanel) then Exit;
  Operations := TVectArtLayerOperations.Create;
  try
    Operations.Document := FDocument;
    Operations.EditorState := FEditorState;
    Operations.EditHistory := FEditHistory;
    case TPanel(Sender).Tag of
      1: if Operations.CanExecute(vlaDelete) then
         begin
           CopyObjects(FDocument, FEditorState);
           Operations.Execute(vlaDelete);
         end;
      2: CopyObjects(FDocument, FEditorState);
      3: PasteObjects(FDocument, FEditorState, FEditHistory);
      4: Operations.Execute(vlaDuplicate);
      5: Operations.Execute(vlaDelete);
      11: Operations.Execute(vlaMoveToFront);
      12: Operations.Execute(vlaMoveToBack);
      13: Operations.Execute(vlaMoveForward);
      14: Operations.Execute(vlaMoveBackward);
    end;
    Close;
  finally
    Operations.Free;
  end;
end;

procedure TMapRakuObjectContextMenu.RegisterContributor(
  Contributor: TMapRakuObjectMenuContributor);
begin
  if Contributor = nil then
    raise EArgumentNilException.Create('Contributor');
  FContributors.Add(Contributor);
end;

procedure TMapRakuObjectContextMenu.ShowForObject(Sender: TObject;
  const ScreenPoint: TPoint);
begin
  FHitLayerIndices := nil;
  Rebuild(CaptureContext);
  FMenu.OpenAtScreenPoint(ScreenPoint);
end;

procedure TMapRakuObjectContextMenu.ShowForObject(Sender: TObject;
  const ScreenPoint: TPoint; const LayerIndices: TArray<Integer>);
begin
  FHitLayerIndices := Copy(LayerIndices);
  Rebuild(CaptureContext);
  FMenu.OpenAtScreenPoint(ScreenPoint);
end;

procedure TMapRakuObjectContextMenu.SelectHitLayer(Sender: TObject);
var
  LayerIndex: Integer;
begin
  if not (Sender is TPanel) or (FDocument = nil) then
    Exit;
  LayerIndex := TPanel(Sender).Tag;
  if (LayerIndex <= 0) or (LayerIndex >= FDocument.LayerCount) then
    Exit;
  FDocument.SelectedIndex := LayerIndex;
  Close;
end;

end.
