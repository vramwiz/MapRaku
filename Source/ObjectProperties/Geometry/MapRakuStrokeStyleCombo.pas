// 線種を文字ではなく実際の線パターンで選択する共通コンボボックス。
// 現在の線パターンは既存ドキュメントとの互換値に対応する。
unit MapRakuStrokeStyleCombo;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.StdCtrls,
  MapRakuDocument;

type
  // Parent未接続のFrame内でItemsへ触れるとTComboBoxがHandleを要求するため、
  // 選択肢の生成を実際のCreateWndまで遅延する。
  TVectArtMifStrokeStyleCombo = class(TComboBox)
  private
    FPendingItemIndex: Integer;
  protected
    procedure CreateWnd; override;
    procedure DrawItem(Index: Integer; Rect: TRect;
      State: TOwnerDrawState); override;
  public
    // 線種項目をウィンドウハンドル生成時に構築するコンボボックスを生成する。
    constructor Create(AOwner: TComponent); override;
    // Handle未生成時にも選択予定値を保持し、生成済みなら表示へ直ちに反映する。
    procedure SetPendingItemIndex(Value: Integer);
    property PendingItemIndex: Integer read FPendingItemIndex;
  end;

implementation

uses
  System.Math, Winapi.Windows, Vcl.Graphics;

const
  COLOR_EDIT = TColor($00303030);
  COLOR_TEXT = TColor($00EEEEEE);

constructor TVectArtMifStrokeStyleCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPendingItemIndex := 0;
end;

procedure TVectArtMifStrokeStyleCombo.CreateWnd;
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
      Items.Add('Solid');
      Items.Add('Dotted');
      Items.Add('Short dash');
      Items.Add('Dash-dot');
      Items.Add('Dash-dot-dot');
      Items.Add('Sparse dotted');
      Items.Add('Medium dash');
      Items.Add('Long dash-dot');
      Items.Add('Long dash');
      ItemIndex := FPendingItemIndex;
    finally
      Items.EndUpdate;
    end;
  finally
    OnChange := ChangeEvent;
  end;
end;

procedure TVectArtMifStrokeStyleCombo.DrawItem(Index: Integer; Rect: TRect;
  State: TOwnerDrawState);
var
  DashIndex: Integer;
  DrawSegment: Boolean;
  Intervals: TArray<Single>;
  SegmentLength: Integer;
  StyleValue: TVectArtMifStrokeStyle;
  X: Integer;
  Y: Integer;
begin
  if odSelected in State then
    Canvas.Brush.Color := TColor($00D77800)
  else
    Canvas.Brush.Color := COLOR_EDIT;
  Canvas.FillRect(Rect);
  if not InRange(Index, Ord(Low(TVectArtMifStrokeStyle)),
    Ord(High(TVectArtMifStrokeStyle))) then
    Exit;
  StyleValue := TVectArtMifStrokeStyle(Index);
  Canvas.Pen.Color := COLOR_TEXT;
  Canvas.Pen.Width := 2;
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Color := COLOR_TEXT;
  Y := (Rect.Top + Rect.Bottom) div 2;
  X := Rect.Left + 5;
  Intervals := VectArtStrokeDashIntervals(StyleValue, 2.0);
  if Length(Intervals) = 0 then
  begin
    Canvas.MoveTo(X, Y);
    Canvas.LineTo(Rect.Right - 5, Y);
    Exit;
  end;
  DashIndex := 0;
  DrawSegment := True;
  while X < Rect.Right - 5 do
  begin
    SegmentLength := Max(Round(Intervals[DashIndex]), 1);
    if DrawSegment then
      if VectArtStrokeUsesRoundCaps(StyleValue) and
        (SegmentLength <= 2) then
        Canvas.Ellipse(X - 1, Y - 1, X + 2, Y + 2)
      else
      begin
        Canvas.MoveTo(X, Y);
        Canvas.LineTo(Min(X + SegmentLength, Rect.Right - 5), Y);
      end;
    Inc(X, SegmentLength);
    DashIndex := (DashIndex + 1) mod Length(Intervals);
    DrawSegment := not DrawSegment;
  end;
end;

procedure TVectArtMifStrokeStyleCombo.SetPendingItemIndex(Value: Integer);
begin
  FPendingItemIndex := Value;
  if HandleAllocated then
    ItemIndex := Value;
end;

end.
