// ツールFrameの左右ドッキング、順序、フローティング、スプリッター幅の保存と復元を管理する。
// 個別ツールの内容には依存せず、空スロットを残さずにドック領域を再構成する。
unit MapRakuDockManager;

interface

uses
  System.Generics.Collections, System.IniFiles, System.Types, Vcl.ExtCtrls,
  Vcl.Forms, MapRakuToolFrames;

type
  TVectDockSide = (vdsLeft, vdsRight);

  TVectDockManager = class
  private
    FAllTools: TList<TToolPlaceholderFrame>;
    FLastIndices: TDictionary<TToolPlaceholderFrame, Integer>;
    FLastSides: TDictionary<TToolPlaceholderFrame, TVectDockSide>;
    FLayoutEditing: Boolean;
    FLeftArea: TPanel;
    FLeftDropTarget: TPanel;
    FLeftSplitter: TSplitter;
    FLeftTools: TList<TToolPlaceholderFrame>;
    FOwnerForm: TCustomForm;
    FRestoring: Boolean;
    FRightArea: TPanel;
    FRightDropTarget: TPanel;
    FRightSplitter: TSplitter;
    FRightTools: TList<TToolPlaceholderFrame>;
    FWorkspace: TPanel;
    FOnToolVisibilityChanged: TToolFrameNotifyEvent;
    function AreaForSide(Side: TVectDockSide): TPanel;
    procedure DockFrame(Frame: TToolPlaceholderFrame; Side: TVectDockSide;
      Index: Integer);
    function DropSideAt(const ScreenPoint: TPoint; out Side: TVectDockSide): Boolean;
    procedure HideDropTargets;
    function InsertIndexAt(Side: TVectDockSide; const ScreenPoint: TPoint): Integer;
    procedure LayoutDockArea(Side: TVectDockSide);
    procedure LayoutDockAreas;
    procedure ResizeDockArea(Side: TVectDockSide);
    function ReadToolSide(Ini: TCustomIniFile;
      Frame: TToolPlaceholderFrame): TVectDockSide;
    function ScreenRect(Control: TPanel): TRect;
    procedure SetLayoutEditing(const Value: Boolean);
    procedure SplitterMoved(Sender: TObject);
    function ToolsForSide(Side: TVectDockSide): TList<TToolPlaceholderFrame>;
    procedure ToolDetached(Sender: TToolPlaceholderFrame);
    procedure ToolDockRequest(Sender: TToolPlaceholderFrame;
      const ScreenPoint: TPoint; var Accepted: Boolean);
    procedure ToolDragMove(Sender: TToolPlaceholderFrame;
      const ScreenPoint: TPoint);
    procedure ToolCloseRequested(Sender: TToolPlaceholderFrame);
    procedure UpdateDropTargets(const ScreenPoint: TPoint);
  public
    // 非所有のFormと各ドックControlを接続し、スプリッター移動の監視を開始する。
    constructor Create(AOwnerForm: TCustomForm; AWorkspace, ALeftArea,
      ARightArea, ALeftDropTarget, ARightDropTarget: TPanel;
      ALeftSplitter, ARightSplitter: TSplitter);
    // 登録Frameのイベント参照を解除する。渡されたControlとFrameは解放しない。
    destructor Destroy; override;
    // Frameを指定側へ登録し、所有権を取得せず専用Slotへドックする。
    procedure RegisterTool(Frame: TToolPlaceholderFrame; DefaultSide: TVectDockSide;
      DefaultIndex: Integer = -1);
    // 現在のドック幅を主要ツールへ反映し、ドロップ領域をWorkspaceへ追従させる。
    procedure Resize;
    // 表示、順序、フローティング位置、左右ドック幅をIniから復元する。
    procedure LoadLayout(Ini: TCustomIniFile);
    // 現在の配置と左右ドック幅をIniへ保存する。
    procedure SaveLayout(Ini: TCustomIniFile);
    // 登録済みFrameを直前の側と順序へ表示するか、Slotごと隠す。
    procedure SetToolVisible(Frame: TToolPlaceholderFrame; const Value: Boolean);
    // Frameがドック済みまたはフローティング表示中ならTrueを返す。
    function ToolVisible(Frame: TToolPlaceholderFrame): Boolean;
    // 有効時だけツールの移動、切離し、閉じる操作を許可する。
    property LayoutEditing: Boolean read FLayoutEditing write SetLayoutEditing;
    // 表示状態の操作が完了した後、メニュー同期を呼び出し側へ通知する。
    property OnToolVisibilityChanged: TToolFrameNotifyEvent
      read FOnToolVisibilityChanged write FOnToolVisibilityChanged;
  end;

implementation

uses
  System.Math, System.SysUtils, Vcl.Controls, Vcl.Graphics, Winapi.Windows;

const
  DOCK_GAP            = 4;
  DOCK_MIN_TOOL_WIDTH = 48; // 過度に縮めてもSlotを消失させない下限。
  DOCK_TARGET_WIDTH   = 64;
  COLOR_TARGET_IDLE   = TColor($00302A24);
  COLOR_TARGET_HOT    = TColor($007A4A22);

function ConstrainToolBounds(const Bounds: TRect): TRect;
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

constructor TVectDockManager.Create(AOwnerForm: TCustomForm;
  AWorkspace, ALeftArea, ARightArea, ALeftDropTarget,
  ARightDropTarget: TPanel; ALeftSplitter, ARightSplitter: TSplitter);
begin
  inherited Create;
  FOwnerForm := AOwnerForm;
  FWorkspace := AWorkspace;
  FLeftArea := ALeftArea;
  FRightArea := ARightArea;
  FLeftDropTarget := ALeftDropTarget;
  FRightDropTarget := ARightDropTarget;
  FLeftSplitter := ALeftSplitter;
  FRightSplitter := ARightSplitter;
  FAllTools := TList<TToolPlaceholderFrame>.Create;
  FLeftTools := TList<TToolPlaceholderFrame>.Create;
  FRightTools := TList<TToolPlaceholderFrame>.Create;
  FLastSides := TDictionary<TToolPlaceholderFrame, TVectDockSide>.Create;
  FLastIndices := TDictionary<TToolPlaceholderFrame, Integer>.Create;
  FLeftSplitter.OnMoved := SplitterMoved;
  FRightSplitter.OnMoved := SplitterMoved;
  HideDropTargets;
end;

destructor TVectDockManager.Destroy;
var
  Frame: TToolPlaceholderFrame;
begin
  FLeftSplitter.OnMoved := nil;
  FRightSplitter.OnMoved := nil;
  for Frame in FAllTools do
  begin
    Frame.OnDetached := nil;
    Frame.OnCloseRequest := nil;
    Frame.OnDockRequest := nil;
    Frame.OnDragMove := nil;
  end;
  FLastIndices.Free;
  FLastSides.Free;
  FRightTools.Free;
  FLeftTools.Free;
  FAllTools.Free;
  inherited Destroy;
end;

function TVectDockManager.AreaForSide(Side: TVectDockSide): TPanel;
begin
  if Side = vdsLeft then
    Result := FLeftArea
  else
    Result := FRightArea;
end;

procedure TVectDockManager.DockFrame(Frame: TToolPlaceholderFrame;
  Side: TVectDockSide; Index: Integer);
var
  Area: TPanel;
  Slot: TPanel;
  Tools: TList<TToolPlaceholderFrame>;
begin
  Tools := ToolsForSide(Side);
  Index := EnsureRange(Index, 0, Tools.Count);
  Area := AreaForSide(Side);
  Slot := TPanel.Create(FOwnerForm);
  Slot.Parent := Area;
  Slot.BevelOuter := bvNone;
  Slot.Color := Frame.Color;
  Slot.ParentBackground := False;
  Tools.Insert(Index, Frame);
  FLastSides.AddOrSetValue(Frame, Side);
  FLastIndices.AddOrSetValue(Frame, Index);
  Frame.DockToHost(Slot);
  Frame.LayoutEditing := FLayoutEditing;
  LayoutDockAreas;
end;

function TVectDockManager.DropSideAt(const ScreenPoint: TPoint;
  out Side: TVectDockSide): Boolean;
var
  LeftRect: TRect;
  RightRect: TRect;
  WorkspaceRect: TRect;
begin
  Result := False;
  WorkspaceRect := ScreenRect(FWorkspace);
  if not PtInRect(WorkspaceRect, ScreenPoint) then
    Exit;
  if FLeftArea.Visible then
  begin
    LeftRect := ScreenRect(FLeftArea);
    if PtInRect(LeftRect, ScreenPoint) then
    begin
      Side := vdsLeft;
      Exit(True);
    end;
  end;
  if FRightArea.Visible then
  begin
    RightRect := ScreenRect(FRightArea);
    if PtInRect(RightRect, ScreenPoint) then
    begin
      Side := vdsRight;
      Exit(True);
    end;
  end;
  if ScreenPoint.X < WorkspaceRect.Left +
    MulDiv(DOCK_TARGET_WIDTH, FOwnerForm.CurrentPPI, 96) then
  begin
    Side := vdsLeft;
    Exit(True);
  end;
  if ScreenPoint.X >= WorkspaceRect.Right -
    MulDiv(DOCK_TARGET_WIDTH, FOwnerForm.CurrentPPI, 96) then
  begin
    Side := vdsRight;
    Exit(True);
  end;
end;

procedure TVectDockManager.HideDropTargets;
begin
  FLeftDropTarget.Visible := False;
  FRightDropTarget.Visible := False;
end;

function TVectDockManager.InsertIndexAt(Side: TVectDockSide;
  const ScreenPoint: TPoint): Integer;
var
  Frame: TToolPlaceholderFrame;
  I: Integer;
  SlotRect: TRect;
  Tools: TList<TToolPlaceholderFrame>;
begin
  Tools := ToolsForSide(Side);
  for I := 0 to Tools.Count - 1 do
  begin
    Frame := Tools[I];
    SlotRect := ScreenRect(TPanel(Frame.Parent));
    if ScreenPoint.X < (SlotRect.Left + SlotRect.Right) div 2 then
      Exit(I);
  end;
  Result := Tools.Count;
end;

procedure TVectDockManager.LayoutDockArea(Side: TVectDockSide);
var
  Area: TPanel;
  Frame: TToolPlaceholderFrame;
  Splitter: TSplitter;
  Tools: TList<TToolPlaceholderFrame>;
  TotalWidth: Integer;
begin
  Area := AreaForSide(Side);
  Tools := ToolsForSide(Side);
  if Side = vdsLeft then
    Splitter := FLeftSplitter
  else
    Splitter := FRightSplitter;
  if Tools.Count = 0 then
  begin
    Area.Visible := False;
    Splitter.Visible := False;
    Exit;
  end;
  TotalWidth := MulDiv(DOCK_GAP, FOwnerForm.CurrentPPI, 96) *
    (Tools.Count - 1);
  for Frame in Tools do
    Inc(TotalWidth, MulDiv(Frame.PreferredDockWidth,
      FOwnerForm.CurrentPPI, 96));
  Area.Width := TotalWidth;
  Area.Visible := True;
  Splitter.Visible := True;
  ResizeDockArea(Side);
end;

procedure TVectDockManager.LayoutDockAreas;
begin
  FWorkspace.DisableAlign;
  try
    LayoutDockArea(vdsLeft);
    LayoutDockArea(vdsRight);
  finally
    FWorkspace.EnableAlign;
  end;
  FWorkspace.Realign;
  Resize;
end;

procedure TVectDockManager.LoadLayout(Ini: TCustomIniFile);
var
  BestFrame: TToolPlaceholderFrame;
  BestOrder: Integer;
  Bounds: TRect;
  Frame: TToolPlaceholderFrame;
  Order: Integer;
  Section: string;
  Side: TVectDockSide;
  State: string;
  Visible: Boolean;
  PPI: Integer;
begin
  PPI := FOwnerForm.CurrentPPI;
  FRestoring := True;
  try
    for Frame in FAllTools do
      if ToolVisible(Frame) then
        SetToolVisible(Frame, False);

    for Frame in FAllTools do
    begin
      Section := 'Tool.' + Frame.ToolId;
      Side := ReadToolSide(Ini, Frame);
      Order := Ini.ReadInteger(Section, 'Order',
        ToolsForSide(Side).Count);
      FLastSides.AddOrSetValue(Frame, Side);
      FLastIndices.AddOrSetValue(Frame, Order);
    end;

    for Side := Low(TVectDockSide) to High(TVectDockSide) do
      while True do
      begin
        BestFrame := nil;
        BestOrder := MaxInt;
        for Frame in FAllTools do
        begin
          Section := 'Tool.' + Frame.ToolId;
          Visible := Ini.ReadBool(Section, 'Visible', True);
          if not Visible or ToolVisible(Frame) or
            (ReadToolSide(Ini, Frame) <> Side) then
            Continue;
          Order := Ini.ReadInteger(Section, 'Order', BestOrder - 1);
          if Order < BestOrder then
          begin
            BestFrame := Frame;
            BestOrder := Order;
          end;
        end;
        if BestFrame = nil then
          Break;
        DockFrame(BestFrame, Side, ToolsForSide(Side).Count);
      end;

    for Frame in FAllTools do
    begin
      Section := 'Tool.' + Frame.ToolId;
      State := Ini.ReadString(Section, 'State', 'Docked');
      if ToolVisible(Frame) and SameText(State, 'Floating') then
      begin
        Bounds := Rect(
          Ini.ReadInteger(Section, 'FloatingLeft', 100),
          Ini.ReadInteger(Section, 'FloatingTop', 100),
          0, 0);
        Bounds.Right := Bounds.Left + MulDiv(Ini.ReadInteger(Section,
          'FloatingWidth', Max(Frame.PreferredDockWidth, 160)), PPI, 96);
        Bounds.Bottom := Bounds.Top + MulDiv(Ini.ReadInteger(Section,
          'FloatingHeight', 600), PPI, 96);
        Bounds.Right := Bounds.Left + Max(Bounds.Width,
          MulDiv(160, PPI, 96));
        Bounds.Bottom := Bounds.Top + Max(Bounds.Height,
          MulDiv(120, PPI, 96));
        Frame.FloatAt(ConstrainToolBounds(Bounds));
      end;
    end;
  finally
    FRestoring := False;
  end;
  FWorkspace.DisableAlign;
  try
    // Frame登録中の推奨幅再計算より、利用者が最後に決めた外枠幅を優先する。
    if FLeftTools.Count > 0 then
      FLeftArea.Width := Max(MulDiv(Ini.ReadInteger('DockAreas', 'LeftWidth',
        MulDiv(FLeftArea.Width, 96, PPI)), PPI, 96),
        MulDiv(DOCK_MIN_TOOL_WIDTH, PPI, 96));
    if FRightTools.Count > 0 then
      FRightArea.Width := Max(MulDiv(Ini.ReadInteger('DockAreas', 'RightWidth',
        MulDiv(FRightArea.Width, 96, PPI)), PPI, 96),
        MulDiv(DOCK_MIN_TOOL_WIDTH, PPI, 96));
  finally
    FWorkspace.EnableAlign;
  end;
  FWorkspace.Realign;
  Resize;
  if Assigned(FOnToolVisibilityChanged) then
    for Frame in FAllTools do
      FOnToolVisibilityChanged(Frame);
end;

function TVectDockManager.ReadToolSide(Ini: TCustomIniFile;
  Frame: TToolPlaceholderFrame): TVectDockSide;
var
  DefaultSide: TVectDockSide;
  SideText: string;
begin
  if not FLastSides.TryGetValue(Frame, DefaultSide) then
    DefaultSide := vdsLeft;
  SideText := Ini.ReadString('Tool.' + Frame.ToolId, 'Side', '');
  if SameText(SideText, 'Right') then
    Result := vdsRight
  else if SameText(SideText, 'Left') then
    Result := vdsLeft
  else
    Result := DefaultSide;
end;

procedure TVectDockManager.SaveLayout(Ini: TCustomIniFile);
var
  Bounds: TRect;
  Frame: TToolPlaceholderFrame;
  Index: Integer;
  Section: string;
  Side: TVectDockSide;
  PPI: Integer;
begin
  PPI := FOwnerForm.CurrentPPI;
  Ini.WriteInteger('DockAreas', 'LeftWidth',
    MulDiv(FLeftArea.Width, 96, PPI));
  Ini.WriteInteger('DockAreas', 'RightWidth',
    MulDiv(FRightArea.Width, 96, PPI));
  for Frame in FAllTools do
  begin
    Section := 'Tool.' + Frame.ToolId;
    Ini.WriteBool(Section, 'Visible', ToolVisible(Frame));
    if Frame.IsFloating then
      Ini.WriteString(Section, 'State', 'Floating')
    else if ToolVisible(Frame) then
      Ini.WriteString(Section, 'State', 'Docked')
    else
      Ini.WriteString(Section, 'State', 'Hidden');
    if not FLastSides.TryGetValue(Frame, Side) then
      Side := vdsLeft;
    if Side = vdsLeft then
      Ini.WriteString(Section, 'Side', 'Left')
    else
      Ini.WriteString(Section, 'Side', 'Right');
    Index := ToolsForSide(Side).IndexOf(Frame);
    if (Index < 0) and not FLastIndices.TryGetValue(Frame, Index) then
      Index := ToolsForSide(Side).Count;
    Ini.WriteInteger(Section, 'Order', Index);
    Bounds := Frame.FloatingBounds;
    Ini.WriteInteger(Section, 'FloatingLeft', Bounds.Left);
    Ini.WriteInteger(Section, 'FloatingTop', Bounds.Top);
    Ini.WriteInteger(Section, 'FloatingWidth', MulDiv(Bounds.Width, 96, PPI));
    Ini.WriteInteger(Section, 'FloatingHeight',
      MulDiv(Bounds.Height, 96, PPI));
  end;
end;

procedure TVectDockManager.RegisterTool(Frame: TToolPlaceholderFrame;
  DefaultSide: TVectDockSide; DefaultIndex: Integer);
begin
  if FAllTools.Contains(Frame) then
    Exit;
  FAllTools.Add(Frame);
  Frame.ConfigureFloatingOwner(FOwnerForm);
  Frame.OnCloseRequest := ToolCloseRequested;
  Frame.OnDetached := ToolDetached;
  Frame.OnDockRequest := ToolDockRequest;
  Frame.OnDragMove := ToolDragMove;
  if DefaultIndex < 0 then
    DefaultIndex := ToolsForSide(DefaultSide).Count;
  DockFrame(Frame, DefaultSide, DefaultIndex);
end;

procedure TVectDockManager.SetToolVisible(Frame: TToolPlaceholderFrame;
  const Value: Boolean);
var
  Index: Integer;
  Side: TVectDockSide;
  Slot: TWinControl;
begin
  if not FAllTools.Contains(Frame) or (ToolVisible(Frame) = Value) then
    Exit;
  if Value then
  begin
    if not FLastSides.TryGetValue(Frame, Side) then
      Side := vdsLeft;
    if not FLastIndices.TryGetValue(Frame, Index) then
      Index := ToolsForSide(Side).Count;
    DockFrame(Frame, Side, Index);
  end
  else
  begin
    HideDropTargets;
    if Frame.IsFloating then
      Frame.HideToolWindow
    else
    begin
      Slot := Frame.Parent;
      Index := FLeftTools.IndexOf(Frame);
      if Index >= 0 then
      begin
        Side := vdsLeft;
        FLeftTools.Delete(Index);
      end
      else
      begin
        Index := FRightTools.IndexOf(Frame);
        if Index < 0 then
          Exit;
        Side := vdsRight;
        FRightTools.Delete(Index);
      end;
      FLastSides.AddOrSetValue(Frame, Side);
      FLastIndices.AddOrSetValue(Frame, Index);
      Frame.HideToolWindow;
      Slot.Free;
      LayoutDockAreas;
    end;
  end;
  if not FRestoring and Assigned(FOnToolVisibilityChanged) then
    FOnToolVisibilityChanged(Frame);
end;

function TVectDockManager.ToolVisible(Frame: TToolPlaceholderFrame): Boolean;
begin
  Result := FAllTools.Contains(Frame) and
    (Frame.IsFloating or (Frame.Parent <> nil));
end;

procedure TVectDockManager.Resize;
var
  TargetWidth: Integer;
begin
  TargetWidth := MulDiv(DOCK_TARGET_WIDTH, FOwnerForm.CurrentPPI, 96);
  ResizeDockArea(vdsLeft);
  ResizeDockArea(vdsRight);
  if FLeftDropTarget.Visible then
    FLeftDropTarget.SetBounds(0, 0, TargetWidth, FWorkspace.ClientHeight);
  if FRightDropTarget.Visible then
    FRightDropTarget.SetBounds(FWorkspace.ClientWidth - TargetWidth, 0,
      TargetWidth, FWorkspace.ClientHeight);
end;

procedure TVectDockManager.ResizeDockArea(Side: TVectDockSide);
var
  Area: TPanel;
  FixedWidth: Integer;
  FlexibleIndex: Integer;
  FlexibleWidth: Integer;
  Frame: TToolPlaceholderFrame;
  I: Integer;
  Slot: TPanel;
  Tools: TList<TToolPlaceholderFrame>;
  X: Integer;
  DockGap: Integer;
  MinimumToolWidth: Integer;
begin
  Area := AreaForSide(Side);
  Tools := ToolsForSide(Side);
  if Tools.Count = 0 then
    Exit;

  // 外側スプリッターの増減分は、最も幅の広い主要ツールへ割り当てる。
  FlexibleIndex := 0;
  for I := 1 to Tools.Count - 1 do
    if Tools[I].PreferredDockWidth > Tools[FlexibleIndex].PreferredDockWidth then
      FlexibleIndex := I;
  DockGap := MulDiv(DOCK_GAP, FOwnerForm.CurrentPPI, 96);
  MinimumToolWidth := MulDiv(DOCK_MIN_TOOL_WIDTH,
    FOwnerForm.CurrentPPI, 96);
  FixedWidth := DockGap * (Tools.Count - 1);
  for I := 0 to Tools.Count - 1 do
    if I <> FlexibleIndex then
      Inc(FixedWidth, MulDiv(Tools[I].PreferredDockWidth,
        FOwnerForm.CurrentPPI, 96));
  FlexibleWidth := Max(Area.ClientWidth - FixedWidth, MinimumToolWidth);

  X := 0;
  for I := 0 to Tools.Count - 1 do
  begin
    Frame := Tools[I];
    Slot := TPanel(Frame.Parent);
    if I = FlexibleIndex then
      Slot.SetBounds(X, 0, FlexibleWidth, Area.ClientHeight)
    else
      Slot.SetBounds(X, 0, MulDiv(Frame.PreferredDockWidth,
        FOwnerForm.CurrentPPI, 96), Area.ClientHeight);
    Slot.Realign;
    Inc(X, Slot.Width + DockGap);
  end;
end;

function TVectDockManager.ScreenRect(Control: TPanel): TRect;
var
  BottomRight: TPoint;
  TopLeft: TPoint;
begin
  TopLeft := Control.ClientToScreen(Point(0, 0));
  BottomRight := Control.ClientToScreen(Point(Control.ClientWidth,
    Control.ClientHeight));
  Result := Rect(TopLeft.X, TopLeft.Y, BottomRight.X, BottomRight.Y);
end;

procedure TVectDockManager.SetLayoutEditing(const Value: Boolean);
var
  Frame: TToolPlaceholderFrame;
  Side: TVectDockSide;
begin
  if FLayoutEditing = Value then
    Exit;
  FLayoutEditing := Value;
  if not Value then
  begin
    HideDropTargets;
    for Frame in FAllTools do
      if Frame.IsFloating then
      begin
        if not FLastSides.TryGetValue(Frame, Side) then
          Side := vdsLeft;
        DockFrame(Frame, Side, ToolsForSide(Side).Count);
      end;
  end;
  for Frame in FAllTools do
    Frame.LayoutEditing := Value;
end;

procedure TVectDockManager.SplitterMoved(Sender: TObject);
begin
  if Sender = FLeftSplitter then
    ResizeDockArea(vdsLeft)
  else if Sender = FRightSplitter then
    ResizeDockArea(vdsRight);
end;

function TVectDockManager.ToolsForSide(
  Side: TVectDockSide): TList<TToolPlaceholderFrame>;
begin
  if Side = vdsLeft then
    Result := FLeftTools
  else
    Result := FRightTools;
end;

procedure TVectDockManager.ToolDetached(Sender: TToolPlaceholderFrame);
var
  Index: Integer;
  Side: TVectDockSide;
  Slot: TWinControl;
begin
  Slot := Sender.Parent;
  Index := FLeftTools.IndexOf(Sender);
  if Index >= 0 then
  begin
    Side := vdsLeft;
    FLeftTools.Delete(Index);
  end
  else
  begin
    Index := FRightTools.IndexOf(Sender);
    if Index < 0 then
      Exit;
    Side := vdsRight;
    FRightTools.Delete(Index);
  end;
  FLastSides.AddOrSetValue(Sender, Side);
  FLastIndices.AddOrSetValue(Sender, Index);
  Sender.Parent := nil;
  Slot.Free;
  LayoutDockAreas;
end;

procedure TVectDockManager.ToolCloseRequested(Sender: TToolPlaceholderFrame);
begin
  if FLayoutEditing then
    SetToolVisible(Sender, False);
end;

procedure TVectDockManager.ToolDockRequest(Sender: TToolPlaceholderFrame;
  const ScreenPoint: TPoint; var Accepted: Boolean);
var
  Index: Integer;
  Side: TVectDockSide;
begin
  Accepted := DropSideAt(ScreenPoint, Side);
  if Accepted then
  begin
    Index := InsertIndexAt(Side, ScreenPoint);
    DockFrame(Sender, Side, Index);
  end;
  HideDropTargets;
end;

procedure TVectDockManager.ToolDragMove(Sender: TToolPlaceholderFrame;
  const ScreenPoint: TPoint);
begin
  UpdateDropTargets(ScreenPoint);
end;

procedure TVectDockManager.UpdateDropTargets(const ScreenPoint: TPoint);
var
  Side: TVectDockSide;
begin
  FLeftDropTarget.Visible := True;
  FRightDropTarget.Visible := True;
  FLeftDropTarget.Color := COLOR_TARGET_IDLE;
  FRightDropTarget.Color := COLOR_TARGET_IDLE;
  if DropSideAt(ScreenPoint, Side) then
  begin
    if Side = vdsLeft then
      FLeftDropTarget.Color := COLOR_TARGET_HOT
    else
      FRightDropTarget.Color := COLOR_TARGET_HOT;
  end;
  Resize;
  FLeftDropTarget.BringToFront;
  FRightDropTarget.BringToFront;
end;

end.
