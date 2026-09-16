// 複数選択時の右クリックメニューへ、整列と均等間隔配置を追加する。
unit MapRakuArrangementContextMenu;

interface

uses
  System.Classes, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState, MapRakuObjectContextMenu;

type
  TMapRakuArrangementMenuContributor = class(
    TMapRakuObjectMenuContributor)
  private
    FContextMenu: TMapRakuObjectContextMenu;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    procedure ArrangementClick(Sender: TObject);
  public
    constructor Create(ContextMenu: TMapRakuObjectContextMenu;
      Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
      EditorState: TVectArtEditorState);
    function AppliesTo(
      const Context: TMapRakuObjectMenuContext): Boolean; override;
    procedure BuildMenu(const Context: TMapRakuObjectMenuContext;
      Builder: TMapRakuObjectMenuBuilder); override;
  end;

implementation

uses
  Vcl.ExtCtrls, MapRakuLayerArrangementOperations;

constructor TMapRakuArrangementMenuContributor.Create(
  ContextMenu: TMapRakuObjectContextMenu; Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
begin
  inherited Create;
  FContextMenu := ContextMenu;
  FDocument := Document;
  FEditHistory := EditHistory;
  FEditorState := EditorState;
end;

function TMapRakuArrangementMenuContributor.AppliesTo(
  const Context: TMapRakuObjectMenuContext): Boolean;
begin
  Result := Context.SelectionCount >= 2;
end;

procedure TMapRakuArrangementMenuContributor.ArrangementClick(
  Sender: TObject);
begin
  if not (Sender is TPanel) then
    Exit;
  if FContextMenu <> nil then
    FContextMenu.Close;
  ArrangeMapRakuSelection(FDocument, FEditHistory, FEditorState,
    TMapRakuArrangement(TPanel(Sender).Tag));
end;

procedure TMapRakuArrangementMenuContributor.BuildMenu(
  const Context: TMapRakuObjectMenuContext;
  Builder: TMapRakuObjectMenuBuilder);
const
  CAPTIONS: array[TMapRakuArrangement] of string =
    ('左端揃え', '水平中央揃え', '右端揃え', '上端揃え',
     '垂直中央揃え', '下端揃え', '水平間隔を均等化',
     '垂直間隔を均等化');
var
  Arrangement: TMapRakuArrangement;
  ArrangementBuilder: TMapRakuObjectMenuBuilder;
  Item: TPanel;
begin
  ArrangementBuilder := Builder.AddSubMenu('整列', 208);
  for Arrangement := Low(TMapRakuArrangement) to
    High(TMapRakuArrangement) do
  begin
    if Arrangement in [slaAlignTop, slaDistributeHorizontal] then
      ArrangementBuilder.AddSeparator;
    Item := ArrangementBuilder.AddItem(CAPTIONS[Arrangement],
      ArrangementClick, CanArrangeMapRakuSelection(FDocument,
        FEditorState, Arrangement));
    Item.Tag := Ord(Arrangement);
  end;
end;

end.
