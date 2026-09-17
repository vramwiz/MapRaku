// 独立した候補DocumentにID指定の操作を順番に適用し、全件成功時だけ返す。
unit MapRakuAutomationBatch;
interface
uses System.JSON, MapRakuDocument;
function BuildAutomationBatch(Document: TVectArtDocument; Root: TJSONObject): TJSONObject;
implementation
uses System.SysUtils, System.Types, System.Generics.Collections, MapRakuDocumentJson, MapRakuLayerGeometry,
  MapRakuAutomationFactory, MapRakuAutomationValues, MapRakuAutomationValidation,
  MapRakuAutomationSession;
type
  TLocation = record
    Layer: TVectArtLayer;
    Parent: TMapRakuGroupLayer;
    Index: Integer;
    Locked: Boolean;
  end;
function Search(L: TVectArtLayer; Parent: TMapRakuGroupLayer; Index: Integer;
  Locked: Boolean; const Id: string; out Found: TLocation): Boolean;
var I: Integer; G: TMapRakuGroupLayer;
begin
  Locked := Locked or L.Locked;
  Result := L.PersistentId = Id;
  if Result then begin
    Found.Layer := L; Found.Parent := Parent; Found.Index := Index; Found.Locked := Locked;
    Exit;
  end;
  if L is TMapRakuGroupLayer then begin
    G := TMapRakuGroupLayer(L);
    for I := 0 to G.ChildCount-1 do
      if Search(G[I],G,I,Locked,Id,Found) then Exit(True);
  end;
end;
function Locate(D: TVectArtDocument; const Id: string): TLocation;
var I: Integer;
begin
  Result := Default(TLocation);
  for I := 1 to D.LayerCount-1 do
    if Search(D[I],nil,I,False,Id,Result) then Exit;
  raise EArgumentException.Create('Unknown layer id: '+Id);
end;
procedure RemoveRelations(D: TVectArtDocument; L: TVectArtLayer);
var I: Integer; R: TMapRakuCrossingRelation;
begin
  if L is TMapRakuGroupLayer then
    for I := 0 to TMapRakuGroupLayer(L).ChildCount-1 do RemoveRelations(D,TMapRakuGroupLayer(L)[I]);
  for I := D.CrossingRelationCount-1 downto 0 do begin
    R := D.CrossingRelations[I];
    if (R.ObjectAId = L.PersistentId) or (R.ObjectBId = L.PersistentId) then
      D.RemoveCrossingRelation(R.ObjectAId,R.ObjectBId);
  end;
end;
procedure PatchLayer(D: TVectArtDocument; L: TVectArtLayer; S: TJSONObject);
var P: TVectArtPathLayer; Pair: TJSONPair;
begin
  // 未対応属性を黙って無視するとAIが修正成功と誤認するため、明示的に拒否する。
  for Pair in S do
    Require((Pair.JsonString.Value = 'name') or (Pair.JsonString.Value = 'opacity') or
      (Pair.JsonString.Value = 'visible') or (Pair.JsonString.Value = 'dx') or
      (Pair.JsonString.Value = 'dy') or (Pair.JsonString.Value = 'vertices') or
      (Pair.JsonString.Value = 'width') or (Pair.JsonString.Value = 'color') or
      (Pair.JsonString.Value = 'text'), 'Unsupported update field: '+Pair.JsonString.Value);
  if S.GetValue('name') <> nil then L.Name := Str(S,'name');
  if S.GetValue('opacity') <> nil then L.Opacity := Num(S,'opacity',1,0,1);
  if S.GetValue('visible') <> nil then L.Visible := Bool(S,'visible');
  TranslateMapRakuLayer(L,Num(S,'dx',0),Num(S,'dy',0));
  if (S.GetValue('vertices') <> nil) or (S.GetValue('width') <> nil) then
    Require(L is TVectArtPathLayer, 'vertices/width update requires path.');
  if L is TVectArtPathLayer then begin
    P := TVectArtPathLayer(L);
    if S.GetValue('vertices') <> nil then P.Vertices := ReadAutomationVertices(S);
    if S.GetValue('width') <> nil then P.StrokeWidth := Num(S,'width',24,0.1,4096);
    if S.GetValue('color') <> nil then begin
      Require((P.MapElement <> 'jr') and (P.MapElement <> 'rail'), 'Rail colors belong to the canvas palette.');
      P.StrokeColor := Int(S,'color',0,0,$FFFFFF);
      P.MapColorOverride := True;
    end;
  end else if S.GetValue('color') <> nil then begin
    Require(L is TVectArtRectangleLayer, 'color update requires path or filled rectangle/text.');
    TVectArtRectangleLayer(L).FillColor := Int(S,'color',0,0,$FFFFFF);
  end;
  if S.GetValue('text') <> nil then begin
    Require(L is TMapRakuTextLayer, 'text update requires text layer.');
    TMapRakuTextLayer(L).Text := Str(S,'text');
  end;
end;
procedure Crossing(D: TVectArtDocument; Op: TJSONObject; Remove: Boolean);
var A,B: TLocation; Kind: Integer; Upper: string;
begin
  A := Locate(D,Str(Op,'a')); B := Locate(D,Str(Op,'b'));
  Require(not A.Locked and not B.Locked, 'Crossing target is locked.');
  Require(A.Layer <> B.Layer, 'Crossing needs two different paths.');
  if Remove then begin
    D.RemoveCrossingRelation(A.Layer.PersistentId,B.Layer.PersistentId);
    Exit;
  end;
  Kind := Int(Op,'kind',0,0,7); Upper := Str(Op,'upper');
  if Kind in [2,3,4,6,7] then Require(Upper <> '', 'Upper path is required for grade separation.');
  D.SetCrossingRelation(A.Layer.PersistentId,B.Layer.PersistentId,
    TMapRakuCrossingKind(Kind),Upper,Num(Op,'margin',12,0,4096));
end;
procedure ConnectPaths(D: TVectArtDocument; Op: TJSONObject);
var A,B: TLocation; P,Q: TVectArtPathLayer; I,J: Integer;
begin
  A := Locate(D,Str(Op,'id')); B := Locate(D,Str(Op,'target'));
  Require(not A.Locked and (A.Layer <> B.Layer), 'Source is locked or source equals target.');
  Require((A.Layer is TVectArtPathLayer) and (B.Layer is TVectArtPathLayer), 'Connection requires paths.');
  P := TVectArtPathLayer(A.Layer); Q := TVectArtPathLayer(B.Layer);
  I := Int(Op,'endpoint',0,0,Length(P.Vertices)-1);
  J := Int(Op,'target_endpoint',0,0,Length(Q.Vertices)-1);
  // 手動配置と同じ系列・接線規則を使い、ロックされた相手は位置の参照だけにする。
  Require(P.ConnectEndpoint(I,Q,J,not B.Locked,Bool(Op,'align',True)), 'Paths cannot connect at these endpoints.');
end;
procedure ConfigureCanvas(D: TVectArtDocument; S: TJSONObject);
var W,H: Integer;
begin
  W := Int(S,'width',D.CanvasLayer.Width,1,8192);
  H := Int(S,'height',D.CanvasLayer.Height,1,8192);
  if AutomationSession.Conditions <> nil then
    Require((Num(AutomationSession.Conditions,'canvas_width',0)=W) and
      (Num(AutomationSession.Conditions,'canvas_height',0)=H), 'Clear reference before changing canvas dimensions.');
  D.SetCanvasSize(W,H);
  D.CanvasLayer.BackgroundColor := Int(S,'background',D.CanvasLayer.BackgroundColor,0,$FFFFFF);
  D.CanvasLayer.Transparent := Bool(S,'transparent',D.CanvasLayer.Transparent);
  D.CanvasLayer.RoadPresetColor := Int(S,'road_color',D.CanvasLayer.RoadPresetColor,0,$FFFFFF);
  D.CanvasLayer.RiverPresetColor := Int(S,'river_color',D.CanvasLayer.RiverPresetColor,0,$FFFFFF);
  D.CanvasLayer.JrPrimaryColor := Int(S,'jr_primary',D.CanvasLayer.JrPrimaryColor,0,$FFFFFF);
  D.CanvasLayer.JrSecondaryColor := Int(S,'jr_secondary',D.CanvasLayer.JrSecondaryColor,0,$FFFFFF);
  D.CanvasLayer.RailPrimaryColor := Int(S,'rail_primary',D.CanvasLayer.RailPrimaryColor,0,$FFFFFF);
  D.CanvasLayer.RailSecondaryColor := Int(S,'rail_secondary',D.CanvasLayer.RailSecondaryColor,0,$FFFFFF);
end;
procedure ApplyOperation(D: TVectArtDocument; Op: TJSONObject);
var Action: string; L: TVectArtLayer; Found: TLocation;
begin
  Action := Str(Op,'op');
  if Action = 'add' then begin
    L := CreateAutomationLayer(Obj(Op.GetValue('spec')),D);
    D.InsertLayer(D.LayerCount,L);
  end else if Action = 'canvas' then ConfigureCanvas(D,Obj(Op.GetValue('spec')))
  else if Action = 'connect' then ConnectPaths(D,Op)
  else if (Action = 'crossing') or (Action = 'remove_crossing') then
    Crossing(D,Op,Action = 'remove_crossing')
  else begin
    Found := Locate(D,Str(Op,'id'));
    Require(not Found.Locked, 'Target or ancestor is locked.');
    if Action = 'update' then PatchLayer(D,Found.Layer,Obj(Op.GetValue('changes')))
    else if Action = 'delete' then begin
      RemoveRelations(D,Found.Layer);
      if Found.Parent <> nil then L := Found.Parent.ExtractChild(Found.Index)
      else L := D.ExtractLayer(Found.Index);
      L.Free;
    end else raise EArgumentException.Create('Unknown operation: '+Action);
  end;
end;
function BuildAutomationBatch(Document: TVectArtDocument; Root: TJSONObject): TJSONObject;
var Candidate: TVectArtDocument; Ops: TJSONArray; I: Integer; ErrorText: string; Report: TJSONObject;
begin
  Ops := Arr(Root,'operations');
  Require((Ops.Count > 0) and (Ops.Count <= 512), 'Batch requires 1..512 operations.');
  Candidate := TVectArtDocument.Create;
  try
    Require(TryDeserializeVectArtDocument(SerializeVectArtDocument(Document),Candidate,ErrorText),ErrorText);
    for I := 0 to Ops.Count-1 do begin
      try
        ApplyOperation(Candidate,Obj(Ops.Items[I]));
      except
        on E: EArgumentException do
          raise EArgumentException.CreateFmt('operations[%d]: %s',[I,E.Message]);
      end;
    end;
    Report := ValidateAutomationMap(Candidate);
    Report.Free;
    Result := TJSONObject(TJSONObject.ParseJSONValue(SerializeVectArtDocument(Candidate)));
  finally
    Candidate.Free;
  end;
end;
end.
