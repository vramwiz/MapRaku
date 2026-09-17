// 選択・図形作成ツールをコード描画アイコンで選択するControlを提供する。
unit MapRakuToolPalette;

interface

uses
  System.Classes, System.Types, Vcl.Controls, MapRakuDocument,
  MapRakuEditorState;

const
  MAPRAKU_TOOL_SELECTED_COLOR = $00CE7818; // 明るい青。地図プリセットとも共用する。
  MAPRAKU_TOOL_SELECTED_BORDER = $00FFCC6C;

type
  TVectArtToolPaletteControl = class(TCustomControl)
  private
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    function ButtonRect(Index: Integer): TRect;
    function ButtonSelected(Index: Integer): Boolean;
    function ButtonTool(Index: Integer): TVectArtEditorTool;
    function ColorSwatchRect: TRect;
    procedure DrawButton(Index: Integer);
    procedure DrawColorSwatch;
    procedure SetEditorState(const Value: TVectArtEditorState);
    procedure SetDocument(const Value: TVectArtDocument);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshState;
    property EditorState: TVectArtEditorState read FEditorState
      write SetEditorState;
    property Document: TVectArtDocument read FDocument write SetDocument;
  end;

implementation

uses
  Vcl.Graphics, Winapi.Windows;

const
  BUTTON_SIZE = 40;
  BUTTON_GAP = 3;
  PALETTE_BUTTON_COUNT = 10;
  COLOR_SWATCH_SIZE = 28;
  COLOR_BACKGROUND = TColor($00252525);
  COLOR_BUTTON = TColor($002D2D2D);
  COLOR_ICON = TColor($00E0E0E0);
  COLOR_SHAPE_FILL = TColor($00808080);

procedure DrawPathKindIcon(ACanvas: TCanvas; CenterX, CenterY: Integer;
  Closed: Boolean; Kind: TMapRakuVertexKind);
var
  Anchors: array[0..3] of TPoint;
  BezierPoints: TArray<TPoint>;
  I: Integer;
begin
  Anchors[0] := Point(CenterX - 12, CenterY + 7);
  Anchors[1] := Point(CenterX - 5, CenterY - 7);
  Anchors[2] := Point(CenterX + 3, CenterY + 5);
  Anchors[3] := Point(CenterX + 12, CenterY - 5);
  if Closed then
    Anchors[3] := Point(CenterX + 10, CenterY + 8);
  if Closed then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_SHAPE_FILL;
  end;
  if Kind = slvkSharp then
  begin
    if Closed then
      ACanvas.Polygon(Anchors)
    else
    begin
      ACanvas.MoveTo(Anchors[0].X, Anchors[0].Y);
      for I := 1 to High(Anchors) do
        ACanvas.LineTo(Anchors[I].X, Anchors[I].Y);
    end;
  end
  else
  begin
    SetLength(BezierPoints, 10 + Ord(Closed) * 3);
    BezierPoints[0] := Anchors[0];
    BezierPoints[1] := Point(CenterX - 11, CenterY - 2);
    BezierPoints[2] := Point(CenterX - 8, CenterY - 8);
    BezierPoints[3] := Anchors[1];
    BezierPoints[4] := Point(CenterX - 2, CenterY - 6);
    BezierPoints[5] := Point(CenterX, CenterY + 5);
    BezierPoints[6] := Anchors[2];
    BezierPoints[7] := Point(CenterX + 7, CenterY + 5);
    BezierPoints[8] := Point(CenterX + 10, CenterY - 5);
    BezierPoints[9] := Anchors[3];
    if Closed then
    begin
      BezierPoints[10] := Point(CenterX + 3, CenterY + 11);
      BezierPoints[11] := Point(CenterX - 8, CenterY + 11);
      BezierPoints[12] := Anchors[0];
    end;
    if Closed then
      BeginPath(ACanvas.Handle);
    ACanvas.PolyBezier(BezierPoints);
    if Closed then
    begin
      EndPath(ACanvas.Handle);
      StrokeAndFillPath(ACanvas.Handle);
    end;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_ICON;
  for I := 0 to High(Anchors) do
    if Kind = slvkBezier then
      ACanvas.Ellipse(Anchors[I].X - 2, Anchors[I].Y - 2,
        Anchors[I].X + 2, Anchors[I].Y + 2)
    else
      ACanvas.Rectangle(Anchors[I].X - 2, Anchors[I].Y - 2,
        Anchors[I].X + 2, Anchors[I].Y + 2);
  ACanvas.Brush.Style := bsClear;
end;

function TVectArtToolPaletteControl.ButtonRect(Index: Integer): TRect;
var
  LogicalWidth: Integer;
begin
  LogicalWidth := MulDiv(ClientWidth, 96, CurrentPPI);
  Result := Rect(6, 6 + Index * (BUTTON_SIZE + BUTTON_GAP),
    LogicalWidth - 6, 6 + Index * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_SIZE);
end;

function TVectArtToolPaletteControl.ColorSwatchRect: TRect;
var
  Left: Integer;
  Top: Integer;
begin
  Left := (MulDiv(ClientWidth, 96, CurrentPPI) - COLOR_SWATCH_SIZE) div 2;
  Top := 6 + PALETTE_BUTTON_COUNT * (BUTTON_SIZE + BUTTON_GAP) + 3;
  Result := Rect(Left, Top, Left + COLOR_SWATCH_SIZE, Top + COLOR_SWATCH_SIZE);
end;

function TVectArtToolPaletteControl.ButtonSelected(Index: Integer): Boolean;
var
  Tool: TVectArtEditorTool;
begin
  Result := False;
  if FEditorState = nil then
    Exit;
  if FEditorState.ActiveMapPreset >= 0 then
    Exit;
  Tool := ButtonTool(Index);
  if Tool = vetRectangle then
    Result := FEditorState.CurrentTool in [vetRectangleLine, vetRectangle]
  else if Tool = vetRoundedRectangle then
    Result := FEditorState.CurrentTool in [vetRoundedRectangleLine,
      vetRoundedRectangle]
  else if Tool = vetEllipse then
    Result := FEditorState.CurrentTool in [vetEllipseLine, vetEllipse]
  else if Tool = vetArcShape then
    Result := FEditorState.CurrentTool in [vetArc, vetArcShape]
  else if Tool = vetText then
    Result := FEditorState.CurrentTool in [vetText, vetTextPath]
  else
    Result := FEditorState.CurrentTool = Tool;
end;

function TVectArtToolPaletteControl.ButtonTool(
  Index: Integer): TVectArtEditorTool;
begin
  case Index of
    0: Result := vetSelect;
    1: Result := vetLine;
    2: Result := vetFreehand;
    3: Result := vetPath;
    4: Result := vetRectangle;
    5: Result := vetRoundedRectangle;
    6: Result := vetEllipse;
    7: Result := vetArcShape;
    8: Result := vetShape;
  else
    Result := vetText;
  end;
end;

constructor TVectArtToolPaletteControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
end;

procedure TVectArtToolPaletteControl.DrawButton(Index: Integer);
var
  Bounds: TRect;
  CenterX: Integer;
  CenterY: Integer;
  Selected: Boolean;
  Tool: TVectArtEditorTool;
  VertexKind: TMapRakuVertexKind;
begin
  Bounds := ButtonRect(Index);
  CenterX := (Bounds.Left + Bounds.Right) div 2;
  CenterY := (Bounds.Top + Bounds.Bottom) div 2;
  Selected := ButtonSelected(Index);
  Tool := ButtonTool(Index);
  if Selected then
    Tool := FEditorState.CurrentTool;
  VertexKind := slvkSharp;
  if FEditorState <> nil then
    VertexKind := FEditorState.NextVertexKind;
  if Selected then
    Canvas.Brush.Color := MAPRAKU_TOOL_SELECTED_COLOR
  else
    Canvas.Brush.Color := COLOR_BUTTON;
  Canvas.FillRect(Bounds);
  if Selected then
  begin
    Canvas.Pen.Color := MAPRAKU_TOOL_SELECTED_BORDER;
    Canvas.Pen.Width := 2;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(Bounds);
  end;
  Canvas.Pen.Color := COLOR_ICON;
  Canvas.Font.Color := COLOR_ICON;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  if Tool = vetSelect then
  begin
    Canvas.MoveTo(CenterX - 8, CenterY - 11);
    Canvas.LineTo(CenterX + 7, CenterY + 2);
    Canvas.LineTo(CenterX, CenterY + 4);
    Canvas.LineTo(CenterX + 4, CenterY + 12);
    Canvas.LineTo(CenterX, CenterY + 14);
    Canvas.LineTo(CenterX - 4, CenterY + 6);
    Canvas.LineTo(CenterX - 9, CenterY + 10);
    Canvas.LineTo(CenterX - 8, CenterY - 11);
  end
  else if Tool = vetRectangleLine then
    Canvas.Rectangle(CenterX - 10, CenterY - 8, CenterX + 10,
      CenterY + 8)
  else if Tool = vetRectangle then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_ICON;
    Canvas.Rectangle(CenterX - 10, CenterY - 8, CenterX + 10,
      CenterY + 8);
    Canvas.Brush.Style := bsClear;
  end
  else if Tool = vetRoundedRectangleLine then
    Canvas.RoundRect(CenterX - 11, CenterY - 9, CenterX + 11,
      CenterY + 9, 8, 8)
  else if Tool = vetRoundedRectangle then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_ICON;
    Canvas.RoundRect(CenterX - 11, CenterY - 9, CenterX + 11,
      CenterY + 9, 8, 8);
    Canvas.Brush.Style := bsClear;
  end
  else if Tool = vetEllipseLine then
    Canvas.Ellipse(CenterX - 12, CenterY - 9, CenterX + 12,
      CenterY + 9)
  else if Tool = vetEllipse then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_ICON;
    Canvas.Ellipse(CenterX - 12, CenterY - 9, CenterX + 12,
      CenterY + 9);
    Canvas.Brush.Style := bsClear;
  end
  else if Tool = vetArc then
    Canvas.Arc(CenterX - 12, CenterY - 9, CenterX + 12, CenterY + 9,
      CenterX + 12, CenterY, CenterX - 12, CenterY)
  else if Tool = vetArcShape then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_ICON;
    Canvas.Pie(CenterX - 12, CenterY - 9, CenterX + 12, CenterY + 9,
      CenterX + 12, CenterY, CenterX - 12, CenterY);
    Canvas.Brush.Style := bsClear;
  end
  else if Tool = vetLine then
  begin
    Canvas.MoveTo(CenterX - 11, CenterY + 8);
    Canvas.LineTo(CenterX + 11, CenterY - 8);
  end
  else if Tool = vetFreehand then
  begin
    Canvas.Polyline([Point(CenterX - 13, CenterY + 5),
      Point(CenterX - 10, CenterY - 3),
      Point(CenterX - 6, CenterY - 7),
      Point(CenterX - 3, CenterY - 2),
      Point(CenterX, CenterY + 7),
      Point(CenterX + 5, CenterY + 9),
      Point(CenterX + 9, CenterY + 3),
      Point(CenterX + 13, CenterY - 6)]);
  end
  else if Tool = vetPath then
    DrawPathKindIcon(Canvas, CenterX, CenterY, False,
      VertexKind)
  else if Tool = vetTextPath then
  begin
    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Height := -18;
    Canvas.Font.Style := [fsBold];
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(CenterX - Canvas.TextWidth('T') div 2,
      CenterY - 11, 'T');
    Canvas.Font.Style := [];
    Canvas.MoveTo(CenterX - 12, CenterY + 8);
    Canvas.LineTo(CenterX - 4, CenterY + 5);
    Canvas.LineTo(CenterX + 4, CenterY + 7);
    Canvas.LineTo(CenterX + 12, CenterY + 3);
  end
  else if Tool = vetText then
  begin
    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Height := -25;
    Canvas.Font.Style := [fsBold];
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(CenterX - Canvas.TextWidth('T') div 2,
      CenterY - Canvas.TextHeight('T') div 2, 'T');
    Canvas.Font.Style := [];
  end
  else
    DrawPathKindIcon(Canvas, CenterX, CenterY, True,
      VertexKind);
end;

procedure TVectArtToolPaletteControl.DrawColorSwatch;
var
  Bounds: TRect;
  FromSelectedObject: Boolean;
begin
  Bounds := ColorSwatchRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clBlack;
  Canvas.FillRect(Bounds);
  InflateRect(Bounds, -1, -1);
  Canvas.Brush.Color := clWhite;
  Canvas.FillRect(Bounds);
  InflateRect(Bounds, -1, -1);
  if FEditorState <> nil then
  begin
    if (FEditorState.CurrentTool <> vetSelect) and (FDocument <> nil) and
      (FDocument.CanvasLayer <> nil) and
      ((FEditorState.MapElement = 'jr') or
       (FEditorState.MapElement = 'rail')) then
    begin
      if FEditorState.MapElement = 'jr' then
      begin
        Canvas.Brush.Color := ColorToRGB(FDocument.CanvasLayer.JrPrimaryColor);
        Canvas.FillRect(Rect(Bounds.Left,Bounds.Top,
          (Bounds.Left+Bounds.Right) div 2,Bounds.Bottom));
        Canvas.Brush.Color := ColorToRGB(FDocument.CanvasLayer.JrSecondaryColor);
      end
      else
      begin
        Canvas.Brush.Color := ColorToRGB(FDocument.CanvasLayer.RailPrimaryColor);
        Canvas.FillRect(Rect(Bounds.Left,Bounds.Top,
          (Bounds.Left+Bounds.Right) div 2,Bounds.Bottom));
        Canvas.Brush.Color := ColorToRGB(FDocument.CanvasLayer.RailSecondaryColor);
      end;
      Canvas.FillRect(Rect((Bounds.Left+Bounds.Right) div 2,Bounds.Top,
        Bounds.Right,Bounds.Bottom));
      Canvas.Brush.Style := bsClear;
      Exit;
    end;
    if (FEditorState.CurrentTool <> vetSelect) and
      ((FEditorState.MapElement = 'road') or
       (FEditorState.MapElement = 'river')) then
      Canvas.Brush.Color := ColorToRGB(
        FEditorState.MapPlacementColor(FDocument,FromSelectedObject))
    else
      Canvas.Brush.Color := ColorToRGB(FEditorState.CreationColor);
  end
  else
    Canvas.Brush.Color := clBlack;
  Canvas.FillRect(Bounds);
  Canvas.Brush.Style := bsClear;
end;

procedure TVectArtToolPaletteControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  LogicalPoint: TPoint;
begin
  LogicalPoint := Point(MulDiv(X, 96, CurrentPPI),
    MulDiv(Y, 96, CurrentPPI));
  if (Button = mbLeft) and (FEditorState <> nil) then
    for I := 0 to PALETTE_BUTTON_COUNT - 1 do
      if PtInRect(ButtonRect(I), LogicalPoint) then
      begin
        FEditorState.PendingSymbol := -1;
        FEditorState.MapElement := '';
        FEditorState.ActiveMapPreset := -1;
        FEditorState.ActivateTool(ButtonTool(I));
        Break;
      end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtToolPaletteControl.Paint;
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
    for I := 0 to PALETTE_BUTTON_COUNT - 1 do
      DrawButton(I);
    DrawColorSwatch;
  finally
    RestoreDC(Canvas.Handle, SavedDC);
  end;
end;

procedure TVectArtToolPaletteControl.RefreshState;
begin
  Invalidate;
end;

procedure TVectArtToolPaletteControl.SetEditorState(
  const Value: TVectArtEditorState);
begin
  FEditorState := Value;
  RefreshState;
end;

procedure TVectArtToolPaletteControl.SetDocument(
  const Value: TVectArtDocument);
begin
  FDocument := Value;
  RefreshState;
end;

end.
