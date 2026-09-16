// フィルターUI下端の補助領域で、一覧スライダーを補う厳密な数値入力を扱う。
unit MapRakuFilterDetailsFrame;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, MapRakuContext, MapRakuDocument,
  MapRakuFilters;

type
  TMapRakuFilterDetailsFrame = class(TFrame)
  private
    FContext: IVectArtDesignerContext;
    FEdits: array[0..5] of TEdit;
    FFilter: TMapRakuFilter;
    FLabels: array[0..5] of TLabel;
    FLayer: TVectArtLayer;
    FOnChanged: TNotifyEvent;
    FRefreshing: Boolean;
    FTitleLabel: TLabel;
    procedure EditExit(Sender: TObject);
    procedure SetContext(const Value: IVectArtDesignerContext);
    procedure SetFilter(Layer: TVectArtLayer;
      Filter: TMapRakuFilter);
    procedure SetRow(Index: Integer; const Caption, Value: string;
      Visible: Boolean);
  public
    // 固定下端領域で使用するコントロールを生成する。
    constructor Create(AOwner: TComponent); override;
    // 選択フィルターの種類と現在値から表示項目を再構築する。
    procedure Refresh;
    // 編集対象を切り替える。LayerとFilterの所有権は受け取らない。
    procedure SelectFilter(Layer: TVectArtLayer;
      Filter: TMapRakuFilter);
    property Context: IVectArtDesignerContext read FContext write SetContext;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Math, System.SysUtils, Vcl.Graphics, Winapi.Windows,
  MapRakuFilterCommands;

{$R MapRakuFilterDetailsFrame.dfm}

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_DISABLED   = TColor($00606060);
  COLOR_HEADER     = TColor($00292929);
  COLOR_TEXT       = TColor($00EEEEEE);
  EDIT_LEFT        = 82;
  EDIT_WIDTH       = 70;
  ROW_HEIGHT       = 26;
  TITLE_HEIGHT     = 28;

constructor TMapRakuFilterDetailsFrame.Create(AOwner: TComponent);
var
  I: Integer;
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.Align := alTop;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Height := MulDiv(TITLE_HEIGHT, CurrentPPI, 96);
  FTitleLabel.Caption := 'フィルター設定';
  FTitleLabel.Color := COLOR_HEADER;
  FTitleLabel.Font.Name := 'Segoe UI';
  FTitleLabel.Font.Height := -MulDiv(12, CurrentPPI, 96);
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Color := COLOR_TEXT;
  FTitleLabel.Layout := tlCenter;
  FTitleLabel.ParentColor := False;
  FTitleLabel.Margins.Left := MulDiv(8, CurrentPPI, 96);
  FTitleLabel.AlignWithMargins := True;

  for I := 0 to High(FEdits) do
  begin
    FLabels[I] := TLabel.Create(Self);
    FLabels[I].Parent := Self;
    FLabels[I].SetBounds(MulDiv(7, CurrentPPI, 96),
      MulDiv(TITLE_HEIGHT + I * ROW_HEIGHT + 5, CurrentPPI, 96),
      MulDiv(72, CurrentPPI, 96), MulDiv(21, CurrentPPI, 96));
    FLabels[I].Font.Name := 'Segoe UI';
    FLabels[I].Font.Height := -MulDiv(12, CurrentPPI, 96);
    FLabels[I].Font.Color := COLOR_TEXT;

    FEdits[I] := TEdit.Create(Self);
    FEdits[I].Parent := Self;
    FEdits[I].SetBounds(MulDiv(EDIT_LEFT, CurrentPPI, 96),
      MulDiv(TITLE_HEIGHT + I * ROW_HEIGHT + 1, CurrentPPI, 96),
      MulDiv(EDIT_WIDTH, CurrentPPI, 96), MulDiv(23, CurrentPPI, 96));
    FEdits[I].Color := COLOR_HEADER;
    FEdits[I].Font.Name := 'Segoe UI';
    FEdits[I].Font.Height := -MulDiv(12, CurrentPPI, 96);
    FEdits[I].Font.Color := COLOR_TEXT;
    FEdits[I].Tag := I;
    FEdits[I].OnExit := EditExit;
  end;

  Refresh;
end;

procedure TMapRakuFilterDetailsFrame.EditExit(Sender: TObject);
var
  Changed: Boolean;
  Command: TMapRakuSetFilterParametersCommand;
  NewValue: TMapRakuFilter;
  OldNumber: Single;
  OldValue: TMapRakuFilter;
  Value: Single;
begin
  if FRefreshing or not (Sender is TEdit) or (FFilter = nil) or
    (FLayer = nil) or FLayer.Locked or (FContext = nil) or
    (FFilter.Kind <> slfkBlur) or (TEdit(Sender).Tag <> 0) or
    not TryStrToFloat(TEdit(Sender).Text, Value) then
  begin
    Refresh;
    Exit;
  end;
  OldValue := FFilter.Clone;
  NewValue := FFilter.Clone;
  try
    OldNumber := TMapRakuBlurFilter(FFilter).Radius;
    Value := EnsureRange(Value, 0.0, 500.0);
    TMapRakuBlurFilter(NewValue).Radius := Value;
    Changed := not SameValue(OldNumber, Value);
    if Changed then
    begin
      Command := TMapRakuSetFilterParametersCommand.Create(
        FContext.Document, FFilter, OldValue, NewValue);
      Command.Execute;
      if FContext.EditHistory <> nil then
        FContext.EditHistory.AddApplied(Command)
      else
        Command.Free;
    end;
  finally
    NewValue.Free;
    OldValue.Free;
  end;
  Refresh;
  if Changed and Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TMapRakuFilterDetailsFrame.Refresh;
var
  Editable: Boolean;
  I: Integer;
begin
  if FRefreshing then
    Exit;
  FRefreshing := True;
  try
    for I := 0 to High(FEdits) do
      SetRow(I, '', '', False);
    FTitleLabel.Caption := 'フィルター設定';
    Visible := False;
    if FFilter = nil then
      Exit;
    FTitleLabel.Caption := 'フィルター設定：' + FFilter.DisplayName;
    Editable := (FLayer <> nil) and not FLayer.Locked;
    case FFilter.Kind of
      slfkBlur:
      begin
        SetRow(0, '半径', FormatFloat('0.##',
          TMapRakuBlurFilter(FFilter).Radius), True);
        Visible := True;
      end;
    end;
    for I := 0 to High(FEdits) do
      FEdits[I].Enabled := Editable and FEdits[I].Visible;
  finally
    FRefreshing := False;
  end;
end;

procedure TMapRakuFilterDetailsFrame.SelectFilter(
  Layer: TVectArtLayer; Filter: TMapRakuFilter);
begin
  SetFilter(Layer, Filter);
end;

procedure TMapRakuFilterDetailsFrame.SetContext(
  const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  Refresh;
end;

procedure TMapRakuFilterDetailsFrame.SetFilter(Layer: TVectArtLayer;
  Filter: TMapRakuFilter);
begin
  FLayer := Layer;
  FFilter := Filter;
  Refresh;
end;

procedure TMapRakuFilterDetailsFrame.SetRow(Index: Integer;
  const Caption, Value: string; Visible: Boolean);
begin
  FLabels[Index].Caption := Caption;
  FLabels[Index].Visible := Visible;
  FEdits[Index].Text := Value;
  FEdits[Index].Visible := Visible;
end;

end.
