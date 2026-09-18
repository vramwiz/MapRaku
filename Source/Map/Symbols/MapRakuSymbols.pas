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
function ValidateRouteMarkers(Document: TVectArtDocument;
  out ErrorText: string): Boolean;
implementation
uses System.Math, System.SysUtils, Vcl.Graphics, MapRakuEditCommands, MapRakuLayerGeometry, MapRakuPathSnap, MapRakuTextGeometry;

function RouteIdentifier(Path: TVectArtPathLayer): string;
begin
  if Path.RouteId<>'' then Result:=Path.RouteId else Result:=Path.PersistentId;
end;

function ValidateRouteMarkers(Document: TVectArtDocument;
  out ErrorText: string): Boolean;
var I,J,StartCount,EndCount: Integer; Layer,Target: TVectArtLayer;
begin
  Result := False;
  ErrorText := '';
  if Document=nil then begin ErrorText:='地図文書がありません'; Exit; end;
  for I:=0 to Document.LayerCount-1 do
    if (Document[I] is TMapRakuGroupLayer) and
       (TMapRakuGroupLayer(Document[I]).RouteMarkerKind<>'') then begin
      Layer:=Document[I];
      if not ((TMapRakuGroupLayer(Layer).RouteMarkerKind='start') or
              (TMapRakuGroupLayer(Layer).RouteMarkerKind='end')) then begin
        ErrorText:='不明なルートマーカー種別です'; Exit;
      end;
      if TMapRakuGroupLayer(Layer).RoutePathId='' then begin
        ErrorText:='開始点または終了点がルートに関連付けられていません'; Exit;
      end;
      Target:=nil;
      for J:=0 to Document.LayerCount-1 do
        if (Document[J] is TVectArtPathLayer) and
           (TVectArtPathLayer(Document[J]).MapElement='route') and
           (RouteIdentifier(TVectArtPathLayer(Document[J]))=
             TMapRakuGroupLayer(Layer).RoutePathId) then
          Target:=Document[J];
      if Target=nil then begin ErrorText:='関連付けられたルートが見つかりません'; Exit; end;
    end;
  for I:=0 to Document.LayerCount-1 do
    if (Document[I] is TVectArtPathLayer) and
       (TVectArtPathLayer(Document[I]).MapElement='route') then begin
      StartCount:=0; EndCount:=0;
      for J:=0 to Document.LayerCount-1 do
        if (Document[J] is TMapRakuGroupLayer) and
         (TMapRakuGroupLayer(Document[J]).RoutePathId=
           RouteIdentifier(TVectArtPathLayer(Document[I]))) then begin
          if TMapRakuGroupLayer(Document[J]).RouteMarkerKind='start' then Inc(StartCount);
          if TMapRakuGroupLayer(Document[J]).RouteMarkerKind='end' then Inc(EndCount);
        end;
      if StartCount>1 then begin ErrorText:='1本のルートに開始点が複数あります'; Exit; end;
      if EndCount>1 then begin ErrorText:='1本のルートに終了点が複数あります'; Exit; end;
      if StartCount=0 then begin ErrorText:='ルートに開始点がありません'; Exit; end;
      if EndCount=0 then begin ErrorText:='ルートに終了点がありません'; Exit; end;
    end;
  Result:=True;
end;
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
    10: Result := '開始点';
    11: Result := '終了点';
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
    10: begin
      Circle(Result,0,0,15,clLime); Circle(Result,0,0,9,clWhite);
      Text(Result,'S',-8,-11,16,22,clBlack);
    end;
    11: begin
      Circle(Result,0,0,15,clRed); Circle(Result,0,0,9,clWhite);
      Text(Result,'E',-8,-11,16,22,clBlack);
    end;
  end;
  except
    Result.Free;
    raise;
  end;
end;

function SnapPathKindForSymbol(Kind: Integer): string;
begin
  // 駅は線路上だけに置く。道路用記号が川や線路に吸着しないよう、対象系列を明示する。
  case Kind of
    0: Result := 'jr';
    1, 2, 3: Result := 'road';
  else
    Result := '';
  end;
end;

procedure PlaceMapSymbol(Document: TVectArtDocument; History: TVectArtEditHistory;
  Kind: Integer; const LabelText: string; Position: TPointF; Snap: Boolean);
var G: TMapRakuGroupLayer; C: TSymbolInsert; P,T: TPointF; Path: TVectArtPathLayer; Bounds: TRectF;
  I: Integer; SnapKind: string; BridgeSpan: Single;
  Endpoint: TMapRakuEndpointSnap;
begin
  G := CreateMapSymbol(Kind, LabelText);
  if Kind=10 then G.RouteMarkerKind:='start'
  else if Kind=11 then G.RouteMarkerKind:='end';
  if Snap and (Kind in [10,11]) and
     NearestMapEndpoint(Document,Position,32,False,'route',Endpoint) then begin
    Position := Endpoint.Point;
    Path := Endpoint.Path;
    G.RoutePathId := RouteIdentifier(Path);
    G.RouteMarkerPosition := Position;
    G.HasRouteMarkerPosition := True;
    for I:=0 to Document.LayerCount-1 do
      if (Document[I] is TMapRakuGroupLayer) and
         (TMapRakuGroupLayer(Document[I]).RouteMarkerKind=G.RouteMarkerKind) and
         (TMapRakuGroupLayer(Document[I]).RoutePathId=G.RoutePathId) then begin
        G.Free;
        Exit;
      end;
  end
  else begin
    SnapKind := SnapPathKindForSymbol(Kind);
    if Snap and (SnapKind <> '') and
       NearestMapPath(Document,Position,32,False,SnapKind,P,T,Path) then begin
    Position := P;
      if (Kind=2) and TryGetMapRakuLayerBounds(G,Bounds) then
        ScaleMapRakuLayer(G,Bounds,TRectF.Create(Bounds.Left,
          -Path.StrokeWidth*0.5,Bounds.Right,Path.StrokeWidth*0.5));
      if (Kind=3) and TryGetMapRakuLayerBounds(G,Bounds) then begin
        // 歩道橋の長辺は道路を横切る。道路幅より短くならないよう余白を足す。
        BridgeSpan := Max(Bounds.Width,Path.StrokeWidth+32);
        ScaleMapRakuLayer(G,Bounds,TRectF.Create(-BridgeSpan*0.5,
          Bounds.Top,BridgeSpan*0.5,Bounds.Bottom));
        RotateMapRakuLayer(G,PointF(0,0),RadToDeg(ArcTan2(T.Y,T.X))+90);
      end
      else
        RotateMapRakuLayer(G,PointF(0,0),RadToDeg(ArcTan2(T.Y,T.X)));
    end;
  end;
  TranslateMapRakuLayer(G,Position.X,Position.Y);
  C := TSymbolInsert.Create(Document, G); C.Execute;
  if History <> nil then History.AddApplied(C) else C.Free;
end;
procedure InsertMapSymbol(Document: TVectArtDocument; History: TVectArtEditHistory;
  Kind: Integer; const LabelText: string);
begin PlaceMapSymbol(Document,History,Kind,LabelText,PointF(0,0),False); end;
end.
