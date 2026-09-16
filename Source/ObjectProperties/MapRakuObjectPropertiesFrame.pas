// フィルターUIと色・不透明度UIを同階層の独立Frameとして提供する。
unit MapRakuObjectPropertiesFrame;

interface

uses
  System.Classes, Vcl.Controls, MapRakuColorPickerFrame, MapRakuContext,
  MapRakuFilterFrame, MapRakuObjectColorController,
  MapRakuToolFrames;

type
  TObjectPropertiesFrame = class(TToolPlaceholderFrame)
  private
    FColorController: TMapRakuObjectColorController;
    FColorPickerFrame: TMapRakuColorPickerFrame;
    FContext: IVectArtDesignerContext;
    FFilterFrame: TMapRakuFilterFrame;
    procedure PropertyControllerChanged(Sender: TObject);
    procedure SetContext(const Value: IVectArtDesignerContext);
  protected
    procedure Resize; override;
  public
    // 独立したフィルターFrameと下部固定の色選択Frameを生成する。
    constructor Create(AOwner: TComponent); override;
    // 非所有のFrameより先に属性Controllerを破棄し、イベント参照を残さない。
    destructor Destroy; override;
    // Documentと選択状態からフィルターおよび色選択を再同期する。
    procedure RefreshFromDocument;
    // 文書読込後または画面を開いた際に、使用色で履歴を初期化する。
    procedure LoadColorHistory;
    // Contextを交換すると、各子Frameへ同じ編集サービスを接続する。
    property Context: IVectArtDesignerContext read FContext write SetContext;
  end;

implementation

uses
  Winapi.Windows, Vcl.Graphics, System.Math;

{$R MapRakuObjectPropertiesFrame.dfm}

const
  COLOR_PANEL_BACKGROUND       = TColor($00212121);
  COLOR_PICKER_PANEL_HEIGHT    = 538; // 最大のモード設定を含めても切り替え時に動かさない高さ。
  OBJECT_PROPERTIES_DOCK_WIDTH = 160;

constructor TObjectPropertiesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ConfigureToolAppearance('ObjectProperties', 'Object Properties',
    COLOR_PANEL_BACKGROUND, OBJECT_PROPERTIES_DOCK_WIDTH);
  TitleLabel.Visible := False;

  FColorPickerFrame := TMapRakuColorPickerFrame.Create(Self);
  FColorPickerFrame.Parent := Self;
  FColorPickerFrame.Align := alBottom;
  FColorPickerFrame.Height := MulDiv(COLOR_PICKER_PANEL_HEIGHT,
    CurrentPPI, 96);

  FFilterFrame := TMapRakuFilterFrame.Create(Self);
  FFilterFrame.Parent := Self;
  FFilterFrame.Align := alClient;

  FColorController := TMapRakuObjectColorController.Create(
    FColorPickerFrame);
  FColorController.OnChanged := PropertyControllerChanged;
end;

procedure TObjectPropertiesFrame.Resize;
var
  PickerHeight: Integer;
begin
  inherited;
  if FColorPickerFrame = nil then Exit;
  // ヘッダー・1行・補助設定を優先して確保し、色ピッカーは最小高さまで縮める。
  PickerHeight := EnsureRange(ClientHeight - MulDiv(184, CurrentPPI, 96),
    FColorPickerFrame.Constraints.MinHeight, MulDiv(COLOR_PICKER_PANEL_HEIGHT, CurrentPPI, 96));
  if FColorPickerFrame.Height <> PickerHeight then FColorPickerFrame.Height := PickerHeight;
end;

destructor TObjectPropertiesFrame.Destroy;
begin
  FColorController.Free;
  inherited Destroy;
end;

procedure TObjectPropertiesFrame.PropertyControllerChanged(Sender: TObject);
begin
  RefreshFromDocument;
end;

procedure TObjectPropertiesFrame.RefreshFromDocument;
begin
  FColorController.Refresh;
  FFilterFrame.RefreshFromDocument;
end;

procedure TObjectPropertiesFrame.LoadColorHistory;
begin
  if FContext <> nil then FColorPickerFrame.LoadColorHistory(FContext.Document);
end;

procedure TObjectPropertiesFrame.SetContext(
  const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  FColorController.SetContext(FContext);
  FFilterFrame.Context := FContext;
  RefreshFromDocument;
end;

end.
