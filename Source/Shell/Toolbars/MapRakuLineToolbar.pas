// 選択種別に応じて線幅または文字フォントを常設し、Documentと履歴へ同期する。
unit MapRakuLineToolbar;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.StdCtrls, Vcl.AppEvnts, Vcl.Graphics,
  HorizontalTrackBarControl, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState, MapRakuLineStyleControls,
  MapRakuStrokeStyleCombo;

type
  TVectArtLineToolbarControl = class(TCustomControl)
  private
    FDocument: TVectArtDocument;
    FApplicationEvents: TApplicationEvents;
    FDetailsButton: TVectArtDarkButton;
    FDetailsPanel: TPanel;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    FFontFamilyCombo: TComboBox;
    FFontStyleButtons: array[TFontStyle] of TMapRakuTextStyleButton;
    FTextAlignmentButton: TMapRakuTextAlignmentButton;
    FTextAlignmentButtons: array[TMapRakuTextAlignment] of
      TMapRakuTextAlignmentButton;
    FTextAlignmentPanel: TPanel;
    FTextPathAttachmentButton: TMapRakuTextPathAttachmentButton;
    FTextPathAttachmentButtons: array[TMapRakuTextPathAttachment] of
      TMapRakuTextPathAttachmentButton;
    FTextPathAttachmentPanel: TPanel;
    FMifStrokeStyleCombo: TVectArtMifStrokeStyleCombo;
    FLineCapButtons: array[TVectArtLineCap] of TVectArtLineCapButton;
    FWidthModeButtons: array[TMapRakuStrokeWidthMode] of
      TMapRakuStrokeWidthModeButton;
    FStrokeWidthTrackBar: THorizontalTrackBarControl;
    FStrokeWidthEdit: TEdit;
    FTrackDocumentUpdateActive: Boolean;
    FTrackGestureActive: Boolean;
    FTrackStartIndices: TArray<Integer>;
    FTrackStartWidths: TArray<Single>;
    FUpdating: Boolean;
    procedure ApplyStrokeWidthInternal(Value: Single;
      RecordHistory: Boolean);
    procedure ApplicationIdle(Sender: TObject; var Done: Boolean);
    procedure BuildControls;
    procedure CommitTrackGesture;
    procedure EditExit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure FontFamilyChanged(Sender: TObject);
    procedure FontStyleClick(Sender: TObject);
    procedure TextAlignmentClick(Sender: TObject);
    procedure TextAlignmentPopupClick(Sender: TObject);
    procedure TextPathAttachmentClick(Sender: TObject);
    procedure TextPathAttachmentPopupClick(Sender: TObject);
    procedure DetailsClick(Sender: TObject);
    function IsTextAlignmentControl(Control: TControl): Boolean;
    function IsTextPathAttachmentControl(Control: TControl): Boolean;
    function IsDetailsControl(Control: TControl): Boolean;
    procedure LineCapClick(Sender: TObject);
    procedure WidthModeClick(Sender: TObject);
    function SelectedLineIndices: TArray<Integer>;
    function SelectedPathIndices: TArray<Integer>;
    function SelectedTextIndices: TArray<Integer>;
    function SelectedTextPathIndices: TArray<Integer>;
    function SelectionHasLockedLine: Boolean;
    function SelectionHasLockedText: Boolean;
    // 正の値はDocument直下、負の値は開いたグループ内の子位置として対象を返す。
    function SelectionLayer(Token: Integer): TVectArtLayer;
    function SelectionLayers(const Tokens: TArray<Integer>): TArray<TVectArtLayer>;
    function SelectionTextLayers(const Tokens: TArray<Integer>):
      TArray<TMapRakuTextLayer>;
    procedure StyleChanged(Sender: TObject);
    procedure TrackBarChanged(Sender: TObject);
    procedure TrackBarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TrackBarMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    // AHostへ接続したツールバーと、同じForm上の詳細パネルを生成する。AOwnerが両方を所有する。
    constructor CreateForHost(AOwner: TComponent; AHost: TWinControl);
    // 作成初期値または選択中の全Lineへ線端形状を適用し、必要なら履歴へ記録する。
    procedure ApplyLineCap(Value: TVectArtLineCap);
    // 作成初期値または選択中の全Lineへ線種を適用する。
    procedure ApplyMifStrokeStyle(Value: TVectArtMifStrokeStyle);
    // 作成初期値または選択中の全Lineへ線幅を適用する。
    procedure ApplyStrokeWidth(Value: Single);
    // 作成初期値または選択中の開いたPathへ均一／可変幅を適用する。
    procedure ApplyStrokeWidthMode(Value: TMapRakuStrokeWidthMode);
    // 選択中の全Textへフォントファミリーを適用する。
    procedure ApplyFontFamily(const Value: string);
    // 選択中の全Textへ1種類の文字装飾を追加または削除する。
    procedure ApplyFontStyle(Style: TFontStyle; Enabled: Boolean);
    // 選択中の全Textへ枠内配置を適用する。
    procedure ApplyTextAlignment(Value: TMapRakuTextAlignment);
    // 選択中の全文字パスへPathに接触させる文字セル面を適用する。
    procedure ApplyTextPathAttachment(
      Value: TMapRakuTextPathAttachment);
    // 選択中の全Textへ文字サイズ比率の字間または行間を適用する。
    procedure ApplyTextSpacing(IsLetterSpacing: Boolean; Ratio: Single);
    // EditorStateと現在選択から表示値、混在状態、有効状態を再同期する。
    procedure RefreshState;
    // 詳細パネル外へフォーカスが移っていればパネルを閉じる。
    procedure UpdateDetailsPanelFocus;
    // Documentは非所有参照。選択中の線属性の読書き対象となる。
    property Document: TVectArtDocument read FDocument write FDocument;
    // 指定した線端形状の選択ボタンを返す。戻り値の所有権はSelfが保持する。
    function LineCapButton(Value: TVectArtLineCap): TVectArtLineCapButton;
    function StrokeWidthModeButton(Value: TMapRakuStrokeWidthMode):
      TMapRakuStrokeWidthModeButton;
    // UIテストとHost側の配置確認に公開する所有Control。
    property DetailsButton: TVectArtDarkButton read FDetailsButton;
    property DetailsPanel: TPanel read FDetailsPanel;
    // EditHistoryとEditorStateは非所有参照。履歴記録と次回作成値の保持に使う。
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write FEditorState;
    property MifStrokeStyleCombo: TVectArtMifStrokeStyleCombo
      read FMifStrokeStyleCombo;
    // Text選択時に線幅UIと入れ替えて表示するフォント一覧。
    property FontFamilyCombo: TComboBox read FFontFamilyCombo;
    function FontStyleButton(Style: TFontStyle): TMapRakuTextStyleButton;
    property TextAlignmentButton: TMapRakuTextAlignmentButton
      read FTextAlignmentButton;
    property TextAlignmentPanel: TPanel read FTextAlignmentPanel;
    function TextAlignmentCell(Value: TMapRakuTextAlignment):
      TMapRakuTextAlignmentButton;
    property TextPathAttachmentButton: TMapRakuTextPathAttachmentButton
      read FTextPathAttachmentButton;
    property TextPathAttachmentPanel: TPanel read FTextPathAttachmentPanel;
    function TextPathAttachmentCell(Value: TMapRakuTextPathAttachment):
      TMapRakuTextPathAttachmentButton;
    // 線幅の常設UI。所有権はToolbarが保持する。
    property StrokeWidthTrackBar: THorizontalTrackBarControl
      read FStrokeWidthTrackBar;
    property StrokeWidthEdit: TEdit read FStrokeWidthEdit;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, Vcl.Forms,
  MapRakuEditCommands, MapRakuLineToolbarOperations,
  MapRakuTextToolbarOperations;

const
  COLOR_BACKGROUND = TColor($00282828);
  COLOR_EDIT = TColor($00353535);
  COLOR_LABEL = TColor($00C8C8C8);
  COLOR_TEXT = TColor($00EEEEEE);
  STROKE_WIDTH_SCALE = 10;
  STROKE_WIDTH_TRACK_MIN = 10;
  STROKE_WIDTH_TRACK_MAX = 1000;
  LINE_TOOLBAR_WIDTH = 350;
  TEXT_TOOLBAR_WIDTH = 420;

function UnicodeText(const CodePoints: array of Word): string;
var
  I: Integer;
begin
  SetLength(Result, Length(CodePoints));
  for I := 0 to High(CodePoints) do
    Result[I + 1] := Char(CodePoints[I]);
end;

constructor TVectArtLineToolbarControl.CreateForHost(AOwner: TComponent;
  AHost: TWinControl);
begin
  inherited Create(AOwner);
  Parent := AHost;
  Align := alRight;
  Width := MulDiv(LINE_TOOLBAR_WIDTH, CurrentPPI, 96);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  FApplicationEvents := TApplicationEvents.Create(Self);
  FApplicationEvents.OnIdle := ApplicationIdle;
  BuildControls;
  // Parent接続時のResizeは子Control生成前に発生するため、生成後にも必ず配置する。
  // これがないとTEditなどがVCL既定の位置と幅で左側へ残り、ほかの線設定を覆う。
  Resize;
  Visible := False;
end;

procedure TVectArtLineToolbarControl.ApplicationIdle(Sender: TObject;
  var Done: Boolean);
var
  ActiveControl: TWinControl;
  ParentForm: TCustomForm;
begin
  UpdateDetailsPanelFocus;
  ParentForm := GetParentForm(Self);
  if (FTextAlignmentPanel <> nil) and FTextAlignmentPanel.Visible then
  begin
    if (ParentForm = nil) or (Screen.ActiveForm <> ParentForm) then
      FTextAlignmentPanel.Visible := False
    else
    begin
      ActiveControl := ParentForm.ActiveControl;
      if (ActiveControl <> FTextAlignmentButton) and
        not IsTextAlignmentControl(ActiveControl) then
        FTextAlignmentPanel.Visible := False;
    end;
  end;
  if (FTextPathAttachmentPanel <> nil) and
    FTextPathAttachmentPanel.Visible then
  begin
    if (ParentForm = nil) or (Screen.ActiveForm <> ParentForm) then
      FTextPathAttachmentPanel.Visible := False
    else
    begin
      ActiveControl := ParentForm.ActiveControl;
      if (ActiveControl <> FTextPathAttachmentButton) and
        not IsTextPathAttachmentControl(ActiveControl) then
        FTextPathAttachmentPanel.Visible := False;
    end;
  end;
end;

procedure TVectArtLineToolbarControl.UpdateDetailsPanelFocus;
var
  ActiveControl: TWinControl;
  ParentForm: TCustomForm;
begin
  if (FDetailsPanel = nil) or not FDetailsPanel.Visible then Exit;
  ParentForm := GetParentForm(Self);
  if (ParentForm = nil) or (Screen.ActiveForm <> ParentForm) then
  begin
    FDetailsPanel.Visible := False;
    Exit;
  end;
  ActiveControl := ParentForm.ActiveControl;
  if (ActiveControl <> FDetailsButton) and
    not IsDetailsControl(ActiveControl) then
    FDetailsPanel.Visible := False;
end;

procedure TVectArtLineToolbarControl.BuildControls;
var
  Attachment: TMapRakuTextPathAttachment;
  Cap: TVectArtLineCap;
  CaptionLabel: TLabel;
  ParentForm: TCustomForm;
  Style: TFontStyle;
  TextAlignment: TMapRakuTextAlignment;
  WidthMode: TMapRakuStrokeWidthMode;
  function Logical(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, CurrentPPI, 96);
  end;
begin
  FFontFamilyCombo := TComboBox.Create(Self);
  FFontFamilyCombo.Parent := Self;
  FFontFamilyCombo.Style := csDropDownList;
  FFontFamilyCombo.DropDownCount := 20;
  FFontFamilyCombo.Color := COLOR_EDIT;
  FFontFamilyCombo.Font.Color := COLOR_TEXT;
  FFontFamilyCombo.Font.Name := 'Segoe UI';
  FFontFamilyCombo.Font.Height := -Logical(12);
  FFontFamilyCombo.Items.Assign(Screen.Fonts);
  FFontFamilyCombo.Sorted := True;
  FFontFamilyCombo.OnChange := FontFamilyChanged;
  FFontFamilyCombo.Visible := False;
  for Style := Low(TFontStyle) to High(TFontStyle) do
  begin
    FFontStyleButtons[Style] := TMapRakuTextStyleButton.Create(Self);
    FFontStyleButtons[Style].Parent := Self;
    FFontStyleButtons[Style].Style := Style;
    FFontStyleButtons[Style].Font.Style := [Style];
    FFontStyleButtons[Style].OnClick := FontStyleClick;
    FFontStyleButtons[Style].Visible := False;
  end;
  FFontStyleButtons[fsBold].Caption := 'B';
  FFontStyleButtons[fsItalic].Caption := 'I';
  FFontStyleButtons[fsUnderline].Caption := 'U';
  FFontStyleButtons[fsStrikeOut].Caption := 'S';

  FTextAlignmentButton := TMapRakuTextAlignmentButton.Create(Self);
  FTextAlignmentButton.Parent := Self;
  FTextAlignmentButton.OnClick := TextAlignmentPopupClick;
  FTextAlignmentButton.ShowHint := True;
  FTextAlignmentButton.Hint := UnicodeText([$914D, $7F6E]);
  FTextAlignmentButton.Visible := False;

  FTextPathAttachmentButton :=
    TMapRakuTextPathAttachmentButton.Create(Self);
  FTextPathAttachmentButton.Parent := Self;
  FTextPathAttachmentButton.OnClick := TextPathAttachmentPopupClick;
  FTextPathAttachmentButton.ShowHint := True;
  FTextPathAttachmentButton.Hint := UnicodeText(
    [$30D1, $30B9, $3078, $63A5, $89E6, $3059, $308B, $9762]);
  FTextPathAttachmentButton.Visible := False;

  FStrokeWidthTrackBar := THorizontalTrackBarControl.Create(Self);
  FStrokeWidthTrackBar.Parent := Self;
  FStrokeWidthTrackBar.BackgroundColor := COLOR_BACKGROUND;
  FStrokeWidthTrackBar.ChannelColor := TColor($00505050);
  FStrokeWidthTrackBar.FillColor := TColor($00D77800);
  FStrokeWidthTrackBar.ThumbColor := COLOR_EDIT;
  FStrokeWidthTrackBar.ThumbBorderColor := COLOR_TEXT;
  FStrokeWidthTrackBar.ShowTicks := False;
  FStrokeWidthTrackBar.SetRange(STROKE_WIDTH_TRACK_MIN,
    STROKE_WIDTH_TRACK_MAX);
  FStrokeWidthTrackBar.SmallChange := 10;
  FStrokeWidthTrackBar.LargeChange := 100;
  FStrokeWidthTrackBar.OnChange := TrackBarChanged;
  FStrokeWidthTrackBar.OnMouseDown := TrackBarMouseDown;
  FStrokeWidthTrackBar.OnMouseUp := TrackBarMouseUp;

  FStrokeWidthEdit := TEdit.Create(Self);
  FStrokeWidthEdit.Parent := Self;
  FStrokeWidthEdit.Color := COLOR_EDIT;
  FStrokeWidthEdit.Font.Color := COLOR_TEXT;
  FStrokeWidthEdit.Font.Name := 'Segoe UI';
  FStrokeWidthEdit.Font.Height := -Logical(12);
  FStrokeWidthEdit.OnExit := EditExit;
  FStrokeWidthEdit.OnKeyDown := EditKeyDown;

  for WidthMode := Low(TMapRakuStrokeWidthMode) to
    High(TMapRakuStrokeWidthMode) do
  begin
    FWidthModeButtons[WidthMode] :=
      TMapRakuStrokeWidthModeButton.Create(Self);
    FWidthModeButtons[WidthMode].Parent := Self;
    FWidthModeButtons[WidthMode].Mode := WidthMode;
    FWidthModeButtons[WidthMode].OnClick := WidthModeClick;
    FWidthModeButtons[WidthMode].ShowHint := True;
  end;
  FWidthModeButtons[slwmUniform].Hint :=
    UnicodeText([$5747, $4E00, $5E45]);
  FWidthModeButtons[slwmVariable].Hint :=
    UnicodeText([$53EF, $5909, $5E45]);
  FWidthModeButtons[slwmUniform].Selected := True;

  FMifStrokeStyleCombo := TVectArtMifStrokeStyleCombo.Create(Self);
  FMifStrokeStyleCombo.Parent := Self;
  FMifStrokeStyleCombo.Style := csOwnerDrawFixed;
  FMifStrokeStyleCombo.ItemHeight := Logical(22);
  FMifStrokeStyleCombo.DropDownCount := 9;
  FMifStrokeStyleCombo.Color := COLOR_EDIT;
  FMifStrokeStyleCombo.Font.Color := COLOR_TEXT;
  FMifStrokeStyleCombo.Font.Name := 'Segoe UI';
  FMifStrokeStyleCombo.Font.Height := -Logical(12);
  FMifStrokeStyleCombo.OnChange := StyleChanged;

  FDetailsButton := TVectArtDarkButton.Create(Self);
  FDetailsButton.Parent := Self;
  FDetailsButton.Caption := UnicodeText([$8A73, $7D30]);
  FDetailsButton.OnClick := DetailsClick;

  ParentForm := GetParentForm(Self);
  FDetailsPanel := TPanel.Create(Self);
  FDetailsPanel.Parent := ParentForm;
  FDetailsPanel.BevelOuter := bvRaised;
  FDetailsPanel.Color := COLOR_BACKGROUND;
  FDetailsPanel.ParentBackground := False;
  FDetailsPanel.SetBounds(0, 0, Logical(420), Logical(96));
  FDetailsPanel.Visible := False;

  FTextAlignmentPanel := TPanel.Create(Self);
  FTextAlignmentPanel.Parent := ParentForm;
  FTextAlignmentPanel.BevelOuter := bvRaised;
  FTextAlignmentPanel.Color := COLOR_BACKGROUND;
  FTextAlignmentPanel.ParentBackground := False;
  FTextAlignmentPanel.SetBounds(0, 0, Logical(112), Logical(106));
  FTextAlignmentPanel.Visible := False;
  for TextAlignment := Low(TMapRakuTextAlignment) to
    High(TMapRakuTextAlignment) do
  begin
    FTextAlignmentButtons[TextAlignment] :=
      TMapRakuTextAlignmentButton.Create(Self);
    FTextAlignmentButtons[TextAlignment].Parent := FTextAlignmentPanel;
    FTextAlignmentButtons[TextAlignment].Alignment := TextAlignment;
    FTextAlignmentButtons[TextAlignment].SetBounds(
      Logical(5 + (Ord(TextAlignment) mod 3) * 35),
      Logical(5 + (Ord(TextAlignment) div 3) * 32), Logical(32), Logical(29));
    FTextAlignmentButtons[TextAlignment].OnClick := TextAlignmentClick;
    // 全体枠フィット中は上下方向の余白がないため、中段の左右配置だけを操作可能にする。
    FTextAlignmentButtons[TextAlignment].Enabled :=
      (Ord(TextAlignment) div 3) = 1;
  end;

  FTextPathAttachmentPanel := TPanel.Create(Self);
  FTextPathAttachmentPanel.Parent := ParentForm;
  FTextPathAttachmentPanel.BevelOuter := bvRaised;
  FTextPathAttachmentPanel.Color := COLOR_BACKGROUND;
  FTextPathAttachmentPanel.ParentBackground := False;
  FTextPathAttachmentPanel.SetBounds(0, 0, Logical(77), Logical(69));
  FTextPathAttachmentPanel.Visible := False;
  for Attachment := Low(TMapRakuTextPathAttachment) to
    High(TMapRakuTextPathAttachment) do
  begin
    FTextPathAttachmentButtons[Attachment] :=
      TMapRakuTextPathAttachmentButton.Create(Self);
    FTextPathAttachmentButtons[Attachment].Parent :=
      FTextPathAttachmentPanel;
    FTextPathAttachmentButtons[Attachment].Attachment := Attachment;
    FTextPathAttachmentButtons[Attachment].SetBounds(
      Logical(5 + (Ord(Attachment) mod 2) * 35),
      Logical(5 + (Ord(Attachment) div 2) * 32), Logical(32), Logical(29));
    FTextPathAttachmentButtons[Attachment].OnClick :=
      TextPathAttachmentClick;
  end;

  // 線幅は即時操作用にツールバーへ残し、低頻度項目だけを詳細へ収容する。
  FMifStrokeStyleCombo.Parent := FDetailsPanel;
  FMifStrokeStyleCombo.SetBounds(Logical(78), Logical(8), Logical(260),
    Logical(25));

  CaptionLabel := TLabel.Create(Self);
  CaptionLabel.Parent := FDetailsPanel;
  CaptionLabel.Caption := UnicodeText([$7A2E, $985E]);
  CaptionLabel.Font.Name := 'Segoe UI';
  CaptionLabel.Font.Height := -Logical(12);
  CaptionLabel.Font.Color := COLOR_LABEL;
  CaptionLabel.SetBounds(Logical(12), Logical(13), Logical(40), Logical(20));

  CaptionLabel := TLabel.Create(Self);
  CaptionLabel.Parent := FDetailsPanel;
  CaptionLabel.Caption := UnicodeText([$5148, $7AEF, $5F62, $72B6]);
  CaptionLabel.Font.Name := 'Segoe UI';
  CaptionLabel.Font.Height := -Logical(12);
  CaptionLabel.Font.Color := COLOR_LABEL;
  CaptionLabel.SetBounds(Logical(12), Logical(60), Logical(60), Logical(20));

  for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
  begin
    FLineCapButtons[Cap] := TVectArtLineCapButton.Create(Self);
    FLineCapButtons[Cap].Parent := FDetailsPanel;
    FLineCapButtons[Cap].LineCap := Cap;
    FLineCapButtons[Cap].SetBounds(Logical(78 + Ord(Cap) * 46), Logical(51),
      Logical(40), Logical(34));
    FLineCapButtons[Cap].OnClick := LineCapClick;
    FLineCapButtons[Cap].ShowHint := True;
  end;
  FLineCapButtons[vlcSquare].Hint := UnicodeText([$89D2, $578B]);
  FLineCapButtons[vlcRound].Hint := UnicodeText([$4E38, $578B]);
  FLineCapButtons[vlcTriangle].Hint := UnicodeText([$4E09, $89D2, $578B]);
  FLineCapButtons[vlcSquare].Selected := True;

end;

procedure TVectArtLineToolbarControl.ApplyFontStyle(Style: TFontStyle;
  Enabled: Boolean);
var
  Indices: TArray<Integer>;
begin
  if FUpdating then
    Exit;
  Indices := SelectedTextIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    ApplyMapRakuToolbarFontStyle(FDocument, FEditHistory,
      SelectionTextLayers(Indices),
      Style, Enabled);
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyTextAlignment(
  Value: TMapRakuTextAlignment);
var
  Indices: TArray<Integer>;
begin
  if FUpdating then
    Exit;
  Indices := SelectedTextIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    ApplyMapRakuToolbarTextAlignment(FDocument, FEditHistory,
      SelectionTextLayers(Indices),
      Value);
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyTextPathAttachment(
  Value: TMapRakuTextPathAttachment);
var
  Indices: TArray<Integer>;
begin
  if FUpdating then
    Exit;
  Indices := SelectedTextPathIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    ApplyMapRakuToolbarTextPathAttachment(FDocument, FEditHistory,
      SelectionTextLayers(Indices), Value);
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyTextSpacing(
  IsLetterSpacing: Boolean; Ratio: Single);
var
  Indices: TArray<Integer>;
begin
  if FUpdating then
    Exit;
  Indices := SelectedTextIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    ApplyMapRakuToolbarTextSpacing(FDocument, FEditHistory,
      SelectionTextLayers(Indices),
      IsLetterSpacing, Ratio);
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyFontFamily(const Value: string);
var
  Indices: TArray<Integer>;
begin
  if FUpdating or (Trim(Value) = '') then
    Exit;
  Indices := SelectedTextIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    ApplyMapRakuToolbarFontFamily(FDocument, FEditHistory,
      SelectionTextLayers(Indices),
      Value);
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyLineCap(Value: TVectArtLineCap);
var
  Indices: TArray<Integer>;
begin
  if FUpdating then
    Exit;
  Indices := SelectedLineIndices;
  if (Length(Indices) > 0) and SelectionHasLockedLine then
    Exit;
  FUpdating := True;
  try
    ApplyMapRakuToolbarLineCap(FDocument, FEditHistory,
      SelectionLayers(Indices), Value);
    if FEditorState <> nil then
      FEditorState.LineCap := Value;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyMifStrokeStyle(
  Value: TVectArtMifStrokeStyle);
var
  Indices: TArray<Integer>;
begin
  if FUpdating then
    Exit;
  Indices := SelectedLineIndices;
  if (Length(Indices) > 0) and SelectionHasLockedLine then
    Exit;
  FUpdating := True;
  try
    ApplyMapRakuToolbarLineStyle(FDocument, FEditHistory,
      SelectionLayers(Indices),
      Value);
    if FEditorState <> nil then
      FEditorState.LineMifStrokeStyle := Value;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyStrokeWidth(Value: Single);
begin
  ApplyStrokeWidthInternal(Value, True);
end;

procedure TVectArtLineToolbarControl.ApplyStrokeWidthMode(
  Value: TMapRakuStrokeWidthMode);
var
  Indices: TArray<Integer>;
begin
  if FUpdating then
    Exit;
  Indices := SelectedPathIndices;
  if (Length(Indices) > 0) and SelectionHasLockedLine then
    Exit;
  FUpdating := True;
  try
    ApplyMapRakuToolbarWidthMode(FDocument, FEditHistory,
      SelectionLayers(Indices),
      Value);
    if FEditorState <> nil then
      FEditorState.StrokeWidthMode := Value;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyStrokeWidthInternal(Value: Single;
  RecordHistory: Boolean);
var
  Indices: TArray<Integer>;
begin
  if FUpdating then
    Exit;
  Value := Max(Value, 0.1);
  Indices := SelectedLineIndices;
  if (Length(Indices) > 0) and SelectionHasLockedLine then
    Exit;
  FUpdating := True;
  try
    ApplyMapRakuToolbarLineWidth(FDocument, FEditHistory,
      SelectionLayers(Indices),
      Value, RecordHistory);
    if (FEditorState <> nil) and
      (RecordHistory or (Length(Indices) = 0)) then
      FEditorState.LineStrokeWidth := Value;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.CommitTrackGesture;
var
  Color: TColor;
  FinalWidth: Single;
  HasFinalWidth: Boolean;
  Indices: TArray<Integer>;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
begin
  if not FTrackGestureActive then
    Exit;
  FinalWidth := 0;
  FTrackGestureActive := False;
  RecordMapRakuToolbarLineWidths(FDocument, FEditHistory,
    SelectionLayers(FTrackStartIndices), FTrackStartWidths);
  Indices := SelectedLineIndices;
  HasFinalWidth := (FDocument <> nil) and (Length(Indices) > 0);
  if HasFinalWidth then
    TryReadMapRakuToolbarLine(SelectionLayer(Indices[0]), Color, FinalWidth,
      Style, LineCap);
  FTrackStartIndices := nil;
  FTrackStartWidths := nil;
  if FTrackDocumentUpdateActive then
  begin
    FTrackDocumentUpdateActive := False;
    FDocument.EndInteractiveUpdate;
  end;
  if (FEditorState <> nil) and HasFinalWidth then
    FEditorState.LineStrokeWidth := FinalWidth;
end;

procedure TVectArtLineToolbarControl.EditExit(Sender: TObject);
var
  Value: Single;
begin
  if FUpdating then
    Exit;
  if TryStrToFloat(Trim(FStrokeWidthEdit.Text), Value) and (Value > 0) then
    ApplyStrokeWidth(Value)
  else
    RefreshState;
end;

procedure TVectArtLineToolbarControl.EditKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    EditExit(Sender);
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    RefreshState;
    Key := 0;
  end;
end;

procedure TVectArtLineToolbarControl.FontFamilyChanged(Sender: TObject);
begin
  if FUpdating or (FFontFamilyCombo.ItemIndex < 0) then
    Exit;
  ApplyFontFamily(FFontFamilyCombo.Items[FFontFamilyCombo.ItemIndex]);
end;

procedure TVectArtLineToolbarControl.FontStyleClick(Sender: TObject);
var
  Button: TMapRakuTextStyleButton;
begin
  if FUpdating or not (Sender is TMapRakuTextStyleButton) then
    Exit;
  Button := TMapRakuTextStyleButton(Sender);
  ApplyFontStyle(Button.Style, not Button.Selected);
end;

procedure TVectArtLineToolbarControl.TextAlignmentClick(Sender: TObject);
begin
  if FUpdating or not (Sender is TMapRakuTextAlignmentButton) then
    Exit;
  ApplyTextAlignment(TMapRakuTextAlignmentButton(Sender).Alignment);
  FTextAlignmentPanel.Visible := False;
end;

procedure TVectArtLineToolbarControl.TextAlignmentPopupClick(
  Sender: TObject);
var
  Position: TPoint;
begin
  if (FTextAlignmentPanel = nil) or
    (FTextAlignmentPanel.Parent = nil) then
    Exit;
  if FTextAlignmentPanel.Visible then
  begin
    FTextAlignmentPanel.Visible := False;
    Exit;
  end;
  FTextPathAttachmentPanel.Visible := False;
  Position := FTextAlignmentButton.ClientToScreen(Point(
    FTextAlignmentButton.Width - FTextAlignmentPanel.Width,
    FTextAlignmentButton.Height + 2));
  Position := FTextAlignmentPanel.Parent.ScreenToClient(Position);
  FTextAlignmentPanel.SetBounds(Position.X, Position.Y,
    FTextAlignmentPanel.Width, FTextAlignmentPanel.Height);
  FTextAlignmentPanel.BringToFront;
  FTextAlignmentPanel.Visible := True;
end;

procedure TVectArtLineToolbarControl.TextPathAttachmentClick(
  Sender: TObject);
begin
  if FUpdating or
    not (Sender is TMapRakuTextPathAttachmentButton) then
    Exit;
  ApplyTextPathAttachment(
    TMapRakuTextPathAttachmentButton(Sender).Attachment);
  FTextPathAttachmentPanel.Visible := False;
end;

procedure TVectArtLineToolbarControl.TextPathAttachmentPopupClick(
  Sender: TObject);
var
  Position: TPoint;
begin
  if (FTextPathAttachmentPanel = nil) or
    (FTextPathAttachmentPanel.Parent = nil) then
    Exit;
  if FTextPathAttachmentPanel.Visible then
  begin
    FTextPathAttachmentPanel.Visible := False;
    Exit;
  end;
  FTextAlignmentPanel.Visible := False;
  Position := FTextPathAttachmentButton.ClientToScreen(Point(
    FTextPathAttachmentButton.Width - FTextPathAttachmentPanel.Width,
    FTextPathAttachmentButton.Height + 2));
  Position := FTextPathAttachmentPanel.Parent.ScreenToClient(Position);
  FTextPathAttachmentPanel.SetBounds(Position.X, Position.Y,
    FTextPathAttachmentPanel.Width, FTextPathAttachmentPanel.Height);
  FTextPathAttachmentPanel.BringToFront;
  FTextPathAttachmentPanel.Visible := True;
end;

function TVectArtLineToolbarControl.IsTextAlignmentControl(
  Control: TControl): Boolean;
begin
  Result := False;
  while Control <> nil do
  begin
    if Control = FTextAlignmentPanel then
      Exit(True);
    Control := Control.Parent;
  end;
end;

function TVectArtLineToolbarControl.IsTextPathAttachmentControl(
  Control: TControl): Boolean;
begin
  Result := False;
  while Control <> nil do
  begin
    if Control = FTextPathAttachmentPanel then
      Exit(True);
    Control := Control.Parent;
  end;
end;

function TVectArtLineToolbarControl.FontStyleButton(
  Style: TFontStyle): TMapRakuTextStyleButton;
begin
  Result := FFontStyleButtons[Style];
end;

function TVectArtLineToolbarControl.TextAlignmentCell(
  Value: TMapRakuTextAlignment): TMapRakuTextAlignmentButton;
begin
  Result := FTextAlignmentButtons[Value];
end;

function TVectArtLineToolbarControl.TextPathAttachmentCell(
  Value: TMapRakuTextPathAttachment):
  TMapRakuTextPathAttachmentButton;
begin
  Result := FTextPathAttachmentButtons[Value];
end;

procedure TVectArtLineToolbarControl.DetailsClick(Sender: TObject);
var
  Position: TPoint;
begin
  if (FDetailsPanel = nil) or (FDetailsPanel.Parent = nil) then
    Exit;
  if FDetailsPanel.Visible then
  begin
    FDetailsPanel.Visible := False;
    Exit;
  end;
  Position := FDetailsButton.ClientToScreen(Point(FDetailsButton.Width -
    FDetailsPanel.Width, FDetailsButton.Height + 2));
  Position := FDetailsPanel.Parent.ScreenToClient(Position);
  FDetailsPanel.SetBounds(Position.X, Position.Y, FDetailsPanel.Width,
    FDetailsPanel.Height);
  FDetailsPanel.BringToFront;
  FDetailsPanel.Visible := True;
end;

function TVectArtLineToolbarControl.IsDetailsControl(
  Control: TControl): Boolean;
begin
  Result := False;
  while Control <> nil do
  begin
    if Control = FDetailsPanel then Exit(True);
    Control := Control.Parent;
  end;
end;

procedure TVectArtLineToolbarControl.LineCapClick(Sender: TObject);
begin
  if FUpdating or not (Sender is TVectArtLineCapButton) then
    Exit;
  ApplyLineCap(TVectArtLineCapButton(Sender).LineCap);
end;

procedure TVectArtLineToolbarControl.WidthModeClick(Sender: TObject);
begin
  if FUpdating or
    not (Sender is TMapRakuStrokeWidthModeButton) then
    Exit;
  ApplyStrokeWidthMode(TMapRakuStrokeWidthModeButton(Sender).Mode);
end;

function TVectArtLineToolbarControl.LineCapButton(
  Value: TVectArtLineCap): TVectArtLineCapButton;
begin
  Result := FLineCapButtons[Value];
end;

function TVectArtLineToolbarControl.StrokeWidthModeButton(
  Value: TMapRakuStrokeWidthMode):
  TMapRakuStrokeWidthModeButton;
begin
  Result := FWidthModeButtons[Value];
end;

procedure TVectArtLineToolbarControl.Paint;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -MulDiv(12, CurrentPPI, 96);
  Canvas.Font.Color := COLOR_TEXT;
  if (FFontFamilyCombo <> nil) and FFontFamilyCombo.Visible then
    Canvas.TextOut(MulDiv(8, CurrentPPI, 96), MulDiv(13, CurrentPPI, 96),
      UnicodeText([$30D5, $30A9, $30F3, $30C8]))
  else
    Canvas.TextOut(MulDiv(8, CurrentPPI, 96), MulDiv(13, CurrentPPI, 96),
      UnicodeText([$592A, $3055]));
end;

procedure TVectArtLineToolbarControl.RefreshState;
var
  Alignment: TMapRakuTextAlignment;
  AlignmentValue: TMapRakuTextAlignment;
  Attachment: TMapRakuTextPathAttachment;
  AttachmentValue: TMapRakuTextPathAttachment;
  AllRegularTexts: Boolean;
  AllTextPaths: Boolean;
  Color: TColor;
  CommonAlignment: Boolean;
  CommonAttachment: Boolean;
  CommonFontFamily: Boolean;
  CommonStyle: Boolean;
  CommonLineCap: Boolean;
  CommonWidthMode: Boolean;
  CommonWidth: Boolean;
  Cap: TVectArtLineCap;
  CurrentLineCap: TVectArtLineCap;
  CurrentStyle: TVectArtMifStrokeStyle;
  CurrentWidth: Single;
  CurrentWidthMode: TMapRakuStrokeWidthMode;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLayer;
  LineCapValue: TVectArtLineCap;
  Locked: Boolean;
  Mode: TMapRakuStrokeWidthMode;
  PathIndices: TArray<Integer>;
  StyleValue: TVectArtMifStrokeStyle;
  SupportsLineCap: Boolean;
  SupportsWidthMode: Boolean;
  Style: TFontStyle;
  TextIndices: TArray<Integer>;
  TextPathIndices: TArray<Integer>;
  UseLineToolDefaults: Boolean;
  FontFamilyValue: string;
  WidthValue: Single;
  WidthModeValue: TMapRakuStrokeWidthMode;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    // 自由線の作成中は選択オブジェクトの属性より、これから描く線の設定を優先する。
    // 選択が残ったままツールを切り替えても、太さUIを隠さない。
    UseLineToolDefaults := (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetLine, vetFreehand, vetPath]);
    if UseLineToolDefaults then
      TextIndices := nil
    else
      TextIndices := SelectedTextIndices;
    if Length(TextIndices) > 0 then
    begin
      TextPathIndices := SelectedTextPathIndices;
      AllTextPaths := Length(TextPathIndices) = Length(TextIndices);
      AllRegularTexts := True;
      for I := 0 to High(TextIndices) do
        AllRegularTexts := AllRegularTexts and
          not (SelectionLayer(TextIndices[I]) is TMapRakuTextPathLayer);
      Width := MulDiv(TEXT_TOOLBAR_WIDTH, CurrentPPI, 96);
      Visible := True;
      FDetailsPanel.Visible := False;
      FFontFamilyCombo.Visible := True;
      FStrokeWidthEdit.Visible := False;
      FStrokeWidthTrackBar.Visible := False;
      FDetailsButton.Visible := False;
      for Mode := Low(TMapRakuStrokeWidthMode) to
        High(TMapRakuStrokeWidthMode) do
        FWidthModeButtons[Mode].Visible := False;
      FTextAlignmentButton.Visible := AllRegularTexts;
      FTextPathAttachmentButton.Visible := AllTextPaths;
      if not AllRegularTexts then
        FTextAlignmentPanel.Visible := False;
      if not AllTextPaths then
        FTextPathAttachmentPanel.Visible := False;
      for Style := Low(TFontStyle) to High(TFontStyle) do
        FFontStyleButtons[Style].Visible := True;
      FontFamilyValue := TMapRakuTextLayer(
        SelectionLayer(TextIndices[0])).FontFamily;
      CommonFontFamily := True;
      for I := 1 to High(TextIndices) do
      begin
        CommonFontFamily := CommonFontFamily and SameText(FontFamilyValue,
          TMapRakuTextLayer(SelectionLayer(TextIndices[I])).FontFamily);
      end;
      if CommonFontFamily then
        FFontFamilyCombo.ItemIndex :=
          FFontFamilyCombo.Items.IndexOf(FontFamilyValue)
      else
        FFontFamilyCombo.ItemIndex := -1;
      FFontFamilyCombo.Enabled := not SelectionHasLockedText;
      if AllRegularTexts then
      begin
        AlignmentValue := TMapRakuTextLayer(
          SelectionLayer(TextIndices[0])).Alignment;
        CommonAlignment := True;
        for I := 1 to High(TextIndices) do
          CommonAlignment := CommonAlignment and
            (AlignmentValue = TMapRakuTextLayer(
              SelectionLayer(TextIndices[I])).Alignment);
        FTextAlignmentButton.Enabled := not SelectionHasLockedText;
        FTextAlignmentButton.Mixed := not CommonAlignment;
        if CommonAlignment then
          FTextAlignmentButton.Alignment := AlignmentValue;
        for Alignment := Low(TMapRakuTextAlignment) to
          High(TMapRakuTextAlignment) do
        begin
          FTextAlignmentButtons[Alignment].Enabled :=
            (not SelectionHasLockedText) and
            ((Ord(Alignment) div 3) = 1);
          FTextAlignmentButtons[Alignment].Selected := CommonAlignment and
            (Alignment = AlignmentValue);
        end;
      end;
      if AllTextPaths then
      begin
        AttachmentValue := TMapRakuTextPathLayer(
          SelectionLayer(TextPathIndices[0])).Attachment;
        CommonAttachment := True;
        for I := 1 to High(TextPathIndices) do
          CommonAttachment := CommonAttachment and
            (AttachmentValue = TMapRakuTextPathLayer(
              SelectionLayer(TextPathIndices[I])).Attachment);
        FTextPathAttachmentButton.Enabled := not SelectionHasLockedText;
        FTextPathAttachmentButton.Mixed := not CommonAttachment;
        if CommonAttachment then
          FTextPathAttachmentButton.Attachment := AttachmentValue;
        for Attachment := Low(TMapRakuTextPathAttachment) to
          High(TMapRakuTextPathAttachment) do
        begin
          FTextPathAttachmentButtons[Attachment].Enabled :=
            not SelectionHasLockedText;
          FTextPathAttachmentButtons[Attachment].Selected :=
            CommonAttachment and (Attachment = AttachmentValue);
        end;
      end;
      for Style := Low(TFontStyle) to High(TFontStyle) do
      begin
        FFontStyleButtons[Style].Selected := True;
        for I := 0 to High(TextIndices) do
          FFontStyleButtons[Style].Selected :=
            FFontStyleButtons[Style].Selected and
            (Style in TMapRakuTextLayer(
              SelectionLayer(TextIndices[I])).FontStyle);
        FFontStyleButtons[Style].Enabled := not SelectionHasLockedText;
      end;
    end
    else
    begin
      Width := MulDiv(LINE_TOOLBAR_WIDTH, CurrentPPI, 96);
      FFontFamilyCombo.Visible := False;
      FTextAlignmentButton.Visible := False;
      FTextAlignmentPanel.Visible := False;
      FTextPathAttachmentButton.Visible := False;
      FTextPathAttachmentPanel.Visible := False;
      for Style := Low(TFontStyle) to High(TFontStyle) do
        FFontStyleButtons[Style].Visible := False;
      FStrokeWidthEdit.Visible := True;
      FStrokeWidthTrackBar.Visible := True;
      FDetailsButton.Visible := True;
      for Mode := Low(TMapRakuStrokeWidthMode) to
        High(TMapRakuStrokeWidthMode) do
        FWidthModeButtons[Mode].Visible := True;
      if UseLineToolDefaults then
        Indices := nil
      else
        Indices := SelectedLineIndices;
      if Length(Indices) > 0 then
      begin
        Visible := True;
        Layer := SelectionLayer(Indices[0]);
        TryReadMapRakuToolbarLine(Layer, Color, WidthValue, StyleValue,
          LineCapValue);
        CommonWidth := True;
        CommonStyle := True;
        CommonLineCap := True;
        SupportsLineCap := not (Layer is TMapRakuRectangleLineLayer);
        for I := 1 to High(Indices) do
        begin
          Layer := SelectionLayer(Indices[I]);
          SupportsLineCap := SupportsLineCap and
            not (Layer is TMapRakuRectangleLineLayer);
          TryReadMapRakuToolbarLine(Layer, Color, CurrentWidth, CurrentStyle,
            CurrentLineCap);
          CommonWidth := CommonWidth and SameValue(CurrentWidth, WidthValue);
          CommonStyle := CommonStyle and (CurrentStyle = StyleValue);
          CommonLineCap := CommonLineCap and
            (CurrentLineCap = LineCapValue);
        end;
        if CommonWidth then
          FStrokeWidthEdit.Text := FormatFloat('0.##', WidthValue)
        else
          FStrokeWidthEdit.Text := '';
        FStrokeWidthTrackBar.Position := EnsureRange(
          Round(WidthValue * STROKE_WIDTH_SCALE), STROKE_WIDTH_TRACK_MIN,
          STROKE_WIDTH_TRACK_MAX);
        if CommonStyle then
          FMifStrokeStyleCombo.SetPendingItemIndex(Ord(StyleValue))
        else
          FMifStrokeStyleCombo.SetPendingItemIndex(-1);
        if CommonLineCap then
          for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
            FLineCapButtons[Cap].Selected := Cap = LineCapValue
        else
          for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
            FLineCapButtons[Cap].Selected := False;
        Locked := SelectionHasLockedLine;
        SupportsWidthMode := (FEditorState <> nil) and
          (FEditorState.CurrentTool in [vetLine, vetFreehand, vetPath]);
        if SupportsWidthMode then
        begin
          WidthModeValue := FEditorState.StrokeWidthMode;
          CommonWidthMode := True;
        end
        else
        begin
          PathIndices := SelectedPathIndices;
          SupportsWidthMode := Length(PathIndices) > 0;
          CommonWidthMode := SupportsWidthMode;
          if SupportsWidthMode then
          begin
            if Length(TVectArtPathLayer(
              SelectionLayer(PathIndices[0])).WidthPoints) > 0 then
              WidthModeValue := slwmVariable
            else
              WidthModeValue := slwmUniform;
            for I := 1 to High(PathIndices) do
            begin
              if Length(TVectArtPathLayer(
                SelectionLayer(PathIndices[I])).WidthPoints) > 0 then
                CurrentWidthMode := slwmVariable
              else
                CurrentWidthMode := slwmUniform;
              CommonWidthMode := CommonWidthMode and
                (CurrentWidthMode = WidthModeValue);
            end;
          end;
        end;
        FStrokeWidthEdit.Enabled := not Locked;
        FStrokeWidthTrackBar.Enabled := not Locked;
        FMifStrokeStyleCombo.Enabled := not Locked;
        for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
          FLineCapButtons[Cap].Enabled := not Locked and SupportsLineCap;
        for Mode := Low(TMapRakuStrokeWidthMode) to
          High(TMapRakuStrokeWidthMode) do
        begin
          FWidthModeButtons[Mode].Enabled :=
            not Locked and SupportsWidthMode;
          FWidthModeButtons[Mode].Selected := SupportsWidthMode and
            CommonWidthMode and (Mode = WidthModeValue);
        end;
      end
      else if UseLineToolDefaults or
        ((FDocument <> nil) and (FDocument.SelectionCount = 0) and
         (FEditorState <> nil) and
         (FEditorState.CurrentTool in [vetRectangleLine,
           vetRoundedRectangleLine, vetArc, vetLine, vetEllipseLine,
           vetPath])) then
      begin
        Visible := True;
        FStrokeWidthEdit.Text := FormatFloat('0.##',
          FEditorState.LineStrokeWidth);
        FStrokeWidthTrackBar.Position := EnsureRange(
          Round(FEditorState.LineStrokeWidth * STROKE_WIDTH_SCALE),
          STROKE_WIDTH_TRACK_MIN, STROKE_WIDTH_TRACK_MAX);
        FMifStrokeStyleCombo.SetPendingItemIndex(
          Ord(FEditorState.LineMifStrokeStyle));
        for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
        begin
          FLineCapButtons[Cap].Selected := Cap = FEditorState.LineCap;
          FLineCapButtons[Cap].Enabled :=
            not (FEditorState.CurrentTool in [vetRectangleLine,
              vetRoundedRectangleLine, vetEllipseLine]);
        end;
        FStrokeWidthEdit.Enabled := True;
        FStrokeWidthTrackBar.Enabled := True;
        FMifStrokeStyleCombo.Enabled := True;
        SupportsWidthMode := FEditorState.CurrentTool in
          [vetLine, vetFreehand, vetPath];
        for Mode := Low(TMapRakuStrokeWidthMode) to
          High(TMapRakuStrokeWidthMode) do
        begin
          FWidthModeButtons[Mode].Enabled := SupportsWidthMode;
          FWidthModeButtons[Mode].Selected := SupportsWidthMode and
            (Mode = FEditorState.StrokeWidthMode);
        end;
      end
      else
      begin
        Visible := False;
        FDetailsPanel.Visible := False;
      end;
    end;
  finally
    FUpdating := False;
  end;
  Invalidate;
end;

procedure TVectArtLineToolbarControl.Resize;
var
  Mode: TMapRakuStrokeWidthMode;
  Style: TFontStyle;
  StyleLeft: Integer;
  TrackWidth: Integer;
  function Logical(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, CurrentPPI, 96);
  end;
begin
  inherited Resize;
  if FFontFamilyCombo <> nil then
    FFontFamilyCombo.SetBounds(Logical(60), Logical(8), Logical(180),
      Logical(25));
  StyleLeft := Logical(246);
  for Style := Low(TFontStyle) to High(TFontStyle) do
    if FFontStyleButtons[Style] <> nil then
      FFontStyleButtons[Style].SetBounds(StyleLeft + Ord(Style) * Logical(32),
        Logical(6), Logical(28), Logical(29));
  if FTextAlignmentButton <> nil then
    FTextAlignmentButton.SetBounds(Logical(374), Logical(6), Logical(34),
      Logical(29));
  if FTextPathAttachmentButton <> nil then
    FTextPathAttachmentButton.SetBounds(Logical(374), Logical(6), Logical(34),
      Logical(29));
  TrackWidth := Max(Width - Logical(256), Logical(60));
  if FStrokeWidthTrackBar <> nil then
    FStrokeWidthTrackBar.SetBounds(Logical(40), Logical(4), TrackWidth,
      Logical(34));
  if FStrokeWidthEdit <> nil then
    FStrokeWidthEdit.SetBounds(Width - Logical(208), Logical(8), Logical(48),
      Logical(25));
  for Mode := Low(TMapRakuStrokeWidthMode) to
    High(TMapRakuStrokeWidthMode) do
    if FWidthModeButtons[Mode] <> nil then
      FWidthModeButtons[Mode].SetBounds(
        Width - Logical(154 - Ord(Mode) * 34), Logical(6), Logical(30),
        Logical(29));
  if FDetailsButton <> nil then
    FDetailsButton.SetBounds(Width - Logical(70), Logical(8), Logical(60),
      Logical(25));
end;

function TVectArtLineToolbarControl.SelectedTextIndices: TArray<Integer>;
var
  I: Integer;
  Selection: TArray<Integer>;
begin
  Result := nil;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
    (FEditorState.OpenGroupChildCount > 0) then
  begin
    for I := 0 to FEditorState.OpenGroup.ChildCount - 1 do
      if FEditorState.IsOpenGroupChildSelected(FEditorState.OpenGroup[I]) then
      begin
        if not (FEditorState.OpenGroup[I] is TMapRakuTextLayer) then
          Exit(nil);
        Result := Result + [-(I + 1)];
      end;
    Exit;
  end;
  if (FDocument = nil) or (FDocument.SelectionCount = 0) then
    Exit;
  Selection := FDocument.GetSelectedLayerIndices;
  for I := 0 to High(Selection) do
    if not (FDocument[Selection[I]] is TMapRakuTextLayer) then
      Exit;
  Result := Selection;
end;

function TVectArtLineToolbarControl.SelectedTextPathIndices:
  TArray<Integer>;
var
  I: Integer;
  Selection: TArray<Integer>;
begin
  Result := nil;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
    (FEditorState.OpenGroupChildCount > 0) then
  begin
    for I := 0 to FEditorState.OpenGroup.ChildCount - 1 do
      if FEditorState.IsOpenGroupChildSelected(FEditorState.OpenGroup[I]) then
      begin
        if not (FEditorState.OpenGroup[I] is TMapRakuTextPathLayer) then
          Exit(nil);
        Result := Result + [-(I + 1)];
      end;
    Exit;
  end;
  if (FDocument = nil) or (FDocument.SelectionCount = 0) then
    Exit;
  Selection := FDocument.GetSelectedLayerIndices;
  for I := 0 to High(Selection) do
    if not (FDocument[Selection[I]] is TMapRakuTextPathLayer) then
      Exit;
  Result := Selection;
end;

function TVectArtLineToolbarControl.SelectedLineIndices: TArray<Integer>;
var
  I, J: Integer;
  Group: TMapRakuGroupLayer;
  Selection: TArray<Integer>;
begin
  Result := nil;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
    (FEditorState.OpenGroupChildCount > 0) then
  begin
    for I := 0 to FEditorState.OpenGroup.ChildCount - 1 do
      if FEditorState.IsOpenGroupChildSelected(FEditorState.OpenGroup[I]) then
      begin
        if (FEditorState.OpenGroup[I] is TMapRakuGroupLayer) and
          TMapRakuGroupLayer(FEditorState.OpenGroup[I]).MapSurface then begin
          Group:=TMapRakuGroupLayer(FEditorState.OpenGroup[I]);
          for J:=0 to Group.ChildCount-1 do begin
            if not ((Group[J] is TVectArtPathLayer) and
              not TVectArtPathLayer(Group[J]).Closed) then Exit(nil);
            Result:=Result+[-2000000-I*1000-J];
          end;
        end else if not ((FEditorState.OpenGroup[I] is TMapRakuRectangleLineLayer) or
          (FEditorState.OpenGroup[I] is TMapRakuArcLayer) or
          ((FEditorState.OpenGroup[I] is TVectArtPathLayer) and
           not TVectArtPathLayer(FEditorState.OpenGroup[I]).Closed)) then
          Exit(nil)
        else Result := Result + [-(I + 1)];
      end;
    Exit;
  end;
  if (FDocument = nil) or (FDocument.SelectionCount = 0) then
    Exit;
  Selection := FDocument.GetSelectedLayerIndices;
  for I := 0 to High(Selection) do begin
    if (FDocument[Selection[I]] is TMapRakuGroupLayer) and
      TMapRakuGroupLayer(FDocument[Selection[I]]).MapSurface then begin
      Group:=TMapRakuGroupLayer(FDocument[Selection[I]]);
      for J:=0 to Group.ChildCount-1 do begin
        if not ((Group[J] is TVectArtPathLayer) and
          not TVectArtPathLayer(Group[J]).Closed) then Exit(nil);
        Result:=Result+[-1000000-Selection[I]*1000-J];
      end;
    end else if not ((FDocument[Selection[I]] is TMapRakuRectangleLineLayer) or
      (FDocument[Selection[I]] is TMapRakuArcLayer) or
      ((FDocument[Selection[I]] is TVectArtPathLayer) and
       not TVectArtPathLayer(FDocument[Selection[I]]).Closed)) then
      Exit(nil)
    else Result:=Result+[Selection[I]];
  end;
end;

function TVectArtLineToolbarControl.SelectedPathIndices: TArray<Integer>;
var
  I: Integer;
  Indices: TArray<Integer>;
  LineIndices: TArray<Integer>;
begin
  Result := nil;
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetLine, vetFreehand, vetPath]) then
    Exit;
  LineIndices := SelectedLineIndices;
  for I := 0 to High(LineIndices) do
    if SelectionLayer(LineIndices[I]) is TVectArtPathLayer then
      Indices := Indices + [LineIndices[I]];
  Result := Indices;
end;

function TVectArtLineToolbarControl.SelectionHasLockedLine: Boolean;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  Result := False;
  Indices := SelectedLineIndices;
  for I := 0 to High(Indices) do
    if SelectionLayer(Indices[I]).Locked then
      Exit(True);
end;

function TVectArtLineToolbarControl.SelectionHasLockedText: Boolean;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  Result := False;
  Indices := SelectedTextIndices;
  for I := 0 to High(Indices) do
    if SelectionLayer(Indices[I]).Locked then
      Exit(True);
end;

function TVectArtLineToolbarControl.SelectionLayer(Token: Integer): TVectArtLayer;
var DocumentIndex, ChildIndex, Encoded: Integer; Group:TMapRakuGroupLayer;
begin
  Result := nil;
  if (Token >= 0) and (FDocument <> nil) and
    (Token < FDocument.LayerCount) then
    Exit(FDocument[Token]);
  if Token <= -2000000 then begin
    Encoded := -Token-2000000;
    DocumentIndex := Encoded div 1000;
    ChildIndex := Encoded mod 1000;
    if (FEditorState<>nil) and (FEditorState.OpenGroup<>nil) and
      (DocumentIndex<FEditorState.OpenGroup.ChildCount) and
      (FEditorState.OpenGroup[DocumentIndex] is TMapRakuGroupLayer) then begin
      Group:=TMapRakuGroupLayer(FEditorState.OpenGroup[DocumentIndex]);
      if ChildIndex<Group.ChildCount then Result:=Group[ChildIndex];
    end;
    Exit;
  end;
  if Token <= -1000000 then begin
    Encoded := -Token-1000000;
    DocumentIndex := Encoded div 1000;
    ChildIndex := Encoded mod 1000;
    if (FDocument<>nil) and (DocumentIndex>0) and
      (DocumentIndex<FDocument.LayerCount) and
      (FDocument[DocumentIndex] is TMapRakuGroupLayer) then begin
      Group:=TMapRakuGroupLayer(FDocument[DocumentIndex]);
      if ChildIndex<Group.ChildCount then Result:=Group[ChildIndex];
    end;
    Exit;
  end;
  if (Token < 0) and (FEditorState <> nil) and
    (FEditorState.OpenGroup <> nil) and
    (-Token - 1 < FEditorState.OpenGroup.ChildCount) then
    Result := FEditorState.OpenGroup[-Token - 1];
end;

function TVectArtLineToolbarControl.SelectionLayers(
  const Tokens: TArray<Integer>): TArray<TVectArtLayer>;
var
  I: Integer;
begin
  SetLength(Result, Length(Tokens));
  for I := 0 to High(Tokens) do
    Result[I] := SelectionLayer(Tokens[I]);
end;

function TVectArtLineToolbarControl.SelectionTextLayers(
  const Tokens: TArray<Integer>): TArray<TMapRakuTextLayer>;
var
  I: Integer;
begin
  SetLength(Result, Length(Tokens));
  for I := 0 to High(Tokens) do
    Result[I] := TMapRakuTextLayer(SelectionLayer(Tokens[I]));
end;

procedure TVectArtLineToolbarControl.StyleChanged(Sender: TObject);
begin
  if FUpdating or not InRange(FMifStrokeStyleCombo.ItemIndex,
    Ord(Low(TVectArtMifStrokeStyle)), Ord(High(TVectArtMifStrokeStyle))) then
    Exit;
  ApplyMifStrokeStyle(TVectArtMifStrokeStyle(FMifStrokeStyleCombo.ItemIndex));
end;

procedure TVectArtLineToolbarControl.TrackBarChanged(Sender: TObject);
var
  Value: Single;
begin
  if FUpdating then
    Exit;
  Value := FStrokeWidthTrackBar.Position / STROKE_WIDTH_SCALE;
  if FTrackGestureActive then
  begin
    // Document側の対話更新より先に操作中の値を表示し、MouseUpまで描画を滞留させない。
    FStrokeWidthEdit.Text := FormatFloat('0.##', Value);
    FStrokeWidthTrackBar.Repaint;
    FStrokeWidthEdit.Repaint;
  end;
  ApplyStrokeWidthInternal(Value, not FTrackGestureActive);
end;

procedure TVectArtLineToolbarControl.TrackBarMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Color: TColor;
  I: Integer;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
begin
  if FUpdating or (Button <> mbLeft) or not FStrokeWidthTrackBar.Enabled then
    Exit;
  FTrackGestureActive := True;
  FTrackStartIndices := SelectedLineIndices;
  SetLength(FTrackStartWidths, Length(FTrackStartIndices));
  for I := 0 to High(FTrackStartIndices) do
    TryReadMapRakuToolbarLine(SelectionLayer(FTrackStartIndices[I]), Color,
      FTrackStartWidths[I], Style, LineCap);
  if (Length(FTrackStartIndices) > 0) and (FDocument <> nil) then
  begin
    FDocument.BeginInteractiveUpdate;
    FTrackDocumentUpdateActive := True;
  end;
end;

procedure TVectArtLineToolbarControl.TrackBarMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    CommitTrackGesture;
end;

end.
