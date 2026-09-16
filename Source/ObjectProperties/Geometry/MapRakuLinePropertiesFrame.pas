// 選択中の線属性を編集する再利用可能な埋め込みFrame。
unit MapRakuLinePropertiesFrame;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls,
  HorizontalTrackBarControl, MapRakuDocument,
  MapRakuLineStyleControls, MapRakuStrokeStyleCombo;

type
  TMapRakuLinePropertiesFrame = class(TFrame)
  private
    FCapButtons: array[TVectArtLineCap] of TVectArtLineCapButton;
    FCapLabel: TLabel;
    FOnCapChange: TNotifyEvent;
    FOnStyleChange: TNotifyEvent;
    FOnWidthChange: TNotifyEvent;
    FOnWidthGestureEnd: TNotifyEvent;
    FOnWidthGestureStart: TNotifyEvent;
    FStyleCombo: TVectArtMifStrokeStyleCombo;
    FStyleLabel: TLabel;
    FTitleLabel: TLabel;
    FUpdating: Boolean;
    FWidthLabel: TLabel;
    FWidthTrackBar: THorizontalTrackBarControl;
    procedure CapClick(Sender: TObject);
    function GetLineCap: TVectArtLineCap;
    function GetStrokeStyle: TVectArtMifStrokeStyle;
    function GetStrokeWidth: Single;
    procedure SetControlsEnabled(Value: Boolean);
    procedure SetLineCap(Value: TVectArtLineCap);
    procedure SetLineCapVisible(Value: Boolean);
    procedure SetStrokeStyle(Value: TVectArtMifStrokeStyle);
    procedure SetStrokeWidth(Value: Single);
    procedure StyleChanged(Sender: TObject);
    procedure WidthChanged(Sender: TObject);
    procedure WidthMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure WidthMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  protected
    procedure Resize; override;
  public
    // 線幅、線種、線端を編集する専用GUIを生成する。
    constructor Create(AOwner: TComponent); override;
    // 選択中にロックレイヤーが含まれる場合、全線属性操作をまとめて無効化する。
    property ControlsEnabled: Boolean write SetControlsEnabled;
    // 線端を持つ円弧と開いたPathに表示する現在値。
    property LineCap: TVectArtLineCap read GetLineCap write SetLineCap;
    property LineCapVisible: Boolean write SetLineCapVisible;
    // MIF互換の線種と0.1単位の線幅をGUIへ同期する。
    property StrokeStyle: TVectArtMifStrokeStyle read GetStrokeStyle
      write SetStrokeStyle;
    property StrokeWidth: Single read GetStrokeWidth write SetStrokeWidth;
    // 各イベントはユーザー操作時だけ発生し、外部からの値同期では発生しない。
    property OnCapChange: TNotifyEvent read FOnCapChange write FOnCapChange;
    property OnStyleChange: TNotifyEvent read FOnStyleChange
      write FOnStyleChange;
    property OnWidthChange: TNotifyEvent read FOnWidthChange
      write FOnWidthChange;
    // ドラッグ境界イベントにより、呼び出し側は連続した線幅変更を1件の履歴へまとめられる。
    property OnWidthGestureEnd: TNotifyEvent read FOnWidthGestureEnd
      write FOnWidthGestureEnd;
    property OnWidthGestureStart: TNotifyEvent read FOnWidthGestureStart
      write FOnWidthGestureStart;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows;

{$R *.dfm}

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_EDIT = TColor($00303030);
  COLOR_HEADER = TColor($00292929);
  COLOR_TEXT = TColor($00EEEEEE);
  WIDTH_SCALE = 10;

constructor TMapRakuLinePropertiesFrame.Create(AOwner: TComponent);
var
  Cap: TVectArtLineCap;
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  Height := 190;

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Caption := 'Line';
  FTitleLabel.Color := COLOR_HEADER;
  FTitleLabel.Font.Name := 'Segoe UI';
  FTitleLabel.Font.Height := -13;
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Color := COLOR_TEXT;
  FTitleLabel.ParentColor := False;
  FTitleLabel.ParentFont := False;
  FTitleLabel.Layout := tlCenter;

  FWidthLabel := TLabel.Create(Self);
  FWidthLabel.Parent := Self;
  FWidthLabel.Font.Name := 'Segoe UI';
  FWidthLabel.Font.Height := -12;
  FWidthLabel.Font.Color := COLOR_TEXT;
  FWidthLabel.ParentFont := False;

  FWidthTrackBar := THorizontalTrackBarControl.Create(Self);
  FWidthTrackBar.Parent := Self;
  FWidthTrackBar.BackgroundColor := COLOR_BACKGROUND;
  FWidthTrackBar.ChannelColor := TColor($00505050);
  FWidthTrackBar.FillColor := TColor($00D77800);
  FWidthTrackBar.ThumbColor := COLOR_EDIT;
  FWidthTrackBar.ThumbBorderColor := COLOR_TEXT;
  FWidthTrackBar.ShowTicks := False;
  FWidthTrackBar.SetRange(0, 1000);
  FWidthTrackBar.SmallChange := 1;
  FWidthTrackBar.LargeChange := 10;
  FWidthTrackBar.OnChange := WidthChanged;
  FWidthTrackBar.OnMouseDown := WidthMouseDown;
  FWidthTrackBar.OnMouseUp := WidthMouseUp;

  FStyleLabel := TLabel.Create(Self);
  FStyleLabel.Parent := Self;
  FStyleLabel.Caption := 'Stroke style';
  FStyleLabel.Font.Assign(FWidthLabel.Font);

  FStyleCombo := TVectArtMifStrokeStyleCombo.Create(Self);
  FStyleCombo.Parent := Self;
  FStyleCombo.Style := csOwnerDrawFixed;
  FStyleCombo.ItemHeight := 22;
  FStyleCombo.DropDownCount := 9;
  FStyleCombo.Color := COLOR_EDIT;
  FStyleCombo.Font.Color := COLOR_TEXT;
  FStyleCombo.Font.Name := 'Segoe UI';
  FStyleCombo.Font.Height := -12;
  FStyleCombo.OnChange := StyleChanged;

  FCapLabel := TLabel.Create(Self);
  FCapLabel.Parent := Self;
  FCapLabel.Caption := 'Line cap';
  FCapLabel.Font.Assign(FWidthLabel.Font);
  for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
  begin
    FCapButtons[Cap] := TVectArtLineCapButton.Create(Self);
    FCapButtons[Cap].Parent := Self;
    FCapButtons[Cap].LineCap := Cap;
    FCapButtons[Cap].OnClick := CapClick;
  end;
  SetStrokeWidth(1.0);
  SetStrokeStyle(vssSolid);
  SetLineCap(vlcSquare);
end;

procedure TMapRakuLinePropertiesFrame.CapClick(Sender: TObject);
begin
  if FUpdating or not (Sender is TVectArtLineCapButton) then
    Exit;
  SetLineCap(TVectArtLineCapButton(Sender).LineCap);
  if Assigned(FOnCapChange) then
    FOnCapChange(Self);
end;

function TMapRakuLinePropertiesFrame.GetLineCap: TVectArtLineCap;
var
  Cap: TVectArtLineCap;
begin
  Result := vlcSquare;
  for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
    if FCapButtons[Cap].Selected then
      Exit(Cap);
end;

function TMapRakuLinePropertiesFrame.GetStrokeStyle:
  TVectArtMifStrokeStyle;
var
  Index: Integer;
begin
  if FStyleCombo.HandleAllocated then
    Index := FStyleCombo.ItemIndex
  else
    Index := FStyleCombo.PendingItemIndex;
  if InRange(Index,
    Ord(Low(TVectArtMifStrokeStyle)), Ord(High(TVectArtMifStrokeStyle))) then
    Result := TVectArtMifStrokeStyle(Index)
  else
    Result := vssSolid;
end;

function TMapRakuLinePropertiesFrame.GetStrokeWidth: Single;
begin
  Result := FWidthTrackBar.Position / WIDTH_SCALE;
end;

procedure TMapRakuLinePropertiesFrame.Resize;
var
  ButtonWidth: Integer;
  Margin: Integer;
begin
  inherited Resize;
  Margin := MulDiv(8, CurrentPPI, 96);
  FTitleLabel.SetBounds(0, 0, ClientWidth, MulDiv(32, CurrentPPI, 96));
  FWidthLabel.SetBounds(Margin, MulDiv(37, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, 1), MulDiv(18, CurrentPPI, 96));
  FWidthTrackBar.SetBounds(Margin, MulDiv(52, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, 1), MulDiv(28, CurrentPPI, 96));
  FStyleLabel.SetBounds(Margin, MulDiv(83, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, 1), MulDiv(18, CurrentPPI, 96));
  FStyleCombo.SetBounds(Margin, MulDiv(101, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, 1), MulDiv(25, CurrentPPI, 96));
  FCapLabel.SetBounds(Margin, MulDiv(132, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, 1), MulDiv(18, CurrentPPI, 96));
  ButtonWidth := Max((ClientWidth - Margin * 2 - 8) div 3, 30);
  FCapButtons[vlcSquare].SetBounds(Margin, MulDiv(151, CurrentPPI, 96),
    ButtonWidth, MulDiv(30, CurrentPPI, 96));
  FCapButtons[vlcRound].SetBounds(Margin + ButtonWidth + 4,
    MulDiv(151, CurrentPPI, 96), ButtonWidth, MulDiv(30, CurrentPPI, 96));
  FCapButtons[vlcTriangle].SetBounds(Margin + (ButtonWidth + 4) * 2,
    MulDiv(151, CurrentPPI, 96), ButtonWidth, MulDiv(30, CurrentPPI, 96));
end;

procedure TMapRakuLinePropertiesFrame.SetControlsEnabled(Value: Boolean);
var
  Cap: TVectArtLineCap;
begin
  FWidthTrackBar.Enabled := Value;
  FStyleCombo.Enabled := Value;
  for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
    FCapButtons[Cap].Enabled := Value and FCapButtons[Cap].Visible;
end;

procedure TMapRakuLinePropertiesFrame.SetLineCap(
  Value: TVectArtLineCap);
var
  Cap: TVectArtLineCap;
begin
  FUpdating := True;
  try
    for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
      FCapButtons[Cap].Selected := Cap = Value;
  finally
    FUpdating := False;
  end;
end;

procedure TMapRakuLinePropertiesFrame.SetLineCapVisible(Value: Boolean);
var
  Cap: TVectArtLineCap;
begin
  FCapLabel.Visible := Value;
  for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
    FCapButtons[Cap].Visible := Value;
end;

procedure TMapRakuLinePropertiesFrame.SetStrokeStyle(
  Value: TVectArtMifStrokeStyle);
begin
  FUpdating := True;
  try
    FStyleCombo.SetPendingItemIndex(Ord(Value));
  finally
    FUpdating := False;
  end;
end;

procedure TMapRakuLinePropertiesFrame.SetStrokeWidth(Value: Single);
begin
  FUpdating := True;
  try
    FWidthTrackBar.Position := Round(EnsureRange(Value, 0.0, 100.0) *
      WIDTH_SCALE);
    FWidthLabel.Caption := Format('Stroke width  %.1f', [GetStrokeWidth]);
  finally
    FUpdating := False;
  end;
end;

procedure TMapRakuLinePropertiesFrame.StyleChanged(Sender: TObject);
begin
  if not FUpdating and Assigned(FOnStyleChange) then
    FOnStyleChange(Self);
end;

procedure TMapRakuLinePropertiesFrame.WidthChanged(Sender: TObject);
begin
  FWidthLabel.Caption := Format('Stroke width  %.1f', [GetStrokeWidth]);
  if not FUpdating and Assigned(FOnWidthChange) then
    FOnWidthChange(Self);
end;

procedure TMapRakuLinePropertiesFrame.WidthMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and FWidthTrackBar.Enabled and
    Assigned(FOnWidthGestureStart) then
    FOnWidthGestureStart(Self);
end;

procedure TMapRakuLinePropertiesFrame.WidthMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and Assigned(FOnWidthGestureEnd) then
    FOnWidthGestureEnd(Self);
end;

end.
