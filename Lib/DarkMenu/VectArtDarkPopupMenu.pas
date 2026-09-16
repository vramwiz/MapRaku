// ダーク表示のドロップダウン、任意位置ポップアップ、階層サブメニューの生成と配置を担当する。
// メニュー項目が実行する機能は利用側へ委譲し、子メニューの所有権は変更しない。
// 複数のルートメニューをまたぐ排他制御とアプリケーションメッセージ監視は担当しない。
unit VectArtDarkPopupMenu;

interface

uses
  System.Classes, System.Generics.Collections, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Graphics, Winapi.Windows;

const
  VECTART_DARK_MENU_ACTIVE_COLOR = TColor($00613F20); // 開いている子メニューの親と共通UIの選択背景。
  VECTART_DARK_MENU_ACCENT_COLOR = TColor($00E89A45); // アクティブ項目の左端と外枠。

type
  TVectArtDarkPopupMenu = class(TComponent)
  private
    FButton: TPanel;
    FActiveSubMenuItem: TPanel; // 表示中の子メニューを開いた親項目。子が閉じるまで強調する。
    FChildMenus: TList<TVectArtDarkPopupMenu>; // このメニューから開く子への非所有参照。
    FHoveredItem: TPanel;       // 現在ポインターがある項目。親項目の固定強調とは独立する。
    FMainForm: TWinControl;
    FOnHover: TNotifyEvent;
    FOnOpening: TNotifyEvent;
    FParentMenu: TVectArtDarkPopupMenu; // 親メニューへの非所有参照。ルートではnil。
    FPopup: TPanel;
    FSubMenus: TDictionary<TPanel, TVectArtDarkPopupMenu>; // 項目Panelと子メニューの対応。
    procedure ButtonClick(Sender: TObject);
    procedure ButtonMouseEnter(Sender: TObject);
    procedure CloseChildMenus(ExceptMenu: TVectArtDarkPopupMenu = nil);
    function GetPopupHeight: Integer;
    function GetVisible: Boolean;
    procedure InitializeControls(AButton, APopup: TPanel);
    procedure ItemMouseEnter(Sender: TObject);
    procedure ItemMouseLeave(Sender: TObject);
    procedure OpenAtScreenPointCore(const ScreenPoint: TPoint;
      NotifyOpening: Boolean);
    procedure OpenSubMenu(Item: TPanel;
      SubMenu: TVectArtDarkPopupMenu);
    procedure SetActiveSubMenuItem(Item: TPanel);
    procedure SetPopupHeight(const Value: Integer);
    procedure SubMenuItemClick(Sender: TObject);
  public
    // メニューバー上へトップボタンとポップアップを新規生成し、両ControlをこのComponentが所有する。
    constructor CreateForHosts(AOwner: TComponent; AMainForm,
      AMenuBar: TWinControl; const ACaption: string; ButtonLeft,
      ButtonWidth, PopupWidth, PopupHeight: Integer); reintroduce;
    // DFMなどで別Ownerが所有する既存Controlへ接続する。Controlの所有権は変更しない。
    constructor CreateForControls(AOwner: TComponent; AMainForm: TWinControl;
      AButton, APopup: TPanel); reintroduce;
    // メニューバーを持たず、任意座標または親項目から開くポップアップを生成する。
    constructor CreatePopup(AOwner: TComponent; AMainForm: TWinControl;
      PopupWidth, PopupHeight: Integer); reintroduce;
    // 親子メニュー間の非所有参照を解除してから、内部生成したPanelと対応表を破棄する。
    destructor Destroy; override;
    // ポップアップへ高さ32pxの項目を追加し、返したPanelから表示状態などを個別調整できる。
    function AddItem(const ACaption: string; Top: Integer;
      ClickHandler: TNotifyEvent): TPanel; overload;
    // 名称とショートカットを別列として追加し、各項目の文字位置を揃える。
    function AddItem(const ACaption, AShortcut: string; Top: Integer;
      ClickHandler: TNotifyEvent): TPanel; overload;
    // 子メニューを持つ項目を追加する。子は別Ownerが所有し、このメニューは参照だけを保持する。
    function AddSubMenu(const ACaption: string; Top: Integer;
      SubMenu: TVectArtDarkPopupMenu): TPanel;
    // 項目群の間へ高さを指定した空白を追加し、利用側が構成した区切りを表現する。
    function AddSeparator(Top, Height: Integer): TPanel;
    // 動的な再構築に備え、子メニューとの関連を外して全項目Controlを破棄する。
    procedure ClearItems;
    // ポップアップを閉じる。すでに閉じている場合は何もしない。
    procedure Close;
    // 指定Controlがトップボタンまたはポップアップ内部に属するかを返す。
    function OwnsControl(AControl: TControl): Boolean;
    // OnOpeningを通知した後、トップボタン直下へポップアップを表示する。
    procedure Open;
    // 指定した画面座標を左上候補として開き、フォームおよびモニター内へ位置を補正する。
    procedure OpenAtScreenPoint(const ScreenPoint: TPoint);
    // 項目のEnabledとダーク配色の文字色を同時に更新する。
    procedure SetItemEnabled(Item: TPanel; const Value: Boolean);
    // 現在の表示状態を反転する。通常はトップボタンのクリックから自動的に呼ばれる。
    procedure Toggle;
    // メニューバー型だけが持つ起点ボタン。任意位置ポップアップではnilを返す。
    property Button: TPanel read FButton;
    // トップボタンへマウスが入るたび通知する。ホバー切替の開始条件は利用側が判断する。
    property OnHover: TNotifyEvent read FOnHover write FOnHover;
    // 非表示から表示へ変わる直前に通知する。利用側は他のメニューをここで閉じられる。
    property OnOpening: TNotifyEvent read FOnOpening write FOnOpening;
    // 利用側が既存DFM項目の追加や表示状態の調整に使用するポップアップ本体。
    property Popup: TPanel read FPopup;
    // 項目数に応じて利用側が変更できるポップアップ本体の高さ。
    property PopupHeight: Integer read GetPopupHeight write SetPopupHeight;
    // ルートまたは子ポップアップ本体が現在表示されているかを返す。
    property Visible: Boolean read GetVisible;
  end;

implementation

uses
  System.Math, System.SysUtils, System.Types, Vcl.Forms;

type
  TVectArtDarkMenuItemState = (dmisNormal, dmisHover, dmisSubMenuActive);

  // 標準メニューに近い左寄せ名称、右寄せショートカット、右端矢印を描く。
  TVectArtDarkMenuItem = class(TPanel)
  private
    FDisplayCaption: string;
    FHasSubMenu: Boolean;
    FShortcut: string;
    FState: TVectArtDarkMenuItemState;
  protected
    procedure Paint; override;
  public
    procedure SetMenuContent(const ACaption, AShortcut: string;
      HasSubMenu: Boolean);
    procedure SetState(Value: TVectArtDarkMenuItemState);
  end;

const
  COLOR_BUTTON = TColor($00222222);
  COLOR_DISABLED = TColor($00757575);
  COLOR_ITEM_HOVER = TColor($00464646);          // 通常項目へポインターがある間の背景。
  COLOR_POPUP = TColor($00303030);
  COLOR_TEXT = TColor($00E6E6E6);
  MENU_ITEM_HEIGHT = 32;
  MENU_ITEM_LEFT_PADDING = 12;
  MENU_ITEM_RIGHT_PADDING = 12;
  MENU_SHORTCUT_COLUMN_WIDTH = 76;

procedure SplitLegacyMenuCaption(const Value: string;
  out DisplayCaption, Shortcut: string);
var
  I: Integer;
  SeparatorStart: Integer;
begin
  DisplayCaption := Value;
  Shortcut := '';
  SeparatorStart := 0;
  I := 1;
  while I < Length(Value) do
  begin
    if (Value[I] = ' ') and (Value[I + 1] = ' ') then
    begin
      SeparatorStart := I;
      Break;
    end;
    Inc(I);
  end;
  if SeparatorStart = 0 then
    Exit;
  DisplayCaption := Trim(Copy(Value, 1, SeparatorStart - 1));
  Shortcut := Trim(Copy(Value, SeparatorStart, MaxInt));
end;

{ TVectArtDarkMenuItem }

procedure TVectArtDarkMenuItem.Paint;
var
  ArrowRect: TRect;
  CaptionRect: TRect;
  ItemLeftPadding: Integer;
  ItemRightPadding: Integer;
  ShortcutColumnWidth: Integer;
  ShortcutRect: TRect;
begin
  case FState of
    dmisHover: Canvas.Brush.Color := COLOR_ITEM_HOVER;
    dmisSubMenuActive: Canvas.Brush.Color := VECTART_DARK_MENU_ACTIVE_COLOR;
  else
    Canvas.Brush.Color := Color;
  end;
  Canvas.FillRect(ClientRect);
  if FState = dmisSubMenuActive then
  begin
    Canvas.Brush.Color := VECTART_DARK_MENU_ACCENT_COLOR;
    Canvas.FillRect(Rect(0, 0, MulDiv(3, CurrentPPI, 96), ClientHeight));
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := VECTART_DARK_MENU_ACCENT_COLOR;
    Canvas.Rectangle(0, 0, ClientWidth, ClientHeight);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);

  ItemLeftPadding := MulDiv(MENU_ITEM_LEFT_PADDING, CurrentPPI, 96);
  ItemRightPadding := MulDiv(MENU_ITEM_RIGHT_PADDING, CurrentPPI, 96);
  ShortcutColumnWidth := MulDiv(MENU_SHORTCUT_COLUMN_WIDTH, CurrentPPI, 96);
  CaptionRect := Rect(ItemLeftPadding, 0,
    ClientWidth - ItemRightPadding, ClientHeight);
  if FShortcut <> '' then
    CaptionRect.Right := Max(CaptionRect.Left,
      ClientWidth - ItemRightPadding - ShortcutColumnWidth);
  if FHasSubMenu then
    CaptionRect.Right := Max(CaptionRect.Left,
      ClientWidth - MulDiv(30, CurrentPPI, 96));
  DrawText(Canvas.Handle, PChar(FDisplayCaption), Length(FDisplayCaption),
    CaptionRect, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS or
    DT_NOPREFIX);

  if FShortcut <> '' then
  begin
    ShortcutRect := Rect(ClientWidth - ItemRightPadding -
      ShortcutColumnWidth, 0, ClientWidth - ItemRightPadding,
      ClientHeight);
    DrawText(Canvas.Handle, PChar(FShortcut), Length(FShortcut), ShortcutRect,
      DT_RIGHT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  end;
  if FHasSubMenu then
  begin
    ArrowRect := Rect(ClientWidth - MulDiv(28, CurrentPPI, 96), 0,
      ClientWidth - ItemRightPadding, ClientHeight);
    DrawText(Canvas.Handle, PChar(#8250), 1, ArrowRect,
      DT_RIGHT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  end;
end;

procedure TVectArtDarkMenuItem.SetState(Value: TVectArtDarkMenuItemState);
begin
  if FState = Value then Exit;
  FState := Value;
  case FState of
    dmisHover: Color := COLOR_ITEM_HOVER;
    dmisSubMenuActive: Color := VECTART_DARK_MENU_ACTIVE_COLOR;
  else
    Color := COLOR_POPUP;
  end;
  Invalidate;
end;

procedure TVectArtDarkMenuItem.SetMenuContent(const ACaption,
  AShortcut: string; HasSubMenu: Boolean);
begin
  FDisplayCaption := ACaption;
  FShortcut := AShortcut;
  FHasSubMenu := HasSubMenu;
  Invalidate;
end;

function TVectArtDarkPopupMenu.AddItem(const ACaption: string; Top: Integer;
  ClickHandler: TNotifyEvent): TPanel;
var
  DisplayCaption: string;
  Shortcut: string;
begin
  SplitLegacyMenuCaption(ACaption, DisplayCaption, Shortcut);
  Result := AddItem(DisplayCaption, Shortcut, Top, ClickHandler);
  Result.Caption := ACaption;
end;

function TVectArtDarkPopupMenu.AddItem(const ACaption, AShortcut: string;
  Top: Integer; ClickHandler: TNotifyEvent): TPanel;
begin
  Result := TVectArtDarkMenuItem.Create(Self);
  Result.Parent := FPopup;
  Result.SetBounds(0, MulDiv(Top, FPopup.CurrentPPI, 96), FPopup.Width,
    MulDiv(MENU_ITEM_HEIGHT, FPopup.CurrentPPI, 96));
  Result.BevelOuter := bvNone;
  Result.Caption := ACaption;
  if AShortcut <> '' then
    Result.Caption := Result.Caption + '    ' + AShortcut;
  Result.Color := COLOR_POPUP;
  Result.Font.Name := 'Segoe UI';
  Result.Font.Height := -MulDiv(12, Result.CurrentPPI, 96);
  Result.Font.Color := COLOR_TEXT;
  Result.ParentBackground := False;
  Result.OnClick := ClickHandler;
  Result.OnMouseEnter := ItemMouseEnter;
  Result.OnMouseLeave := ItemMouseLeave;
  TVectArtDarkMenuItem(Result).SetMenuContent(ACaption, AShortcut, False);
end;

function TVectArtDarkPopupMenu.AddSubMenu(const ACaption: string;
  Top: Integer; SubMenu: TVectArtDarkPopupMenu): TPanel;
begin
  Result := AddItem(ACaption, '', Top, SubMenuItemClick);
  Result.Caption := ACaption + '  >';
  TVectArtDarkMenuItem(Result).SetMenuContent(ACaption, '', True);
  if SubMenu = nil then
    Exit;
  if (SubMenu.FParentMenu <> nil) and
    (SubMenu.FParentMenu <> Self) then
    SubMenu.FParentMenu.FChildMenus.Remove(SubMenu);
  SubMenu.FParentMenu := Self;
  if not FChildMenus.Contains(SubMenu) then
    FChildMenus.Add(SubMenu);
  FSubMenus.AddOrSetValue(Result, SubMenu);
end;

function TVectArtDarkPopupMenu.AddSeparator(Top, Height: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := FPopup;
  Result.SetBounds(0, MulDiv(Top, FPopup.CurrentPPI, 96), FPopup.Width,
    MulDiv(Height, FPopup.CurrentPPI, 96));
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.Color := COLOR_POPUP;
  Result.ParentBackground := False;
end;

procedure TVectArtDarkPopupMenu.ButtonClick(Sender: TObject);
begin
  Toggle;
end;

procedure TVectArtDarkPopupMenu.ButtonMouseEnter(Sender: TObject);
begin
  if Assigned(FOnHover) then
    FOnHover(Self);
end;

procedure TVectArtDarkPopupMenu.Close;
begin
  CloseChildMenus;
  SetActiveSubMenuItem(nil);
  FPopup.Visible := False;
  if FParentMenu <> nil then
    FParentMenu.SetActiveSubMenuItem(nil);
end;

procedure TVectArtDarkPopupMenu.ClearItems;
var
  Menu: TVectArtDarkPopupMenu;
begin
  Close;
  FHoveredItem := nil;
  for Menu in FChildMenus do
    if Menu.FParentMenu = Self then
      Menu.FParentMenu := nil;
  FChildMenus.Clear;
  FSubMenus.Clear;
  while FPopup.ControlCount > 0 do
    FPopup.Controls[0].Free;
end;

procedure TVectArtDarkPopupMenu.CloseChildMenus(
  ExceptMenu: TVectArtDarkPopupMenu);
var
  Menu: TVectArtDarkPopupMenu;
begin
  for Menu in FChildMenus do
    if Menu <> ExceptMenu then
      Menu.Close;
end;

constructor TVectArtDarkPopupMenu.CreateForControls(AOwner: TComponent;
  AMainForm: TWinControl; AButton, APopup: TPanel);
begin
  inherited Create(AOwner);
  FMainForm := AMainForm;
  FChildMenus := TList<TVectArtDarkPopupMenu>.Create;
  FSubMenus := TDictionary<TPanel, TVectArtDarkPopupMenu>.Create;
  InitializeControls(AButton, APopup);
end;

constructor TVectArtDarkPopupMenu.CreateForHosts(AOwner: TComponent;
  AMainForm, AMenuBar: TWinControl; const ACaption: string; ButtonLeft,
  ButtonWidth, PopupWidth, PopupHeight: Integer);
var
  ButtonControl: TPanel;
  PopupControl: TPanel;
begin
  inherited Create(AOwner);
  FMainForm := AMainForm;
  FChildMenus := TList<TVectArtDarkPopupMenu>.Create;
  FSubMenus := TDictionary<TPanel, TVectArtDarkPopupMenu>.Create;

  ButtonControl := TPanel.Create(Self);
  ButtonControl.Parent := AMenuBar;
  ButtonControl.SetBounds(MulDiv(ButtonLeft, ButtonControl.CurrentPPI, 96),
    0, MulDiv(ButtonWidth, ButtonControl.CurrentPPI, 96), AMenuBar.Height);
  ButtonControl.BevelOuter := bvNone;
  ButtonControl.Caption := ACaption;
  ButtonControl.Color := COLOR_BUTTON;
  ButtonControl.Font.Name := 'Segoe UI';
  ButtonControl.Font.Height := -MulDiv(12, ButtonControl.CurrentPPI, 96);
  ButtonControl.Font.Color := COLOR_TEXT;
  ButtonControl.ParentBackground := False;

  PopupControl := TPanel.Create(Self);
  PopupControl.Parent := AMainForm;
  PopupControl.SetBounds(MulDiv(ButtonLeft, PopupControl.CurrentPPI, 96),
    AMenuBar.Height, MulDiv(PopupWidth, PopupControl.CurrentPPI, 96),
    MulDiv(PopupHeight, PopupControl.CurrentPPI, 96));
  PopupControl.BevelOuter := bvNone;
  PopupControl.Color := COLOR_POPUP;
  PopupControl.ParentBackground := False;
  PopupControl.Visible := False;
  InitializeControls(ButtonControl, PopupControl);
end;

constructor TVectArtDarkPopupMenu.CreatePopup(AOwner: TComponent;
  AMainForm: TWinControl; PopupWidth, PopupHeight: Integer);
var
  PopupControl: TPanel;
begin
  inherited Create(AOwner);
  FMainForm := AMainForm;
  FChildMenus := TList<TVectArtDarkPopupMenu>.Create;
  FSubMenus := TDictionary<TPanel, TVectArtDarkPopupMenu>.Create;
  PopupControl := TPanel.Create(Self);
  PopupControl.Parent := AMainForm;
  PopupControl.SetBounds(0, 0,
    MulDiv(PopupWidth, PopupControl.CurrentPPI, 96),
    MulDiv(PopupHeight, PopupControl.CurrentPPI, 96));
  PopupControl.BevelOuter := bvNone;
  PopupControl.Color := COLOR_POPUP;
  PopupControl.ParentBackground := False;
  PopupControl.Visible := False;
  InitializeControls(nil, PopupControl);
end;

destructor TVectArtDarkPopupMenu.Destroy;
var
  Menu: TVectArtDarkPopupMenu;
begin
  if FParentMenu <> nil then
    FParentMenu.FChildMenus.Remove(Self);
  for Menu in FChildMenus do
    if Menu.FParentMenu = Self then
      Menu.FParentMenu := nil;
  FSubMenus.Free;
  FChildMenus.Free;
  inherited Destroy;
end;

function TVectArtDarkPopupMenu.GetPopupHeight: Integer;
begin
  Result := MulDiv(FPopup.Height, 96, FPopup.CurrentPPI);
end;

function TVectArtDarkPopupMenu.GetVisible: Boolean;
begin
  Result := FPopup.Visible;
end;

procedure TVectArtDarkPopupMenu.InitializeControls(AButton,
  APopup: TPanel);
begin
  FButton := AButton;
  FPopup := APopup;
  if FButton <> nil then
  begin
    FButton.OnClick := ButtonClick;
    FButton.OnMouseEnter := ButtonMouseEnter;
  end;
end;

procedure TVectArtDarkPopupMenu.ItemMouseEnter(Sender: TObject);
var
  Item: TPanel;
  SubMenu: TVectArtDarkPopupMenu;
begin
  if not (Sender is TPanel) then Exit;
  Item := TPanel(Sender);
  if (FHoveredItem <> nil) and (FHoveredItem <> FActiveSubMenuItem) then
    TVectArtDarkMenuItem(FHoveredItem).SetState(dmisNormal);
  FHoveredItem := Item;
  SubMenu := nil;
  if FSubMenus.TryGetValue(Item, SubMenu) then
  begin
    CloseChildMenus(SubMenu);
    SetActiveSubMenuItem(Item);
    OpenSubMenu(Item, SubMenu);
  end
  else begin
    CloseChildMenus;
    SetActiveSubMenuItem(nil);
    TVectArtDarkMenuItem(Item).SetState(dmisHover);
  end;
end;

procedure TVectArtDarkPopupMenu.ItemMouseLeave(Sender: TObject);
begin
  if not (Sender is TPanel) then Exit;
  if FHoveredItem = Sender then FHoveredItem := nil;
  if Sender <> FActiveSubMenuItem then
    TVectArtDarkMenuItem(Sender).SetState(dmisNormal);
end;

procedure TVectArtDarkPopupMenu.Open;
var
  Origin: TPoint;
begin
  if FButton = nil then
    Exit;
  if FPopup.Visible then
  begin
    FPopup.BringToFront;
    Exit;
  end;
  Origin := FMainForm.ScreenToClient(FButton.ClientToScreen(Point(0,
    FButton.Height)));
  OpenAtScreenPointCore(FMainForm.ClientToScreen(Origin), True);
end;

procedure TVectArtDarkPopupMenu.OpenAtScreenPoint(
  const ScreenPoint: TPoint);
begin
  OpenAtScreenPointCore(ScreenPoint, True);
end;

procedure TVectArtDarkPopupMenu.OpenAtScreenPointCore(
  const ScreenPoint: TPoint; NotifyOpening: Boolean);
var
  ClientBounds: TRect;
  ClientPoint: TPoint;
  Monitor: TMonitor;
  PopupBounds: TRect;
  PopupScreenPoint: TPoint;
  WorkArea: TRect;
begin
  if (FPopup = nil) or (FMainForm = nil) then
    Exit;
  if NotifyOpening and Assigned(FOnOpening) then
    FOnOpening(Self);
  ClientPoint := FMainForm.ScreenToClient(ScreenPoint);
  ClientBounds := FMainForm.ClientRect;
  ClientPoint.X := EnsureRange(ClientPoint.X, ClientBounds.Left,
    Max(ClientBounds.Left, ClientBounds.Right - FPopup.Width));
  ClientPoint.Y := EnsureRange(ClientPoint.Y, ClientBounds.Top,
    Max(ClientBounds.Top, ClientBounds.Bottom - FPopup.Height));

  PopupScreenPoint := FMainForm.ClientToScreen(ClientPoint);
  PopupBounds := Rect(PopupScreenPoint.X, PopupScreenPoint.Y,
    PopupScreenPoint.X + FPopup.Width, PopupScreenPoint.Y + FPopup.Height);
  Monitor := Screen.MonitorFromRect(PopupBounds, mdNearest);
  if Monitor <> nil then
  begin
    WorkArea := Monitor.WorkareaRect;
    if PopupBounds.Right > WorkArea.Right then
      ClientPoint.X := ClientPoint.X - (PopupBounds.Right - WorkArea.Right);
    if PopupBounds.Bottom > WorkArea.Bottom then
      ClientPoint.Y := ClientPoint.Y - (PopupBounds.Bottom - WorkArea.Bottom);
    ClientPoint.X := Max(ClientBounds.Left, ClientPoint.X);
    ClientPoint.Y := Max(ClientBounds.Top, ClientPoint.Y);
  end;
  FPopup.Left := ClientPoint.X;
  FPopup.Top := ClientPoint.Y;
  FPopup.Visible := True;
  FPopup.BringToFront;
end;

procedure TVectArtDarkPopupMenu.OpenSubMenu(Item: TPanel;
  SubMenu: TVectArtDarkPopupMenu);
var
  ItemOrigin: TPoint;
  Monitor: TMonitor;
  WorkArea: TRect;
begin
  if (Item = nil) or (SubMenu = nil) then
    Exit;
  ItemOrigin := Item.ClientToScreen(Point(Item.Width, 0));
  Monitor := Screen.MonitorFromPoint(ItemOrigin, mdNearest);
  if Monitor <> nil then
  begin
    WorkArea := Monitor.WorkareaRect;
    if ItemOrigin.X + SubMenu.Popup.Width > WorkArea.Right then
      ItemOrigin.X := Item.ClientToScreen(Point(-SubMenu.Popup.Width, 0)).X;
  end;
  SubMenu.OpenAtScreenPointCore(ItemOrigin, False);
end;

procedure TVectArtDarkPopupMenu.SetActiveSubMenuItem(Item: TPanel);
begin
  if FActiveSubMenuItem = Item then Exit;
  if FActiveSubMenuItem <> nil then
    TVectArtDarkMenuItem(FActiveSubMenuItem).SetState(dmisNormal);
  FActiveSubMenuItem := Item;
  if FActiveSubMenuItem <> nil then
    TVectArtDarkMenuItem(FActiveSubMenuItem).SetState(dmisSubMenuActive);
end;

function TVectArtDarkPopupMenu.OwnsControl(AControl: TControl): Boolean;
var
  Menu: TVectArtDarkPopupMenu;
begin
  Result := False;
  if AControl = nil then
    Exit;
  if ((FButton <> nil) and
      ((AControl = FButton) or FButton.ContainsControl(AControl))) or
    ((FPopup <> nil) and
      ((AControl = FPopup) or FPopup.ContainsControl(AControl))) then
    Exit(True);
  for Menu in FChildMenus do
    if Menu.OwnsControl(AControl) then
      Exit(True);
end;

procedure TVectArtDarkPopupMenu.SetItemEnabled(Item: TPanel;
  const Value: Boolean);
begin
  if Item = nil then
    Exit;
  Item.Enabled := Value;
  if Value then
    Item.Font.Color := COLOR_TEXT
  else
    Item.Font.Color := COLOR_DISABLED;
end;

procedure TVectArtDarkPopupMenu.SetPopupHeight(const Value: Integer);
begin
  FPopup.Height := MulDiv(Value, FPopup.CurrentPPI, 96);
end;

procedure TVectArtDarkPopupMenu.Toggle;
begin
  if FPopup.Visible then
    Close
  else
    Open;
end;

procedure TVectArtDarkPopupMenu.SubMenuItemClick(Sender: TObject);
var
  SubMenu: TVectArtDarkPopupMenu;
begin
  if (Sender is TPanel) and
    FSubMenus.TryGetValue(TPanel(Sender), SubMenu) then
    OpenSubMenu(TPanel(Sender), SubMenu);
end;

end.
