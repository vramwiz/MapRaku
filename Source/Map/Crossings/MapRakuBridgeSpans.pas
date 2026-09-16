// 上側経路上の橋区間を統合する。描画・文書変更には依存しない。
unit MapRakuBridgeSpans;
interface
const
  // 両側の端の開き(3)＋線の半幅(1)と、衝突を避ける余白。
  MAP_BRIDGE_JOIN_GAP = 10.0;
type
  TMapRakuBridgeSpan = record
    UpperObjectId: string;
    StartDistance, EndDistance: Single;
    Underpass: Boolean;
  end;
// 距離は変換後の経路の弧長。対象IDと側線形式が等しい近接区間だけを統合する。
procedure AddMapBridgeSpan(var Spans: TArray<TMapRakuBridgeSpan>;
  const Span: TMapRakuBridgeSpan);
implementation
uses System.Math;
procedure AddMapBridgeSpan(var Spans: TArray<TMapRakuBridgeSpan>;
  const Span: TMapRakuBridgeSpan);
var Joined: TMapRakuBridgeSpan; I,J: Integer;
begin
  Joined:=Span; I:=0;
  while I<Length(Spans) do
    if (Spans[I].UpperObjectId=Joined.UpperObjectId) and
      (Spans[I].Underpass=Joined.Underpass) and
      (Spans[I].StartDistance<=Joined.EndDistance+MAP_BRIDGE_JOIN_GAP) and
      (Joined.StartDistance<=Spans[I].EndDistance+MAP_BRIDGE_JOIN_GAP) then begin
      Joined.StartDistance:=Min(Joined.StartDistance,Spans[I].StartDistance);
      Joined.EndDistance:=Max(Joined.EndDistance,Spans[I].EndDistance);
      for J:=I to High(Spans)-1 do Spans[J]:=Spans[J+1];
      SetLength(Spans,Length(Spans)-1);
      // 区間の拡張で別の区間ともつながる場合を含め、順序によらず統合する。
      I:=0;
    end else Inc(I);
  Spans:=Spans+[Joined];
end;

end.
