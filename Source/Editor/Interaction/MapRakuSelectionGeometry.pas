// 選択枠、リサイズマーカー、上辺中央の回転マーカーを計算する。
unit MapRakuSelectionGeometry;

interface

uses
  System.Types, Vcl.Controls;

type
  TVectArtScreenQuad = array[0..3] of TPoint;

  TVectArtSelectionHandle = (vshNone, vshTopLeft, vshTop,
    vshTopRight, vshRight, vshBottomRight, vshBottom,
    vshBottomLeft, vshLeft);

  TVectArtSelectionGeometry = record
    DrawFrame: Boolean;                          // 選択枠本体を描画する場合にTrue。
    FrameRect: TRect;                            // 回転しない選択枠の画面範囲。
    FramePoints: array[0..4] of TPoint;           // 閉じた回転選択枠の5点。
    Handles: array[vshTopLeft..vshLeft] of TRect; // 8方向リサイズハンドルの描画範囲。
    PrimaryRotationHandle: TRect;                // 上辺中央の回転マーク範囲。
    RotationStem: array[0..1] of TPoint;          // 選択枠から回転マークへ結ぶ線分。
  end;

// 線幅とズームを考慮し、選択枠を図形から離す画面上の距離を返す。
function SelectionFrameOffset(StrokeWidth, Zoom: Single): Integer;
// 回転しない矩形について、選択枠、8方向ハンドル、回転マークを構築する。
function BuildSelectionGeometry(const LayerRect: TRect;
  FrameOffset: Integer = 8): TVectArtSelectionGeometry;
// 任意の四辺形について、辺方向に沿う選択枠、8方向ハンドル、回転マークを構築する。
function BuildRotatedSelectionGeometry(
  const Quad: TVectArtScreenQuad;
  FrameOffset: Integer = 8): TVectArtSelectionGeometry;
// 2点の単線について、両端を操作する選択ハンドルを構築する。
function BuildLineSelectionGeometry(const StartPoint,
  EndPoint: TPoint): TVectArtSelectionGeometry;
// Pathの外接矩形について、共通変形用の選択枠を構築する。
function BuildPathSelectionGeometry(const LayerRect: TRect;
  FrameOffset: Integer = 8): TVectArtSelectionGeometry;
// 単線の端点から選択ハンドルを離す固定距離を返す。
function LineSelectionHandleDistance: Integer;
// ハンドルまたは選択枠の辺からリサイズ方向を返す。
function HitTestSelectionHandle(const Point: TPoint;
  const Geometry: TVectArtSelectionGeometry): TVectArtSelectionHandle;
// 指定位置が上辺中央の回転マーク内ならTrueを返す。
function HitTestRotationHandle(const Point: TPoint;
  const Geometry: TVectArtSelectionGeometry): Boolean;
// 回転操作を表す円弧矢印カーソルを返す。画像リソースは使用しない。
function RotationHandleCursor: TCursor;
// リサイズ方向に対応する標準カーソルを返す。
function SelectionHandleCursor(Handle: TVectArtSelectionHandle): TCursor;

implementation

uses
  System.Math, Vcl.Forms, Winapi.Windows;

const
  SELECTION_FRAME_OFFSET = 6;
  SELECTION_HANDLE_SIZE = 8;
  PRIMARY_ROTATION_HANDLE_SIZE = 18;
  PRIMARY_ROTATION_HANDLE_OFFSET = 30;
  LINE_HANDLE_GAP = 6;
  HANDLE_HIT_PADDING = 1; // 見えているハンドルの近傍だけを操作対象にする。
  FRAME_HIT_DISTANCE = 2; // 選択枠の線をドラッグできる画面px。
  CR_VECTART_ROTATE = 101;

var
  RotationCursorHandle: HCURSOR;

function CreateRotationCursor: HCURSOR;
var
  AndMask: array[0..127] of Byte;
  Angle: Integer;
  XorMask: array[0..127] of Byte;

  procedure SetPixel(X, Y: Integer);
  var
    ByteIndex: Integer;
  begin
    if (X < 0) or (X >= 32) or (Y < 0) or (Y >= 32) then
      Exit;
    ByteIndex := Y * 4 + X div 8;
    XorMask[ByteIndex] := XorMask[ByteIndex] or (Byte($80) shr (X mod 8));
  end;

  procedure DrawLine(X1, Y1, X2, Y2: Integer);
  var
    DX: Integer;
    DY: Integer;
    ErrorValue: Integer;
    StepX: Integer;
    StepY: Integer;
  begin
    DX := Abs(X2 - X1);
    DY := -Abs(Y2 - Y1);
    if X1 < X2 then
      StepX := 1
    else
      StepX := -1;
    if Y1 < Y2 then
      StepY := 1
    else
      StepY := -1;
    ErrorValue := DX + DY;
    while True do
    begin
      SetPixel(X1, Y1);
      SetPixel(X1 + 1, Y1);
      if (X1 = X2) and (Y1 = Y2) then
        Break;
      if ErrorValue * 2 >= DY then
      begin
        ErrorValue := ErrorValue + DY;
        X1 := X1 + StepX;
      end;
      if ErrorValue * 2 <= DX then
      begin
        ErrorValue := ErrorValue + DX;
        Y1 := Y1 + StepY;
      end;
    end;
  end;

begin
  FillChar(AndMask, SizeOf(AndMask), $FF);
  FillChar(XorMask, SizeOf(XorMask), 0);
  for Angle := 35 to 325 do
    if Angle mod 3 = 0 then
    begin
      SetPixel(Round(16 + 10 * Cos(DegToRad(Angle))),
        Round(16 - 10 * Sin(DegToRad(Angle))));
      SetPixel(Round(16 + 9 * Cos(DegToRad(Angle))),
        Round(16 - 9 * Sin(DegToRad(Angle))));
    end;
  DrawLine(24, 10, 19, 8);
  DrawLine(24, 10, 22, 15);
  Result := CreateCursor(HInstance, 16, 16, 32, 32, @AndMask[0],
    @XorMask[0]);
end;

function SelectionFrameOffset(StrokeWidth, Zoom: Single): Integer;
begin
  Result := SELECTION_FRAME_OFFSET +
    Ceil(Max(0.0, StrokeWidth) * Max(0.0, Zoom) * 0.5);
end;

function LineSelectionHandleDistance: Integer;
begin
  Result := SELECTION_HANDLE_SIZE div 2 + LINE_HANDLE_GAP;
end;

function BuildSelectionGeometry(const LayerRect: TRect;
  FrameOffset: Integer): TVectArtSelectionGeometry;
var
  CenterX: Integer;
  CenterY: Integer;
  HalfHandle: Integer;

  function HandleRect(X, Y: Integer): TRect;
  begin
    Result := Rect(X - HalfHandle, Y - HalfHandle,
      X - HalfHandle + SELECTION_HANDLE_SIZE,
      Y - HalfHandle + SELECTION_HANDLE_SIZE);
  end;

  function PrimaryRotationHandleRect(X, Y: Integer): TRect;
  var
    HalfPrimaryHandle: Integer;
  begin
    HalfPrimaryHandle := PRIMARY_ROTATION_HANDLE_SIZE div 2;
    Result := Rect(X - HalfPrimaryHandle, Y - HalfPrimaryHandle,
      X - HalfPrimaryHandle + PRIMARY_ROTATION_HANDLE_SIZE,
      Y - HalfPrimaryHandle + PRIMARY_ROTATION_HANDLE_SIZE);
  end;

begin
  Result.FrameRect := LayerRect;
  Result.DrawFrame := True;
  FrameOffset := Max(0, FrameOffset);
  InflateRect(Result.FrameRect, FrameOffset, FrameOffset);
  CenterX := (Result.FrameRect.Left + Result.FrameRect.Right) div 2;
  CenterY := (Result.FrameRect.Top + Result.FrameRect.Bottom) div 2;
  HalfHandle := SELECTION_HANDLE_SIZE div 2;
  Result.FramePoints[0] := Result.FrameRect.TopLeft;
  Result.FramePoints[1] := Point(Result.FrameRect.Right,
    Result.FrameRect.Top);
  Result.FramePoints[2] := Result.FrameRect.BottomRight;
  Result.FramePoints[3] := Point(Result.FrameRect.Left,
    Result.FrameRect.Bottom);
  Result.FramePoints[4] := Result.FramePoints[0];
  Result.Handles[vshTopLeft] := HandleRect(Result.FrameRect.Left,
    Result.FrameRect.Top);
  Result.Handles[vshTop] := HandleRect(CenterX, Result.FrameRect.Top);
  Result.Handles[vshTopRight] := HandleRect(Result.FrameRect.Right,
    Result.FrameRect.Top);
  Result.Handles[vshRight] := HandleRect(Result.FrameRect.Right, CenterY);
  Result.Handles[vshBottomRight] := HandleRect(Result.FrameRect.Right,
    Result.FrameRect.Bottom);
  Result.Handles[vshBottom] := HandleRect(CenterX, Result.FrameRect.Bottom);
  Result.Handles[vshBottomLeft] := HandleRect(Result.FrameRect.Left,
    Result.FrameRect.Bottom);
  Result.Handles[vshLeft] := HandleRect(Result.FrameRect.Left, CenterY);
  Result.PrimaryRotationHandle := PrimaryRotationHandleRect(CenterX,
    Result.FrameRect.Top - PRIMARY_ROTATION_HANDLE_OFFSET);
  Result.RotationStem[0] := Point(CenterX,
    Result.FrameRect.Top - HalfHandle);
  Result.RotationStem[1] := Point(CenterX,
    Result.PrimaryRotationHandle.Bottom);
end;

function BuildRotatedSelectionGeometry(
  const Quad: TVectArtScreenQuad;
  FrameOffset: Integer): TVectArtSelectionGeometry;
var
  Distance: Single;
  HalfHandle: Integer;
  I: Integer;
  Midpoint: TPoint;
  OutwardX: array[0..3] of Single;
  OutwardY: array[0..3] of Single;
  UnitX: Single;
  UnitY: Single;
  AxisUX: Single;
  AxisUY: Single;
  AxisVX: Single;
  AxisVY: Single;

  function HandleRect(X, Y: Integer): TRect;
  begin
    Result := Rect(X - HalfHandle, Y - HalfHandle,
      X - HalfHandle + SELECTION_HANDLE_SIZE,
      Y - HalfHandle + SELECTION_HANDLE_SIZE);
  end;

  function PrimaryRotationHandleRect(X, Y: Integer): TRect;
  var
    HalfPrimaryHandle: Integer;
  begin
    HalfPrimaryHandle := PRIMARY_ROTATION_HANDLE_SIZE div 2;
    Result := Rect(X - HalfPrimaryHandle, Y - HalfPrimaryHandle,
      X - HalfPrimaryHandle + PRIMARY_ROTATION_HANDLE_SIZE,
      Y - HalfPrimaryHandle + PRIMARY_ROTATION_HANDLE_SIZE);
  end;

begin
  Result.DrawFrame := True;
  FrameOffset := Max(0, FrameOffset);
  AxisUX := 0;
  AxisUY := 0;
  AxisVX := 0;
  AxisVY := 0;
  Distance := Hypot(Quad[1].X - Quad[0].X, Quad[1].Y - Quad[0].Y);
  if Distance > 0 then
  begin
    AxisUX := (Quad[1].X - Quad[0].X) / Distance;
    AxisUY := (Quad[1].Y - Quad[0].Y) / Distance;
  end;
  Distance := Hypot(Quad[3].X - Quad[0].X, Quad[3].Y - Quad[0].Y);
  if Distance > 0 then
  begin
    AxisVX := (Quad[3].X - Quad[0].X) / Distance;
    AxisVY := (Quad[3].Y - Quad[0].Y) / Distance;
  end;
  OutwardX[0] := -AxisUX - AxisVX;
  OutwardY[0] := -AxisUY - AxisVY;
  OutwardX[1] := AxisUX - AxisVX;
  OutwardY[1] := AxisUY - AxisVY;
  OutwardX[2] := AxisUX + AxisVX;
  OutwardY[2] := AxisUY + AxisVY;
  OutwardX[3] := -AxisUX + AxisVX;
  OutwardY[3] := -AxisUY + AxisVY;
  HalfHandle := SELECTION_HANDLE_SIZE div 2;
  Result.FrameRect := TRect.Empty;
  for I := 0 to High(Quad) do
  begin
    Result.FramePoints[I] := Point(
      Round(Quad[I].X + OutwardX[I] * FrameOffset),
      Round(Quad[I].Y + OutwardY[I] * FrameOffset));
    if I = 0 then
      Result.FrameRect := Rect(Result.FramePoints[I].X,
        Result.FramePoints[I].Y, Result.FramePoints[I].X,
        Result.FramePoints[I].Y)
    else
    begin
      Result.FrameRect.Left := Min(Result.FrameRect.Left,
        Result.FramePoints[I].X);
      Result.FrameRect.Top := Min(Result.FrameRect.Top,
        Result.FramePoints[I].Y);
      Result.FrameRect.Right := Max(Result.FrameRect.Right,
        Result.FramePoints[I].X);
      Result.FrameRect.Bottom := Max(Result.FrameRect.Bottom,
        Result.FramePoints[I].Y);
    end;
  end;
  Result.FramePoints[4] := Result.FramePoints[0];
  Result.Handles[vshTopLeft] := HandleRect(Result.FramePoints[0].X,
    Result.FramePoints[0].Y);
  Midpoint := Point((Result.FramePoints[0].X + Result.FramePoints[1].X) div 2,
    (Result.FramePoints[0].Y + Result.FramePoints[1].Y) div 2);
  Result.Handles[vshTop] := HandleRect(Midpoint.X, Midpoint.Y);
  Result.Handles[vshTopRight] := HandleRect(Result.FramePoints[1].X,
    Result.FramePoints[1].Y);
  Midpoint := Point((Result.FramePoints[1].X + Result.FramePoints[2].X) div 2,
    (Result.FramePoints[1].Y + Result.FramePoints[2].Y) div 2);
  Result.Handles[vshRight] := HandleRect(Midpoint.X, Midpoint.Y);
  Result.Handles[vshBottomRight] := HandleRect(Result.FramePoints[2].X,
    Result.FramePoints[2].Y);
  Midpoint := Point((Result.FramePoints[2].X + Result.FramePoints[3].X) div 2,
    (Result.FramePoints[2].Y + Result.FramePoints[3].Y) div 2);
  Result.Handles[vshBottom] := HandleRect(Midpoint.X, Midpoint.Y);
  Result.Handles[vshBottomLeft] := HandleRect(Result.FramePoints[3].X,
    Result.FramePoints[3].Y);
  Midpoint := Point((Result.FramePoints[3].X + Result.FramePoints[0].X) div 2,
    (Result.FramePoints[3].Y + Result.FramePoints[0].Y) div 2);
  Result.Handles[vshLeft] := HandleRect(Midpoint.X, Midpoint.Y);
  Midpoint := Point((Result.FramePoints[0].X + Result.FramePoints[1].X) div 2,
    (Result.FramePoints[0].Y + Result.FramePoints[1].Y) div 2);
  UnitX := -AxisVX;
  UnitY := -AxisVY;
  Result.PrimaryRotationHandle := PrimaryRotationHandleRect(
    Round(Midpoint.X + UnitX * PRIMARY_ROTATION_HANDLE_OFFSET),
    Round(Midpoint.Y + UnitY * PRIMARY_ROTATION_HANDLE_OFFSET));
  Result.RotationStem[0] := Point(
    Round(Midpoint.X + UnitX * HalfHandle),
    Round(Midpoint.Y + UnitY * HalfHandle));
  Result.RotationStem[1] := Point(
    Round(Midpoint.X + UnitX *
      (PRIMARY_ROTATION_HANDLE_OFFSET -
       PRIMARY_ROTATION_HANDLE_SIZE * 0.5)),
    Round(Midpoint.Y + UnitY *
      (PRIMARY_ROTATION_HANDLE_OFFSET -
       PRIMARY_ROTATION_HANDLE_SIZE * 0.5)));
end;

function BuildLineSelectionGeometry(const StartPoint,
  EndPoint: TPoint): TVectArtSelectionGeometry;
var
  Distance: Single;
  HalfHandle: Integer;
  UnitX: Single;
  UnitY: Single;
  EndHandlePoint: TPoint;
  StartHandlePoint: TPoint;

  function HandleRect(const PointValue: TPoint): TRect;
  begin
    Result := Rect(PointValue.X - HalfHandle, PointValue.Y - HalfHandle,
      PointValue.X - HalfHandle + SELECTION_HANDLE_SIZE,
      PointValue.Y - HalfHandle + SELECTION_HANDLE_SIZE);
  end;

  function PrimaryRotationHandleRect(X, Y: Integer): TRect;
  var
    HalfPrimaryHandle: Integer;
  begin
    HalfPrimaryHandle := PRIMARY_ROTATION_HANDLE_SIZE div 2;
    Result := Rect(X - HalfPrimaryHandle, Y - HalfPrimaryHandle,
      X - HalfPrimaryHandle + PRIMARY_ROTATION_HANDLE_SIZE,
      Y - HalfPrimaryHandle + PRIMARY_ROTATION_HANDLE_SIZE);
  end;

begin
  FillChar(Result, SizeOf(Result), 0);
  Result.DrawFrame := False;
  HalfHandle := SELECTION_HANDLE_SIZE div 2;
  Distance := Hypot(EndPoint.X - StartPoint.X, EndPoint.Y - StartPoint.Y);
  if Distance > 0 then
  begin
    UnitX := (EndPoint.X - StartPoint.X) / Distance;
    UnitY := (EndPoint.Y - StartPoint.Y) / Distance;
  end
  else
  begin
    UnitX := 1;
    UnitY := 0;
  end;
  StartHandlePoint := Point(
    Round(StartPoint.X - UnitX * LineSelectionHandleDistance),
    Round(StartPoint.Y - UnitY * LineSelectionHandleDistance));
  EndHandlePoint := Point(
    Round(EndPoint.X + UnitX * LineSelectionHandleDistance),
    Round(EndPoint.Y + UnitY * LineSelectionHandleDistance));
  Result.FrameRect := Rect(Min(StartPoint.X, EndPoint.X),
    Min(StartPoint.Y, EndPoint.Y), Max(StartPoint.X, EndPoint.X),
    Max(StartPoint.Y, EndPoint.Y));
  Result.FramePoints[0] := StartPoint;
  Result.FramePoints[1] := EndPoint;
  Result.FramePoints[2] := EndPoint;
  Result.FramePoints[3] := StartPoint;
  Result.FramePoints[4] := StartPoint;
  Result.Handles[vshTopLeft] := HandleRect(StartHandlePoint);
  Result.Handles[vshBottomRight] := HandleRect(EndHandlePoint);
  Result.PrimaryRotationHandle := PrimaryRotationHandleRect(
    (Result.FrameRect.Left + Result.FrameRect.Right) div 2,
    Result.FrameRect.Top - PRIMARY_ROTATION_HANDLE_OFFSET);
  Result.RotationStem[0] := Point(
    (Result.FrameRect.Left + Result.FrameRect.Right) div 2,
    Result.FrameRect.Top - HalfHandle);
  Result.RotationStem[1] := Point(
    (Result.FrameRect.Left + Result.FrameRect.Right) div 2,
    Result.PrimaryRotationHandle.Bottom);
end;

function BuildPathSelectionGeometry(const LayerRect: TRect;
  FrameOffset: Integer): TVectArtSelectionGeometry;
begin
  Result := BuildSelectionGeometry(LayerRect, FrameOffset);
  FillChar(Result.Handles, SizeOf(Result.Handles), 0);
end;

function HitTestSelectionHandle(const Point: TPoint;
  const Geometry: TVectArtSelectionGeometry): TVectArtSelectionHandle;
var
  DX, DY, LengthSquared, Projection, TestX, TestY: Single;
  Handle: TVectArtSelectionHandle;
  HitRect: TRect;
  I: Integer;
begin
  for Handle := vshTopLeft to vshLeft do
  begin
    HitRect := Geometry.Handles[Handle];
    if HitRect.IsEmpty then
      Continue;
    InflateRect(HitRect, HANDLE_HIT_PADDING, HANDLE_HIT_PADDING);
    if PtInRect(HitRect, Point) then
      Exit(Handle);
  end;
  if Geometry.DrawFrame then
  begin
    // Path系は角ハンドルを描かないが、枠の角では二軸変形を優先する。
    for I := 0 to 3 do
      if Hypot(Point.X-Geometry.FramePoints[I].X,
        Point.Y-Geometry.FramePoints[I].Y) <= FRAME_HIT_DISTANCE then
        case I of
          0: Exit(vshTopLeft);
          1: Exit(vshTopRight);
          2: Exit(vshBottomRight);
          3: Exit(vshBottomLeft);
        end;
    for I := 0 to 3 do
    begin
      DX := Geometry.FramePoints[I+1].X - Geometry.FramePoints[I].X;
      DY := Geometry.FramePoints[I+1].Y - Geometry.FramePoints[I].Y;
      LengthSquared := DX*DX + DY*DY;
      if LengthSquared <= 0 then
        Continue;
      Projection := EnsureRange(((Point.X-Geometry.FramePoints[I].X)*DX +
        (Point.Y-Geometry.FramePoints[I].Y)*DY)/LengthSquared,0.0,1.0);
      TestX := Geometry.FramePoints[I].X + Projection*DX;
      TestY := Geometry.FramePoints[I].Y + Projection*DY;
      if Hypot(Point.X-TestX,Point.Y-TestY) <= FRAME_HIT_DISTANCE then
        case I of
          0: Exit(vshTop);
          1: Exit(vshRight);
          2: Exit(vshBottom);
          3: Exit(vshLeft);
        end;
    end;
  end;
  Result := vshNone;
end;

function HitTestRotationHandle(const Point: TPoint;
  const Geometry: TVectArtSelectionGeometry): Boolean;
begin
  Result := PtInRect(Geometry.PrimaryRotationHandle, Point);
end;

function RotationHandleCursor: TCursor;
begin
  if RotationCursorHandle = 0 then
  begin
    RotationCursorHandle := CreateRotationCursor;
    if RotationCursorHandle <> 0 then
      Screen.Cursors[CR_VECTART_ROTATE] := RotationCursorHandle;
  end;
  if RotationCursorHandle <> 0 then
    Result := CR_VECTART_ROTATE
  else
    Result := crCross;
end;

function SelectionHandleCursor(Handle: TVectArtSelectionHandle): TCursor;
begin
  case Handle of
    vshTopLeft, vshBottomRight:
      Result := crSizeNWSE;
    vshTopRight, vshBottomLeft:
      Result := crSizeNESW;
    vshTop, vshBottom:
      Result := crSizeNS;
    vshLeft, vshRight:
      Result := crSizeWE;
  else
    Result := crDefault;
  end;
end;

end.
