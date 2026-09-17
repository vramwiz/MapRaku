// AIの簡潔な部品指定を既存の地図モデル・記号生成器へ変換する。
unit MapRakuAutomationFactory;
interface
uses System.JSON, MapRakuDocument;
function CreateAutomationLayer(Spec: TJSONObject; Document: TVectArtDocument): TVectArtLayer;
function ReadAutomationVertices(Spec: TJSONObject): TArray<TMapRakuVertex>;
implementation
uses System.SysUtils, System.Types, System.Generics.Collections, MapRakuAutomationValues,
  System.Math, MapRakuSymbols, MapRakuLayerGeometry, MapRakuTextGeometry;
procedure CheckSpec(S: TJSONObject; const Kind: string);
var Fields: string; Pair: TJSONPair;
begin
  Fields := ',kind,id,name,opacity,';
  if (Kind='road') or (Kind='jr') or (Kind='rail') or (Kind='river') then
    Fields := Fields + 'vertices,width,color,line_cap,'
  else if Kind='symbol' then Fields := Fields + 'symbol,label,x,y,rotation,'
  else if Kind='building' then Fields := Fields + 'x,y,width,height,label,color,text_color,font_size,'
  else if Kind='text' then Fields := Fields + 'x,y,width,height,text,font,font_size,color,'
  else if (Kind='rectangle') or (Kind='ellipse') then Fields := Fields + 'x,y,width,height,color,';
  for Pair in S do
    Require(Pos(','+Pair.JsonString.Value+',',Fields) > 0,
      'Unsupported placement field: '+Pair.JsonString.Value);
  if S.GetValue('id') <> nil then
    Require((Str(S,'id') <> '') and (Length(Str(S,'id')) <= 128), 'id must be 1..128 characters.');
end;
function FittedText(const Name, Text, Font: string; FontSize: Single;
  const Box: TRectF; Color: Integer; Center: Boolean): TMapRakuTextLayer;
var Layout: TMapRakuTextLayout; W,H,Scale,X,Y: Single;
begin
  Layout := BuildMapRakuTextLayout(Text,Font,FontSize,0);
  // 文字枠全体への拡大を避け、指定サイズを上限に施設内へ収める。
  Scale := Min(1,Min(Box.Width/Max(1,Layout.Width),Box.Height/Max(1,Layout.Height)));
  W := Max(1,Layout.Width*Scale); H := Max(1,Layout.Height*Scale);
  X := Box.Left; Y := Box.Top;
  if Center then begin X := X+(Box.Width-W)/2; Y := Y+(Box.Height-H)/2; end;
  Result := TMapRakuTextLayer.Create(Name,TRectF.Create(X,Y,X+W,Y+H),Text,Font,FontSize,0,Color);
end;
function ReadAutomationVertices(Spec: TJSONObject): TArray<TMapRakuVertex>;
var A: TJSONArray; V: TJSONObject; I: Integer; Segment, Kind: string;
begin
  A := Arr(Spec,'vertices');
  Require((A.Count >= 2) and (A.Count <= 4096), 'A path requires 2..4096 vertices.');
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do begin
    V := Obj(A.Items[I]);
    Require((V.GetValue('x') <> nil) and (V.GetValue('y') <> nil), 'Vertex x/y required.');
    Result[I].Position := PointF(Num(V,'x',0), Num(V,'y',0));
    Result[I].IncomingControl := PointF(Num(V,'incomingX',0), Num(V,'incomingY',0));
    Result[I].OutgoingControl := PointF(Num(V,'outgoingX',0), Num(V,'outgoingY',0));
    Segment := Str(V,'outgoingSegment','line');
    Kind := Str(V,'kind','sharp');
    Require((Segment = 'line') or (Segment = 'cubicBezier'), 'Unknown segment kind.');
    Require((Kind = 'sharp') or (Kind = 'bezier'), 'Unknown vertex kind.');
    if Segment = 'cubicBezier' then Result[I].OutgoingSegment := slskCubicBezier;
    if Kind = 'bezier' then Result[I].Kind := slvkBezier;
  end;
end;
function MakePath(S: TJSONObject; D: TVectArtDocument; const Kind, Name: string): TVectArtPathLayer;
var Color: Integer;
begin
  Color := D.CanvasLayer.RoadPresetColor;
  if Kind = 'river' then Color := D.CanvasLayer.RiverPresetColor;
  if (Kind = 'jr') or (Kind = 'rail') then
    Require(S.GetValue('color') = nil, 'Rail colors belong to the canvas palette.');
  Result := TVectArtPathLayer.Create(Name, ReadAutomationVertices(S), False);
  try
    Result.MapElement := Kind;
    Result.StrokeWidth := Num(S,'width',24,0.1,4096);
    Result.StrokeColor := Int(S,'color',Color,0,$FFFFFF);
    Result.MapColorOverride := (S.GetValue('color') <> nil) and (Result.StrokeColor <> Color);
    Result.LineCap := TVectArtLineCap(Int(S,'line_cap',1,0,2));
  except
    Result.Free;
    raise;
  end;
end;
function MakeBuilding(S: TJSONObject; const Name: string): TMapRakuGroupLayer;
var X,Y,W,H: Single;
begin
  X := Num(S,'x',0); Y := Num(S,'y',0);
  W := Num(S,'width',100,12,10000); H := Num(S,'height',60,12,10000);
  Result := TMapRakuGroupLayer.Create(Name);
  try
    Result.AddChild(TVectArtRectangleLayer.Create(Name,
      TRectF.Create(X-W/2,Y-H/2,X+W/2,Y+H/2),Int(S,'color',$D8D8D8,0,$FFFFFF)));
    Result.AddChild(FittedText('名称',Str(S,'label',Name),'Yu Gothic UI',
      Num(S,'font_size',16,1,512),TRectF.Create(X-W/2+4,Y-H/2+4,X+W/2-4,Y+H/2-4),
      Int(S,'text_color',0,0,$FFFFFF),True));
  except
    Result.Free;
    raise;
  end;
end;
function CreateAutomationLayer(Spec: TJSONObject; Document: TVectArtDocument): TVectArtLayer;
var Kind, Name: string; X,Y,W,H: Single; Symbol: Integer;
begin
  Kind := Str(Spec,'kind'); Name := Str(Spec,'name',Kind);
  CheckSpec(Spec,Kind);
  if (Kind = 'road') or (Kind = 'jr') or (Kind = 'rail') or (Kind = 'river') then
    Result := MakePath(Spec,Document,Kind,Name)
  else if Kind = 'symbol' then begin
    Symbol := Int(Spec,'symbol',-1,0,9);
    Result := CreateMapSymbol(Symbol,Str(Spec,'label',MapSymbolDefaultLabel(Symbol)));
    try
      RotateMapRakuLayer(Result,PointF(0,0),Num(Spec,'rotation',0,-360,360));
      TranslateMapRakuLayer(Result,Num(Spec,'x',0),Num(Spec,'y',0));
    except
      Result.Free;
      raise;
    end;
  end
  else if Kind = 'building' then Result := MakeBuilding(Spec,Name)
  else if Kind = 'level_boundary' then Result := TMapRakuLevelBoundaryLayer.Create(Name)
  else begin
    X := Num(Spec,'x',0); Y := Num(Spec,'y',0);
    W := Num(Spec,'width',120,1,10000); H := Num(Spec,'height',32,1,10000);
    if Kind = 'text' then
      Result := FittedText(Name,Str(Spec,'text'),Str(Spec,'font','Yu Gothic UI'),
        Num(Spec,'font_size',20,1,512),TRectF.Create(X,Y,X+W,Y+H),Int(Spec,'color',0,0,$FFFFFF),False)
    else if Kind = 'rectangle' then
      Result := TVectArtRectangleLayer.Create(Name,TRectF.Create(X,Y,X+W,Y+H),
        Int(Spec,'color',$D8D8D8,0,$FFFFFF))
    else if Kind = 'ellipse' then
      Result := TMapRakuEllipseLayer.Create(Name,TRectF.Create(X,Y,X+W,Y+H),
        Int(Spec,'color',$E8A050,0,$FFFFFF))
    else raise EArgumentException.Create('Unknown placement kind: '+Kind);
  end;
  try
    Result.Name := Name;
    if Str(Spec,'id') <> '' then Result.PersistentId := Str(Spec,'id');
    Result.Opacity := Num(Spec,'opacity',1,0,1);
  except
    Result.Free;
    raise;
  end;
end;
end.
