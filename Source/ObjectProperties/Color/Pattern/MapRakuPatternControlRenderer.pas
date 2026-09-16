// パターン設定コントロールのプレビュー生成と表示を担当し、入力状態の変更は行わない。
unit MapRakuPatternControlRenderer;

interface

uses System.Types, Vcl.Graphics, Vcl.Imaging.pngimage,
  MapRakuPatternStyle;

// 必要ならCPU側プレビューを再生成し、種類と色の選択ボタンを描く。
// Previewの所有権は呼び出し側が保持し、再生成後はPreviewDirtyをFalseにする。
procedure DrawMapRakuPatternControl(Canvas: TCanvas; const Bounds: TRect;
  PPI: Integer; ControlEnabled: Boolean;
  const Style: TMapRakuPatternStyle; const SlotId: string;
  Preview: TPngImage; var PreviewDirty: Boolean);

implementation

uses System.Classes, System.Math, System.Skia, System.UITypes,
  System.SysUtils, Winapi.Windows, MapRakuPatternRenderer;

const
  COLOR_BACKGROUND = TColor($00212121); // 親の色パネルと同じ背景色。
  COLOR_EDIT       = TColor($00303030); // 種類、色、数値の行背景。
  COLOR_BORDER     = TColor($00606060); // 未選択の種類と色の枠。
  COLOR_SELECTED   = TColor($00D77800); // 現在の種類、色、数値行の枠。
  PREVIEW_WIDTH    = 180;               // DPIと無関係な一時プレビュー幅。
  PREVIEW_HEIGHT   = 42;                // DPIと無関係な一時プレビュー高さ。
  CHECKER_SIZE     = 6;                 // 透明部分を示す市松の一辺。

function Logical(Value, PPI: Integer): Integer;
begin
  Result := MulDiv(Value, PPI, 96);
end;

procedure UpdatePreview(const Style: TMapRakuPatternStyle;
  Preview: TPngImage; var PreviewDirty: Boolean);
var
  Image: ISkImage;
  Paint: ISkPaint;
  Stream: TMemoryStream;
  Surface: ISkSurface;
begin
  if not PreviewDirty then
    Exit;
  Surface := TSkSurface.MakeRaster(PREVIEW_WIDTH, PREVIEW_HEIGHT);
  Surface.Canvas.Clear(TAlphaColorRec.Null);
  Paint := TSkPaint.Create;
  ApplyMapRakuPattern(Paint, Style,
    TRectF.Create(0, 0, PREVIEW_WIDTH, PREVIEW_HEIGHT), 0, 1);
  Surface.Canvas.DrawRect(
    TRectF.Create(0, 0, PREVIEW_WIDTH, PREVIEW_HEIGHT), Paint);
  Image := Surface.MakeImageSnapshot;
  Stream := TMemoryStream.Create;
  try
    Image.EncodeToStream(Stream);
    Stream.Position := 0;
    Preview.LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
  PreviewDirty := False;
end;

procedure DrawCheckerBackground(Canvas: TCanvas; const Bounds: TRect);
var
  X: Integer;
  Y: Integer;
begin
  for Y := Bounds.Top div CHECKER_SIZE to Bounds.Bottom div CHECKER_SIZE do
    for X := Bounds.Left div CHECKER_SIZE to Bounds.Right div CHECKER_SIZE do
    begin
      Canvas.Brush.Color := IfThen(Odd(X + Y), TColor($00707070),
        TColor($00A0A0A0));
      Canvas.FillRect(Rect(Max(X * CHECKER_SIZE, Bounds.Left),
        Max(Y * CHECKER_SIZE, Bounds.Top),
        Min(X * CHECKER_SIZE + CHECKER_SIZE, Bounds.Right),
        Min(Y * CHECKER_SIZE + CHECKER_SIZE, Bounds.Bottom)));
    end;
end;

procedure DrawMapRakuPatternControl(Canvas: TCanvas; const Bounds: TRect;
  PPI: Integer; ControlEnabled: Boolean;
  const Style: TMapRakuPatternStyle; const SlotId: string;
  Preview: TPngImage; var PreviewDirty: Boolean);
var
  ColorSlot: TMapRakuPatternColor;
  I: Integer;
  Kind: TMapRakuPatternKind;
  R: TRect;
  W: Integer;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(Bounds);
  if not ControlEnabled then
    Canvas.Font.Color := clGray;
  W := Max(Bounds.Width div 3, 1);
  for Kind := Low(Kind) to High(Kind) do
  begin
    R := Rect((Ord(Kind) mod 3) * W,
      Logical((Ord(Kind) div 3) * 24, PPI),
      (Ord(Kind) mod 3 + 1) * W - 2,
      Logical((Ord(Kind) div 3 + 1) * 24, PPI) - 2);
    Canvas.Brush.Color := COLOR_EDIT;
    Canvas.Pen.Color := COLOR_BORDER;
    if Kind = Style.Kind then
      Canvas.Pen.Color := COLOR_SELECTED;
    Canvas.Rectangle(R);
    DrawText(Canvas.Handle, PChar(PATTERN_NAMES[Kind]), -1, R,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  end;

  R := Rect(Bounds.Left, Logical(50, PPI), Bounds.Right,
    Logical(92, PPI));
  UpdatePreview(Style, Preview, PreviewDirty);
  DrawCheckerBackground(Canvas, R);
  Canvas.StretchDraw(R, Preview);

  I := 0;
  W := Max(Bounds.Width div Length(Style.Colors), 1);
  for ColorSlot in Style.Colors do
  begin
    R := Rect(I * W, Logical(96, PPI), (I + 1) * W - 2,
      Logical(120, PPI));
    Canvas.Brush.Color := COLOR_EDIT;
    Canvas.Pen.Color := COLOR_BORDER;
    if ColorSlot.Id = SlotId then
      Canvas.Pen.Color := COLOR_SELECTED;
    Canvas.Rectangle(R);
    Canvas.TextOut(R.Left + 3, R.Top + 4,
      MapRakuPatternColorName(Style.Kind, ColorSlot.Id));
    Inc(I);
  end;

end;

end.
