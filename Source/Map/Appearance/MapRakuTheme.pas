// 白／黒テーマを基本色へ適用し、Undo時には元の色を復元する。
unit MapRakuTheme;
interface
uses MapRakuDocument, MapRakuEditHistory;
procedure ApplyMapTheme(Document: TVectArtDocument; History: TVectArtEditHistory; Dark: Boolean);
implementation
uses System.Generics.Collections, Vcl.Graphics, MapRakuEditCommands;
type
  TRailPalette = array[0..3] of TColor;
  TThemeCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayers: TList<TVectArtLayer>;
    FOld, FNew: TList<TColor>;
    FOldBackground, FNewBackground: TColor;
    FOldRoadPreset, FNewRoadPreset: TColor;
    FOldRail, FNewRail: TRailPalette;
    procedure Collect(L: TVectArtLayer; Dark: Boolean);
    procedure Apply(Colors: TList<TColor>; Background,
      RoadPreset: TColor; const Rail: TRailPalette);
  public
    constructor Create(Document: TVectArtDocument; Dark: Boolean);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;
procedure TThemeCommand.Collect(L: TVectArtLayer; Dark: Boolean);
var I: Integer; C, N: TColor;
begin
  if L is TMapRakuGroupLayer then begin
    if TMapRakuGroupLayer(L).MapSymbol then Exit;
    for I := 0 to TMapRakuGroupLayer(L).ChildCount - 1 do Collect(TMapRakuGroupLayer(L)[I], Dark);
    Exit;
  end;
  if (L is TVectArtPathLayer) and
    (TVectArtPathLayer(L).MapElement = 'road') then begin
    if TVectArtPathLayer(L).MapColorOverride then Exit;
    C := TVectArtPathLayer(L).StrokeColor;
    N := FNewRoadPreset;
  end else if L is TMapRakuTextLayer then begin
    C := TMapRakuTextLayer(L).FillColor;
    if (C <> clBlack) and (C <> clWhite) then Exit;
    if Dark then N := clWhite else N := clBlack;
  end else Exit;
  FLayers.Add(L); FOld.Add(C); FNew.Add(N);
end;
constructor TThemeCommand.Create(Document: TVectArtDocument; Dark: Boolean);
var I: Integer; OldDark: Boolean;
  function UpdatedColor(Current, LightDefault, DarkDefault: TColor): TColor;
  begin
    Result := Current;
    if OldDark and (Current = DarkDefault) then Result := LightDefault
    else if not OldDark and (Current = LightDefault) then Result := DarkDefault;
  end;
begin
  inherited Create;
  FDocument := Document; FLayers := TList<TVectArtLayer>.Create;
  FOld := TList<TColor>.Create; FNew := TList<TColor>.Create;
  FOldBackground := Document.CanvasLayer.BackgroundColor;
  FOldRoadPreset := Document.CanvasLayer.RoadPresetColor;
  OldDark := FOldBackground = clBlack;
  FOldRail[0] := Document.CanvasLayer.JrPrimaryColor;
  FOldRail[1] := Document.CanvasLayer.JrSecondaryColor;
  FOldRail[2] := Document.CanvasLayer.RailPrimaryColor;
  FOldRail[3] := Document.CanvasLayer.RailSecondaryColor;
  FNewRail := FOldRail;
  if Dark <> OldDark then
  begin
    FNewRail[0] := UpdatedColor(FOldRail[0],$00222222,clWhite);
    FNewRail[1] := UpdatedColor(FOldRail[1],clWhite,$00222222);
    FNewRail[2] := UpdatedColor(FOldRail[2],$00222222,clWhite);
    FNewRail[3] := UpdatedColor(FOldRail[3],$00222222,clWhite);
  end;
  // ユーザーが変更した道路プリセットはテーマ切替でも維持する。
  if ((FOldBackground=clBlack) and (FOldRoadPreset<>clWhite)) or
     ((FOldBackground<>clBlack) and (FOldRoadPreset<>$00E4E4E4)) then
    FNewRoadPreset:=FOldRoadPreset
  else if Dark then FNewRoadPreset:=clWhite
  else FNewRoadPreset:=$00E4E4E4;
  if Dark then FNewBackground := clBlack else FNewBackground := clWhite;
  for I := 1 to Document.LayerCount - 1 do Collect(Document[I], Dark);
end;
destructor TThemeCommand.Destroy;
begin FLayers.Free; FOld.Free; FNew.Free; inherited; end;
procedure TThemeCommand.Apply(Colors: TList<TColor>; Background,
  RoadPreset: TColor; const Rail: TRailPalette);
var I: Integer;
begin
  FDocument.BeginUpdate;
  try
    FDocument.CanvasLayer.BackgroundColor := Background;
    FDocument.CanvasLayer.RoadPresetColor := RoadPreset;
    FDocument.CanvasLayer.JrPrimaryColor := Rail[0];
    FDocument.CanvasLayer.JrSecondaryColor := Rail[1];
    FDocument.CanvasLayer.RailPrimaryColor := Rail[2];
    FDocument.CanvasLayer.RailSecondaryColor := Rail[3];
    for I := 0 to FLayers.Count - 1 do
      if FLayers[I] is TVectArtPathLayer then TVectArtPathLayer(FLayers[I]).StrokeColor := Colors[I]
      else TMapRakuTextLayer(FLayers[I]).FillColor := Colors[I];
    FDocument.Changed;
  finally FDocument.EndUpdate; end;
end;
procedure TThemeCommand.Execute;
begin Apply(FNew, FNewBackground, FNewRoadPreset,FNewRail); end;
procedure TThemeCommand.Undo;
begin Apply(FOld, FOldBackground, FOldRoadPreset,FOldRail); end;
procedure ApplyMapTheme(Document: TVectArtDocument; History: TVectArtEditHistory; Dark: Boolean);
var C: TThemeCommand;
begin
  C := TThemeCommand.Create(Document, Dark); C.Execute;
  if History <> nil then History.AddApplied(C) else C.Free;
end;

end.
