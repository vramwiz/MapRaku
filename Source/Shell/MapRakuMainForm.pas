// MapRakuのメイン画面を提供する。
// 個別ツールの内容はFrameへ分離し、このユニットは外枠と初期配置だけを担当する。
unit MapRakuMainForm;

interface

uses
  System.Classes, System.SysUtils, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.StdCtrls, Winapi.Messages, Winapi.ShellAPI, Winapi.Windows,
  ShortcutAction, VectArtDarkMenuGroup, VectArtDarkPopupMenu,
  MapRakuContext,
  MapRakuDockManager,
  MapRakuDocument,
  MapRakuEditHistory, MapRakuEditorState,
  MapRakuEditorWorkspaceFrame, MapRakuLayerPanelFrame,
  MapRakuLineToolbar,
  MapRakuObjectClipboard, MapRakuLayerOperations, MapRakuEditActionsUI,
  MapRakuGroupCommands,
  MapRakuGeometryPropertiesFrame,
  MapRakuMapPanel,
  MapRakuObjectPropertiesFrame, MapRakuToolFrames,
  MapRakuToolPaletteFrame, MapRakuObjectContextMenu,
  MapRakuTextContextMenu, MapRakuPathContextMenu,
  MapRakuTransformContextMenu,
  MapRakuArrangementContextMenu,
  PipeServerTThread, MapRakuAutomationPipeServer, Vcl.Graphics;

type
  TMainForm = class(TForm)
    pnlMenuBar: TPanel;
    lblMenuItems: TLabel;
    pnlViewMenuButton: TPanel;
    pnlViewMenuPopup: TPanel;
    pnlLayoutEditMenuItem: TPanel;
    pnlStatusBar: TPanel;
    lblStatus: TLabel;
    pnlWorkspace: TPanel;
    pnlLeftDockArea: TPanel;
    splLeftRegion: TSplitter;
    pnlRightDockArea: TPanel;
    splRightRegion: TSplitter;
    pnlEditorHost: TPanel;
    pnlLeftDropTarget: TPanel;
    pnlRightDropTarget: TPanel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormResize(Sender: TObject);
    procedure lblLayoutEditMenuItemClick(Sender: TObject);
  private
    FDockManager: TVectDockManager;
    FDesignerContext: IVectArtDesignerContext;
    FDocument: TVectArtDocument;
    FCurrentDocumentFileName: string;
    FSavedRevision: Int64;
    FEditorFrame: TEditorWorkspaceFrame;
    FEditorState: TVectArtEditorState;
    FEditActionsUI: TVectArtEditActionsUI;
    FEditHistory: TVectArtEditHistory;
    FFileDropCaptionBase: string;
    FFileDropCaptionEnabled: Boolean;
    FFileMenu: TVectArtDarkPopupMenu;
    FGeometryPopup: TForm;
    FGeometryPopupFrame: TMapRakuGeometryPropertiesFrame;
    FLayerFrame: TLayerPanelFrame;
    FLineToolbar: TVectArtLineToolbarControl;
    FMapToolsPanel: TMapToolsPanel;
    FObjectPropertiesFrame: TObjectPropertiesFrame;
    FObjectContextMenu: TMapRakuObjectContextMenu;
    FSkiaAcquired: Boolean;
    FShortcuts: TShortcutAction;
    FToolPaletteFrame: TToolPaletteFrame;
    FViewMenu: TVectArtDarkPopupMenu;
    FLayoutEditing: Boolean;
    FAutomationPipeStarted: Boolean; // このFormが専用Pipeを所有している間だけTrue。
    FLayoutFileName: string;
    FMenuGroup: TVectArtDarkMenuGroup;
    FLayerMenuItem: TPanel;
    FObjectPropertiesMenuItem: TPanel;
    FToolPaletteMenuItem: TPanel;
    function ConfirmSave: Boolean;
    procedure FileNewClick(Sender: TObject);
    procedure ActivateToolShortcut(const Tool: TVectArtEditorTool);
    procedure AttachFrame(AFrame: TFrame; AHost: TWinControl);
    procedure CanvasSettingsRequest(Sender: TObject);
    function CreateViewMenuItem(const Caption: string): TPanel;
    procedure DocumentChanged(Sender: TObject);
    procedure FinalizeSkiaRuntime;
    procedure FileOpenClick(Sender: TObject);
    procedure FileSaveClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure GeometryPopupDeactivate(Sender: TObject);
    procedure GeometryPopupKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure GeometrySettingsRequest(Sender: TObject);
    procedure HistoryChanged(Sender: TObject);
    procedure EditorStateChanged(Sender: TObject);
    procedure ExecuteLayerAction(Action: TVectArtLayerAction);
    procedure InitializeSkiaRuntime;
    procedure InitializeShortcuts;
    function IsEditingSurfaceFocused: Boolean;
    function IsTextInputFocused: Boolean;
    function CanExecuteLayerAction(Action: TVectArtLayerAction): Boolean;
    function ToolShortcutEnabled: Boolean;
    procedure LoadLayoutSettings;
    procedure LoadDocument;
    procedure SaveLayoutSettings;
    procedure SaveDocumentAs;
    procedure SelectAllLayers;
    procedure SetLayoutEditing(const Value: Boolean);
    procedure ToolMenuItemClick(Sender: TObject);
    procedure ToolVisibilityChanged(Sender: TToolPlaceholderFrame);
    procedure UpdateLayoutEditMenu;
    procedure UpdateGeometrySettingsAvailability;
    procedure UpdateToolMenuItems;
    procedure WMDropFiles(var Message: TWMDropFiles); message WM_DROPFILES;
    procedure WMAutomationPipe(var Message: TMessage); message WM_PIPE_NOTIFY;
  protected
    // 外部ホストによる文書初期化後、表示直前の使用色を取り込む。
    procedure DoShow; override;
  public
    // 単独アプリだけがJSONの読込・保存メニューを生成するための初期化口。
    function CloseQuery: Boolean; override;
    procedure EnableStandaloneFileActions;
    // 外部ホストが編集メニュー内のキャンバス設定項目を表示するか切り替える。
    procedure SetCanvasSettingsVisible(const Value: Boolean);
    // ウィンドウへドロップされた画像ファイルの配置を有効化する。
    procedure SetFileDropCaptionEnabled(const Value: Boolean);
    // プラグインホストが編集中だけ表示する参照背景を設定する。
    procedure SetReferenceBackgroundRgba(const Pixels: TBytes;
      Width, Height: Integer);
    // プラグインなど外部ホストが、同じ編集UIへDocumentを受け渡すための接続口。
    property Document: TVectArtDocument read FDocument;
  end;

var
  MainForm: TMainForm;

implementation

uses
  MapRakuFile, MapRakuExport, System.UITypes, System.IniFiles, System.IOUtils, System.Math, System.Types,
  TextRendererSkiaBootstrap, TextRendererSkiaRuntime,
  MapRakuCanvasSettingsDialog, MapRakuTheme, MapRakuMapCommands,
  MapRakuDocumentJson, MapRakuImageImport,
  MapRakuKeyboardMovement, MapRakuLayerFlipOperations,
  Vcl.Dialogs, Winapi.Dwmapi;

{$R *.dfm}

const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

function CheckedMenuCaption(const IsVisible: Boolean;
  const Caption: string): string;
begin
  if IsVisible then
    Result := '✓ ' + Caption
  else
    Result := '□ ' + Caption;
end;

procedure TMainForm.ActivateToolShortcut(const Tool: TVectArtEditorTool);
begin
  if FEditorState <> nil then
  begin
    FEditorState.MapElement := '';
    FEditorState.ActiveMapPreset := -1;
    FEditorState.ActivateTool(Tool);
  end;
end;

function ConstrainToMonitor(const Bounds: TRect): TRect;
var
  Monitor: TMonitor;
  WorkArea: TRect;
begin
  Result := Bounds;
  Monitor := Screen.MonitorFromRect(Result, mdNearest);
  WorkArea := Monitor.WorkareaRect;
  if Result.Width > WorkArea.Width then
    Result.Right := Result.Left + WorkArea.Width;
  if Result.Height > WorkArea.Height then
    Result.Bottom := Result.Top + WorkArea.Height;
  if Result.Left < WorkArea.Left then
    OffsetRect(Result, WorkArea.Left - Result.Left, 0);
  if Result.Top < WorkArea.Top then
    OffsetRect(Result, 0, WorkArea.Top - Result.Top);
  if Result.Right > WorkArea.Right then
    OffsetRect(Result, WorkArea.Right - Result.Right, 0);
  if Result.Bottom > WorkArea.Bottom then
    OffsetRect(Result, 0, WorkArea.Bottom - Result.Bottom);
end;

procedure TMainForm.AttachFrame(AFrame: TFrame; AHost: TWinControl);
begin
  AFrame.Parent := AHost;
  AFrame.Align := alClient;
  AFrame.Visible := True;
end;

function TMainForm.CreateViewMenuItem(const Caption: string): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := pnlViewMenuPopup;
  Result.Align := alTop;
  Result.BevelOuter := bvNone;
  Result.Caption := Caption;
  Result.Color := pnlViewMenuPopup.Color;
  Result.Font.Assign(pnlLayoutEditMenuItem.Font);
  Result.Height := MulDiv(32, CurrentPPI, 96);
  Result.ParentBackground := False;
  Result.OnClick := ToolMenuItemClick;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  DarkModeEnabled: BOOL;
  ErrorMessage: string;
  LayoutFolder: string;
begin
  DarkModeEnabled := True;
  DwmSetWindowAttribute(Handle, DWMWA_USE_IMMERSIVE_DARK_MODE,
    @DarkModeEnabled, SizeOf(DarkModeEnabled));

  InitializeSkiaRuntime;

  FDocument := TVectArtDocument.Create;
  FDocument.OnChanged := DocumentChanged;
  FEditorState := TVectArtEditorState.Create;
  FEditorState.OnChanged := EditorStateChanged;
  FEditHistory := TVectArtEditHistory.Create;
  FEditHistory.OnChanged := HistoryChanged;
  FDesignerContext := TVectArtDesignerContext.Create(FDocument, FEditHistory,
    FEditorState);
  lblMenuItems.Visible := False;
  FEditActionsUI := TVectArtEditActionsUI.CreateForHosts(Self, Self,
    pnlMenuBar);
  FEditActionsUI.Document := FDocument;
  FEditActionsUI.History := FEditHistory;
  FEditActionsUI.EditorState := FEditorState;
  FEditActionsUI.OnCanvasSettingsRequest := CanvasSettingsRequest;
  FEditActionsUI.OnGeometrySettingsRequest := GeometrySettingsRequest;
  pnlViewMenuButton.Left := MulDiv(36, CurrentPPI, 96);
  FLineToolbar := TVectArtLineToolbarControl.CreateForHost(Self,
    pnlMenuBar);
  FLineToolbar.Document := FDocument;
  FLineToolbar.EditHistory := FEditHistory;
  FLineToolbar.EditorState := FEditorState;
  FLineToolbar.BringToFront;

  // 低頻度の厳密配置は右ペインを占有せず、編集メニューからモデルレス表示する。
  FGeometryPopup := TForm.CreateNew(Self);
  FGeometryPopup.BorderIcons := [];
  FGeometryPopup.BorderStyle := bsNone;
  FGeometryPopup.Caption := '配置とサイズ';
  FGeometryPopup.ClientWidth := MulDiv(360, CurrentPPI, 96);
  FGeometryPopup.ClientHeight := MulDiv(207, CurrentPPI, 96);
  FGeometryPopup.Color := $00212121;
  FGeometryPopup.KeyPreview := True;
  FGeometryPopup.OnDeactivate := GeometryPopupDeactivate;
  FGeometryPopup.OnKeyDown := GeometryPopupKeyDown;
  FGeometryPopup.PopupParent := Self;
  FGeometryPopup.Position := poDesigned;
  FGeometryPopupFrame := TMapRakuGeometryPropertiesFrame.Create(
    FGeometryPopup);
  FGeometryPopupFrame.Parent := FGeometryPopup;
  FGeometryPopupFrame.Align := alClient;
  FGeometryPopupFrame.Document := FDocument;
  FGeometryPopupFrame.EditHistory := FEditHistory;
  FGeometryPopupFrame.EditorState := FEditorState;
  FViewMenu := TVectArtDarkPopupMenu.CreateForControls(Self, Self,
    pnlViewMenuButton, pnlViewMenuPopup);
  FMenuGroup := TVectArtDarkMenuGroup.Create(Self);
  FMenuGroup.RegisterMenu(FEditActionsUI.Menu);
  FMenuGroup.RegisterMenu(FViewMenu);
  FObjectContextMenu := TMapRakuObjectContextMenu.Create(Self, Self,
    FMenuGroup, FDocument, FEditorState);
  FObjectContextMenu.EditHistory := FEditHistory;
  FObjectContextMenu.RegisterContributor(
    TMapRakuArrangementMenuContributor.Create(FObjectContextMenu,
      FDocument, FEditHistory, FEditorState));
  FObjectContextMenu.RegisterContributor(
    TMapRakuTransformMenuContributor.Create(FObjectContextMenu,
      FDocument, FEditHistory, FEditorState));
  FObjectContextMenu.RegisterContributor(
    TMapRakuTextMenuContributor.Create(FObjectContextMenu,
      FEditHistory));
  FObjectContextMenu.RegisterContributor(
    TMapRakuPathMenuContributor.Create(FObjectContextMenu,
      FEditHistory));
  FEditorFrame := TEditorWorkspaceFrame.Create(Self);
  FEditorFrame.Context := FDesignerContext;
  FEditorFrame.CanvasControl.OnObjectContextMenu :=
    FObjectContextMenu.ShowForObject;
  AttachFrame(FEditorFrame, pnlEditorHost);

  FDockManager := TVectDockManager.Create(Self, pnlWorkspace,
    pnlLeftDockArea, pnlRightDockArea, pnlLeftDropTarget,
    pnlRightDropTarget, splLeftRegion, splRightRegion);
  FLayerFrame := TLayerPanelFrame.Create(Self);
  FToolPaletteFrame := TToolPaletteFrame.Create(Self);
  FObjectPropertiesFrame := TObjectPropertiesFrame.Create(Self);
  // Context設定は、各Frameが正式なドックスロットへ接続された後に行う。
  FDockManager.RegisterTool(FLayerFrame, vdsLeft);
  FDockManager.RegisterTool(FToolPaletteFrame, vdsLeft);
  FDockManager.RegisterTool(FObjectPropertiesFrame, vdsRight);
  FLayerFrame.Context := FDesignerContext;
  FLayerFrame.LayerList.OnObjectContextMenu :=
    FObjectContextMenu.ShowForObject;
  FToolPaletteFrame.Context := FDesignerContext;
  FObjectPropertiesFrame.Context := FDesignerContext;
  FDockManager.OnToolVisibilityChanged := ToolVisibilityChanged;

  pnlViewMenuPopup.Height := MulDiv(128, CurrentPPI, 96);
  pnlLayoutEditMenuItem.Align := alTop;
  FObjectPropertiesMenuItem := CreateViewMenuItem('Object Properties');
  FToolPaletteMenuItem := CreateViewMenuItem('Tools');
  FLayerMenuItem := CreateViewMenuItem('Layers');

  LayoutFolder := TPath.Combine(TPath.GetDocumentsPath, 'MapRaku');
  FLayoutFileName := TPath.Combine(LayoutFolder, 'MainForm.ini');
  try
    TDirectory.CreateDirectory(LayoutFolder);
  except
    on E: Exception do
      lblStatus.Caption := 'Layout folder error: ' + E.Message;
  end;

  FLayoutEditing := False;
  FViewMenu.Close;
  UpdateLayoutEditMenu;
  UpdateToolMenuItems;
  LoadLayoutSettings;
  FMapToolsPanel := TMapToolsPanel.CreateTools(Self, FDocument,
    FEditorState, FEditHistory, pnlWorkspace);
  InitializeShortcuts;
  HistoryChanged(FEditHistory);
  EditorStateChanged(FEditorState);
  FAutomationPipeStarted := StartMapRakuAutomationPipeServer(Handle,
    FDocument, FEditHistory, FEditorState, FEditorFrame.CanvasControl, ErrorMessage);
  if not FAutomationPipeStarted then
    lblStatus.Caption := 'Codex pipe: ' + ErrorMessage;
end;

procedure TMainForm.CanvasSettingsRequest(Sender: TObject);
var
  CanvasHeight: Integer;
  CanvasWidth: Integer;
  Settings: TMapRakuCanvasColorSettings;
  RailColors: array[0..3] of TColor;
  I: Integer;
begin
  if (FDocument = nil) or (FDocument.CanvasLayer = nil) then
    Exit;
  if ExecuteCanvasSettingsDialog(Self, FDocument.CanvasLayer.Width,
    FDocument.CanvasLayer.Height,FDocument.CanvasLayer,
    CanvasWidth, CanvasHeight, Settings) then
  begin
    if (CanvasWidth <> FDocument.CanvasLayer.Width) or
      (CanvasHeight <> FDocument.CanvasLayer.Height) then
      FDocument.SetCanvasSize(CanvasWidth, CanvasHeight);
    if Settings.DarkMap <> (FDocument.CanvasLayer.BackgroundColor = clBlack) then
    begin
      ApplyMapTheme(FDocument, FEditHistory, Settings.DarkMap);
      if Settings.DarkMap then FEditorState.CreationColor := clWhite
      else FEditorState.CreationColor := clBlack;
    end;
    if Settings.ColorChanged[0] or Settings.ApplyRoadExisting then
      SetMapPlacementPreset(FDocument,FEditHistory,'road',Settings.Colors[0],
        Settings.ApplyRoadExisting);
    if Settings.ColorChanged[1] or Settings.ApplyRiverExisting then
      SetMapPlacementPreset(FDocument,FEditHistory,'river',Settings.Colors[1],
        Settings.ApplyRiverExisting);
    RailColors[0] := FDocument.CanvasLayer.JrPrimaryColor;
    RailColors[1] := FDocument.CanvasLayer.JrSecondaryColor;
    RailColors[2] := FDocument.CanvasLayer.RailPrimaryColor;
    RailColors[3] := FDocument.CanvasLayer.RailSecondaryColor;
    for I := 0 to 3 do
      if Settings.ColorChanged[I+2] then
        RailColors[I] := Settings.Colors[I+2];
    SetMapRailPalette(FDocument,FEditHistory,RailColors[0],RailColors[1],
      RailColors[2],RailColors[3]);
    EditorStateChanged(FEditorState);
  end;
end;

procedure TMainForm.GeometryPopupDeactivate(Sender: TObject);
begin
  if FGeometryPopup <> nil then
    FGeometryPopup.Hide;
end;

procedure TMainForm.GeometryPopupKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key <> VK_ESCAPE then
    Exit;
  // Escでは編集中の文字列をDocumentへ適用せず、確定済み値へ戻して閉じる。
  if FGeometryPopupFrame <> nil then
    FGeometryPopupFrame.RefreshFromDocument;
  FGeometryPopup.Hide;
  Key := 0;
end;

procedure TMainForm.GeometrySettingsRequest(Sender: TObject);
var
  PopupBounds: TRect;
begin
  UpdateGeometrySettingsAvailability;
  if (FEditActionsUI = nil) or
    not FEditActionsUI.GeometrySettingsEnabled or
    (FGeometryPopup = nil) then
    Exit;
  FGeometryPopupFrame.RefreshFromDocument;
  PopupBounds := Rect(Left + (Width - FGeometryPopup.Width) div 2,
    Top + (Height - FGeometryPopup.Height) div 2,
    Left + (Width + FGeometryPopup.Width) div 2,
    Top + (Height + FGeometryPopup.Height) div 2);
  PopupBounds := ConstrainToMonitor(PopupBounds);
  FGeometryPopup.SetBounds(PopupBounds.Left, PopupBounds.Top,
    PopupBounds.Width, PopupBounds.Height);
  FGeometryPopup.Show;
  FGeometryPopup.BringToFront;
  FGeometryPopupFrame.FocusFirstInput;
end;

procedure TMainForm.DocumentChanged(Sender: TObject);
begin
  if FEditorState <> nil then
  begin
    FEditorState.ValidateOpenGroupPath(FDocument);
    FEditorState.ValidateSelectedGradientStop(FDocument);
    FEditorState.ValidateSelectedFilter(FDocument);
  end;
  if FEditActionsUI <> nil then
    FEditActionsUI.RefreshState;
  if FEditorFrame <> nil then
    FEditorFrame.CanvasControl.Invalidate;
  // ドラッグ中はCanvasだけを更新し、重い属性UIの再同期は操作確定時にまとめる。
  if (FDocument <> nil) and FDocument.IsInteractiveUpdate then
    Exit;
  if FLayerFrame <> nil then
    FLayerFrame.RefreshFromDocument;
  if FObjectPropertiesFrame <> nil then
    FObjectPropertiesFrame.RefreshFromDocument;
  if FLineToolbar <> nil then
    FLineToolbar.RefreshState;
  EditorStateChanged(FEditorState);
end;

procedure TMainForm.EnableStandaloneFileActions;
begin
  SetFileDropCaptionEnabled(True);
  if FFileMenu <> nil then
    Exit;
  FEditActionsUI.Menu.Button.Left := MulDiv(56, CurrentPPI, 96);
  pnlViewMenuButton.Left := MulDiv(92, CurrentPPI, 96);
  FFileMenu := TVectArtDarkPopupMenu.CreateForHosts(Self, Self, pnlMenuBar,
    'ファイル', 0, 56, 220, 160);
  FFileMenu.AddItem('地図を開く...    Ctrl+O', 0, FileOpenClick);
  FFileMenu.AddItem('地図を保存...    Ctrl+S', 32, FileSaveClick);
  FFileMenu.AddItem('SVG出力...', 64, ExportClick).Tag := 0;
  FFileMenu.AddItem('PNG出力...', 96, ExportClick).Tag := 1;
  FFileMenu.AddItem('新しい地図', 128, FileNewClick);
  FSavedRevision := FDocument.Revision;
  FMenuGroup.RegisterMenu(FFileMenu);
end;

function TMainForm.ConfirmSave: Boolean;
begin
  Result := True;
  if (FDocument = nil) or (FDocument.Revision = FSavedRevision) then Exit;
  case MessageDlg('地図の変更を保存しますか？', mtConfirmation, [mbYes,mbNo,mbCancel],0) of
    mrCancel: Result := False;
    mrYes: begin SaveDocumentAs; Result := FDocument.Revision = FSavedRevision; end;
  end;
end;
function TMainForm.CloseQuery: Boolean;
begin
  {$IFDEF DEBUG}
  // 自動テストと反復起動を保存確認で停止させない。Releaseでは変更保護を維持する。
  Result := inherited CloseQuery;
  {$ELSE}
  Result := inherited CloseQuery and ConfirmSave;
  {$ENDIF}
end;
procedure TMainForm.FileNewClick(Sender: TObject);
var Empty: TVectArtDocument; ErrorMessage: string;
begin
  FFileMenu.Close;
  if not ConfirmSave then Exit;
  FEditorState.CurrentTool := vetSelect; FEditorState.OpenGroup := nil;
  FEditorState.PendingSymbol := -1;
  FEditorState.ActiveMapPreset := -1;
  Empty := TVectArtDocument.Create;
  try
    FEditHistory.Clear;
    if not TryDeserializeVectArtDocument(SerializeVectArtDocument(Empty),FDocument,ErrorMessage) then
      raise EConvertError.Create(ErrorMessage);
    FCurrentDocumentFileName := ''; FSavedRevision := FDocument.Revision;
    Caption := 'ちずらく — 新しい地図';
  finally Empty.Free; end;
end;
procedure TMainForm.ExportClick(Sender: TObject);
var D: TSaveDialog; Ext: string;
begin
  FFileMenu.Close;
  if TComponent(Sender).Tag = 0 then Ext := 'svg' else Ext := 'png';
  D := TSaveDialog.Create(Self);
  try
    D.DefaultExt := Ext; D.Filter := UpperCase(Ext) + '|*.' + Ext;
    D.FileName := '地図.' + Ext; D.Options := [ofOverwritePrompt, ofPathMustExist];
    if D.Execute then begin
      try
        if Ext = 'svg' then ExportMapSvg(FDocument, D.FileName)
        else ExportMapPng(FDocument, D.FileName);
        lblStatus.Caption := '出力しました: ' + D.FileName;
      except on E: Exception do ShowMessage('出力に失敗しました: ' + E.Message); end;
    end;
  finally D.Free; end;
end;
procedure TMainForm.FileOpenClick(Sender: TObject);
begin
  if FFileMenu <> nil then
    FFileMenu.Close;
  LoadDocument;
end;

procedure TMainForm.FileSaveClick(Sender: TObject);
begin
  if FFileMenu <> nil then
    FFileMenu.Close;
  SaveDocumentAs;
end;

procedure TMainForm.SetReferenceBackgroundRgba(const Pixels: TBytes;
  Width, Height: Integer);
begin
  if (FEditorFrame <> nil) and (FEditorFrame.CanvasControl <> nil) then
    FEditorFrame.CanvasControl.SetReferenceBackgroundRgba(Pixels,
      Width, Height);
end;

procedure TMainForm.SetCanvasSettingsVisible(const Value: Boolean);
begin
  if FEditActionsUI <> nil then
    FEditActionsUI.CanvasSettingsVisible := Value;
end;

procedure TMainForm.EditorStateChanged(Sender: TObject);
var
  CanvasSize: string;
  VertexMode: string;
begin
  UpdateGeometrySettingsAvailability;
  if FEditActionsUI <> nil then
    FEditActionsUI.RefreshState;
  if (FGeometryPopup <> nil) and FGeometryPopup.Visible and
    (FGeometryPopupFrame <> nil) then
    FGeometryPopupFrame.RefreshFromDocument;
  if FEditorFrame <> nil then
  begin
    FEditorFrame.CanvasControl.ApplyPathVertexModeToSelection;
    FEditorFrame.CanvasControl.Invalidate;
  end;
  if FLayerFrame <> nil then
    FLayerFrame.RefreshFromDocument;
  if FObjectPropertiesFrame <> nil then
    FObjectPropertiesFrame.RefreshFromDocument;
  if FToolPaletteFrame <> nil then
    FToolPaletteFrame.RefreshState;
  if FMapToolsPanel <> nil then
    FMapToolsPanel.RefreshState;
  if FLineToolbar <> nil then
    FLineToolbar.RefreshState;
  if (FDocument <> nil) and (FDocument.CanvasLayer <> nil) then
    CanvasSize := Format('%d x %d', [FDocument.CanvasLayer.Width,
      FDocument.CanvasLayer.Height])
  else
    CanvasSize := '-';
  VertexMode := 'Sharp';
  if (FEditorState <> nil) and
    (FEditorState.NextVertexKind = slvkBezier) then
    VertexMode := 'Bezier';
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetRectangleLine) then
    lblStatus.Caption := 'Ready   Tool: Rectangle Line   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetRectangle) then
    lblStatus.Caption := 'Ready   Tool: Rectangle   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetRoundedRectangleLine) then
    lblStatus.Caption := 'Ready   Tool: Rounded Rectangle Line   Canvas: ' +
      CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetRoundedRectangle) then
    lblStatus.Caption := 'Ready   Tool: Rounded Rectangle   Canvas: ' +
      CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetEllipseLine) then
    lblStatus.Caption := 'Ready   Tool: Ellipse Line   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetEllipse) then
    lblStatus.Caption := 'Ready   Tool: Ellipse   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetArc) then
    lblStatus.Caption := 'Ready   Tool: Arc   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetArcShape) then
    lblStatus.Caption := 'Ready   Tool: Arc Shape   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetLine) then
    lblStatus.Caption := 'Ready   Tool: Line   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetFreehand) then
    lblStatus.Caption := 'Freehand: drag to draw one open path   Canvas: ' +
      CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetPath) then
    lblStatus.Caption := 'Path (' + VertexMode +
      '): V sharp / B bezier, click vertices, ' +
      'double-click/right-click to finish   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetShape) then
    lblStatus.Caption := 'Shape (' + VertexMode +
      '): click at least three vertices, then click ' +
      'the first point or double-click/right-click to close   Canvas: ' +
      CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetText) then
    lblStatus.Caption := 'Text: drag an input guide, type, click outside to ' +
      'finish   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetTextPath) then
    lblStatus.Caption := 'Text Path: create an open path for text   Canvas: ' +
      CanvasSize
  else
    lblStatus.Caption := 'Ready   Tool: Select   Canvas: ' + CanvasSize;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
  begin
    lblStatus.Caption := lblStatus.Caption + '   Open group: ' +
      FEditorState.OpenGroup.Name;
    if FEditorState.OpenGroupDepth > 1 then
      lblStatus.Caption := lblStatus.Caption + '   Esc: parent group'
    else
      lblStatus.Caption := lblStatus.Caption + '   Esc: close';
  end;
  if (FEditorState <> nil) and (FEditorState.OpenGroupChild <> nil) then
    lblStatus.Caption := lblStatus.Caption + '   Child: ' +
      FEditorState.OpenGroupChild.Name;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (FEditorFrame <> nil) and FEditorFrame.CanvasControl.TransformDragging then
  begin
    if Key = VK_ESCAPE then FEditorFrame.CanvasControl.CancelTransformDrag;
    Key := 0;
    Exit;
  end;
  if (FFileMenu <> nil) and (Key = Ord('O')) and (Shift = [ssCtrl]) then
  begin
    LoadDocument;
    Key := 0;
    Exit;
  end;
  if (FFileMenu <> nil) and (Key = Ord('S')) and (Shift = [ssCtrl]) then
  begin
    SaveDocumentAs;
    Key := 0;
    Exit;
  end;
  if (FEditorFrame <> nil) and FEditorFrame.CanvasControl.TextEditing then Exit;
  if (Key = VK_ESCAPE) and (FEditorState <> nil) and
    (FEditorState.PendingSymbol >= 0) then
  begin
    FEditorState.PendingSymbol := -1;
    FEditorState.ActiveMapPreset := -1;
    Key := 0;
    Exit;
  end;
  if (FShortcuts <> nil) and FShortcuts.KeyDown(Key, Shift) then
    Exit;
  if (FEditorFrame <> nil) and
    (GetFocus = FEditorFrame.CanvasControl.Handle) and
    HandleSelectionNudge(FDocument, FEditHistory, Key, Shift) then
    Key := 0;
end;

procedure TMainForm.DoShow;
begin
  FObjectPropertiesFrame.LoadColorHistory;
  inherited;
  // AviUtl2内のモーダル表示では生成後にHandleが変わるため、表示時の値へ更新する。
  if FAutomationPipeStarted then
    UpdateMapRakuAutomationPipeNotifyWindow(Handle);
end;

procedure TMainForm.LoadDocument;
var
  ErrorMessage: string;
  OpenDialog: TFileOpenDialog;
  SkippedReferenceCount: Integer;
begin
  if FDocument = nil then
    Exit;
  if not ConfirmSave then Exit;
  OpenDialog := TFileOpenDialog.Create(Self);
  try
    try
      OpenDialog.Title := '地図を開く';
      OpenDialog.DefaultExtension := 'mapraku';
      OpenDialog.Options := [fdoFileMustExist, fdoPathMustExist,
        fdoForceFileSystem];
      with OpenDialog.FileTypes.Add do
      begin
        DisplayName := 'ちずらく地図 (*.mapraku)';
        FileMask := '*.mapraku';
      end;
      OpenDialog.FileTypeIndex := 1;
      if FCurrentDocumentFileName <> '' then
      begin
        OpenDialog.DefaultFolder := ExtractFilePath(
          FCurrentDocumentFileName);
        OpenDialog.FileName := ExtractFileName(FCurrentDocumentFileName);
      end
      else
        OpenDialog.DefaultFolder := TPath.GetDocumentsPath;
      if not OpenDialog.Execute(Handle) then
        Exit;
      if FEditorState <> nil then
        FEditorState.OpenGroup := nil;
      if not TryLoadVectArtDocumentFromJsonFile(OpenDialog.FileName,
        FDocument, SkippedReferenceCount, ErrorMessage) then
        raise EConvertError.Create(ErrorMessage);
      FObjectPropertiesFrame.LoadColorHistory;
      FCurrentDocumentFileName := OpenDialog.FileName;
      FSavedRevision := FDocument.Revision;
      FEditHistory.Clear;
      Caption := 'MapRaku - ' +
        ExtractFileName(FCurrentDocumentFileName);
      if SkippedReferenceCount > 0 then
        lblStatus.Caption := Format('Loaded: %s (%d missing references skipped)',
          [FCurrentDocumentFileName, SkippedReferenceCount])
      else
        lblStatus.Caption := 'Loaded: ' + FCurrentDocumentFileName;
    except
      on E: Exception do
      begin
        lblStatus.Caption := 'Load error: ' + E.Message;
        Application.MessageBox(PChar('JSONの読込に失敗しました。' +
          sLineBreak + E.Message), 'MapRaku',
          MB_OK or MB_ICONERROR);
      end;
    end;
  finally
    OpenDialog.Free;
  end;
end;

procedure TMainForm.SaveDocumentAs;
var
  SaveDialog: TFileSaveDialog;
begin
  if FDocument = nil then
    Exit;
  SaveDialog := TFileSaveDialog.Create(Self);
  try
    try
      SaveDialog.Title := '地図を保存';
      SaveDialog.DefaultExtension := 'mapraku';
      if FCurrentDocumentFileName <> '' then
      begin
        SaveDialog.FileName := ExtractFileName(FCurrentDocumentFileName);
        SaveDialog.DefaultFolder := ExtractFilePath(
          FCurrentDocumentFileName);
      end
      else
      begin
        SaveDialog.FileName := '地図.mapraku';
        SaveDialog.DefaultFolder := TPath.GetDocumentsPath;
      end;
      SaveDialog.Options := [fdoOverWritePrompt, fdoPathMustExist,
        fdoForceFileSystem];
      with SaveDialog.FileTypes.Add do
      begin
        DisplayName := 'ちずらく地図 (*.mapraku)';
        FileMask := '*.mapraku';
      end;
      SaveDialog.FileTypeIndex := 1;
      if not SaveDialog.Execute(Handle) then
        Exit;
      SaveMapFile(FDocument, SaveDialog.FileName);
      FCurrentDocumentFileName := SaveDialog.FileName;
      FSavedRevision := FDocument.Revision;
      Caption := 'MapRaku - ' +
        ExtractFileName(FCurrentDocumentFileName);
      lblStatus.Caption := 'Saved: ' + SaveDialog.FileName;
    except
      on E: Exception do
      begin
        lblStatus.Caption := 'Save error: ' + E.Message;
        Application.MessageBox(PChar('JSONの保存に失敗しました。' +
          sLineBreak + E.Message), 'MapRaku',
          MB_OK or MB_ICONERROR);
      end;
    end;
  finally
    SaveDialog.Free;
  end;
end;

procedure TMainForm.HistoryChanged(Sender: TObject);
begin
  if FEditActionsUI <> nil then
    FEditActionsUI.RefreshState;
end;

function TMainForm.CanExecuteLayerAction(
  Action: TVectArtLayerAction): Boolean;
var
  Operations: TVectArtLayerOperations;
begin
  Result := False;
  if not IsEditingSurfaceFocused or IsTextInputFocused then Exit;
  Operations := TVectArtLayerOperations.Create;
  try
    Operations.Document := FDocument;
    Operations.EditorState := FEditorState;
    Result := Operations.CanExecute(Action);
  finally
    Operations.Free;
  end;
end;

procedure TMainForm.ExecuteLayerAction(Action: TVectArtLayerAction);
var
  Operations: TVectArtLayerOperations;
begin
  Operations := TVectArtLayerOperations.Create;
  try
    Operations.Document := FDocument;
    Operations.EditHistory := FEditHistory;
    Operations.EditorState := FEditorState;
    Operations.Execute(Action);
  finally
    Operations.Free;
  end;
end;

procedure TMainForm.ToolMenuItemClick(Sender: TObject);
begin
  if Sender = FLayerMenuItem then
    FDockManager.SetToolVisible(FLayerFrame,
      not FDockManager.ToolVisible(FLayerFrame))
  else if Sender = FToolPaletteMenuItem then
    FDockManager.SetToolVisible(FToolPaletteFrame,
      not FDockManager.ToolVisible(FToolPaletteFrame))
  else if Sender = FObjectPropertiesMenuItem then
    FDockManager.SetToolVisible(FObjectPropertiesFrame,
      not FDockManager.ToolVisible(FObjectPropertiesFrame));
  FViewMenu.Close;
end;

procedure TMainForm.ToolVisibilityChanged(Sender: TToolPlaceholderFrame);
begin
  UpdateToolMenuItems;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  if FAutomationPipeStarted then
  begin
    StopMapRakuAutomationPipeServer;
    FAutomationPipeStarted := False;
  end;
  if FFileDropCaptionEnabled then
    DragAcceptFiles(Handle, False);
  SaveLayoutSettings;
  FreeAndNil(FShortcuts);
  FreeAndNil(FGeometryPopup);
  FGeometryPopupFrame := nil;
  FreeAndNil(FLineToolbar);
  FDockManager.Free;
  if FDocument <> nil then
    FDocument.OnChanged := nil;
  if FEditorFrame <> nil then
    FEditorFrame.Context := nil;
  if FLayerFrame <> nil then
    FLayerFrame.Context := nil;
  if FObjectPropertiesFrame <> nil then
    FObjectPropertiesFrame.Context := nil;
  if FToolPaletteFrame <> nil then
    FToolPaletteFrame.Context := nil;
  FDesignerContext := nil;
  if FEditorState <> nil then
    FEditorState.OnChanged := nil;
  if FEditHistory <> nil then
    FEditHistory.OnChanged := nil;
  FreeAndNil(FEditActionsUI);
  FreeAndNil(FEditHistory);
  FreeAndNil(FEditorState);
  FreeAndNil(FDocument);
  FinalizeSkiaRuntime;
end;

procedure TMainForm.WMAutomationPipe(var Message: TMessage);
begin
  ProcessMapRakuAutomationPipeMessage(Message.WParam);
  Message.Result := 0;
end;

procedure TMainForm.SetFileDropCaptionEnabled(const Value: Boolean);
begin
  if FFileDropCaptionEnabled = Value then
    Exit;
  FFileDropCaptionEnabled := Value;
  if Value then
    FFileDropCaptionBase := Caption;
  DragAcceptFiles(Handle, Value);
end;

procedure TMainForm.InitializeShortcuts;
begin
  FShortcuts := TShortcutAction.Create;
  FShortcuts.Add(VK_OEM_6, [ssCtrl],
    procedure begin ExecuteLayerAction(vlaMoveForward); end,
    function: Boolean begin Result := CanExecuteLayerAction(vlaMoveForward); end);
  FShortcuts.Add(VK_OEM_4, [ssCtrl],
    procedure begin ExecuteLayerAction(vlaMoveBackward); end,
    function: Boolean begin Result := CanExecuteLayerAction(vlaMoveBackward); end);
  FShortcuts.Add(VK_OEM_6, [ssCtrl, ssShift],
    procedure begin ExecuteLayerAction(vlaMoveToFront); end,
    function: Boolean begin Result := CanExecuteLayerAction(vlaMoveToFront); end);
  FShortcuts.Add(VK_OEM_4, [ssCtrl, ssShift],
    procedure begin ExecuteLayerAction(vlaMoveToBack); end,
    function: Boolean begin Result := CanExecuteLayerAction(vlaMoveToBack); end);
  FShortcuts.Add(Ord('S'), [],
    procedure
    begin
      ActivateToolShortcut(vetSelect);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('R'), [],
    procedure
    begin
      ActivateToolShortcut(vetRectangle);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('U'), [],
    procedure
    begin
      ActivateToolShortcut(vetRoundedRectangle);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('C'), [],
    procedure
    begin
      ActivateToolShortcut(vetEllipse);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('A'), [],
    procedure
    begin
      ActivateToolShortcut(vetArcShape);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('L'), [],
    procedure
    begin
      ActivateToolShortcut(vetLine);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('P'), [],
    procedure
    begin
      ActivateToolShortcut(vetPath);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('G'), [],
    procedure
    begin
      ActivateToolShortcut(vetShape);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('T'), [],
    procedure
    begin
      ActivateToolShortcut(vetText);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('H'), [ssShift],
    procedure
    begin
      FlipMapRakuSelection(FDocument, FEditHistory, FEditorState,
        slfdHorizontal);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and not IsTextInputFocused and
        CanFlipMapRakuSelection(FDocument, FEditorState);
    end);
  FShortcuts.Add(Ord('V'), [ssShift],
    procedure
    begin
      FlipMapRakuSelection(FDocument, FEditHistory, FEditorState,
        slfdVertical);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and not IsTextInputFocused and
        CanFlipMapRakuSelection(FDocument, FEditorState);
    end);
  FShortcuts.Add(Ord('Z'), [ssCtrl],
    procedure
    begin
      FEditHistory.Undo;
    end,
    function: Boolean
    begin
      Result := (FEditHistory <> nil) and not IsTextInputFocused;
    end);
  FShortcuts.Add(Ord('Z'), [ssCtrl, ssShift],
    procedure
    begin
      FEditHistory.Redo;
    end,
    function: Boolean
    begin
      Result := (FEditHistory <> nil) and not IsTextInputFocused;
    end);
  FShortcuts.Add(Ord('Y'), [ssCtrl],
    procedure
    begin
      FEditHistory.Redo;
    end,
    function: Boolean
    begin
      Result := (FEditHistory <> nil) and not IsTextInputFocused;
    end);
  FShortcuts.Add(Ord('A'), [ssCtrl],
    procedure
    begin
      SelectAllLayers;
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FDocument <> nil) and
        (FDocument.LayerCount > 1);
    end);
  FShortcuts.Add(Ord('C'), [ssCtrl],
    procedure
    begin
      CopyObjects(FDocument, FEditorState);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (Length(ClipboardSelection(FDocument, FEditorState)) > 0);
    end);
  FShortcuts.Add(Ord('V'), [ssCtrl],
    procedure
    begin
      PasteObjects(FDocument, FEditorState, FEditHistory);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and CanPasteObjects(FEditorState);
    end);
  FShortcuts.Add(Ord('X'), [ssCtrl],
    procedure
    begin
      CopyObjects(FDocument, FEditorState);
      FLayerFrame.RunLayerAction(vlaDelete);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FLayerFrame <> nil) and FLayerFrame.CanRunLayerAction(vlaDelete);
    end);
  FShortcuts.Add(Ord('D'), [ssCtrl],
    procedure
    begin
      FLayerFrame.RunLayerAction(vlaDuplicate);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FLayerFrame <> nil) and
        FLayerFrame.CanRunLayerAction(vlaDuplicate);
    end);
  FShortcuts.Add(Ord('G'), [ssCtrl],
    procedure
    begin
      GroupCurrentSelection(FDocument, FEditHistory, FEditorState);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and
        CanGroupCurrentSelection(FDocument, FEditorState);
    end);
  FShortcuts.Add(Ord('G'), [ssCtrl, ssShift],
    procedure
    begin
      UngroupCurrentSelection(FDocument, FEditHistory, FEditorState);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and
        CanUngroupCurrentSelection(FDocument, FEditorState);
    end);
  FShortcuts.Add(VK_DELETE, [],
    procedure
    begin
      FLayerFrame.RunLayerAction(vlaDelete);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FLayerFrame <> nil) and
        FLayerFrame.CanRunLayerAction(vlaDelete);
    end);
  FShortcuts.Add(VK_ESCAPE, [],
    procedure
    begin
      if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
        FEditorState.OpenParentGroup
      else
        FDocument.SetSelectedLayers([]);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FDocument <> nil) and
        ((FDocument.SelectionCount > 0) or
         ((FEditorState <> nil) and (FEditorState.OpenGroup <> nil)));
    end);
end;

function TMainForm.IsEditingSurfaceFocused: Boolean;
begin
  Result := ((FEditorFrame <> nil) and
    (GetFocus = FEditorFrame.CanvasControl.Handle)) or
    ((FLayerFrame <> nil) and
    (GetFocus = FLayerFrame.LayerList.Handle));
end;

function TMainForm.IsTextInputFocused: Boolean;
var
  FocusedControl: TWinControl;
begin
  FocusedControl := FindControl(GetFocus);
  Result := (FocusedControl is TCustomEdit) or
    (FocusedControl is TCustomComboBox);
end;

function TMainForm.ToolShortcutEnabled: Boolean;
begin
  Result := (FEditorState <> nil) and not IsTextInputFocused;
end;

procedure TMainForm.SelectAllLayers;
var
  Layers: TArray<TVectArtLayer>;
  I: Integer;
  Indices: TArray<Integer>;
begin
  if FDocument = nil then Exit;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
  begin
    SetLength(Layers, FEditorState.OpenGroup.ChildCount);
    for I := 0 to High(Layers) do Layers[I] := FEditorState.OpenGroup[I];
    FEditorState.SetOpenGroupChildren(Layers);
    Exit;
  end;
  SetLength(Indices, FDocument.LayerCount - 1);
  for I := 1 to FDocument.LayerCount - 1 do
    Indices[I - 1] := I;
  FDocument.SetSelectedLayers(Indices);
end;

procedure TMainForm.FinalizeSkiaRuntime;
begin
  if not FSkiaAcquired then
    Exit;
  TTextRendererSkiaRuntime.Release;
  FSkiaAcquired := False;
end;

procedure TMainForm.InitializeSkiaRuntime;
begin
  try
    TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
    FSkiaAcquired := True;
  except
    on E: Exception do
      lblStatus.Caption := 'Skia runtime error: ' + E.Message;
  end;
end;

procedure TMainForm.LoadLayoutSettings;
var
  Bounds: TRect;
  Ini: TMemIniFile;
  LayoutVersion: Integer;
  SavedHeight: Integer;
  SavedWidth: Integer;
begin
  if (FLayoutFileName = '') or not TFile.Exists(FLayoutFileName) then
    Exit;
  Ini := nil;
  try
    try
      Ini := TMemIniFile.Create(FLayoutFileName, TEncoding.UTF8);
      LayoutVersion := Ini.ReadInteger('File', 'Version', 0);
      if not (LayoutVersion in [1, 2]) then
        Exit;
      SavedWidth := Max(MulDiv(Ini.ReadInteger('MainForm', 'Width',
        MulDiv(Width, 96, CurrentPPI)), CurrentPPI, 96),
        Constraints.MinWidth);
      SavedHeight := Max(MulDiv(Ini.ReadInteger('MainForm', 'Height',
        MulDiv(Height, 96, CurrentPPI)), CurrentPPI, 96),
        Constraints.MinHeight);
      Bounds := Rect(
        Ini.ReadInteger('MainForm', 'Left', Left),
        Ini.ReadInteger('MainForm', 'Top', Top), 0, 0);
      Bounds.Right := Bounds.Left + SavedWidth;
      Bounds.Bottom := Bounds.Top + SavedHeight;
      Bounds := ConstrainToMonitor(Bounds);
      SetBounds(Bounds.Left, Bounds.Top, Bounds.Width, Bounds.Height);
      FDockManager.LoadLayout(Ini);
      if SameText(Ini.ReadString('MainForm', 'WindowState', 'Normal'),
        'Maximized') then
        WindowState := wsMaximized
      else
        WindowState := wsNormal;
      UpdateToolMenuItems;
    except
      on E: Exception do
        lblStatus.Caption := 'Layout load error: ' + E.Message;
    end;
  finally
    Ini.Free;
  end;
end;

procedure TMainForm.SaveLayoutSettings;
var
  Ini: TMemIniFile;
  Placement: TWindowPlacement;
  SavedBounds: TRect;
begin
  if FindCmdLineSwitch('test',True) then Exit;
  if (FLayoutFileName = '') or (FDockManager = nil) then
    Exit;
  Ini := nil;
  try
    try
      Ini := TMemIniFile.Create(FLayoutFileName, TEncoding.UTF8);
      Placement.Length := SizeOf(Placement);
      if GetWindowPlacement(Handle, @Placement) then
        SavedBounds := Placement.rcNormalPosition
      else
        SavedBounds := BoundsRect;
      Ini.WriteInteger('File', 'Version', 2);
      Ini.WriteInteger('MainForm', 'Left', SavedBounds.Left);
      Ini.WriteInteger('MainForm', 'Top', SavedBounds.Top);
      Ini.WriteInteger('MainForm', 'Width',
        MulDiv(SavedBounds.Width, 96, CurrentPPI));
      Ini.WriteInteger('MainForm', 'Height',
        MulDiv(SavedBounds.Height, 96, CurrentPPI));
      if WindowState = wsMaximized then
        Ini.WriteString('MainForm', 'WindowState', 'Maximized')
      else
        Ini.WriteString('MainForm', 'WindowState', 'Normal');
      FDockManager.SaveLayout(Ini);
      Ini.UpdateFile;
    except
      on E: Exception do
        lblStatus.Caption := 'Layout save error: ' + E.Message;
    end;
  finally
    Ini.Free;
  end;
end;

procedure TMainForm.UpdateToolMenuItems;
begin
  FLayerMenuItem.Caption := CheckedMenuCaption(
    FDockManager.ToolVisible(FLayerFrame), 'Layers');
  FToolPaletteMenuItem.Caption := CheckedMenuCaption(
    FDockManager.ToolVisible(FToolPaletteFrame), 'Tools');
  FObjectPropertiesMenuItem.Caption := CheckedMenuCaption(
    FDockManager.ToolVisible(FObjectPropertiesFrame), 'Object Properties');
end;

procedure TMainForm.UpdateGeometrySettingsAvailability;
var
  Available: Boolean;
begin
  // 開いたグループでは直下の単一選択を優先し、それ以外はDocument選択を対象にする。
  Available := (FDocument <> nil) and
    (((FEditorState <> nil) and
      (FEditorState.OpenGroupChildCount = 1)) or
     (FDocument.SelectionCount > 0));
  if FEditActionsUI <> nil then
    FEditActionsUI.GeometrySettingsEnabled := Available;
  if not Available and (FGeometryPopup <> nil) then
    FGeometryPopup.Hide;
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  if FDockManager <> nil then
    FDockManager.Resize;
end;

procedure TMainForm.lblLayoutEditMenuItemClick(Sender: TObject);
begin
  SetLayoutEditing(not FLayoutEditing);
  FViewMenu.Close;
end;

procedure TMainForm.SetLayoutEditing(const Value: Boolean);
begin
  if FLayoutEditing = Value then
    Exit;
  FLayoutEditing := Value;
  FDockManager.LayoutEditing := Value;
  UpdateLayoutEditMenu;
end;

procedure TMainForm.UpdateLayoutEditMenu;
begin
  if FLayoutEditing then
    pnlLayoutEditMenuItem.Caption := '✓ レイアウト編集'
  else
    pnlLayoutEditMenuItem.Caption := '□ レイアウト編集';
end;

procedure TMainForm.WMDropFiles(var Message: TWMDropFiles);
var
  CanvasClientPoint: TPoint;
  DropPoint: TPoint;
  DropScreenPoint: TPoint;
  DroppedFileNames: TArray<string>;
  ErrorMessage: string;
  FileCount: UINT;
  FileIndex: UINT;
  FileNameLength: UINT;
  ImportedCount: Integer;
  LogicalDropPoint: TPointF;
begin
  Message.Result := 0;
  try
    FileCount := DragQueryFile(Message.Drop, $FFFFFFFF, nil, 0);
    if FileCount = 0 then
      Exit;
    SetLength(DroppedFileNames, FileCount);
    for FileIndex := 0 to FileCount - 1 do
    begin
      FileNameLength := DragQueryFile(Message.Drop, FileIndex, nil, 0);
      SetLength(DroppedFileNames[FileIndex], FileNameLength);
      DragQueryFile(Message.Drop, FileIndex,
        PChar(DroppedFileNames[FileIndex]), FileNameLength + 1);
    end;

    LogicalDropPoint := TPointF.Zero;
    if DragQueryPoint(Message.Drop, DropPoint) and
      (FEditorFrame <> nil) and (FEditorFrame.CanvasControl <> nil) then
    begin
      DropScreenPoint := ClientToScreen(DropPoint);
      CanvasClientPoint := FEditorFrame.CanvasControl.ScreenToClient(
        DropScreenPoint);
      FEditorFrame.CanvasControl.TryClientPointToLogical(CanvasClientPoint,
        LogicalDropPoint);
    end;
    ImportedCount := ImportMapRakuImageFiles(FDocument, FEditHistory,
      DroppedFileNames, LogicalDropPoint, ErrorMessage);
    if ImportedCount > 0 then
    begin
      FEditorState.CurrentTool := vetSelect;
      lblStatus.Caption := Format('%d image(s) imported', [ImportedCount]);
      if ErrorMessage <> '' then
        lblStatus.Caption := lblStatus.Caption + '  ' + ErrorMessage;
      if FFileDropCaptionEnabled and (Length(DroppedFileNames) = 1) then
        Caption := FFileDropCaptionBase + ' - ' +
          ExtractFileName(DroppedFileNames[0]);
    end
    else if ErrorMessage <> '' then
      lblStatus.Caption := 'Image import failed: ' + ErrorMessage;
  finally
    DragFinish(Message.Drop);
  end;
end;

end.
