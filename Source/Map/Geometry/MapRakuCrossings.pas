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
    DistanceA: Single;
    DistanceB: Single;
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
function MapCrossingPathSection(Path: TVectArtPathLayer;
  Distance, HalfLength: Single): TArray<TPointF>;
function MapCrossingPathWidth(Path: TVectArtPathLayer): Single;

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
const STEPS = 64;
var I, J, N, Next, Count: Integer; V: TArray<TMapRakuVertex>; A, B, C, D: TPointF;
  S: TPathSample;
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
var S: TArray<TPathSample>; I: Integer; D,L,A,B: Single;
  function Interpolate(T: Single): TPointF;
  begin
    Result:=PointF(S[I].P.X+(S[I+1].P.X-S[I].P.X)*T,
      S[I].P.Y+(S[I+1].P.Y-S[I].P.Y)*T);
  end;
begin
  Result:=nil; S:=Samples(Path); D:=0;
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
  PointSwap:TPointF; Len, DA, DB:Single;
  Paths: TList<TVectArtPathLayer>;
  Levels: TList<Integer>;
  Level: Integer;
  OverrideRelation:TMapRakuCrossingRelation;
  procedure Collect(Layer: TVectArtLayer);
  var N: Integer;
  begin
    if not Layer.Visible or (Layer.Opacity<=0) then Exit;
    if Layer is TMapRakuGroupLayer then
      for N:=0 to TMapRakuGroupLayer(Layer).ChildCount-1 do
        Collect(TMapRakuGroupLayer(Layer)[N])
    else if (Layer is TVectArtPathLayer) and
      IsCrossingPath(TVectArtPathLayer(Layer).MapElement) then
    begin Paths.Add(TVectArtPathLayer(Layer)); Levels.Add(Level); end;
  end;
begin
  Result:=nil; if Document=nil then Exit;
  Paths:=TList<TVectArtPathLayer>.Create;
  Levels:=TList<Integer>.Create;
  try
    Level:=0;
    for I:=1 to Document.LayerCount-1 do
      if Document[I] is TMapRakuLevelBoundaryLayer then Inc(Level)
      else Collect(Document[I]);
    for I:=0 to Paths.Count-1 do
      for J:=I+1 to Paths.Count-1 do
        begin
          A:=Paths[I]; B:=Paths[J];
          SA:=Samples(A); SB:=Samples(B); SameLevel:=Levels[I]=Levels[J];
          DA:=0;
          for K:=0 to High(SA)-1 do begin
          DB:=0;
          for L:=0 to High(SB)-1 do begin
            if SegmentIntersection(SA[K].P,SA[K+1].P,SB[L].P,SB[L+1].P,P,TA,TB) then
            begin
              C:=Default(TMapRakuCrossing); C.ObjectAId:=A.PersistentId;
              C.ObjectBId:=B.PersistentId; C.Position:=P;
              C.Kind:=CrossingKind(A,B,SameLevel); C.UpperObjectId:=B.PersistentId;
              // 同層の踏切は線路、川との橋は道路を上に描く。
              if (C.Kind=mckRailroadCrossing) and IsRail(A.MapElement) then
                C.UpperObjectId:=A.PersistentId;
              if (C.Kind=mckBridge) and SameText(A.MapElement,'road') then
                C.UpperObjectId:=A.PersistentId;
              OverrideRelation:=Document.FindCrossingRelation(
                A.PersistentId,B.PersistentId);
              if OverrideRelation<>nil then
              begin
                C.Kind:=OverrideRelation.Kind;
                C.UpperObjectId:=OverrideRelation.UpperObjectId;
              end;
              if C.Kind=mckRailroadCrossing then begin
                if IsRail(A.MapElement) then C.UpperObjectId:=A.PersistentId
                else if IsRail(B.MapElement) then C.UpperObjectId:=B.PersistentId;
              end;
              C.SegmentA:=SA[K].Segment; C.SegmentB:=SB[L].Segment;
              C.DistanceA:=DA+TA*Hypot(SA[K+1].P.X-SA[K].P.X,SA[K+1].P.Y-SA[K].P.Y);
              C.DistanceB:=DB+TB*Hypot(SB[L+1].P.X-SB[L].P.X,SB[L+1].P.Y-SB[L].P.Y);
              C.ParameterA:=SA[K].PathParameter+(SA[K+1].PathParameter-SA[K].PathParameter)*TA;
              C.ParameterB:=SB[L].PathParameter+(SB[L+1].PathParameter-SB[L].PathParameter)*TB;
              if SA[K+1].Segment<>SA[K].Segment then
                C.ParameterA:=SA[K].PathParameter+(1-SA[K].PathParameter)*TA;
              if SB[L+1].Segment<>SB[L].Segment then
                C.ParameterB:=SB[L].PathParameter+(1-SB[L].PathParameter)*TB;
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
                FloatSwap:=C.DistanceA; C.DistanceA:=C.DistanceB; C.DistanceB:=FloatSwap;
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
            DB:=DB+Hypot(SB[L+1].P.X-SB[L].P.X,SB[L+1].P.Y-SB[L].P.Y);
          end;
          DA:=DA+Hypot(SA[K+1].P.X-SA[K].P.X,SA[K+1].P.Y-SA[K].P.Y);
          end;
        end;
  finally Levels.Free; Paths.Free; end;
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
