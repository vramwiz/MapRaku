// Editメニュー、配置ポップアップの要求、コード描画Undo／Redoショートカットを管理する。
unit MapRakuEditActionsUI;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  VectArtDarkPopupMenu, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState;

type
  TVectArtEditShortcutControl = class(TCustomControl)
  private
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FHistory: TVectArtEditHistory;
    function ButtonEnabled(Index: Integer): Boolean;
    function ButtonRect(Index: Integer): TRect;
    function CanApplyShapeBoolean: Boolean;
    procedure DrawButton(Index: Integer; const Caption: string);
    procedure DrawIcon(Index: Integer; const Bounds: TRect);
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetEditorState(const Value: TVectArtEditorState);
    procedure SetHistory(const Value: TVectArtEditHistory);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
  public
    // Undo／Redoと図形論理演算のコード描画ボタンを生成する。
    constructor Create(AOwner: TComponent); override;
    // 履歴と選択状態から各ボタンの有効状態を再計算する。
    procedure RefreshState;
    // DocumentとHistoryは非所有参照であり、交換時に表示を再同期する。
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditorState: TVectArtEditorState read FEditorState
      write SetEditorState;
    property History: TVectArtEditHistory read FHistory write SetHistory;
  end;

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
    FShortcutControl: TVectArtEditShortcutControl;
    FUndoItem: TPanel;
    procedure CanvasSettingsClick(Sender: TObject);
    procedure GeometrySettingsClick(Sender: TObject);
    function NewMenuItem(const Caption: string; Top: Integer;
      ClickHandler: TNotifyEvent): TPanel;
    procedure RedoClick(Sender: TObject);
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetEditorState(const Value: TVectArtEditorState);
    procedure SetHistory(const Value: TVectArtEditHistory);
    procedure SetCanvasSettingsVisible(const Value: Boolean);
    procedure SetGeometrySettingsEnabled(const Value: Boolean);
    procedure UndoClick(Sender: TObject);
  public
    // メニューとショートカットUIを各Hostへ生成し、初期状態を同期する。
    constructor CreateForHosts(AOwner: TComponent; AMainForm,
      AMenuBar, AShortcutHost: TWinControl);
    // 履歴、選択、図形演算可否を各メニュー項目とショートカットへ反映する。
    procedure RefreshState;
    // DocumentとHistoryは非所有参照であり、交換時にメニューを再同期する。
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditorState: TVectArtEditorState read FEditorState
      write SetEditorState;
    property History: TVectArtEditHistory read FHistory write SetHistory;
    // Editボタンとポップアップを所有するメニューUI。
    property Menu: TVectArtDarkPopupMenu read FMenu;
    // 単独アプリだけが持つキャンバス設定項目の表示を切り替える。
    property CanvasSettingsVisible: Boolean read FCanvasSettingsVisible
      write SetCanvasSettingsVisible;
    // 選択がなく配置対象を確定できない間は、配置とサイズ項目を無効化する。
    property GeometrySettingsEnabled: Boolean read FGeometrySettingsEnabled
      write SetGeometrySettingsEnabled;
    // キャンバス設定Dialogを所有する呼び出し側へ表示を要求する。
    property OnCanvasSettingsRequest: TNotifyEvent
      read FOnCanvasSettingsRequest write FOnCanvasSettingsRequest;
    // メニュー自身は編集せず、ポップアップ表示を所有する呼び出し側へ要求する。
    property OnGeometrySettingsRequest: TNotifyEvent
      read FOnGeometrySettingsRequest write FOnGeometrySettingsRequest;
  end;

implementation

uses
  Vcl.Graphics, Winapi.Windows, MapRakuLayerFlipOperations,
  MapRakuShapeBooleanOperations;

const
  BUTTON_UNDO_INDEX      = 0;
  BUTTON_REDO_INDEX      = 1;
  BUTTON_FLIP_H_INDEX    = 2;
  BUTTON_FLIP_V_INDEX    = 3;
  BUTTON_UNION_INDEX     = 4;
  BUTTON_SUBTRACT_INDEX  = 5;
  BUTTON_INTERSECT_INDEX = 6;
  BUTTON_XOR_INDEX       = 7;
  BUTTON_COUNT           = 8;
  BUTTON_WIDTH           = 78;
  COLOR_BACKGROUND = TColor($00282828);
  COLOR_BUTTON = TColor($00303030);
  COLOR_DISABLED = TColor($00757575);
  COLOR_TEXT = TColor($00E6E6E6);

{ TVectArtEditShortcutControl }

function TVectArtEditShortcutControl.ButtonEnabled(Index: Integer): Boolean;
begin
  case Index of
    BUTTON_UNDO_INDEX: Result := (FHistory <> nil) and FHistory.CanUndo;
    BUTTON_REDO_INDEX: Result := (FHistory <> nil) and FHistory.CanRedo;
    BUTTON_FLIP_H_INDEX, BUTTON_FLIP_V_INDEX:
      Result := CanFlipMapRakuSelection(FDocument, FEditorState);
    BUTTON_UNION_INDEX..BUTTON_XOR_INDEX: Result := CanApplyShapeBoolean;
  else
    Result := False;
  end;
end;

function TVectArtEditShortcutControl.ButtonRect(Index: Integer): TRect;
begin
  Result := Rect(Index * BUTTON_WIDTH, 0, (Index + 1) * BUTTON_WIDTH,
    MulDiv(ClientHeight, 96, CurrentPPI));
end;

function TVectArtEditShortcutControl.CanApplyShapeBoolean: Boolean;
begin
  Result := CanExecuteMapRakuShapeBoolean(FDocument);
end;

constructor TVectArtEditShortcutControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
end;

procedure TVectArtEditShortcutControl.DrawButton(Index: Integer;
  const Caption: string);
var
  Bounds: TRect;
begin
  Bounds := ButtonRect(Index);
  Canvas.Brush.Color := COLOR_BUTTON;
  Canvas.FillRect(Bounds);
  DrawIcon(Index, Rect(Bounds.Left + 7, Bounds.Top + 10,
    Bounds.Left + 27, Bounds.Top + 30));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -12;
  if ButtonEnabled(Index) then
    Canvas.Font.Color := COLOR_TEXT
  else
    Canvas.Font.Color := COLOR_DISABLED;
  Canvas.TextOut(Bounds.Left + 32,
    Bounds.Top + (Bounds.Height - Canvas.TextHeight(Caption)) div 2,
    Caption);
end;

procedure TVectArtEditShortcutControl.DrawIcon(Index: Integer;
  const Bounds: TRect);
var
  IconColor: TColor;
begin
  Canvas.Pen.Width := 1;
  if ButtonEnabled(Index) then
    IconColor := COLOR_TEXT
  else
    IconColor := COLOR_DISABLED;
  Canvas.Pen.Color := IconColor;
  Canvas.Brush.Style := bsClear;
  case Index of
    BUTTON_UNDO_INDEX, BUTTON_REDO_INDEX:
      begin
        Canvas.Arc(Bounds.Left + 3, Bounds.Top + 4, Bounds.Right - 3,
          Bounds.Bottom - 2, Bounds.Right - 4, Bounds.Top + 7,
          Bounds.Left + 4, Bounds.Top + 7);
        if Index = BUTTON_UNDO_INDEX then
        begin
          Canvas.MoveTo(Bounds.Left + 3, Bounds.Top + 7);
          Canvas.LineTo(Bounds.Left + 8, Bounds.Top + 3);
          Canvas.MoveTo(Bounds.Left + 3, Bounds.Top + 7);
          Canvas.LineTo(Bounds.Left + 8, Bounds.Top + 11);
        end
        else
        begin
          Canvas.MoveTo(Bounds.Right - 3, Bounds.Top + 7);
          Canvas.LineTo(Bounds.Right - 8, Bounds.Top + 3);
          Canvas.MoveTo(Bounds.Right - 3, Bounds.Top + 7);
          Canvas.LineTo(Bounds.Right - 8, Bounds.Top + 11);
        end;
      end;
    BUTTON_FLIP_H_INDEX:
      begin
        Canvas.MoveTo(Bounds.Left + 10, Bounds.Top + 1);
        Canvas.LineTo(Bounds.Left + 10, Bounds.Bottom);
        Canvas.MoveTo(Bounds.Left + 8, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Left + 2, Bounds.Top + 10);
        Canvas.MoveTo(Bounds.Left + 2, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Left + 5, Bounds.Top + 7);
        Canvas.MoveTo(Bounds.Left + 2, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Left + 5, Bounds.Top + 13);
        Canvas.MoveTo(Bounds.Left + 12, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Right - 1, Bounds.Top + 10);
        Canvas.MoveTo(Bounds.Right - 1, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Right - 4, Bounds.Top + 7);
        Canvas.MoveTo(Bounds.Right - 1, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Right - 4, Bounds.Top + 13);
      end;
    BUTTON_FLIP_V_INDEX:
      begin
        Canvas.MoveTo(Bounds.Left + 1, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Right, Bounds.Top + 10);
        Canvas.MoveTo(Bounds.Left + 10, Bounds.Top + 8);
        Canvas.LineTo(Bounds.Left + 10, Bounds.Top + 2);
        Canvas.MoveTo(Bounds.Left + 10, Bounds.Top + 2);
        Canvas.LineTo(Bounds.Left + 7, Bounds.Top + 5);
        Canvas.MoveTo(Bounds.Left + 10, Bounds.Top + 2);
        Canvas.LineTo(Bounds.Left + 13, Bounds.Top + 5);
        Canvas.MoveTo(Bounds.Left + 10, Bounds.Top + 12);
        Canvas.LineTo(Bounds.Left + 10, Bounds.Bottom - 1);
        Canvas.MoveTo(Bounds.Left + 10, Bounds.Bottom - 1);
        Canvas.LineTo(Bounds.Left + 7, Bounds.Bottom - 4);
        Canvas.MoveTo(Bounds.Left + 10, Bounds.Bottom - 1);
        Canvas.LineTo(Bounds.Left + 13, Bounds.Bottom - 4);
      end;
    BUTTON_UNION_INDEX:
      begin
        Canvas.Rectangle(Bounds.Left + 2, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 1);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 2,
          Bounds.Right - 1, Bounds.Bottom - 6);
        Canvas.MoveTo(Bounds.Left + 8, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Right - 5, Bounds.Top + 10);
        Canvas.MoveTo(Bounds.Left + 11, Bounds.Top + 7);
        Canvas.LineTo(Bounds.Left + 11, Bounds.Bottom - 5);
      end;
    BUTTON_SUBTRACT_INDEX:
      begin
        Canvas.Rectangle(Bounds.Left + 2, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 1);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 2,
          Bounds.Right - 1, Bounds.Bottom - 6);
        Canvas.MoveTo(Bounds.Left + 9, Bounds.Top + 9);
        Canvas.LineTo(Bounds.Right - 3, Bounds.Top + 9);
      end;
    BUTTON_INTERSECT_INDEX:
      begin
        Canvas.Rectangle(Bounds.Left + 2, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 1);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 2,
          Bounds.Right - 1, Bounds.Bottom - 6);
        Canvas.Brush.Color := IconColor;
        Canvas.Brush.Style := bsSolid;
        Canvas.FillRect(Rect(Bounds.Left + 7, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 6));
        Canvas.Brush.Style := bsClear;
      end;
    BUTTON_XOR_INDEX:
      begin
        Canvas.Rectangle(Bounds.Left + 2, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 1);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 2,
          Bounds.Right - 1, Bounds.Bottom - 6);
        Canvas.MoveTo(Bounds.Left + 8, Bounds.Top + 7);
        Canvas.LineTo(Bounds.Right - 5, Bounds.Bottom - 6);
        Canvas.MoveTo(Bounds.Right - 5, Bounds.Top + 7);
        Canvas.LineTo(Bounds.Left + 8, Bounds.Bottom - 6);
      end;
  end;
end;

procedure TVectArtEditShortcutControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  if Button = mbLeft then
  begin
    Index := MulDiv(X, 96, CurrentPPI) div BUTTON_WIDTH;
    if (Index >= 0) and (Index < BUTTON_COUNT) then
    begin
      if (Index = BUTTON_UNDO_INDEX) and (FHistory <> nil) and
        FHistory.CanUndo then
        FHistory.Undo
      else if (Index = BUTTON_REDO_INDEX) and (FHistory <> nil) and
        FHistory.CanRedo then
        FHistory.Redo
      else if (Index = BUTTON_FLIP_H_INDEX) and
        CanFlipMapRakuSelection(FDocument, FEditorState) then
        FlipMapRakuSelection(FDocument, FHistory, FEditorState,
          slfdHorizontal)
      else if (Index = BUTTON_FLIP_V_INDEX) and
        CanFlipMapRakuSelection(FDocument, FEditorState) then
        FlipMapRakuSelection(FDocument, FHistory, FEditorState,
          slfdVertical)
      else if (Index = BUTTON_UNION_INDEX) and CanApplyShapeBoolean then
        ExecuteMapRakuShapeBoolean(FDocument, FHistory, slsboUnion)
      else if (Index = BUTTON_SUBTRACT_INDEX) and CanApplyShapeBoolean then
        ExecuteMapRakuShapeBoolean(FDocument, FHistory, slsboSubtract)
      else if (Index = BUTTON_INTERSECT_INDEX) and CanApplyShapeBoolean then
        ExecuteMapRakuShapeBoolean(FDocument, FHistory, slsboIntersect)
      else if (Index = BUTTON_XOR_INDEX) and CanApplyShapeBoolean then
        ExecuteMapRakuShapeBoolean(FDocument, FHistory, slsboXor);
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtEditShortcutControl.Paint;
const
  CAPTIONS: array[0..BUTTON_COUNT - 1] of string =
    ('Undo', 'Redo', '左右', '上下', '加算', '減算', 'AND', 'XOR');
var
  I: Integer;
  LogicalBounds: TRect;
  SavedDC: Integer;
begin
  SavedDC := SaveDC(Canvas.Handle);
  try
    SetMapMode(Canvas.Handle, MM_ANISOTROPIC);
    SetWindowExtEx(Canvas.Handle, 96, 96, nil);
    SetViewportExtEx(Canvas.Handle, CurrentPPI, CurrentPPI, nil);
    LogicalBounds := Rect(0, 0, MulDiv(ClientWidth, 96, CurrentPPI),
      MulDiv(ClientHeight, 96, CurrentPPI));
    Canvas.Brush.Color := COLOR_BACKGROUND;
    Canvas.FillRect(LogicalBounds);
    for I := 0 to BUTTON_COUNT - 1 do
      DrawButton(I, CAPTIONS[I]);
  finally
    RestoreDC(Canvas.Handle, SavedDC);
  end;
end;

procedure TVectArtEditShortcutControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  Index: Integer;
begin
  Index := MulDiv(X, 96, CurrentPPI) div BUTTON_WIDTH;
  if (Index < 0) or (Index >= BUTTON_COUNT) then
  begin
    Hint := '';
    inherited MouseMove(Shift, X, Y);
    Exit;
  end;
  case Index of
    BUTTON_UNDO_INDEX: Hint := '元に戻す';
    BUTTON_REDO_INDEX: Hint := 'やり直す';
    BUTTON_FLIP_H_INDEX: Hint := '選択を左右反転 (Shift+H)';
    BUTTON_FLIP_V_INDEX: Hint := '選択を上下反転 (Shift+V)';
    BUTTON_UNION_INDEX: Hint := '選択したShapeを加算';
    BUTTON_SUBTRACT_INDEX:
      Hint := 'アクティブShapeからほかの選択Shapeを減算';
    BUTTON_INTERSECT_INDEX: Hint := '選択したShapeの共通部分を残す';
    BUTTON_XOR_INDEX: Hint := '選択したShapeの重ならない部分を残す';
  end;
  inherited MouseMove(Shift, X, Y);
end;

procedure TVectArtEditShortcutControl.RefreshState;
begin
  Invalidate;
end;

procedure TVectArtEditShortcutControl.SetHistory(
  const Value: TVectArtEditHistory);
begin
  FHistory := Value;
  RefreshState;
end;

procedure TVectArtEditShortcutControl.SetDocument(
  const Value: TVectArtDocument);
begin
  FDocument := Value;
  RefreshState;
end;

procedure TVectArtEditShortcutControl.SetEditorState(
  const Value: TVectArtEditorState);
begin
  FEditorState := Value;
  RefreshState;
end;

{ TVectArtEditActionsUI }

constructor TVectArtEditActionsUI.CreateForHosts(AOwner: TComponent;
  AMainForm, AMenuBar, AShortcutHost: TWinControl);
begin
  inherited Create(AOwner);
  FMenu := TVectArtDarkPopupMenu.CreateForHosts(Self, AMainForm, AMenuBar,
    '編集', 0, 36, 190, 128);
  FUndoItem := NewMenuItem('Undo    Ctrl+Z', 0, UndoClick);
  FRedoItem := NewMenuItem('Redo    Ctrl+Y', 32, RedoClick);
  FGeometrySettingsItem := NewMenuItem('配置とサイズ...', 64,
    GeometrySettingsClick);
  FGeometrySettingsEnabled := False;
  FCanvasSettingsItem := NewMenuItem('キャンバスの設定', 96,
    CanvasSettingsClick);
  FCanvasSettingsVisible := True;

  FShortcutControl := TVectArtEditShortcutControl.Create(Self);
  FShortcutControl.Parent := AShortcutHost;
  FShortcutControl.Align := alClient;
  FShortcutControl.ShowHint := True;
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
begin
  FShortcutControl.RefreshState;
  FUndoItem.Enabled := (FHistory <> nil) and FHistory.CanUndo;
  FRedoItem.Enabled := (FHistory <> nil) and FHistory.CanRedo;
  if FUndoItem.Enabled then FUndoItem.Font.Color := COLOR_TEXT
  else FUndoItem.Font.Color := COLOR_DISABLED;
  if FRedoItem.Enabled then FRedoItem.Font.Color := COLOR_TEXT
  else FRedoItem.Font.Color := COLOR_DISABLED;
  FGeometrySettingsItem.Enabled := FGeometrySettingsEnabled;
  if FGeometrySettingsItem.Enabled then
    FGeometrySettingsItem.Font.Color := COLOR_TEXT
  else
    FGeometrySettingsItem.Font.Color := COLOR_DISABLED;
end;

procedure TVectArtEditActionsUI.SetDocument(const Value: TVectArtDocument);
begin
  FDocument := Value;
  FShortcutControl.Document := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.SetEditorState(
  const Value: TVectArtEditorState);
begin
  FEditorState := Value;
  FShortcutControl.EditorState := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.SetHistory(const Value: TVectArtEditHistory);
begin
  FHistory := Value;
  FShortcutControl.History := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.SetCanvasSettingsVisible(
  const Value: Boolean);
begin
  FCanvasSettingsVisible := Value;
  FCanvasSettingsItem.Visible := Value;
  if Value then
    FMenu.PopupHeight := 128
  else
    FMenu.PopupHeight := 96;
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

end.
