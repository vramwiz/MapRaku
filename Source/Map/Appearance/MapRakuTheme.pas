// 白／黒テーマを基本色へ適用し、Undo時には元の色を復元する。
unit MapRakuTheme;
interface
uses MapRakuDocument, MapRakuEditHistory;
procedure ApplyMapTheme(Document: TVectArtDocument; History: TVectArtEditHistory; Dark: Boolean);
procedure NormalizeMapRailTheme(Document:TVectArtDocument; Dark:Boolean);
implementation
uses System.Generics.Collections, Vcl.Graphics, MapRakuEditCommands;
type
  TThemeCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayers: TList<TVectArtLayer>;
    FOld, FNew: TList<TColor>;
    FOldBackground, FNewBackground: TColor;
    procedure Collect(L: TVectArtLayer; Dark: Boolean);
    procedure Apply(Colors: TList<TColor>; Background: TColor);
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
  if (L is TVectArtPathLayer) and ((TVectArtPathLayer(L).MapElement = 'road') or (TVectArtPathLayer(L).MapElement = 'jr') or (TVectArtPathLayer(L).MapElement = 'rail')) then begin
    C := TVectArtPathLayer(L).StrokeColor;
    if Dark then N := clWhite else if TVectArtPathLayer(L).MapElement='road' then N := $00E4E4E4 else N := clBlack;
  end else if L is TMapRakuTextLayer then begin
    C := TMapRakuTextLayer(L).FillColor;
    if (C <> clBlack) and (C <> clWhite) then Exit;
    if Dark then N := clWhite else N := clBlack;
  end else Exit;
  FLayers.Add(L); FOld.Add(C); FNew.Add(N);
end;
constructor TThemeCommand.Create(Document: TVectArtDocument; Dark: Boolean);
var I: Integer;
begin
  inherited Create;
  FDocument := Document; FLayers := TList<TVectArtLayer>.Create;
  FOld := TList<TColor>.Create; FNew := TList<TColor>.Create;
  FOldBackground := Document.CanvasLayer.BackgroundColor;
  if Dark then FNewBackground := clBlack else FNewBackground := clWhite;
  for I := 1 to Document.LayerCount - 1 do Collect(Document[I], Dark);
end;
destructor TThemeCommand.Destroy;
begin FLayers.Free; FOld.Free; FNew.Free; inherited; end;
procedure TThemeCommand.Apply(Colors: TList<TColor>; Background: TColor);
var I: Integer;
begin
  FDocument.BeginUpdate;
  try
    FDocument.CanvasLayer.BackgroundColor := Background;
    for I := 0 to FLayers.Count - 1 do
      if FLayers[I] is TVectArtPathLayer then TVectArtPathLayer(FLayers[I]).StrokeColor := Colors[I]
      else TMapRakuTextLayer(FLayers[I]).FillColor := Colors[I];
    FDocument.Changed;
  finally FDocument.EndUpdate; end;
end;
procedure TThemeCommand.Execute;
begin Apply(FNew, FNewBackground); end;
procedure TThemeCommand.Undo;
begin Apply(FOld, FOldBackground); end;
procedure ApplyMapTheme(Document: TVectArtDocument; History: TVectArtEditHistory; Dark: Boolean);
var C: TThemeCommand;
begin
  C := TThemeCommand.Create(Document, Dark); C.Execute;
  if History <> nil then History.AddApplied(C) else C.Free;
end;

procedure NormalizeMapRailTheme(Document:TVectArtDocument; Dark:Boolean);
  procedure Normalize(L:TVectArtLayer);
  var I:Integer;
  begin
    if L is TMapRakuGroupLayer then
    begin
      for I:=0 to TMapRakuGroupLayer(L).ChildCount-1 do
        Normalize(TMapRakuGroupLayer(L)[I]);
      Exit;
    end;
    if (L is TVectArtPathLayer) and
      ((TVectArtPathLayer(L).MapElement='jr') or
       (TVectArtPathLayer(L).MapElement='rail')) then
      if Dark then TVectArtPathLayer(L).StrokeColor:=clWhite
      else TVectArtPathLayer(L).StrokeColor:=clBlack;
  end;
var I:Integer;
begin
  if Document=nil then Exit;
  for I:=1 to Document.LayerCount-1 do Normalize(Document[I]);
end;
end.
