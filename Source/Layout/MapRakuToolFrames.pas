// ドッキング可能なツールFrameとフローティングフォームの共通動作を提供する。
// 個別ツールの内容は持たず、ドラッグ入力とウィンドウ化だけを担当する。
unit MapRakuToolFrames;

interface

uses
  System.Classes, System.Types, Winapi.Messages, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls;

type
  TToolPlaceholderFrame = class;

  TFloatingToolForm = class(TForm)
  private
    FTitleDragging: Boolean;
    FToolFrame: TToolPlaceholderFrame;
    function ClientMessagePoint(const Message: TMessage): TPoint;
    function ScreenMessagePoint(const Message: TMessage): TPoint;
  protected
    procedure WndProc(var Message: TMessage); override;
  public
    property ToolFrame: TToolPlaceholderFrame read FToolFrame write FToolFrame;
  end;

  TToolFrameNotifyEvent = procedure(Sender: TToolPlaceholderFrame) of object;
  TToolFrameDragEvent = procedure(Sender: TToolPlaceholderFrame;
    const ScreenPoint: TPoint) of object;
  TToolFrameDockRequestEvent = procedure(Sender: TToolPlaceholderFrame;
    const ScreenPoint: TPoint; var Accepted: Boolean) of object;

  TPlaceholderFrame = class(TFrame)
  private
    FTitleLabel: TLabel;
  protected
    procedure SetPlaceholderAppearance(const ATitle: string; ABackgroundColor: TColor);
    property TitleLabel: TLabel read FTitleLabel;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TToolPlaceholderFrame = class(TPlaceholderFrame)
  private
    FDragging: Boolean;
    FDragAnchor: TPoint;
    FDragOffset: TPoint;
    FDragStarted: Boolean;
    FFloatingForm: TFloatingToolForm;
    FGripLabel: TLabel;
    FGripPanel: TPanel;
    FLayoutEditing: Boolean;
    FMainForm: TCustomForm;
    FContextForm: TForm;
    FOnCloseRequest: TToolFrameNotifyEvent;
    FOnDetached: TToolFrameNotifyEvent;
    FOnDockRequest: TToolFrameDockRequestEvent;
    FOnDragMove: TToolFrameDragEvent;
    FPreferredDockWidth: Integer;
    FLastFloatingBounds: TRect;
    FToolId: string;
    FToolTitle: string;
    procedure BeginFloatingTitleDrag(const ScreenPoint: TPoint);
    procedure ContinueFloatingDrag(const ScreenPoint: TPoint);
    procedure ContextCloseClick(Sender: TObject);
    procedure ContextFormDeactivate(Sender: TObject);
    procedure EndFloatingDrag(const ScreenPoint: TPoint);
    procedure EnsureFloating;
    function EventScreenPoint(Sender: TObject; X, Y: Integer): TPoint;
    function GetIsFloating: Boolean;
    procedure GripMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure GripMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GripMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure HideContextMenu;
    procedure SetLayoutEditing(const Value: Boolean);
    procedure ShowContextMenu(const ScreenPoint: TPoint);
  protected
    procedure ConfigureToolAppearance(const AToolId, ATitle: string;
      ABackgroundColor: TColor; APreferredDockWidth: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ConfigureFloatingOwner(AMainForm: TCustomForm);
    procedure DockToHost(AHost: TWinControl);
    procedure FloatAt(const Bounds: TRect);
    function FloatingBounds: TRect;
    procedure HideToolWindow;
    property IsFloating: Boolean read GetIsFloating;
    property LayoutEditing: Boolean read FLayoutEditing write SetLayoutEditing;
    property OnCloseRequest: TToolFrameNotifyEvent read FOnCloseRequest
      write FOnCloseRequest;
    property OnDetached: TToolFrameNotifyEvent read FOnDetached write FOnDetached;
    property OnDockRequest: TToolFrameDockRequestEvent read FOnDockRequest
      write FOnDockRequest;
    property OnDragMove: TToolFrameDragEvent read FOnDragMove write FOnDragMove;
    property PreferredDockWidth: Integer read FPreferredDockWidth;
    property ToolId: string read FToolId;
    property ToolTitle: string read FToolTitle;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.Dwmapi, Winapi.Windows;

const
  COLOR_TEXT_PRIMARY      = TColor($00E6E6E6);
  COLOR_GRIP_BACKGROUND   = TColor($003A3A3A);
  DRAG_THRESHOLD          = 4;

{ TFloatingToolForm }

function TFloatingToolForm.ClientMessagePoint(
  const Message: TMessage): TPoint;
begin
  Result := ClientToScreen(Point(SmallInt(Message.LParam and $FFFF),
    SmallInt((Message.LParam shr 16) and $FFFF)));
end;

function TFloatingToolForm.ScreenMessagePoint(
  const Message: TMessage): TPoint;
begin
  Result := Point(SmallInt(Message.LParam and $FFFF),
    SmallInt((Message.LParam shr 16) and $FFFF));
end;

procedure TFloatingToolForm.WndProc(var Message: TMessage);
begin
  if (FToolFrame <> nil) and FToolFrame.LayoutEditing then
    case Message.Msg of
      WM_NCLBUTTONDOWN:
        if Message.WParam = HTCAPTION then
        begin
          FTitleDragging := True;
          FToolFrame.BeginFloatingTitleDrag(ScreenMessagePoint(Message));
          SetCapture(Handle);
          Exit;
        end;
      WM_MOUSEMOVE:
        if FTitleDragging then
        begin
          FToolFrame.ContinueFloatingDrag(ClientMessagePoint(Message));
          Exit;
        end;
      WM_LBUTTONUP:
        if FTitleDragging then
        begin
          FTitleDragging := False;
          ReleaseCapture;
          FToolFrame.EndFloatingDrag(ClientMessagePoint(Message));
          Exit;
        end;
      WM_CAPTURECHANGED:
        FTitleDragging := False;
      WM_NCRBUTTONUP:
        if Message.WParam = HTCAPTION then
        begin
          FToolFrame.ShowContextMenu(ScreenMessagePoint(Message));
          Exit;
        end;
    end;
  inherited WndProc(Message);
end;

{ TPlaceholderFrame }

constructor TPlaceholderFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ParentBackground := False;
  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.Align := alClient;
  FTitleLabel.Alignment := taCenter;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Font.Name := 'Segoe UI';
  FTitleLabel.Font.Height := -MulDiv(15, CurrentPPI, 96);
  FTitleLabel.Font.Color := COLOR_TEXT_PRIMARY;
  FTitleLabel.Layout := tlCenter;
  FTitleLabel.Transparent := True;
  FTitleLabel.WordWrap := True;
end;

procedure TPlaceholderFrame.SetPlaceholderAppearance(const ATitle: string;
  ABackgroundColor: TColor);
begin
  Color := ABackgroundColor;
  FTitleLabel.Caption := ATitle;
end;

{ TToolPlaceholderFrame }

constructor TToolPlaceholderFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // 子Control生成時にHandleが必要なため、ドック登録前だけ所有Controlへ接続する。
  if AOwner is TWinControl then
    Parent := TWinControl(AOwner);
  FGripPanel := TPanel.Create(Self);
  FGripPanel.Parent := Self;
  FGripPanel.Align := alTop;
  FGripPanel.BevelOuter := bvNone;
  FGripPanel.Color := COLOR_GRIP_BACKGROUND;
  FGripPanel.Cursor := crSizeAll;
  FGripPanel.Height := MulDiv(24, CurrentPPI, 96);
  FGripPanel.ParentBackground := False;
  FGripPanel.Visible := False;
  FGripPanel.OnMouseDown := GripMouseDown;
  FGripPanel.OnMouseMove := GripMouseMove;
  FGripPanel.OnMouseUp := GripMouseUp;

  FGripLabel := TLabel.Create(Self);
  FGripLabel.Parent := FGripPanel;
  FGripLabel.Align := alClient;
  FGripLabel.Alignment := taCenter;
  FGripLabel.AutoSize := False;
  FGripLabel.Caption := ':: DRAG ::';
  FGripLabel.Cursor := crSizeAll;
  FGripLabel.Font.Name := 'Segoe UI';
  FGripLabel.Font.Height := -MulDiv(11, CurrentPPI, 96);
  FGripLabel.Font.Color := COLOR_TEXT_PRIMARY;
  FGripLabel.Layout := tlCenter;
  FGripLabel.Transparent := True;
  FGripLabel.OnMouseDown := GripMouseDown;
  FGripLabel.OnMouseMove := GripMouseMove;
  FGripLabel.OnMouseUp := GripMouseUp;
  TitleLabel.OnMouseUp := GripMouseUp;
  OnMouseUp := GripMouseUp;
  FGripPanel.BringToFront;
end;

destructor TToolPlaceholderFrame.Destroy;
var
  FloatingForm: TFloatingToolForm;
begin
  if FContextForm <> nil then
  begin
    FContextForm.OnDeactivate := nil;
    FreeAndNil(FContextForm);
  end;
  FloatingForm := FFloatingForm;
  FFloatingForm := nil;
  if FloatingForm <> nil then
  begin
    Parent := nil;
    FloatingForm.Free;
  end;
  inherited Destroy;
end;

procedure TToolPlaceholderFrame.ContextCloseClick(Sender: TObject);
begin
  HideContextMenu;
  if Assigned(FOnCloseRequest) then
    FOnCloseRequest(Self);
end;

procedure TToolPlaceholderFrame.ContextFormDeactivate(Sender: TObject);
begin
  HideContextMenu;
end;

procedure TToolPlaceholderFrame.ConfigureFloatingOwner(AMainForm: TCustomForm);
begin
  FMainForm := AMainForm;
end;

procedure TToolPlaceholderFrame.ConfigureToolAppearance(const AToolId,
  ATitle: string; ABackgroundColor: TColor; APreferredDockWidth: Integer);
begin
  FToolId := AToolId;
  FToolTitle := ATitle;
  FPreferredDockWidth := APreferredDockWidth;
  FLastFloatingBounds := Rect(MulDiv(100, CurrentPPI, 96),
    MulDiv(100, CurrentPPI, 96),
    MulDiv(100 + Max(APreferredDockWidth, 160), CurrentPPI, 96),
    MulDiv(700, CurrentPPI, 96));
  SetPlaceholderAppearance(ATitle, ABackgroundColor);
  FGripLabel.Caption := ':: ' + ATitle + ' ::';
end;

procedure TToolPlaceholderFrame.DockToHost(AHost: TWinControl);
var
  FloatingForm: TFloatingToolForm;
begin
  FloatingForm := FFloatingForm;
  if FloatingForm <> nil then
    FLastFloatingBounds := FloatingForm.BoundsRect;
  FFloatingForm := nil;
  Parent := AHost;
  Align := alClient;
  Visible := True;
  FGripPanel.Visible := FLayoutEditing;
  if FloatingForm <> nil then
  begin
    FloatingForm.Hide;
    FloatingForm.ToolFrame := nil;
    FloatingForm.Release;
  end;
end;

procedure TToolPlaceholderFrame.FloatAt(const Bounds: TRect);
begin
  EnsureFloating;
  if (Bounds.Width > 0) and (Bounds.Height > 0) then
  begin
    FFloatingForm.SetBounds(Bounds.Left, Bounds.Top, Bounds.Width,
      Bounds.Height);
    FLastFloatingBounds := Bounds;
  end;
end;

function TToolPlaceholderFrame.FloatingBounds: TRect;
begin
  if FFloatingForm <> nil then
    Result := FFloatingForm.BoundsRect
  else
    Result := FLastFloatingBounds;
end;

procedure TToolPlaceholderFrame.HideContextMenu;
begin
  if FContextForm <> nil then
    FContextForm.Hide;
end;

procedure TToolPlaceholderFrame.HideToolWindow;
var
  FloatingForm: TFloatingToolForm;
begin
  HideContextMenu;
  FDragging := False;
  FDragStarted := False;
  FloatingForm := FFloatingForm;
  if FloatingForm <> nil then
    FLastFloatingBounds := FloatingForm.BoundsRect;
  FFloatingForm := nil;
  Parent := nil;
  Visible := False;
  FGripPanel.Visible := False;
  if FloatingForm <> nil then
  begin
    FloatingForm.Hide;
    FloatingForm.ToolFrame := nil;
    FloatingForm.Release;
  end;
end;

procedure TToolPlaceholderFrame.BeginFloatingTitleDrag(
  const ScreenPoint: TPoint);
begin
  if not FLayoutEditing or (FFloatingForm = nil) then
    Exit;
  FDragging := True;
  FDragStarted := True;
  FDragOffset := Point(ScreenPoint.X - FFloatingForm.Left,
    ScreenPoint.Y - FFloatingForm.Top);
end;

procedure TToolPlaceholderFrame.ContinueFloatingDrag(
  const ScreenPoint: TPoint);
begin
  if not FDragging or (FFloatingForm = nil) then
    Exit;
  FFloatingForm.Left := ScreenPoint.X - FDragOffset.X;
  FFloatingForm.Top := ScreenPoint.Y - FDragOffset.Y;
  if Assigned(FOnDragMove) then
    FOnDragMove(Self, ScreenPoint);
end;

procedure TToolPlaceholderFrame.EndFloatingDrag(const ScreenPoint: TPoint);
var
  Accepted: Boolean;
begin
  if not FDragging then
    Exit;
  FDragging := False;
  FDragStarted := False;
  Accepted := False;
  if Assigned(FOnDockRequest) then
    FOnDockRequest(Self, ScreenPoint, Accepted);
end;

procedure TToolPlaceholderFrame.EnsureFloating;
var
  DarkModeEnabled: BOOL;
  FrameHeight: Integer;
  FrameWidth: Integer;
  Origin: TPoint;
begin
  if FFloatingForm <> nil then
    Exit;
  Origin := ClientToScreen(Point(0, 0));
  FrameWidth := Max(Width, 160);
  FrameHeight := Max(Height, 120);
  if Assigned(FOnDetached) then
    FOnDetached(Self);
  FFloatingForm := TFloatingToolForm.CreateNew(nil);
  FFloatingForm.ToolFrame := Self;
  FFloatingForm.BorderIcons := [];
  FFloatingForm.BorderStyle := bsSizeToolWin;
  FFloatingForm.Caption := FToolTitle;
  FFloatingForm.Color := Color;
  FFloatingForm.Font.Assign(Font);
  FFloatingForm.Position := poDesigned;
  FFloatingForm.PopupParent := FMainForm;
  FFloatingForm.ClientWidth := FrameWidth;
  FFloatingForm.ClientHeight := FrameHeight;
  FFloatingForm.Left := Origin.X;
  FFloatingForm.Top := Origin.Y;
  DarkModeEnabled := True;
  DwmSetWindowAttribute(FFloatingForm.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE,
    @DarkModeEnabled, SizeOf(DarkModeEnabled));
  Parent := FFloatingForm;
  Align := alClient;
  FGripPanel.Visible := False;
  FFloatingForm.Show;
  FFloatingForm.BringToFront;
end;

function TToolPlaceholderFrame.EventScreenPoint(Sender: TObject;
  X, Y: Integer): TPoint;
begin
  Result := TControl(Sender).ClientToScreen(Point(X, Y));
end;

function TToolPlaceholderFrame.GetIsFloating: Boolean;
begin
  Result := FFloatingForm <> nil;
end;

procedure TToolPlaceholderFrame.GripMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not FLayoutEditing or (Button <> mbLeft) then
    Exit;
  FDragAnchor := EventScreenPoint(Sender, X, Y);
  FDragging := True;
  FDragStarted := False;
  SetCapture(FGripPanel.Handle);
end;

procedure TToolPlaceholderFrame.GripMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  ScreenPoint: TPoint;
begin
  if not FDragging then
    Exit;
  ScreenPoint := EventScreenPoint(Sender, X, Y);
  if not FDragStarted then
  begin
    if (Abs(ScreenPoint.X - FDragAnchor.X) < DRAG_THRESHOLD) and
      (Abs(ScreenPoint.Y - FDragAnchor.Y) < DRAG_THRESHOLD) then
      Exit;
    EnsureFloating;
    FDragOffset := Point(ScreenPoint.X - FFloatingForm.Left,
      ScreenPoint.Y - FFloatingForm.Top);
    FDragStarted := True;
    SetCapture(FGripPanel.Handle);
  end;
  FFloatingForm.Left := ScreenPoint.X - FDragOffset.X;
  FFloatingForm.Top := ScreenPoint.Y - FDragOffset.Y;
  if Assigned(FOnDragMove) then
    FOnDragMove(Self, ScreenPoint);
end;

procedure TToolPlaceholderFrame.GripMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Accepted: Boolean;
  ScreenPoint: TPoint;
begin
  if Button = mbRight then
  begin
    if FLayoutEditing then
      ShowContextMenu(EventScreenPoint(Sender, X, Y));
    Exit;
  end;
  if (Button <> mbLeft) or not FDragging then
    Exit;
  ScreenPoint := EventScreenPoint(Sender, X, Y);
  FDragging := False;
  ReleaseCapture;
  if FDragStarted then
  begin
    Accepted := False;
    if Assigned(FOnDockRequest) then
      FOnDockRequest(Self, ScreenPoint, Accepted);
  end;
  FDragStarted := False;
end;

procedure TToolPlaceholderFrame.SetLayoutEditing(const Value: Boolean);
begin
  if FLayoutEditing = Value then
    Exit;
  FLayoutEditing := Value;
  if not Value then
  begin
    FDragging := False;
    FDragStarted := False;
    ReleaseCapture;
    HideContextMenu;
  end;
  FGripPanel.Visible := Value and not IsFloating;
  if FGripPanel.Visible then
    FGripPanel.BringToFront;
end;

procedure TToolPlaceholderFrame.ShowContextMenu(const ScreenPoint: TPoint);
var
  ClosePanel: TPanel;
begin
  if not FLayoutEditing then
    Exit;
  if FContextForm = nil then
  begin
    FContextForm := TForm.CreateNew(nil);
    FContextForm.BorderStyle := bsNone;
    FContextForm.Color := COLOR_GRIP_BACKGROUND;
    FContextForm.PopupParent := FMainForm;
    FContextForm.ClientWidth := MulDiv(128, CurrentPPI, 96);
    FContextForm.ClientHeight := MulDiv(32, CurrentPPI, 96);
    FContextForm.Font.Name := 'Segoe UI';
    FContextForm.Font.Height := -MulDiv(12, CurrentPPI, 96);
    FContextForm.FormStyle := fsStayOnTop;
    FContextForm.OnDeactivate := ContextFormDeactivate;
    ClosePanel := TPanel.Create(FContextForm);
    ClosePanel.Parent := FContextForm;
    ClosePanel.Align := alClient;
    ClosePanel.BevelOuter := bvNone;
    ClosePanel.Caption := #38281#12376#12427;
    ClosePanel.Color := COLOR_GRIP_BACKGROUND;
    ClosePanel.Font.Color := COLOR_TEXT_PRIMARY;
    ClosePanel.ParentBackground := False;
    ClosePanel.ParentFont := False;
    ClosePanel.OnClick := ContextCloseClick;
  end;
  FContextForm.Left := ScreenPoint.X;
  FContextForm.Top := ScreenPoint.Y;
  FContextForm.Show;
  FContextForm.BringToFront;
end;

end.
