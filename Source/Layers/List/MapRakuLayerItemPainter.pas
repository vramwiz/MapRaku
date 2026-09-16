// 1行の選択背景、状態アイコン、サムネイルをGDI／Direct2Dへ描画する。
// 行の積層順、スクロール、選択変更はレイヤー一覧側が担当する。
unit MapRakuLayerItemPainter;

interface

uses
  System.Types, Vcl.Direct2D, Vcl.Graphics,
  MapRakuDocument, MapRakuEditorState, MapRakuLayerThumbnailCache;

type
  TMapRakuLayerItemPainter = class
  private
    FDocument   : TVectArtDocument;                 // 描画中の文書。所有しない。
    FEditorState: TVectArtEditorState;              // 開いたグループの表示を参照する。
    FThumbnails : TMapRakuLayerThumbnailCache; // 生成済み画像と作業バッファを所有する。
    FPPI        : Integer;                          // 論理寸法を描画ピクセルへ変換するDPI。
    function Scale(Value: Integer): Integer;
    function FitThumbnailRect(const AvailableRect: TRect; LogicalWidth, LogicalHeight: Integer): TRect;
  public
    // 行サムネイル用の作業領域とキャッシュを生成する。
    constructor Create;
    // 所有する画像と作業領域を破棄する。
    destructor Destroy; override;
    // 描画対象を設定し、文書・DPI・Revisionの変更に応じてキャッシュを更新する。
    procedure Configure(Document: TVectArtDocument; State: TVectArtEditorState; PPI: Integer);
    // 文書の交換やDPI変更で使えなくなったサムネイルを破棄する。
    procedure ResetCache;
    // 指定行の背景、アイコン、サムネイルをGDIへ描く。選択状態は変更しない。
    procedure DrawLayerItem(ACanvas: TCanvas; const ItemRect: TRect; Layer: TVectArtLayer;
      Selected, Active: Boolean); overload;
    // 同じ行内容をDirect2Dへ描く。
    procedure DrawLayerItem(ACanvas: TDirect2DCanvas; const ItemRect: TRect; Layer: TVectArtLayer;
      Selected, Active: Boolean); overload;
    // ロック操作の当たり判定矩形を現在DPIで返す。
    function LockButtonRect(const ItemRect: TRect): TRect;
    // グループ開閉操作の当たり判定矩形を現在DPIで返す。
    function ExpandButtonRect(const ItemRect: TRect): TRect;
    // 表示切り替え操作の当たり判定矩形を現在DPIで返す。
    function VisibilityButtonRect(const ItemRect: TRect): TRect;
  end;

implementation

uses
  System.Math, Winapi.Windows, MapRakuLayerListStyle;

constructor TMapRakuLayerItemPainter.Create;
begin
  inherited Create;
  FThumbnails := TMapRakuLayerThumbnailCache.Create;
  FPPI := 96;
end;

destructor TMapRakuLayerItemPainter.Destroy;
begin
  FThumbnails.Free;
  inherited Destroy;
end;

function TMapRakuLayerItemPainter.Scale(Value: Integer): Integer;
begin
  Result := MulDiv(Value, FPPI, 96);
end;

procedure TMapRakuLayerItemPainter.ResetCache;
begin
  FThumbnails.Clear;
end;

procedure TMapRakuLayerItemPainter.Configure(Document: TVectArtDocument;
  State: TVectArtEditorState; PPI: Integer);
begin
  if (FDocument <> Document) or (FPPI <> PPI) then ResetCache;
  FDocument := Document;
  FEditorState := State;
  FPPI := Max(1, PPI);
  FThumbnails.Configure(FDocument, FPPI);
end;

procedure TMapRakuLayerItemPainter.DrawLayerItem(ACanvas: TCanvas;
  const ItemRect: TRect; Layer: TVectArtLayer; Selected, Active: Boolean);
var
  CanvasLayer: TVectArtCanvasLayer;
  CellRect: TRect;
  Column: Integer;
  ExpandPoints: array[0..2] of TPoint;
  ExpandRect: TRect;
  LockRect: TRect;
  Row: Integer;
  ThumbnailArea: TRect;
  ThumbnailRect: TRect;
  VisibilityRect: TRect;
begin
  ACanvas.Brush.Style := bsSolid;
  if Active then
    ACanvas.Brush.Color := COLOR_ROW_ACTIVE_BACKGROUND
  else if Selected then
    ACanvas.Brush.Color := COLOR_ROW_SELECTED
  else
    ACanvas.Brush.Color := COLOR_ROW_BACKGROUND;
  ACanvas.FillRect(ItemRect);
  ACanvas.Brush.Style := bsClear;
  if Active then
    ACanvas.Pen.Color := COLOR_ROW_ACTIVE
  else ACanvas.Pen.Color := COLOR_ROW_BORDER;
  ACanvas.FrameRect(ItemRect);
  if Active then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_ROW_ACTIVE;
    ACanvas.FillRect(Rect(ItemRect.Left, ItemRect.Top,
      ItemRect.Left + Scale(4), ItemRect.Bottom));
    ACanvas.Brush.Style := bsClear;
  end;

  ThumbnailArea := Rect(ItemRect.Left + Scale(30),
    ItemRect.Top + (ItemRect.Height - Scale(THUMBNAIL_HEIGHT)) div 2,
    Min(ItemRect.Left + Scale(30 + THUMBNAIL_WIDTH),
      ItemRect.Right - Scale(8)),
    ItemRect.Top + (ItemRect.Height + Scale(THUMBNAIL_HEIGHT)) div 2);
  CanvasLayer := nil;
  if FDocument <> nil then
    CanvasLayer := FDocument.CanvasLayer;
  if (Layer is TVectArtCanvasLayer) and (CanvasLayer <> nil) then
    ThumbnailRect := FitThumbnailRect(ThumbnailArea, CanvasLayer.Width,
      CanvasLayer.Height)
  else
    ThumbnailRect := ThumbnailArea;

  ACanvas.Brush.Style := bsSolid;
  if (Layer is TVectArtCanvasLayer) and
    not TVectArtCanvasLayer(Layer).Transparent then
  begin
    ACanvas.Brush.Color := TVectArtCanvasLayer(Layer).BackgroundColor;
    ACanvas.FillRect(ThumbnailRect);
  end
  else
  begin
    Row := 0;
    while ThumbnailRect.Top + Row * Scale(THUMBNAIL_CHECKER_SIZE) <
      ThumbnailRect.Bottom do
    begin
      Column := 0;
      while ThumbnailRect.Left + Column * Scale(THUMBNAIL_CHECKER_SIZE) <
        ThumbnailRect.Right do
      begin
        CellRect := Rect(
          ThumbnailRect.Left + Column * Scale(THUMBNAIL_CHECKER_SIZE),
          ThumbnailRect.Top + Row * Scale(THUMBNAIL_CHECKER_SIZE),
          Min(ThumbnailRect.Left + (Column + 1) *
            Scale(THUMBNAIL_CHECKER_SIZE),
            ThumbnailRect.Right),
          Min(ThumbnailRect.Top + (Row + 1) *
            Scale(THUMBNAIL_CHECKER_SIZE),
            ThumbnailRect.Bottom));
        if Odd(Row + Column) then
          ACanvas.Brush.Color := TColor($00B8B8B8)
        else
          ACanvas.Brush.Color := clWhite;
        ACanvas.FillRect(CellRect);
        Inc(Column);
      end;
      Inc(Row);
    end;
  end;
  if not (Layer is TVectArtCanvasLayer) then
    FThumbnails.Draw(ACanvas, ThumbnailRect, Layer);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := COLOR_THUMB_BORDER;
  ACanvas.FrameRect(ThumbnailRect);

  if Layer is TMapRakuGroupLayer then
  begin
    // 名称列を省いても開閉操作を失わないよう、三角だけを状態列へ残す。
    ExpandRect := ExpandButtonRect(ItemRect);
    if (FEditorState <> nil) and FEditorState.IsGroupInOpenPath(
      TMapRakuGroupLayer(Layer)) then
    begin
      ExpandPoints[0] := Point(ExpandRect.Left + Scale(5),
        ExpandRect.Top + Scale(4));
      ExpandPoints[1] := Point(ExpandRect.Right - Scale(5),
        ExpandRect.Top + Scale(4));
      ExpandPoints[2] := Point((ExpandRect.Left + ExpandRect.Right) div 2,
        ExpandRect.Bottom - Scale(3));
    end
    else
    begin
      ExpandPoints[0] := Point(ExpandRect.Left + Scale(6),
        ExpandRect.Top + Scale(2));
      ExpandPoints[1] := Point(ExpandRect.Left + Scale(6),
        ExpandRect.Bottom - Scale(2));
      ExpandPoints[2] := Point(ExpandRect.Right - Scale(4),
        (ExpandRect.Top + ExpandRect.Bottom) div 2);
    end;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_TEXT_SECONDARY;
    ACanvas.Polygon(ExpandPoints);
  end;

  VisibilityRect := VisibilityButtonRect(ItemRect);
  LockRect := LockButtonRect(ItemRect);
  ACanvas.Pen.Color := COLOR_TEXT_SECONDARY;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Ellipse(VisibilityRect.Left + Scale(2),
    VisibilityRect.Top + Scale(5), VisibilityRect.Right - Scale(2),
    VisibilityRect.Bottom - Scale(5));
  if Layer.Visible then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_TEXT_PRIMARY;
    ACanvas.Ellipse(VisibilityRect.Left + Scale(8),
      VisibilityRect.Top + Scale(8), VisibilityRect.Left + Scale(12),
      VisibilityRect.Top + Scale(12));
  end;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Rectangle(LockRect.Left + Scale(3), LockRect.Top + Scale(8),
    LockRect.Right - Scale(3), LockRect.Bottom - Scale(2));
  ACanvas.MoveTo(LockRect.Left + Scale(6), LockRect.Top + Scale(8));
  ACanvas.LineTo(LockRect.Left + Scale(6), LockRect.Top + Scale(3));
  ACanvas.LineTo(LockRect.Right - Scale(6), LockRect.Top + Scale(3));
  if Layer.Locked then
    ACanvas.LineTo(LockRect.Right - Scale(6), LockRect.Top + Scale(8));
end;

procedure TMapRakuLayerItemPainter.DrawLayerItem(ACanvas: TDirect2DCanvas;
  const ItemRect: TRect; Layer: TVectArtLayer; Selected, Active: Boolean);
var
  CanvasLayer: TVectArtCanvasLayer;
  CellRect: TRect;
  Column: Integer;
  ExpandPoints: array[0..2] of TPoint;
  ExpandRect: TRect;
  LockRect: TRect;
  Row: Integer;
  ThumbnailArea: TRect;
  ThumbnailRect: TRect;
  VisibilityRect: TRect;
begin
  ACanvas.Brush.Style := bsSolid;
  if Active then
    ACanvas.Brush.Color := COLOR_ROW_ACTIVE_BACKGROUND
  else if Selected then
    ACanvas.Brush.Color := COLOR_ROW_SELECTED
  else
    ACanvas.Brush.Color := COLOR_ROW_BACKGROUND;
  ACanvas.FillRect(ItemRect);
  ACanvas.Brush.Style := bsClear;
  if Active then
    ACanvas.Pen.Color := COLOR_ROW_ACTIVE
  else ACanvas.Pen.Color := COLOR_ROW_BORDER;
  ACanvas.FrameRect(ItemRect);
  if Active then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_ROW_ACTIVE;
    ACanvas.FillRect(Rect(ItemRect.Left, ItemRect.Top,
      ItemRect.Left + Scale(4), ItemRect.Bottom));
    ACanvas.Brush.Style := bsClear;
  end;

  ThumbnailArea := Rect(ItemRect.Left + Scale(30),
    ItemRect.Top + (ItemRect.Height - Scale(THUMBNAIL_HEIGHT)) div 2,
    Min(ItemRect.Left + Scale(30 + THUMBNAIL_WIDTH),
      ItemRect.Right - Scale(8)),
    ItemRect.Top + (ItemRect.Height + Scale(THUMBNAIL_HEIGHT)) div 2);
  CanvasLayer := nil;
  if FDocument <> nil then
    CanvasLayer := FDocument.CanvasLayer;
  if (Layer is TVectArtCanvasLayer) and (CanvasLayer <> nil) then
    ThumbnailRect := FitThumbnailRect(ThumbnailArea, CanvasLayer.Width,
      CanvasLayer.Height)
  else
    ThumbnailRect := ThumbnailArea;

  ACanvas.Brush.Style := bsSolid;
  if (Layer is TVectArtCanvasLayer) and
    not TVectArtCanvasLayer(Layer).Transparent then
  begin
    ACanvas.Brush.Color := TVectArtCanvasLayer(Layer).BackgroundColor;
    ACanvas.FillRect(ThumbnailRect);
  end
  else
  begin
    Row := 0;
    while ThumbnailRect.Top + Row * Scale(THUMBNAIL_CHECKER_SIZE) <
      ThumbnailRect.Bottom do
    begin
      Column := 0;
      while ThumbnailRect.Left + Column * Scale(THUMBNAIL_CHECKER_SIZE) <
        ThumbnailRect.Right do
      begin
        CellRect := Rect(
          ThumbnailRect.Left + Column * Scale(THUMBNAIL_CHECKER_SIZE),
          ThumbnailRect.Top + Row * Scale(THUMBNAIL_CHECKER_SIZE),
          Min(ThumbnailRect.Left + (Column + 1) *
            Scale(THUMBNAIL_CHECKER_SIZE),
            ThumbnailRect.Right),
          Min(ThumbnailRect.Top + (Row + 1) *
            Scale(THUMBNAIL_CHECKER_SIZE),
            ThumbnailRect.Bottom));
        if Odd(Row + Column) then
          ACanvas.Brush.Color := TColor($00B8B8B8)
        else
          ACanvas.Brush.Color := clWhite;
        ACanvas.FillRect(CellRect);
        Inc(Column);
      end;
      Inc(Row);
    end;
  end;
  if not (Layer is TVectArtCanvasLayer) then
    FThumbnails.Draw(ACanvas, ThumbnailRect, Layer);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := COLOR_THUMB_BORDER;
  ACanvas.FrameRect(ThumbnailRect);

  if Layer is TMapRakuGroupLayer then
  begin
    // GDI経路と同じ当たり判定矩形を使い、描画方式で操作位置を変えない。
    ExpandRect := ExpandButtonRect(ItemRect);
    if (FEditorState <> nil) and FEditorState.IsGroupInOpenPath(
      TMapRakuGroupLayer(Layer)) then
    begin
      ExpandPoints[0] := Point(ExpandRect.Left + Scale(5),
        ExpandRect.Top + Scale(4));
      ExpandPoints[1] := Point(ExpandRect.Right - Scale(5),
        ExpandRect.Top + Scale(4));
      ExpandPoints[2] := Point((ExpandRect.Left + ExpandRect.Right) div 2,
        ExpandRect.Bottom - Scale(3));
    end
    else
    begin
      ExpandPoints[0] := Point(ExpandRect.Left + Scale(6),
        ExpandRect.Top + Scale(2));
      ExpandPoints[1] := Point(ExpandRect.Left + Scale(6),
        ExpandRect.Bottom - Scale(2));
      ExpandPoints[2] := Point(ExpandRect.Right - Scale(4),
        (ExpandRect.Top + ExpandRect.Bottom) div 2);
    end;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_TEXT_SECONDARY;
    ACanvas.Polygon(ExpandPoints);
  end;

  VisibilityRect := VisibilityButtonRect(ItemRect);
  LockRect := LockButtonRect(ItemRect);
  ACanvas.Pen.Color := COLOR_TEXT_SECONDARY;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Ellipse(VisibilityRect.Left + Scale(2),
    VisibilityRect.Top + Scale(5), VisibilityRect.Right - Scale(2),
    VisibilityRect.Bottom - Scale(5));
  if Layer.Visible then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_TEXT_PRIMARY;
    ACanvas.Ellipse(VisibilityRect.Left + Scale(8),
      VisibilityRect.Top + Scale(8), VisibilityRect.Left + Scale(12),
      VisibilityRect.Top + Scale(12));
  end;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Rectangle(LockRect.Left + Scale(3), LockRect.Top + Scale(8),
    LockRect.Right - Scale(3), LockRect.Bottom - Scale(2));
  ACanvas.MoveTo(LockRect.Left + Scale(6), LockRect.Top + Scale(8));
  ACanvas.LineTo(LockRect.Left + Scale(6), LockRect.Top + Scale(3));
  ACanvas.LineTo(LockRect.Right - Scale(6), LockRect.Top + Scale(3));
  if Layer.Locked then
    ACanvas.LineTo(LockRect.Right - Scale(6), LockRect.Top + Scale(8));
end;

function TMapRakuLayerItemPainter.FitThumbnailRect(
  const AvailableRect: TRect; LogicalWidth, LogicalHeight: Integer): TRect;
var
  DrawHeight: Integer;
  DrawWidth: Integer;
  Scale: Double;
begin
  if (AvailableRect.Width <= 0) or (AvailableRect.Height <= 0) then
    Exit(TRect.Empty);
  Scale := Min(AvailableRect.Width / Max(LogicalWidth, 1),
    AvailableRect.Height / Max(LogicalHeight, 1));
  DrawWidth := Max(Round(LogicalWidth * Scale), 1);
  DrawHeight := Max(Round(LogicalHeight * Scale), 1);
  Result.Left := AvailableRect.Left + (AvailableRect.Width - DrawWidth) div 2;
  Result.Top := AvailableRect.Top + (AvailableRect.Height - DrawHeight) div 2;
  Result.Right := Result.Left + DrawWidth;
  Result.Bottom := Result.Top + DrawHeight;
end;

function TMapRakuLayerItemPainter.LockButtonRect(
  const ItemRect: TRect): TRect;
begin
  Result := Rect(ItemRect.Left + Scale(STATE_COLUMN_LEFT),
    ItemRect.Top + Scale(LOCK_BUTTON_TOP),
    ItemRect.Left + Scale(STATE_COLUMN_LEFT + STATE_BUTTON_SIZE),
    ItemRect.Top + Scale(LOCK_BUTTON_TOP + STATE_BUTTON_SIZE));
end;

function TMapRakuLayerItemPainter.ExpandButtonRect(
  const ItemRect: TRect): TRect;
begin
  Result := Rect(ItemRect.Left + Scale(STATE_COLUMN_LEFT),
    ItemRect.Top + Scale(1),
    ItemRect.Left + Scale(STATE_COLUMN_LEFT + STATE_BUTTON_SIZE),
    ItemRect.Top + Scale(15));
end;

function TMapRakuLayerItemPainter.VisibilityButtonRect(
  const ItemRect: TRect): TRect;
begin
  Result := Rect(ItemRect.Left + Scale(STATE_COLUMN_LEFT),
    ItemRect.Top + Scale(VISIBILITY_BUTTON_TOP),
    ItemRect.Left + Scale(STATE_COLUMN_LEFT + STATE_BUTTON_SIZE),
    ItemRect.Top + Scale(VISIBILITY_BUTTON_TOP + STATE_BUTTON_SIZE));
end;

end.
