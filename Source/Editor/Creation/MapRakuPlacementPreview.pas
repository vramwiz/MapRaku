// 配置確定前の塗り図形を独立文書で描画し、通常描画と同じ色・塗り・透明度を再利用する。
unit MapRakuPlacementPreview;

interface

uses System.Types, Vcl.Graphics, MapRakuDocument, MapRakuEditorState,
  MapRakuPaintStyles, MapRakuCanvasRenderCache;

type
  TMapRakuPlacementPreview = class
  private
    FCache: TMapRakuCanvasRenderCache;  // 乗算済みRGBAプレビューを所有する。
    FBounds: TRect;                          // 前回の配置範囲。画面座標。
    FCanvasBounds: TRect;                    // 前回のキャンバス表示範囲。
    FCanvasWidth, FCanvasHeight: Integer;    // 前回の文書の論理サイズ。
    FZoom: Single;                           // 前回の論理座標から画面座標への倍率。
    FTool: TVectArtEditorTool;                // 前回描画した図形種別。
    FStyle: TMapRakuPaintStyle;          // 前回描画した塗り設定の値コピー。
    FStrokeWidth: Single;                     // 円弧の前回線幅。
    FStrokeStyle: TVectArtMifStrokeStyle; // 円弧の前回線種。
    FLineCap: TVectArtLineCap;            // 円弧の前回端形状。
    FOpacity: Single;                     // 前回描画したレイヤー透明度。
    function GetBitmap: TBitmap;
  public
    // 文書画像キャッシュを所有する。編集文書やEditorStateは所有しない。
    constructor Create;
    destructor Destroy; override;
    // 有効な配置範囲だけを描画する。編集文書・選択・Undoには変更を加えない。
    procedure Update(Document: TVectArtDocument; State: TVectArtEditorState;
      const Bounds, CanvasBounds: TRect; Zoom: Single);
    // Updateが生成したキャンバス寸法の乗算済み画像。所有権は本クラスに残る。
    property Bitmap: TBitmap read GetBitmap;
  end;

implementation

uses System.Math, MapRakuGeometry, MapRakuShapeOperations;

constructor TMapRakuPlacementPreview.Create;
begin
  inherited;
  FCache := TMapRakuCanvasRenderCache.Create;
end;

destructor TMapRakuPlacementPreview.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TMapRakuPlacementPreview.GetBitmap: TBitmap;
begin
  Result := FCache.Bitmap;
end;

procedure TMapRakuPlacementPreview.Update(Document: TVectArtDocument; State: TVectArtEditorState;
  const Bounds, CanvasBounds: TRect; Zoom: Single);
var
  Preview: TVectArtDocument;
  Layer: TVectArtLayer;
  LogicalBounds: TRectF;
begin
  if (Document = nil) or (State = nil) or (Zoom <= 0) or Bounds.IsEmpty or
    not (State.CurrentTool in [vetRectangle, vetRoundedRectangle, vetEllipse, vetArc, vetArcShape]) then
  begin
    FCache.Reset;
    Exit;
  end;
  if (Bitmap.Width > 0) and (FBounds = Bounds) and (FCanvasBounds = CanvasBounds) and
    (FCanvasWidth = Document.CanvasLayer.Width) and (FCanvasHeight = Document.CanvasLayer.Height) and
    SameValue(FZoom, Zoom) and (FTool = State.CurrentTool) and
    FStyle.SameAs(State.CreationPaintStyle) and SameValue(FOpacity, State.RectangleOpacity) and
    SameValue(FStrokeWidth, State.LineStrokeWidth) and (FStrokeStyle = State.LineMifStrokeStyle) and
    (FLineCap = State.LineCap) then Exit;
  LogicalBounds := TRectF.Create(
    ScreenToLogicalX(Bounds.Left, CanvasBounds, Zoom, Document.CanvasLayer.Width),
    ScreenToLogicalY(Bounds.Top, CanvasBounds, Zoom, Document.CanvasLayer.Height),
    ScreenToLogicalX(Bounds.Right, CanvasBounds, Zoom, Document.CanvasLayer.Width),
    ScreenToLogicalY(Bounds.Bottom, CanvasBounds, Zoom, Document.CanvasLayer.Height));
  Preview := TVectArtDocument.Create;
  try
    Preview.SetCanvasSize(Document.CanvasLayer.Width, Document.CanvasLayer.Height);
    Preview.CanvasLayer.Transparent := True;
    case State.CurrentTool of
      vetArcShape:
        begin
          Layer := TMapRakuEllipseArcShapeLayer.Create('', LogicalBounds, State.RectangleFillColor);
          TMapRakuEllipseArcShapeLayer(Layer).StartAngleDegrees := 180;
          TMapRakuEllipseArcShapeLayer(Layer).SweepAngleDegrees := 180;
        end;
      vetArc:
        begin
          Layer := TMapRakuArcLayer.Create('', LogicalBounds);
          TMapRakuArcLayer(Layer).StartAngleDegrees := 180;
          TMapRakuArcLayer(Layer).SweepAngleDegrees := 180;
          TMapRakuArcLayer(Layer).StrokeColor := State.LineStrokeColor;
          TMapRakuArcLayer(Layer).StrokeWidth := State.LineStrokeWidth;
          TMapRakuArcLayer(Layer).StrokeStyle := State.LineMifStrokeStyle;
          TMapRakuArcLayer(Layer).LineCap := State.LineCap;
        end;
      vetRoundedRectangle:
        Layer := TMapRakuRoundedRectangleLayer.Create('', LogicalBounds, State.RectangleFillColor,
          UniformMapRakuCornerRadii(Min(LogicalBounds.Width, LogicalBounds.Height) * 0.2));
      vetEllipse:
        Layer := TMapRakuEllipseLayer.Create('', LogicalBounds, State.RectangleFillColor);
    else
      Layer := TVectArtRectangleLayer.Create('', LogicalBounds, State.RectangleFillColor);
    end;
    Preview.InsertLayer(Preview.LayerCount, Layer);
    Layer.PaintStyle := State.CreationPaintStyle;
    Layer.Opacity := State.RectangleOpacity;
    FCache.Reset;
    FCache.Update(Preview, CanvasBounds.Width, CanvasBounds.Height, 0, nil, clNone, False, False);
    FBounds := Bounds;
    FCanvasBounds := CanvasBounds;
    FCanvasWidth := Document.CanvasLayer.Width;
    FCanvasHeight := Document.CanvasLayer.Height;
    FZoom := Zoom;
    FTool := State.CurrentTool;
    FStyle := State.CreationPaintStyle;
    FOpacity := State.RectangleOpacity;
    FStrokeWidth := State.LineStrokeWidth;
    FStrokeStyle := State.LineMifStrokeStyle;
    FLineCap := State.LineCap;
  finally
    Preview.Free;
  end;
end;

end.
