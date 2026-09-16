// 開いた線Pathに、表示輪郭を閉じたパス図形へ変換する項目を提供する。
unit MapRakuPathContextMenu;

interface

uses
  System.Classes, MapRakuEditHistory, MapRakuObjectContextMenu;

type
  TMapRakuPathMenuContributor = class(TMapRakuObjectMenuContributor)
  private
    FContext: TMapRakuObjectMenuContext;
    FContextMenu: TMapRakuObjectContextMenu;
    FEditHistory: TVectArtEditHistory;
    procedure OutlineClick(Sender: TObject);
  public
    constructor Create(ContextMenu: TMapRakuObjectContextMenu;
      EditHistory: TVectArtEditHistory);
    function AppliesTo(const Context: TMapRakuObjectMenuContext): Boolean;
      override;
    procedure BuildMenu(const Context: TMapRakuObjectMenuContext;
      Builder: TMapRakuObjectMenuBuilder); override;
  end;

implementation

uses
  MapRakuDocument, MapRakuStrokeOutlineCommands;

constructor TMapRakuPathMenuContributor.Create(
  ContextMenu: TMapRakuObjectContextMenu;
  EditHistory: TVectArtEditHistory);
begin
  inherited Create;
  FContextMenu := ContextMenu;
  FEditHistory := EditHistory;
end;

function TMapRakuPathMenuContributor.AppliesTo(
  const Context: TMapRakuObjectMenuContext): Boolean;
begin
  Result := (Context.SingleLayer is TVectArtPathLayer) and
    not TVectArtPathLayer(Context.SingleLayer).Closed;
end;

procedure TMapRakuPathMenuContributor.BuildMenu(
  const Context: TMapRakuObjectMenuContext;
  Builder: TMapRakuObjectMenuBuilder);
begin
  FContext := Context;
  Builder.AddItem('線を閉じたパス図形へ変換', OutlineClick,
    not Context.SingleLayer.Locked);
end;

procedure TMapRakuPathMenuContributor.OutlineClick(Sender: TObject);
begin
  if not (FContext.SingleLayer is TVectArtPathLayer) then
    Exit;
  if ExecuteMapRakuStrokeOutline(FContext.Document,
    FContext.EditorState, FEditHistory,
    TVectArtPathLayer(FContext.SingleLayer)) and (FContextMenu <> nil) then
    FContextMenu.Close;
end;

end.
