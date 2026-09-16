// 複数のダークメニューを一つの操作グループとして監視し、排他的な開閉と一括終了を担当する。
// 各メニューの項目構成、表示位置、階層サブメニュー内部の切替は担当しない。
unit VectArtDarkMenuGroup;

interface

uses
  System.Classes, System.Generics.Collections, Vcl.AppEvnts, Vcl.Controls,
  Winapi.Windows, VectArtDarkPopupMenu;

type
  TVectArtDarkMenuGroup = class(TComponent)
  private
    FApplicationEvents: TApplicationEvents;
    FMenus: TList<TVectArtDarkPopupMenu>; // グループへ登録されたルートメニューの非所有参照。
    procedure ApplicationDeactivate(Sender: TObject);
    procedure ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
    function AnyMenuVisible: Boolean;
    procedure MenuHover(Sender: TObject);
    procedure MenuOpening(Sender: TObject);
  public
    // アプリケーション全体の入力監視を開始し、Ownerと同じ期間だけ登録メニューを管理する。
    constructor Create(AOwner: TComponent); override;
    // 入力監視用Componentと非所有の登録一覧を解放する。登録メニュー自体は破棄しない。
    destructor Destroy; override;
    // 登録された全ルートメニューと、それらが所有する表示中の子メニューを閉じる。
    procedure CloseAll;
    // ルートメニューを非所有参照で登録し、相互切替とグループ外操作による自動終了を接続する。
    procedure RegisterMenu(Menu: TVectArtDarkPopupMenu);
  end;

implementation

uses
  Winapi.Messages;

procedure TVectArtDarkMenuGroup.ApplicationDeactivate(Sender: TObject);
begin
  CloseAll;
end;

procedure TVectArtDarkMenuGroup.ApplicationMessage(var Msg: TMsg;
  var Handled: Boolean);
var
  Menu: TVectArtDarkPopupMenu;
  Target: TControl;
begin
  if ((Msg.message = WM_KEYDOWN) or (Msg.message = WM_SYSKEYDOWN)) and
    (Msg.wParam = VK_ESCAPE) then
  begin
    if AnyMenuVisible then
    begin
      CloseAll;
      Handled := True;
    end;
    Exit;
  end;
  if (Msg.message <> WM_LBUTTONDOWN) and
    (Msg.message <> WM_RBUTTONDOWN) and
    (Msg.message <> WM_MBUTTONDOWN) and
    (Msg.message <> WM_NCLBUTTONDOWN) then
    Exit;
  Target := FindVCLWindow(Msg.pt);
  for Menu in FMenus do
    if Menu.OwnsControl(Target) then
      Exit;
  CloseAll;
end;

function TVectArtDarkMenuGroup.AnyMenuVisible: Boolean;
var
  Menu: TVectArtDarkPopupMenu;
begin
  for Menu in FMenus do
    if Menu.Visible then
      Exit(True);
  Result := False;
end;

procedure TVectArtDarkMenuGroup.CloseAll;
var
  Menu: TVectArtDarkPopupMenu;
begin
  for Menu in FMenus do
    Menu.Close;
end;

constructor TVectArtDarkMenuGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenus := TList<TVectArtDarkPopupMenu>.Create;
  FApplicationEvents := TApplicationEvents.Create(Self);
  FApplicationEvents.OnDeactivate := ApplicationDeactivate;
  FApplicationEvents.OnMessage := ApplicationMessage;
end;

destructor TVectArtDarkMenuGroup.Destroy;
begin
  FMenus.Free;
  inherited Destroy;
end;

procedure TVectArtDarkMenuGroup.MenuHover(Sender: TObject);
begin
  if AnyMenuVisible and (Sender is TVectArtDarkPopupMenu) then
    TVectArtDarkPopupMenu(Sender).Open;
end;

procedure TVectArtDarkMenuGroup.MenuOpening(Sender: TObject);
var
  Menu: TVectArtDarkPopupMenu;
begin
  for Menu in FMenus do
    if Menu <> Sender then
      Menu.Close;
end;

procedure TVectArtDarkMenuGroup.RegisterMenu(Menu: TVectArtDarkPopupMenu);
begin
  if (Menu = nil) or FMenus.Contains(Menu) then
    Exit;
  FMenus.Add(Menu);
  Menu.OnHover := MenuHover;
  Menu.OnOpening := MenuOpening;
end;

end.
