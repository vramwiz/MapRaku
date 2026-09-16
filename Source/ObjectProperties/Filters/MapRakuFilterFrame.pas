// フィルターUIの見出し、操作列、一覧、下端の補助設定を1つのFrameへまとめる。
// 一覧固有の描画と入力はMapRakuFilterListControlへ委譲する。
unit MapRakuFilterFrame;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.Graphics, Vcl.StdCtrls, MapRakuContext,
  MapRakuDocument, MapRakuFilterDetailsFrame,
  MapRakuFilterListControl, MapRakuFilters, VectArtDarkMenuGroup,
  VectArtDarkPopupMenu;

type
  TMapRakuFilterFrame = class(TFrame)
  private
    FAddButton: TPanel;
    FAddMenu: TVectArtDarkPopupMenu;
    FAddMenuGroup: TVectArtDarkMenuGroup;
    FCaptionLabel: TLabel;
    FContext: IVectArtDesignerContext;
    FDeleteButton: TPanel;
    FDetailsFrame: TMapRakuFilterDetailsFrame;
    FFilterList: TMapRakuFilterListControl;
    FHeaderPanel: TPanel;
    FToolbarPanel: TPanel;
    FValueGestureFilter: TMapRakuFilter;
    FValueGestureOldParameters: TMapRakuFilter;
    procedure AddButtonClick(Sender: TObject);
    procedure AddFilterClick(Sender: TObject);
    procedure DeleteButtonClick(Sender: TObject);
    procedure EnsureAddMenu;
    procedure FilterMoved(Sender: TObject; FromIndex, ToIndex: Integer);
    procedure FilterSelectionChanged(Sender: TObject);
    procedure FilterToggleEnabled(Sender: TObject; Index: Integer);
    procedure FilterValueChanged(Sender: TObject; Index: Integer;
      Value: Single);
    procedure FilterValueGestureEnd(Sender: TObject; Index: Integer);
    procedure FilterValueGestureStart(Sender: TObject; Index: Integer);
    procedure SetContext(const Value: IVectArtDesignerContext);
    procedure UpdateControlState;
  protected
    procedure Resize; override;
  public
    // レイアウト変更時に一体で載せ替えられる3領域を生成する。
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 単一選択中のレイヤーまたはグループから一覧と補助設定を再同期する。
    procedure RefreshFromDocument;
    property Context: IVectArtDesignerContext read FContext write SetContext;
  end;

implementation

uses
  System.Math, Winapi.Windows, MapRakuEditCommands,
  MapRakuEditorState, MapRakuFilterCommands,
  MapRakuObjectPropertySelection;

{$R MapRakuFilterFrame.dfm}

const
  COLOR_BACKGROUND       = TColor($00212121);
  COLOR_BUTTON           = TColor($00303030);
  COLOR_DISABLED         = TColor($00606060);
  COLOR_HEADER           = TColor($00292929);
  COLOR_TEXT_PRIMARY     = TColor($00EEEEEE);
  CAPTION_HEIGHT         = 28;
  DETAIL_HEIGHT          = 88;
  HEADER_HEIGHT          = 58;

type
  TFilterToolbarButtonKind = (ftbkAdd, ftbkDelete);

  TFilterToolbarButton = class(TPanel)
  private
    FKind: TFilterToolbarButtonKind; // 追加または削除の描画種別。
  protected
    // DPIと有効状態に合わせ、追加記号またはゴミ箱を線画で描く。
    procedure Paint; override;
  public
    // 操作種別を保持するダークテーマのツールバーボタンを生成する。
    constructor CreateButton(AOwner: TComponent; Kind: TFilterToolbarButtonKind);
  end;

constructor TFilterToolbarButton.CreateButton(AOwner: TComponent;
  Kind: TFilterToolbarButtonKind);
begin
  inherited Create(AOwner);
  FKind := Kind;
  BevelOuter := bvNone;
  Caption := '';
  Color := COLOR_BUTTON;
  Font.Color := COLOR_TEXT_PRIMARY;
  ParentBackground := False;
  Cursor := crHandPoint;
end;

procedure TFilterToolbarButton.Paint;
var
  CenterX: Integer;
  CenterY: Integer;
  GlyphColor: TColor;
  HalfSize: Integer;
  Left: Integer;
  PenWidth: Integer;
  Top: Integer;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  if Enabled then GlyphColor := COLOR_TEXT_PRIMARY
  else GlyphColor := COLOR_DISABLED;
  Canvas.Pen.Color := GlyphColor;
  PenWidth := Max(MulDiv(2, CurrentPPI, 96), 1);
  Canvas.Pen.Width := PenWidth;
  CenterX := ClientWidth div 2;
  CenterY := ClientHeight div 2;
  if FKind = ftbkAdd then
  begin
    HalfSize := MulDiv(8, CurrentPPI, 96);
    Canvas.MoveTo(CenterX - HalfSize, CenterY);
    Canvas.LineTo(CenterX + HalfSize + 1, CenterY);
    Canvas.MoveTo(CenterX, CenterY - HalfSize);
    Canvas.LineTo(CenterX, CenterY + HalfSize + 1);
  end
  else
  begin
    Left := CenterX - MulDiv(6, CurrentPPI, 96);
    Top := CenterY - MulDiv(6, CurrentPPI, 96);
    Canvas.MoveTo(Left, Top + MulDiv(3, CurrentPPI, 96));
    Canvas.LineTo(Left + MulDiv(1, CurrentPPI, 96), Top + MulDiv(12, CurrentPPI, 96));
    Canvas.LineTo(Left + MulDiv(11, CurrentPPI, 96), Top + MulDiv(12, CurrentPPI, 96));
    Canvas.LineTo(Left + MulDiv(12, CurrentPPI, 96), Top + MulDiv(3, CurrentPPI, 96));
    Canvas.MoveTo(Left - MulDiv(1, CurrentPPI, 96), Top + MulDiv(2, CurrentPPI, 96));
    Canvas.LineTo(Left + MulDiv(13, CurrentPPI, 96), Top + MulDiv(2, CurrentPPI, 96));
    Canvas.MoveTo(Left + MulDiv(4, CurrentPPI, 96), Top);
    Canvas.LineTo(Left + MulDiv(8, CurrentPPI, 96), Top);
  end;
  Canvas.Pen.Width := 1;
end;

procedure TMapRakuFilterFrame.AddButtonClick(Sender: TObject);
var
  PopupPoint: TPoint;
begin
  if not FAddButton.Enabled then
    Exit;
  EnsureAddMenu;
  if FAddMenu = nil then
    Exit;
  if FAddMenu.Visible then
  begin
    FAddMenu.Close;
    Exit;
  end;
  PopupPoint := FAddButton.ClientToScreen(Point(0, FAddButton.Height));
  FAddMenu.OpenAtScreenPoint(PopupPoint);
end;

procedure TMapRakuFilterFrame.AddFilterClick(Sender: TObject);
var
  Command: TMapRakuAddFilterCommand;
  Filter: TMapRakuFilter;
  Kind: TMapRakuFilterKind;
  Layer: TVectArtLayer;
begin
  if not (Sender is TPanel) or (FContext = nil) then
    Exit;
  if FAddMenu <> nil then
    FAddMenu.Close;
  Layer := MapRakuSelectedSingleLayer(FContext);
  if (Layer = nil) or Layer.Locked then
    Exit;
  Kind := TMapRakuFilterKind(TPanel(Sender).Tag);
  Filter := CreateDefaultMapRakuFilter(Kind);
  Command := TMapRakuAddFilterCommand.Create(FContext.Document, Layer,
    Layer.FilterCount, Filter);
  Command.Execute;
  if FContext.EditHistory <> nil then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FFilterList.SelectedIndex := Layer.FilterCount - 1;
  UpdateControlState;
end;

constructor TMapRakuFilterFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := alClient;
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;

  FHeaderPanel := TPanel.Create(Self);
  FHeaderPanel.Parent := Self;
  FHeaderPanel.Align := alTop;
  FHeaderPanel.Height := MulDiv(HEADER_HEIGHT, CurrentPPI, 96);
  FHeaderPanel.BevelOuter := bvNone;
  FHeaderPanel.Color := COLOR_HEADER;
  FHeaderPanel.ParentBackground := False;

  FCaptionLabel := TLabel.Create(Self);
  FCaptionLabel.Parent := FHeaderPanel;
  FCaptionLabel.Align := alTop;
  FCaptionLabel.AutoSize := False;
  FCaptionLabel.Height := MulDiv(CAPTION_HEIGHT, CurrentPPI, 96);
  FCaptionLabel.Caption := 'フィルター';
  FCaptionLabel.Font.Name := 'Segoe UI';
  FCaptionLabel.Font.Height := -MulDiv(12, CurrentPPI, 96);
  FCaptionLabel.Font.Style := [fsBold];
  FCaptionLabel.Font.Color := COLOR_TEXT_PRIMARY;
  FCaptionLabel.Layout := tlCenter;
  FCaptionLabel.Margins.Left := MulDiv(8, CurrentPPI, 96);
  FCaptionLabel.AlignWithMargins := True;

  FToolbarPanel := TPanel.Create(Self);
  FToolbarPanel.Parent := FHeaderPanel;
  FToolbarPanel.Align := alClient;
  FToolbarPanel.BevelOuter := bvNone;
  FToolbarPanel.Color := COLOR_HEADER;
  FToolbarPanel.ParentBackground := False;

  FAddButton := TFilterToolbarButton.CreateButton(Self, ftbkAdd);
  FAddButton.Parent := FToolbarPanel;
  FAddButton.SetBounds(MulDiv(5, CurrentPPI, 96), 2,
    MulDiv(32, CurrentPPI, 96), MulDiv(26, CurrentPPI, 96));
  FAddButton.Hint := 'フィルターを追加';
  FAddButton.ShowHint := True;
  FAddButton.Color := COLOR_BUTTON;
  FAddButton.Font.Color := COLOR_TEXT_PRIMARY;
  FAddButton.ParentBackground := False;
  FAddButton.OnClick := AddButtonClick;

  FDeleteButton := TFilterToolbarButton.CreateButton(Self, ftbkDelete);
  FDeleteButton.Parent := FToolbarPanel;
  FDeleteButton.SetBounds(MulDiv(41, CurrentPPI, 96), 2,
    MulDiv(28, CurrentPPI, 96), MulDiv(26, CurrentPPI, 96));
  FDeleteButton.Hint := '選択したフィルターを削除';
  FDeleteButton.ShowHint := True;
  FDeleteButton.Color := COLOR_BUTTON;
  FDeleteButton.Font.Color := COLOR_TEXT_PRIMARY;
  FDeleteButton.ParentBackground := False;
  FDeleteButton.OnClick := DeleteButtonClick;

  FDetailsFrame := TMapRakuFilterDetailsFrame.Create(Self);
  FDetailsFrame.Parent := Self;
  FDetailsFrame.Align := alBottom;
  FDetailsFrame.Height := MulDiv(DETAIL_HEIGHT, CurrentPPI, 96);

  FFilterList := TMapRakuFilterListControl.Create(Self);
  FFilterList.Parent := Self;
  FFilterList.Align := alClient;
  FFilterList.OnMoveFilter := FilterMoved;
  FFilterList.OnSelectionChanged := FilterSelectionChanged;
  FFilterList.OnToggleEnabled := FilterToggleEnabled;
  FFilterList.OnValueChanged := FilterValueChanged;
  FFilterList.OnValueGestureEnd := FilterValueGestureEnd;
  FFilterList.OnValueGestureStart := FilterValueGestureStart;
  FDetailsFrame.OnChanged := FilterSelectionChanged;
  UpdateControlState;
end;

procedure TMapRakuFilterFrame.Resize;
begin
  inherited;
  if (FDetailsFrame = nil) or (FHeaderPanel = nil) then Exit;
  // 補助設定より先に一覧1行分を確保し、狭い高さでもスクロール操作を残す。
  FDetailsFrame.Height := EnsureRange(ClientHeight - FHeaderPanel.Height - MulDiv(38, CurrentPPI, 96),
    0, MulDiv(DETAIL_HEIGHT, CurrentPPI, 96));
end;

procedure TMapRakuFilterFrame.EnsureAddMenu;
const
  ITEM_HEIGHT = 32;
  MENU_WIDTH = 140;
var
  Host: TCustomForm;
  Item: TPanel;

  procedure AddMenuItem(const Caption: string;
    Kind: TMapRakuFilterKind; Top: Integer);
  begin
    Item := FAddMenu.AddItem(Caption, Top, AddFilterClick);
    Item.Tag := Ord(Kind);
  end;

begin
  if FAddMenu <> nil then
    Exit;
  Host := GetParentForm(Self);
  if Host = nil then
    Exit;
  FAddMenuGroup := TVectArtDarkMenuGroup.Create(Self);
  FAddMenu := TVectArtDarkPopupMenu.CreatePopup(Self, Host,
    MENU_WIDTH, ITEM_HEIGHT * 3);
  FAddMenuGroup.RegisterMenu(FAddMenu);
  AddMenuItem('縁取り', slfkOutline, 0);
  AddMenuItem('影', slfkShadow, ITEM_HEIGHT);
  AddMenuItem('ぼかし', slfkBlur, ITEM_HEIGHT * 2);
end;

destructor TMapRakuFilterFrame.Destroy;
begin
  if (FValueGestureOldParameters <> nil) and (FContext <> nil) and
    (FContext.Document <> nil) then
    FContext.Document.EndInteractiveUpdate;
  FValueGestureOldParameters.Free;
  inherited Destroy;
end;

procedure TMapRakuFilterFrame.DeleteButtonClick(Sender: TObject);
var
  Command: TMapRakuRemoveFilterCommand;
  Index: Integer;
  Layer: TVectArtLayer;
begin
  if FContext = nil then
    Exit;
  Layer := FFilterList.Layer;
  Index := FFilterList.SelectedIndex;
  if (Layer = nil) or Layer.Locked or (Index < 0) or
    (Index >= Layer.FilterCount) then
    Exit;
  Command := TMapRakuRemoveFilterCommand.Create(FContext.Document,
    Layer, Index);
  Command.Execute;
  if FContext.EditHistory <> nil then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FFilterList.SelectedIndex := Min(Index, Layer.FilterCount - 1);
  UpdateControlState;
end;

procedure TMapRakuFilterFrame.FilterMoved(Sender: TObject;
  FromIndex, ToIndex: Integer);
var
  Command: TMapRakuMoveFilterCommand;
  Layer: TVectArtLayer;
begin
  if FContext = nil then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer = nil) or Layer.Locked then
    Exit;
  Command := TMapRakuMoveFilterCommand.Create(FContext.Document,
    Layer, FromIndex, ToIndex);
  Command.Execute;
  if FContext.EditHistory <> nil then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FFilterList.SelectedIndex := ToIndex;
end;

procedure TMapRakuFilterFrame.FilterSelectionChanged(Sender: TObject);
var
  Filter: TMapRakuFilter;
  Layer: TVectArtLayer;
begin
  UpdateControlState;
  if (FContext = nil) or (FContext.EditorState = nil) then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer <> nil) and (FFilterList.SelectedIndex >= 0) and
    (FFilterList.SelectedIndex < Layer.FilterCount) then
    Filter := Layer.Filters[FFilterList.SelectedIndex]
  else
    Filter := nil;
  // Only an actual filter selection enters direct filter-edit mode.
  // Refreshing the list after a document selection change also raises this
  // event with Filter=nil; that must not cancel an active creation tool.
  if Filter <> nil then
    FContext.EditorState.CurrentTool := vetSelect;
  FContext.EditorState.SelectFilter(Layer, Filter);
end;

procedure TMapRakuFilterFrame.FilterToggleEnabled(Sender: TObject;
  Index: Integer);
var
  Command: TMapRakuSetFilterEnabledCommand;
  Filter: TMapRakuFilter;
  Layer: TVectArtLayer;
begin
  if FContext = nil then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer = nil) or Layer.Locked or (Index < 0) or
    (Index >= Layer.FilterCount) then
    Exit;
  Filter := Layer.Filters[Index];
  Command := TMapRakuSetFilterEnabledCommand.Create(FContext.Document,
    Filter, Filter.Enabled, not Filter.Enabled);
  Command.Execute;
  if FContext.EditHistory <> nil then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FFilterList.Invalidate;
end;

procedure TMapRakuFilterFrame.FilterValueChanged(Sender: TObject;
  Index: Integer; Value: Single);
var
  Filter: TMapRakuFilter;
  Layer: TVectArtLayer;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer = nil) or Layer.Locked or (Index < 0) or
    (Index >= Layer.FilterCount) then
    Exit;
  Filter := Layer.Filters[Index];
  if Filter is TMapRakuOutlineFilter then
    TMapRakuOutlineFilter(Filter).Width := Value
  else if Filter is TMapRakuShadowFilter then
    TMapRakuShadowFilter(Filter).BlurRadius := Value
  else if Filter is TMapRakuBlurFilter then
    TMapRakuBlurFilter(Filter).Radius := Value
  else
    Exit;
  FContext.Document.Changed;
  FFilterList.Invalidate;
end;

procedure TMapRakuFilterFrame.FilterValueGestureEnd(Sender: TObject;
  Index: Integer);
var
  Command: TMapRakuSetFilterParametersCommand;
begin
  if FValueGestureOldParameters = nil then
    Exit;
  if (FContext <> nil) and (FContext.EditHistory <> nil) and
    (FValueGestureFilter <> nil) and
    not SameValue(FilterRepresentativeRatio(FValueGestureOldParameters),
      FilterRepresentativeRatio(FValueGestureFilter)) then
  begin
    Command := TMapRakuSetFilterParametersCommand.Create(
      FContext.Document, FValueGestureFilter,
      FValueGestureOldParameters, FValueGestureFilter);
    FContext.EditHistory.AddApplied(Command);
  end;
  FValueGestureOldParameters.Free;
  FValueGestureOldParameters := nil;
  FValueGestureFilter := nil;
  if (FContext <> nil) and (FContext.Document <> nil) then
    FContext.Document.EndInteractiveUpdate;
end;

procedure TMapRakuFilterFrame.FilterValueGestureStart(Sender: TObject;
  Index: Integer);
var
  Layer: TVectArtLayer;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer = nil) or Layer.Locked or (Index < 0) or
    (Index >= Layer.FilterCount) then
    Exit;
  FValueGestureOldParameters.Free;
  FValueGestureFilter := Layer.Filters[Index];
  FValueGestureOldParameters := FValueGestureFilter.Clone;
  FContext.Document.BeginInteractiveUpdate;
end;

procedure TMapRakuFilterFrame.RefreshFromDocument;
var
  DesiredIndex: Integer;
  I: Integer;
  Layer: TVectArtLayer;
begin
  Layer := MapRakuSelectedSingleLayer(FContext);
  FFilterList.Layer := Layer;
  DesiredIndex := -1;
  if (Layer <> nil) and (FContext <> nil) and (FContext.EditorState <> nil) and
    (FContext.EditorState.SelectedFilterLayer = Layer) then
    for I := 0 to Layer.FilterCount - 1 do
      if Layer.Filters[I] = FContext.EditorState.SelectedFilter then
      begin
        DesiredIndex := I;
        Break;
      end;
  FFilterList.SelectedIndex := DesiredIndex;
  FFilterList.Invalidate;
  UpdateControlState;
end;

procedure TMapRakuFilterFrame.SetContext(
  const Value: IVectArtDesignerContext);
begin
  if FValueGestureOldParameters <> nil then
  begin
    if (FContext <> nil) and (FContext.Document <> nil) then
      FContext.Document.EndInteractiveUpdate;
    FValueGestureOldParameters.Free;
    FValueGestureOldParameters := nil;
    FValueGestureFilter := nil;
  end;
  if (FContext <> nil) and (FContext.EditorState <> nil) then
    FContext.EditorState.SelectFilter(nil, nil);
  FContext := Value;
  FDetailsFrame.Context := FContext;
  RefreshFromDocument;
end;

procedure TMapRakuFilterFrame.UpdateControlState;
var
  Editable: Boolean;
  Filter: TMapRakuFilter;
  Layer: TVectArtLayer;
begin
  Layer := FFilterList.Layer;
  Editable := (Layer <> nil) and not Layer.Locked;
  if not Editable and (FAddMenu <> nil) then
    FAddMenu.Close;
  FAddButton.Enabled := Editable;
  if Editable then
    FAddButton.Font.Color := COLOR_TEXT_PRIMARY
  else
    FAddButton.Font.Color := COLOR_DISABLED;
  FDeleteButton.Enabled := Editable and
    (FFilterList.SelectedIndex >= 0);
  if FDeleteButton.Enabled then
    FDeleteButton.Font.Color := COLOR_TEXT_PRIMARY
  else
    FDeleteButton.Font.Color := COLOR_DISABLED;

  if (Layer <> nil) and (FFilterList.SelectedIndex >= 0) and
    (FFilterList.SelectedIndex < Layer.FilterCount) then
  begin
    Filter := Layer.Filters[FFilterList.SelectedIndex];
    FDetailsFrame.SelectFilter(Layer, Filter);
  end
  else
    FDetailsFrame.SelectFilter(Layer, nil);
end;

end.
