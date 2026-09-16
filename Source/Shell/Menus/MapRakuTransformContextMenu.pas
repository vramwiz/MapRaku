// オブジェクト右クリックメニューへ、選択共通の反転操作を追加する。
unit MapRakuTransformContextMenu;

interface

uses
  System.Classes, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState, MapRakuObjectContextMenu;

type
  TMapRakuTransformMenuContributor = class(
    TMapRakuObjectMenuContributor)
  private
    FContextMenu: TMapRakuObjectContextMenu;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    procedure FlipHorizontalClick(Sender: TObject);
    procedure FlipVerticalClick(Sender: TObject);
    procedure RotateClick(Sender: TObject);
  public
    // 選択解決とUndo履歴を共有する右クリック項目提供者を生成する。
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
  Vcl.ExtCtrls, MapRakuLayerFlipOperations, MapRakuLayerOperations;

constructor TMapRakuTransformMenuContributor.Create(
  ContextMenu: TMapRakuObjectContextMenu; Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
begin
  inherited Create;
  FContextMenu := ContextMenu;
  FDocument := Document;
  FEditHistory := EditHistory;
  FEditorState := EditorState;
end;

function TMapRakuTransformMenuContributor.AppliesTo(
  const Context: TMapRakuObjectMenuContext): Boolean;
begin
  Result := Context.SelectionCount > 0;
end;

procedure TMapRakuTransformMenuContributor.BuildMenu(
  const Context: TMapRakuObjectMenuContext;
  Builder: TMapRakuObjectMenuBuilder);
var
  Enabled: Boolean;
  RotationBuilder: TMapRakuObjectMenuBuilder;
  TransformBuilder: TMapRakuObjectMenuBuilder;
begin
  Enabled := CanFlipMapRakuSelection(FDocument, FEditorState);
  TransformBuilder := Builder.AddSubMenu('反転', 208);
  TransformBuilder.AddItem('左右反転', 'Shift+H', FlipHorizontalClick,
    Enabled);
  TransformBuilder.AddItem('上下反転', 'Shift+V', FlipVerticalClick,
    Enabled);
  RotationBuilder := Builder.AddSubMenu('回転', 208);
  RotationBuilder.AddItem('左へ90度', RotateClick, Enabled).Tag := -90;
  RotationBuilder.AddItem('右へ90度', RotateClick, Enabled).Tag := 90;
end;

procedure TMapRakuTransformMenuContributor.RotateClick(Sender: TObject);
var
  Operations: TVectArtLayerOperations;
begin
  if not (Sender is TPanel) then Exit;
  if FContextMenu <> nil then FContextMenu.Close;
  Operations := TVectArtLayerOperations.Create;
  try
    Operations.Document := FDocument;
    Operations.EditHistory := FEditHistory;
    Operations.EditorState := FEditorState;
    if TPanel(Sender).Tag < 0 then
      Operations.Execute(vlaRotateLeft90)
    else
      Operations.Execute(vlaRotateRight90);
  finally
    Operations.Free;
  end;
end;

procedure TMapRakuTransformMenuContributor.FlipHorizontalClick(
  Sender: TObject);
begin
  if FContextMenu <> nil then
    FContextMenu.Close;
  FlipMapRakuSelection(FDocument, FEditHistory, FEditorState,
    slfdHorizontal);
end;

procedure TMapRakuTransformMenuContributor.FlipVerticalClick(
  Sender: TObject);
begin
  if FContextMenu <> nil then
    FContextMenu.Close;
  FlipMapRakuSelection(FDocument, FEditHistory, FEditorState,
    slfdVertical);
end;

end.
