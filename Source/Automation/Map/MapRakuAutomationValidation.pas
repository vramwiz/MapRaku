// 保存形式だけでは表せないID参照・地図経路の不変条件を反映前に検査する。
unit MapRakuAutomationValidation;
interface
uses System.JSON, MapRakuDocument;
function ValidateAutomationMap(Document: TVectArtDocument): TJSONObject;
implementation
uses System.SysUtils, System.Math, System.Generics.Collections,
  MapRakuAutomationValues;
procedure CheckLayer(L: TVectArtLayer; Ids: TDictionary<string,TVectArtLayer>;
  Warnings: TJSONArray; Depth: Integer);
var I: Integer; P: TVectArtPathLayer; V: TMapRakuVertex;
  function Finite(N: Single): Boolean;
  begin Result := not IsNan(N) and not IsInfinite(N) and (Abs(N) <= 1000000); end;
begin
  Require(Depth <= 32, 'Group nesting exceeds 32.');
  Require((L.PersistentId <> '') and not Ids.ContainsKey(L.PersistentId), 'Missing or duplicate layer id.');
  Ids.Add(L.PersistentId,L);
  if L is TVectArtPathLayer then begin
    P := TVectArtPathLayer(L);
    Require(Length(P.Vertices) >= 2, 'Path requires at least two vertices: '+L.PersistentId);
    Require(Finite(P.StrokeWidth) and (P.StrokeWidth > 0), 'Invalid path width.');
    for V in P.Vertices do
      Require(Finite(V.Position.X) and Finite(V.Position.Y) and
        Finite(V.IncomingControl.X) and Finite(V.IncomingControl.Y) and
        Finite(V.OutgoingControl.X) and Finite(V.OutgoingControl.Y), 'Invalid vertex coordinate.');
    if (P.MapElement <> '') and P.Closed then
      Warnings.Add('Closed map path: '+L.PersistentId);
  end;
  if L is TMapRakuGroupLayer then
    for I := 0 to TMapRakuGroupLayer(L).ChildCount - 1 do
      CheckLayer(TMapRakuGroupLayer(L)[I],Ids,Warnings,Depth+1);
end;
procedure CheckCrossings(D: TVectArtDocument; Ids: TDictionary<string,TVectArtLayer>);
var I: Integer; R: TMapRakuCrossingRelation; A,B: TVectArtLayer;
begin
  for I := 0 to D.CrossingRelationCount-1 do begin
    R := D.CrossingRelations[I];
    Require((R.ObjectAId <> R.ObjectBId) and Ids.TryGetValue(R.ObjectAId,A) and
      Ids.TryGetValue(R.ObjectBId,B), 'Crossing refers to missing or identical paths.');
    Require((A is TVectArtPathLayer) and (B is TVectArtPathLayer), 'Crossing requires path layers.');
    Require((TVectArtPathLayer(A).ConnectionFamily <> '') and
      (TVectArtPathLayer(B).ConnectionFamily <> ''), 'Crossing requires map paths.');
    Require((R.UpperObjectId = '') or (R.UpperObjectId = R.ObjectAId) or
      (R.UpperObjectId = R.ObjectBId), 'Upper path must belong to the crossing.');
    Require(not IsNan(R.RangeMargin) and not IsInfinite(R.RangeMargin) and
      (R.RangeMargin >= 0) and (R.RangeMargin <= 4096), 'Invalid crossing margin.');
  end;
end;
function ValidateAutomationMap(Document: TVectArtDocument): TJSONObject;
var Ids: TDictionary<string,TVectArtLayer>; Warnings: TJSONArray; I: Integer;
begin
  Ids := TDictionary<string,TVectArtLayer>.Create;
  Result := TJSONObject.Create;
  try
    try
      Require((Document.CanvasLayer.Width > 0) and (Document.CanvasLayer.Width <= 8192) and
        (Document.CanvasLayer.Height > 0) and (Document.CanvasLayer.Height <= 8192),
        'Automation canvas must be 1..8192 per edge.');
      Warnings := TJSONArray.Create;
      Result.AddPair('warnings',Warnings);
      for I := 1 to Document.LayerCount-1 do CheckLayer(Document[I],Ids,Warnings,0);
      Require(Ids.Count <= 10000, 'Too many layers.');
      CheckCrossings(Document,Ids);
      Result.AddPair('valid',TJSONBool.Create(True));
      Result.AddPair('layer_count',TJSONNumber.Create(Ids.Count));
      Result.AddPair('accuracy_checked',TJSONBool.Create(False));
    except
      Result.Free;
      raise;
    end;
  finally
    Ids.Free;
  end;
end;
end.
