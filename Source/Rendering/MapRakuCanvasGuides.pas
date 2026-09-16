// 編集キャンバスの出力範囲を示す補助線の座標生成と描画を担当する。
unit MapRakuCanvasGuides;

interface

uses
  System.Types, Vcl.Direct2D, Vcl.Graphics;

// 表示矩形の四隅から一定間隔を空けたトンボ線を、始点と終点の組で返す。
function BuildCanvasCropMarkPoints(const CanvasBounds: TRect): TArray<TPoint>;
// GDIまたはDirect2Dへ画面ピクセル固定長のトンボ線を描く。
procedure DrawCanvasCropMarks(Target: TCanvas;
  const CanvasBounds: TRect); overload;
procedure DrawCanvasCropMarks(Target: TDirect2DCanvas;
  const CanvasBounds: TRect); overload;

implementation

uses
  MapRakuOverlayPrimitives;

const
  CANVAS_GUIDE_DARK        = clBlack;            // 明るい背景で輪郭を保つ外側の線色。
  CANVAS_GUIDE_LIGHT       = TColor($00D0D0D0); // 暗い背景で見える内側の線色。
  CANVAS_GUIDE_MARK_GAP    = 8;                  // キャンバス隅からトンボまでの画面px。
  CANVAS_GUIDE_MARK_LENGTH = 12;                 // ズームに依存しないトンボの画面px長。

function BuildCanvasCropMarkPoints(const CanvasBounds: TRect): TArray<TPoint>;
var
  Bottom: Integer;
  Left: Integer;
  Right: Integer;
  Top: Integer;

  procedure AddSegment(const StartPoint, EndPoint: TPoint);
  var
    Index: Integer;
  begin
    Index := Length(Result);
    SetLength(Result, Index + 2);
    Result[Index] := StartPoint;
    Result[Index + 1] := EndPoint;
  end;

begin
  Result := nil;
  if CanvasBounds.IsEmpty then
    Exit;
  Left := CanvasBounds.Left;
  Top := CanvasBounds.Top;
  Right := CanvasBounds.Right - 1;
  Bottom := CanvasBounds.Bottom - 1;

  AddSegment(Point(Left - CANVAS_GUIDE_MARK_GAP -
    CANVAS_GUIDE_MARK_LENGTH, Top),
    Point(Left - CANVAS_GUIDE_MARK_GAP, Top));
  AddSegment(Point(Left, Top - CANVAS_GUIDE_MARK_GAP -
    CANVAS_GUIDE_MARK_LENGTH), Point(Left, Top - CANVAS_GUIDE_MARK_GAP));
  AddSegment(Point(Right + CANVAS_GUIDE_MARK_GAP, Top),
    Point(Right + CANVAS_GUIDE_MARK_GAP + CANVAS_GUIDE_MARK_LENGTH, Top));
  AddSegment(Point(Right, Top - CANVAS_GUIDE_MARK_GAP -
    CANVAS_GUIDE_MARK_LENGTH), Point(Right, Top - CANVAS_GUIDE_MARK_GAP));
  AddSegment(Point(Left - CANVAS_GUIDE_MARK_GAP -
    CANVAS_GUIDE_MARK_LENGTH, Bottom),
    Point(Left - CANVAS_GUIDE_MARK_GAP, Bottom));
  AddSegment(Point(Left, Bottom + CANVAS_GUIDE_MARK_GAP),
    Point(Left, Bottom + CANVAS_GUIDE_MARK_GAP +
      CANVAS_GUIDE_MARK_LENGTH));
  AddSegment(Point(Right + CANVAS_GUIDE_MARK_GAP, Bottom),
    Point(Right + CANVAS_GUIDE_MARK_GAP + CANVAS_GUIDE_MARK_LENGTH, Bottom));
  AddSegment(Point(Right, Bottom + CANVAS_GUIDE_MARK_GAP),
    Point(Right, Bottom + CANVAS_GUIDE_MARK_GAP +
      CANVAS_GUIDE_MARK_LENGTH));
end;

procedure DrawCanvasCropMarks(Target: TCanvas;
  const CanvasBounds: TRect);
var
  I: Integer;
  Points: TArray<TPoint>;
begin
  Points := BuildCanvasCropMarkPoints(CanvasBounds);
  if Length(Points) = 0 then
    Exit;
  // 明暗の二重線にして、単色の範囲外背景上でも識別できるようにする。
  I := 0;
  while I + 1 < Length(Points) do
  begin
    DrawOverlayLine(Target, Points[I], Points[I + 1],
      CANVAS_GUIDE_LIGHT, psSolid, 3, 1, CANVAS_GUIDE_DARK);
    Inc(I, 2);
  end;
end;

procedure DrawCanvasCropMarks(Target: TDirect2DCanvas;
  const CanvasBounds: TRect);
var
  I: Integer;
  Points: TArray<TPoint>;
begin
  Points := BuildCanvasCropMarkPoints(CanvasBounds);
  if Length(Points) = 0 then
    Exit;
  // GDI経路と同じ太さと色順を使い、描画方式による見た目の差を抑える。
  I := 0;
  while I + 1 < Length(Points) do
  begin
    DrawOverlayLine(Target, Points[I], Points[I + 1],
      CANVAS_GUIDE_LIGHT, psSolid, 3, 1, CANVAS_GUIDE_DARK);
    Inc(I, 2);
  end;
end;

end.
