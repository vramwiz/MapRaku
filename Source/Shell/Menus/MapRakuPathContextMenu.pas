// 開いた線Pathに、表示輪郭を閉じたパス図形へ変換する項目を提供する。
unit MapRakuPathContextMenu;

interface

uses
  System.Classes, MapRakuDocument, MapRakuEditHistory,
  MapRakuObjectContextMenu;

type
  TMapRakuPathMenuContributor = class(TMapRakuObjectMenuContributor)
  private
    FContext: TMapRakuObjectMenuContext;
    FContextMenu: TMapRakuObjectContextMenu;
    FEditHistory: TVectArtEditHistory;
    FPathLayer: TVectArtPathLayer;
    FVertexIndex: Integer;
    FSegmentIndex: Integer;
    FSegmentT: Single;
    procedure AddVertexClick(Sender: TObject);
    procedure ApplyColorPresetClick(Sender: TObject);
    procedure DeleteVertexClick(Sender: TObject);
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
  Vcl.ExtCtrls, MapRakuCanvas, MapRakuMapCommands,
  MapRakuStrokeOutlineCommands;

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
var
  ColorBuilder: TMapRakuObjectMenuBuilder;
  VertexBuilder: TMapRakuObjectMenuBuilder;
begin
  FContext := Context;
  FPathLayer:=nil;
  FVertexIndex:=-1;
  FSegmentIndex:=-1;
  if (Context.Source is TVectArtCanvasControl) and
    (TVectArtPathLayer(Context.SingleLayer).MapElement<>'') and
    TVectArtCanvasControl(Context.Source).TryPathVertexMenuTarget(
      Context.ScreenPoint,FPathLayer,FVertexIndex,FSegmentIndex,FSegmentT) and
    (FPathLayer=Context.SingleLayer) then
  begin
    VertexBuilder:=Builder.AddSubMenu('頂点');
    VertexBuilder.AddItem('追加',AddVertexClick,
      not FPathLayer.Locked and (FSegmentIndex>=0));
    VertexBuilder.AddItem('削除',DeleteVertexClick,
      not FPathLayer.Locked and (FVertexIndex>=0) and
      (Length(FPathLayer.Vertices)>2));
    Builder.AddSeparator;
  end;
  if (TVectArtPathLayer(Context.SingleLayer).MapElement='road') or
    (TVectArtPathLayer(Context.SingleLayer).MapElement='river') then
  begin
    ColorBuilder:=Builder.AddSubMenu('色プリセット',208);
    ColorBuilder.AddItem('新規配置の色に設定',ApplyColorPresetClick,
      not Context.SingleLayer.Locked).Tag:=0;
    ColorBuilder.AddItem('同種の既存経路にも一括適用',ApplyColorPresetClick,
      not Context.SingleLayer.Locked).Tag:=1;
    Builder.AddSeparator;
  end;
  Builder.AddItem('線を閉じたパス図形へ変換', OutlineClick,
    not Context.SingleLayer.Locked);
end;

procedure TMapRakuPathMenuContributor.ApplyColorPresetClick(Sender: TObject);
begin
  if not (Sender is TPanel) or
    not (FContext.SingleLayer is TVectArtPathLayer) then Exit;
  FContextMenu.Close;
  ApplyMapColorPreset(FContext.Document,FEditHistory,
    TVectArtPathLayer(FContext.SingleLayer),TPanel(Sender).Tag=1);
end;

procedure TMapRakuPathMenuContributor.AddVertexClick(Sender: TObject);
begin
  if (FPathLayer=nil) or not (FContext.Source is TVectArtCanvasControl) then Exit;
  FContextMenu.Close;
  TVectArtCanvasControl(FContext.Source).ExecutePathVertexMenuEdit(
    FPathLayer,-1,FSegmentIndex,FSegmentT,False);
end;

procedure TMapRakuPathMenuContributor.DeleteVertexClick(Sender: TObject);
begin
  if (FPathLayer=nil) or not (FContext.Source is TVectArtCanvasControl) then Exit;
  FContextMenu.Close;
  TVectArtCanvasControl(FContext.Source).ExecutePathVertexMenuEdit(
    FPathLayer,FVertexIndex,-1,0,True);
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
