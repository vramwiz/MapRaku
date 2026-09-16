// レイヤー一覧のマウス入力、ドラッグ移動、スクロールと共有モデルの接続を担当する。
unit MapRakuLayerList;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Direct2D, Vcl.ExtCtrls,
  MapRakuDocument, MapRakuEditCommands, MapRakuEditHistory,
  MapRakuEditorState, MapRakuLayerRenderer, MapRakuLayerSelection,
  VerticalScrollBarControl;

type
  TMapRakuLayerContextMenuEvent = procedure(Sender: TObject;
    const ScreenPoint: TPoint) of object;

  TMapRakuLayerDropMode = (sldmNone, sldmReorder, sldmIntoGroup);

  TVectArtLayerListControl = class(TCustomControl)
  private
    FDirect2DEnabled      : Boolean;                     // Direct2D失敗後はGDI描画へ切り替える。
    FDocument             : TVectArtDocument;            // 編集対象の文書。所有しない。
    FEditHistory          : TVectArtEditHistory;         // 階層移動と状態変更を記録する履歴。
    FEditorState          : TVectArtEditorState;         // 開いたグループと選択の共有状態。
    FDragCandidateIndex   : Integer;                     // 押下した表示行。負値はドラッグ候補なし。
    FDragStartPoint       : TPoint;                      // ドラッグ開始閾値を判定するクライアント座標。
    FDraggingLayer        : Boolean;                     // 移動量が閾値を超えてドラッグ中か。
    FDragDropMode         : TMapRakuLayerDropMode;  // 現在のドロップ候補の種別。
    FDragIndicatorY       : Integer;                     // 行間へ挿入する位置の表示座標。
    FDragSourceIndices    : TArray<Integer>;             // 移動元コンテナ内の昇順レイヤー位置。
    FDragSourceGroup      : TMapRakuGroupLayer;     // 移動元の親。nilは文書直下。
    FDragScrollDirection  : Integer;                     // 端での自動スクロール方向。0は停止。
    FDragScrollTimer      : TTimer;                      // ドラッグ中の端スクロール周期を管理する。
    FDragTargetIndex      : Integer;                     // ドロップ先の表示行。
    FDragTargetGroup      : TMapRakuGroupLayer;     // グループへ入れる場合の移動先。
    FDragTargetParent     : TMapRakuGroupLayer;     // 並べ替え先の親。nilは文書直下。
    FDragTargetSourceIndex: Integer;                     // 移動元を除いた後の挿入位置。
    FHoverTargetGroup     : TMapRakuGroupLayer;     // 一定時間ポイントすると展開するグループ。
    FHoverTimer           : TTimer;                      // グループのホバー展開待ち時間を管理する。
    FRenderer             : TVectArtLayerRenderer;       // 表示行の配置・当たり判定・描画を所有する。
    FSelection            : TMapRakuLayerSelection; // クリック選択と範囲アンカーを所有する。
    FScrollBar            : TVerticalScrollBarControl;   // 文書の積層順に対応する縦スクロールUI。
    FUpdatingScrollBar    : Boolean;                     // 表示更新によるスクロール通知の再入を抑止する。
    FOnObjectContextMenu  : TMapRakuLayerContextMenuEvent;
    function DragSourcesEditable: Boolean;
    function IsDragSourceLayer(Layer: TVectArtLayer): Boolean;
    function LayerBounds: TRect;
    procedure ResetDragState;
    procedure RestoreDragSourceContext;
    procedure DragScrollTimerTick(Sender: TObject);
    function SelectedSourceIndices(Parent: TMapRakuGroupLayer): TArray<Integer>;
    function ScrollBarWidth: Integer;
    procedure ScrollBarChanged(Sender: TObject);
    procedure SetHoverTarget(Value: TMapRakuGroupLayer);
    procedure SetDragScrollDirection(Value: Integer);
    procedure SyncRendererContext;
    procedure HoverTimerTick(Sender: TObject);
    procedure ToggleGroupExpanded(Group: TMapRakuGroupLayer; Parent: TMapRakuGroupLayer);
    procedure UpdateScrollBar;
    procedure PaintDirect2D;
    procedure PaintGDI;
    procedure SetDocument(const Value: TVectArtDocument);
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
  public
    // 描画・選択の委譲先とドラッグ用タイマーを生成する。
    constructor Create(AOwner: TComponent); override;
    // 所有する描画・選択処理を破棄する。子コントロールとタイマーはOwnerに従う。
    destructor Destroy; override;
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditHistory: TVectArtEditHistory read FEditHistory write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState write FEditorState;
    property OnObjectContextMenu: TMapRakuLayerContextMenuEvent
      read FOnObjectContextMenu write FOnObjectContextMenu;
  end;

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils, Winapi.Windows,
  Vcl.Graphics,
  MapRakuGroupChildCommands;

const
  COLOR_LIST_BACKGROUND = TColor($001A1A1A);
  COLOR_DROP_TARGET     = TColor($00D69C4A);
  LAYER_DRAG_THRESHOLD  = 5;
  DRAG_SCROLL_INTERVAL  = 50;
  DRAG_SCROLL_MARGIN    = 28;
  DRAG_SCROLL_PIXELS    = 12;
  GROUP_HOVER_OPEN_DELAY= 700;
  LAYER_SCROLL_BAR_WIDTH= 14;
  LAYER_WHEEL_ROWS      = 3;

constructor TVectArtLayerListControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_LIST_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FDirect2DEnabled := TDirect2DCanvas.Supported;
  FRenderer := TVectArtLayerRenderer.Create;
  FSelection := TMapRakuLayerSelection.Create;
  FDragScrollTimer := TTimer.Create(Self);
  FDragScrollTimer.Enabled := False;
  FDragScrollTimer.Interval := DRAG_SCROLL_INTERVAL;
  FDragScrollTimer.OnTimer := DragScrollTimerTick;
  FHoverTimer := TTimer.Create(Self);
  FHoverTimer.Enabled := False;
  FHoverTimer.Interval := GROUP_HOVER_OPEN_DELAY;
  FHoverTimer.OnTimer := HoverTimerTick;
  FScrollBar := TVerticalScrollBarControl.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Visible := False;
  FScrollBar.OnChange := ScrollBarChanged;
  FSelection.ResetAnchor;
  FSelection.ResetClick;
  FDragCandidateIndex := -1;
  FDragDropMode := sldmNone;
  FDragIndicatorY := -1;
  FDragTargetIndex := -1;
  FDragTargetSourceIndex := -1;
end;

procedure TVectArtLayerListControl.DragScrollTimerTick(Sender: TObject);
var
  ClientPoint: TPoint;
  NewOffset: Integer;
  ScreenPoint: TPoint;
begin
  if not FDraggingLayer or (FDragScrollDirection = 0) then
  begin
    SetDragScrollDirection(0);
    Exit;
  end;
  NewOffset := FRenderer.ScrollOffset +
    FDragScrollDirection * MulDiv(DRAG_SCROLL_PIXELS, CurrentPPI, 96);
  FRenderer.ScrollOffset := NewOffset;
  UpdateScrollBar;
  if FRenderer.ScrollOffset = NewOffset then
  begin
    GetCursorPos(ScreenPoint);
    ClientPoint := ScreenToClient(ScreenPoint);
    MouseMove([ssLeft], ClientPoint.X, ClientPoint.Y);
  end
  else
    SetDragScrollDirection(0);
end;

function TVectArtLayerListControl.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Delta: Integer;
begin
  UpdateScrollBar;
  Result := FScrollBar.Visible and (WheelDelta <> 0);
  if Result then
  begin
    Delta := MulDiv(WheelDelta,
      FRenderer.ScrollStep * LAYER_WHEEL_ROWS, WHEEL_DELTA);
    FRenderer.ScrollOffset := FRenderer.ScrollOffset + Delta;
    UpdateScrollBar;
    Invalidate;
  end
  else
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

function TVectArtLayerListControl.LayerBounds: TRect;
begin
  Result := ClientRect;
  if (FScrollBar <> nil) and FScrollBar.Visible then
    Result.Right := Max(Result.Left,
      Result.Right - FScrollBar.Width - 1);
end;

function TVectArtLayerListControl.DragSourcesEditable: Boolean;
var
  Index: Integer;
begin
  Result := Length(FDragSourceIndices) > 0;
  if not Result then
    Exit;
  for Index in FDragSourceIndices do
    if FDragSourceGroup <> nil then
    begin
      if (Index < 0) or (Index >= FDragSourceGroup.ChildCount) or
        FDragSourceGroup[Index].Locked then
        Exit(False);
    end
    else if (FDocument = nil) or (Index <= 0) or
      (Index >= FDocument.LayerCount) or FDocument[Index].Locked then
      Exit(False);
end;

function TVectArtLayerListControl.IsDragSourceLayer(
  Layer: TVectArtLayer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index in FDragSourceIndices do
    if FDragSourceGroup <> nil then
    begin
      if (Index >= 0) and (Index < FDragSourceGroup.ChildCount) and
        (FDragSourceGroup[Index] = Layer) then
        Exit(True);
    end
    else if (FDocument <> nil) and (Index > 0) and
      (Index < FDocument.LayerCount) and (FDocument[Index] = Layer) then
      Exit(True);
end;

procedure TVectArtLayerListControl.HoverTimerTick(Sender: TObject);
var
  Target: TMapRakuGroupLayer;
begin
  FHoverTimer.Enabled := False;
  Target := FHoverTargetGroup;
  FHoverTargetGroup := nil;
  if not FDraggingLayer or (Target = nil) or (FEditorState = nil) then
    Exit;
  FEditorState.OpenGroupInDocument(FDocument, Target);
  if FEditorState.OpenGroup <> Target then
    Exit;
  FDragDropMode := sldmIntoGroup;
  FDragTargetGroup := Target;
  FDragTargetIndex := -1;
  FSelection.ResetAnchor;
  SyncRendererContext;
  UpdateScrollBar;
  Invalidate;
end;

procedure TVectArtLayerListControl.ToggleGroupExpanded(
  Group: TMapRakuGroupLayer; Parent: TMapRakuGroupLayer);
begin
  if (FEditorState = nil) or (Group = nil) then
    Exit;
  if FEditorState.IsGroupInOpenPath(Group) then
  begin
    if Parent <> nil then
      FEditorState.OpenGroupInDocument(FDocument, Parent)
    else
      FEditorState.OpenGroup := nil;
  end
  else
    FEditorState.OpenGroupInDocument(FDocument, Group);
  FSelection.ResetAnchor;
  ResetDragState;
  Invalidate;
end;

function TVectArtLayerListControl.ScrollBarWidth: Integer;
begin
  Result := MulDiv(LAYER_SCROLL_BAR_WIDTH, CurrentPPI, 96);
end;

destructor TVectArtLayerListControl.Destroy;
begin
  FSelection.Free;
  FRenderer.Free;
  inherited Destroy;
end;

procedure TVectArtLayerListControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  ItemRect: TRect;
  Layer: TVectArtLayer;
  NewValue: Boolean;
  Command: TVectArtEditCommand;
  Parent: TMapRakuGroupLayer;
  SourceIndex: Integer;
begin
  if (Button = mbRight) and (FDocument <> nil) then
  begin
    SyncRendererContext;
    Index := FRenderer.LayerIndexAt(LayerBounds, Y);
    if Index > 0 then
    begin
      Layer := FRenderer.LayerAt(Index);
      Parent := FRenderer.LayerParentAt(Index);
      SourceIndex := FRenderer.LayerSourceIndexAt(Index);
      FSelection.SelectLayer(FDocument, FEditorState, Parent, Layer,
        SourceIndex, []);
      FSelection.CompleteClick(Layer, SourceIndex);
      Invalidate;
    end;
    if Assigned(FOnObjectContextMenu) then
      FOnObjectContextMenu(Self, ClientToScreen(Point(X, Y)));
    Exit;
  end;
  if (Button = mbLeft) and (FDocument <> nil) then
  begin
    ResetDragState;
    SyncRendererContext;
    if CanFocus then
      SetFocus;
    Index := FRenderer.LayerIndexAt(LayerBounds, Y);
    if Index > 0 then
    begin
      ItemRect := FRenderer.LayerItemRect(LayerBounds, Index);
      Layer := FRenderer.LayerAt(Index);
      Parent := FRenderer.LayerParentAt(Index);
      SourceIndex := FRenderer.LayerSourceIndexAt(Index);
      if (Layer is TMapRakuGroupLayer) and
        PtInRect(FRenderer.ExpandButtonRect(ItemRect), Point(X, Y)) then
      begin
        if (ssDouble in Shift) and not (ssCtrl in Shift) and not (ssShift in Shift) then
          ToggleGroupExpanded(TMapRakuGroupLayer(Layer), Parent);
        Exit;
      end;
      if (ssDouble in Shift) and not (ssCtrl in Shift) and not (ssShift in Shift) and
        (Layer is TMapRakuGroupLayer) and
        (FEditorState <> nil) then
      begin
        ToggleGroupExpanded(TMapRakuGroupLayer(Layer), Parent);
        Exit;
      end;
      if PtInRect(FRenderer.VisibilityButtonRect(ItemRect), Point(X, Y)) then
      begin
        NewValue := not Layer.Visible;
        if Parent <> nil then
          Command := TMapRakuGroupChildBooleanCommand.Create(FDocument,
            Layer, vlbpVisible, not NewValue, NewValue)
        else
          Command := TVectArtLayerBooleanCommand.Create(FDocument,
            SourceIndex,
            vlbpVisible, not NewValue, NewValue);
        Command.Execute;
        if FEditHistory <> nil then
          FEditHistory.AddApplied(Command)
        else
          Command.Free;
        Exit;
      end;
      if PtInRect(FRenderer.LockButtonRect(ItemRect), Point(X, Y)) then
      begin
        NewValue := not Layer.Locked;
        if Parent <> nil then
          Command := TMapRakuGroupChildBooleanCommand.Create(FDocument,
            Layer, vlbpLocked, not NewValue, NewValue)
        else
          Command := TVectArtLayerBooleanCommand.Create(FDocument,
            SourceIndex,
            vlbpLocked, not NewValue, NewValue);
        Command.Execute;
        if FEditHistory <> nil then
          FEditHistory.AddApplied(Command)
        else
          Command.Free;
        Exit;
      end;
      if (Layer is TMapRakuGroupLayer) and (FEditorState <> nil) and
        FEditorState.IsGroupInOpenPath(TMapRakuGroupLayer(Layer)) then
        Exit;
      if (FEditorState <> nil) and
        (FEditorState.SelectedFilter <> nil) then
        FEditorState.SelectFilter(nil, nil);
      FSelection.SelectLayer(FDocument, FEditorState, Parent, Layer, SourceIndex, Shift);
      if FSelection.PendingLayer <> nil then MouseCapture := True;
      Invalidate;
      if not (ssShift in Shift) and not (ssCtrl in Shift) and
        not Layer.Locked then
      begin
        FDragCandidateIndex := Index;
        FDragDropMode := sldmReorder;
        FDragSourceGroup := Parent;
        FDragSourceIndices := SelectedSourceIndices(Parent);
        if not DragSourcesEditable then
        begin
          FDragCandidateIndex := -1;
          Exit;
        end;
        FDragTargetIndex := Index;
        FDragTargetGroup := nil;
        FDragTargetParent := Parent;
        FDragTargetSourceIndex := SourceIndex;
        FDragStartPoint := Point(X, Y);
        MouseCapture := True;
      end;
      Exit;
    end;
    if not (ssCtrl in Shift) and not (ssShift in Shift) then
    begin
      if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
        FEditorState.SetOpenGroupChildren([]);
      FDocument.SetSelectedLayers([]);
      FSelection.ResetAnchor;
      Invalidate;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtLayerListControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  I: Integer;
  Index: Integer;
  ItemRect: TRect;
  Layer: TVectArtLayer;
  MiddleMargin: Integer;
  OpenGroup: TMapRakuGroupLayer;
  TargetSourceIndex: Integer;
begin
  if (FDragCandidateIndex > 0) and (ssLeft in Shift) then
  begin
    if not FDraggingLayer and
      ((Abs(X - FDragStartPoint.X) >=
        MulDiv(LAYER_DRAG_THRESHOLD, CurrentPPI, 96)) or
       (Abs(Y - FDragStartPoint.Y) >=
        MulDiv(LAYER_DRAG_THRESHOLD, CurrentPPI, 96))) then
      FDraggingLayer := True;
    if FDraggingLayer then
    begin
      if Y < LayerBounds.Top + MulDiv(DRAG_SCROLL_MARGIN,
        CurrentPPI, 96) then
        SetDragScrollDirection(1)
      else if Y >= LayerBounds.Bottom - MulDiv(DRAG_SCROLL_MARGIN,
        CurrentPPI, 96) then
        SetDragScrollDirection(-1)
      else
        SetDragScrollDirection(0);
      OpenGroup := nil;
      if FEditorState <> nil then
        OpenGroup := FEditorState.OpenGroup;
      FDragDropMode := sldmNone;
      FDragTargetGroup := nil;
      Index := FRenderer.LayerIndexAt(LayerBounds, Y);
      if Index > 0 then
      begin
        FDragTargetIndex := Index;
        Layer := FRenderer.LayerAt(Index);
        FDragTargetParent := FRenderer.LayerParentAt(Index);
        TargetSourceIndex := FRenderer.LayerSourceIndexAt(Index);
        ItemRect := FRenderer.LayerItemRect(LayerBounds, Index);
        MiddleMargin := Max(ItemRect.Height div 4, 1);
        if (Layer is TMapRakuGroupLayer) and not Layer.Locked and
          not IsDragSourceLayer(Layer) and
          (Y >= ItemRect.Top + MiddleMargin) and
          (Y < ItemRect.Bottom - MiddleMargin) then
        begin
          FDragDropMode := sldmIntoGroup;
          FDragTargetGroup := TMapRakuGroupLayer(Layer);
          SetHoverTarget(FDragTargetGroup);
        end
        else
        begin
          SetHoverTarget(nil);
          if not IsDragSourceLayer(Layer) then
          begin
            FDragDropMode := sldmReorder;
            if Y < ItemRect.Top + ItemRect.Height div 2 then
            begin
              FDragTargetSourceIndex := TargetSourceIndex + 1;
              FDragIndicatorY := ItemRect.Top;
            end
            else
            begin
              FDragTargetSourceIndex := TargetSourceIndex;
              FDragIndicatorY := ItemRect.Bottom;
            end;
            if FDragTargetParent = FDragSourceGroup then
              for I in FDragSourceIndices do
                if I < FDragTargetSourceIndex then
                  Dec(FDragTargetSourceIndex);
          end;
        end;
      end;
      if Index <= 0 then
      begin
        SetHoverTarget(nil);
        if OpenGroup <> FDragSourceGroup then
        begin
          FDragDropMode := sldmIntoGroup;
          FDragTargetGroup := OpenGroup;
          FDragTargetIndex := -1;
        end;
      end;
      Cursor := crSizeAll;
      Invalidate;
      Exit;
    end;
  end;
  inherited MouseMove(Shift, X, Y);
end;

procedure TVectArtLayerListControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Command: TVectArtEditCommand;
  DestinationIndex: Integer;
  MoveApplied: Boolean;
  Index: Integer;
begin
  if (Button = mbLeft) and not FDraggingLayer and (FSelection.PendingLayer <> nil) then
  begin
    SyncRendererContext;
    Index := FRenderer.LayerIndexAt(LayerBounds, Y);
    if (Index > 0) and (FRenderer.LayerAt(Index) = FSelection.PendingLayer) and
      PtInRect(LayerBounds, Point(X, Y)) then
    begin
      FSelection.CompleteClick(FRenderer.LayerAt(Index), FRenderer.LayerSourceIndexAt(Index));
    end;
    ResetDragState;
    Invalidate;
    Exit;
  end;
  if (Button = mbLeft) and (FDragCandidateIndex > 0) then
  begin
    MouseCapture := False;
    MoveApplied := False;
    if FDraggingLayer and (FEditorState <> nil) and
      (FDragDropMode = sldmIntoGroup) and
      (FDragTargetGroup <> nil) then
    begin
      DestinationIndex := FDragTargetGroup.ChildCount;
      if FDragTargetGroup = FDragSourceGroup then
        Dec(DestinationIndex, Length(FDragSourceIndices));
      Command := TMapRakuReparentLayersCommand.Create(FDocument,
        FEditorState, FDragSourceGroup, FDragSourceIndices, FDragTargetGroup,
        DestinationIndex);
      Command.Execute;
      if FEditHistory <> nil then
        FEditHistory.AddApplied(Command)
      else
        Command.Free;
      MoveApplied := True;
      FSelection.ResetAnchor;
    end
    else if FDraggingLayer and (FDragDropMode = sldmReorder) and
      (FDragTargetSourceIndex >= 0) then
    begin
      Command := TMapRakuReparentLayersCommand.Create(FDocument,
        FEditorState, FDragSourceGroup, FDragSourceIndices,
        FDragTargetParent, FDragTargetSourceIndex);
      Command.Execute;
      if FEditHistory <> nil then
        FEditHistory.AddApplied(Command)
      else
        Command.Free;
      MoveApplied := True;
      FSelection.ResetAnchor;
    end;
    if FDraggingLayer and not MoveApplied then
      RestoreDragSourceContext;
    ResetDragState;
    Invalidate;
    Exit;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TVectArtLayerListControl.Paint;
begin
  SyncRendererContext;
  UpdateScrollBar;
  if FDirect2DEnabled then
    try
      PaintDirect2D;
      UpdateScrollBar;
      Exit;
    except
      FDirect2DEnabled := False;
    end;
  PaintGDI;
  UpdateScrollBar;
end;

procedure TVectArtLayerListControl.ResetDragState;
begin
  SetDragScrollDirection(0);
  SetHoverTarget(nil);
  MouseCapture := False;
  FSelection.ResetClick;
  FDragCandidateIndex := -1;
  FDragDropMode := sldmNone;
  FDragIndicatorY := -1;
  SetLength(FDragSourceIndices, 0);
  FDragSourceGroup := nil;
  FDragTargetIndex := -1;
  FDragTargetGroup := nil;
  FDragTargetParent := nil;
  FDragTargetSourceIndex := -1;
  FDraggingLayer := False;
  Cursor := crDefault;
end;

procedure TVectArtLayerListControl.RestoreDragSourceContext;
begin
  if FEditorState = nil then
    Exit;
  if FDragSourceGroup <> nil then
    FEditorState.OpenGroupInDocument(FDocument, FDragSourceGroup)
  else
    FEditorState.OpenGroup := nil;
end;

function TVectArtLayerListControl.SelectedSourceIndices(
  Parent: TMapRakuGroupLayer): TArray<Integer>;
var
  I: Integer;
  Indices: TList<Integer>;
begin
  if Parent = nil then
    Exit(FDocument.GetSelectedLayerIndices);
  Indices := TList<Integer>.Create;
  try
    for I := 0 to Parent.ChildCount - 1 do
      if FEditorState.IsOpenGroupChildSelected(Parent[I]) then
        Indices.Add(I);
    Result := Indices.ToArray;
  finally
    Indices.Free;
  end;
end;

procedure TVectArtLayerListControl.SyncRendererContext;
begin
  FRenderer.EditorState := FEditorState;
  FRenderer.PPI := CurrentPPI;
end;

procedure TVectArtLayerListControl.PaintDirect2D;
var
  Direct2DCanvas: TDirect2DCanvas;
  IndicatorY: Integer;
  TargetRect: TRect;
begin
  Direct2DCanvas := TDirect2DCanvas.Create(Canvas, LayerBounds);
  try
    Direct2DCanvas.BeginDraw;
    try
      FRenderer.DrawLayers(Direct2DCanvas, LayerBounds);
      if FDraggingLayer and (FDragDropMode = sldmIntoGroup) and
        (FDragTargetIndex > 0) then
      begin
        TargetRect := FRenderer.LayerItemRect(LayerBounds,
          FDragTargetIndex);
        Direct2DCanvas.Brush.Style := bsClear;
        Direct2DCanvas.Pen.Color := COLOR_DROP_TARGET;
        Direct2DCanvas.Pen.Width := MulDiv(3, CurrentPPI, 96);
        Direct2DCanvas.Rectangle(TargetRect);
        Direct2DCanvas.Pen.Width := 1;
      end
      else if FDraggingLayer and (FDragDropMode = sldmReorder) and
        (FDragTargetIndex > 0) and
        (FDragTargetIndex <> FDragCandidateIndex) then
      begin
        TargetRect := FRenderer.LayerItemRect(LayerBounds,
          FDragTargetIndex);
        IndicatorY := FDragIndicatorY;
        Direct2DCanvas.Pen.Color := COLOR_DROP_TARGET;
        Direct2DCanvas.Pen.Width := MulDiv(3, CurrentPPI, 96);
        Direct2DCanvas.MoveTo(TargetRect.Left, IndicatorY);
        Direct2DCanvas.LineTo(TargetRect.Right, IndicatorY);
        Direct2DCanvas.Pen.Width := 1;
      end;
    finally
      Direct2DCanvas.EndDraw;
    end;
  finally
    Direct2DCanvas.Free;
  end;
end;

procedure TVectArtLayerListControl.PaintGDI;
var
  IndicatorY: Integer;
  TargetRect: TRect;
begin
  FRenderer.DrawLayers(Canvas, LayerBounds);
  if FDraggingLayer and (FDragDropMode = sldmIntoGroup) and
    (FDragTargetIndex > 0) then
  begin
    TargetRect := FRenderer.LayerItemRect(LayerBounds, FDragTargetIndex);
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := COLOR_DROP_TARGET;
    Canvas.Pen.Width := MulDiv(3, CurrentPPI, 96);
    Canvas.Rectangle(TargetRect);
    Canvas.Pen.Width := 1;
  end
  else if FDraggingLayer and (FDragDropMode = sldmReorder) and
    (FDragTargetIndex > 0) and
    (FDragTargetIndex <> FDragCandidateIndex) then
  begin
    TargetRect := FRenderer.LayerItemRect(LayerBounds, FDragTargetIndex);
    IndicatorY := FDragIndicatorY;
    Canvas.Pen.Color := COLOR_DROP_TARGET;
    Canvas.Pen.Width := MulDiv(3, CurrentPPI, 96);
    Canvas.MoveTo(TargetRect.Left, IndicatorY);
    Canvas.LineTo(TargetRect.Right, IndicatorY);
    Canvas.Pen.Width := 1;
  end;
end;

procedure TVectArtLayerListControl.Resize;
begin
  inherited;
  if FScrollBar <> nil then
  begin
    FScrollBar.SetBounds(Max(ClientWidth - ScrollBarWidth, 0), 0,
      ScrollBarWidth, ClientHeight);
    UpdateScrollBar;
  end;
end;

procedure TVectArtLayerListControl.ScrollBarChanged(Sender: TObject);
begin
  if FUpdatingScrollBar then
    Exit;
  FRenderer.ScrollOffset := FScrollBar.Maximum - FScrollBar.Position;
  Invalidate;
end;

procedure TVectArtLayerListControl.SetHoverTarget(
  Value: TMapRakuGroupLayer);
begin
  if FHoverTargetGroup = Value then
    Exit;
  FHoverTimer.Enabled := False;
  FHoverTargetGroup := Value;
  FHoverTimer.Enabled := Value <> nil;
end;

procedure TVectArtLayerListControl.SetDragScrollDirection(Value: Integer);
begin
  Value := Sign(Value);
  if FDragScrollDirection = Value then
    Exit;
  FDragScrollTimer.Enabled := False;
  FDragScrollDirection := Value;
  FDragScrollTimer.Enabled := Value <> 0;
end;

procedure TVectArtLayerListControl.SetDocument(
  const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  ResetDragState;
  FDocument := Value;
  FSelection.ResetAnchor;
  FDragCandidateIndex := -1;
  FDragTargetIndex := -1;
  FDraggingLayer := False;
  FRenderer.Document := Value;
  UpdateScrollBar;
  Invalidate;
end;

procedure TVectArtLayerListControl.UpdateScrollBar;
var
  Bounds: TRect;
  MaximumOffset: Integer;
begin
  if (FScrollBar = nil) or (FRenderer = nil) then
    Exit;
  SyncRendererContext;
  Bounds := LayerBounds;
  MaximumOffset := FRenderer.MaximumScrollOffset(Bounds);
  FUpdatingScrollBar := True;
  try
    FScrollBar.Visible := MaximumOffset > 0;
    FScrollBar.SetBounds(Max(ClientWidth - ScrollBarWidth, 0), 0,
      ScrollBarWidth, ClientHeight);
    Bounds := LayerBounds;
    MaximumOffset := FRenderer.MaximumScrollOffset(Bounds);
    FRenderer.ScrollOffset := EnsureRange(FRenderer.ScrollOffset, 0,
      MaximumOffset);
    FScrollBar.SmallChange := FRenderer.ScrollStep;
    FScrollBar.LargeChange := Max(Bounds.Height -
      FRenderer.ScrollStep, FRenderer.ScrollStep);
    FScrollBar.SetRange(MaximumOffset, Max(Bounds.Height, 1));
    FScrollBar.Position := MaximumOffset - FRenderer.ScrollOffset;
  finally
    FUpdatingScrollBar := False;
  end;
end;

end.
