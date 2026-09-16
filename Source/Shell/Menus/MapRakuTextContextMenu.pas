// 文字オブジェクト固有の右クリック項目を提供し、処理本体からメニュー構成を分離する。
unit MapRakuTextContextMenu;

interface

uses
  System.Classes, MapRakuEditHistory, MapRakuObjectContextMenu,
  MapRakuTextDecompositionCommands;

type
  TMapRakuTextMenuContributor = class(
    TMapRakuObjectMenuContributor)
  private
    FContext: TMapRakuObjectMenuContext;
    FContextMenu: TMapRakuObjectContextMenu;
    FEditHistory: TVectArtEditHistory;
    procedure DecomposeAsClosedPathsClick(Sender: TObject);
    procedure DecomposeAsTextClick(Sender: TObject);
    procedure ExecuteDecomposition(Kind: TMapRakuTextDecompositionKind);
  public
    constructor Create(ContextMenu: TMapRakuObjectContextMenu;
      EditHistory: TVectArtEditHistory);
    // 単一の文字オブジェクトが選択されている場合だけ文字専用項目を提供する。
    function AppliesTo(const Context: TMapRakuObjectMenuContext): Boolean;
      override;
    // 文字レイヤーまたは閉じたパス図形へ分解するサブメニューを追加する。
    procedure BuildMenu(const Context: TMapRakuObjectMenuContext;
      Builder: TMapRakuObjectMenuBuilder); override;
  end;

implementation

uses
  MapRakuDocument;

constructor TMapRakuTextMenuContributor.Create(
  ContextMenu: TMapRakuObjectContextMenu;
  EditHistory: TVectArtEditHistory);
begin
  inherited Create;
  FContextMenu := ContextMenu;
  FEditHistory := EditHistory;
end;

function TMapRakuTextMenuContributor.AppliesTo(
  const Context: TMapRakuObjectMenuContext): Boolean;
begin
  Result := Context.SingleLayer is TMapRakuTextLayer;
end;

procedure TMapRakuTextMenuContributor.BuildMenu(
  const Context: TMapRakuObjectMenuContext;
  Builder: TMapRakuObjectMenuBuilder);
var
  DecomposeMenu: TMapRakuObjectMenuBuilder;
begin
  FContext := Context;
  DecomposeMenu := Builder.AddSubMenu('テキストの分解', 208);
  DecomposeMenu.AddItem('行／文字へ分解', DecomposeAsTextClick,
    not Context.SingleLayer.Locked);
  DecomposeMenu.AddItem('閉じたパス図形へ分解',
    DecomposeAsClosedPathsClick, not Context.SingleLayer.Locked);
end;

procedure TMapRakuTextMenuContributor.DecomposeAsClosedPathsClick(
  Sender: TObject);
begin
  ExecuteDecomposition(sldkClosedPathShapes);
end;

procedure TMapRakuTextMenuContributor.DecomposeAsTextClick(
  Sender: TObject);
begin
  ExecuteDecomposition(sldkTextFragments);
end;

procedure TMapRakuTextMenuContributor.ExecuteDecomposition(
  Kind: TMapRakuTextDecompositionKind);
var
  Layer: TVectArtLayer;
begin
  Layer := FContext.SingleLayer;
  if not (Layer is TMapRakuTextLayer) then
    Exit;
  if ExecuteMapRakuTextDecomposition(FContext.Document,
    FContext.EditorState, FEditHistory, TMapRakuTextLayer(Layer),
    Kind) and
    (FContextMenu <> nil) then
    FContextMenu.Close;
end;

end.
