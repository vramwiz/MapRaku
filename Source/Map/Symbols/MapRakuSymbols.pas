// 地図記号を編集可能なベクター部品のグループとして作る。
unit MapRakuSymbols;
interface
uses System.Types, MapRakuDocument, MapRakuEditHistory;
function MapSymbolDefaultLabel(Kind: Integer): string;
function CreateMapSymbol(Kind: Integer; const LabelText: string): TMapRakuGroupLayer;
procedure InsertMapSymbol(Document: TVectArtDocument; History: TVectArtEditHistory;
  Kind: Integer; const LabelText: string);
procedure PlaceMapSymbol(Document: TVectArtDocument; History: TVectArtEditHistory;
  Kind: Integer; const LabelText: string; Position: TPointF; Snap: Boolean);
implementation
uses System.Math, System.SysUtils, Vcl.Graphics, MapRakuEditCommands, MapRakuLayerGeometry, MapRakuPathSnap, MapRakuTextGeometry;
type
  TSymbolInsert = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FSymbol: TMapRakuGroupLayer;
    FIndex: Integer;
    FApplied: Boolean;
  public
    constructor Create(Document: TVectArtDocument; Symbol: TMapRakuGroupLayer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;
procedure Box(G: TMapRakuGroupLayer; X,Y,W,H: Single; Color: TColor);
begin G.AddChild(TVectArtRectangleLayer.Create('部品', TRectF.Create(X,Y,X+W,Y+H), Color)); end;
procedure Circle(G: TMapRakuGroupLayer; X,Y,R: Single; Color: TColor);
begin G.AddChild(TMapRakuEllipseLayer.Create('丸', TRectF.Create(X-R,Y-R,X+R,Y+R), Color)); end;
procedure Text(G: TMapRakuGroupLayer; const S: string; X,Y,W,H: Single; Color: TColor);
var T: TMapRakuTextLayer; Layout: TMapRakuTextLayout;
begin
  T := TMapRakuTextLayer.Create('名称', TRectF.Create(X,Y,X+W,Y+H), S, 'Yu Gothic UI', H * 0.75, 0, Color);
  T.Text := S; T.FontFamily := 'Yu Gothic UI'; T.FontSize := H * 0.75;
  Layout := BuildMapRakuTextLayout(S, T.FontFamily, T.FontSize, 0);
  T.Bounds := TRectF.Create(X+(W-Layout.Width)*0.5,Y+(H-Layout.Height)*0.5,
    X+(W+Layout.Width)*0.5,Y+(H+Layout.Height)*0.5);
  G.AddChild(T);
end;
function MapSymbolDefaultLabel(Kind: Integer): string;
begin
  case Kind of
    0: Result := '駅';
    1: Result := '信号';
    2: Result := '横断歩道';
    3: Result := '歩道橋';
    4,7: Result := '1';
    5: Result := '駐車場';
    6: Result := '方位';
    9: Result := '矢印';
  else Result := '';
  end;
end;
constructor TSymbolInsert.Create(Document: TVectArtDocument; Symbol: TMapRakuGroupLayer);
begin inherited Create; FDocument := Document; FSymbol := Symbol; FIndex := Document.LayerCount; end;
destructor TSymbolInsert.Destroy;
begin if not FApplied then FSymbol.Free; inherited; end;
procedure TSymbolInsert.Execute;
begin FDocument.InsertLayer(FIndex, FSymbol); FApplied := True; FDocument.SetSelectedLayers([FIndex]); end;
procedure TSymbolInsert.Undo;
begin FDocument.ExtractLayer(FIndex); FApplied := False; end;
function CreateMapSymbol(Kind: Integer; const LabelText: string): TMapRakuGroupLayer;
var I: Integer;
begin
  Result := TMapRakuGroupLayer.Create(LabelText);
  Result.MapSymbol := True;
  try
  case Kind of
    0: begin
      Box(Result,-62,-18,124,36,clBlack); Box(Result,-60,-16,120,32,clWhite);
      Text(Result,LabelText,-48,-13,96,26,clBlack);
    end;
    1: begin
      Box(Result,-30,-12,60,24,$00404040);
      Circle(Result,-19,0,8,clLime); Circle(Result,0,0,8,clYellow); Circle(Result,19,0,8,clRed);
    end;
    2: begin
      Box(Result,-25,-18,50,36,$00606060);
      for I := 0 to 5 do Box(Result,-23+I*8,-18,4,36,clWhite);
    end;
    3: begin
      Box(Result,-50,-8,100,16,$00808080); Box(Result,-48,-6,96,12,clWhite);
      for I := 0 to 6 do begin
        Box(Result,-50,-8+I*4,16,2,clBlack); Box(Result,34,-8+I*4,16,2,clBlack);
      end;
    end;
    4: begin
      Circle(Result,0,0,18,clYellow); Circle(Result,0,0,15,clRed);
      Text(Result,LabelText,-10,-12,20,24,clWhite);
    end;
    5: begin
      Box(Result,-17,-17,34,34,$00D08020);
      Text(Result,'P',-10,-15,20,30,clWhite);
    end;
    6: begin
      Text(Result,'↑',-15,-25,30,40,clBlack); Text(Result,'北',-10,14,20,20,clBlack);
    end;
    7: begin
      Box(Result,-24,-15,48,30,$00CC8822); Text(Result,LabelText,-20,-12,40,24,clWhite);
    end;
    8: begin
      Circle(Result,0,0,40,$00E8BC48);
    end;
    9: Text(Result,'→',-30,-15,60,30,clRed);
  end;
  except
    Result.Free;
    raise;
  end;
end;
procedure PlaceMapSymbol(Document: TVectArtDocument; History: TVectArtEditHistory;
  Kind: Integer; const LabelText: string; Position: TPointF; Snap: Boolean);
var G: TMapRakuGroupLayer; C: TSymbolInsert; P,T: TPointF; Path: TVectArtPathLayer; Bounds: TRectF;
begin
  G := CreateMapSymbol(Kind, LabelText);
  if Snap and (Kind in [0,1,2,3]) and NearestMapPath(Document,Position,32,False,'',P,T,Path) then begin
    Position := P;
    if (Kind in [2,3]) and TryGetMapRakuLayerBounds(G,Bounds) then
      ScaleMapRakuLayer(G,Bounds,TRectF.Create(Bounds.Left,-Path.StrokeWidth*0.5,Bounds.Right,Path.StrokeWidth*0.5));
    RotateMapRakuLayer(G,PointF(0,0),RadToDeg(ArcTan2(T.Y,T.X)));
  end;
  TranslateMapRakuLayer(G,Position.X,Position.Y);
  C := TSymbolInsert.Create(Document, G); C.Execute;
  if History <> nil then History.AddApplied(C) else C.Free;
end;
procedure InsertMapSymbol(Document: TVectArtDocument; History: TVectArtEditHistory;
  Kind: Integer; const LabelText: string);
begin PlaceMapSymbol(Document,History,Kind,LabelText,PointF(0,0),False); end;
end.
