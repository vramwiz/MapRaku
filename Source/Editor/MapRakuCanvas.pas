// 中央編集領域のキャンバス表示を担当する。
// 論理サイズと画面上の拡大率を分離し、描画にはDirect2Dを優先して使用する。
unit MapRakuCanvas;

interface

uses
  MapRakuPathEditor,
  System.Classes, System.SysUtils, System.Types, Winapi.Messages,
  Winapi.Windows, Vcl.Controls, Vcl.Direct2D, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.Graphics,
  MapRakuCanvasInteraction,
  MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState, MapRakuFilterInteraction,
  MapRakuGradientInteraction,
  MapRakuTextureInteraction,
  MapRakuGroupInteraction,
  MapRakuTransformInteraction,
  MapRakuProjectiveTransform,
  MapRakuPaintStyles,
  MapRakuSelectionGeometry,
  MapRakuShapeCreation, MapRakuPlacementPreview, MapRakuCanvasRenderCache,
  MapRakuTextEditing, MapRakuTextEditOverlay,
  WindowsImeController;

type
  TMapRakuObjectContextMenuEvent = procedure(Sender: TObject;
    const ScreenPoint: TPoint;
    const LayerIndices: TArray<Integer>) of object;

  TVectArtCanvasControl = class(TCustomControl)
  private
    FCanvasBounds: TRect;
    FDirect2DEnabled: Boolean;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FFilterInteraction: TMapRakuFilterInteraction;
    FGradientInteraction: TMapRakuGradientInteraction;
    FTextureInteraction: TMapRakuTextureInteraction; // 画像の配置ハンドルとUndo操作。
    FGroupDrag: TMapRakuGroupDrag;
    FTransformInteraction: TMapRakuTransformInteraction;
    FInteraction: TVectArtCanvasInteraction;
    FImeState: TWindowsImeState;
    FOnObjectContextMenu: TMapRakuObjectContextMenuEvent;
    FPenPointerActive: Boolean;
    FPenPressure: Single;
    FPenPressureAvailable: Boolean;
    FPointerInside: Boolean;
    FPointerPosition: TPoint;
    FReferenceBackground: TBitmap;
    FReferenceBackgroundToken: string; // 参照背景だけの更新もAIの配置案から検出する。
    FPlacementPreview: TMapRakuPlacementPreview; // 確定前の塗り図形画像を所有する。
    FRenderCache: TMapRakuCanvasRenderCache; // 文書画像、移動プレビュー、ズーム再利用を所有する。
    FShapeCreation: TVectArtShapeCreation;
    FMapPathEditor: TMapPathEditor;
    FLastPlacedLayerIndex: Integer;
    FLastPlacedLayer: TVectArtLayer;
    FSkipTextDblClick: Boolean;
    FTextBeforeSelection: TArray<Integer>;
    FTextBuffer: string;
    FTextCaretIndex: Integer;
    FTextPreferredCaretX: Single;
    FTextSelectionAnchor: Integer;
    FTextCompositionActive: Boolean;
    FTextCompositionCursor: Integer;
    FTextCompositionText: string;
    FTextDragActive: Boolean;
    FTextDragCurrent: TPoint;
    FTextDragStart: TPoint;
    FTextEditing: Boolean;
    FTextEditor: TMapRakuImeEdit;
    FTextEnding: Boolean;
    FTextGuideBounds: TRectF;
    FTextLayerIndex: Integer;
    FTextLayer: TMapRakuTextLayer; // 編集中のトップレベルまたは開いたグループ内文字。所有しない。
    FTextInputOutlineColor: TColor;
    FTextAutoExpandWidth: Boolean;
    FTextNewLayer: Boolean;
    FTextNewPathLayer: Boolean;
    FTextOriginalData: TMapRakuTextData;
    FPanning: Boolean;
    FPanOffset: TPointF;
    FPanStartMouse: TPoint;
    FPanStartOffset: TPointF;
    FViewZoom: Single;
    FZoom: Single;
    FZoomPreviewActive: Boolean;
    FZoomRenderTimer: TTimer;
    procedure CalculateCanvasBounds;
    procedure ConfigureInteraction;
    function EditingTextPath: Boolean;
    procedure EndPan;
    procedure PaintDirect2D;
    procedure PaintGDI;
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetEditorState(const Value: TVectArtEditorState);
    procedure SyncSelectedPathVertexMode;
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
    function GetEditHistory: TVectArtEditHistory;
    function HasReferenceBackground: Boolean;
    procedure BeginMovePreview;
    procedure EndMovePreview;
    procedure UpdateRenderedDocument;
    procedure SetEditHistory(const Value: TVectArtEditHistory);
    procedure BeginExistingTextEdit(Index: Integer);
    procedure BeginExistingTextLayerEdit(Layer: TMapRakuTextLayer;
      Index: Integer);
    function EditingTextLayer: TMapRakuTextLayer;
    procedure BeginCreatedTextPathEdit;
    procedure BeginNewTextEdit(const GuideBounds: TRectF;
      AutoExpandWidth: Boolean);
    procedure BeginNewTextPathEdit(Index: Integer;
      const BeforeSelection: TArray<Integer>);
    function TextEditOverlayState: TMapRakuTextEditOverlayState;
    procedure DrawTextEditingOverlay(ACanvas: TCanvas);
    procedure DrawTextEditingOverlayDirect2D(ACanvas: TDirect2DCanvas);
    procedure DrawSnapGuides(ACanvas: TCanvas); overload;
    procedure DrawSnapGuides(ACanvas: TDirect2DCanvas); overload;
    procedure FinishTextEdit(Cancel: Boolean;
      RestoreCanvasFocus: Boolean = True);
    procedure FinishTextEditAndSelect(RestoreCanvasFocus: Boolean);
    procedure TextEditorCommittedText(Sender: TObject; const Text: string);
    procedure TextEditorComposition(Sender: TObject; const Text: string;
      CursorPosition: Integer; Active: Boolean);
    procedure TextEditorExit(Sender: TObject);
    procedure TextEditorKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure MoveTextCaretVertical(Direction: Integer;
      ExtendSelection: Boolean);
    procedure SetTextCaretFromClientPoint(X, Y: Integer;
      ExtendSelection: Boolean);
    procedure UpdateTextEditorBackground;
    procedure UpdateTextEditorBounds;
    procedure UpdateTextLayerFromBuffer;
    procedure ZoomRenderTimerTick(Sender: TObject);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    function StrokeWidthCursorVisible: Boolean;
    function StrokeWidthCursorDiameter: Single;
    procedure UpdatePenPressure(MessageId: Cardinal; WParam: WPARAM);
  protected
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 外部ホストのRGBA8画像をDocumentに含めない参照背景として設定する。
    procedure SetReferenceBackgroundRgba(const Pixels: TBytes;
      Width, Height: Integer);
    // 呼出側所有のBitmapへ参照背景を複写する。背景なしなら空画像にする。
    procedure CopyReferenceBackground(Target: TBitmap);
    property ReferenceBackgroundToken: string read FReferenceBackgroundToken;
    // コントロール座標が用紙内なら、中央原点の文書座標へ変換する。
    function TryClientPointToLogical(const ClientPoint: TPoint;
      out LogicalPoint: TPointF): Boolean;
    // パス編集モードの現在種別を、選択中アンカーへ適用する。
    function ApplyPathVertexModeToSelection: Boolean;
    // 変形ドラッグ中はホスト側ショートカットによる対象の変更を抑止する。
    function TransformDragging: Boolean;
    // 変形前の状態へ戻してマウスキャプチャを解放する。
    procedure CancelTransformDrag;
    // 配置先の分類を変える場合も右クリックと同じ規則で配置を終了する。
    procedure EndPlacement;
    // 文字入力中はホスト側のオブジェクト編集ショートカットを抑止する。
    property TextEditing: Boolean read FTextEditing;
    property CanvasBounds: TRect read FCanvasBounds;
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditHistory: TVectArtEditHistory read GetEditHistory
      write SetEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write SetEditorState;
    // オブジェクト上の未処理右クリックを、画面座標でホストへ通知する。
    property OnObjectContextMenu: TMapRakuObjectContextMenuEvent
      read FOnObjectContextMenu write FOnObjectContextMenu;
    property Zoom: Single read FZoom;
    function TryPathVertexMenuTarget(const ScreenPoint: TPoint;
      out Layer: TVectArtPathLayer; out VertexIndex, SegmentIndex: Integer;
      out SegmentT: Single): Boolean;
    function ExecutePathVertexMenuEdit(Layer: TVectArtPathLayer;
      VertexIndex, SegmentIndex: Integer; SegmentT: Single;
      DeleteVertex: Boolean): Boolean;
  end;

const
  DESIGN_CANVAS_WIDTH  = DEFAULT_CANVAS_WIDTH;
  DESIGN_CANVAS_HEIGHT = DEFAULT_CANVAS_HEIGHT;

implementation

uses
  MapRakuSymbols, System.Math, System.Skia, System.UITypes, Winapi.D2D1, Vcl.Clipbrd,
  MapRakuCanvasGuides, MapRakuCanvasPreview,
  MapRakuContextMenuInteraction,
  MapRakuEllipseGeometry, MapRakuGeometry,
  MapRakuGroupCommands,
  MapRakuLayerGeometry,
  MapRakuOverlayHandles,
  MapRakuOverlayPrimitives,
  MapRakuOverlayShapes,
  MapRakuPathOperations,
  MapRakuShapeOperations, MapRakuTextCommands,
  MapRakuTextGeometry, MapRakuTextPathGeometry,
  MapRakuLayerNaming, MapRakuSnapGeometry;

const
  CANVAS_MARGIN         = 32;
  CANVAS_SHADOW_OFFSET  = 6;
  COLOR_EDITOR_SURROUND = TColor($00484848); // 出力範囲外を背景色と区別する中間色。
  COLOR_CANVAS_SHADOW   = TColor($00070707);
  COLOR_ROTATION_MARK       = TColor($00008000); // ダブルクリックで0度へ戻せる回転。
  COLOR_ROTATION_BAKED_MARK = TColor($000080FF); // 座標へ焼き込むためリセット対象外の回転。
  COLOR_SELECTION       = clBlack;
  COLOR_OPEN_GROUP      = TColor($00D6A04A);
  COLOR_SNAP            = TColor($0048A8F8);
  COLOR_TRANSPARENT_A   = TColor($00D8D8D8);
  COLOR_TRANSPARENT_B   = TColor($00FFFFFF);
  TRANSPARENCY_CELL     = 16;
  MAX_VIEW_ZOOM         = 8.0;
  MIN_VIEW_ZOOM         = 0.25;
  VIEW_ZOOM_STEP        = 1.2;
  DEFAULT_TEXT_FONT_FAMILY = 'Yu Gothic UI';
  DEFAULT_TEXT_FONT_SIZE = 32.0;
  DEFAULT_TEXT_VALUE = 'Text';
  DEFAULT_TEXT_GUIDE_WIDTH = 320;
  DEFAULT_TEXT_GUIDE_HEIGHT = 80;
  TEXT_INPUT_EDIT_WIDTH = 4;
  // Falseにすると編集ビューの細線補正を一括で無効化する。
  ENABLE_THIN_STROKE_PREVIEW = True;
  MIN_PREVIEW_STROKE_WIDTH_PIXELS = 1.0;

procedure DrawPremultipliedBitmap(Target: TCanvas; const Bounds: TRect;
  Bitmap: Vcl.Graphics.TBitmap);
var
  Blend: BLENDFUNCTION;
begin
  if (Bitmap = nil) or (Bitmap.Width <= 0) or (Bitmap.Height <= 0) then
    Exit;
  Blend.BlendOp := AC_SRC_OVER;
  Blend.BlendFlags := 0;
  Blend.SourceConstantAlpha := 255;
  Blend.AlphaFormat := AC_SRC_ALPHA;
  AlphaBlend(Target.Handle, Bounds.Left, Bounds.Top,
    Bounds.Width, Bounds.Height, Bitmap.Canvas.Handle,
    0, 0, Bitmap.Width, Bitmap.Height, Blend);
end;

function HorizontalTextAlignmentOffset(
  Alignment: TMapRakuTextAlignment; LayoutWidth,
  LineWidth: Single): Single;
begin
  case Ord(Alignment) mod 3 of
    1: Result := (LayoutWidth - LineWidth) * 0.5;
    2: Result := LayoutWidth - LineWidth;
  else
    Result := 0;
  end;
end;

constructor TVectArtCanvasControl.Create(AOwner: TComponent);
var
  Token: TGUID;
begin
  inherited Create(AOwner);
  CreateGUID(Token);
  FReferenceBackgroundToken := GUIDToString(Token);
  Color := COLOR_EDITOR_SURROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  FDirect2DEnabled := TDirect2DCanvas.Supported;
  FFilterInteraction := TMapRakuFilterInteraction.Create;
  FGradientInteraction := TMapRakuGradientInteraction.Create;
  FTextureInteraction := TMapRakuTextureInteraction.Create;
  FGroupDrag := TMapRakuGroupDrag.Create;
  FTransformInteraction := TMapRakuTransformInteraction.Create;
  FMapPathEditor := TMapPathEditor.Create;
  FInteraction := TVectArtCanvasInteraction.Create;
  FReferenceBackground := Vcl.Graphics.TBitmap.Create;
  FReferenceBackground.PixelFormat := pf32bit;
  FRenderCache := TMapRakuCanvasRenderCache.Create;
  FPlacementPreview := TMapRakuPlacementPreview.Create;
  FZoomRenderTimer := TTimer.Create(Self);
  FZoomRenderTimer.Enabled := False;
  FZoomRenderTimer.Interval := 140;
  FZoomRenderTimer.OnTimer := ZoomRenderTimerTick;
  FShapeCreation := TVectArtShapeCreation.Create;
  FShapeCreation.DeferTextPathHistory := True;
  FTextEditor := TMapRakuImeEdit.Create(Self);
  FTextEditor.Parent := Self;
  FTextEditor.BorderStyle := bsNone;
  FTextEditor.Color := TColor($00303030);
  FTextInputOutlineColor := clWhite;
  FTextEditor.Ctl3D := False;
  FTextEditor.HideSelection := False;
  FTextEditor.TabStop := True;
  FTextEditor.Visible := False;
  FTextEditor.SetBounds(0, 0, 1, 1);
  FTextEditor.OnCommittedText := TextEditorCommittedText;
  FTextEditor.OnComposition := TextEditorComposition;
  FTextEditor.OnExit := TextEditorExit;
  FTextEditor.OnKeyDown := TextEditorKeyDown;
  FImeState := Default(TWindowsImeState);
  FPanOffset := TPointF.Zero;
  FViewZoom := 1.0;
  CalculateCanvasBounds;
end;

destructor TVectArtCanvasControl.Destroy;
begin
  FTextEditor.Free;
  FZoomRenderTimer.Free;
  FPlacementPreview.Free;
  FRenderCache.Free;
  FReferenceBackground.Free;
  FShapeCreation.Free;
  FGradientInteraction.Free;
  FTextureInteraction.Free;
  FFilterInteraction.Free;
  FGroupDrag.Free;
  FTransformInteraction.Free;
  FMapPathEditor.Free;
  FInteraction.Free;
  inherited Destroy;
end;

procedure TVectArtCanvasControl.BeginNewTextEdit(
  const GuideBounds: TRectF; AutoExpandWidth: Boolean);
var
  Data: TMapRakuTextData;
begin
  if (FDocument = nil) or (FDocument.CanvasLayer = nil) then
    Exit;
  FTextBeforeSelection := FDocument.GetSelectedLayerIndices;
  Data := Default(TMapRakuTextData);
  Data.Bounds := TRectF.Create(GuideBounds.Left, GuideBounds.Top,
    GuideBounds.Left + 1, GuideBounds.Top + DEFAULT_TEXT_FONT_SIZE);
  Data.FontFamily := DEFAULT_TEXT_FONT_FAMILY;
  Data.FontSize := DEFAULT_TEXT_FONT_SIZE;
  Data.Locked := False;
  Data.Name := NextMapRakuLayerName(FDocument, 'Text');
  if FEditorState <> nil then
    Data.Opacity := FEditorState.RectangleOpacity
  else
    Data.Opacity := 1.0;
  Data.RotationDegrees := 0.0;
  Data.Text := DEFAULT_TEXT_VALUE;
  if FEditorState <> nil then
    Data.TextColor := FEditorState.CreationColor
  else
    Data.TextColor := clWhite;
  if FEditorState <> nil then
    Data.PaintStyle := FEditorState.CreationPaintStyle
  else
    Data.PaintStyle := TMapRakuPaintStyle.Solid(Data.TextColor);
  Data.Visible := True;
  // クリック配置は幅0を「折り返しなし」として保持し、ドラッグ指定時だけ固定幅を使う。
  if AutoExpandWidth then
    Data.WrapWidth := 0
  else
    Data.WrapWidth := Max(GuideBounds.Width, 1.0);
  FTextLayerIndex := FDocument.InsertText(FDocument.LayerCount, Data);
  FTextLayer := TMapRakuTextLayer(FDocument[FTextLayerIndex]);
  FDocument.SetSelectedLayers([FTextLayerIndex]);
  FTextGuideBounds := GuideBounds;
  FTextAutoExpandWidth := AutoExpandWidth;
  FTextNewLayer := True;
  FTextNewPathLayer := False;
  FTextBuffer := DEFAULT_TEXT_VALUE;
  FTextCaretIndex := Length(FTextBuffer);
  FTextSelectionAnchor := 0;
  FTextPreferredCaretX := -1.0;
  FTextCompositionActive := False;
  FTextCompositionCursor := 0;
  FTextCompositionText := '';
  FTextEditor.Text := '';
  FTextEditor.Font.Name := Data.FontFamily;
  FTextEditor.Font.Size := Round(Data.FontSize);
  FTextEditor.Font.Style := Data.FontStyle;
  FTextEditor.Font.Color := Data.TextColor;
  FTextEditing := True;
  UpdateTextLayerFromBuffer;
  UpdateTextEditorBackground;
  FTextEditor.Visible := True;
  FTextEditor.BringToFront;
  FTextEditor.SetFocus;
  RestoreWindowsIme(FTextEditor.Handle, FImeState);
end;

procedure TVectArtCanvasControl.BeginExistingTextEdit(Index: Integer);
var
  Layer: TMapRakuTextLayer;
begin
  if (FDocument = nil) or (Index <= 0) or
    (Index >= FDocument.LayerCount) or
    not (FDocument[Index] is TMapRakuTextLayer) or
    FDocument[Index].Locked then
    Exit;
  if FTextEditing then
    FinishTextEdit(False);
  Layer := TMapRakuTextLayer(FDocument[Index]);
  BeginExistingTextLayerEdit(Layer, Index);
end;

procedure TVectArtCanvasControl.BeginExistingTextLayerEdit(
  Layer: TMapRakuTextLayer; Index: Integer);
begin
  if (FDocument = nil) or (Layer = nil) or Layer.Locked then
    Exit;
  if FTextEditing then
    FinishTextEdit(False);
  FTextBeforeSelection := FDocument.GetSelectedLayerIndices;
  if Index > 0 then
    FDocument.SetSelectedLayers([Index])
  else
    FDocument.SetSelectedLayers([]);
  FTextLayerIndex := Index;
  FTextLayer := Layer;
  FTextOriginalData := CaptureMapRakuTextData(Layer);
  FTextGuideBounds := TRectF.Create(Layer.Bounds.Left, Layer.Bounds.Top,
    Layer.Bounds.Left + Max(Layer.WrapWidth, Layer.Bounds.Width),
    Layer.Bounds.Top + Max(Layer.Bounds.Height, DEFAULT_TEXT_GUIDE_HEIGHT));
  FTextNewLayer := False;
  FTextAutoExpandWidth := False;
  FTextNewPathLayer := False;
  FTextBuffer := Layer.Text;
  FTextCaretIndex := Length(FTextBuffer);
  FTextSelectionAnchor := FTextCaretIndex;
  FTextPreferredCaretX := -1.0;
  FTextCompositionActive := False;
  FTextCompositionCursor := 0;
  FTextCompositionText := '';
  FTextEditor.Text := '';
  FTextEditor.Font.Name := Layer.FontFamily;
  FTextEditor.Font.Size := Round(Layer.FontSize);
  FTextEditor.Font.Style := Layer.FontStyle;
  FTextEditor.Font.Color := Layer.FillColor;
  FTextEditing := True;
  UpdateTextEditorBounds;
  UpdateTextEditorBackground;
  FTextEditor.Visible := True;
  FTextEditor.BringToFront;
  FTextEditor.SetFocus;
  RestoreWindowsIme(FTextEditor.Handle, FImeState);
end;

function TVectArtCanvasControl.EditingTextLayer: TMapRakuTextLayer;
begin
  if FTextEditing then
    Result := FTextLayer
  else
    Result := nil;
end;

procedure TVectArtCanvasControl.BeginNewTextPathEdit(Index: Integer;
  const BeforeSelection: TArray<Integer>);
var
  Layer: TMapRakuTextPathLayer;
begin
  if (FDocument = nil) or (Index <= 0) or
    (Index >= FDocument.LayerCount) or
    not (FDocument[Index] is TMapRakuTextPathLayer) then
    Exit;
  Layer := TMapRakuTextPathLayer(FDocument[Index]);
  FTextBeforeSelection := Copy(BeforeSelection);
  FDocument.SetSelectedLayers([Index]);
  FTextLayerIndex := Index;
  FTextLayer := Layer;
  FTextGuideBounds := TRectF.Create(Layer.Bounds.Left, Layer.Bounds.Top,
    Layer.Bounds.Left + Max(Layer.WrapWidth, Layer.Bounds.Width),
    Layer.Bounds.Top + Max(Layer.Bounds.Height, DEFAULT_TEXT_GUIDE_HEIGHT));
  FTextNewLayer := True;
  FTextNewPathLayer := True;
  FTextAutoExpandWidth := False;
  FTextBuffer := Layer.Text;
  FTextCaretIndex := Length(FTextBuffer);
  FTextSelectionAnchor := 0;
  FTextPreferredCaretX := -1.0;
  FTextCompositionActive := False;
  FTextCompositionCursor := 0;
  FTextCompositionText := '';
  FTextEditor.Text := '';
  FTextEditor.Font.Name := Layer.FontFamily;
  FTextEditor.Font.Size := Round(Layer.FontSize);
  FTextEditor.Font.Style := Layer.FontStyle;
  FTextEditor.Font.Color := Layer.FillColor;
  FTextEditing := True;
  UpdateTextEditorBounds;
  UpdateTextEditorBackground;
  FTextEditor.Visible := True;
  FTextEditor.BringToFront;
  FTextEditor.SetFocus;
  RestoreWindowsIme(FTextEditor.Handle, FImeState);
end;

procedure TVectArtCanvasControl.BeginCreatedTextPathEdit;
var
  BeforeSelection: TArray<Integer>;
  Index: Integer;
begin
  if FShapeCreation.TakeCreatedTextPath(Index, BeforeSelection) then
    BeginNewTextPathEdit(Index, BeforeSelection);
end;

procedure TVectArtCanvasControl.DblClick;
var
  ClientPoint: TPoint;
begin
  if FSkipTextDblClick then
  begin
    FSkipTextDblClick := False;
    Exit;
  end;
  if (FDocument <> nil) and (FDocument.SelectedIndex > 0) and
    (FDocument.SelectedIndex < FDocument.LayerCount) and
    (FDocument[FDocument.SelectedIndex] is TMapRakuTextLayer) then
  begin
    GetCursorPos(ClientPoint);
    ClientPoint := ScreenToClient(ClientPoint);
    if not FTextEditing or
      (FTextLayerIndex <> FDocument.SelectedIndex) then
      BeginExistingTextEdit(FDocument.SelectedIndex);
    SetTextCaretFromClientPoint(ClientPoint.X, ClientPoint.Y, False);
    Exit;
  end;
  inherited DblClick;
end;

function TVectArtCanvasControl.TextEditOverlayState:
  TMapRakuTextEditOverlayState;
begin
  Result := Default(TMapRakuTextEditOverlayState);
  Result.Layer := EditingTextLayer;
  Result.Text := FTextBuffer;
  Result.CaretIndex := FTextCaretIndex;
  Result.SelectionAnchor := FTextSelectionAnchor;
  if FTextCompositionActive then
    Result.CompositionText := FTextCompositionText;
  Result.CompositionPosition := Point(FTextEditor.Left + FTextEditor.Width,
    FTextEditor.Top);
  Result.CompositionFontHeight := FTextEditor.Font.Height;
  Result.CanvasBounds := FCanvasBounds;
  if (FDocument <> nil) and (FDocument.CanvasLayer <> nil) then
  begin
    Result.CanvasWidth := FDocument.CanvasLayer.Width;
    Result.CanvasHeight := FDocument.CanvasLayer.Height;
  end;
  Result.Zoom := FZoom;
  Result.DragActive := FTextDragActive;
  Result.DragStart := FTextDragStart;
  Result.DragCurrent := FTextDragCurrent;
end;

procedure TVectArtCanvasControl.DrawTextEditingOverlay(ACanvas: TCanvas);
begin
  DrawMapRakuTextEditOverlay(ACanvas, TextEditOverlayState);
end;

procedure TVectArtCanvasControl.DrawTextEditingOverlayDirect2D(
  ACanvas: TDirect2DCanvas);
begin
  DrawMapRakuTextEditOverlay(ACanvas, TextEditOverlayState);
end;

procedure TVectArtCanvasControl.BeginMovePreview;
var
  Height: Integer;
  LayerIndex: Integer;
  PreviewStrokeWidth: Single;
  Width: Integer;
begin
  EndMovePreview;
  if (FDocument = nil) or (FDocument.CanvasLayer = nil) or
    not (FInteraction.Moving or FTransformInteraction.Moving) then
    Exit;
  Width := Max(Min(FCanvasBounds.Width,
    FDocument.CanvasLayer.Width), 1);
  Height := Max(Min(FCanvasBounds.Height,
    FDocument.CanvasLayer.Height), 1);
  PreviewStrokeWidth := 0.0;
  if ENABLE_THIN_STROKE_PREVIEW and (FZoom > 0) then
    PreviewStrokeWidth := MIN_PREVIEW_STROKE_WIDTH_PIXELS / FZoom;
  LayerIndex := -1;
  if FDocument.SelectionCount = 1 then
    LayerIndex := FDocument.SelectedIndex;
  FRenderCache.BeginMove(FDocument, LayerIndex, Width, Height,
    PreviewStrokeWidth);
end;

procedure TVectArtCanvasControl.EndMovePreview;
begin
  FRenderCache.EndMove;
end;

procedure TVectArtCanvasControl.DrawSnapGuides(ACanvas: TCanvas);
var
  Guide: TMapRakuSnapGuide;
  Guides: TArray<TMapRakuSnapGuide>;
  TargetRect: TRect;
begin
  Guides := FInteraction.SnapGuides;
  for Guide in Guides do
  begin
    DrawOverlayLine(ACanvas,
      Point(ToScreenX(Guide.StartPoint.X), ToScreenY(Guide.StartPoint.Y)),
      Point(ToScreenX(Guide.EndPoint.X), ToScreenY(Guide.EndPoint.Y)),
      COLOR_SNAP, psDot);
    if Guide.HighlightTarget then
    begin
      TargetRect := Rect(ToScreenX(Guide.TargetBounds.Left),
        ToScreenY(Guide.TargetBounds.Top), ToScreenX(Guide.TargetBounds.Right),
        ToScreenY(Guide.TargetBounds.Bottom));
      DrawOverlayFrameRect(ACanvas, TargetRect, COLOR_SNAP, psDot);
    end;
  end;
  Guides := FGroupDrag.SnapGuides;
  for Guide in Guides do
  begin
    DrawOverlayLine(ACanvas,
      Point(ToScreenX(Guide.StartPoint.X), ToScreenY(Guide.StartPoint.Y)),
      Point(ToScreenX(Guide.EndPoint.X), ToScreenY(Guide.EndPoint.Y)),
      COLOR_SNAP, psDot);
    if Guide.HighlightTarget then
    begin
      TargetRect := Rect(ToScreenX(Guide.TargetBounds.Left),
        ToScreenY(Guide.TargetBounds.Top), ToScreenX(Guide.TargetBounds.Right),
        ToScreenY(Guide.TargetBounds.Bottom));
      DrawOverlayFrameRect(ACanvas, TargetRect, COLOR_SNAP, psDot);
    end;
  end;
  if not FShapeCreation.Active then
    Exit;
  Guides := FShapeCreation.SnapGuides;
  for Guide in Guides do
  begin
    DrawOverlayLine(ACanvas,
      Point(ToScreenX(Guide.StartPoint.X), ToScreenY(Guide.StartPoint.Y)),
      Point(ToScreenX(Guide.EndPoint.X), ToScreenY(Guide.EndPoint.Y)),
      COLOR_SNAP, psDot);
    if Guide.HighlightTarget then
    begin
      TargetRect := Rect(ToScreenX(Guide.TargetBounds.Left),
        ToScreenY(Guide.TargetBounds.Top), ToScreenX(Guide.TargetBounds.Right),
        ToScreenY(Guide.TargetBounds.Bottom));
      DrawOverlayFrameRect(ACanvas, TargetRect, COLOR_SNAP, psDot);
    end;
  end;
end;

procedure TVectArtCanvasControl.DrawSnapGuides(ACanvas: TDirect2DCanvas);
var
  Guide: TMapRakuSnapGuide;
  Guides: TArray<TMapRakuSnapGuide>;
  TargetRect: TRect;
begin
  Guides := FInteraction.SnapGuides;
  for Guide in Guides do
  begin
    DrawOverlayLine(ACanvas,
      Point(ToScreenX(Guide.StartPoint.X), ToScreenY(Guide.StartPoint.Y)),
      Point(ToScreenX(Guide.EndPoint.X), ToScreenY(Guide.EndPoint.Y)),
      COLOR_SNAP, psDot);
    if Guide.HighlightTarget then
    begin
      TargetRect := Rect(ToScreenX(Guide.TargetBounds.Left),
        ToScreenY(Guide.TargetBounds.Top), ToScreenX(Guide.TargetBounds.Right),
        ToScreenY(Guide.TargetBounds.Bottom));
      DrawOverlayFrameRect(ACanvas, TargetRect, COLOR_SNAP, psDot);
    end;
  end;
  Guides := FGroupDrag.SnapGuides;
  for Guide in Guides do
  begin
    DrawOverlayLine(ACanvas,
      Point(ToScreenX(Guide.StartPoint.X), ToScreenY(Guide.StartPoint.Y)),
      Point(ToScreenX(Guide.EndPoint.X), ToScreenY(Guide.EndPoint.Y)),
      COLOR_SNAP, psDot);
    if Guide.HighlightTarget then
    begin
      TargetRect := Rect(ToScreenX(Guide.TargetBounds.Left),
        ToScreenY(Guide.TargetBounds.Top), ToScreenX(Guide.TargetBounds.Right),
        ToScreenY(Guide.TargetBounds.Bottom));
      DrawOverlayFrameRect(ACanvas, TargetRect, COLOR_SNAP, psDot);
    end;
  end;
  if not FShapeCreation.Active then
    Exit;
  Guides := FShapeCreation.SnapGuides;
  for Guide in Guides do
  begin
    DrawOverlayLine(ACanvas,
      Point(ToScreenX(Guide.StartPoint.X), ToScreenY(Guide.StartPoint.Y)),
      Point(ToScreenX(Guide.EndPoint.X), ToScreenY(Guide.EndPoint.Y)),
      COLOR_SNAP, psDot);
    if Guide.HighlightTarget then
    begin
      TargetRect := Rect(ToScreenX(Guide.TargetBounds.Left),
        ToScreenY(Guide.TargetBounds.Top), ToScreenX(Guide.TargetBounds.Right),
        ToScreenY(Guide.TargetBounds.Bottom));
      DrawOverlayFrameRect(ACanvas, TargetRect, COLOR_SNAP, psDot);
    end;
  end;
end;

procedure TVectArtCanvasControl.FinishTextEdit(Cancel,
  RestoreCanvasFocus: Boolean);
var
  AfterSelection: TArray<Integer>;
  CurrentData: TMapRakuTextData;
  RemovedData: TMapRakuTextData;
  RemovedLayer: TVectArtLayer;
begin
  if not FTextEditing or FTextEnding then
    Exit;
  FTextEnding := True;
  try
    SuspendWindowsIme(FTextEditor.Handle, FImeState);
    FTextEditor.Visible := False;
    if (FDocument <> nil) and (EditingTextLayer <> nil) then
    begin
      CurrentData := CaptureMapRakuTextData(EditingTextLayer);
      if FTextNewLayer then
      begin
        if Cancel or (CurrentData.Text = '') then
        begin
          if FTextNewPathLayer then
          begin
            RemovedLayer := FDocument.ExtractLayer(FTextLayerIndex);
            RemovedLayer.Free;
          end
          else
            FDocument.RemoveText(FTextLayerIndex, RemovedData);
          FDocument.SetSelectedLayers(FTextBeforeSelection);
        end
        else if EditHistory <> nil then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if FTextNewPathLayer then
            EditHistory.AddApplied(TMapRakuInsertTextPathCommand.Create(
              FDocument, FTextLayerIndex,
              TMapRakuTextPathLayer(FDocument[FTextLayerIndex]),
              FTextBeforeSelection, AfterSelection))
          else
            EditHistory.AddApplied(TMapRakuInsertTextCommand.Create(
              FDocument, FTextLayerIndex, CurrentData,
              FTextBeforeSelection, AfterSelection));
        end;
      end
      else if (FTextLayerIndex > 0) and Cancel then
        FDocument.SetTextData(FTextLayerIndex, FTextOriginalData)
      else if (FTextLayerIndex > 0) and (CurrentData.Text = '') then
      begin
        FDocument.RemoveText(FTextLayerIndex, RemovedData);
        AfterSelection := FDocument.GetSelectedLayerIndices;
        if EditHistory <> nil then
          EditHistory.AddApplied(TMapRakuDeleteTextCommand.Create(
            FDocument, FTextLayerIndex, FTextOriginalData,
            FTextBeforeSelection, AfterSelection));
      end
      else if FTextLayerIndex > 0 then
      begin
        if EditHistory <> nil then
          EditHistory.AddApplied(TMapRakuTextDataCommand.Create(FDocument,
            FTextLayerIndex, FTextOriginalData, CurrentData));
      end
      else if Cancel then
        FDocument.SetTextLayerData(EditingTextLayer, FTextOriginalData)
      else if EditHistory <> nil then
        EditHistory.AddApplied(TMapRakuTextDataCommand.CreateForLayer(
          FDocument, EditingTextLayer, FTextOriginalData, CurrentData));
    end;
    FTextEditing := False;
    FTextLayerIndex := -1;
    FTextLayer := nil;
    FTextNewLayer := False;
    FTextNewPathLayer := False;
    FTextAutoExpandWidth := False;
    FTextBuffer := '';
    FTextCaretIndex := 0;
    FTextSelectionAnchor := 0;
    FTextPreferredCaretX := -1.0;
    FTextCompositionActive := False;
    FTextCompositionCursor := 0;
    FTextCompositionText := '';
    FTextEditor.Text := '';
    if RestoreCanvasFocus and
      not (csDestroying in ComponentState) and
      (Parent <> nil) and not (csDestroying in Parent.ComponentState) and
      not Application.Terminated and CanFocus then
      SetFocus;
    Invalidate;
  finally
    FTextEnding := False;
  end;
end;

procedure TVectArtCanvasControl.FinishTextEditAndSelect(
  RestoreCanvasFocus: Boolean);
begin
  if not FTextEditing then
    Exit;
  FinishTextEdit(False, RestoreCanvasFocus);
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetText, vetTextPath]) then
    FEditorState.CurrentTool := vetSelect;
end;

procedure TVectArtCanvasControl.TextEditorCommittedText(Sender: TObject;
  const Text: string);
var
  InputText: string;
begin
  if not FTextEditing or FTextEnding or (Text = '') then
    Exit;
  FTextCompositionActive := False;
  FTextCompositionCursor := 0;
  FTextCompositionText := '';
  InputText := Text;
  if EditingTextLayer is TMapRakuTextPathLayer then
    InputText := NormalizeMapRakuTextPathText(InputText);
  InsertMapRakuTextAtCaret(FTextBuffer, FTextCaretIndex,
    FTextSelectionAnchor, FTextPreferredCaretX, InputText);
  UpdateTextLayerFromBuffer;
end;

procedure TVectArtCanvasControl.TextEditorComposition(Sender: TObject;
  const Text: string; CursorPosition: Integer; Active: Boolean);
begin
  if not FTextEditing or FTextEnding then
    Exit;
  FTextCompositionActive := Active;
  FTextCompositionCursor := EnsureRange(CursorPosition, 0, Length(Text));
  FTextCompositionText := Text;
  UpdateTextEditorBounds;
  FTextEditor.BringToFront;
  Invalidate;
end;

procedure TVectArtCanvasControl.TextEditorExit(Sender: TObject);
begin
  if FTextEditing and not FTextEnding then
    FinishTextEditAndSelect(False);
end;

procedure TVectArtCanvasControl.MoveTextCaretVertical(Direction: Integer;
  ExtendSelection: Boolean);
var
  CaretLines: TArray<TMapRakuCaretLine>;
  CurrentLine: Integer;
  Font: ISkFont;
  I: Integer;
  Layer: TMapRakuTextLayer;
  TargetLine: Integer;
begin
  Layer := EditingTextLayer;
  if Layer = nil then
    Exit;
  CaretLines := BuildMapRakuTextCaretLines(FTextBuffer,
    Layer.FontFamily, Layer.FontSize, Layer.WrapWidth, Layer.FontStyle,
    Layer.LetterSpacingRatio, Layer.LineSpacingRatio);
  if Length(CaretLines) = 0 then
    Exit;
  CurrentLine := 0;
  for I := 0 to High(CaretLines) do
    if (FTextCaretIndex >= CaretLines[I].StartIndex) and
      (FTextCaretIndex <= CaretLines[I].EndIndex) then
      CurrentLine := I;
  if FTextPreferredCaretX < 0 then
  begin
    Font := CreateMapRakuTextFont(Layer.FontFamily, Layer.FontSize,
      Layer.FontStyle);
    FTextPreferredCaretX := MeasureMapRakuText(Copy(FTextBuffer,
      CaretLines[CurrentLine].StartIndex + 1,
      FTextCaretIndex - CaretLines[CurrentLine].StartIndex), Font,
      Layer.FontSize * Layer.LetterSpacingRatio);
  end;
  TargetLine := EnsureRange(CurrentLine + Direction, 0,
    High(CaretLines));
  FTextCaretIndex := MapRakuTextCaretIndexAtLineX(
    CaretLines[TargetLine], Layer.FontFamily, Layer.FontSize,
    FTextPreferredCaretX, Layer.FontStyle, Layer.LetterSpacingRatio);
  if not ExtendSelection then
    FTextSelectionAnchor := FTextCaretIndex;
  UpdateTextEditorBounds;
  Invalidate;
end;

procedure TVectArtCanvasControl.SetTextCaretFromClientPoint(X, Y: Integer;
  ExtendSelection: Boolean);
var
  InverseTransform: TMapRakuTransform;
  Center: TPointF;
  Font: ISkFont;
  Layout: TMapRakuTextLayout;
  Layer: TMapRakuTextLayer;
  LineIndex: Integer;
  LineWidth: Single;
  LocalPoint: TPointF;
  LogicalPoint: TPointF;
  ScaleX: Single;
  ScaleY: Single;
  TargetX: Single;
  TargetY: Single;
begin
  Layer := EditingTextLayer;
  if (Layer = nil) or (FDocument = nil) then
    Exit;
  LogicalPoint := TPointF.Create(
    ScreenToLogicalX(X, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(Y, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Center := TPointF.Create((Layer.Bounds.Left + Layer.Bounds.Right) * 0.5,
    (Layer.Bounds.Top + Layer.Bounds.Bottom) * 0.5);
  if Layer.Transform.Inverse(InverseTransform) then
    LogicalPoint := InverseTransform.Map(LogicalPoint);
  LocalPoint := RotatePointAround(LogicalPoint, Center,
    -Layer.RotationDegrees);
  if Layer.FlipHorizontal then
    LocalPoint.X := 2 * Center.X - LocalPoint.X;
  if Layer.FlipVertical then
    LocalPoint.Y := 2 * Center.Y - LocalPoint.Y;
  Layout := BuildMapRakuTextLayout(FTextBuffer, Layer.FontFamily,
    Layer.FontSize, Layer.WrapWidth, Layer.FontStyle,
    Layer.LetterSpacingRatio, Layer.LineSpacingRatio);
  if Layer is TMapRakuTextPathLayer then
  begin
    ScaleX := 1.0;
    ScaleY := 1.0;
  end
  else
  begin
    ScaleX := Layer.Bounds.Width / Max(Layout.Width, 1.0);
    ScaleY := Layer.Bounds.Height / Max(Layout.Height, Layer.FontSize);
  end;
  TargetX := (LocalPoint.X - Layer.Bounds.Left) /
    Max(ScaleX, 0.0001);
  TargetY := (LocalPoint.Y - Layer.Bounds.Top) /
    Max(ScaleY, 0.0001);
  LineIndex := EnsureRange(Floor(TargetY /
    Max(Layout.LineHeight, 1.0)), 0, High(Layout.Lines));
  Font := CreateMapRakuTextFont(Layer.FontFamily, Layer.FontSize,
    Layer.FontStyle);
  LineWidth := MeasureMapRakuText(Layout.Lines[LineIndex], Font,
    Layer.FontSize * Layer.LetterSpacingRatio);
  TargetX := TargetX - HorizontalTextAlignmentOffset(Layer.Alignment,
    Layout.Width, LineWidth);
  FTextCaretIndex := MapRakuTextCaretIndexAtPoint(FTextBuffer,
    Layer.FontFamily, Layer.FontSize, Layer.WrapWidth,
    TargetX, TargetY,
    Layer.FontStyle, Layer.LetterSpacingRatio, Layer.LineSpacingRatio);
  if not ExtendSelection then
    FTextSelectionAnchor := FTextCaretIndex;
  FTextPreferredCaretX := -1.0;
  UpdateTextEditorBounds;
  UpdateTextEditorBackground;
  FTextEditor.Visible := True;
  FTextEditor.BringToFront;
  FTextEditor.SetFocus;
  Invalidate;
end;

procedure TVectArtCanvasControl.TextEditorKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
var
  CaretLines: TArray<TMapRakuCaretLine>;
  CurrentLine: Integer;
  DeleteCount: Integer;
  ExtendSelection: Boolean;
  I: Integer;
  InputText: string;
  Layer: TMapRakuTextLayer;
  SelectionEnd: Integer;
  SelectionStart: Integer;
begin
  Layer := EditingTextLayer;
  if (FDocument = nil) or (Layer = nil) then
    Exit;
  // 変換確定のEnterなどはIME自身へ渡す。ここで編集キーとして扱うと、
  // 漢字変換の確定と同時にDocumentへ改行が挿入される。
  if FTextCompositionActive then
    Exit;
  ExtendSelection := ssShift in Shift;
  if ssCtrl in Shift then
  begin
    case Key of
      Ord('A'):
        begin
          Key := 0;
          FTextSelectionAnchor := 0;
          FTextCaretIndex := Length(FTextBuffer);
          FTextPreferredCaretX := -1.0;
          UpdateTextEditorBounds;
          Invalidate;
        end;
      Ord('C'):
        begin
          Key := 0;
          SelectionStart := Min(FTextCaretIndex, FTextSelectionAnchor);
          SelectionEnd := Max(FTextCaretIndex, FTextSelectionAnchor);
          if SelectionStart <> SelectionEnd then
            Clipboard.AsText := Copy(FTextBuffer, SelectionStart + 1,
              SelectionEnd - SelectionStart);
        end;
      Ord('X'):
        begin
          Key := 0;
          SelectionStart := Min(FTextCaretIndex, FTextSelectionAnchor);
          SelectionEnd := Max(FTextCaretIndex, FTextSelectionAnchor);
          if SelectionStart <> SelectionEnd then
          begin
            Clipboard.AsText := Copy(FTextBuffer, SelectionStart + 1,
              SelectionEnd - SelectionStart);
            DeleteMapRakuTextSelection(FTextBuffer, FTextCaretIndex,
              FTextSelectionAnchor, FTextPreferredCaretX);
            UpdateTextLayerFromBuffer;
          end;
        end;
      Ord('V'):
        begin
          Key := 0;
          InputText := Clipboard.AsText;
          if Layer is TMapRakuTextPathLayer then
            InputText := NormalizeMapRakuTextPathText(InputText);
          InsertMapRakuTextAtCaret(FTextBuffer, FTextCaretIndex,
            FTextSelectionAnchor, FTextPreferredCaretX, InputText);
          UpdateTextLayerFromBuffer;
        end;
      VK_HOME:
        begin
          Key := 0;
          FTextCaretIndex := 0;
          if not ExtendSelection then
            FTextSelectionAnchor := FTextCaretIndex;
          FTextPreferredCaretX := -1.0;
          UpdateTextEditorBounds;
          Invalidate;
        end;
      VK_END:
        begin
          Key := 0;
          FTextCaretIndex := Length(FTextBuffer);
          if not ExtendSelection then
            FTextSelectionAnchor := FTextCaretIndex;
          FTextPreferredCaretX := -1.0;
          UpdateTextEditorBounds;
          Invalidate;
        end;
    end;
    if Key = 0 then
      Exit;
  end;
  case Key of
    VK_ESCAPE:
      begin
        Key := 0;
        FinishTextEdit(True);
      end;
    VK_RETURN:
      begin
        Key := 0;
        if Layer is TMapRakuTextPathLayer then
        begin
          FinishTextEditAndSelect(True);
          Exit;
        end;
        InsertMapRakuTextAtCaret(FTextBuffer, FTextCaretIndex,
          FTextSelectionAnchor, FTextPreferredCaretX, sLineBreak);
        UpdateTextLayerFromBuffer;
      end;
    VK_BACK:
      begin
        Key := 0;
        if DeleteMapRakuTextSelection(FTextBuffer, FTextCaretIndex,
          FTextSelectionAnchor, FTextPreferredCaretX) then
        begin
          UpdateTextLayerFromBuffer;
          Exit;
        end;
        if FTextCaretIndex <= 0 then
          Exit;
        DeleteCount := 1;
        if (FTextCaretIndex >= 2) and
          (FTextBuffer[FTextCaretIndex - 1] = #13) and
          (FTextBuffer[FTextCaretIndex] = #10) then
          DeleteCount := 2
        else if (FTextCaretIndex >= 2) and
          (Ord(FTextBuffer[FTextCaretIndex - 1]) >= $D800) and
          (Ord(FTextBuffer[FTextCaretIndex - 1]) <= $DBFF) and
          (Ord(FTextBuffer[FTextCaretIndex]) >= $DC00) and
          (Ord(FTextBuffer[FTextCaretIndex]) <= $DFFF) then
          DeleteCount := 2;
        Delete(FTextBuffer, FTextCaretIndex - DeleteCount + 1,
          DeleteCount);
        Dec(FTextCaretIndex, DeleteCount);
        FTextSelectionAnchor := FTextCaretIndex;
        FTextPreferredCaretX := -1.0;
        UpdateTextLayerFromBuffer;
      end;
    VK_DELETE:
      begin
        Key := 0;
        if DeleteMapRakuTextSelection(FTextBuffer, FTextCaretIndex,
          FTextSelectionAnchor, FTextPreferredCaretX) then
        begin
          UpdateTextLayerFromBuffer;
          Exit;
        end;
        if FTextCaretIndex >= Length(FTextBuffer) then
          Exit;
        DeleteCount := 1;
        if (FTextCaretIndex + 2 <= Length(FTextBuffer)) and
          (FTextBuffer[FTextCaretIndex + 1] = #13) and
          (FTextBuffer[FTextCaretIndex + 2] = #10) then
          DeleteCount := 2
        else if (FTextCaretIndex + 2 <= Length(FTextBuffer)) and
          (Ord(FTextBuffer[FTextCaretIndex + 1]) >= $D800) and
          (Ord(FTextBuffer[FTextCaretIndex + 1]) <= $DBFF) and
          (Ord(FTextBuffer[FTextCaretIndex + 2]) >= $DC00) and
          (Ord(FTextBuffer[FTextCaretIndex + 2]) <= $DFFF) then
          DeleteCount := 2;
        Delete(FTextBuffer, FTextCaretIndex + 1, DeleteCount);
        FTextSelectionAnchor := FTextCaretIndex;
        FTextPreferredCaretX := -1.0;
        UpdateTextLayerFromBuffer;
      end;
    VK_LEFT:
      begin
        Key := 0;
        MoveMapRakuTextCaretHorizontal(FTextBuffer, FTextCaretIndex,
          FTextSelectionAnchor, FTextPreferredCaretX, -1,
          ExtendSelection);
        UpdateTextEditorBounds;
        Invalidate;
      end;
    VK_RIGHT:
      begin
        Key := 0;
        MoveMapRakuTextCaretHorizontal(FTextBuffer, FTextCaretIndex,
          FTextSelectionAnchor, FTextPreferredCaretX, 1,
          ExtendSelection);
        UpdateTextEditorBounds;
        Invalidate;
      end;
    VK_UP:
      begin
        Key := 0;
        MoveTextCaretVertical(-1, ExtendSelection);
      end;
    VK_DOWN:
      begin
        Key := 0;
        MoveTextCaretVertical(1, ExtendSelection);
      end;
    VK_HOME:
      begin
        Key := 0;
        CaretLines := BuildMapRakuTextCaretLines(FTextBuffer,
          Layer.FontFamily, Layer.FontSize, Layer.WrapWidth,
          Layer.FontStyle, Layer.LetterSpacingRatio,
          Layer.LineSpacingRatio);
        CurrentLine := 0;
        for I := 0 to High(CaretLines) do
          if (FTextCaretIndex >= CaretLines[I].StartIndex) and
            (FTextCaretIndex <= CaretLines[I].EndIndex) then
            CurrentLine := I;
        if Length(CaretLines) > 0 then
          FTextCaretIndex := CaretLines[CurrentLine].StartIndex;
        if not ExtendSelection then
          FTextSelectionAnchor := FTextCaretIndex;
        FTextPreferredCaretX := -1.0;
        UpdateTextEditorBounds;
        Invalidate;
      end;
    VK_END:
      begin
        Key := 0;
        CaretLines := BuildMapRakuTextCaretLines(FTextBuffer,
          Layer.FontFamily, Layer.FontSize, Layer.WrapWidth,
          Layer.FontStyle, Layer.LetterSpacingRatio,
          Layer.LineSpacingRatio);
        CurrentLine := 0;
        for I := 0 to High(CaretLines) do
          if (FTextCaretIndex >= CaretLines[I].StartIndex) and
            (FTextCaretIndex <= CaretLines[I].EndIndex) then
            CurrentLine := I;
        if Length(CaretLines) > 0 then
          FTextCaretIndex := CaretLines[CurrentLine].EndIndex;
        if not ExtendSelection then
          FTextSelectionAnchor := FTextCaretIndex;
        FTextPreferredCaretX := -1.0;
        UpdateTextEditorBounds;
        Invalidate;
      end;
  end;
end;

procedure TVectArtCanvasControl.UpdateTextEditorBackground;
var
  BlueTotal: Integer;
  ColorValue: COLORREF;
  EditorRect: TRect;
  GreenTotal: Integer;
  I: Integer;
  J: Integer;
  RedTotal: Integer;
  SampleCount: Integer;
  SampleX: Integer;
  SampleY: Integer;
begin
  EditorRect := Rect(ToScreenX(FTextGuideBounds.Left),
    ToScreenY(FTextGuideBounds.Top), ToScreenX(FTextGuideBounds.Right),
    ToScreenY(FTextGuideBounds.Bottom));
  RedTotal := 0;
  GreenTotal := 0;
  BlueTotal := 0;
  SampleCount := 0;
  for J := 0 to 2 do
    for I := 0 to 2 do
    begin
      SampleX := EditorRect.Left +
        (EditorRect.Width * (I + 1)) div 4;
      SampleY := EditorRect.Top +
        (EditorRect.Height * (J + 1)) div 4;
      if not PtInRect(ClientRect, Point(SampleX, SampleY)) then
        Continue;
      ColorValue := GetPixel(Canvas.Handle, SampleX, SampleY);
      if ColorValue = CLR_INVALID then
        Continue;
      Inc(RedTotal, GetRValue(ColorValue));
      Inc(GreenTotal, GetGValue(ColorValue));
      Inc(BlueTotal, GetBValue(ColorValue));
      Inc(SampleCount);
    end;
  if SampleCount > 0 then
  begin
    FTextEditor.Color := RGB(RedTotal div SampleCount,
      GreenTotal div SampleCount, BlueTotal div SampleCount);
    FTextInputOutlineColor := clWhite;
  end
  else
  begin
    FTextEditor.Color := TColor($00303030);
    FTextInputOutlineColor := clWhite;
  end;
end;

procedure TVectArtCanvasControl.UpdateTextEditorBounds;
var
  CaretLayout: TMapRakuTextLayout;
  CaretPoint: TPointF;
  Center: TPointF;
  FullLayout: TMapRakuTextLayout;
  IndividualLetterSpacingRatios: TArray<Single>;
  LastLine: Integer;
  Layer: TMapRakuTextLayer;
  LineWidth: Single;
  Prefix: string;
  ScaleX: Single;
  ScaleY: Single;
  ScreenPoint: TPoint;
begin
  Layer := EditingTextLayer;
  if (Layer = nil) or (FDocument = nil) then
    Exit;
  IndividualLetterSpacingRatios := Layer.IndividualLetterSpacingRatios;
  FullLayout := BuildMapRakuTextLayout(FTextBuffer, Layer.FontFamily,
    Layer.FontSize, Layer.WrapWidth, Layer.FontStyle,
    Layer.LetterSpacingRatio, Layer.LineSpacingRatio,
    IndividualLetterSpacingRatios);
  if Layer is TMapRakuTextPathLayer then
  begin
    ScaleX := 1.0;
    ScaleY := 1.0;
  end
  else
  begin
    ScaleX := Layer.Bounds.Width / Max(FullLayout.Width, 1.0);
    ScaleY := Layer.Bounds.Height / Max(FullLayout.Height, Layer.FontSize);
  end;
  FTextEditor.Font.Name := Layer.FontFamily;
  FTextEditor.Font.Height := -Max(Round(Layer.FontSize * ScaleY * FZoom), 1);
  FTextEditor.Font.Style := Layer.FontStyle;
  FTextEditor.Font.Color := Layer.FillColor;
  Prefix := Copy(FTextBuffer, 1, FTextCaretIndex);
  CaretLayout := BuildMapRakuTextLayout(Prefix, Layer.FontFamily,
    Layer.FontSize, Layer.WrapWidth, Layer.FontStyle,
    Layer.LetterSpacingRatio, Layer.LineSpacingRatio,
    IndividualLetterSpacingRatios);
  LastLine := Max(High(CaretLayout.Lines), 0);
  CaretPoint := TPointF.Create(Layer.Bounds.Left,
    Layer.Bounds.Top + LastLine * CaretLayout.LineHeight * ScaleY);
  if Length(CaretLayout.Lines) > 0 then
  begin
    LineWidth := MeasureMapRakuText(FullLayout.Lines[
      Min(LastLine, High(FullLayout.Lines))], CreateMapRakuTextFont(
      Layer.FontFamily, Layer.FontSize, Layer.FontStyle),
      Layer.FontSize * Layer.LetterSpacingRatio, Layer.FontSize,
      IndividualLetterSpacingRatios,
      FullLayout.LineGapOffsets[Min(LastLine, High(FullLayout.Lines))]);
    CaretPoint.X := CaretPoint.X +
      HorizontalTextAlignmentOffset(Layer.Alignment, FullLayout.Width,
        LineWidth) * ScaleX + MeasureMapRakuText(
          CaretLayout.Lines[LastLine], CreateMapRakuTextFont(
            Layer.FontFamily, Layer.FontSize, Layer.FontStyle),
          Layer.FontSize * Layer.LetterSpacingRatio, Layer.FontSize,
          IndividualLetterSpacingRatios,
          CaretLayout.LineGapOffsets[LastLine]) * ScaleX;
  end;
  Center := TPointF.Create((Layer.Bounds.Left + Layer.Bounds.Right) * 0.5,
    (Layer.Bounds.Top + Layer.Bounds.Bottom) * 0.5);
  if Layer.FlipHorizontal then
    CaretPoint.X := 2 * Center.X - CaretPoint.X;
  if Layer.FlipVertical then
    CaretPoint.Y := 2 * Center.Y - CaretPoint.Y;
  CaretPoint := RotatePointAround(CaretPoint, Center,
    Layer.RotationDegrees);
  CaretPoint := Layer.Transform.Map(CaretPoint);
  ScreenPoint := Point(ToScreenX(CaretPoint.X), ToScreenY(CaretPoint.Y));
  ScreenPoint.X := EnsureRange(ScreenPoint.X, FCanvasBounds.Left,
    Max(FCanvasBounds.Right - TEXT_INPUT_EDIT_WIDTH, FCanvasBounds.Left));
  ScreenPoint.Y := EnsureRange(ScreenPoint.Y, FCanvasBounds.Top,
    Max(FCanvasBounds.Bottom - 1, FCanvasBounds.Top));
  FTextEditor.SetBounds(ScreenPoint.X, ScreenPoint.Y,
    TEXT_INPUT_EDIT_WIDTH,
    Max(Round(CaretLayout.LineHeight * ScaleY * FZoom), 1));
end;

procedure TVectArtCanvasControl.UpdateTextLayerFromBuffer;
var
  Data: TMapRakuTextData;
  Layout: TMapRakuTextLayout;
begin
  if (EditingTextLayer = nil) or (FDocument = nil) then
    Exit;
  Data := CaptureMapRakuTextData(EditingTextLayer);
  if Data.Text <> FTextBuffer then
    SetLength(Data.IndividualLetterSpacingRatios, 0);
  Data.Text := FTextBuffer;
  if FTextNewLayer and not FTextNewPathLayer then
  begin
    // WrapWidth=0も自動幅の永続的な印として扱い、通知中のUI再同期で入力状態が変わっても固定幅へ戻さない。
    if FTextAutoExpandWidth or (Data.WrapWidth <= 0) then
    begin
      Layout := BuildMapRakuTextLayout(Data.Text, Data.FontFamily,
        Data.FontSize, 0, Data.FontStyle, Data.LetterSpacingRatio,
        Data.LineSpacingRatio);
      Data.WrapWidth := 0;
      FTextGuideBounds.Right := FTextGuideBounds.Left + Max(Layout.Width, 1.0);
    end
    else
      Data.WrapWidth := Max(FTextGuideBounds.Width, 1.0);
    Layout := BuildMapRakuTextLayout(Data.Text, Data.FontFamily,
      Data.FontSize, Data.WrapWidth, Data.FontStyle, Data.LetterSpacingRatio,
      Data.LineSpacingRatio);
    Data.Bounds := TRectF.Create(FTextGuideBounds.Left, FTextGuideBounds.Top,
      FTextGuideBounds.Left + Max(Layout.Width, 1.0),
      FTextGuideBounds.Top + Max(Layout.Height, Data.FontSize));
  end;
  FDocument.SetTextLayerData(EditingTextLayer, Data);
  UpdateTextEditorBounds;
  Invalidate;
end;

function TVectArtCanvasControl.HasReferenceBackground: Boolean;
begin
  Result := (FReferenceBackground <> nil) and
    (FReferenceBackground.Width > 0) and
    (FReferenceBackground.Height > 0);
end;

// 文字入力中はPathガイドだけを維持し、入力確定まで変形用の枠とハンドルを隠す。
function TVectArtCanvasControl.EditingTextPath: Boolean;
begin
  Result := FTextEditing and
    (((FEditorState <> nil) and
      (FEditorState.OpenGroupChild is TMapRakuTextPathLayer)) or
     ((FDocument <> nil) and (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TMapRakuTextPathLayer)));
end;

procedure TVectArtCanvasControl.CalculateCanvasBounds;
var
  AvailableHeight: Integer;
  AvailableWidth: Integer;
  ControlHeight: Integer;
  ControlWidth: Integer;
  DisplayHeight: Integer;
  DisplayWidth: Integer;
  LogicalHeight: Integer;
  LogicalWidth: Integer;
begin
  // Create/Parent/Alignの途中ではまだWinControlのハンドルを作成できない。
  // ClientWidth/ClientHeightは暗黙にHandleNeededを呼ぶため、その期間は
  // ハンドルを必要としないWidth/Heightを使って初期値を計算する。
  if HandleAllocated then
  begin
    ControlWidth := ClientWidth;
    ControlHeight := ClientHeight;
  end
  else
  begin
    ControlWidth := Width;
    ControlHeight := Height;
  end;
  AvailableWidth := Max(ControlWidth - (CANVAS_MARGIN * 2), 1);
  AvailableHeight := Max(ControlHeight - (CANVAS_MARGIN * 2), 1);
  LogicalWidth := DESIGN_CANVAS_WIDTH;
  LogicalHeight := DESIGN_CANVAS_HEIGHT;
  if (FDocument <> nil) and (FDocument.CanvasLayer <> nil) then
  begin
    LogicalWidth := Max(FDocument.CanvasLayer.Width, 1);
    LogicalHeight := Max(FDocument.CanvasLayer.Height, 1);
  end;
  FZoom := Min(AvailableWidth / LogicalWidth,
    AvailableHeight / LogicalHeight);
  FZoom := Min(FZoom, 1.0);
  FZoom := FZoom * FViewZoom;
  DisplayWidth := Max(Round(LogicalWidth * FZoom), 1);
  DisplayHeight := Max(Round(LogicalHeight * FZoom), 1);
  FCanvasBounds := Rect(
    (ControlWidth - DisplayWidth) div 2 + Round(FPanOffset.X),
    (ControlHeight - DisplayHeight) div 2 + Round(FPanOffset.Y),
    (ControlWidth + DisplayWidth) div 2 + Round(FPanOffset.X),
    (ControlHeight + DisplayHeight) div 2 + Round(FPanOffset.Y));
  if FTextEditing then
    UpdateTextEditorBounds;
end;

procedure TVectArtCanvasControl.ConfigureInteraction;
begin
  FInteraction.Configure(FDocument, FCanvasBounds, FZoom);
  if FEditorState = nil then
    FInteraction.SetVertexStructureEditing(False, False)
  else
    FInteraction.SetVertexStructureEditing(
      FEditorState.CurrentTool in [vetLine, vetPath, vetShape, vetTextPath],
      FEditorState.CurrentTool in [vetPath, vetShape]);
end;

procedure TVectArtCanvasControl.SyncSelectedPathVertexMode;
var
  Kind: TMapRakuVertexKind;
begin
  if (FEditorState = nil) or
    (FEditorState.CurrentTool <> vetPath) then
    Exit;
  if FInteraction.SelectedPathVertexKind(Kind) then
    FEditorState.NextVertexKind := Kind;
end;

function TVectArtCanvasControl.ApplyPathVertexModeToSelection: Boolean;
begin
  Result := False;
  if (FEditorState = nil) or
    (FEditorState.CurrentTool <> vetPath) then
    Exit;
  ConfigureInteraction;
  Result := FInteraction.SetSelectedPathVertexKind(
    FEditorState.NextVertexKind);
  if Result then
    Invalidate;
end;

function TVectArtCanvasControl.ToScreenX(Value: Single): Integer;
begin
  Result := LogicalToScreenX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TVectArtCanvasControl.ToScreenY(Value: Single): Integer;
begin
  Result := LogicalToScreenY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TVectArtCanvasControl.TryClientPointToLogical(
  const ClientPoint: TPoint; out LogicalPoint: TPointF): Boolean;
begin
  CalculateCanvasBounds;
  Result := (FDocument <> nil) and (FDocument.CanvasLayer <> nil) and
    PtInRect(FCanvasBounds, ClientPoint);
  if not Result then
  begin
    LogicalPoint := TPointF.Zero;
    Exit;
  end;
  LogicalPoint := TPointF.Create(ScreenToLogicalX(ClientPoint.X,
    FCanvasBounds, FZoom, FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ClientPoint.Y, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
end;

function TVectArtCanvasControl.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  CanvasX: Single;
  CanvasY: Single;
  ClientPoint: TPoint;
  NewViewZoom: Single;
begin
  ClientPoint := ScreenToClient(MousePos);
  if not PtInRect(ClientRect, ClientPoint) then
    Exit(inherited DoMouseWheel(Shift, WheelDelta, MousePos));

  Result := True;
  if WheelDelta = 0 then
    Exit;
  CalculateCanvasBounds;
  if FZoom <= 0 then
    Exit;

  // カーソル直下の論理キャンバス座標を、新しい倍率でも同じ位置に保つ。
  CanvasX := (ClientPoint.X - FCanvasBounds.Left) / FZoom;
  CanvasY := (ClientPoint.Y - FCanvasBounds.Top) / FZoom;
  if WheelDelta > 0 then
    NewViewZoom := FViewZoom * VIEW_ZOOM_STEP
  else
    NewViewZoom := FViewZoom / VIEW_ZOOM_STEP;
  NewViewZoom := EnsureRange(NewViewZoom, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM);
  if SameValue(NewViewZoom, FViewZoom) then
    Exit;

  FViewZoom := NewViewZoom;
  FPanOffset := TPointF.Zero;
  CalculateCanvasBounds;
  FPanOffset.X := ClientPoint.X - CanvasX * FZoom - FCanvasBounds.Left;
  FPanOffset.Y := ClientPoint.Y - CanvasY * FZoom - FCanvasBounds.Top;
  CalculateCanvasBounds;
  EndMovePreview;
  FZoomPreviewActive := (FRenderCache.Bitmap.Width > 0) and
    (FRenderCache.Bitmap.Height > 0);
  FZoomRenderTimer.Enabled := False;
  FZoomRenderTimer.Enabled := True;
  Invalidate;
end;

procedure TVectArtCanvasControl.ZoomRenderTimerTick(Sender: TObject);
begin
  FZoomRenderTimer.Enabled := False;
  if not FZoomPreviewActive then
    Exit;
  FZoomPreviewActive := False;
  Invalidate;
end;

procedure TVectArtCanvasControl.EndPan;
begin
  if not FPanning then
    Exit;
  FPanning := False;
  MouseCapture := False;
  Cursor := crDefault;
end;

procedure TVectArtCanvasControl.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if not FPointerInside then
    Exit;
  FPointerInside := False;
  Invalidate;
end;

function TVectArtCanvasControl.StrokeWidthCursorVisible: Boolean;
begin
  Result := FPointerInside and (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetFreehand) and
    PtInRect(FCanvasBounds, FPointerPosition) and not FPanning and
    not FTextEditing;
end;

function TVectArtCanvasControl.StrokeWidthCursorDiameter: Single;
begin
  Result := FEditorState.LineStrokeWidth * FZoom;
  if FPenPointerActive and FPenPressureAvailable and FShapeCreation.Active then
    Result := Result * FPenPressure;
end;

procedure TVectArtCanvasControl.UpdatePenPressure(MessageId: Cardinal;
  WParam: WPARAM);
var
  PenInfo: POINTER_PEN_INFO;
  PointerId: UINT32;
  PointerType: POINTER_INPUT_TYPE;
begin
  PointerId := GET_POINTERID_WPARAM(WParam);
  if not GetPointerType(PointerId, @PointerType) or
    (PointerType <> DWORD(Ord(PT_PEN))) then
  begin
    if MessageId = WM_POINTERDOWN then
    begin
      FPenPointerActive := False;
      FPenPressureAvailable := False;
    end;
    Exit;
  end;
  PenInfo := Default(POINTER_PEN_INFO);
  if not GetPointerPenInfo(PointerId, @PenInfo) then
    Exit;
  if (MessageId = WM_POINTERDOWN) or
    ((PenInfo.pointerInfo.pointerFlags and POINTER_FLAG_INCONTACT) <> 0) then
    FPenPointerActive := True;
  FPenPressureAvailable := (PenInfo.penMask and PEN_MASK_PRESSURE) <> 0;
  if FPenPressureAvailable then
    FPenPressure := EnsureRange(PenInfo.pressure / 1024.0, 0.0, 1.0);
  if FPenPointerActive then
    Invalidate;
end;

procedure TVectArtCanvasControl.KeyDown(var Key: Word;
  Shift: TShiftState);
begin
  if (Shift=[]) and FMapPathEditor.KeyDown(Key) then begin Key:=0; Invalidate; Exit; end;
  if (Key = VK_ESCAPE) and FTransformInteraction.Finish(True) then
  begin
    EndMovePreview;
    Key := 0;
    MouseCapture := False;
    Invalidate;
    Exit;
  end;
  if (Key = VK_ESCAPE) and FInteraction.CancelTextSpacingDrag then
  begin
    Key := 0;
    MouseCapture := False;
    Invalidate;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

function TVectArtCanvasControl.TransformDragging: Boolean;
begin
  Result := FTransformInteraction.Active;
end;

procedure TVectArtCanvasControl.CancelTransformDrag;
begin
  FTransformInteraction.Finish(True);
  EndMovePreview;
  MouseCapture := False;
  Cursor := crDefault;
  Invalidate;
end;

function TVectArtCanvasControl.GetEditHistory: TVectArtEditHistory;
begin
  Result := FInteraction.EditHistory;
end;

function TVectArtCanvasControl.TryPathVertexMenuTarget(
  const ScreenPoint: TPoint; out Layer: TVectArtPathLayer;
  out VertexIndex, SegmentIndex: Integer; out SegmentT: Single): Boolean;
var
  ClientPoint: TPoint;
begin
  CalculateCanvasBounds;
  FMapPathEditor.Configure(FDocument,FEditorState,EditHistory,FCanvasBounds,FZoom);
  ClientPoint:=ScreenToClient(ScreenPoint);
  Result:=FMapPathEditor.ContextTarget(ClientPoint.X,ClientPoint.Y,
    Layer,VertexIndex,SegmentIndex,SegmentT);
end;

function TVectArtCanvasControl.ExecutePathVertexMenuEdit(
  Layer: TVectArtPathLayer; VertexIndex, SegmentIndex: Integer;
  SegmentT: Single; DeleteVertex: Boolean): Boolean;
begin
  FMapPathEditor.Configure(FDocument,FEditorState,EditHistory,FCanvasBounds,FZoom);
  Result:=FMapPathEditor.ExecuteContextEdit(Layer,VertexIndex,SegmentIndex,
    SegmentT,DeleteVertex);
  if Result then Invalidate;
end;

procedure TVectArtCanvasControl.EndPlacement;
var
  LayerCountBefore: Integer;
begin
  if (FDocument = nil) or (FEditorState = nil) or
    ((FEditorState.CurrentTool = vetSelect) and
     (FEditorState.PendingSymbol < 0)) then Exit;
  LayerCountBefore := FDocument.LayerCount;
  CalculateCanvasBounds;
  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  if FShapeCreation.Active then
  begin
    if not FShapeCreation.FinishPath(
      FEditorState.CurrentTool = vetShape) then
      FShapeCreation.CancelPath;
    if FDocument.LayerCount > LayerCountBefore then
    begin
      FLastPlacedLayerIndex := FDocument.LayerCount - 1;
      FLastPlacedLayer := FDocument[FLastPlacedLayerIndex];
    end;
  end;
  FEditorState.CurrentTool := vetSelect;
  FEditorState.PendingSymbol := -1;
  FEditorState.ActiveMapPreset := -1;
  FEditorState.MapElement := '';
  if (FLastPlacedLayerIndex > 0) and
     (FLastPlacedLayerIndex < FDocument.LayerCount) and
     (FDocument[FLastPlacedLayerIndex] = FLastPlacedLayer) then
    FDocument.SelectedIndex := FLastPlacedLayerIndex
  else
    FDocument.SetSelectedLayers([]);
  Invalidate;
end;

procedure TVectArtCanvasControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  GroupChild: TVectArtLayer;
  GroupChildBounds: TRectF;
  GroupChildRect: TRect;
  Handle: TVectArtSelectionHandle;
  LayerIndex: Integer;
  LogicalPoint: TPointF;
  OpenGroupBounds: TRectF;
  SelectionGeometry: TVectArtSelectionGeometry;
  TextLayerIndex: Integer;
  VertexCaptureNeeded: Boolean;
  LogicalPointValid: Boolean;
  PathMenuLayer: TVectArtPathLayer;
  PathMenuVertex, PathMenuSegment: Integer;
  PathMenuT: Single;
  LayerCountBefore: Integer;
begin
  LayerCountBefore := 0;
  if FDocument <> nil then LayerCountBefore := FDocument.LayerCount;
  FPointerPosition := Point(X, Y);
  FPointerInside := PtInRect(ClientRect, FPointerPosition);
  if (Button = mbLeft) and (FEditorState <> nil) and (FEditorState.PendingSymbol >= 0) then
  begin
    CalculateCanvasBounds;
    if TryClientPointToLogical(Point(X,Y), LogicalPoint) then
    begin
      PlaceMapSymbol(FDocument, EditHistory, FEditorState.PendingSymbol,
        FEditorState.PendingSymbolLabel, LogicalPoint, not (ssAlt in Shift));
      if FDocument.LayerCount > LayerCountBefore then
      begin
        FLastPlacedLayerIndex := FDocument.LayerCount - 1;
        FLastPlacedLayer := FDocument[FLastPlacedLayerIndex];
      end;
      FEditorState.PendingSymbol := -1;
      FEditorState.ActiveMapPreset := -1;
      Invalidate;
    end;
    Exit;
  end;  CalculateCanvasBounds;
  if (Button = mbRight) and (FEditorState <> nil) and
    ((FEditorState.CurrentTool <> vetSelect) or
     (FEditorState.PendingSymbol >= 0)) then
  begin
    EndPlacement;
    Exit;
  end;
  FMapPathEditor.Configure(FDocument,FEditorState,EditHistory,FCanvasBounds,FZoom);
  if FMapPathEditor.MouseDown(Button,Shift,X,Y) then begin
    if CanFocus then SetFocus;
    MouseCapture := Button = mbLeft; Invalidate; Exit;
  end;  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  if (Button = mbRight) and (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape, vetTextPath]) and
    FShapeCreation.Active then
  begin
    if not FShapeCreation.FinishPath(
      FEditorState.CurrentTool = vetShape) then
      FShapeCreation.CancelPath;
    BeginCreatedTextPathEdit;
    Invalidate;
    Exit;
  end;
  CalculateCanvasBounds;
  // ペン系ツールでも頂点上だけは削除を優先し、未命中は通常のオブジェクトメニュー判定へ渡す。
  if (Button = mbRight) and (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetLine, vetPath, vetShape, vetTextPath]) then
  begin
    CalculateCanvasBounds;
    ConfigureInteraction;
    if FInteraction.MouseDownSelectedVertex(Button, Shift, X, Y,
      VertexCaptureNeeded) then
    begin
      Invalidate;
      Exit;
    end;
  end;
  FTextureInteraction.Configure(FDocument, EditHistory, FEditorState, FCanvasBounds, FZoom);
  if FTextureInteraction.MouseDown(Button, X, Y) then
  begin
    if CanFocus then SetFocus;
    MouseCapture := True;
    Cursor := crSizeAll;
    Invalidate;
    Exit;
  end;
  FGradientInteraction.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  if FGradientInteraction.MouseDown(Button, X, Y) then
  begin
    if CanFocus then
      SetFocus;
    if Button = mbLeft then
      MouseCapture := True;
    Cursor := FGradientInteraction.CursorAt(X, Y);
    Invalidate;
    Exit;
  end;
  if Button = mbRight then
  begin
    CalculateCanvasBounds;
    ConfigureInteraction;
    // 地図経路の右クリックは頂点を直接削除せず、位置付きメニューへ渡す。
    if not FMapPathEditor.ContextTarget(X,Y,PathMenuLayer,
      PathMenuVertex,PathMenuSegment,PathMenuT) and
      FInteraction.MouseDown(Button, Shift, X, Y) then
    begin
      Invalidate;
      Exit;
    end;
    if (FEditorState <> nil) and
      not (FEditorState.CurrentTool in
        [vetSelect, vetLine, vetPath, vetShape, vetTextPath]) then Exit;
    LogicalPointValid := TryClientPointToLogical(Point(X, Y), LogicalPoint);
    LayerIndex := FInteraction.LayerAt(X, Y);
    if (LayerIndex <= 0) and (PathMenuLayer = nil) then
      Exit;
    if (LayerIndex > 0) and not FDocument.IsLayerSelected(LayerIndex) then
    begin
      SelectMapRakuContextMenuTarget(FDocument, FEditorState,
        LayerIndex, LogicalPoint, LogicalPointValid);
      Invalidate;
      Exit;
    end;
    if (((LayerIndex<=0) and (PathMenuLayer<>nil)) or
      SelectMapRakuContextMenuTarget(FDocument, FEditorState,
        LayerIndex, LogicalPoint, LogicalPointValid)) and
      Assigned(FOnObjectContextMenu) then
    begin
      FOnObjectContextMenu(Self, ClientToScreen(Point(X, Y)),
        FInteraction.LayersAt(X, Y));
      Invalidate;
      Exit;
    end;
    inherited MouseDown(Button, Shift, X, Y);
    Exit;
  end;
  if Button = mbMiddle then
  begin
    FPanning := True;
    FPanStartMouse := Point(X, Y);
    FPanStartOffset := FPanOffset;
    MouseCapture := True;
    Cursor := crSizeAll;
    Exit;
  end;
  if (Button = mbLeft) and (FDocument <> nil) then
  begin
    CalculateCanvasBounds;
    FFilterInteraction.Configure(FDocument, EditHistory, FEditorState,
      FCanvasBounds, FZoom);
    if FFilterInteraction.MouseDown(X, Y) then
    begin
      if CanFocus then
        SetFocus;
      MouseCapture := True;
      Cursor := FFilterInteraction.CursorAt(X, Y);
      Exit;
    end;
    ConfigureInteraction;
    LayerIndex := FInteraction.LayerAt(X, Y);
    if (LayerIndex > 0) and (FEditorState <> nil) and
      (FEditorState.SelectedFilter <> nil) then
      FEditorState.SelectFilter(nil, nil);
    if FTextEditing then
    begin
      CalculateCanvasBounds;
      ConfigureInteraction;
      if (FTextLayerIndex < 0) and (FEditorState <> nil) and
        (FEditorState.OpenGroup <> nil) and
        TryClientPointToLogical(Point(X, Y), LogicalPoint) and
        (HitTestGroupChild(FEditorState.OpenGroup, LogicalPoint) = FTextLayer) then
      begin
        SetTextCaretFromClientPoint(X, Y, ssShift in Shift);
        Exit;
      end;
      TextLayerIndex := FInteraction.LayerAt(X, Y);
      if (FTextLayerIndex > 0) and (TextLayerIndex = FTextLayerIndex) then
      begin
        SetTextCaretFromClientPoint(X, Y, ssShift in Shift);
        Exit;
      end;
      FinishTextEditAndSelect(False);
    end;
    if CanFocus then
      SetFocus;
    CalculateCanvasBounds;
    ConfigureInteraction;
    FTransformInteraction.Configure(FDocument, EditHistory, FEditorState, FCanvasBounds, FZoom);
    if FTransformInteraction.HasTransformedSelection and
      FInteraction.MouseDownSelectedVertex(Button, Shift, X, Y, VertexCaptureNeeded) then
    begin
      if VertexCaptureNeeded then MouseCapture := True;
      Cursor := crCross;
      Invalidate;
      Exit;
    end;
    if FTransformInteraction.MouseDown(Shift, X, Y) then
    begin
      EndMovePreview;
      MouseCapture := True;
      Cursor := crCross;
      Invalidate;
      Exit;
    end;
    // Creation tools take precedence over existing layer frames and open
    // group hit-testing. Only an explicit vertex/control-point hit keeps
    // the structural editing behavior of line, path, and shape tools.
    if (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetLine, vetPath, vetShape,
        vetTextPath]) and
      FInteraction.MouseDownSelectedVertex(Button, Shift, X, Y,
        VertexCaptureNeeded) then
    begin
      SyncSelectedPathVertexMode;
      if VertexCaptureNeeded then
        MouseCapture := True;
      Cursor := FInteraction.CursorAt(X, Y);
      Invalidate;
      Exit;
    end;
    FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
      FCanvasBounds, FZoom);
    FShapeCreation.SetInputPressure(FPenPressure,
      FPenPointerActive and FPenPressureAvailable);
    if FShapeCreation.MouseDown(Button, Shift, X, Y) then
    begin
      if FDocument.LayerCount > LayerCountBefore then
      begin
        FLastPlacedLayerIndex := FDocument.LayerCount - 1;
        FLastPlacedLayer := FDocument[FLastPlacedLayerIndex];
      end;
      BeginCreatedTextPathEdit;
      if FTextEditing and (ssDouble in Shift) then
        FSkipTextDblClick := True;
      if (FEditorState <> nil) and
        not (FEditorState.CurrentTool in [vetPath, vetShape,
          vetTextPath]) then
        MouseCapture := True;
      if FTextEditing then
        Cursor := crIBeam
      else if (FEditorState <> nil) and
        (FEditorState.CurrentTool = vetFreehand) then
        Cursor := crNone
      else
        Cursor := crCross;
      Invalidate;
      Exit;
    end;
    if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
      (FEditorState.OpenGroupChild <> nil) and
      OpenGroupSelectionEditable(FEditorState) and
      TryGetOpenGroupSelectionBounds(FEditorState, GroupChildBounds) then
    begin
      GroupChildRect := Rect(ToScreenX(GroupChildBounds.Left),
        ToScreenY(GroupChildBounds.Top), ToScreenX(GroupChildBounds.Right),
        ToScreenY(GroupChildBounds.Bottom));
      SelectionGeometry := BuildSelectionGeometry(GroupChildRect,
        SelectionFrameOffset(0, FZoom));
      if HitTestRotationHandle(Point(X, Y), SelectionGeometry) then
      begin
        FGroupDrag.BeginRotate(FDocument,
          FEditorState.GetOpenGroupChildren, GroupChildBounds.CenterPoint,
          RadToDeg(ArcTan2(Y - ToScreenY(GroupChildBounds.CenterPoint.Y),
            X - ToScreenX(GroupChildBounds.CenterPoint.X))));
        MouseCapture := True;
        Cursor := RotationHandleCursor;
        Exit;
      end;
      Handle := HitTestSelectionHandle(Point(X, Y), SelectionGeometry);
      if Handle <> vshNone then
      begin
        FGroupDrag.BeginResize(FDocument,
          FEditorState.GetOpenGroupChildren, Point(X, Y), Handle,
          GroupChildBounds);
        MouseCapture := True;
        Cursor := SelectionHandleCursor(Handle);
        Exit;
      end;
    end;
    if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
      if not TryClientPointToLogical(Point(X, Y), LogicalPoint) or
        not TryGetMapRakuLayerBounds(FEditorState.OpenGroup,
          OpenGroupBounds) or not OpenGroupBounds.Contains(LogicalPoint) then
        FEditorState.OpenGroup := nil;
    if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
      (ssDouble in Shift) and
      TryClientPointToLogical(Point(X, Y), LogicalPoint) then
    begin
      GroupChild := HitTestGroupChild(FEditorState.OpenGroup, LogicalPoint);
      if GroupChild is TMapRakuGroupLayer then
      begin
        FDocument.SetSelectedLayers([]);
        FEditorState.OpenChildGroup(TMapRakuGroupLayer(GroupChild));
        Invalidate;
        Exit;
      end;
    end;
    if (FEditorState <> nil) and (ssDouble in Shift) then
    begin
      LayerIndex := FInteraction.LayerAt(X, Y);
      if (LayerIndex > 0) and
        (FDocument[LayerIndex] is TMapRakuGroupLayer) then
      begin
        FDocument.SelectedIndex := LayerIndex;
        if FEditorState.OpenGroup = FDocument[LayerIndex] then
          FEditorState.OpenGroup := nil
        else
          FEditorState.OpenGroup := TMapRakuGroupLayer(
            FDocument[LayerIndex]);
        if (FEditorState.OpenGroup<>nil) and (FEditorState.OpenGroup.ChildCount=1) then
          FEditorState.OpenGroupChild:=FEditorState.OpenGroup[0];
        Invalidate;
        Exit;
      end;
    end;
    if (FEditorState <> nil) and (FEditorState.CurrentTool = vetText) and
      (FEditorState.OpenGroup <> nil) and
      TryClientPointToLogical(Point(X, Y), LogicalPoint) then
    begin
      GroupChild := HitTestGroupChild(FEditorState.OpenGroup, LogicalPoint);
      if (GroupChild is TMapRakuTextLayer) and not GroupChild.Locked then
      begin
        FEditorState.OpenGroupChild := GroupChild;
        BeginExistingTextLayerEdit(TMapRakuTextLayer(GroupChild), -1);
        SetTextCaretFromClientPoint(X, Y, ssShift in Shift);
        Cursor := crIBeam;
        Invalidate;
        Exit;
      end;
    end;
    if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
      TryClientPointToLogical(Point(X, Y), LogicalPoint) then
    begin
      GroupChild := HitTestGroupChild(FEditorState.OpenGroup,
        LogicalPoint);
      FDocument.SetSelectedLayers([]);
      if ssCtrl in Shift then
      begin
        if GroupChild <> nil then
          FEditorState.ToggleOpenGroupChild(GroupChild);
        Invalidate;
        Exit;
      end;
      if (GroupChild <> nil) and
        not FEditorState.IsOpenGroupChildSelected(GroupChild) then
        FEditorState.OpenGroupChild := GroupChild
      else if GroupChild = nil then
        FEditorState.OpenGroupChild := nil;
      if (GroupChild <> nil) and OpenGroupSelectionEditable(FEditorState) then
      begin
        FGroupDrag.BeginMove(FDocument,
          FEditorState.GetOpenGroupChildren, Point(X, Y));
        MouseCapture := True;
        Cursor := crSizeAll;
      end;
      Invalidate;
      Exit;
    end;
    if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetText) then
    begin
      if not PtInRect(FCanvasBounds, Point(X, Y)) then
        Exit;
      ConfigureInteraction;
      TextLayerIndex := FInteraction.LayerAt(X, Y);
      if (TextLayerIndex > 0) and
        (FDocument[TextLayerIndex] is TMapRakuTextLayer) then
      begin
        BeginExistingTextEdit(TextLayerIndex);
        SetTextCaretFromClientPoint(X, Y, ssShift in Shift);
        Cursor := crIBeam;
        Invalidate;
        Exit;
      end;
      FTextDragActive := True;
      FTextDragStart := Point(X, Y);
      FTextDragCurrent := FTextDragStart;
      MouseCapture := True;
      Cursor := crIBeam;
      Invalidate;
      Exit;
    end;
    if (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetRectangleLine, vetRectangle,
        vetRoundedRectangleLine, vetRoundedRectangle,
        vetEllipseLine, vetEllipse, vetArc, vetArcShape, vetLine,
        vetFreehand, vetPath, vetShape, vetText, vetTextPath]) then
    begin
      if FEditorState.CurrentTool = vetText then
        Cursor := crIBeam
      else
        Cursor := crCross;
      Exit;
    end;
    ConfigureInteraction;
    if FInteraction.MouseDown(Button, Shift, X, Y) then
    begin
      EndMovePreview;
      MouseCapture := True;
      Cursor := FInteraction.CursorAt(X, Y);
    end;
    Invalidate;
    Exit;
  end;
  // 左ドラッグは将来の範囲選択用として、この段階では開始しない。
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtCanvasControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  Angle: Single;
  GroupChildBounds: TRectF;
  GroupChildRect: TRect;
  Handle: TVectArtSelectionHandle;
  SelectionGeometry: TVectArtSelectionGeometry;
begin
  if FMapPathEditor.MouseMove(Shift,X,Y) then begin Invalidate; Exit; end;
  FPointerPosition := Point(X, Y);
  FPointerInside := PtInRect(ClientRect, FPointerPosition);
  if FTransformInteraction.Active and FTransformInteraction.Moving and
    not FRenderCache.MoveAttempted then
    BeginMovePreview;
  if FTransformInteraction.MouseMove(Shift, X, Y) then
  begin
    Cursor := crCross; Invalidate; Exit;
  end;
  CalculateCanvasBounds;
  FTextureInteraction.Configure(FDocument, EditHistory, FEditorState, FCanvasBounds, FZoom);
  if FTextureInteraction.MouseMove(Shift, X, Y) then
  begin
    Cursor := crSizeAll;
    Invalidate;
    Exit;
  end;
  FGradientInteraction.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  if FGradientInteraction.MouseMove(Shift, X, Y) then
  begin
    Cursor := FGradientInteraction.CursorAt(X, Y);
    Invalidate;
    Exit;
  end;
  FFilterInteraction.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  if FFilterInteraction.MouseMove(X, Y) then
  begin
    Cursor := FFilterInteraction.CursorAt(X, Y);
    Invalidate;
    Exit;
  end;
  if FGroupDrag.UpdateMoveOrResize(Shift, X, Y, FZoom) then
  begin
    if FGroupDrag.Mode = slgdmMove then
      Cursor := crSizeAll
    else
      Cursor := SelectionHandleCursor(FGroupDrag.ResizeHandle);
    Invalidate;
    Exit;
  end;
  if FGroupDrag.Mode = slgdmRotate then
  begin
    Angle := RadToDeg(ArcTan2(
      Y - ToScreenY(FGroupDrag.RotationCenter.Y),
      X - ToScreenX(FGroupDrag.RotationCenter.X)));
    FGroupDrag.UpdateRotation(Angle, Shift);
    Cursor := RotationHandleCursor;
    Invalidate;
    Exit;
  end;
  if FTextDragActive then
  begin
    FTextDragCurrent := Point(X, Y);
    Cursor := crIBeam;
    Invalidate;
    Exit;
  end;
  if FPanning then
  begin
    if not (ssMiddle in Shift) then
    begin
      EndPan;
      Exit;
    end;
    FPanOffset.X := FPanStartOffset.X + X - FPanStartMouse.X;
    FPanOffset.Y := FPanStartOffset.Y + Y - FPanStartMouse.Y;
    CalculateCanvasBounds;
    Invalidate;
    Exit;
  end;
  CalculateCanvasBounds;
  if (FEditorState <> nil) and (FEditorState.OpenGroupChild <> nil) and
    OpenGroupSelectionEditable(FEditorState) and
    TryGetOpenGroupSelectionBounds(FEditorState, GroupChildBounds) then
  begin
    GroupChildRect := Rect(ToScreenX(GroupChildBounds.Left),
      ToScreenY(GroupChildBounds.Top), ToScreenX(GroupChildBounds.Right),
      ToScreenY(GroupChildBounds.Bottom));
    SelectionGeometry := BuildSelectionGeometry(GroupChildRect,
      SelectionFrameOffset(0, FZoom));
    if HitTestRotationHandle(Point(X, Y), SelectionGeometry) then
    begin
      Cursor := RotationHandleCursor;
      Exit;
    end;
    Handle := HitTestSelectionHandle(Point(X, Y), SelectionGeometry);
    if Handle <> vshNone then
    begin
      Cursor := SelectionHandleCursor(Handle);
      Exit;
    end;
  end;
  ConfigureInteraction;
  if FInteraction.Dragging and FInteraction.Moving and
    not FRenderCache.MoveAttempted then
    BeginMovePreview;
  if FInteraction.Dragging and FInteraction.MouseMove(Shift, X, Y) then
  begin
    if not FInteraction.Dragging then
    begin
      MouseCapture := False;
      EndMovePreview;
    end;
    Cursor := FInteraction.CursorAt(X, Y);
    Invalidate;
    Exit;
  end;
  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  FShapeCreation.SetInputPressure(FPenPressure,
    FPenPointerActive and FPenPressureAvailable);
  if FShapeCreation.MouseMove(Shift, X, Y) then
  begin
    if not FShapeCreation.Active then
      MouseCapture := False;
    if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetFreehand) then
      Cursor := crNone
    else
      Cursor := crCross;
    Invalidate;
    Exit;
  end;
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetPath) then
  begin
    Cursor := FInteraction.CursorAt(X, Y);
    if Cursor <> crDefault then
      Exit;
  end;
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetRectangleLine, vetRectangle,
      vetRoundedRectangleLine, vetRoundedRectangle,
      vetEllipseLine, vetEllipse, vetArc, vetArcShape, vetLine,
      vetFreehand, vetPath, vetShape, vetText, vetTextPath]) then
  begin
    if FEditorState.CurrentTool = vetText then
      Cursor := crIBeam
    else if FEditorState.CurrentTool = vetFreehand then
      Cursor := crNone
    else
      Cursor := crCross;
    Invalidate;
    Exit;
  end;
  ConfigureInteraction;
  if FInteraction.MouseMove(Shift, X, Y) then
  begin
    if not FInteraction.Dragging then
      MouseCapture := False;
    Cursor := FInteraction.CursorAt(X, Y);
    Invalidate;
    Exit;
  end;
  Cursor := FInteraction.CursorAt(X, Y);
  inherited MouseMove(Shift, X, Y);
end;

procedure TVectArtCanvasControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  AutoExpandWidth: Boolean;
  Bottom: Single;
  GuideRect: TRect;
  Left: Single;
  Right: Single;
  Top: Single;
  LayerCountBefore: Integer;
begin
  LayerCountBefore := 0;
  if FDocument <> nil then LayerCountBefore := FDocument.LayerCount;
  if (Button=mbLeft) and FMapPathEditor.MouseUp then begin MouseCapture:=False; Invalidate; Exit; end;
  if (Button = mbLeft) and FTransformInteraction.Finish then
  begin
    EndMovePreview;
    MouseCapture := False; Cursor := crDefault; Invalidate; Exit;
  end;
  if Button = mbLeft then
  begin
    CalculateCanvasBounds;
    if FTextureInteraction.MouseUp(X, Y) then
    begin
      MouseCapture := False;
      Cursor := crDefault;
      Invalidate;
      Exit;
    end;
    FGradientInteraction.Configure(FDocument, EditHistory, FEditorState,
      FCanvasBounds, FZoom);
    if FGradientInteraction.MouseUp(X, Y) then
    begin
      MouseCapture := False;
      Cursor := FGradientInteraction.CursorAt(X, Y);
      Invalidate;
      Exit;
    end;
  end;
  if (Button = mbLeft) and FFilterInteraction.MouseUp then
  begin
    MouseCapture := False;
    Cursor := crDefault;
    Invalidate;
    Exit;
  end;
  if (Button = mbLeft) and FGroupDrag.Active then
  begin
    MouseCapture := False;
    FGroupDrag.Finish(EditHistory);
    Cursor := crDefault;
    Invalidate;
    Exit;
  end;
  if (Button = mbLeft) and FTextDragActive then
  begin
    FTextDragActive := False;
    MouseCapture := False;
    FTextDragCurrent := Point(X, Y);
    GuideRect := TRect.Create(Min(FTextDragStart.X, X),
      Min(FTextDragStart.Y, Y), Max(FTextDragStart.X, X),
      Max(FTextDragStart.Y, Y));
    // TRectの正規化やキャンバスとの交差結果ではなく、実際のドラッグ距離でクリック配置を判定する。
    AutoExpandWidth := (Abs(X - FTextDragStart.X) < 4) and
      (Abs(Y - FTextDragStart.Y) < 4);
    if AutoExpandWidth then
      GuideRect := TRect.Create(FTextDragStart.X, FTextDragStart.Y,
        FTextDragStart.X + Round(DEFAULT_TEXT_GUIDE_WIDTH * FZoom),
        FTextDragStart.Y + Round(DEFAULT_TEXT_GUIDE_HEIGHT * FZoom));
    GuideRect.Intersect(FCanvasBounds);
    Left := ScreenToLogicalX(GuideRect.Left, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width);
    Top := ScreenToLogicalY(GuideRect.Top, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height);
    Right := ScreenToLogicalX(GuideRect.Right, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width);
    Bottom := ScreenToLogicalY(GuideRect.Bottom, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height);
    BeginNewTextEdit(TRectF.Create(Left, Top, Right, Bottom),
      AutoExpandWidth);
    Cursor := crIBeam;
    Invalidate;
    Exit;
  end;
  if (Button = mbMiddle) and FPanning then
  begin
    EndPan;
    Exit;
  end;
  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  FShapeCreation.SetInputPressure(FPenPressure,
    FPenPointerActive and FPenPressureAvailable);
  if FShapeCreation.MouseUp(Button, Shift, X, Y) then
  begin
    if FDocument.LayerCount > LayerCountBefore then
    begin
      FLastPlacedLayerIndex := FDocument.LayerCount - 1;
      FLastPlacedLayer := FDocument[FLastPlacedLayerIndex];
    end;
    FPenPointerActive := False;
    MouseCapture := False;
    if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetFreehand) then
      Cursor := crNone
    else
      Cursor := crCross;
    Invalidate;
    Exit;
  end;
  if FInteraction.MouseUp(Button) then
  begin
    EndMovePreview;
    MouseCapture := False;
    ConfigureInteraction;
    Cursor := FInteraction.CursorAt(X, Y);
    Invalidate;
    Exit;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TVectArtCanvasControl.Paint;
begin
  CalculateCanvasBounds;
  ConfigureInteraction;
  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  UpdateRenderedDocument;
  FPlacementPreview.Update(FDocument, FEditorState, FShapeCreation.PreviewRect, FCanvasBounds, FZoom);
  if FDirect2DEnabled then
    try
      PaintDirect2D;
      Exit;
    except
      FDirect2DEnabled := False;
    end;
  PaintGDI;
end;

procedure TVectArtCanvasControl.UpdateRenderedDocument;
var
  Height: Integer;
  InputTextLayer: TMapRakuTextLayer;
  PreviewStrokeWidth: Single;
  Width: Integer;
begin
  if (FDocument = nil) or (FDocument.CanvasLayer = nil) then
  begin
    FRenderCache.Reset;
    Exit;
  end;
  // The editor only needs as many pixels as are currently visible. Keeping
  // the native document size while zoomed out makes interactive blur and
  // shadow changes needlessly process millions of hidden pixels.
  Width := Max(Min(FCanvasBounds.Width,
    FDocument.CanvasLayer.Width), 1);
  Height := Max(Min(FCanvasBounds.Height,
    FDocument.CanvasLayer.Height), 1);
  PreviewStrokeWidth := 0.0;
  if ENABLE_THIN_STROKE_PREVIEW and (FZoom > 0) then
    PreviewStrokeWidth := MIN_PREVIEW_STROKE_WIDTH_PIXELS / FZoom;
  InputTextLayer := nil;
  if FTextEditing then
    InputTextLayer := EditingTextLayer;
  FRenderCache.Update(FDocument, Width, Height, PreviewStrokeWidth,
    InputTextLayer, FTextInputOutlineColor, FZoomPreviewActive,
    FInteraction.Moving or FTransformInteraction.Moving);
end;

function CreationPathPreviewColor(State: TVectArtEditorState;
  Document: TVectArtDocument): TColor;
var FromSelectedObject: Boolean;
begin
  if (State.MapElement = 'road') or (State.MapElement = 'river') then
    Result := State.MapPlacementColor(Document,FromSelectedObject)
  else if (Document <> nil) and (State.MapElement = 'jr') then
    Result := Document.CanvasLayer.JrPrimaryColor
  else if (Document <> nil) and (State.MapElement = 'rail') then
    Result := Document.CanvasLayer.RailPrimaryColor
  else
    Result := State.LineStrokeColor;
end;

procedure TVectArtCanvasControl.PaintDirect2D;
var
  ArcHandles: TMapRakuArcAngleHandles;
  TextSpacingHandles: TMapRakuTextSpacingHandles;
  TextIndividualGapIndex: Integer;
  TextIndividualHandle: TMapRakuTextIndividualSpacingHandle;
  TextIndividualHandles: TArray<TMapRakuTextIndividualSpacingHandle>;
  TextSpacingIsLetter: Boolean;
  TextSpacingRatio: Single;
  ArcLayer: TMapRakuArcLayer;
  ArcPreview: TArray<TPoint>;
  BezierHandles: TMapRakuBezierHandles;
  CanvasLayer: TVectArtCanvasLayer;
  CellRect: TRect;
  CreationRect: TRect;
  Column: Integer;
  ColumnEnd: Integer;
  ColumnStart: Integer;
  CornerHandle: TMapRakuRoundedCornerHandle;
  CornerHandles: TArray<TMapRakuRoundedCornerHandle>;
  Direct2DCanvas: TDirect2DCanvas;
  DocumentBitmap: ID2D1Bitmap;
  ReferenceBitmap: ID2D1Bitmap;
  ReferenceRect: TD2D1RectF;
  Handle: TVectArtSelectionHandle;
  RotationHandleIndex: Integer;
  RotationArcPoints: TArray<TPoint>;
  RotationArrowPoints: TArray<TPoint>;
  RotationMarkColor: TColor;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Layer: TVectArtLayer;
  RectangleLine: TMapRakuRectangleLineLayer;
  LayerRect: TRect;
  LineEnd: TPoint;
  LineStart: TPoint;
  PathGuidePoints: TArray<TPoint>;
  PathPreview: TArray<TPoint>;
  PathWidthHandle: TMapRakuPathWidthHandle;
  PathWidthHandles: TArray<TMapRakuPathWidthHandle>;
  PathWidthScales: TArray<Single>;
  PathVertexRects: TArray<TRect>;
  PreviewRadius: Integer;
  SelectedShapeVertexRect: TRect;
  ShapeKindButtons: TArray<TMapRakuVertexKindButton>;
  ShapeKindIconPoints: TArray<TPoint>;
  ShapeVertexRects: TArray<TRect>;
  LogicalQuad: TVectArtQuad;
  PathLayer: TVectArtPathLayer;
  PathVertices: TArray<TMapRakuVertex>;
  RectangleLayer: TVectArtRectangleLayer;
  ShapeLayer: TMapRakuShapeLayer;
  RotatedBounds: TRectF;
  RangeRect: TRect;
  RadiusHandlePoints: TArray<TPoint>;
  RadiusHandleRect: TRect;
  Row: Integer;
  RowEnd: Integer;
  RowStart: Integer;
  CharacterGeometry: TVectArtSelectionGeometry;
  SelectionGeometry: TVectArtSelectionGeometry;
  SelectionFrameOffsetPixels: Integer;
  SelectionLayerRect: TRect;
  SelectionLocked: Boolean;
  ScreenQuad: TVectArtScreenQuad;
  ShadowBounds: TRect;
  VisibleCanvasBounds: TRect;
begin
  Direct2DCanvas := TDirect2DCanvas.Create(Canvas, ClientRect);
  try
    Direct2DCanvas.BeginDraw;
    try
      SelectionLayerRect := TRect.Empty;
      SelectionFrameOffsetPixels := SelectionFrameOffset(0, FZoom);
      SelectionLocked := False;
      Direct2DCanvas.Brush.Color := COLOR_EDITOR_SURROUND;
      Direct2DCanvas.FillRect(ClientRect);
      ShadowBounds := FCanvasBounds;
      OffsetRect(ShadowBounds, CANVAS_SHADOW_OFFSET, CANVAS_SHADOW_OFFSET);
      Direct2DCanvas.Brush.Color := COLOR_CANVAS_SHADOW;
      Direct2DCanvas.FillRect(ShadowBounds);

      CanvasLayer := nil;
      if FDocument <> nil then
        CanvasLayer := FDocument.CanvasLayer;
      if HasReferenceBackground then
      begin
        ReferenceBitmap := Direct2DCanvas.CreateBitmap(FReferenceBackground);
        if ReferenceBitmap = nil then
          raise EInvalidOp.Create('Direct2D reference background creation failed');
        ReferenceRect := D2D1RectF(FCanvasBounds.Left, FCanvasBounds.Top,
          FCanvasBounds.Right, FCanvasBounds.Bottom);
        Direct2DCanvas.RenderTarget.DrawBitmap(ReferenceBitmap,
          @ReferenceRect);
        ReferenceBitmap := nil;
      end
      else if (CanvasLayer <> nil) and CanvasLayer.Visible and
        not CanvasLayer.Transparent then
      begin
        Direct2DCanvas.Brush.Color := CanvasLayer.BackgroundColor;
        Direct2DCanvas.FillRect(FCanvasBounds);
      end
      else
      begin
        if IntersectRect(VisibleCanvasBounds, FCanvasBounds, ClientRect) then
        begin
          ColumnStart := (VisibleCanvasBounds.Left - FCanvasBounds.Left) div
            TRANSPARENCY_CELL;
          ColumnEnd := (VisibleCanvasBounds.Right - 1 - FCanvasBounds.Left) div
            TRANSPARENCY_CELL;
          RowStart := (VisibleCanvasBounds.Top - FCanvasBounds.Top) div
            TRANSPARENCY_CELL;
          RowEnd := (VisibleCanvasBounds.Bottom - 1 - FCanvasBounds.Top) div
            TRANSPARENCY_CELL;
          for Row := RowStart to RowEnd do
            for Column := ColumnStart to ColumnEnd do
            begin
              CellRect := Rect(
                FCanvasBounds.Left + Column * TRANSPARENCY_CELL,
                FCanvasBounds.Top + Row * TRANSPARENCY_CELL,
                Min(FCanvasBounds.Left + (Column + 1) * TRANSPARENCY_CELL,
                  FCanvasBounds.Right),
                Min(FCanvasBounds.Top + (Row + 1) * TRANSPARENCY_CELL,
                  FCanvasBounds.Bottom));
              if Odd(Row + Column) then
                Direct2DCanvas.Brush.Color := COLOR_TRANSPARENT_A
              else
                Direct2DCanvas.Brush.Color := COLOR_TRANSPARENT_B;
              Direct2DCanvas.FillRect(CellRect);
            end;
        end;
      end;

      if (FRenderCache.Bitmap.Width > 0) and
        (FRenderCache.Bitmap.Height > 0) then
      begin
        DocumentBitmap := Direct2DCanvas.CreateBitmap(FRenderCache.Bitmap);
        if DocumentBitmap = nil then
          raise EInvalidOp.Create('Direct2D document bitmap creation failed');
        ReferenceRect := D2D1RectF(FCanvasBounds.Left, FCanvasBounds.Top,
          FCanvasBounds.Right, FCanvasBounds.Bottom);
        Direct2DCanvas.RenderTarget.DrawBitmap(DocumentBitmap,
          @ReferenceRect);
        DocumentBitmap := nil;
      end;
      DrawCanvasCropMarks(Direct2DCanvas, FCanvasBounds);

      if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
        TryGetMapRakuLayerBounds(FEditorState.OpenGroup,
          RotatedBounds) then
      begin
        LayerRect := Rect(ToScreenX(RotatedBounds.Left),
          ToScreenY(RotatedBounds.Top), ToScreenX(RotatedBounds.Right),
          ToScreenY(RotatedBounds.Bottom));
        InflateRect(LayerRect, 5, 5);
        DrawOverlayFrameRect(Direct2DCanvas, LayerRect,
          COLOR_OPEN_GROUP, psDash);
      end;
      if (FEditorState <> nil) and
        (FEditorState.OpenGroupChild <> nil) and
        not EditingTextPath and
        TryGetOpenGroupSelectionBounds(FEditorState, RotatedBounds) then
      begin
        LayerRect := Rect(ToScreenX(RotatedBounds.Left),
          ToScreenY(RotatedBounds.Top), ToScreenX(RotatedBounds.Right),
          ToScreenY(RotatedBounds.Bottom));
        SelectionGeometry := BuildSelectionGeometry(LayerRect,
          SelectionFrameOffset(0, FZoom));
        FTransformInteraction.Configure(FDocument, EditHistory, FEditorState, FCanvasBounds, FZoom);
        if FTransformInteraction.Active or FTransformInteraction.HasTransformedSelection then
          FTransformInteraction.Geometry(SelectionGeometry);
        DrawOverlayPolyline(Direct2DCanvas,
          SelectionGeometry.FramePoints);
        if OpenGroupSelectionEditable(FEditorState) then
        begin
          for Handle := vshTopLeft to vshLeft do
          begin
            DrawOverlayHandleRect(Direct2DCanvas,
              SelectionGeometry.Handles[Handle]);
          end;
          DrawOverlayLine(Direct2DCanvas,
            SelectionGeometry.RotationStem[0],
            SelectionGeometry.RotationStem[1]);
          DrawOverlayHandleEllipse(Direct2DCanvas,
            SelectionGeometry.PrimaryRotationHandle, clWhite,
            COLOR_ROTATION_MARK);
        end;
      end;

      if FDocument <> nil then
        for I := 1 to FDocument.LayerCount - 1 do
        begin
          Layer := FDocument[I];
          if not Layer.Visible or
            not ((Layer is TMapRakuGroupLayer) or
              (Layer is TMapRakuRectangleLineLayer) or
              (Layer is TVectArtRectangleLayer) or
              (Layer is TMapRakuArcLayer) or
              (Layer is TVectArtPathLayer) or
              (Layer is TMapRakuShapeLayer) or
              (Layer is TVectArtImageLayer)) then
            Continue;
          if Layer is TMapRakuGroupLayer then
          begin
            if not TryGetMapRakuLayerBounds(Layer, RotatedBounds) then
              Continue;
          end
          else if Layer is TMapRakuRectangleLineLayer then
          begin
            RectangleLine := TMapRakuRectangleLineLayer(Layer);
            RotatedBounds := QuadBounds(RectangleCorners(
              RectangleLine.Bounds, RectangleLine.RotationDegrees));
            SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
              SelectionFrameOffset(RectangleLine.StrokeWidth, FZoom));
          end
          else if Layer is TMapRakuTextPathLayer then
          begin
            if not TryGetMapRakuTextPathBounds(
              TMapRakuTextPathLayer(Layer), RotatedBounds) then
              Continue;
          end
          else if Layer is TMapRakuArcLayer then
          begin
            ArcLayer := TMapRakuArcLayer(Layer);
            RotatedBounds := MapRakuEllipseBounds(ArcLayer.Bounds,
              ArcLayer.RotationDegrees);
            SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
              SelectionFrameOffset(ArcLayer.StrokeWidth, FZoom));
          end
          else if Layer is TVectArtRectangleLayer then
          begin
            RectangleLayer := TVectArtRectangleLayer(Layer);
            RotatedBounds := QuadBounds(RectangleCorners(
              RectangleLayer.Bounds, RectangleLayer.RotationDegrees));
          end
          else if Layer is TVectArtPathLayer then
          begin
            PathLayer := TVectArtPathLayer(Layer);
            RotatedBounds := MapRakuPathVerticesBounds(
              PathLayer.Vertices);
            if not PathLayer.Closed then
              SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
                SelectionFrameOffset(PathLayer.StrokeWidth, FZoom));
          end
          else if Layer is TMapRakuShapeLayer then
          begin
            ShapeLayer := TMapRakuShapeLayer(Layer);
            RotatedBounds := MapRakuShapeContoursBounds(
              ShapeLayer.Contours);
            SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
              SelectionFrameOffset(ShapeLayer.StrokeWidth, FZoom));
          end
          else
          begin
            ImageLayer := TVectArtImageLayer(Layer);
            RotatedBounds := TRectF.Create(ImageLayer.Points[0],
              ImageLayer.Points[0]);
            for RotationHandleIndex := 1 to High(ImageLayer.Points) do
            begin
              RotatedBounds.Left := Min(RotatedBounds.Left,
                ImageLayer.Points[RotationHandleIndex].X);
              RotatedBounds.Top := Min(RotatedBounds.Top,
                ImageLayer.Points[RotationHandleIndex].Y);
              RotatedBounds.Right := Max(RotatedBounds.Right,
                ImageLayer.Points[RotationHandleIndex].X);
              RotatedBounds.Bottom := Max(RotatedBounds.Bottom,
                ImageLayer.Points[RotationHandleIndex].Y);
            end;
          end;
          LayerRect := Rect(ToScreenX(RotatedBounds.Left),
            ToScreenY(RotatedBounds.Top), ToScreenX(RotatedBounds.Right),
            ToScreenY(RotatedBounds.Bottom));
          if LayerRect.Width = 0 then
            Inc(LayerRect.Right);
          if LayerRect.Height = 0 then
            Inc(LayerRect.Bottom);
          if FDocument.IsLayerSelected(I) then
          begin
            SelectionLocked := SelectionLocked or Layer.Locked;
            if SelectionLayerRect.IsEmpty then
              SelectionLayerRect := LayerRect
            else
              SelectionLayerRect := Rect(
                Min(SelectionLayerRect.Left, LayerRect.Left),
                Min(SelectionLayerRect.Top, LayerRect.Top),
                Max(SelectionLayerRect.Right, LayerRect.Right),
                Max(SelectionLayerRect.Bottom, LayerRect.Bottom));
          end;
        end;
      if (SelectionLayerRect.Width > 0) and
        (SelectionLayerRect.Height > 0) and
        not EditingTextPath then
      begin
        if (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is
            TMapRakuTextPathLayer) then
        begin
          SelectionGeometry := BuildSelectionGeometry(SelectionLayerRect,
            SelectionFrameOffsetPixels);
          SelectionGeometry.Handles[vshTop] := TRect.Empty;
          SelectionGeometry.Handles[vshRight] := TRect.Empty;
          SelectionGeometry.Handles[vshBottom] := TRect.Empty;
          SelectionGeometry.Handles[vshLeft] := TRect.Empty;
        end
        else if (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) then
        begin
          PathLayer := TVectArtPathLayer(
            FDocument[FDocument.SelectedIndex]);
          PathVertices := PathLayer.Vertices;
          if not PathLayer.Closed and
            MapRakuPathIsStraightLine(PathVertices) then
            SelectionGeometry := BuildLineSelectionGeometry(
              Point(ToScreenX(PathVertices[0].Position.X),
                ToScreenY(PathVertices[0].Position.Y)),
              Point(ToScreenX(PathVertices[1].Position.X),
                ToScreenY(PathVertices[1].Position.Y)))
          else
            SelectionGeometry := BuildPathSelectionGeometry(
              SelectionLayerRect, SelectionFrameOffsetPixels);
        end
        else if (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is
            TMapRakuShapeLayer) then
          SelectionGeometry := BuildPathSelectionGeometry(
            SelectionLayerRect, SelectionFrameOffsetPixels)
        else if (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) then
        begin
          ImageLayer := TVectArtImageLayer(
            FDocument[FDocument.SelectedIndex]);
          for I := 0 to High(ScreenQuad) do
            ScreenQuad[I] := Point(ToScreenX(ImageLayer.Points[I].X),
              ToScreenY(ImageLayer.Points[I].Y));
          SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
            SelectionFrameOffsetPixels);
        end
        else if not FInteraction.AxisAlignedSelection and
          (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is
            TMapRakuRectangleLineLayer) then
        begin
          RectangleLine := TMapRakuRectangleLineLayer(
            FDocument[FDocument.SelectedIndex]);
          LogicalQuad := RectangleCorners(RectangleLine.Bounds,
            RectangleLine.RotationDegrees);
          for I := 0 to High(ScreenQuad) do
            ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
              ToScreenY(LogicalQuad[I].Y));
          SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
            SelectionFrameOffsetPixels);
        end
        else if not FInteraction.AxisAlignedSelection and
          (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer) then
        begin
          ArcLayer := TMapRakuArcLayer(
            FDocument[FDocument.SelectedIndex]);
          LogicalQuad := RectangleCorners(ArcLayer.Bounds,
            ArcLayer.RotationDegrees);
          for I := 0 to High(ScreenQuad) do
            ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
              ToScreenY(LogicalQuad[I].Y));
          SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
            SelectionFrameOffsetPixels);
        end
        else if not FInteraction.AxisAlignedSelection and
          (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) then
        begin
          RectangleLayer := TVectArtRectangleLayer(
            FDocument[FDocument.SelectedIndex]);
          LogicalQuad := RectangleCorners(RectangleLayer.Bounds,
            RectangleLayer.RotationDegrees);
          for I := 0 to High(ScreenQuad) do
            ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
              ToScreenY(LogicalQuad[I].Y));
          SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
            SelectionFrameOffsetPixels);
        end
        else
          SelectionGeometry := BuildSelectionGeometry(SelectionLayerRect,
            SelectionFrameOffsetPixels);
        FInteraction.CurrentSelectionGeometry(SelectionGeometry);
        FTransformInteraction.Configure(FDocument, EditHistory, FEditorState, FCanvasBounds, FZoom);
        if FTransformInteraction.Active or FTransformInteraction.HasTransformedSelection then
          FTransformInteraction.Geometry(SelectionGeometry);
        if SelectionGeometry.DrawFrame then
          DrawOverlayPolyline(Direct2DCanvas,
            SelectionGeometry.FramePoints);
        if not SelectionLocked then
        begin
          for Handle := vshTopLeft to vshLeft do
            if not SelectionGeometry.Handles[Handle].IsEmpty then
              DrawOverlayHandleRect(Direct2DCanvas,
                SelectionGeometry.Handles[Handle]);
          if (FDocument.SelectionCount = 1) and
            ((FDocument[FDocument.SelectedIndex] is TMapRakuGroupLayer) or
             (FDocument[FDocument.SelectedIndex] is TMapRakuRectangleLineLayer) or
             (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
             (FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer) or
             (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) or
             (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) or
             (FDocument[FDocument.SelectedIndex] is
               TMapRakuShapeLayer)) and
            not FInteraction.AxisAlignedSelection then
          begin
            if FInteraction.RotationSnapped then
              DrawOverlayLine(Direct2DCanvas,
                SelectionGeometry.RotationStem[0],
                SelectionGeometry.RotationStem[1], COLOR_SNAP, psDot)
            else
              DrawOverlayLine(Direct2DCanvas,
                SelectionGeometry.RotationStem[0],
                SelectionGeometry.RotationStem[1]);
            DrawOverlayHandleEllipse(Direct2DCanvas,
              SelectionGeometry.PrimaryRotationHandle, clWhite,
              COLOR_ROTATION_MARK);
            BuildRotationMarkPoints(
              SelectionGeometry.PrimaryRotationHandle,
              RotationArcPoints, RotationArrowPoints);
            if FInteraction.CanResetSelectedRotation then
              RotationMarkColor := COLOR_ROTATION_MARK
            else
              RotationMarkColor := COLOR_ROTATION_BAKED_MARK;
            DrawOverlayPolyline(Direct2DCanvas, RotationArcPoints,
              RotationMarkColor, psSolid, 1, 1);
            DrawOverlayHandlePolygon(Direct2DCanvas,
              RotationArrowPoints, RotationMarkColor,
              RotationMarkColor, 1, 1);
          end;
          if FInteraction.SelectedTextPathCharacterGeometry(
            CharacterGeometry) then
          begin
            DrawOverlayPolyline(Direct2DCanvas,
              CharacterGeometry.FramePoints, TColor($0048A8F8));
            for Handle := vshTopLeft to vshLeft do
              if not CharacterGeometry.Handles[Handle].IsEmpty then
                DrawOverlayHandleRect(Direct2DCanvas,
                  CharacterGeometry.Handles[Handle], clWhite,
                  TColor($0048A8F8));
          end;
          CornerHandles := FInteraction.RoundedRectangleCornerHandles;
          for CornerHandle in CornerHandles do
          begin
            if CornerHandle.Selected then
              DrawOverlayHandleEllipse(Direct2DCanvas,
                CornerHandle.Bounds, TColor($0048A8F8), COLOR_SELECTION)
            else
              DrawOverlayHandleEllipse(Direct2DCanvas,
                CornerHandle.Bounds, clWhite, COLOR_SELECTION);
          end;
          if FInteraction.RoundedRectangleRadiusHandle(RadiusHandleRect) then
          begin
            RadiusHandlePoints := BuildDiamondPoints(RadiusHandleRect);
            DrawOverlayHandlePolygon(Direct2DCanvas,
              RadiusHandlePoints, TColor($0048A8F8), COLOR_SELECTION);
          end;
          if FInteraction.SelectedArcAngleHandles(ArcHandles) then
          begin
            DrawOverlayHandleEllipse(Direct2DCanvas,
              ArcHandles.StartHandle, TColor($0060C060),
              COLOR_SELECTION);
            DrawOverlayHandleEllipse(Direct2DCanvas,
              ArcHandles.EndHandle, TColor($0048A8F8),
              COLOR_SELECTION);
          end;
          if not FTextEditing and
            FInteraction.SelectedTextSpacingHandles(TextSpacingHandles) then
          begin
            TextIndividualHandles :=
              FInteraction.SelectedTextIndividualSpacingHandles;
            for TextIndividualHandle in TextIndividualHandles do
              DrawBidirectionalArrow(Direct2DCanvas,
                TextIndividualHandle.LineStart,
                TextIndividualHandle.LineEnd);
            DrawBidirectionalArrow(Direct2DCanvas,
              TextSpacingHandles.LetterLineStart,
              TextSpacingHandles.LetterLineEnd);
            if TextSpacingHandles.HasLineSpacing then
              DrawBidirectionalArrow(Direct2DCanvas,
                TextSpacingHandles.LineLineStart,
                TextSpacingHandles.LineLineEnd);
            if FInteraction.TextSpacingDragValue(TextSpacingIsLetter,
              TextSpacingRatio) then
            begin
              Direct2DCanvas.Brush.Style := bsClear;
              Direct2DCanvas.Font.Color := clWhite;
              if TextSpacingIsLetter then
                Direct2DCanvas.TextOut(
                  TextSpacingHandles.LetterHandle.Right + 4,
                  TextSpacingHandles.LetterHandle.Top - 2,
                  Format('字間 %.0f%%', [TextSpacingRatio * 100]))
              else
                Direct2DCanvas.TextOut(TextSpacingHandles.LineHandle.Right + 4,
                  TextSpacingHandles.LineHandle.Top - 2,
                  Format('行間 %.0f%%', [TextSpacingRatio * 100]));
              Direct2DCanvas.Brush.Style := bsSolid;
            end;
            if FInteraction.IndividualTextSpacingDragValue(
              TextIndividualGapIndex, TextSpacingRatio) and
              (TextIndividualGapIndex >= 0) and
              (TextIndividualGapIndex < Length(TextIndividualHandles)) then
            begin
              Direct2DCanvas.Brush.Style := bsClear;
              Direct2DCanvas.Font.Color := clWhite;
              Direct2DCanvas.TextOut(
                TextIndividualHandles[TextIndividualGapIndex].HitRect.Right + 4,
                TextIndividualHandles[TextIndividualGapIndex].HitRect.Top - 2,
                Format('個別字間 %.0f%%', [TextSpacingRatio * 100]));
              Direct2DCanvas.Brush.Style := bsSolid;
            end;
          end;
        end;
      end;
      if (FDocument.SelectionCount = 1) and
        (FDocument.SelectedIndex > 0) and
        (FDocument[FDocument.SelectedIndex] is
          TMapRakuTextPathLayer) then
      begin
        PathGuidePoints := FInteraction.SelectedPathPoints;
        if Length(PathGuidePoints) > 1 then
        begin
          DrawOverlayPolyline(Direct2DCanvas, PathGuidePoints,
            COLOR_SELECTION, psDot);
        end;
      end;
      PathVertexRects := FInteraction.SelectedPathVertexRects;
      for I := 0 to High(PathVertexRects) do
      begin
        DrawOverlayHandleRect(Direct2DCanvas, PathVertexRects[I],
          TColor($00F0C060), COLOR_SELECTION);
      end;
      PathWidthHandles := FInteraction.SelectedPathWidthHandles;
      for PathWidthHandle in PathWidthHandles do
      begin
        DrawOverlayLine(Direct2DCanvas, PathWidthHandle.LeftPoint,
          PathWidthHandle.RightPoint, COLOR_SELECTION, psDot);
        DrawOverlayHandleRect(Direct2DCanvas, PathWidthHandle.CenterRect,
          TColor($0060D0A0), COLOR_SELECTION);
        DrawOverlayHandleRect(Direct2DCanvas, PathWidthHandle.LeftRect,
          TColor($00E0A060), COLOR_SELECTION);
        DrawOverlayHandleRect(Direct2DCanvas, PathWidthHandle.RightRect,
          TColor($00E0A060), COLOR_SELECTION);
      end;
      ShapeVertexRects := FInteraction.SelectedShapeVertexRects;
      for I := 0 to High(ShapeVertexRects) do
      begin
        DrawOverlayHandleRect(Direct2DCanvas, ShapeVertexRects[I],
          TColor($00F0C060), COLOR_SELECTION);
      end;
      if FInteraction.SelectedShapeVertexRect(SelectedShapeVertexRect) then
      begin
        DrawOverlayHandleRect(Direct2DCanvas,
          SelectedShapeVertexRect);
      end;
      if FInteraction.SelectedShapeBezierHandles(BezierHandles) then
      begin
        SetLength(ShapeKindIconPoints, 2);
        ShapeKindIconPoints[0] := BezierHandles.IncomingPoint;
        ShapeKindIconPoints[1] := BezierHandles.OutgoingPoint;
        DrawOverlayPolyline(Direct2DCanvas, ShapeKindIconPoints,
          COLOR_SELECTION, psDot);
        DrawOverlayHandleRect(Direct2DCanvas,
          BezierHandles.IncomingRect);
        DrawOverlayHandleRect(Direct2DCanvas,
          BezierHandles.OutgoingRect);
      end;
      ShapeKindButtons := FInteraction.SelectedShapeVertexKindButtons;
      for I := 0 to High(ShapeKindButtons) do
      begin
        if ShapeKindButtons[I].Selected then
          DrawOverlayHandleRect(Direct2DCanvas,
            ShapeKindButtons[I].Bounds, TColor($00F0C060),
            COLOR_SELECTION)
        else
          DrawOverlayHandleRect(Direct2DCanvas,
            ShapeKindButtons[I].Bounds);
        ShapeKindIconPoints := BuildVertexKindIconPoints(
          ShapeKindButtons[I].Bounds, ShapeKindButtons[I].Kind);
        DrawOverlayPolyline(Direct2DCanvas, ShapeKindIconPoints);
      end;
      if FInteraction.RangeSelecting then
      begin
        RangeRect := FInteraction.RangeSelectionRect;
        DrawOverlayFrameRect(Direct2DCanvas, RangeRect);
      end;
      if FPlacementPreview.Bitmap.Width > 0 then
      begin
        DocumentBitmap := Direct2DCanvas.CreateBitmap(FPlacementPreview.Bitmap);
        ReferenceRect := D2D1RectF(FCanvasBounds.Left, FCanvasBounds.Top, FCanvasBounds.Right, FCanvasBounds.Bottom);
        Direct2DCanvas.RenderTarget.DrawBitmap(DocumentBitmap, @ReferenceRect);
        DocumentBitmap := nil;
      end;
      CreationRect := FShapeCreation.PreviewRect;
      if not CreationRect.IsEmpty then
      begin
        if FPlacementPreview.Bitmap.Width > 0 then
          DrawOverlayFrameRect(Direct2DCanvas, CreationRect, clBlack, psDot)
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool = vetArcShape) then
        begin
          DrawOverlayPie(Direct2DCanvas, CreationRect,
            Point(CreationRect.Right,
              (CreationRect.Top + CreationRect.Bottom) div 2),
            Point(CreationRect.Left,
              (CreationRect.Top + CreationRect.Bottom) div 2),
            COLOR_SELECTION);
        end
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool = vetArc) then
          Direct2DCanvas.Brush.Style := bsClear
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool = vetRectangleLine) then
        begin
          DrawOverlayFrameRect(Direct2DCanvas, CreationRect,
            FEditorState.LineStrokeColor, psSolid,
            Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
            Max(Round(FEditorState.LineStrokeWidth * FZoom), 1));
        end
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool in [vetEllipseLine, vetEllipse]) then
        begin
          if FEditorState.CurrentTool = vetEllipseLine then
            DrawOverlayEllipse(Direct2DCanvas, CreationRect,
              FEditorState.LineStrokeColor,
              Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
              Max(Round(FEditorState.LineStrokeWidth * FZoom), 1))
          else
            DrawOverlayEllipse(Direct2DCanvas, CreationRect);
        end
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool in [vetRoundedRectangleLine,
            vetRoundedRectangle]) then
        begin
          PreviewRadius := Round(Min(CreationRect.Width,
            CreationRect.Height) * 0.2);
          if FEditorState.CurrentTool = vetRoundedRectangleLine then
            DrawOverlayRoundRect(Direct2DCanvas, CreationRect,
              PreviewRadius, FEditorState.LineStrokeColor,
              Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
              Max(Round(FEditorState.LineStrokeWidth * FZoom), 1))
          else
            DrawOverlayRoundRect(Direct2DCanvas, CreationRect,
              PreviewRadius);
        end
        else
        begin
          DrawOverlayFrameRect(Direct2DCanvas, CreationRect);
        end;
      end;
      if (FPlacementPreview.Bitmap.Width = 0) and FShapeCreation.PreviewArc(ArcPreview) then
      begin
        DrawOverlayPolyline(Direct2DCanvas, ArcPreview,
          FEditorState.LineStrokeColor, psSolid,
          Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
          Max(Round(FEditorState.LineStrokeWidth * FZoom), 1));
      end;
      if FShapeCreation.PreviewLine(LineStart, LineEnd) then
        DrawStyledPreviewLine(Direct2DCanvas, LineStart, LineEnd,
          CreationPathPreviewColor(FEditorState,FDocument),
          FEditorState.LineStrokeWidth * FZoom,
          FEditorState.LineMifStrokeStyle, FEditorState.LineCap);
      if FShapeCreation.PreviewPath(PathPreview) then
      begin
        PathWidthScales := FShapeCreation.PreviewWidthScales;
        if Length(PathWidthScales) = Length(PathPreview) then
          DrawVariableWidthPreview(Direct2DCanvas, PathPreview,
            PathWidthScales, CreationPathPreviewColor(FEditorState,FDocument),
            FEditorState.LineStrokeWidth * FZoom)
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool in [vetFreehand, vetPath]) then
          DrawOverlayPolyline(Direct2DCanvas, PathPreview,
            CreationPathPreviewColor(FEditorState,FDocument), psSolid,
            Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
            Max(Round(FEditorState.LineStrokeWidth * FZoom), 1))
        else
          DrawOverlayPolyline(Direct2DCanvas, PathPreview);
      end;
      DrawSnapGuides(Direct2DCanvas);
      FFilterInteraction.Configure(FDocument, EditHistory, FEditorState,
        FCanvasBounds, FZoom);
      FFilterInteraction.Draw(Direct2DCanvas);
      FGradientInteraction.Configure(FDocument, EditHistory, FEditorState,
        FCanvasBounds, FZoom);
      FGradientInteraction.Draw(Direct2DCanvas);
      FTextureInteraction.Configure(FDocument, EditHistory, FEditorState, FCanvasBounds, FZoom);
      FTextureInteraction.Draw(Direct2DCanvas);
      FMapPathEditor.Configure(FDocument,FEditorState,EditHistory,FCanvasBounds,FZoom);
      FMapPathEditor.Draw(Direct2DCanvas);
      DrawTextEditingOverlayDirect2D(Direct2DCanvas);
      if StrokeWidthCursorVisible then
        DrawStrokeWidthCursor(Direct2DCanvas, FPointerPosition,
          StrokeWidthCursorDiameter,
          Max(MulDiv(4, CurrentPPI, 96), 2));
    finally
      Direct2DCanvas.EndDraw;
    end;
  finally
    Direct2DCanvas.Free;
  end;
end;

procedure TVectArtCanvasControl.PaintGDI;
var
  ArcHandles: TMapRakuArcAngleHandles;
  TextSpacingHandles: TMapRakuTextSpacingHandles;
  TextIndividualGapIndex: Integer;
  TextIndividualHandle: TMapRakuTextIndividualSpacingHandle;
  TextIndividualHandles: TArray<TMapRakuTextIndividualSpacingHandle>;
  TextSpacingIsLetter: Boolean;
  TextSpacingRatio: Single;
  ArcLayer: TMapRakuArcLayer;
  ArcPreview: TArray<TPoint>;
  BezierHandles: TMapRakuBezierHandles;
  CanvasLayer: TVectArtCanvasLayer;
  CreationRect: TRect;
  CellRect: TRect;
  Column: Integer;
  ColumnEnd: Integer;
  ColumnStart: Integer;
  CornerHandle: TMapRakuRoundedCornerHandle;
  CornerHandles: TArray<TMapRakuRoundedCornerHandle>;
  Handle: TVectArtSelectionHandle;
  RotationHandleIndex: Integer;
  RotationArcPoints: TArray<TPoint>;
  RotationArrowPoints: TArray<TPoint>;
  RotationMarkColor: TColor;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Layer: TVectArtLayer;
  RectangleLine: TMapRakuRectangleLineLayer;
  LayerRect: TRect;
  LineEnd: TPoint;
  LineStart: TPoint;
  PathGuidePoints: TArray<TPoint>;
  PathPreview: TArray<TPoint>;
  PathWidthHandle: TMapRakuPathWidthHandle;
  PathWidthHandles: TArray<TMapRakuPathWidthHandle>;
  PathWidthScales: TArray<Single>;
  PathVertexRects: TArray<TRect>;
  PreviewRadius: Integer;
  SelectedShapeVertexRect: TRect;
  ShapeKindButtons: TArray<TMapRakuVertexKindButton>;
  ShapeKindIconPoints: TArray<TPoint>;
  ShapeVertexRects: TArray<TRect>;
  LogicalQuad: TVectArtQuad;
  PathLayer: TVectArtPathLayer;
  PathVertices: TArray<TMapRakuVertex>;
  RectangleLayer: TVectArtRectangleLayer;
  ShapeLayer: TMapRakuShapeLayer;
  RotatedBounds: TRectF;
  RangeRect: TRect;
  RadiusHandlePoints: TArray<TPoint>;
  RadiusHandleRect: TRect;
  Row: Integer;
  RowEnd: Integer;
  RowStart: Integer;
  CharacterGeometry: TVectArtSelectionGeometry;
  SelectionGeometry: TVectArtSelectionGeometry;
  SelectionFrameOffsetPixels: Integer;
  SelectionLayerRect: TRect;
  SelectionLocked: Boolean;
  ScreenQuad: TVectArtScreenQuad;
  ShadowBounds: TRect;
  VisibleCanvasBounds: TRect;
begin
  SelectionLayerRect := TRect.Empty;
  SelectionFrameOffsetPixels := SelectionFrameOffset(0, FZoom);
  SelectionLocked := False;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := COLOR_EDITOR_SURROUND;
  Canvas.FillRect(ClientRect);
  ShadowBounds := FCanvasBounds;
  OffsetRect(ShadowBounds, CANVAS_SHADOW_OFFSET, CANVAS_SHADOW_OFFSET);
  Canvas.Brush.Color := COLOR_CANVAS_SHADOW;
  Canvas.FillRect(ShadowBounds);

  CanvasLayer := nil;
  if FDocument <> nil then
    CanvasLayer := FDocument.CanvasLayer;
  if HasReferenceBackground then
  begin
    Canvas.StretchDraw(FCanvasBounds, FReferenceBackground);
  end
  else if (CanvasLayer <> nil) and CanvasLayer.Visible and
    not CanvasLayer.Transparent then
  begin
    Canvas.Brush.Color := CanvasLayer.BackgroundColor;
    Canvas.FillRect(FCanvasBounds);
  end
  else
  begin
    if IntersectRect(VisibleCanvasBounds, FCanvasBounds, ClientRect) then
    begin
      ColumnStart := (VisibleCanvasBounds.Left - FCanvasBounds.Left) div
        TRANSPARENCY_CELL;
      ColumnEnd := (VisibleCanvasBounds.Right - 1 - FCanvasBounds.Left) div
        TRANSPARENCY_CELL;
      RowStart := (VisibleCanvasBounds.Top - FCanvasBounds.Top) div
        TRANSPARENCY_CELL;
      RowEnd := (VisibleCanvasBounds.Bottom - 1 - FCanvasBounds.Top) div
        TRANSPARENCY_CELL;
      for Row := RowStart to RowEnd do
        for Column := ColumnStart to ColumnEnd do
        begin
          CellRect := Rect(
            FCanvasBounds.Left + Column * TRANSPARENCY_CELL,
            FCanvasBounds.Top + Row * TRANSPARENCY_CELL,
            Min(FCanvasBounds.Left + (Column + 1) * TRANSPARENCY_CELL,
              FCanvasBounds.Right),
            Min(FCanvasBounds.Top + (Row + 1) * TRANSPARENCY_CELL,
              FCanvasBounds.Bottom));
          if Odd(Row + Column) then
            Canvas.Brush.Color := COLOR_TRANSPARENT_A
          else
            Canvas.Brush.Color := COLOR_TRANSPARENT_B;
          Canvas.FillRect(CellRect);
        end;
    end;
  end;

  DrawPremultipliedBitmap(Canvas, FCanvasBounds, FRenderCache.Bitmap);
  DrawCanvasCropMarks(Canvas, FCanvasBounds);
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
    TryGetMapRakuLayerBounds(FEditorState.OpenGroup,
      RotatedBounds) then
  begin
    LayerRect := Rect(ToScreenX(RotatedBounds.Left),
      ToScreenY(RotatedBounds.Top), ToScreenX(RotatedBounds.Right),
      ToScreenY(RotatedBounds.Bottom));
    InflateRect(LayerRect, 5, 5);
    DrawOverlayFrameRect(Canvas, LayerRect, COLOR_OPEN_GROUP, psDash);
  end;
  if (FEditorState <> nil) and (FEditorState.OpenGroupChild <> nil) and
    not EditingTextPath and
    TryGetOpenGroupSelectionBounds(FEditorState, RotatedBounds) then
  begin
    LayerRect := Rect(ToScreenX(RotatedBounds.Left),
      ToScreenY(RotatedBounds.Top), ToScreenX(RotatedBounds.Right),
      ToScreenY(RotatedBounds.Bottom));
    SelectionGeometry := BuildSelectionGeometry(LayerRect,
      SelectionFrameOffset(0, FZoom));
    FTransformInteraction.Configure(FDocument, EditHistory, FEditorState, FCanvasBounds, FZoom);
    if FTransformInteraction.Active or FTransformInteraction.HasTransformedSelection then
      FTransformInteraction.Geometry(SelectionGeometry);
    DrawOverlayPolyline(Canvas, SelectionGeometry.FramePoints);
    if OpenGroupSelectionEditable(FEditorState) then
    begin
      for Handle := vshTopLeft to vshLeft do
      begin
        DrawOverlayHandleRect(Canvas,
          SelectionGeometry.Handles[Handle]);
      end;
      DrawOverlayLine(Canvas, SelectionGeometry.RotationStem[0],
        SelectionGeometry.RotationStem[1]);
      DrawOverlayHandleEllipse(Canvas,
        SelectionGeometry.PrimaryRotationHandle, clWhite,
        COLOR_ROTATION_MARK);
    end;
  end;

  if FDocument <> nil then
    for I := 1 to FDocument.LayerCount - 1 do
    begin
      Layer := FDocument[I];
      if not Layer.Visible or
        not ((Layer is TMapRakuGroupLayer) or
          (Layer is TMapRakuRectangleLineLayer) or
          (Layer is TVectArtRectangleLayer) or
          (Layer is TMapRakuArcLayer) or
          (Layer is TVectArtPathLayer) or
          (Layer is TMapRakuShapeLayer) or
          (Layer is TVectArtImageLayer)) then
        Continue;
      if Layer is TMapRakuGroupLayer then
      begin
        if not TryGetMapRakuLayerBounds(Layer, RotatedBounds) then
          Continue;
      end
      else if Layer is TMapRakuRectangleLineLayer then
      begin
        RectangleLine := TMapRakuRectangleLineLayer(Layer);
        RotatedBounds := QuadBounds(RectangleCorners(RectangleLine.Bounds,
          RectangleLine.RotationDegrees));
        SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
          SelectionFrameOffset(RectangleLine.StrokeWidth, FZoom));
      end
      else if Layer is TMapRakuTextPathLayer then
      begin
        if not TryGetMapRakuTextPathBounds(
          TMapRakuTextPathLayer(Layer), RotatedBounds) then
          Continue;
      end
      else if Layer is TMapRakuArcLayer then
      begin
        ArcLayer := TMapRakuArcLayer(Layer);
        RotatedBounds := MapRakuEllipseBounds(ArcLayer.Bounds,
          ArcLayer.RotationDegrees);
        SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
          SelectionFrameOffset(ArcLayer.StrokeWidth, FZoom));
      end
      else if Layer is TVectArtRectangleLayer then
      begin
        RectangleLayer := TVectArtRectangleLayer(Layer);
        RotatedBounds := QuadBounds(RectangleCorners(RectangleLayer.Bounds,
          RectangleLayer.RotationDegrees));
      end
      else if Layer is TVectArtPathLayer then
      begin
        PathLayer := TVectArtPathLayer(Layer);
        RotatedBounds := MapRakuPathVerticesBounds(PathLayer.Vertices);
        if not PathLayer.Closed then
          SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
            SelectionFrameOffset(PathLayer.StrokeWidth, FZoom));
      end
      else if Layer is TMapRakuShapeLayer then
      begin
        ShapeLayer := TMapRakuShapeLayer(Layer);
        RotatedBounds := MapRakuShapeContoursBounds(
          ShapeLayer.Contours);
        SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
          SelectionFrameOffset(ShapeLayer.StrokeWidth, FZoom));
      end
      else
      begin
        ImageLayer := TVectArtImageLayer(Layer);
        RotatedBounds := TRectF.Create(ImageLayer.Points[0],
          ImageLayer.Points[0]);
        for RotationHandleIndex := 1 to High(ImageLayer.Points) do
        begin
          RotatedBounds.Left := Min(RotatedBounds.Left,
            ImageLayer.Points[RotationHandleIndex].X);
          RotatedBounds.Top := Min(RotatedBounds.Top,
            ImageLayer.Points[RotationHandleIndex].Y);
          RotatedBounds.Right := Max(RotatedBounds.Right,
            ImageLayer.Points[RotationHandleIndex].X);
          RotatedBounds.Bottom := Max(RotatedBounds.Bottom,
            ImageLayer.Points[RotationHandleIndex].Y);
        end;
      end;
      LayerRect := Rect(ToScreenX(RotatedBounds.Left),
        ToScreenY(RotatedBounds.Top), ToScreenX(RotatedBounds.Right),
        ToScreenY(RotatedBounds.Bottom));
      if LayerRect.Width = 0 then
        Inc(LayerRect.Right);
      if LayerRect.Height = 0 then
        Inc(LayerRect.Bottom);
      if FDocument.IsLayerSelected(I) then
      begin
        SelectionLocked := SelectionLocked or Layer.Locked;
        if SelectionLayerRect.IsEmpty then
          SelectionLayerRect := LayerRect
        else
          SelectionLayerRect := Rect(
            Min(SelectionLayerRect.Left, LayerRect.Left),
            Min(SelectionLayerRect.Top, LayerRect.Top),
            Max(SelectionLayerRect.Right, LayerRect.Right),
            Max(SelectionLayerRect.Bottom, LayerRect.Bottom));
      end;
    end;
  if (SelectionLayerRect.Width > 0) and (SelectionLayerRect.Height > 0) and
    not EditingTextPath then
  begin
    if (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is
        TMapRakuTextPathLayer) then
    begin
      SelectionGeometry := BuildSelectionGeometry(SelectionLayerRect,
        SelectionFrameOffsetPixels);
      SelectionGeometry.Handles[vshTop] := TRect.Empty;
      SelectionGeometry.Handles[vshRight] := TRect.Empty;
      SelectionGeometry.Handles[vshBottom] := TRect.Empty;
      SelectionGeometry.Handles[vshLeft] := TRect.Empty;
    end
    else if (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) then
    begin
      PathLayer := TVectArtPathLayer(FDocument[FDocument.SelectedIndex]);
      PathVertices := PathLayer.Vertices;
      if not PathLayer.Closed and
        MapRakuPathIsStraightLine(PathVertices) then
        SelectionGeometry := BuildLineSelectionGeometry(
          Point(ToScreenX(PathVertices[0].Position.X),
            ToScreenY(PathVertices[0].Position.Y)),
          Point(ToScreenX(PathVertices[1].Position.X),
            ToScreenY(PathVertices[1].Position.Y)))
      else
        SelectionGeometry := BuildPathSelectionGeometry(SelectionLayerRect,
          SelectionFrameOffsetPixels);
    end
    else if (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TMapRakuShapeLayer) then
      SelectionGeometry := BuildPathSelectionGeometry(SelectionLayerRect,
        SelectionFrameOffsetPixels)
    else if (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) then
    begin
      ImageLayer := TVectArtImageLayer(FDocument[FDocument.SelectedIndex]);
      for I := 0 to High(ScreenQuad) do
        ScreenQuad[I] := Point(ToScreenX(ImageLayer.Points[I].X),
          ToScreenY(ImageLayer.Points[I].Y));
      SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
        SelectionFrameOffsetPixels);
    end
    else if not FInteraction.AxisAlignedSelection and
      (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is
        TMapRakuRectangleLineLayer) then
    begin
      RectangleLine := TMapRakuRectangleLineLayer(
        FDocument[FDocument.SelectedIndex]);
      LogicalQuad := RectangleCorners(RectangleLine.Bounds,
        RectangleLine.RotationDegrees);
      for I := 0 to High(ScreenQuad) do
        ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
          ToScreenY(LogicalQuad[I].Y));
      SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
        SelectionFrameOffsetPixels);
    end
    else if not FInteraction.AxisAlignedSelection and
      (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer) then
    begin
      ArcLayer := TMapRakuArcLayer(FDocument[FDocument.SelectedIndex]);
      LogicalQuad := RectangleCorners(ArcLayer.Bounds,
        ArcLayer.RotationDegrees);
      for I := 0 to High(ScreenQuad) do
        ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
          ToScreenY(LogicalQuad[I].Y));
      SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
        SelectionFrameOffsetPixels);
    end
    else if not FInteraction.AxisAlignedSelection and
      (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) then
    begin
      RectangleLayer := TVectArtRectangleLayer(
        FDocument[FDocument.SelectedIndex]);
      LogicalQuad := RectangleCorners(RectangleLayer.Bounds,
        RectangleLayer.RotationDegrees);
      for I := 0 to High(ScreenQuad) do
        ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
          ToScreenY(LogicalQuad[I].Y));
      SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
        SelectionFrameOffsetPixels);
    end
    else
      SelectionGeometry := BuildSelectionGeometry(SelectionLayerRect,
        SelectionFrameOffsetPixels);
    FInteraction.CurrentSelectionGeometry(SelectionGeometry);
    FTransformInteraction.Configure(FDocument, EditHistory, FEditorState, FCanvasBounds, FZoom);
    if FTransformInteraction.Active or FTransformInteraction.HasTransformedSelection then
      FTransformInteraction.Geometry(SelectionGeometry);
    if SelectionGeometry.DrawFrame then
      DrawOverlayPolyline(Canvas, SelectionGeometry.FramePoints);
    if not SelectionLocked then
    begin
      for Handle := vshTopLeft to vshLeft do
        if not SelectionGeometry.Handles[Handle].IsEmpty then
          DrawOverlayHandleRect(Canvas,
            SelectionGeometry.Handles[Handle]);
      if (FDocument.SelectionCount = 1) and
        ((FDocument[FDocument.SelectedIndex] is TMapRakuGroupLayer) or
         (FDocument[FDocument.SelectedIndex] is TMapRakuRectangleLineLayer) or
         (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
         (FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer) or
         (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) or
         (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) or
         (FDocument[FDocument.SelectedIndex] is
           TMapRakuShapeLayer)) and
        not FInteraction.AxisAlignedSelection then
      begin
        if FInteraction.RotationSnapped then
          DrawOverlayLine(Canvas, SelectionGeometry.RotationStem[0],
            SelectionGeometry.RotationStem[1], COLOR_SNAP, psDot)
        else
          DrawOverlayLine(Canvas, SelectionGeometry.RotationStem[0],
            SelectionGeometry.RotationStem[1]);
        DrawOverlayHandleEllipse(Canvas,
          SelectionGeometry.PrimaryRotationHandle, clWhite,
          COLOR_ROTATION_MARK);
        BuildRotationMarkPoints(SelectionGeometry.PrimaryRotationHandle,
          RotationArcPoints, RotationArrowPoints);
        if FInteraction.CanResetSelectedRotation then
          RotationMarkColor := COLOR_ROTATION_MARK
        else
          RotationMarkColor := COLOR_ROTATION_BAKED_MARK;
        DrawOverlayPolyline(Canvas, RotationArcPoints,
          RotationMarkColor, psSolid, 1, 1);
        DrawOverlayHandlePolygon(Canvas, RotationArrowPoints,
          RotationMarkColor, RotationMarkColor, 1, 1);
      end;
      if FInteraction.SelectedTextPathCharacterGeometry(
        CharacterGeometry) then
      begin
        DrawOverlayPolyline(Canvas, CharacterGeometry.FramePoints,
          TColor($0048A8F8));
        for Handle := vshTopLeft to vshLeft do
          if not CharacterGeometry.Handles[Handle].IsEmpty then
            DrawOverlayHandleRect(Canvas,
              CharacterGeometry.Handles[Handle], clWhite,
              TColor($0048A8F8));
      end;
      CornerHandles := FInteraction.RoundedRectangleCornerHandles;
      for CornerHandle in CornerHandles do
      begin
        if CornerHandle.Selected then
          DrawOverlayHandleEllipse(Canvas, CornerHandle.Bounds,
            TColor($0048A8F8), COLOR_SELECTION)
        else
          DrawOverlayHandleEllipse(Canvas, CornerHandle.Bounds,
            clWhite, COLOR_SELECTION);
      end;
      if FInteraction.RoundedRectangleRadiusHandle(RadiusHandleRect) then
      begin
        RadiusHandlePoints := BuildDiamondPoints(RadiusHandleRect);
        DrawOverlayHandlePolygon(Canvas, RadiusHandlePoints,
          TColor($0048A8F8), COLOR_SELECTION);
      end;
      if FInteraction.SelectedArcAngleHandles(ArcHandles) then
      begin
        DrawOverlayHandleEllipse(Canvas, ArcHandles.StartHandle,
          TColor($0060C060), COLOR_SELECTION);
        DrawOverlayHandleEllipse(Canvas, ArcHandles.EndHandle,
          TColor($0048A8F8), COLOR_SELECTION);
      end;
      if not FTextEditing and
        FInteraction.SelectedTextSpacingHandles(TextSpacingHandles) then
      begin
        TextIndividualHandles :=
          FInteraction.SelectedTextIndividualSpacingHandles;
        for TextIndividualHandle in TextIndividualHandles do
          DrawBidirectionalArrow(Canvas, TextIndividualHandle.LineStart,
            TextIndividualHandle.LineEnd);
        DrawBidirectionalArrow(Canvas, TextSpacingHandles.LetterLineStart,
          TextSpacingHandles.LetterLineEnd);
        if TextSpacingHandles.HasLineSpacing then
          DrawBidirectionalArrow(Canvas, TextSpacingHandles.LineLineStart,
            TextSpacingHandles.LineLineEnd);
        if FInteraction.TextSpacingDragValue(TextSpacingIsLetter,
          TextSpacingRatio) then
        begin
          Canvas.Brush.Style := bsClear;
          Canvas.Font.Color := clWhite;
          if TextSpacingIsLetter then
            Canvas.TextOut(TextSpacingHandles.LetterHandle.Right + 4,
              TextSpacingHandles.LetterHandle.Top - 2,
              Format('字間 %.0f%%', [TextSpacingRatio * 100]))
          else
            Canvas.TextOut(TextSpacingHandles.LineHandle.Right + 4,
              TextSpacingHandles.LineHandle.Top - 2,
              Format('行間 %.0f%%', [TextSpacingRatio * 100]));
          Canvas.Brush.Style := bsSolid;
        end;
        if FInteraction.IndividualTextSpacingDragValue(
          TextIndividualGapIndex, TextSpacingRatio) and
          (TextIndividualGapIndex >= 0) and
          (TextIndividualGapIndex < Length(TextIndividualHandles)) then
        begin
          Canvas.Brush.Style := bsClear;
          Canvas.Font.Color := clWhite;
          Canvas.TextOut(
            TextIndividualHandles[TextIndividualGapIndex].HitRect.Right + 4,
            TextIndividualHandles[TextIndividualGapIndex].HitRect.Top - 2,
            Format('個別字間 %.0f%%', [TextSpacingRatio * 100]));
          Canvas.Brush.Style := bsSolid;
        end;
      end;
    end;
  end;
  if (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is
      TMapRakuTextPathLayer) then
  begin
    PathGuidePoints := FInteraction.SelectedPathPoints;
    if Length(PathGuidePoints) > 1 then
    begin
      DrawOverlayPolyline(Canvas, PathGuidePoints,
        COLOR_SELECTION, psDot);
    end;
  end;
  PathVertexRects := FInteraction.SelectedPathVertexRects;
  for I := 0 to High(PathVertexRects) do
  begin
    DrawOverlayHandleRect(Canvas, PathVertexRects[I],
      TColor($00F0C060), COLOR_SELECTION);
  end;
  PathWidthHandles := FInteraction.SelectedPathWidthHandles;
  for PathWidthHandle in PathWidthHandles do
  begin
    DrawOverlayLine(Canvas, PathWidthHandle.LeftPoint,
      PathWidthHandle.RightPoint, COLOR_SELECTION, psDot);
    DrawOverlayHandleRect(Canvas, PathWidthHandle.CenterRect,
      TColor($0060D0A0), COLOR_SELECTION);
    DrawOverlayHandleRect(Canvas, PathWidthHandle.LeftRect,
      TColor($00E0A060), COLOR_SELECTION);
    DrawOverlayHandleRect(Canvas, PathWidthHandle.RightRect,
      TColor($00E0A060), COLOR_SELECTION);
  end;
  ShapeVertexRects := FInteraction.SelectedShapeVertexRects;
  for I := 0 to High(ShapeVertexRects) do
  begin
    DrawOverlayHandleRect(Canvas, ShapeVertexRects[I],
      TColor($00F0C060), COLOR_SELECTION);
  end;
  if FInteraction.SelectedShapeVertexRect(SelectedShapeVertexRect) then
  begin
    DrawOverlayHandleRect(Canvas, SelectedShapeVertexRect);
  end;
  if FInteraction.SelectedShapeBezierHandles(BezierHandles) then
  begin
    SetLength(ShapeKindIconPoints, 2);
    ShapeKindIconPoints[0] := BezierHandles.IncomingPoint;
    ShapeKindIconPoints[1] := BezierHandles.OutgoingPoint;
    DrawOverlayPolyline(Canvas, ShapeKindIconPoints,
      COLOR_SELECTION, psDot);
    DrawOverlayHandleRect(Canvas, BezierHandles.IncomingRect);
    DrawOverlayHandleRect(Canvas, BezierHandles.OutgoingRect);
  end;
  ShapeKindButtons := FInteraction.SelectedShapeVertexKindButtons;
  for I := 0 to High(ShapeKindButtons) do
  begin
    if ShapeKindButtons[I].Selected then
      DrawOverlayHandleRect(Canvas, ShapeKindButtons[I].Bounds,
        TColor($00F0C060), COLOR_SELECTION)
    else
      DrawOverlayHandleRect(Canvas, ShapeKindButtons[I].Bounds);
    ShapeKindIconPoints := BuildVertexKindIconPoints(
      ShapeKindButtons[I].Bounds, ShapeKindButtons[I].Kind);
    DrawOverlayPolyline(Canvas, ShapeKindIconPoints);
  end;
  if FInteraction.RangeSelecting then
  begin
    RangeRect := FInteraction.RangeSelectionRect;
    DrawOverlayFrameRect(Canvas, RangeRect);
  end;
  DrawPremultipliedBitmap(Canvas, FCanvasBounds, FPlacementPreview.Bitmap);
  CreationRect := FShapeCreation.PreviewRect;
  if not CreationRect.IsEmpty then
  begin
    if FPlacementPreview.Bitmap.Width > 0 then
      DrawOverlayFrameRect(Canvas, CreationRect, clBlack, psDot)
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetArcShape) then
    begin
      DrawOverlayPie(Canvas, CreationRect,
        Point(CreationRect.Right,
          (CreationRect.Top + CreationRect.Bottom) div 2),
        Point(CreationRect.Left,
          (CreationRect.Top + CreationRect.Bottom) div 2),
        COLOR_SELECTION);
    end
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetArc) then
      Canvas.Brush.Style := bsClear
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetRectangleLine) then
    begin
      DrawOverlayFrameRect(Canvas, CreationRect,
        FEditorState.LineStrokeColor, psSolid,
        Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
        Max(Round(FEditorState.LineStrokeWidth * FZoom), 1));
    end
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetEllipseLine, vetEllipse]) then
    begin
      if FEditorState.CurrentTool = vetEllipseLine then
        DrawOverlayEllipse(Canvas, CreationRect,
          FEditorState.LineStrokeColor,
          Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
          Max(Round(FEditorState.LineStrokeWidth * FZoom), 1))
      else
        DrawOverlayEllipse(Canvas, CreationRect);
    end
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetRoundedRectangleLine,
        vetRoundedRectangle]) then
    begin
      PreviewRadius := Round(Min(CreationRect.Width,
        CreationRect.Height) * 0.2);
      if FEditorState.CurrentTool = vetRoundedRectangleLine then
        DrawOverlayRoundRect(Canvas, CreationRect, PreviewRadius,
          FEditorState.LineStrokeColor,
          Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
          Max(Round(FEditorState.LineStrokeWidth * FZoom), 1))
      else
        DrawOverlayRoundRect(Canvas, CreationRect, PreviewRadius);
    end
    else
    begin
      DrawOverlayFrameRect(Canvas, CreationRect);
    end;
  end;
  if (FPlacementPreview.Bitmap.Width = 0) and FShapeCreation.PreviewArc(ArcPreview) then
  begin
    DrawOverlayPolyline(Canvas, ArcPreview,
      FEditorState.LineStrokeColor, psSolid,
      Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
      Max(Round(FEditorState.LineStrokeWidth * FZoom), 1));
  end;
  if FShapeCreation.PreviewLine(LineStart, LineEnd) then
    DrawStyledPreviewLine(Canvas, LineStart, LineEnd,
      CreationPathPreviewColor(FEditorState,FDocument),
      FEditorState.LineStrokeWidth * FZoom,
      FEditorState.LineMifStrokeStyle, FEditorState.LineCap);
  if FShapeCreation.PreviewPath(PathPreview) then
  begin
    PathWidthScales := FShapeCreation.PreviewWidthScales;
    if Length(PathWidthScales) = Length(PathPreview) then
      DrawVariableWidthPreview(Canvas, PathPreview, PathWidthScales,
        CreationPathPreviewColor(FEditorState,FDocument),
        FEditorState.LineStrokeWidth * FZoom)
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetFreehand, vetPath]) then
      DrawOverlayPolyline(Canvas, PathPreview,
        CreationPathPreviewColor(FEditorState,FDocument), psSolid,
        Max(Round(FEditorState.LineStrokeWidth * FZoom), 1) + 2,
        Max(Round(FEditorState.LineStrokeWidth * FZoom), 1))
    else
      DrawOverlayPolyline(Canvas, PathPreview);
  end;
  DrawSnapGuides(Canvas);
  FFilterInteraction.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  FFilterInteraction.Draw(Canvas);
  FGradientInteraction.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  FGradientInteraction.Draw(Canvas);
  FTextureInteraction.Configure(FDocument, EditHistory, FEditorState, FCanvasBounds, FZoom);
  FTextureInteraction.Draw(Canvas);
  FMapPathEditor.Configure(FDocument,FEditorState,EditHistory,FCanvasBounds,FZoom);
  FMapPathEditor.Draw(Canvas);
  DrawTextEditingOverlay(Canvas);
  if StrokeWidthCursorVisible then
    DrawStrokeWidthCursor(Canvas, FPointerPosition,
      StrokeWidthCursorDiameter,
      Max(MulDiv(4, CurrentPPI, 96), 2));
end;

procedure TVectArtCanvasControl.SetReferenceBackgroundRgba(
  const Pixels: TBytes; Width, Height: Integer);
var
  Destination: PByte;
  Source: PByte;
  X: Integer;
  Y: Integer;
  Token: TGUID;
begin
  CreateGUID(Token);
  FReferenceBackgroundToken := GUIDToString(Token);
  FReferenceBackground.SetSize(0, 0);
  if (Width <= 0) or (Height <= 0) or
    (Length(Pixels) <> NativeInt(Width) * Height * 4) then
  begin
    Invalidate;
    Exit;
  end;
  FReferenceBackground.PixelFormat := pf32bit;
  FReferenceBackground.SetSize(Width, Height);
  FReferenceBackground.AlphaFormat := afIgnored;
  Source := @Pixels[0];
  for Y := 0 to Height - 1 do
  begin
    Destination := FReferenceBackground.ScanLine[Y];
    for X := 0 to Width - 1 do
    begin
      Destination[0] := Source[2];
      Destination[1] := Source[1];
      Destination[2] := Source[0];
      Destination[3] := 255;
      Inc(Destination, 4);
      Inc(Source, 4);
    end;
  end;
  Invalidate;
end;

procedure TVectArtCanvasControl.CopyReferenceBackground(Target: TBitmap);
begin
  Target.Assign(FReferenceBackground);
end;

procedure TVectArtCanvasControl.Resize;
begin
  inherited Resize;
  CalculateCanvasBounds;
  Invalidate;
end;

procedure TVectArtCanvasControl.SetDocument(const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  if FTextEditing then
    FinishTextEdit(True, False);
  EndMovePreview;
  FZoomRenderTimer.Enabled := False;
  FZoomPreviewActive := False;
  FDocument := Value;
  FRenderCache.Reset;
  FPanOffset := TPointF.Zero;
  FViewZoom := 1.0;
  CalculateCanvasBounds;
  Invalidate;
end;

procedure TVectArtCanvasControl.SetEditHistory(
  const Value: TVectArtEditHistory);
begin
  FInteraction.EditHistory := Value;
end;

procedure TVectArtCanvasControl.SetEditorState(
  const Value: TVectArtEditorState);
begin
  FEditorState := Value;
  Invalidate;
end;

procedure TVectArtCanvasControl.WndProc(var Message: TMessage);
begin
  if (Message.Msg = WM_POINTERDOWN) or
    (Message.Msg = WM_POINTERUPDATE) or (Message.Msg = WM_POINTERUP) then
    UpdatePenPressure(Message.Msg, Message.WParam);
  inherited WndProc(Message);
end;

end.
