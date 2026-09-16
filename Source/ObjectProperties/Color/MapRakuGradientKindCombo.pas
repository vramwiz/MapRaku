// グラデーション種別を、親画面と同じ暗色で選択するコンボボックスを提供する。
unit MapRakuGradientKindCombo;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.StdCtrls,
  Winapi.Messages;

type
  TMapRakuGradientKindCombo = class(TComboBox)
  private
    FPendingItemIndex: Integer;
    function Logical(Value: Integer): Integer;
  protected
    // Windows標準テーマを外し、閉状態も暗色で描画できるHandleを準備する。
    procedure CreateWnd; override;
    // ドロップダウン項目の背景と文字を暗色で描く。
    procedure DrawItem(Index: Integer; Rect: TRect;
      State: TOwnerDrawState); override;
    // 選択文字、背景、矢印を暗色テーマとして描き直す。
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
  public
    // 種別一覧はHandle生成時に構築し、Parent未接続時のHandle生成を避ける。
    constructor Create(AOwner: TComponent); override;
    // Handle再生成後も復元できるよう、表示中または次回表示する種別を保持する。
    procedure SetPendingItemIndex(Value: Integer);
  end;

implementation

uses
  System.Math, Vcl.Graphics, Winapi.UxTheme, Winapi.Windows;

const
  COLOR_EDIT = TColor($00303030);
  COLOR_EDIT_BORDER = TColor($00606060);
  COLOR_SELECTED = TColor($00504438);
  COLOR_TEXT = TColor($00EEEEEE);

constructor TMapRakuGradientKindCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := csOwnerDrawFixed;
  Ctl3D := False;
  Color := COLOR_EDIT;
  Font.Name := 'Segoe UI';
  Font.Height := -12;
  Font.Color := COLOR_TEXT;
  FPendingItemIndex := 0;
  ItemHeight := Logical(20);
end;

function TMapRakuGradientKindCombo.Logical(Value: Integer): Integer;
begin
  Result := MulDiv(Value, CurrentPPI, 96);
end;

procedure TMapRakuGradientKindCombo.CreateWnd;
var
  ChangeEvent: TNotifyEvent;
begin
  Font.Height := -Logical(12);
  ItemHeight := Logical(20);
  inherited CreateWnd;
  SetWindowTheme(Handle, '', '');
  ChangeEvent := OnChange;
  OnChange := nil;
  try
    Items.BeginUpdate;
    try
      Items.Clear;
      Items.Add('線形');
      Items.Add('放射（楕円）');
      Items.Add('矩形');
      Items.Add('円形（角度）');
      Items.Add('線方向');
      Items.Add('線幅方向');
      ItemIndex := FPendingItemIndex;
    finally
      Items.EndUpdate;
    end;
  finally
    OnChange := ChangeEvent;
  end;
end;

procedure TMapRakuGradientKindCombo.SetPendingItemIndex(Value: Integer);
begin
  FPendingItemIndex := EnsureRange(Value, 0, 5);
  if HandleAllocated then
    ItemIndex := FPendingItemIndex;
end;

procedure TMapRakuGradientKindCombo.DrawItem(Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
begin
  if odSelected in State then
    Canvas.Brush.Color := COLOR_SELECTED
  else
    Canvas.Brush.Color := COLOR_EDIT;
  Canvas.FillRect(Rect);
  Canvas.Font := Font;
  Canvas.Font.Color := COLOR_TEXT;
  if (Index >= 0) and (Index < Items.Count) then
    Canvas.TextOut(Rect.Left + Logical(5), Rect.Top + Logical(2), Items[Index]);
end;

procedure TMapRakuGradientKindCombo.WMPaint(var Message: TWMPaint);
var
  Canvas: TCanvas;
  DC: HDC;
  R: TRect;
  X: Integer;
  Y: Integer;
begin
  inherited;
  DC := GetDC(Handle);
  Canvas := TCanvas.Create;
  try
    Canvas.Handle := DC;
    R := ClientRect;
    Canvas.Brush.Color := COLOR_EDIT;
    Canvas.Pen.Color := COLOR_EDIT_BORDER;
    Canvas.Rectangle(R);
    Canvas.Font := Font;
    if Enabled then
      Canvas.Font.Color := COLOR_TEXT
    else
      Canvas.Font.Color := clGray;
    if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    begin
      R.Right := R.Right - Logical(20);
      Canvas.TextRect(R, Logical(5),
        Max((ClientHeight - Canvas.TextHeight(Items[ItemIndex])) div 2, Logical(1)),
        Items[ItemIndex]);
    end;
    X := ClientWidth - Logical(11);
    Y := ClientHeight div 2;
    Canvas.Pen.Color := Canvas.Font.Color;
    Canvas.MoveTo(X - Logical(4), Y - Logical(2));
    Canvas.LineTo(X, Y + Logical(2));
    Canvas.LineTo(X + Logical(4), Y - Logical(2));
  finally
    Canvas.Handle := 0;
    Canvas.Free;
    ReleaseDC(Handle, DC);
  end;
end;

end.
