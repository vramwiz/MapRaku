// 共通経路から地図要素別の描画へ振り分ける。通常Pathは元の描画へ戻す。
unit MapRakuPathRenderer;
interface
uses System.Skia, MapRakuDocument;
function DrawMapPath(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single; Pass: Integer): Boolean;
implementation
uses MapRakuRoadRenderer, MapRakuRailRenderer, MapRakuRiverRenderer,
  MapRakuStairRenderer;
function DrawMapPath(const Canvas: ISkCanvas; const Path: ISkPath;
  Layer: TVectArtPathLayer; Opacity: Single; Pass: Integer): Boolean;
begin
  Result := Layer.MapElement <> '';
  if Layer.MapElement = 'road' then DrawMapRoad(Canvas, Path, Layer, Opacity, Pass)
  else if Pass <> 1 then begin
    if (Layer.MapElement = 'jr') or (Layer.MapElement = 'rail') then
      DrawMapRail(Canvas, Path, Layer, Opacity)
    else if Layer.MapElement = 'river' then DrawMapRiver(Canvas, Path, Layer, Opacity);
    if (Layer.MapElement='stairs-up') or (Layer.MapElement='stairs-down') then
      DrawMapStairs(Canvas,Path,Layer,Opacity);
    if Layer.MapElement='pedestrian-bridge' then
      DrawPedestrianBridge(Canvas,Path,Layer,Opacity);
  end;
end;
end.
