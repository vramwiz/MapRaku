// パイプ利用者へ、地図部品・操作・座標の実装済み契約を自己記述として返す。
unit MapRakuAutomationSchema;
interface
uses System.JSON;
function AutomationMapSchema: TJSONObject;
implementation
uses MapRakuSymbols;
function AutomationMapSchema: TJSONObject;
var K: Integer; Symbols: TJSONArray; Item: TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(
    '{"version":1,"origin":"canvas_center","x_axis":"right","y_axis":"down",'+
    '"color_encoding":"Delphi TColor 0x00BBGGRR",'+
    '"reference":"pre-oriented and cropped PNG, same aspect ratio as canvas; north clockwise from screen up",'+
    '"operations":["canvas","add","update","delete","connect","crossing","remove_crossing"],'+
    '"canvas_fields":["width","height","background","transparent","road_color","river_color","jr_primary","jr_secondary","rail_primary","rail_secondary"],'+
    '"kinds":["road","jr","rail","river","symbol","building","text","rectangle","ellipse","level_boundary"],'+
    '"common_fields":["kind","id","name","opacity"],'+
    '"path_fields":["vertices","width","color","line_cap"],'+
    '"vertex_fields":["x","y","incomingX","incomingY","outgoingX","outgoingY","kind","outgoingSegment"],'+
    '"vertex_kind":["sharp","bezier"],"outgoingSegment":["line","cubicBezier"],'+
    '"control_coordinates":"offset from vertex; vertices are document coordinates",'+
    '"rail_colors":"Set canvas palette; color on jr/rail paths is rejected",'+
    '"connect_example":{"op":"connect","id":"road-branch","endpoint":0,"target":"road-main","target_endpoint":1,"align":true},'+
    '"symbol_fields":["symbol","label","x","y","rotation"],'+
    '"building_fields":["x","y","width","height","label","color","text_color","font_size"],'+
    '"text_fields":["x","y","width","height","text","font","font_size","color"],'+
    '"shape_fields":["x","y","width","height","color"],'+
    '"position":"building and symbol: center; text and shapes: top-left",'+
    '"update_fields":["name","opacity","visible","dx","dy","vertices","width","color","text"],'+
    '"crossing_kinds":{"normal":0,"railroad_crossing":1,"overpass":2,"bridge":3,"rail_overpass":4,"none":5,"underpass":6,"tunnel":7},'+
    '"line_caps":{"square":0,"round":1,"triangle":2},'+
    '"ordering":"add appends at top; level_boundary separates height; groups are organizational",'+
    '"batch_example":{"operations":['+
    '{"op":"add","spec":{"kind":"road","id":"road-main","width":24,"vertices":[{"x":-300,"y":0},{"x":300,"y":0}]}},'+
    '{"op":"add","spec":{"kind":"jr","id":"jr-main","width":12,"vertices":[{"x":0,"y":-200},{"x":0,"y":200}]}},'+
    '{"op":"crossing","a":"road-main","b":"jr-main","kind":4,"upper":"jr-main","margin":16},'+
    '{"op":"add","spec":{"kind":"symbol","symbol":0,"label":"中央駅","x":0,"y":-100}},'+
    '{"op":"add","spec":{"kind":"building","name":"市役所","x":130,"y":120,"width":100,"height":60}}]},'+
    '"update_example":{"op":"update","id":"road-main","changes":{"width":28}},'+
    '"delete_example":{"op":"delete","id":"road-main"},'+
    '"limits":{"batch_operations":512,"vertices_per_path":4096,"layers":10000,"canvas_edge":8192},'+
    '"validation":"structural only; compare preview with source for geographic accuracy"}') as TJSONObject;
  Symbols := TJSONArray.Create;
  Result.AddPair('symbols',Symbols);
  for K := 0 to 9 do begin
    Item := TJSONObject.Create;
    Item.AddPair('symbol',TJSONNumber.Create(K));
    Item.AddPair('label',MapSymbolDefaultLabel(K));
    Symbols.AddElement(Item);
  end;
end;
end.
