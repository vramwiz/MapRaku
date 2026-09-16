// 中央編集領域のFrameを提供し、Documentを編集キャンバスへ接続する。
unit MapRakuEditorWorkspaceFrame;

interface

uses
  System.Classes, MapRakuCanvas, MapRakuContext,
  MapRakuToolFrames;

type
  TEditorWorkspaceFrame = class(TPlaceholderFrame)
  private
    FCanvasControl: TVectArtCanvasControl;
    FContext: IVectArtDesignerContext;
    procedure SetContext(const Value: IVectArtDesignerContext);
  public
    constructor Create(AOwner: TComponent); override;
    property CanvasControl: TVectArtCanvasControl read FCanvasControl;
    // Contextを交換すると、Frame内の全Controlへ同じサービス一式を接続する。
    property Context: IVectArtDesignerContext read FContext write SetContext;
  end;

implementation

uses
  Vcl.Controls, Vcl.Graphics;

{$R MapRakuEditorWorkspaceFrame.dfm}

const
  COLOR_EDITOR_BACKGROUND = TColor($00121212);

constructor TEditorWorkspaceFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetPlaceholderAppearance('Editor Workspace', COLOR_EDITOR_BACKGROUND);
  TitleLabel.Visible := False;
  FCanvasControl := TVectArtCanvasControl.Create(Self);
  FCanvasControl.Parent := Self;
  FCanvasControl.Align := alClient;
end;

procedure TEditorWorkspaceFrame.SetContext(
  const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  if FContext = nil then
  begin
    FCanvasControl.EditorState := nil;
    FCanvasControl.EditHistory := nil;
    FCanvasControl.Document := nil;
  end
  else
  begin
    FCanvasControl.Document := FContext.Document;
    FCanvasControl.EditHistory := FContext.EditHistory;
    FCanvasControl.EditorState := FContext.EditorState;
  end;
end;

end.
