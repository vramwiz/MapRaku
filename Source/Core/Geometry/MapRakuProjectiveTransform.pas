// 四辺形間の射影変換を描画・入力・保存で共有する。
unit MapRakuProjectiveTransform;

interface

uses System.Types, System.Math.Vectors;

type
  TMapRakuQuad = array[0..3] of TPointF;
  TMapRakuTransform = record
    Values: array[0..8] of Double; // 行優先。列ベクトルへ左から適用する3×3行列。
    // 変形を加えない行列を返す。
    class function Identity: TMapRakuTransform; static;
    // 元の座標を表示座標へ変換する。
    function Map(const P: TPointF): TPointF;
    // 有効な逆変換を返す。退化した行列ではFalse。
    function Inverse(out Value: TMapRakuTransform): Boolean;
    // この変換の後にNextを適用する行列を返す。
    function ThenApply(const Next: TMapRakuTransform): TMapRakuTransform;
    // 数値誤差を除いて恒等変換かを返す。
    function IsIdentity: Boolean;
    // 復元用レコードへ所有権を共有しない9要素配列を渡す。
    function ToArray: TArray<Double>;
    // 空配列を恒等変換として復元する。
    class function FromArray(const Value: TArray<Double>): TMapRakuTransform; static;
    // 描画APIへ渡す行ベクトル形式の行列を返す。
    function Matrix: TMatrix;
  end;

// 左上、右上、右下、左下の順で矩形の頂点を返す。
function MapRakuRectQuad(const Bounds: TRectF): TMapRakuQuad;
// 自己交差と退化のない凸四辺形の間で射影変換を求める。
function TryMapRakuQuadTransform(const Source, Target: TMapRakuQuad;
  out Transform: TMapRakuTransform): Boolean;
// 四辺形を囲む軸平行範囲を返す。
function MapRakuQuadBounds(const Quad: TMapRakuQuad): TRectF;

implementation

uses System.Math;

class function TMapRakuTransform.Identity: TMapRakuTransform;
begin
  Result := Default(TMapRakuTransform);
  Result.Values[0] := 1;
  Result.Values[4] := 1;
  Result.Values[8] := 1;
end;

function TMapRakuTransform.Matrix: TMatrix;
begin
  Result.m11 := Values[0]; Result.m21 := Values[1]; Result.m31 := Values[2];
  Result.m12 := Values[3]; Result.m22 := Values[4]; Result.m32 := Values[5];
  Result.m13 := Values[6]; Result.m23 := Values[7]; Result.m33 := Values[8];
end;

function TMapRakuTransform.ToArray: TArray<Double>;
var I: Integer;
begin
  SetLength(Result,9);
  for I := 0 to 8 do Result[I] := Values[I];
end;

class function TMapRakuTransform.FromArray(const Value: TArray<Double>): TMapRakuTransform;
var I: Integer;
begin
  Result := Identity;
  if Length(Value) = 9 then
    for I := 0 to 8 do Result.Values[I] := Value[I];
end;

function TMapRakuTransform.IsIdentity: Boolean;
var I: Integer; Expected: Double;
begin
  for I := 0 to 8 do
  begin
    Expected := 0;
    if I in [0, 4, 8] then Expected := 1;
    if Abs(Values[I] - Expected) > 1E-9 then Exit(False);
  end;
  Result := True;
end;

function TMapRakuTransform.Map(const P: TPointF): TPointF;
var W: Double;
begin
  W := Values[6] * P.X + Values[7] * P.Y + Values[8];
  if Abs(W) < 1E-12 then Exit(P);
  Result := TPointF.Create((Values[0] * P.X + Values[1] * P.Y + Values[2]) / W,
    (Values[3] * P.X + Values[4] * P.Y + Values[5]) / W);
end;

function TMapRakuTransform.Inverse(out Value: TMapRakuTransform): Boolean;
var D: Double; I: Integer;
begin
  Value.Values[0] := Values[4]*Values[8]-Values[5]*Values[7];
  Value.Values[1] := Values[2]*Values[7]-Values[1]*Values[8];
  Value.Values[2] := Values[1]*Values[5]-Values[2]*Values[4];
  Value.Values[3] := Values[5]*Values[6]-Values[3]*Values[8];
  Value.Values[4] := Values[0]*Values[8]-Values[2]*Values[6];
  Value.Values[5] := Values[2]*Values[3]-Values[0]*Values[5];
  Value.Values[6] := Values[3]*Values[7]-Values[4]*Values[6];
  Value.Values[7] := Values[1]*Values[6]-Values[0]*Values[7];
  Value.Values[8] := Values[0]*Values[4]-Values[1]*Values[3];
  D := Values[0]*Value.Values[0]+Values[1]*Value.Values[3]+Values[2]*Value.Values[6];
  Result := Abs(D) > 1E-12;
  if Result then for I := 0 to 8 do Value.Values[I] := Value.Values[I] / D;
end;

function TMapRakuTransform.ThenApply(const Next: TMapRakuTransform): TMapRakuTransform;
var R, C, K: Integer;
begin
  Result := Default(TMapRakuTransform);
  for R := 0 to 2 do for C := 0 to 2 do for K := 0 to 2 do
    Result.Values[R*3+C] := Result.Values[R*3+C] + Next.Values[R*3+K]*Values[K*3+C];
end;

function MapRakuRectQuad(const Bounds: TRectF): TMapRakuQuad;
begin
  Result[0] := Bounds.TopLeft;
  Result[1] := TPointF.Create(Bounds.Right, Bounds.Top);
  Result[2] := Bounds.BottomRight;
  Result[3] := TPointF.Create(Bounds.Left, Bounds.Bottom);
end;

function MapRakuQuadBounds(const Quad: TMapRakuQuad): TRectF;
var I: Integer;
begin
  Result := TRectF.Create(Quad[0], Quad[0]);
  for I := 1 to 3 do
  begin
    Result.Left := Min(Result.Left, Quad[I].X);
    Result.Right := Max(Result.Right, Quad[I].X);
    Result.Top := Min(Result.Top, Quad[I].Y);
    Result.Bottom := Max(Result.Bottom, Quad[I].Y);
  end;
end;

function ConvexQuad(const Q: TMapRakuQuad): Boolean;
var I: Integer; Cross, Previous: Double; A, B: TPointF;
begin
  Previous := 0;
  for I := 0 to 3 do
  begin
    A := Q[(I+1) mod 4] - Q[I];
    B := Q[(I+2) mod 4] - Q[(I+1) mod 4];
    Cross := A.X*B.Y-A.Y*B.X;
    if IsNan(Cross) or IsInfinite(Cross) or (Abs(Cross) < 0.01) or
      ((I > 0) and (Cross*Previous <= 0)) then Exit(False);
    Previous := Cross;
  end;
  Result := True;
end;

function TryMapRakuQuadTransform(const Source, Target: TMapRakuQuad;
  out Transform: TMapRakuTransform): Boolean;
var A: array[0..7,0..8] of Double; I, J, K, Pivot: Integer; V, X, Y, U, W: Double;
begin
  Transform := TMapRakuTransform.Identity;
  if not ConvexQuad(Source) or not ConvexQuad(Target) then Exit(False);
  FillChar(A, SizeOf(A), 0);
  for I := 0 to 3 do
  begin
    X := Source[I].X; Y := Source[I].Y; U := Target[I].X; W := Target[I].Y;
    A[I*2,0] := X; A[I*2,1] := Y; A[I*2,2] := 1;
    A[I*2,6] := -U*X; A[I*2,7] := -U*Y; A[I*2,8] := U;
    A[I*2+1,3] := X; A[I*2+1,4] := Y; A[I*2+1,5] := 1;
    A[I*2+1,6] := -W*X; A[I*2+1,7] := -W*Y; A[I*2+1,8] := W;
  end;
  for I := 0 to 7 do
  begin
    Pivot := I;
    for J := I+1 to 7 do if Abs(A[J,I]) > Abs(A[Pivot,I]) then Pivot := J;
    if Abs(A[Pivot,I]) < 1E-12 then Exit(False);
    for K := I to 8 do begin V := A[I,K]; A[I,K] := A[Pivot,K]; A[Pivot,K] := V end;
    V := A[I,I];
    for K := I to 8 do A[I,K] := A[I,K] / V;
    for J := 0 to 7 do if J <> I then
    begin
      V := A[J,I];
      for K := I to 8 do A[J,K] := A[J,K] - V*A[I,K];
    end;
  end;
  for I := 0 to 7 do Transform.Values[I] := A[I,8];
  Result := True;
end;

end.
