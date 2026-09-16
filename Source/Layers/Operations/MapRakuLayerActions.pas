// レイヤー構造操作をコード描画ボタンとして表示し、操作サービスへ入力を渡す。
unit MapRakuLayerActions;

interface

uses
  System.Classes, System.Types, Vcl.Controls, MapRakuDocument,
  MapRakuEditHistory, MapRakuEditorState,
  MapRakuLayerOperations;

type
  TVectArtLayerActionsControl = class(TCustomControl)
  private
    FOperations: TVectArtLayerOperations;
    function ButtonRect(Index: Integer): TRect;
    procedure DrawButton(Index: Integer);
    function GetDocument: TVectArtDocument;
    function GetEditHistory: TVectArtEditHistory;
    function GetEditorState: TVectArtEditorState;
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetEditHistory(const Value: TVectArtEditHistory);
    procedure SetEditorState(const Value: TVectArtEditorState);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // ボタンと同じ判定・履歴処理でレイヤー操作を実行する。
    function CanRunLayerAction(Action: TVectArtLayerAction): Boolean;
    procedure RunLayerAction(Action: TVectArtLayerAction);
    procedure RefreshState;
    property Document: TVectArtDocument read GetDocument write SetDocument;
    property EditHistory: TVectArtEditHistory read GetEditHistory write SetEditHistory;
    property EditorState: TVectArtEditorState read GetEditorState write SetEditorState;
  end;

implementation

uses
  Vcl.Graphics, Winapi.Windows;

const
  BUTTON_COUNT    = 5;
  BUTTON_SIZE     = 34;
  COLOR_BACKGROUND= TColor($00212121);
  COLOR_BUTTON    = TColor($002B2B2B);
  COLOR_DISABLED  = TColor($006A6A6A);
  COLOR_ICON      = TColor($00D8D8D8);

function TVectArtLayerActionsControl.ButtonRect(Index: Integer): TRect;
begin
  Result := Rect(Index * BUTTON_SIZE, 0, (Index + 1) * BUTTON_SIZE,
    MulDiv(ClientHeight, 96, CurrentPPI));
end;

constructor TVectArtLayerActionsControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  FOperations := TVectArtLayerOperations.Create;
end;

destructor TVectArtLayerActionsControl.Destroy;
begin
  FOperations.Free;
  inherited Destroy;
end;

function TVectArtLayerActionsControl.CanRunLayerAction(
  Action: TVectArtLayerAction): Boolean;
begin
  Result := FOperations.CanExecute(Action);
end;

procedure TVectArtLayerActionsControl.RunLayerAction(
  Action: TVectArtLayerAction);
begin
  FOperations.Execute(Action);
end;

procedure TVectArtLayerActionsControl.DrawButton(Index: Integer);
var
  Bounds: TRect;
  CenterX: Integer;
  CenterY: Integer;
begin
  Bounds := ButtonRect(Index);
  CenterX := (Bounds.Left + Bounds.Right) div 2;
  CenterY := (Bounds.Top + Bounds.Bottom) div 2;
  Canvas.Brush.Color := COLOR_BUTTON;
  Canvas.FillRect(Bounds);
  if FOperations.CanExecute(TVectArtLayerAction(Index)) then
    Canvas.Pen.Color := COLOR_ICON
  else
    Canvas.Pen.Color := COLOR_DISABLED;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  case TVectArtLayerAction(Index) of
    vlaAdd:
      begin
        Canvas.MoveTo(CenterX - 6, CenterY);
        Canvas.LineTo(CenterX + 6, CenterY);
        Canvas.MoveTo(CenterX, CenterY - 6);
        Canvas.LineTo(CenterX, CenterY + 6);
      end;
    vlaDuplicate:
      begin
        Canvas.Rectangle(CenterX - 7, CenterY - 5, CenterX + 5,
          CenterY + 7);
        Canvas.Rectangle(CenterX - 3, CenterY - 9, CenterX + 9,
          CenterY + 3);
      end;
    vlaDelete:
      begin
        Canvas.Rectangle(CenterX - 6, CenterY - 5, CenterX + 6,
          CenterY + 8);
        Canvas.MoveTo(CenterX - 8, CenterY - 8);
        Canvas.LineTo(CenterX + 8, CenterY - 8);
        Canvas.MoveTo(CenterX - 3, CenterY - 11);
        Canvas.LineTo(CenterX + 3, CenterY - 11);
      end;
    vlaMoveForward:
      begin
        Canvas.MoveTo(CenterX - 6, CenterY + 3);
        Canvas.LineTo(CenterX, CenterY - 4);
        Canvas.LineTo(CenterX + 6, CenterY + 3);
      end;
    vlaMoveBackward:
      begin
        Canvas.MoveTo(CenterX - 6, CenterY - 3);
        Canvas.LineTo(CenterX, CenterY + 4);
        Canvas.LineTo(CenterX + 6, CenterY - 3);
      end;
  end;
end;

function TVectArtLayerActionsControl.GetDocument: TVectArtDocument;
begin
  Result := FOperations.Document;
end;

function TVectArtLayerActionsControl.GetEditHistory: TVectArtEditHistory;
begin
  Result := FOperations.EditHistory;
end;

function TVectArtLayerActionsControl.GetEditorState: TVectArtEditorState;
begin
  Result := FOperations.EditorState;
end;

procedure TVectArtLayerActionsControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  if Button = mbLeft then
  begin
    Index := MulDiv(X, 96, CurrentPPI) div BUTTON_SIZE;
    if (Index >= 0) and (Index < BUTTON_COUNT) then
      FOperations.Execute(TVectArtLayerAction(Index));
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtLayerActionsControl.Paint;
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
      DrawButton(I);
  finally
    RestoreDC(Canvas.Handle, SavedDC);
  end;
end;

procedure TVectArtLayerActionsControl.RefreshState;
begin
  Invalidate;
end;

procedure TVectArtLayerActionsControl.SetDocument(
  const Value: TVectArtDocument);
begin
  FOperations.Document := Value;
  RefreshState;
end;

procedure TVectArtLayerActionsControl.SetEditHistory(
  const Value: TVectArtEditHistory);
begin
  FOperations.EditHistory := Value;
end;

procedure TVectArtLayerActionsControl.SetEditorState(
  const Value: TVectArtEditorState);
begin
  FOperations.EditorState := Value;
end;

end.
