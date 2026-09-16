// 地図経路同士の交差を固定座標にせず、現在の形状から都度導出する。
unit MapRakuCrossings;

interface

uses System.Types, MapRakuDocument;

type
  TMapRakuCrossing = record
    ObjectAId: string;
    ObjectBId: string;
    Position: TPointF;
    Kind: TMapRakuCrossingKind;
    UpperObjectId: string;
    SegmentA: Integer;
    SegmentB: Integer;
    ParameterA: Single;
    ParameterB: Single;
    TangentA: TPointF;
    TangentB: TPointF;
  end;

  TMapRakuCrossingGroup = record
    SubjectId: string;
    TargetIds: TArray<string>;
    Kind: TMapRakuCrossingKind;
    StartPosition: TPointF;
    EndPosition: TPointF;
  end;

function CalculateMapRakuCrossings(Document: TVectArtDocument):
  TArray<TMapRakuCrossing>;
function GroupMapRakuRailCrossings(
  const Crossings: TArray<TMapRakuCrossing>): TArray<TMapRakuCrossingGroup>;

implementation

uses System.Generics.Collections, System.Math, System.SysUtils;

type
  TPathSample = record
    P: TPointF;
    Segment: Integer;
    PathParameter: Single;
  end;

function IsRail(const S: string): Boolean;
begin
  Result := SameText(S, 'jr') or SameText(S, 'rail');
end;

function IsCrossingPath(const S:string):Boolean;
begin
  Result:=SameText(S,'road') or IsRail(S) or SameText(S,'river');
end;

function Cubic(const A, B, C, D: TPointF; T: Single): TPointF;
var U: Single;
begin
  U := 1-T;
  Result := TPointF.Create(U*U*U*A.X + 3*U*U*T*B.X +
    3*U*T*T*C.X + T*T*T*D.X, U*U*U*A.Y + 3*U*U*T*B.Y +
    3*U*T*T*C.Y + T*T*T*D.Y);
end;

function Samples(Path: TVectArtPathLayer): TArray<TPathSample>;
const STEPS = 16;
var I, J, N: Integer; V: TArray<TMapRakuVertex>; A, B, C, D: TPointF;
  S: TPathSample;
begin
  V := Path.Vertices;
  Result := nil;
  if Length(V)<2 then Exit;
  for I:=0 to High(V)-1 do
  begin
    A:=V[I].Position; D:=V[I+1].Position;
    B:=TPointF.Create(A.X+V[I].OutgoingControl.X,A.Y+V[I].OutgoingControl.Y);
    C:=TPointF.Create(D.X+V[I+1].IncomingControl.X,D.Y+V[I+1].IncomingControl.Y);
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
  S.Segment:=High(V)-1; S.PathParameter:=1;
  S.P:=Path.Transform.Map(V[High(V)].Position); Result:=Result+[S];
end;

function SegmentIntersection(const A, B, C, D:TPointF; out P:TPointF;
  out TA,TB:Single):Boolean;
var RX,RY,SX,SY,QX,QY,Den:Double;
begin
  RX:=B.X-A.X; RY:=B.Y-A.Y; SX:=D.X-C.X; SY:=D.Y-C.Y;
  QX:=C.X-A.X; QY:=C.Y-A.Y; Den:=RX*SY-RY*SX;
  if Abs(Den)<1E-7 then Exit(False);
  TA:=(QX*SY-QY*SX)/Den; TB:=(QX*RY-QY*RX)/Den;
  Result:=(TA>=0) and (TA<=1) and (TB>=0) and (TB<=1);
  if Result then P:=TPointF.Create(A.X+TA*RX,A.Y+TA*RY);
end;

function LevelAt(Document:TVectArtDocument; Index:Integer):Integer;
var I:Integer;
begin
  Result:=0;
  for I:=1 to Index-1 do
    if Document[I] is TMapRakuLevelBoundaryLayer then Inc(Result);
end;

function CrossingKind(A,B:TVectArtPathLayer; SameLevel:Boolean):TMapRakuCrossingKind;
begin
  if SameLevel then
  begin
    if (SameText(A.MapElement,'road') and IsRail(B.MapElement)) or
       (SameText(B.MapElement,'road') and IsRail(A.MapElement)) then
      Exit(mckRailroadCrossing);
    if (SameText(A.MapElement,'road') and SameText(B.MapElement,'river')) or
       (SameText(B.MapElement,'road') and SameText(A.MapElement,'river')) then
      Exit(mckBridge);
    Exit(mckNormal);
  end;
  if IsRail(A.MapElement) or IsRail(B.MapElement) then Exit(mckRailOverpass);
  Result:=mckOverpass;
end;

function CalculateMapRakuCrossings(Document:TVectArtDocument):TArray<TMapRakuCrossing>;
var I,J,K,L:Integer; A,B:TVectArtPathLayer; SA,SB:TArray<TPathSample>;
  P:TPointF; TA,TB:Single; C:TMapRakuCrossing; SameLevel:Boolean;
  Existing:TMapRakuCrossing; Duplicate:Boolean; TextSwap:string;
  IntSwap:Integer; FloatSwap:Single;
  PointSwap:TPointF; Len:Single;
  OverrideRelation:TMapRakuCrossingRelation;
begin
  Result:=nil; if Document=nil then Exit;
  for I:=1 to Document.LayerCount-1 do
    if (Document[I] is TVectArtPathLayer) and
      IsCrossingPath(TVectArtPathLayer(Document[I]).MapElement) then
      for J:=I+1 to Document.LayerCount-1 do
        if (Document[J] is TVectArtPathLayer) and
          IsCrossingPath(TVectArtPathLayer(Document[J]).MapElement) then
        begin
          A:=TVectArtPathLayer(Document[I]); B:=TVectArtPathLayer(Document[J]);
          SA:=Samples(A); SB:=Samples(B); SameLevel:=LevelAt(Document,I)=LevelAt(Document,J);
          for K:=0 to High(SA)-1 do for L:=0 to High(SB)-1 do
            if SegmentIntersection(SA[K].P,SA[K+1].P,SB[L].P,SB[L+1].P,P,TA,TB) then
            begin
              C:=Default(TMapRakuCrossing); C.ObjectAId:=A.PersistentId;
              C.ObjectBId:=B.PersistentId; C.Position:=P;
              C.Kind:=CrossingKind(A,B,SameLevel); C.UpperObjectId:=B.PersistentId;
              OverrideRelation:=Document.FindCrossingRelation(
                A.PersistentId,B.PersistentId);
              if OverrideRelation<>nil then
              begin
                C.Kind:=OverrideRelation.Kind;
                C.UpperObjectId:=OverrideRelation.UpperObjectId;
              end;
              C.SegmentA:=SA[K].Segment; C.SegmentB:=SB[L].Segment;
              C.ParameterA:=SA[K].PathParameter+(SA[K+1].PathParameter-SA[K].PathParameter)*TA;
              C.ParameterB:=SB[L].PathParameter+(SB[L+1].PathParameter-SB[L].PathParameter)*TB;
              C.TangentA:=TPointF.Create(SA[K+1].P.X-SA[K].P.X,
                SA[K+1].P.Y-SA[K].P.Y);
              Len:=Hypot(C.TangentA.X,C.TangentA.Y);
              if Len>0 then C.TangentA:=TPointF.Create(C.TangentA.X/Len,C.TangentA.Y/Len);
              C.TangentB:=TPointF.Create(SB[L+1].P.X-SB[L].P.X,
                SB[L+1].P.Y-SB[L].P.Y);
              Len:=Hypot(C.TangentB.X,C.TangentB.Y);
              if Len>0 then C.TangentB:=TPointF.Create(C.TangentB.X/Len,C.TangentB.Y/Len);
              // グループ化では道路を主体として扱えるよう参照順を正規化する。
              if SameText(B.MapElement,'road') and not SameText(A.MapElement,'road') then
              begin
                TextSwap:=C.ObjectAId; C.ObjectAId:=C.ObjectBId; C.ObjectBId:=TextSwap;
                IntSwap:=C.SegmentA; C.SegmentA:=C.SegmentB; C.SegmentB:=IntSwap;
                FloatSwap:=C.ParameterA; C.ParameterA:=C.ParameterB; C.ParameterB:=FloatSwap;
                PointSwap:=C.TangentA; C.TangentA:=C.TangentB; C.TangentB:=PointSwap;
              end;
              Duplicate:=False;
              for Existing in Result do
                if (Existing.ObjectAId=C.ObjectAId) and
                  (Existing.ObjectBId=C.ObjectBId) and
                  (Hypot(Existing.Position.X-C.Position.X,
                    Existing.Position.Y-C.Position.Y)<0.01) then
                begin Duplicate:=True; Break; end;
              if not Duplicate then Result:=Result+[C];
            end;
        end;
end;

function GroupMapRakuRailCrossings(const Crossings:TArray<TMapRakuCrossing>):TArray<TMapRakuCrossingGroup>;
var C:TMapRakuCrossing; G:TMapRakuCrossingGroup; I,J:Integer; Key:string;
  HasTarget:Boolean;
begin
  Result:=nil;
  for C in Crossings do
    if C.Kind in [mckRailroadCrossing,mckRailOverpass] then
    begin
      Key:=C.ObjectAId;
      I:=-1;
      if Length(Result)>0 then
        for I:=0 to High(Result) do if Result[I].SubjectId=Key then Break;
      if (I<0) or (I>High(Result)) or (Result[I].SubjectId<>Key) then
      begin
        G:=Default(TMapRakuCrossingGroup); G.SubjectId:=Key; G.Kind:=C.Kind;
        G.StartPosition:=C.Position; G.EndPosition:=C.Position;
        G.TargetIds:=[C.ObjectBId]; Result:=Result+[G];
      end else begin
        HasTarget:=False;
        for J:=0 to High(Result[I].TargetIds) do
          HasTarget:=HasTarget or (Result[I].TargetIds[J]=C.ObjectBId);
        if not HasTarget then
          Result[I].TargetIds:=Result[I].TargetIds+[C.ObjectBId];
        Result[I].EndPosition:=C.Position;
      end;
    end;
end;

end.
