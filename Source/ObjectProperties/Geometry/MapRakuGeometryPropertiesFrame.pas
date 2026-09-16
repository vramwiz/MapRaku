// 選択範囲の中心座標・実寸と、キャンバス基準の配置プリセットをポップアップで編集する。
unit MapRakuGeometryPropertiesFrame;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  MapRakuDocument, MapRakuEditHistory, MapRakuEditorState;

type
  // 先頭9値は現在サイズを維持する基準点、末尾値はキャンバス全体への拡大を表す。
  TMapRakuGeometryPreset = (slgpTopLeft, slgpTopCenter,
    slgpTopRight, slgpCenterLeft, slgpCenter, slgpCenterRight,
    slgpBottomLeft, slgpBottomCenter, slgpBottomRight, slgpFillCanvas);

  // Parent未接続のFrameでも生成できるよう、項目構築をHandle生成まで遅延する。
  TMapRakuGeometryPresetCombo = class(TComboBox)
  private
    FPendingItemIndex: Integer;
  protected
    procedure CreateWnd; override;
  public
    // Handle生成前でも中央プリセットを初期値として保持できるComboBoxを生成する。
    constructor Create(AOwner: TComponent); override;
    // Handleの有無にかかわらず選択値を保持し、生成後のItemsへ同じ値を反映する。
    procedure SetPendingItemIndex(Value: Integer);
    // Handle未生成時を含む論理上の選択Index。
    property PendingItemIndex: Integer read FPendingItemIndex;
  end;

  TMapRakuGeometryPropertiesFrame = class(TFrame)
  private
    FApplyPresetButton: TButton;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    FHeightEdit: TEdit;
    FHeightLabel: TLabel;
    FPresetCombo: TMapRakuGeometryPresetCombo;
    FPresetLabel: TLabel;
    FTitleLabel: TLabel;
    FUpdating: Boolean;
    FWidthEdit: TEdit;
    FWidthLabel: TLabel;
    FXEdit: TEdit;
    FXLabel: TLabel;
    FYEdit: TEdit;
    FYLabel: TLabel;
    procedure ApplyGeometry;
    procedure ApplyPresetClick(Sender: TObject);
    procedure EditExit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    function NewDarkEdit: TEdit;
    function NewFieldLabel(const Caption: string): TLabel;
    procedure PresetChanged(Sender: TObject);
    function SelectedGeometry(out Layers: TArray<TVectArtLayer>;
      out Bounds: TRectF; out Locked: Boolean): Boolean;
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetEditorState(const Value: TVectArtEditorState);
    procedure SetInputsEnabled(Value: Boolean; SizeEnabled: Boolean);
    procedure UpdatePresetEnabled(Value, SizeEnabled: Boolean);
  protected
    procedure Resize; override;
  public
    // 座標とサイズの共通入力欄を生成し、選択型に応じた表示名へ切り替える。
    constructor Create(AOwner: TComponent); override;
    // 現在サイズを維持する9点配置、またはキャンバス全面への変形を1回のUndo対象として適用する。
    procedure ApplyPreset(Value: TMapRakuGeometryPreset);
    // ポップアップ表示直後にX入力へフォーカスを移す。
    procedure FocusFirstInput;
    // 現在選択の外接範囲とロック状態を入力欄へ反映する。
    procedure RefreshFromDocument;
    // 各サービスは非所有参照であり、呼び出し側がFrameより長い寿命を保証する。
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write SetEditorState;
  end;

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils, Winapi.Windows,
  Vcl.Graphics, MapRakuEditCommands, MapRakuGroupTransformCommands,
  MapRakuLayerGeometry;

{$R *.dfm}

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_EDIT = TColor($00303030);
  COLOR_HEADER = TColor($00292929);
  COLOR_LABEL = TColor($00BDBDBD);
  COLOR_TEXT = TColor($00EEEEEE);
  EDIT_HEIGHT = 25;
  MIN_OBJECT_SIZE = 1.0;

function UnicodeText(const CodePoints: array of Word): string;
var
  I: Integer;
begin
  SetLength(Result, Length(CodePoints));
  for I := 0 to High(CodePoints) do
    Result[I + 1] := Char(CodePoints[I]);
end;

constructor TMapRakuGeometryPresetCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPendingItemIndex := Ord(slgpCenter);
end;

procedure TMapRakuGeometryPresetCombo.CreateWnd;
var
  ChangeEvent: TNotifyEvent;
begin
  inherited CreateWnd;
  ChangeEvent := OnChange;
  OnChange := nil;
  try
    Items.BeginUpdate;
    try
      Items.Clear;
      Items.Add(UnicodeText([$5DE6, $4E0A]));
      Items.Add(UnicodeText([$4E0A, $4E2D, $592E]));
      Items.Add(UnicodeText([$53F3, $4E0A]));
      Items.Add(UnicodeText([$5DE6, $4E2D, $592E]));
      Items.Add(UnicodeText([$4E2D, $592E]));
      Items.Add(UnicodeText([$53F3, $4E2D, $592E]));
      Items.Add(UnicodeText([$5DE6, $4E0B]));
      Items.Add(UnicodeText([$4E0B, $4E2D, $592E]));
      Items.Add(UnicodeText([$53F3, $4E0B]));
      Items.Add(UnicodeText([$753B, $9762, $3044, $3063, $3071, $3044,
        $306B, $5F15, $304D, $5EF6, $3070, $3059]));
      ItemIndex := FPendingItemIndex;
    finally
      Items.EndUpdate;
    end;
  finally
    OnChange := ChangeEvent;
  end;
end;

procedure TMapRakuGeometryPresetCombo.SetPendingItemIndex(
  Value: Integer);
begin
  FPendingItemIndex := Value;
  if HandleAllocated then
    ItemIndex := Value;
end;

constructor TMapRakuGeometryPropertiesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  Height := MulDiv(207, CurrentPPI, 96);

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Caption := UnicodeText([$914D, $7F6E, $3068, $30B5, $30A4,
    $30BA]);
  FTitleLabel.Color := COLOR_HEADER;
  FTitleLabel.Font.Name := 'Segoe UI';
  FTitleLabel.Font.Height := -MulDiv(13, CurrentPPI, 96);
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Color := COLOR_TEXT;
  FTitleLabel.ParentColor := False;
  FTitleLabel.ParentFont := False;
  FTitleLabel.Layout := tlCenter;

  FXLabel := NewFieldLabel('X');
  FYLabel := NewFieldLabel('Y');
  FWidthLabel := NewFieldLabel(UnicodeText([$6A2A, $5E45]));
  FHeightLabel := NewFieldLabel(UnicodeText([$7E26, $5E45]));
  FXEdit := NewDarkEdit;
  FYEdit := NewDarkEdit;
  FWidthEdit := NewDarkEdit;
  FHeightEdit := NewDarkEdit;

  FPresetLabel := NewFieldLabel(UnicodeText([$914D, $7F6E, $30D7, $30EA,
    $30BB, $30C3, $30C8]));
  FPresetCombo := TMapRakuGeometryPresetCombo.Create(Self);
  FPresetCombo.Parent := Self;
  FPresetCombo.Style := csDropDownList;
  FPresetCombo.Color := COLOR_EDIT;
  FPresetCombo.Font.Name := 'Segoe UI';
  FPresetCombo.Font.Height := -MulDiv(12, CurrentPPI, 96);
  FPresetCombo.Font.Color := COLOR_TEXT;
  FPresetCombo.ParentFont := False;
  FPresetCombo.SetPendingItemIndex(Ord(slgpCenter));
  FPresetCombo.OnChange := PresetChanged;

  FApplyPresetButton := TButton.Create(Self);
  FApplyPresetButton.Parent := Self;
  FApplyPresetButton.Caption := UnicodeText([$9069, $7528]);
  FApplyPresetButton.OnClick := ApplyPresetClick;
  SetInputsEnabled(False, False);
end;

procedure TMapRakuGeometryPropertiesFrame.ApplyPreset(
  Value: TMapRakuGeometryPreset);
var
  Bounds: TRectF;
  CanvasHeight: Single;
  CanvasWidth: Single;
  Layers: TArray<TVectArtLayer>;
  Locked: Boolean;
  XValue: Single;
  YValue: Single;
begin
  if not SelectedGeometry(Layers, Bounds, Locked) or Locked or
    (FDocument.CanvasLayer = nil) then
    Exit;
  CanvasWidth := FDocument.CanvasLayer.Width;
  CanvasHeight := FDocument.CanvasLayer.Height;
  if (Value = slgpFillCanvas) and
    ((Bounds.Width <= 0.0001) or (Bounds.Height <= 0.0001)) then
    Exit;

  case Value of
    slgpTopLeft, slgpCenterLeft, slgpBottomLeft:
      XValue := -CanvasWidth * 0.5 + Bounds.Width * 0.5;
    slgpTopCenter, slgpCenter, slgpBottomCenter:
      XValue := 0;
  else
    XValue := CanvasWidth * 0.5 - Bounds.Width * 0.5;
  end;
  case Value of
    slgpTopLeft, slgpTopCenter, slgpTopRight:
      YValue := -CanvasHeight * 0.5 + Bounds.Height * 0.5;
    slgpCenterLeft, slgpCenter, slgpCenterRight:
      YValue := 0;
  else
    YValue := CanvasHeight * 0.5 - Bounds.Height * 0.5;
  end;

  FUpdating := True;
  try
    FXEdit.Text := FormatFloat('0.##', XValue);
    FYEdit.Text := FormatFloat('0.##', YValue);
    if Value = slgpFillCanvas then
    begin
      FXEdit.Text := '0';
      FYEdit.Text := '0';
      FWidthEdit.Text := FormatFloat('0.##', CanvasWidth);
      FHeightEdit.Text := FormatFloat('0.##', CanvasHeight);
    end
    else
    begin
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
    end;
  finally
    FUpdating := False;
  end;
  ApplyGeometry;
end;

procedure TMapRakuGeometryPropertiesFrame.ApplyPresetClick(
  Sender: TObject);
begin
  if InRange(FPresetCombo.PendingItemIndex,
    Ord(Low(TMapRakuGeometryPreset)),
    Ord(High(TMapRakuGeometryPreset))) then
    ApplyPreset(TMapRakuGeometryPreset(FPresetCombo.PendingItemIndex));
end;

procedure TMapRakuGeometryPropertiesFrame.ApplyGeometry;
var
  Bounds: TRectF;
  Command: TVectArtCompoundCommand;
  DegenerateSize: Boolean;
  DX: Single;
  DY: Single;
  HeightValue: Double;
  I: Integer;
  Layers: TArray<TVectArtLayer>;
  Locked: Boolean;
  NewBounds: TRectF;
  WidthValue: Double;
  XValue: Double;
  YValue: Double;
begin
  if FUpdating or not SelectedGeometry(Layers, Bounds, Locked) or Locked then
    Exit;
  if not TryStrToFloat(Trim(FXEdit.Text), XValue) or
    not TryStrToFloat(Trim(FYEdit.Text), YValue) or
    not TryStrToFloat(Trim(FWidthEdit.Text), WidthValue) or
    not TryStrToFloat(Trim(FHeightEdit.Text), HeightValue) then
  begin
    RefreshFromDocument;
    Exit;
  end;

  DegenerateSize := (Bounds.Width <= 0.0001) or
    (Bounds.Height <= 0.0001);
  DX := XValue - Bounds.CenterPoint.X;
  DY := YValue - Bounds.CenterPoint.Y;
  if DegenerateSize then
  begin
    if SameValue(DX, 0.0) and SameValue(DY, 0.0) then
      Exit;
  end
  else
  begin
    WidthValue := Max(WidthValue, MIN_OBJECT_SIZE);
    HeightValue := Max(HeightValue, MIN_OBJECT_SIZE);
    NewBounds := TRectF.Create(XValue - WidthValue * 0.5,
      YValue - HeightValue * 0.5, XValue + WidthValue * 0.5,
      YValue + HeightValue * 0.5);
    if SameValue(Bounds.Left, NewBounds.Left) and
      SameValue(Bounds.Top, NewBounds.Top) and
      SameValue(Bounds.Right, NewBounds.Right) and
      SameValue(Bounds.Bottom, NewBounds.Bottom) then
      Exit;
  end;

  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  FDocument.BeginUpdate;
  try
    for I := 0 to High(Layers) do
      if DegenerateSize then
      begin
        TranslateMapRakuLayer(Layers[I], DX, DY);
        if Command <> nil then
          Command.Add(TMapRakuTranslateLayerCommand.Create(FDocument,
            Layers[I], DX, DY));
      end
      else
      begin
        ScaleMapRakuLayer(Layers[I], Bounds, NewBounds);
        if Command <> nil then
          Command.Add(TMapRakuScaleLayerCommand.Create(FDocument,
            Layers[I], Bounds, NewBounds));
      end;
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
  RefreshFromDocument;
end;

procedure TMapRakuGeometryPropertiesFrame.EditExit(Sender: TObject);
begin
  ApplyGeometry;
end;

procedure TMapRakuGeometryPropertiesFrame.EditKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    ApplyGeometry;
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    RefreshFromDocument;
    Key := 0;
  end;
end;

procedure TMapRakuGeometryPropertiesFrame.FocusFirstInput;
begin
  if FXEdit.Enabled and FXEdit.CanFocus then
  begin
    FXEdit.SetFocus;
    FXEdit.SelectAll;
  end;
end;

function TMapRakuGeometryPropertiesFrame.NewDarkEdit: TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.AutoSize := False;
  Result.Height := MulDiv(EDIT_HEIGHT, CurrentPPI, 96);
  Result.Color := COLOR_EDIT;
  Result.Font.Name := 'Segoe UI';
  Result.Font.Height := -MulDiv(12, CurrentPPI, 96);
  Result.Font.Color := COLOR_TEXT;
  Result.ParentColor := False;
  Result.ParentFont := False;
  Result.OnExit := EditExit;
  Result.OnKeyDown := EditKeyDown;
end;

function TMapRakuGeometryPropertiesFrame.NewFieldLabel(
  const Caption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Caption := Caption;
  Result.Font.Name := 'Segoe UI';
  Result.Font.Height := -MulDiv(12, CurrentPPI, 96);
  Result.Font.Color := COLOR_LABEL;
  Result.ParentFont := False;
end;

procedure TMapRakuGeometryPropertiesFrame.RefreshFromDocument;
var
  Bounds: TRectF;
  Layers: TArray<TVectArtLayer>;
  Locked: Boolean;
  SizeEnabled: Boolean;
begin
  FUpdating := True;
  try
    if SelectedGeometry(Layers, Bounds, Locked) then
    begin
      FXEdit.Text := FormatFloat('0.##', Bounds.CenterPoint.X);
      FYEdit.Text := FormatFloat('0.##', Bounds.CenterPoint.Y);
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      SizeEnabled := (Bounds.Width > 0.0001) and
        (Bounds.Height > 0.0001);
      SetInputsEnabled(not Locked, not Locked and SizeEnabled);
    end
    else
    begin
      FXEdit.Text := '';
      FYEdit.Text := '';
      FWidthEdit.Text := '';
      FHeightEdit.Text := '';
      SetInputsEnabled(False, False);
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TMapRakuGeometryPropertiesFrame.PresetChanged(
  Sender: TObject);
var
  Bounds: TRectF;
  Layers: TArray<TVectArtLayer>;
  Locked: Boolean;
  SizeEnabled: Boolean;
begin
  FPresetCombo.SetPendingItemIndex(FPresetCombo.ItemIndex);
  if SelectedGeometry(Layers, Bounds, Locked) then
  begin
    SizeEnabled := (Bounds.Width > 0.0001) and
      (Bounds.Height > 0.0001);
    UpdatePresetEnabled(not Locked, not Locked and SizeEnabled);
  end
  else
    UpdatePresetEnabled(False, False);
end;

procedure TMapRakuGeometryPropertiesFrame.Resize;
var
  ColumnWidth: Integer;
  EditHeight: Integer;
  Margin: Integer;
  RightColumn: Integer;
begin
  inherited Resize;
  Margin := MulDiv(12, CurrentPPI, 96);
  EditHeight := MulDiv(EDIT_HEIGHT, CurrentPPI, 96);
  FTitleLabel.Font.Height := -MulDiv(13, CurrentPPI, 96);
  FPresetCombo.Font.Height := -MulDiv(12, CurrentPPI, 96);
  FXLabel.Font.Height := -MulDiv(12, CurrentPPI, 96);
  FYLabel.Font.Height := FXLabel.Font.Height;
  FWidthLabel.Font.Height := FXLabel.Font.Height;
  FHeightLabel.Font.Height := FXLabel.Font.Height;
  FPresetLabel.Font.Height := FXLabel.Font.Height;
  FXEdit.Font.Height := -MulDiv(12, CurrentPPI, 96);
  FYEdit.Font.Height := FXEdit.Font.Height;
  FWidthEdit.Font.Height := FXEdit.Font.Height;
  FHeightEdit.Font.Height := FXEdit.Font.Height;
  FTitleLabel.SetBounds(0, 0, ClientWidth, MulDiv(32, CurrentPPI, 96));
  ColumnWidth := Max((ClientWidth - MulDiv(36, CurrentPPI, 96)) div 2,
    MulDiv(48, CurrentPPI, 96));
  RightColumn := (ClientWidth div 2) + MulDiv(4, CurrentPPI, 96);
  FXLabel.SetBounds(Margin, MulDiv(42, CurrentPPI, 96), ColumnWidth,
    MulDiv(17, CurrentPPI, 96));
  FYLabel.SetBounds(RightColumn, MulDiv(42, CurrentPPI, 96), ColumnWidth,
    MulDiv(17, CurrentPPI, 96));
  FXEdit.SetBounds(Margin, MulDiv(59, CurrentPPI, 96), ColumnWidth, EditHeight);
  FYEdit.SetBounds(RightColumn, MulDiv(59, CurrentPPI, 96), ColumnWidth,
    EditHeight);
  FWidthLabel.SetBounds(Margin, MulDiv(91, CurrentPPI, 96), ColumnWidth,
    MulDiv(17, CurrentPPI, 96));
  FHeightLabel.SetBounds(RightColumn, MulDiv(91, CurrentPPI, 96), ColumnWidth,
    MulDiv(17, CurrentPPI, 96));
  FWidthEdit.SetBounds(Margin, MulDiv(108, CurrentPPI, 96), ColumnWidth,
    EditHeight);
  FHeightEdit.SetBounds(RightColumn, MulDiv(108, CurrentPPI, 96), ColumnWidth,
    EditHeight);
  FPresetLabel.SetBounds(Margin, MulDiv(142, CurrentPPI, 96), ColumnWidth,
    MulDiv(17, CurrentPPI, 96));
  FPresetCombo.SetBounds(Margin, MulDiv(159, CurrentPPI, 96),
    Max(ClientWidth - MulDiv(106, CurrentPPI, 96),
      MulDiv(80, CurrentPPI, 96)), EditHeight);
  FApplyPresetButton.SetBounds(
    Max(ClientWidth - MulDiv(86, CurrentPPI, 96), Margin),
    MulDiv(158, CurrentPPI, 96), MulDiv(74, CurrentPPI, 96),
    MulDiv(27, CurrentPPI, 96));
end;

function TMapRakuGeometryPropertiesFrame.SelectedGeometry(
  out Layers: TArray<TVectArtLayer>; out Bounds: TRectF;
  out Locked: Boolean): Boolean;
var
  CandidateBounds: TRectF;
  I: Integer;
  Layer: TVectArtLayer;
  LayerList: TList<TVectArtLayer>;
begin
  Result := False;
  Locked := False;
  Bounds := TRectF.Empty;
  Layers := nil;
  if FDocument = nil then
    Exit;
  LayerList := TList<TVectArtLayer>.Create;
  try
    if (FEditorState <> nil) and
      (FEditorState.OpenGroupChildCount = 1) and
      (FEditorState.OpenGroupChild <> nil) then
    begin
      Layer := FEditorState.OpenGroupChild;
      if TryGetMapRakuLayerBounds(Layer, CandidateBounds) then
      begin
        LayerList.Add(Layer);
        Bounds := CandidateBounds;
        Locked := Layer.Locked;
        Result := True;
      end;
    end
    else
      for I := 1 to FDocument.LayerCount - 1 do
        if FDocument.IsLayerSelected(I) then
        begin
          Layer := FDocument[I];
          if not TryGetMapRakuLayerBounds(Layer, CandidateBounds) then
            Continue;
          LayerList.Add(Layer);
          Locked := Locked or Layer.Locked;
          if not Result then
            Bounds := CandidateBounds
          else
          begin
            Bounds.Left := Min(Bounds.Left, CandidateBounds.Left);
            Bounds.Top := Min(Bounds.Top, CandidateBounds.Top);
            Bounds.Right := Max(Bounds.Right, CandidateBounds.Right);
            Bounds.Bottom := Max(Bounds.Bottom, CandidateBounds.Bottom);
          end;
          Result := True;
        end;
    Layers := LayerList.ToArray;
  finally
    LayerList.Free;
  end;
end;

procedure TMapRakuGeometryPropertiesFrame.SetDocument(
  const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  FDocument := Value;
  RefreshFromDocument;
end;

procedure TMapRakuGeometryPropertiesFrame.SetEditorState(
  const Value: TVectArtEditorState);
begin
  if FEditorState = Value then
    Exit;
  FEditorState := Value;
  RefreshFromDocument;
end;

procedure TMapRakuGeometryPropertiesFrame.SetInputsEnabled(
  Value, SizeEnabled: Boolean);
begin
  FXEdit.Enabled := Value;
  FYEdit.Enabled := Value;
  FWidthEdit.Enabled := SizeEnabled;
  FHeightEdit.Enabled := SizeEnabled;
  FPresetCombo.Enabled := Value;
  UpdatePresetEnabled(Value, SizeEnabled);
end;

procedure TMapRakuGeometryPropertiesFrame.UpdatePresetEnabled(
  Value, SizeEnabled: Boolean);
begin
  FApplyPresetButton.Enabled := Value and
    ((FPresetCombo.PendingItemIndex <> Ord(slgpFillCanvas)) or SizeEnabled);
end;

end.
