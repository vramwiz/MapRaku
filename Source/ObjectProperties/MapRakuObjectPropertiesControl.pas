// 選択オブジェクトの位置、サイズ、描画属性を表示・編集するダークテーマ用Controlを提供する。
// 共通項目と線・パスの描画属性を扱う。
unit MapRakuObjectPropertiesControl;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.StdCtrls,
  MapRakuDocument, MapRakuEditCommands,
  MapRakuEditHistory, MapRakuEditorState,
  MapRakuLineStyleControls, MapRakuStrokeStyleCombo;

type
  TVectArtObjectPropertiesControl = class(TCustomControl)
  private
    FArcEndAngleEdit: TEdit;
    FArcStartAngleEdit: TEdit;
    FColorEdit: TEdit;
    FColorControlsVisible: Boolean;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    FGeometryControlsVisible: Boolean;
    FHeightEdit: TEdit;
    FOpacityEdit: TEdit;
    FOpacityControlsVisible: Boolean;
    FStrokeColorEdit: TEdit;
    FStrokePropertyControlsVisible: Boolean;
    FMifStrokeStyleCombo: TVectArtMifStrokeStyleCombo;
    FPathLineCapButtons: array[TVectArtLineCap] of TVectArtLineCapButton;
    FStrokeWidthEdit: TEdit;
    FUpdating: Boolean;
    FWidthEdit: TEdit;
    FXEdit: TEdit;
    FYEdit: TEdit;
    procedure ApplyColor;
    procedure ApplyArcAngles;
    procedure ApplyGeometry;
    procedure ApplyOpacity;
    procedure ApplyStrokeColor;
    procedure ApplyMifStrokeStyle(Sender: TObject);
    procedure ApplyPathLineCap(Sender: TObject);
    procedure ApplyStrokeWidth;
    procedure ClearEditValue(Edit: TEdit);
    procedure EditExit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function GetSelectedFillIndices: TArray<Integer>;
    function GetSelectedOpacityIndices: TArray<Integer>;
    function GetSelectedRectangleIndices: TArray<Integer>;
    function GetSelectedStrokeIndices: TArray<Integer>;
    function SelectedLayersHaveLock: Boolean;
    function NewDarkEdit: TEdit;
    function NewDarkCombo: TVectArtMifStrokeStyleCombo;
    function SelectedBounds(out Bounds: TRectF): Boolean;
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetColorControlsVisible(Value: Boolean);
    procedure SetGeometryControlsVisible(Value: Boolean);
    procedure SetOpacityControlsVisible(Value: Boolean);
    procedure SetStrokePropertyControlsVisible(Value: Boolean);
    procedure SetEditorsEnabled(Value: Boolean);
    procedure SetPathStyleControlsVisible(Value: Boolean);
    procedure SetStrokeControlsVisible(Value: Boolean);
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    // 旧属性UIを生成する。各表示フラグにより専用Frameへ移した項目を除外できる。
    constructor Create(AOwner: TComponent); override;
    // 現在選択から表示対象と値を再判定し、変更イベントを発生させずに同期する。
    procedure RefreshFromDocument;
    // Document、履歴、編集状態は非所有参照として接続する。
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write FEditorState;
    // 専用Frameへ移した項目を非表示にし、残る項目を上へ詰めるための表示フラグ。
    property GeometryControlsVisible: Boolean read FGeometryControlsVisible
      write SetGeometryControlsVisible;
    property ColorControlsVisible: Boolean read FColorControlsVisible
      write SetColorControlsVisible;
    property OpacityControlsVisible: Boolean read FOpacityControlsVisible
      write SetOpacityControlsVisible;
    property StrokePropertyControlsVisible: Boolean
      read FStrokePropertyControlsVisible write SetStrokePropertyControlsVisible;
  end;

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils, Winapi.Windows,
  Vcl.Graphics, MapRakuGeometry, MapRakuShapeEditCommands,
  MapRakuEllipseGeometry, MapRakuGroupCommands,
  MapRakuGroupTransformCommands,
  MapRakuLayerGeometry, MapRakuPathOperations;

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_EDIT = TColor($00303030);
  COLOR_LABEL = TColor($00BDBDBD);
  COLOR_TEXT = TColor($00EEEEEE);
  EDIT_HEIGHT = 25;
  MIN_OBJECT_SIZE = 1.0;

procedure ReadStrokeLayer(Layer: TVectArtLayer; out Color: TColor;
  out Width: Single; out Style: TVectArtMifStrokeStyle);
begin
  if Layer is TMapRakuRectangleLineLayer then
  begin
    Color := TMapRakuRectangleLineLayer(Layer).StrokeColor;
    Width := TMapRakuRectangleLineLayer(Layer).StrokeWidth;
    Style := TMapRakuRectangleLineLayer(Layer).StrokeStyle;
  end
  else if Layer is TMapRakuArcLayer then
  begin
    Color := TMapRakuArcLayer(Layer).StrokeColor;
    Width := TMapRakuArcLayer(Layer).StrokeWidth;
    Style := TMapRakuArcLayer(Layer).StrokeStyle;
  end
  else
  begin
    Color := TVectArtPathLayer(Layer).StrokeColor;
    Width := TVectArtPathLayer(Layer).StrokeWidth;
    Style := TVectArtPathLayer(Layer).MifStrokeStyle;
  end;
end;

procedure SetStrokeLayer(Document: TVectArtDocument; Index: Integer;
  Color: TColor; Width: Single; Style: TVectArtMifStrokeStyle);
begin
  if Document[Index] is TMapRakuRectangleLineLayer then
    Document.SetRectangleLineStroke(Index, Color, Width, Style)
  else if Document[Index] is TMapRakuArcLayer then
    Document.SetArcStroke(Index, Color, Width, Style)
  else
    Document.SetPathStroke(Index, Color, Width, Style);
end;

constructor TVectArtObjectPropertiesControl.Create(AOwner: TComponent);
var
  LineCap: TVectArtLineCap;
begin
  inherited Create(AOwner);
  FColorControlsVisible := True;
  FGeometryControlsVisible := True;
  FOpacityControlsVisible := True;
  FStrokePropertyControlsVisible := True;
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  FXEdit := NewDarkEdit;
  FYEdit := NewDarkEdit;
  FWidthEdit := NewDarkEdit;
  FHeightEdit := NewDarkEdit;
  FArcStartAngleEdit := NewDarkEdit;
  FArcEndAngleEdit := NewDarkEdit;
  FColorEdit := NewDarkEdit;
  FStrokeColorEdit := NewDarkEdit;
  FStrokeWidthEdit := NewDarkEdit;
  FMifStrokeStyleCombo := NewDarkCombo;
  FOpacityEdit := NewDarkEdit;
  for LineCap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
  begin
    FPathLineCapButtons[LineCap] := TVectArtLineCapButton.Create(Self);
    FPathLineCapButtons[LineCap].Parent := Self;
    FPathLineCapButtons[LineCap].LineCap := LineCap;
    FPathLineCapButtons[LineCap].OnClick := ApplyPathLineCap;
  end;
  SetEditorsEnabled(False);
  SetPathStyleControlsVisible(False);
  FArcStartAngleEdit.Visible := False;
  FArcEndAngleEdit.Visible := False;
end;

procedure TVectArtObjectPropertiesControl.ApplyArcAngles;
var
  ArcLayer: TMapRakuArcLayer;
  ArcShapeLayer: TMapRakuEllipseArcShapeLayer;
  EndAngle: Double;
  NewStartAngle: Single;
  NewSweepAngle: Single;
  OldStartAngle: Single;
  OldSweepAngle: Single;
  StartAngle: Double;
  SweepValue: Double;
begin
  if FUpdating or (FDocument = nil) or
    (FDocument.SelectionCount <> 1) or SelectedLayersHaveLock or
    not ((FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer) or
      (FDocument[FDocument.SelectedIndex] is
        TMapRakuEllipseArcShapeLayer)) then
    Exit;
  if not TryStrToFloat(Trim(FArcStartAngleEdit.Text), StartAngle) or
    not TryStrToFloat(Trim(FArcEndAngleEdit.Text), EndAngle) then
  begin
    RefreshFromDocument;
    Exit;
  end;
  if FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer then
  begin
    ArcLayer := TMapRakuArcLayer(FDocument[FDocument.SelectedIndex]);
    OldStartAngle := ArcLayer.StartAngleDegrees;
    OldSweepAngle := ArcLayer.SweepAngleDegrees;
  end
  else
  begin
    ArcShapeLayer := TMapRakuEllipseArcShapeLayer(
      FDocument[FDocument.SelectedIndex]);
    OldStartAngle := ArcShapeLayer.StartAngleDegrees;
    OldSweepAngle := ArcShapeLayer.SweepAngleDegrees;
  end;
  NewStartAngle := NormalizeMapRakuEllipseAngleDegrees(StartAngle);
  SweepValue := EndAngle - NewStartAngle;
  if Abs(SweepValue) >= 360.0 then
    NewSweepAngle := 360.0
  else
    NewSweepAngle := NormalizeMapRakuEllipseAngleDegrees(SweepValue);
  if SameValue(OldStartAngle, NewStartAngle) and
    SameValue(OldSweepAngle, NewSweepAngle) then
    Exit;
  if FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer then
    FDocument.SetArcAngles(FDocument.SelectedIndex, NewStartAngle,
      NewSweepAngle)
  else
    FDocument.SetEllipseArcShapeAngles(FDocument.SelectedIndex,
      NewStartAngle, NewSweepAngle);
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TMapRakuArcAnglesCommand.Create(FDocument,
      FDocument.SelectedIndex, OldStartAngle, OldSweepAngle,
      NewStartAngle, NewSweepAngle));
end;

procedure TVectArtObjectPropertiesControl.ApplyPathLineCap(Sender: TObject);
var
  ArcLayer: TMapRakuArcLayer;
  NewValue: TVectArtLineCap;
  OldValue: TVectArtLineCap;
  PathLayer: TVectArtPathLayer;
begin
  if FUpdating or (FDocument = nil) or
    (FDocument.SelectionCount <> 1) or SelectedLayersHaveLock or
    not ((FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) or
      (FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer)) or
    not (Sender is TVectArtLineCapButton) then
    Exit;
  if FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer then
  begin
    ArcLayer := TMapRakuArcLayer(FDocument[FDocument.SelectedIndex]);
    OldValue := ArcLayer.LineCap;
  end
  else
  begin
    PathLayer := TVectArtPathLayer(FDocument[FDocument.SelectedIndex]);
    OldValue := PathLayer.LineCap;
  end;
  NewValue := TVectArtLineCapButton(Sender).LineCap;
  if OldValue = NewValue then
    Exit;
  if FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer then
    FDocument.SetArcLineCap(FDocument.SelectedIndex, NewValue)
  else
    FDocument.SetPathLineCap(FDocument.SelectedIndex, NewValue);
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtPathLineCapCommand.Create(FDocument,
      FDocument.SelectedIndex, OldValue, NewValue));
  if FEditorState <> nil then
    FEditorState.LineCap := NewValue;
end;

procedure TVectArtObjectPropertiesControl.ApplyStrokeColor;
var
  Blue: Integer;
  Command: TVectArtCompoundCommand;
  Green: Integer;
  I: Integer;
  LayerIndex: Integer;
  LayerIndices: TArray<Integer>;
  NewColor: TColor;
  OldColor: TColor;
  Layer: TVectArtLayer;
  OldStyle: TVectArtMifStrokeStyle;
  OldWidth: Single;
  Red: Integer;
  Value: Integer;
begin
  if FUpdating or (FDocument = nil) or
    (FDocument.SelectionCount = 0) or SelectedLayersHaveLock then
    Exit;
  if not TryStrToInt('$' + StringReplace(Trim(FStrokeColorEdit.Text), '#', '', []),
    Value) or (Value < 0) or (Value > $FFFFFF) then
  begin
    RefreshFromDocument;
    Exit;
  end;
  Red := (Value shr 16) and $FF;
  Green := (Value shr 8) and $FF;
  Blue := Value and $FF;
  NewColor := RGB(Red, Green, Blue);
  LayerIndices := GetSelectedStrokeIndices;
  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  for I := 0 to High(LayerIndices) do
  begin
    LayerIndex := LayerIndices[I];
    Layer := FDocument[LayerIndex];
    ReadStrokeLayer(Layer, OldColor, OldWidth, OldStyle);
    SetStrokeLayer(FDocument, LayerIndex, NewColor, OldWidth, OldStyle);
    if (Command <> nil) and (OldColor <> NewColor) then
      Command.Add(TVectArtStrokeCommand.Create(FDocument, LayerIndex,
        OldColor, OldWidth, OldStyle, NewColor, OldWidth, OldStyle));
  end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
  if FEditorState <> nil then
    FEditorState.LineStrokeColor := NewColor;
end;

procedure TVectArtObjectPropertiesControl.ApplyMifStrokeStyle(Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  LayerIndex: Integer;
  LayerIndices: TArray<Integer>;
  NewStyle: TVectArtMifStrokeStyle;
  OldStyle: TVectArtMifStrokeStyle;
  Color: TColor;
  Layer: TVectArtLayer;
  Width: Single;
begin
  if FUpdating or (FDocument = nil) or (FDocument.SelectionCount = 0) or
    SelectedLayersHaveLock or (FMifStrokeStyleCombo.ItemIndex < 0) then
    Exit;
  if not InRange(FMifStrokeStyleCombo.ItemIndex,
    Ord(Low(TVectArtMifStrokeStyle)), Ord(High(TVectArtMifStrokeStyle))) then
    Exit;
  NewStyle := TVectArtMifStrokeStyle(FMifStrokeStyleCombo.ItemIndex);
  LayerIndices := GetSelectedStrokeIndices;
  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  for I := 0 to High(LayerIndices) do
  begin
    LayerIndex := LayerIndices[I];
    Layer := FDocument[LayerIndex];
    ReadStrokeLayer(Layer, Color, Width, OldStyle);
    SetStrokeLayer(FDocument, LayerIndex, Color, Width, NewStyle);
    if (Command <> nil) and (OldStyle <> NewStyle) then
      Command.Add(TVectArtStrokeCommand.Create(FDocument, LayerIndex,
        Color, Width, OldStyle, Color, Width, NewStyle));
  end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
  if FEditorState <> nil then
    FEditorState.LineMifStrokeStyle := NewStyle;
end;

procedure TVectArtObjectPropertiesControl.ApplyStrokeWidth;
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  LayerIndex: Integer;
  LayerIndices: TArray<Integer>;
  NewWidth: Double;
  OldWidth: Single;
  Color: TColor;
  Layer: TVectArtLayer;
  Style: TVectArtMifStrokeStyle;
begin
  if FUpdating or (FDocument = nil) or (FDocument.SelectionCount = 0) or
    SelectedLayersHaveLock then
    Exit;
  if not TryStrToFloat(Trim(FStrokeWidthEdit.Text), NewWidth) then
  begin
    RefreshFromDocument;
    Exit;
  end;
  NewWidth := Max(NewWidth, 0.1);
  LayerIndices := GetSelectedStrokeIndices;
  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  for I := 0 to High(LayerIndices) do
  begin
    LayerIndex := LayerIndices[I];
    Layer := FDocument[LayerIndex];
    ReadStrokeLayer(Layer, Color, OldWidth, Style);
    SetStrokeLayer(FDocument, LayerIndex, Color, NewWidth, Style);
    if (Command <> nil) and not SameValue(OldWidth, NewWidth) then
      Command.Add(TVectArtStrokeCommand.Create(FDocument, LayerIndex,
        Color, OldWidth, Style, Color, NewWidth, Style));
  end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
  if FEditorState <> nil then
    FEditorState.LineStrokeWidth := NewWidth;
end;

procedure TVectArtObjectPropertiesControl.ClearEditValue(Edit: TEdit);
begin
  // TCustomEdit.ClearはHandleNeededを呼ぶ。フォーム接続前の初期更新では
  // 親ウィンドウがまだないため、既定で空のEditはそのままにする。
  if (Edit <> nil) and Edit.HandleAllocated then
    Edit.Clear;
end;

procedure TVectArtObjectPropertiesControl.ApplyColor;
var
  Blue: Integer;
  Command: TVectArtCompoundCommand;
  Green: Integer;
  I: Integer;
  LayerIndex: Integer;
  LayerIndices: TArray<Integer>;
  Red: Integer;
  NewColor: TColor;
  OldColor: TColor;
  Value: Integer;
begin
  if FUpdating or (FDocument = nil) or
    (FDocument.SelectionCount = 0) or SelectedLayersHaveLock then
    Exit;
  if not TryStrToInt('$' + StringReplace(Trim(FColorEdit.Text), '#', '', []),
    Value) or (Value < 0) or (Value > $FFFFFF) then
  begin
    RefreshFromDocument;
    Exit;
  end;
  Red := (Value shr 16) and $FF;
  Green := (Value shr 8) and $FF;
  Blue := Value and $FF;
  NewColor := RGB(Red, Green, Blue);
  LayerIndices := GetSelectedFillIndices;
  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  for I := 0 to High(LayerIndices) do
  begin
    LayerIndex := LayerIndices[I];
    OldColor := TVectArtRectangleLayer(FDocument[LayerIndex]).FillColor;
    FDocument.SetRectangleFillColor(LayerIndex, NewColor);
    if (Command <> nil) and (OldColor <> NewColor) then
      Command.Add(TVectArtFillColorCommand.Create(FDocument, LayerIndex,
        OldColor, NewColor));
  end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
  if FEditorState <> nil then
    FEditorState.RectangleFillColor := NewColor;
end;

procedure TVectArtObjectPropertiesControl.ApplyGeometry;
var
  AngleRadians: Double;
  ArcLayer: TMapRakuArcLayer;
  Bounds: TRectF;
  HeightValue: Double;
  I: Integer;
  LayerIndices: TArray<Integer>;
  NewBounds: TArray<TRectF>;
  NewEndPoint: TPointF;
  NewImagePoints: TVectArtImagePoints;
  NewLeft: Single;
  NewPathVertices: TArray<TMapRakuVertex>;
  NewSelectionBounds: TRectF;
  NewStartPoint: TPointF;
  NewTop: Single;
  OldBounds: TArray<TRectF>;
  OldImagePoints: TVectArtImagePoints;
  OldEndPoint: TPointF;
  OldSelectionBounds: TRectF;
  OldStartPoint: TPointF;
  OldPathVertices: TArray<TMapRakuVertex>;
  PathLayer: TVectArtPathLayer;
  RectangleLine: TMapRakuRectangleLineLayer;
  ImageLayer: TVectArtImageLayer;
  ScaleX: Single;
  ScaleY: Single;
  WidthValue: Double;
  ULength: Single;
  VLength: Single;
  XValue: Double;
  YValue: Double;
begin
  if FUpdating or (FDocument = nil) then
    Exit;
  if (FEditorState <> nil) and
    (FEditorState.OpenGroupChildCount = 1) and
    (FEditorState.OpenGroupChild <> nil) then
  begin
    if FEditorState.OpenGroupChild.Locked or
      not TryGetMapRakuLayerBounds(FEditorState.OpenGroupChild,
        OldSelectionBounds) then
      Exit;
    if not TryStrToFloat(Trim(FXEdit.Text), XValue) or
      not TryStrToFloat(Trim(FYEdit.Text), YValue) or
      not TryStrToFloat(Trim(FWidthEdit.Text), WidthValue) or
      not TryStrToFloat(Trim(FHeightEdit.Text), HeightValue) then
    begin
      RefreshFromDocument;
      Exit;
    end;
    WidthValue := Max(WidthValue, MIN_OBJECT_SIZE);
    HeightValue := Max(HeightValue, MIN_OBJECT_SIZE);
    NewSelectionBounds := TRectF.Create(XValue - WidthValue * 0.5,
      YValue - HeightValue * 0.5, XValue + WidthValue * 0.5,
      YValue + HeightValue * 0.5);
    if SameValue(OldSelectionBounds.Left, NewSelectionBounds.Left) and
      SameValue(OldSelectionBounds.Top, NewSelectionBounds.Top) and
      SameValue(OldSelectionBounds.Right, NewSelectionBounds.Right) and
      SameValue(OldSelectionBounds.Bottom, NewSelectionBounds.Bottom) then
      Exit;
    ScaleMapRakuLayer(FEditorState.OpenGroupChild,
      OldSelectionBounds, NewSelectionBounds);
    FDocument.Changed;
    if FEditHistory <> nil then
      FEditHistory.AddApplied(TMapRakuScaleLayerCommand.Create(
        FDocument, FEditorState.OpenGroupChild, OldSelectionBounds,
        NewSelectionBounds));
    Exit;
  end;
  if (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is TMapRakuGroupLayer) then
  begin
    if FDocument[FDocument.SelectedIndex].Locked or
      not TryGetMapRakuLayerBounds(
        FDocument[FDocument.SelectedIndex], OldSelectionBounds) then
      Exit;
    if not TryStrToFloat(Trim(FXEdit.Text), XValue) or
      not TryStrToFloat(Trim(FYEdit.Text), YValue) or
      not TryStrToFloat(Trim(FWidthEdit.Text), WidthValue) or
      not TryStrToFloat(Trim(FHeightEdit.Text), HeightValue) then
    begin
      RefreshFromDocument;
      Exit;
    end;
    WidthValue := Max(WidthValue, MIN_OBJECT_SIZE);
    HeightValue := Max(HeightValue, MIN_OBJECT_SIZE);
    NewSelectionBounds := TRectF.Create(XValue - WidthValue * 0.5,
      YValue - HeightValue * 0.5, XValue + WidthValue * 0.5,
      YValue + HeightValue * 0.5);
    if SameValue(OldSelectionBounds.Left, NewSelectionBounds.Left) and
      SameValue(OldSelectionBounds.Top, NewSelectionBounds.Top) and
      SameValue(OldSelectionBounds.Right, NewSelectionBounds.Right) and
      SameValue(OldSelectionBounds.Bottom, NewSelectionBounds.Bottom) then
      Exit;
    ScaleMapRakuLayer(FDocument[FDocument.SelectedIndex],
      OldSelectionBounds, NewSelectionBounds);
    FDocument.Changed;
    if FEditHistory <> nil then
      FEditHistory.AddApplied(TMapRakuScaleLayerCommand.Create(
        FDocument, FDocument[FDocument.SelectedIndex], OldSelectionBounds,
        NewSelectionBounds));
    Exit;
  end;
  if (FDocument.SelectionCount = 0) or SelectedLayersHaveLock then
    Exit;
  if not TryStrToFloat(Trim(FXEdit.Text), XValue) or
    not TryStrToFloat(Trim(FYEdit.Text), YValue) or
    not TryStrToFloat(Trim(FWidthEdit.Text), WidthValue) or
    not TryStrToFloat(Trim(FHeightEdit.Text), HeightValue) then
  begin
    RefreshFromDocument;
    Exit;
  end;
  if (FDocument.SelectionCount = 1) and
    (FDocument[FDocument.SelectedIndex] is
      TMapRakuRectangleLineLayer) then
  begin
    RectangleLine := TMapRakuRectangleLineLayer(
      FDocument[FDocument.SelectedIndex]);
    WidthValue := Max(WidthValue, MIN_OBJECT_SIZE);
    HeightValue := Max(HeightValue, MIN_OBJECT_SIZE);
    OldBounds := [RectangleLine.Bounds];
    NewBounds := [TRectF.Create(XValue - WidthValue * 0.5,
      YValue - HeightValue * 0.5, XValue + WidthValue * 0.5,
      YValue + HeightValue * 0.5)];
    if SameValue(OldBounds[0].Left, NewBounds[0].Left) and
      SameValue(OldBounds[0].Top, NewBounds[0].Top) and
      SameValue(OldBounds[0].Right, NewBounds[0].Right) and
      SameValue(OldBounds[0].Bottom, NewBounds[0].Bottom) then
      Exit;
    FDocument.SetRectangleLineBounds(FDocument.SelectedIndex, NewBounds[0]);
    if FEditHistory <> nil then
      FEditHistory.AddApplied(TVectArtBoundsCommand.Create(FDocument,
        [FDocument.SelectedIndex], OldBounds, NewBounds));
    Exit;
  end;
  if (FDocument.SelectionCount = 1) and
    (FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer) then
  begin
    ArcLayer := TMapRakuArcLayer(FDocument[FDocument.SelectedIndex]);
    WidthValue := Max(WidthValue, MIN_OBJECT_SIZE);
    HeightValue := Max(HeightValue, MIN_OBJECT_SIZE);
    OldBounds := [ArcLayer.Bounds];
    NewBounds := [TRectF.Create(XValue - WidthValue * 0.5,
      YValue - HeightValue * 0.5, XValue + WidthValue * 0.5,
      YValue + HeightValue * 0.5)];
    if SameValue(OldBounds[0].Left, NewBounds[0].Left) and
      SameValue(OldBounds[0].Top, NewBounds[0].Top) and
      SameValue(OldBounds[0].Right, NewBounds[0].Right) and
      SameValue(OldBounds[0].Bottom, NewBounds[0].Bottom) then
      Exit;
    FDocument.SetArcBounds(FDocument.SelectedIndex, NewBounds[0]);
    if FEditHistory <> nil then
      FEditHistory.AddApplied(TVectArtBoundsCommand.Create(FDocument,
        [FDocument.SelectedIndex], OldBounds, NewBounds));
    Exit;
  end;
  if (FDocument.SelectionCount = 1) and
    (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) and
    not TVectArtPathLayer(FDocument[FDocument.SelectedIndex]).Closed and
    MapRakuPathIsStraightLine(TVectArtPathLayer(
      FDocument[FDocument.SelectedIndex]).Vertices) then
  begin
    PathLayer := TVectArtPathLayer(FDocument[FDocument.SelectedIndex]);
    OldPathVertices := PathLayer.Vertices;
    OldStartPoint := OldPathVertices[0].Position;
    OldEndPoint := OldPathVertices[1].Position;
    WidthValue := Max(WidthValue, MIN_OBJECT_SIZE);
    AngleRadians := DegToRad(HeightValue);
    NewStartPoint := TPointF.Create(
      XValue - Cos(AngleRadians) * WidthValue * 0.5,
      YValue - Sin(AngleRadians) * WidthValue * 0.5);
    NewEndPoint := TPointF.Create(
      XValue + Cos(AngleRadians) * WidthValue * 0.5,
      YValue + Sin(AngleRadians) * WidthValue * 0.5);
    if SameValue(OldStartPoint.X, NewStartPoint.X) and
      SameValue(OldStartPoint.Y, NewStartPoint.Y) and
      SameValue(OldEndPoint.X, NewEndPoint.X) and
      SameValue(OldEndPoint.Y, NewEndPoint.Y) then
      Exit;
    NewPathVertices := CloneMapRakuPathVertices(OldPathVertices);
    NewPathVertices[0].Position := NewStartPoint;
    NewPathVertices[1].Position := NewEndPoint;
    FDocument.SetPathVertices(FDocument.SelectedIndex, NewPathVertices);
    if FEditHistory <> nil then
      FEditHistory.AddApplied(TMapRakuPathVerticesCommand.Create(
        FDocument, FDocument.SelectedIndex, OldPathVertices,
        NewPathVertices));
    Exit;
  end;
  WidthValue := Max(WidthValue, MIN_OBJECT_SIZE);
  HeightValue := Max(HeightValue, MIN_OBJECT_SIZE);
  if (FDocument.SelectionCount = 1) and
    (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) then
  begin
    ImageLayer := TVectArtImageLayer(FDocument[FDocument.SelectedIndex]);
    OldImagePoints := ImageLayer.Points;
    ULength := Hypot(OldImagePoints[1].X - OldImagePoints[0].X,
      OldImagePoints[1].Y - OldImagePoints[0].Y);
    VLength := Hypot(OldImagePoints[3].X - OldImagePoints[0].X,
      OldImagePoints[3].Y - OldImagePoints[0].Y);
    if (ULength <= 0) or (VLength <= 0) then
    begin
      RefreshFromDocument;
      Exit;
    end;
    NewImagePoints[0] := TPointF.Create(
      XValue - (OldImagePoints[1].X - OldImagePoints[0].X) / ULength *
        WidthValue * 0.5 -
        (OldImagePoints[3].X - OldImagePoints[0].X) / VLength *
        HeightValue * 0.5,
      YValue - (OldImagePoints[1].Y - OldImagePoints[0].Y) / ULength *
        WidthValue * 0.5 -
        (OldImagePoints[3].Y - OldImagePoints[0].Y) / VLength *
        HeightValue * 0.5);
    NewImagePoints[1] := TPointF.Create(NewImagePoints[0].X +
      (OldImagePoints[1].X - OldImagePoints[0].X) / ULength * WidthValue,
      NewImagePoints[0].Y +
        (OldImagePoints[1].Y - OldImagePoints[0].Y) / ULength * WidthValue);
    NewImagePoints[3] := TPointF.Create(NewImagePoints[0].X +
      (OldImagePoints[3].X - OldImagePoints[0].X) / VLength * HeightValue,
      NewImagePoints[0].Y +
        (OldImagePoints[3].Y - OldImagePoints[0].Y) / VLength * HeightValue);
    NewImagePoints[2] := TPointF.Create(
      NewImagePoints[1].X + NewImagePoints[3].X - NewImagePoints[0].X,
      NewImagePoints[1].Y + NewImagePoints[3].Y - NewImagePoints[0].Y);
    FDocument.SetImagePoints(FDocument.SelectedIndex, NewImagePoints);
    if FEditHistory <> nil then
      FEditHistory.AddApplied(TVectArtImagePointsCommand.Create(FDocument,
        FDocument.SelectedIndex, OldImagePoints, NewImagePoints));
    Exit;
  end;
  if (FDocument.SelectionCount = 1) and
    (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) then
  begin
    PathLayer := TVectArtPathLayer(FDocument[FDocument.SelectedIndex]);
    OldPathVertices := PathLayer.Vertices;
    OldSelectionBounds := MapRakuPathVerticesBounds(OldPathVertices);
    if SameValue(OldSelectionBounds.Width, 0.0) or
      SameValue(OldSelectionBounds.Height, 0.0) then
    begin
      RefreshFromDocument;
      Exit;
    end;
    NewLeft := XValue - WidthValue * 0.5;
    NewTop := YValue - HeightValue * 0.5;
    NewSelectionBounds := TRectF.Create(NewLeft, NewTop,
      NewLeft + WidthValue, NewTop + HeightValue);
    NewPathVertices := ScaleMapRakuPathVertices(OldPathVertices,
      OldSelectionBounds, NewSelectionBounds);
    FDocument.SetPathVertices(FDocument.SelectedIndex, NewPathVertices);
    if FEditHistory <> nil then
      FEditHistory.AddApplied(TMapRakuPathVerticesCommand.Create(
        FDocument, FDocument.SelectedIndex, OldPathVertices,
        NewPathVertices));
    Exit;
  end;
  if not SelectedBounds(OldSelectionBounds) then
    Exit;
  NewSelectionBounds := TRectF.Create(XValue - WidthValue * 0.5,
    YValue - HeightValue * 0.5, XValue + WidthValue * 0.5,
    YValue + HeightValue * 0.5);
  ScaleX := NewSelectionBounds.Width / OldSelectionBounds.Width;
  ScaleY := NewSelectionBounds.Height / OldSelectionBounds.Height;
  LayerIndices := GetSelectedRectangleIndices;
  SetLength(OldBounds, Length(LayerIndices));
  SetLength(NewBounds, Length(LayerIndices));
  for I := 0 to High(LayerIndices) do
  begin
    OldBounds[I] := TVectArtRectangleLayer(
      FDocument[LayerIndices[I]]).Bounds;
    Bounds := OldBounds[I];
    NewBounds[I].Left := NewSelectionBounds.Left +
      (Bounds.Left - OldSelectionBounds.Left) * ScaleX;
    NewBounds[I].Right := NewSelectionBounds.Left +
      (Bounds.Right - OldSelectionBounds.Left) * ScaleX;
    NewBounds[I].Top := NewSelectionBounds.Top +
      (Bounds.Top - OldSelectionBounds.Top) * ScaleY;
    NewBounds[I].Bottom := NewSelectionBounds.Top +
      (Bounds.Bottom - OldSelectionBounds.Top) * ScaleY;
    FDocument.SetRectangleBounds(LayerIndices[I], NewBounds[I]);
  end;
  if (FEditHistory <> nil) and
    (not SameValue(OldSelectionBounds.Left, NewSelectionBounds.Left) or
     not SameValue(OldSelectionBounds.Top, NewSelectionBounds.Top) or
     not SameValue(OldSelectionBounds.Right, NewSelectionBounds.Right) or
     not SameValue(OldSelectionBounds.Bottom, NewSelectionBounds.Bottom)) then
    FEditHistory.AddApplied(TVectArtBoundsCommand.Create(FDocument,
      LayerIndices, OldBounds, NewBounds));
end;

function TVectArtObjectPropertiesControl.GetSelectedFillIndices:
  TArray<Integer>;
var
  I: Integer;
  Indices: TList<Integer>;
begin
  Indices := TList<Integer>.Create;
  try
    if FDocument <> nil then
      for I := 1 to FDocument.LayerCount - 1 do
        if FDocument.IsLayerSelected(I) and
          (FDocument[I] is TVectArtRectangleLayer) then
          Indices.Add(I);
    Result := Indices.ToArray;
  finally
    Indices.Free;
  end;
end;

function TVectArtObjectPropertiesControl.GetSelectedOpacityIndices:
  TArray<Integer>;
var
  I: Integer;
  Indices: TList<Integer>;
begin
  Indices := TList<Integer>.Create;
  try
    if FDocument <> nil then
      for I := 1 to FDocument.LayerCount - 1 do
        if FDocument.IsLayerSelected(I) and
          ((FDocument[I] is TVectArtRectangleLayer) or
           (FDocument[I] is TMapRakuRectangleLineLayer) or
           (FDocument[I] is TMapRakuArcLayer) or
           (FDocument[I] is TVectArtPathLayer) or
           (FDocument[I] is TVectArtImageLayer)) then
          Indices.Add(I);
    Result := Indices.ToArray;
  finally
    Indices.Free;
  end;
end;

procedure TVectArtObjectPropertiesControl.ApplyOpacity;
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  LayerIndex: Integer;
  LayerIndices: TArray<Integer>;
  NewValue: Double;
  OldValue: Single;
begin
  if FUpdating or (FDocument = nil) or
    (FDocument.SelectionCount = 0) then
    Exit;
  if not TryStrToFloat(Trim(FOpacityEdit.Text), NewValue) then
  begin
    RefreshFromDocument;
    Exit;
  end;
  NewValue := EnsureRange(NewValue, 0.0, 100.0) / 100.0;
  LayerIndices := GetSelectedOpacityIndices;
  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  for I := 0 to High(LayerIndices) do
  begin
    LayerIndex := LayerIndices[I];
    OldValue := FDocument[LayerIndex].Opacity;
    FDocument.SetLayerOpacity(LayerIndex, NewValue);
    if (Command <> nil) and not SameValue(OldValue, NewValue) then
      Command.Add(TVectArtLayerOpacityCommand.Create(FDocument, LayerIndex,
        OldValue, NewValue));
  end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
  if FEditorState <> nil then
    FEditorState.RectangleOpacity := NewValue;
end;

procedure TVectArtObjectPropertiesControl.EditExit(Sender: TObject);
begin
  if (Sender = FArcStartAngleEdit) or (Sender = FArcEndAngleEdit) then
    ApplyArcAngles
  else if Sender = FColorEdit then
    ApplyColor
  else if Sender = FStrokeColorEdit then
    ApplyStrokeColor
  else if Sender = FStrokeWidthEdit then
    ApplyStrokeWidth
  else if Sender = FOpacityEdit then
    ApplyOpacity
  else
    ApplyGeometry;
end;

function TVectArtObjectPropertiesControl.NewDarkCombo:
  TVectArtMifStrokeStyleCombo;
begin
  Result := TVectArtMifStrokeStyleCombo.Create(Self);
  Result.Parent := Self;
  Result.Style := csOwnerDrawFixed;
  Result.ItemHeight := 22;
  Result.DropDownCount := 9;
  Result.Color := COLOR_EDIT;
  Result.Font.Name := 'Segoe UI';
  Result.Font.Height := -12;
  Result.Font.Color := COLOR_TEXT;
  Result.ParentColor := False;
  Result.ParentFont := False;
  Result.OnChange := ApplyMifStrokeStyle;
end;

procedure TVectArtObjectPropertiesControl.EditKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    EditExit(Sender);
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    RefreshFromDocument;
    Key := 0;
  end;
end;

function TVectArtObjectPropertiesControl.NewDarkEdit: TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.AutoSize := False;
  Result.Height := EDIT_HEIGHT;
  Result.Color := COLOR_EDIT;
  Result.Font.Name := 'Segoe UI';
  Result.Font.Height := -12;
  Result.Font.Color := COLOR_TEXT;
  Result.ParentColor := False;
  Result.ParentFont := False;
  Result.OnExit := EditExit;
  Result.OnKeyDown := EditKeyDown;
end;

function TVectArtObjectPropertiesControl.GetSelectedRectangleIndices:
  TArray<Integer>;
var
  I: Integer;
  Indices: TList<Integer>;
begin
  Indices := TList<Integer>.Create;
  try
    if FDocument <> nil then
      for I := 1 to FDocument.LayerCount - 1 do
        if FDocument.IsLayerSelected(I) and
          (FDocument[I] is TVectArtRectangleLayer) then
          Indices.Add(I);
    Result := Indices.ToArray;
  finally
    Indices.Free;
  end;
end;

function TVectArtObjectPropertiesControl.GetSelectedStrokeIndices:
  TArray<Integer>;
var
  I: Integer;
  Indices: TList<Integer>;
begin
  Indices := TList<Integer>.Create;
  try
    if FDocument <> nil then
      for I := 1 to FDocument.LayerCount - 1 do
        if FDocument.IsLayerSelected(I) and
          ((FDocument[I] is TMapRakuRectangleLineLayer) or
           (FDocument[I] is TVectArtPathLayer) or
           (FDocument[I] is TMapRakuArcLayer)) then
          Indices.Add(I);
    Result := Indices.ToArray;
  finally
    Indices.Free;
  end;
end;

function TVectArtObjectPropertiesControl.SelectedLayersHaveLock: Boolean;
var
  I: Integer;
begin
  Result := False;
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and FDocument[I].Locked then
      Exit(True);
end;

procedure TVectArtObjectPropertiesControl.Paint;
var
  ColorOffset: Integer;
  ColorValue: TColor;
  HeaderText: string;
  HexValue: Integer;
  IsLineSelection: Boolean;
  OpacityOffset: Integer;
  SectionOffset: Integer;
  SwatchRect: TRect;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -12;
  Canvas.Font.Color := COLOR_LABEL;
  if (FEditorState <> nil) and (FEditorState.OpenGroupChildCount > 1) then
    HeaderText := Format('%d objects selected',
      [FEditorState.OpenGroupChildCount])
  else if (FEditorState <> nil) and
    (FEditorState.OpenGroupChild <> nil) then
    HeaderText := FEditorState.OpenGroupChild.Name
  else if (FDocument = nil) or (FDocument.SelectionCount = 0) then
    HeaderText := 'No selection'
  else if FDocument.SelectionCount = 1 then
    HeaderText := FDocument[FDocument.SelectedIndex].Name
  else
    HeaderText := Format('%d objects selected', [FDocument.SelectionCount]);
  Canvas.Font.Color := COLOR_TEXT;
  Canvas.TextOut(12, 12, HeaderText);
  Canvas.Font.Color := COLOR_LABEL;
  if FGeometryControlsVisible then
  begin
    Canvas.TextOut(12, 43, 'X');
    Canvas.TextOut((ClientWidth div 2) + 4, 43, 'Y');
  end;
  IsLineSelection := (FDocument <> nil) and
    (FDocument.SelectionCount = 1) and
    (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) and
    not TVectArtPathLayer(FDocument[FDocument.SelectedIndex]).Closed and
    MapRakuPathIsStraightLine(TVectArtPathLayer(
      FDocument[FDocument.SelectedIndex]).Vertices);
  if FGeometryControlsVisible and IsLineSelection then
  begin
    Canvas.TextOut(12, 91, 'Length');
    Canvas.TextOut((ClientWidth div 2) + 4, 91, 'Angle (deg)');
  end
  else if FGeometryControlsVisible then
  begin
    Canvas.TextOut(12, 91, 'Width');
    Canvas.TextOut((ClientWidth div 2) + 4, 91, 'Height');
  end;
  if FGeometryControlsVisible then
    SectionOffset := 0
  else
    SectionOffset := -96;
  if FColorControlsVisible then
    ColorOffset := 0
  else
    ColorOffset := -49;
  if FOpacityControlsVisible then
    OpacityOffset := 0
  else
    OpacityOffset := -49;
  if FColorEdit.Visible then
    Canvas.TextOut(12, 139 + SectionOffset, 'Fill color');
  if FArcStartAngleEdit.Visible then
  begin
    Canvas.TextOut(12, 139 + SectionOffset, 'Start angle');
    Canvas.TextOut((ClientWidth div 2) + 4, 139 + SectionOffset,
      'End angle');
  end;
  if FStrokeColorEdit.Visible then
    Canvas.TextOut(12, 190 + SectionOffset, 'Stroke color');
  if FStrokeWidthEdit.Visible then
  begin
    Canvas.TextOut(12, 239 + SectionOffset + ColorOffset,
      'Stroke width (0 = none)');
    Canvas.TextOut((ClientWidth div 2) + 4,
      239 + SectionOffset + ColorOffset,
      'Stroke style');
  end;
  if FOpacityEdit.Visible then
    Canvas.TextOut(12, 288 + SectionOffset + ColorOffset, 'Opacity (%)');
  if FPathLineCapButtons[vlcSquare].Visible then
    Canvas.TextOut(12, 337 + SectionOffset + ColorOffset + OpacityOffset,
      'Line cap');
  if FColorEdit.Visible then
  begin
    SwatchRect := Rect(ClientWidth - 42, 158 + SectionOffset,
      ClientWidth - 12, 183 + SectionOffset);
    ColorValue := COLOR_EDIT;
    if TryStrToInt('$' + StringReplace(Trim(FColorEdit.Text), '#', '', []),
      HexValue) and (HexValue >= 0) and (HexValue <= $FFFFFF) then
      ColorValue := RGB((HexValue shr 16) and $FF,
        (HexValue shr 8) and $FF, HexValue and $FF);
    Canvas.Brush.Color := ColorValue;
    Canvas.FillRect(SwatchRect);
    Canvas.Brush.Color := COLOR_LABEL;
    Canvas.FrameRect(SwatchRect);
  end;
  if FStrokeColorEdit.Visible then
  begin
    SwatchRect := Rect(ClientWidth - 42, 207 + SectionOffset,
      ClientWidth - 12, 232 + SectionOffset);
    ColorValue := COLOR_EDIT;
    if TryStrToInt('$' + StringReplace(Trim(FStrokeColorEdit.Text), '#', '', []),
      HexValue) and (HexValue >= 0) and (HexValue <= $FFFFFF) then
      ColorValue := RGB((HexValue shr 16) and $FF,
        (HexValue shr 8) and $FF, HexValue and $FF);
    Canvas.Brush.Color := ColorValue;
    Canvas.FillRect(SwatchRect);
    Canvas.Brush.Color := COLOR_LABEL;
    Canvas.FrameRect(SwatchRect);
  end;
end;

procedure TVectArtObjectPropertiesControl.RefreshFromDocument;
var
  ArcLayer: TMapRakuArcLayer;
  ArcShapeLayer: TMapRakuEllipseArcShapeLayer;
  Bounds: TRectF;
  ColorValue: TColor;
  CommonColor: Boolean;
  CommonOpacity: Boolean;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  LayerIndices: TArray<Integer>;
  OpacityValue: Single;
  PathLayer: TVectArtPathLayer;
  PathVertices: TArray<TMapRakuVertex>;
  RectangleLine: TMapRakuRectangleLineLayer;
  RectangleLayer: TVectArtRectangleLayer;
  StrokeColorValue: TColor;
begin
  FUpdating := True;
  try
    SetPathStyleControlsVisible(False);
    SetStrokeControlsVisible(False);
    FColorEdit.Visible := False;
    FArcStartAngleEdit.Visible := False;
    FArcEndAngleEdit.Visible := False;
    if (FDocument <> nil) and (FEditorState <> nil) and
      (FEditorState.OpenGroupChildCount = 1) and
      (FEditorState.OpenGroupChild <> nil) and
      TryGetMapRakuLayerBounds(FEditorState.OpenGroupChild, Bounds) then
    begin
      FXEdit.Text := FormatFloat('0.##', Bounds.CenterPoint.X);
      FYEdit.Text := FormatFloat('0.##', Bounds.CenterPoint.Y);
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      ClearEditValue(FColorEdit);
      ClearEditValue(FStrokeColorEdit);
      ClearEditValue(FStrokeWidthEdit);
      FMifStrokeStyleCombo.SetPendingItemIndex(-1);
      FOpacityEdit.Text := FormatFloat('0.##',
        FEditorState.OpenGroupChild.Opacity * 100);
      SetEditorsEnabled(not FEditorState.OpenGroupChild.Locked);
      FColorEdit.Enabled := False;
      FStrokeColorEdit.Enabled := False;
      FStrokeWidthEdit.Enabled := False;
      FMifStrokeStyleCombo.Enabled := False;
      FOpacityEdit.Enabled := False;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TMapRakuGroupLayer) and
      TryGetMapRakuLayerBounds(FDocument[FDocument.SelectedIndex],
        Bounds) then
    begin
      FXEdit.Text := FormatFloat('0.##', Bounds.CenterPoint.X);
      FYEdit.Text := FormatFloat('0.##', Bounds.CenterPoint.Y);
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      ClearEditValue(FColorEdit);
      ClearEditValue(FStrokeColorEdit);
      ClearEditValue(FStrokeWidthEdit);
      FMifStrokeStyleCombo.SetPendingItemIndex(-1);
      ClearEditValue(FOpacityEdit);
      SetEditorsEnabled(not FDocument[FDocument.SelectedIndex].Locked);
      FColorEdit.Enabled := False;
      FStrokeColorEdit.Enabled := False;
      FStrokeWidthEdit.Enabled := False;
      FMifStrokeStyleCombo.Enabled := False;
      FOpacityEdit.Enabled := False;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
      (FDocument[FDocument.SelectedIndex] is
        TMapRakuRectangleLineLayer) then
    begin
      RectangleLine := TMapRakuRectangleLineLayer(
        FDocument[FDocument.SelectedIndex]);
      Bounds := RectangleLine.Bounds;
      FXEdit.Text := FormatFloat('0.##', (Bounds.Left + Bounds.Right) * 0.5);
      FYEdit.Text := FormatFloat('0.##', (Bounds.Top + Bounds.Bottom) * 0.5);
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      SetStrokeControlsVisible(True);
      StrokeColorValue := ColorToRGB(RectangleLine.StrokeColor);
      FStrokeColorEdit.Text := Format('#%.2x%.2x%.2x',
        [GetRValue(StrokeColorValue), GetGValue(StrokeColorValue),
         GetBValue(StrokeColorValue)]);
      FStrokeWidthEdit.Text := FormatFloat('0.##', RectangleLine.StrokeWidth);
      FMifStrokeStyleCombo.SetPendingItemIndex(
        Ord(RectangleLine.StrokeStyle));
      FOpacityEdit.Text := FormatFloat('0.##', RectangleLine.Opacity * 100);
      SetEditorsEnabled(not RectangleLine.Locked);
      FColorEdit.Enabled := False;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
      (FDocument[FDocument.SelectedIndex] is
        TMapRakuEllipseArcShapeLayer) then
    begin
      ArcShapeLayer := TMapRakuEllipseArcShapeLayer(
        FDocument[FDocument.SelectedIndex]);
      Bounds := ArcShapeLayer.Bounds;
      FXEdit.Text := FormatFloat('0.##', (Bounds.Left + Bounds.Right) * 0.5);
      FYEdit.Text := FormatFloat('0.##', (Bounds.Top + Bounds.Bottom) * 0.5);
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      FArcStartAngleEdit.Visible := True;
      FArcEndAngleEdit.Visible := True;
      FArcStartAngleEdit.Text := FormatFloat('0.##',
        ArcShapeLayer.StartAngleDegrees);
      FArcEndAngleEdit.Text := FormatFloat('0.##',
        ArcShapeLayer.StartAngleDegrees + ArcShapeLayer.SweepAngleDegrees);
      FColorEdit.Visible := True;
      ColorValue := ColorToRGB(ArcShapeLayer.FillColor);
      FColorEdit.Text := Format('#%.2x%.2x%.2x', [GetRValue(ColorValue),
        GetGValue(ColorValue), GetBValue(ColorValue)]);
      FOpacityEdit.Text := FormatFloat('0.##', ArcShapeLayer.Opacity * 100);
      SetEditorsEnabled(not ArcShapeLayer.Locked);
      FStrokeColorEdit.Enabled := False;
      FStrokeWidthEdit.Enabled := False;
      FMifStrokeStyleCombo.Enabled := False;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
      (FDocument[FDocument.SelectedIndex] is TMapRakuArcLayer) then
    begin
      ArcLayer := TMapRakuArcLayer(FDocument[FDocument.SelectedIndex]);
      Bounds := ArcLayer.Bounds;
      FXEdit.Text := FormatFloat('0.##', (Bounds.Left + Bounds.Right) * 0.5);
      FYEdit.Text := FormatFloat('0.##', (Bounds.Top + Bounds.Bottom) * 0.5);
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      FArcStartAngleEdit.Visible := True;
      FArcEndAngleEdit.Visible := True;
      FArcStartAngleEdit.Text := FormatFloat('0.##',
        ArcLayer.StartAngleDegrees);
      FArcEndAngleEdit.Text := FormatFloat('0.##',
        ArcLayer.StartAngleDegrees + ArcLayer.SweepAngleDegrees);
      SetStrokeControlsVisible(True);
      StrokeColorValue := ColorToRGB(ArcLayer.StrokeColor);
      FStrokeColorEdit.Text := Format('#%.2x%.2x%.2x',
        [GetRValue(StrokeColorValue), GetGValue(StrokeColorValue),
         GetBValue(StrokeColorValue)]);
      FStrokeWidthEdit.Text := FormatFloat('0.##', ArcLayer.StrokeWidth);
      FMifStrokeStyleCombo.SetPendingItemIndex(Ord(ArcLayer.StrokeStyle));
      SetPathStyleControlsVisible(True);
      FPathLineCapButtons[vlcSquare].Selected :=
        ArcLayer.LineCap = vlcSquare;
      FPathLineCapButtons[vlcRound].Selected :=
        ArcLayer.LineCap = vlcRound;
      FPathLineCapButtons[vlcTriangle].Selected :=
        ArcLayer.LineCap = vlcTriangle;
      FOpacityEdit.Text := FormatFloat('0.##', ArcLayer.Opacity * 100);
      SetEditorsEnabled(not ArcLayer.Locked);
      FColorEdit.Enabled := False;
      if ArcLayer.Locked then
      begin
        FPathLineCapButtons[vlcSquare].Enabled := False;
        FPathLineCapButtons[vlcRound].Enabled := False;
        FPathLineCapButtons[vlcTriangle].Enabled := False;
      end;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
      (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) then
    begin
      RectangleLayer := TVectArtRectangleLayer(
        FDocument[FDocument.SelectedIndex]);
      FColorEdit.Visible := True;
      Bounds := RectangleLayer.Bounds;
      FXEdit.Text := FormatFloat('0.##', (Bounds.Left + Bounds.Right) * 0.5);
      FYEdit.Text := FormatFloat('0.##', (Bounds.Top + Bounds.Bottom) * 0.5);
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      ColorValue := ColorToRGB(RectangleLayer.FillColor);
      FColorEdit.Text := Format('#%.2x%.2x%.2x', [GetRValue(ColorValue),
        GetGValue(ColorValue), GetBValue(ColorValue)]);
      FOpacityEdit.Text := FormatFloat('0.##', RectangleLayer.Opacity * 100);
      ClearEditValue(FStrokeColorEdit);
      ClearEditValue(FStrokeWidthEdit);
      FMifStrokeStyleCombo.SetPendingItemIndex(-1);
      SetEditorsEnabled(True);
      FStrokeColorEdit.Enabled := False;
      FStrokeWidthEdit.Enabled := False;
      FMifStrokeStyleCombo.Enabled := False;
      if RectangleLayer.Locked then
      begin
        FXEdit.Enabled := False;
        FYEdit.Enabled := False;
        FWidthEdit.Enabled := False;
        FHeightEdit.Enabled := False;
        FColorEdit.Enabled := False;
        FStrokeColorEdit.Enabled := False;
        FStrokeWidthEdit.Enabled := False;
        FMifStrokeStyleCombo.Enabled := False;
      end;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
      (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) then
    begin
      ImageLayer := TVectArtImageLayer(FDocument[FDocument.SelectedIndex]);
      FXEdit.Text := FormatFloat('0.##',
        (ImageLayer.Points[0].X + ImageLayer.Points[2].X) * 0.5);
      FYEdit.Text := FormatFloat('0.##',
        (ImageLayer.Points[0].Y + ImageLayer.Points[2].Y) * 0.5);
      FWidthEdit.Text := FormatFloat('0.##', Hypot(
        ImageLayer.Points[1].X - ImageLayer.Points[0].X,
        ImageLayer.Points[1].Y - ImageLayer.Points[0].Y));
      FHeightEdit.Text := FormatFloat('0.##', Hypot(
        ImageLayer.Points[3].X - ImageLayer.Points[0].X,
        ImageLayer.Points[3].Y - ImageLayer.Points[0].Y));
      ClearEditValue(FColorEdit);
      ClearEditValue(FStrokeColorEdit);
      ClearEditValue(FStrokeWidthEdit);
      FMifStrokeStyleCombo.SetPendingItemIndex(-1);
      FOpacityEdit.Text := FormatFloat('0.##', ImageLayer.Opacity * 100);
      SetEditorsEnabled(True);
      FColorEdit.Enabled := False;
      FStrokeColorEdit.Enabled := False;
      FStrokeWidthEdit.Enabled := False;
      FMifStrokeStyleCombo.Enabled := False;
      if ImageLayer.Locked then
      begin
        FXEdit.Enabled := False;
        FYEdit.Enabled := False;
        FWidthEdit.Enabled := False;
        FHeightEdit.Enabled := False;
        FOpacityEdit.Enabled := False;
      end;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
      (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) then
    begin
      PathLayer := TVectArtPathLayer(FDocument[FDocument.SelectedIndex]);
      PathVertices := PathLayer.Vertices;
      if not PathLayer.Closed and
        MapRakuPathIsStraightLine(PathVertices) then
      begin
        FXEdit.Text := FormatFloat('0.##',
          (PathVertices[0].Position.X +
            PathVertices[1].Position.X) * 0.5);
        FYEdit.Text := FormatFloat('0.##',
          (PathVertices[0].Position.Y +
            PathVertices[1].Position.Y) * 0.5);
        FWidthEdit.Text := FormatFloat('0.##', Hypot(
          PathVertices[1].Position.X - PathVertices[0].Position.X,
          PathVertices[1].Position.Y - PathVertices[0].Position.Y));
        FHeightEdit.Text := FormatFloat('0.##', RadToDeg(ArcTan2(
          PathVertices[1].Position.Y - PathVertices[0].Position.Y,
          PathVertices[1].Position.X - PathVertices[0].Position.X)));
      end
      else
      begin
        Bounds := MapRakuPathVerticesBounds(PathVertices);
        FXEdit.Text := FormatFloat('0.##',
          (Bounds.Left + Bounds.Right) * 0.5);
        FYEdit.Text := FormatFloat('0.##',
          (Bounds.Top + Bounds.Bottom) * 0.5);
        FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
        FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      end;
      FOpacityEdit.Text := FormatFloat('0.##', PathLayer.Opacity * 100);
      SetStrokeControlsVisible(True);
      ClearEditValue(FColorEdit);
      StrokeColorValue := ColorToRGB(PathLayer.StrokeColor);
      FStrokeColorEdit.Text := Format('#%.2x%.2x%.2x',
        [GetRValue(StrokeColorValue), GetGValue(StrokeColorValue),
         GetBValue(StrokeColorValue)]);
      FStrokeWidthEdit.Text := FormatFloat('0.##', PathLayer.StrokeWidth);
      FMifStrokeStyleCombo.SetPendingItemIndex(Ord(PathLayer.MifStrokeStyle));
      SetPathStyleControlsVisible(not PathLayer.Closed);
      FPathLineCapButtons[vlcSquare].Selected := PathLayer.LineCap = vlcSquare;
      FPathLineCapButtons[vlcRound].Selected := PathLayer.LineCap = vlcRound;
      FPathLineCapButtons[vlcTriangle].Selected :=
        PathLayer.LineCap = vlcTriangle;
      SetEditorsEnabled(True);
      FColorEdit.Enabled := False;
      if PathLayer.Locked then
      begin
        FXEdit.Enabled := False;
        FYEdit.Enabled := False;
        FWidthEdit.Enabled := False;
        FHeightEdit.Enabled := False;
        FColorEdit.Enabled := False;
        FStrokeColorEdit.Enabled := False;
        FStrokeWidthEdit.Enabled := False;
        FMifStrokeStyleCombo.Enabled := False;
        FPathLineCapButtons[vlcSquare].Enabled := False;
        FPathLineCapButtons[vlcRound].Enabled := False;
        FPathLineCapButtons[vlcTriangle].Enabled := False;
      end;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount > 1) and
      SelectedBounds(Bounds) then
    begin
      FColorEdit.Visible := True;
      FXEdit.Text := FormatFloat('0.##', (Bounds.Left + Bounds.Right) * 0.5);
      FYEdit.Text := FormatFloat('0.##', (Bounds.Top + Bounds.Bottom) * 0.5);
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      LayerIndices := GetSelectedRectangleIndices;
      RectangleLayer := TVectArtRectangleLayer(FDocument[LayerIndices[0]]);
      ColorValue := RectangleLayer.FillColor;
      OpacityValue := RectangleLayer.Opacity;
      CommonColor := True;
      CommonOpacity := True;
      for I := 1 to High(LayerIndices) do
      begin
        RectangleLayer := TVectArtRectangleLayer(FDocument[LayerIndices[I]]);
        CommonColor := CommonColor and
          (RectangleLayer.FillColor = ColorValue);
        CommonOpacity := CommonOpacity and
          SameValue(RectangleLayer.Opacity, OpacityValue);
      end;
      if CommonColor then
      begin
        ColorValue := ColorToRGB(ColorValue);
        FColorEdit.Text := Format('#%.2x%.2x%.2x', [GetRValue(ColorValue),
          GetGValue(ColorValue), GetBValue(ColorValue)]);
      end
      else
        ClearEditValue(FColorEdit);
      if CommonOpacity then
        FOpacityEdit.Text := FormatFloat('0.##', OpacityValue * 100)
      else
        ClearEditValue(FOpacityEdit);
      ClearEditValue(FStrokeColorEdit);
      ClearEditValue(FStrokeWidthEdit);
      FMifStrokeStyleCombo.SetPendingItemIndex(-1);
      SetEditorsEnabled(True);
      FStrokeColorEdit.Enabled := False;
      FStrokeWidthEdit.Enabled := False;
      FMifStrokeStyleCombo.Enabled := False;
      if SelectedLayersHaveLock then
      begin
        FXEdit.Enabled := False;
        FYEdit.Enabled := False;
        FWidthEdit.Enabled := False;
        FHeightEdit.Enabled := False;
        FColorEdit.Enabled := False;
        FStrokeColorEdit.Enabled := False;
        FStrokeWidthEdit.Enabled := False;
        FMifStrokeStyleCombo.Enabled := False;
      end;
    end
    else
    begin
      ClearEditValue(FXEdit);
      ClearEditValue(FYEdit);
      ClearEditValue(FWidthEdit);
      ClearEditValue(FHeightEdit);
      ClearEditValue(FArcStartAngleEdit);
      ClearEditValue(FArcEndAngleEdit);
      ClearEditValue(FColorEdit);
      ClearEditValue(FStrokeColorEdit);
      ClearEditValue(FStrokeWidthEdit);
      FMifStrokeStyleCombo.SetPendingItemIndex(-1);
      ClearEditValue(FOpacityEdit);
      SetEditorsEnabled(False);
    end;
  finally
    if not FColorControlsVisible then
    begin
      FColorEdit.Visible := False;
      FStrokeColorEdit.Visible := False;
    end;
    if not FOpacityControlsVisible then
      FOpacityEdit.Visible := False;
    if not FStrokePropertyControlsVisible then
    begin
      FStrokeWidthEdit.Visible := False;
      FMifStrokeStyleCombo.Visible := False;
      SetPathStyleControlsVisible(False);
    end;
    FUpdating := False;
  end;
  Invalidate;
end;

function TVectArtObjectPropertiesControl.SelectedBounds(
  out Bounds: TRectF): Boolean;
var
  I: Integer;
  LayerBounds: TRectF;
begin
  Bounds := TRectF.Empty;
  Result := False;
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and
      (FDocument[I] is TVectArtRectangleLayer) then
    begin
      LayerBounds := TVectArtRectangleLayer(FDocument[I]).Bounds;
      if not Result then
      begin
        Bounds := LayerBounds;
        Result := True;
      end
      else
      begin
        Bounds.Left := Min(Bounds.Left, LayerBounds.Left);
        Bounds.Top := Min(Bounds.Top, LayerBounds.Top);
        Bounds.Right := Max(Bounds.Right, LayerBounds.Right);
        Bounds.Bottom := Max(Bounds.Bottom, LayerBounds.Bottom);
      end;
    end;
end;

procedure TVectArtObjectPropertiesControl.Resize;
var
  ButtonWidth: Integer;
  ColorOffset: Integer;
  ColumnWidth: Integer;
  OpacityOffset: Integer;
  SectionOffset: Integer;
begin
  inherited Resize;
  if FGeometryControlsVisible then
    SectionOffset := 0
  else
    SectionOffset := -96;
  if FColorControlsVisible then
    ColorOffset := 0
  else
    ColorOffset := -49;
  if FOpacityControlsVisible then
    OpacityOffset := 0
  else
    OpacityOffset := -49;
  ColumnWidth := Max((ClientWidth - 36) div 2, 48);
  FXEdit.SetBounds(12, 59, ColumnWidth, EDIT_HEIGHT);
  FYEdit.SetBounds((ClientWidth div 2) + 4, 59, ColumnWidth, EDIT_HEIGHT);
  FWidthEdit.SetBounds(12, 107, ColumnWidth, EDIT_HEIGHT);
  FHeightEdit.SetBounds((ClientWidth div 2) + 4, 107, ColumnWidth,
    EDIT_HEIGHT);
  FArcStartAngleEdit.SetBounds(12, 158 + SectionOffset, ColumnWidth,
    EDIT_HEIGHT);
  FArcEndAngleEdit.SetBounds((ClientWidth div 2) + 4,
    158 + SectionOffset, ColumnWidth, EDIT_HEIGHT);
  FColorEdit.SetBounds(12, 158 + SectionOffset,
    Max(ClientWidth - 66, 48), EDIT_HEIGHT);
  FStrokeColorEdit.SetBounds(12, 207 + SectionOffset,
    Max(ClientWidth - 66, 48), EDIT_HEIGHT);
  FStrokeWidthEdit.SetBounds(12, 256 + SectionOffset + ColorOffset,
    ColumnWidth,
    EDIT_HEIGHT);
  FMifStrokeStyleCombo.SetBounds((ClientWidth div 2) + 4,
    256 + SectionOffset + ColorOffset, ColumnWidth, EDIT_HEIGHT);
  FOpacityEdit.SetBounds(12, 305 + SectionOffset + ColorOffset,
    Max(ClientWidth - 24, 48), EDIT_HEIGHT);
  ButtonWidth := Max((ClientWidth - 40) div 3, 32);
  FPathLineCapButtons[vlcSquare].SetBounds(12,
    354 + SectionOffset + ColorOffset + OpacityOffset,
    ButtonWidth, 30);
  FPathLineCapButtons[vlcRound].SetBounds(16 + ButtonWidth,
    354 + SectionOffset + ColorOffset + OpacityOffset,
    ButtonWidth, 30);
  FPathLineCapButtons[vlcTriangle].SetBounds(20 + ButtonWidth * 2,
    354 + SectionOffset + ColorOffset + OpacityOffset, ButtonWidth, 30);
end;

procedure TVectArtObjectPropertiesControl.SetColorControlsVisible(
  Value: Boolean);
begin
  if FColorControlsVisible = Value then
    Exit;
  FColorControlsVisible := Value;
  RefreshFromDocument;
  Resize;
  Invalidate;
end;

procedure TVectArtObjectPropertiesControl.SetDocument(
  const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  FDocument := Value;
  RefreshFromDocument;
end;

procedure TVectArtObjectPropertiesControl.SetGeometryControlsVisible(
  Value: Boolean);
begin
  if FGeometryControlsVisible = Value then
    Exit;
  FGeometryControlsVisible := Value;
  FXEdit.Visible := Value;
  FYEdit.Visible := Value;
  FWidthEdit.Visible := Value;
  FHeightEdit.Visible := Value;
  Resize;
  Invalidate;
end;

procedure TVectArtObjectPropertiesControl.SetOpacityControlsVisible(
  Value: Boolean);
begin
  if FOpacityControlsVisible = Value then
    Exit;
  FOpacityControlsVisible := Value;
  RefreshFromDocument;
  Resize;
  Invalidate;
end;

procedure TVectArtObjectPropertiesControl.SetEditorsEnabled(Value: Boolean);
begin
  FXEdit.Enabled := Value;
  FYEdit.Enabled := Value;
  FWidthEdit.Enabled := Value;
  FHeightEdit.Enabled := Value;
  FArcStartAngleEdit.Enabled := Value;
  FArcEndAngleEdit.Enabled := Value;
  FColorEdit.Enabled := Value;
  FStrokeColorEdit.Enabled := Value;
  FStrokeWidthEdit.Enabled := Value;
  FMifStrokeStyleCombo.Enabled := Value;
  FOpacityEdit.Enabled := Value;
end;

procedure TVectArtObjectPropertiesControl.SetPathStyleControlsVisible(
  Value: Boolean);
var
  LineCap: TVectArtLineCap;
begin
  for LineCap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
  begin
    FPathLineCapButtons[LineCap].Visible := Value;
    FPathLineCapButtons[LineCap].Enabled := Value;
  end;
end;

procedure TVectArtObjectPropertiesControl.SetStrokeControlsVisible(
  Value: Boolean);
begin
  FStrokeColorEdit.Visible := Value and FColorControlsVisible;
  FStrokeWidthEdit.Visible := Value and FStrokePropertyControlsVisible;
  FMifStrokeStyleCombo.Visible := Value and FStrokePropertyControlsVisible;
end;

procedure TVectArtObjectPropertiesControl.SetStrokePropertyControlsVisible(
  Value: Boolean);
begin
  if FStrokePropertyControlsVisible = Value then
    Exit;
  FStrokePropertyControlsVisible := Value;
  RefreshFromDocument;
  Resize;
  Invalidate;
end;

end.
