// 編集ツールパレットのFrame外枠を提供する。
unit MapRakuToolPaletteFrame;

interface

uses
  System.Classes, MapRakuContext, MapRakuToolFrames,
  MapRakuToolPalette;

type
  TToolPaletteFrame = class(TToolPlaceholderFrame)
  private
    FToolPalette: TVectArtToolPaletteControl;
    FContext: IVectArtDesignerContext;
    procedure SetContext(const Value: IVectArtDesignerContext);
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshState;
    // 他のFrameと同じContext接続口を使い、必要な編集状態だけを利用する。
    property Context: IVectArtDesignerContext read FContext write SetContext;
  end;

implementation

uses
  Vcl.Controls, Vcl.Graphics;

{$R MapRakuToolPaletteFrame.dfm}

const
  COLOR_TOOL_BACKGROUND = TColor($00252525);

constructor TToolPaletteFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ConfigureToolAppearance('Tools', 'Tools', COLOR_TOOL_BACKGROUND, 58);
  TitleLabel.Visible := False;
  FToolPalette := TVectArtToolPaletteControl.Create(Self);
  FToolPalette.Parent := Self;
  FToolPalette.Align := alClient;
end;

procedure TToolPaletteFrame.RefreshState;
begin
  FToolPalette.RefreshState;
end;

procedure TToolPaletteFrame.SetContext(const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  if FContext = nil then
  begin
    FToolPalette.Document := nil;
    FToolPalette.EditorState := nil
  end
  else
  begin
    FToolPalette.Document := FContext.Document;
    FToolPalette.EditorState := FContext.EditorState;
  end;
end;

end.
