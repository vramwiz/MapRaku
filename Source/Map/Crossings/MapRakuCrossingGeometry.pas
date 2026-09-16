// 交差判定と交差描画で同じ変換済み経路・弧長を使用する。
unit MapRakuCrossingGeometry;
interface
uses System.Types, MapRakuDocument;
type
  TMapCrossingSample = record
    P: TPointF;
    Segment: Integer;
    PathParameter: Single;
  end;

// 元区間番号と区間内パラメータを保持し、ベジェを直線列へ近似する。
function SampleMapCrossingPath(Path: TVectArtPathLayer): TArray<TMapCrossingSample>;
// 中心弧長と半長で切り出す。経路の外側は端点へ制限する。
function MapCrossingPathSection(Path: TVectArtPathLayer;
  Distance, HalfLength: Single): TArray<TPointF>;
// 変形後の線幅。非等方拡大では大きい軸を採用して切り抜き不足を防ぐ。
function MapCrossingPathWidth(Path: TVectArtPathLayer): Single;
implementation
uses System.Math;
function Cubic(const A, B, C, D: TPointF; T: Single): TPointF;
var U: Single;
begin
  U := 1-T;
  Result := TPointF.Create(U*U*U*A.X + 3*U*U*T*B.X +
    3*U*T*T*C.X + T*T*T*D.X, U*U*U*A.Y + 3*U*U*T*B.Y +
    3*U*T*T*C.Y + T*T*T*D.Y);
end;

function SampleMapCrossingPath(Path: TVectArtPathLayer): TArray<TMapCrossingSample>;
const STEPS = 64;
var I, J, N, Next, Count: Integer; V: TArray<TMapRakuVertex>; A, B, C, D: TPointF;
  S: TMapCrossingSample;
begin
  V := Path.Vertices;
  Result := nil;
  if Length(V)<2 then Exit;
  Count:=Length(V)-1;
  if Path.Closed then Inc(Count);
  for I:=0 to Count-1 do
  begin
    Next:=(I+1) mod Length(V);
    A:=V[I].Position; D:=V[Next].Position;
    B:=TPointF.Create(A.X+V[I].OutgoingControl.X,A.Y+V[I].OutgoingControl.Y);
    C:=TPointF.Create(D.X+V[Next].IncomingControl.X,D.Y+V[Next].IncomingControl.Y);
    N:=1;
    if V[I].OutgoingSegment=slskCubicBezier then N:=STEPS;
    for J:=0 to N-1 do
    begin
      S.Segment:=I; S.PathParameter:=J/N;
      if N=1 then S.P:=A else S.P:=Cubic(A,B,C,D,J/N);
      S.P:=Path.Transform.Map(S.P);
      Result:=Result+[S];
    end;
  end;
  S.Segment:=Count-1; S.PathParameter:=1;
  S.P:=Path.Transform.Map(V[Count mod Length(V)].Position); Result:=Result+[S];
end;

function MapCrossingPathWidth(Path: TVectArtPathLayer): Single;
var O, X, Y: TPointF;
begin
  O:=Path.Transform.Map(PointF(0,0));
  X:=Path.Transform.Map(PointF(1,0));
  Y:=Path.Transform.Map(PointF(0,1));
  Result:=Max(2,Path.StrokeWidth)*Max(Hypot(X.X-O.X,X.Y-O.Y),
    Hypot(Y.X-O.X,Y.Y-O.Y));
end;

function MapCrossingPathSection(Path: TVectArtPathLayer;
  Distance, HalfLength: Single): TArray<TPointF>;
var S: TArray<TMapCrossingSample>; I: Integer; D,L,A,B: Single;
  function Interpolate(T: Single): TPointF;
  begin
    Result:=PointF(S[I].P.X+(S[I+1].P.X-S[I].P.X)*T,
      S[I].P.Y+(S[I+1].P.Y-S[I].P.Y)*T);
  end;
begin
  Result:=nil; S:=SampleMapCrossingPath(Path); D:=0;
  for I:=0 to High(S)-1 do
  begin
    L:=Hypot(S[I+1].P.X-S[I].P.X,S[I+1].P.Y-S[I].P.Y);
    if L>1E-6 then
    begin
      A:=Max(0,Distance-HalfLength-D);
      B:=Min(L,Distance+HalfLength-D);
      if B>A then
      begin
        if Length(Result)=0 then Result:=Result+[Interpolate(A/L)];
        Result:=Result+[Interpolate(B/L)];
      end;
    end;
    D:=D+L;
  end;
end;

end.
