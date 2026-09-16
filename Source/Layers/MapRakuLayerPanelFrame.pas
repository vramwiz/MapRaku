// サムネイルと状態操作に絞ったレイヤー一覧を提供し、Documentへ接続する。
unit MapRakuLayerPanelFrame;

interface

uses
  System.Classes, MapRakuContext, MapRakuLayerActions,
  MapRakuLayerList, MapRakuLayerOperations,
  MapRakuToolFrames;

type
  TLayerPanelFrame = class(TToolPlaceholderFrame)
  private
    FLayerList   : TVectArtLayerListControl;
    FLayerActions: TVectArtLayerActionsControl;
    FContext     : IVectArtDesignerContext;
    procedure SetContext(const Value: IVectArtDesignerContext);
  public
    // 一覧と操作バーを生成し、幅をサムネイル主体の初期値へ設定する。
    constructor Create(AOwner: TComponent); override;
    // 現在選択で指定操作を実行できる場合にTrueを返す。
    function CanRunLayerAction(Action: TVectArtLayerAction): Boolean;
    // 指定操作をDocumentへ適用し、必要な履歴を記録する。
    procedure RunLayerAction(Action: TVectArtLayerAction);
    // Document変更後の一覧と操作可否を再同期する。
    procedure RefreshFromDocument;
    // Contextを交換すると、一覧と操作バーへ同じサービス一式を接続する。
    property Context: IVectArtDesignerContext read FContext write SetContext;
    // 呼び出し側がフォーカス判定などに使う一覧Control。所有権はFrameが保持する。
    property LayerList: TVectArtLayerListControl read FLayerList;
  end;

implementation

uses
  Winapi.Windows, Vcl.Controls, Vcl.Graphics;

{$R MapRakuLayerPanelFrame.dfm}

const
  COLOR_PANEL_BACKGROUND= TColor($00212121);
  LAYER_PANEL_DOCK_WIDTH= 150;               // 文字列を持たない行と状態列が欠けない初期幅。

function TLayerPanelFrame.CanRunLayerAction(
  Action: TVectArtLayerAction): Boolean;
begin
  Result := FLayerActions.CanRunLayerAction(Action);
end;

constructor TLayerPanelFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ConfigureToolAppearance('Layers', 'Layers', COLOR_PANEL_BACKGROUND,
    LAYER_PANEL_DOCK_WIDTH);
  TitleLabel.Visible := False;
  FLayerList := TVectArtLayerListControl.Create(Self);
  FLayerList.Parent := Self;
  FLayerList.Align := alClient;
  FLayerActions := TVectArtLayerActionsControl.Create(Self);
  FLayerActions.Parent := Self;
  FLayerActions.Align := alBottom;
  FLayerActions.Height := MulDiv(34, CurrentPPI, 96);
  FLayerActions.BringToFront;
end;

procedure TLayerPanelFrame.RunLayerAction(Action: TVectArtLayerAction);
begin
  FLayerActions.RunLayerAction(Action);
end;

procedure TLayerPanelFrame.RefreshFromDocument;
begin
  FLayerList.Invalidate;
  FLayerActions.RefreshState;
end;

procedure TLayerPanelFrame.SetContext(const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  if FContext = nil then
  begin
    FLayerActions.EditorState := nil;
    FLayerActions.EditHistory := nil;
    FLayerActions.Document := nil;
    FLayerList.EditHistory := nil;
    FLayerList.EditorState := nil;
    FLayerList.Document := nil;
  end
  else
  begin
    FLayerList.Document := FContext.Document;
    FLayerList.EditHistory := FContext.EditHistory;
    FLayerList.EditorState := FContext.EditorState;
    FLayerActions.Document := FContext.Document;
    FLayerActions.EditHistory := FContext.EditHistory;
    FLayerActions.EditorState := FContext.EditorState;
  end;
end;

end.
