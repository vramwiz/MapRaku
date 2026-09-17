// 上部の編集メニューに履歴、反転、図形演算、設定をまとめる。
unit MapRakuEditActionsUI;

interface

uses
  System.Classes, Vcl.Controls, Vcl.ExtCtrls,
  VectArtDarkPopupMenu, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState;

type
  TVectArtEditActionsUI = class(TComponent)
  private
    FCanvasSettingsItem: TPanel;
    FCanvasSettingsVisible: Boolean;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FGeometrySettingsEnabled: Boolean;
    FGeometrySettingsItem: TPanel;
    FHistory: TVectArtEditHistory;
    FMenu: TVectArtDarkPopupMenu;
    FOnCanvasSettingsRequest: TNotifyEvent;
    FOnGeometrySettingsRequest: TNotifyEvent;
    FRedoItem: TPanel;
    FUndoItem: TPanel;
    FFlipHorizontalItem: TPanel;
    FFlipVerticalItem: TPanel;
    FBooleanItems: array[0..3] of TPanel;
    procedure CanvasSettingsClick(Sender: TObject);
    procedure FlipHorizontalClick(Sender: TObject);
    procedure FlipVerticalClick(Sender: TObject);
    procedure GeometrySettingsClick(Sender: TObject);
    function NewMenuItem(const Caption: string; Top: Integer;
      ClickHandler: TNotifyEvent): TPanel;
    procedure RedoClick(Sender: TObject);
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetEditorState(const Value: TVectArtEditorState);
    procedure SetHistory(const Value: TVectArtEditHistory);
    procedure SetCanvasSettingsVisible(const Value: Boolean);
    procedure SetGeometrySettingsEnabled(const Value: Boolean);
    procedure ShapeBooleanClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
  public
    constructor CreateForHosts(AOwner: TComponent; AMainForm,
      AMenuBar: TWinControl);
    procedure RefreshState;
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditorState: TVectArtEditorState read FEditorState
      write SetEditorState;
    property History: TVectArtEditHistory read FHistory write SetHistory;
    property Menu: TVectArtDarkPopupMenu read FMenu;
    property CanvasSettingsVisible: Boolean read FCanvasSettingsVisible
      write SetCanvasSettingsVisible;
    property GeometrySettingsEnabled: Boolean read FGeometrySettingsEnabled
      write SetGeometrySettingsEnabled;
    property OnCanvasSettingsRequest: TNotifyEvent
      read FOnCanvasSettingsRequest write FOnCanvasSettingsRequest;
    property OnGeometrySettingsRequest: TNotifyEvent
      read FOnGeometrySettingsRequest write FOnGeometrySettingsRequest;
  end;

implementation

uses
  Vcl.Graphics, MapRakuLayerFlipOperations,
  MapRakuShapeBooleanOperations;

const
  COLOR_DISABLED = TColor($00757575);
  COLOR_TEXT = TColor($00E6E6E6);

{ TVectArtEditActionsUI }

constructor TVectArtEditActionsUI.CreateForHosts(AOwner: TComponent;
  AMainForm, AMenuBar: TWinControl);
const
  BOOLEAN_CAPTIONS: array[0..3] of string =
    ('加算', '減算', '共通部分', '排他的論理和');
var
  I: Integer;
begin
  inherited Create(AOwner);
  FMenu := TVectArtDarkPopupMenu.CreateForHosts(Self, AMainForm, AMenuBar,
    '編集', 0, 36, 210, 320);
  FUndoItem := NewMenuItem('Undo    Ctrl+Z', 0, UndoClick);
  FRedoItem := NewMenuItem('Redo    Ctrl+Y', 32, RedoClick);
  FFlipHorizontalItem := NewMenuItem('左右反転    Shift+H', 64,
    FlipHorizontalClick);
  FFlipVerticalItem := NewMenuItem('上下反転    Shift+V', 96,
    FlipVerticalClick);
  for I := Low(FBooleanItems) to High(FBooleanItems) do
  begin
    FBooleanItems[I] := NewMenuItem(BOOLEAN_CAPTIONS[I], 128 + I * 32,
      ShapeBooleanClick);
    FBooleanItems[I].Tag := I;
  end;
  FGeometrySettingsItem := NewMenuItem('配置とサイズ...', 256,
    GeometrySettingsClick);
  FGeometrySettingsEnabled := False;
  FCanvasSettingsItem := NewMenuItem('キャンバスの設定', 288,
    CanvasSettingsClick);
  FCanvasSettingsVisible := True;
end;

procedure TVectArtEditActionsUI.FlipHorizontalClick(Sender: TObject);
begin
  FMenu.Close;
  if CanFlipMapRakuSelection(FDocument, FEditorState) then
    FlipMapRakuSelection(FDocument, FHistory, FEditorState, slfdHorizontal);
end;

procedure TVectArtEditActionsUI.FlipVerticalClick(Sender: TObject);
begin
  FMenu.Close;
  if CanFlipMapRakuSelection(FDocument, FEditorState) then
    FlipMapRakuSelection(FDocument, FHistory, FEditorState, slfdVertical);
end;

procedure TVectArtEditActionsUI.GeometrySettingsClick(Sender: TObject);
begin
  FMenu.Close;
  if FGeometrySettingsEnabled and
    Assigned(FOnGeometrySettingsRequest) then
    FOnGeometrySettingsRequest(Self);
end;

procedure TVectArtEditActionsUI.CanvasSettingsClick(Sender: TObject);
begin
  FMenu.Close;
  if FCanvasSettingsVisible and Assigned(FOnCanvasSettingsRequest) then
    FOnCanvasSettingsRequest(Self);
end;

function TVectArtEditActionsUI.NewMenuItem(const Caption: string;
  Top: Integer; ClickHandler: TNotifyEvent): TPanel;
begin
  Result := FMenu.AddItem(Caption, Top, ClickHandler);
end;

procedure TVectArtEditActionsUI.RedoClick(Sender: TObject);
begin
  FMenu.Close;
  if (FHistory <> nil) and FHistory.CanRedo then
    FHistory.Redo;
end;

procedure TVectArtEditActionsUI.RefreshState;
var
  CanFlip: Boolean;
  CanApplyBoolean: Boolean;
  I: Integer;
begin
  FUndoItem.Enabled := (FHistory <> nil) and FHistory.CanUndo;
  FRedoItem.Enabled := (FHistory <> nil) and FHistory.CanRedo;
  if FUndoItem.Enabled then FUndoItem.Font.Color := COLOR_TEXT
  else FUndoItem.Font.Color := COLOR_DISABLED;
  if FRedoItem.Enabled then FRedoItem.Font.Color := COLOR_TEXT
  else FRedoItem.Font.Color := COLOR_DISABLED;
  CanFlip := CanFlipMapRakuSelection(FDocument, FEditorState);
  FFlipHorizontalItem.Enabled := CanFlip;
  FFlipVerticalItem.Enabled := CanFlip;
  if CanFlip then
  begin
    FFlipHorizontalItem.Font.Color := COLOR_TEXT;
    FFlipVerticalItem.Font.Color := COLOR_TEXT;
  end
  else
  begin
    FFlipHorizontalItem.Font.Color := COLOR_DISABLED;
    FFlipVerticalItem.Font.Color := COLOR_DISABLED;
  end;
  CanApplyBoolean := CanExecuteMapRakuShapeBoolean(FDocument);
  for I := Low(FBooleanItems) to High(FBooleanItems) do
  begin
    FBooleanItems[I].Enabled := CanApplyBoolean;
    if CanApplyBoolean then
      FBooleanItems[I].Font.Color := COLOR_TEXT
    else
      FBooleanItems[I].Font.Color := COLOR_DISABLED;
  end;
  FGeometrySettingsItem.Enabled := FGeometrySettingsEnabled;
  if FGeometrySettingsItem.Enabled then
    FGeometrySettingsItem.Font.Color := COLOR_TEXT
  else
    FGeometrySettingsItem.Font.Color := COLOR_DISABLED;
end;

procedure TVectArtEditActionsUI.SetDocument(const Value: TVectArtDocument);
begin
  FDocument := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.SetEditorState(
  const Value: TVectArtEditorState);
begin
  FEditorState := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.SetHistory(const Value: TVectArtEditHistory);
begin
  FHistory := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.SetCanvasSettingsVisible(
  const Value: Boolean);
begin
  FCanvasSettingsVisible := Value;
  FCanvasSettingsItem.Visible := Value;
  if Value then
    FMenu.PopupHeight := 320
  else
    FMenu.PopupHeight := 288;
end;

procedure TVectArtEditActionsUI.SetGeometrySettingsEnabled(
  const Value: Boolean);
begin
  if FGeometrySettingsEnabled = Value then
    Exit;
  FGeometrySettingsEnabled := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.UndoClick(Sender: TObject);
begin
  FMenu.Close;
  if (FHistory <> nil) and FHistory.CanUndo then
    FHistory.Undo;
end;

procedure TVectArtEditActionsUI.ShapeBooleanClick(Sender: TObject);
begin
  FMenu.Close;
  if (Sender is TPanel) and CanExecuteMapRakuShapeBoolean(FDocument) then
    ExecuteMapRakuShapeBoolean(FDocument, FHistory,
      TMapRakuShapeBooleanOperation(TPanel(Sender).Tag));
end;

end.
