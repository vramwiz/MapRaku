// 地図要素を分類と描画サムネイルから選び、既存作成ツールへ接続する。
unit MapRakuMapPanel;
interface
uses System.Classes, System.Types, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  MapRakuDocument, MapRakuEditorState, MapRakuEditHistory;
type
  TMapPresetButton = class(TCustomControl)
  private FTitle:string; FState:TVectArtEditorState; FDocument:TVectArtDocument;
    FPreview:TBitmap; FPreviewBackground:TColor;
    procedure PaintSymbolPreview;
  protected procedure Paint; override;
  public constructor Create(AOwner:TComponent); override;
    destructor Destroy; override;
    property Title:string read FTitle write FTitle;
    property EditorState:TVectArtEditorState read FState write FState;
    property Document:TVectArtDocument read FDocument write FDocument;
    property OnMouseWheel;
  end;
  TMapToolsPanel = class(TPanel)
  private
    FDocument:TVectArtDocument; FState:TVectArtEditorState;
    FHistory:TVectArtEditHistory; FCategory:TComboBox; FGallery:TScrollBox;
    FFirstPreset:TMapPresetButton;
    FOnCategoryChange:TNotifyEvent;
    FRowTop,FRowHeight,FGroupItemCount:Integer;
    procedure CategoryChange(Sender:TObject); procedure PresetClick(Sender:TObject);
    procedure PresetMouseWheel(Sender:TObject; Shift:TShiftState;
      WheelDelta:Integer; MousePos:TPoint; var Handled:Boolean);
    procedure CategoryDrawItem(Control:TWinControl; Index:Integer; Rect:TRect;
      State:TOwnerDrawState);
    procedure FillPresets; procedure FillCategoryPresets(Index:Integer);
    procedure AddCategoryHeader(const Title:string);
    procedure AddPreset(Preset:Integer; const Title:string);
    procedure ActivateFirstPreset;
    procedure ActivateLine(const Kind:string; Tool:TVectArtEditorTool;
      VertexKind:TMapRakuVertexKind; Color:TColor);
    procedure ActivateWaterShape(Tool:TVectArtEditorTool; VertexKind:TMapRakuVertexKind);
    procedure ActivateSymbol(SymbolIndex:Integer);
    procedure ActivateGeneric(Tool:TVectArtEditorTool);
  public constructor CreateTools(Owner:TComponent; Document:TVectArtDocument;
    State:TVectArtEditorState; History:TVectArtEditHistory; Host:TWinControl);
    procedure RefreshState;
    property OnCategoryChange:TNotifyEvent read FOnCategoryChange write FOnCategoryChange;
  end;
implementation
uses System.Math, System.SysUtils, Winapi.Windows, MapRakuSymbols, MapRakuPresetThumbnail,
  MapRakuPresetButtonPainter;

function U(const C:array of Word):string;
var I:Integer;
begin SetLength(Result,Length(C)); for I:=0 to High(C) do Result[I+1]:=Char(C[I]); end;

constructor TMapPresetButton.Create(AOwner:TComponent);
begin inherited; Width:=72; Height:=64; Cursor:=crHandPoint; TabStop:=True;
  FPreviewBackground:=clNone; end;

destructor TMapPresetButton.Destroy;
begin FPreview.Free; inherited; end;

procedure TMapPresetButton.PaintSymbolPreview;
var Layer:TMapRakuGroupLayer; Background:TColor;
begin
  Background:=clWhite;
  if (FDocument<>nil) and (FDocument.CanvasLayer<>nil) then
    Background:=FDocument.CanvasLayer.BackgroundColor;
  if (FPreview<>nil) and (FPreviewBackground<>Background) then
    FreeAndNil(FPreview);
  if FPreview=nil then begin
    Layer:=CreateMapSymbol(Tag-100,MapSymbolDefaultLabel(Tag-100));
    try FPreview:=CreateMapPresetThumbnail(Layer,64,42,Background);
    finally Layer.Free; end;
    FPreviewBackground:=Background;
  end;
  Canvas.Draw(4,3,FPreview);
end;

procedure TMapPresetButton.Paint;
begin
  // 記号の縮図キャッシュはボタンが持ち、他の描画は共通の描画担当に任せる。
  PaintMapPresetButton(Canvas,Width,Height,Tag,FTitle,FDocument,
    (FState<>nil) and (FState.ActiveMapPreset=Tag),Focused,PaintSymbolPreview);
end;

constructor TMapToolsPanel.CreateTools(Owner:TComponent; Document:TVectArtDocument;
  State:TVectArtEditorState; History:TVectArtEditHistory; Host:TWinControl);
begin
  inherited Create(Owner); Parent:=Host; FDocument:=Document; FState:=State; FHistory:=History;
  Align:=alLeft; Width:=174; BevelOuter:=bvNone; Color:=$00252525; ParentBackground:=False;
  FCategory:=TComboBox.Create(Self); FCategory.Parent:=Self; FCategory.SetBounds(10,10,150,28);
  FCategory.Style:=csOwnerDrawFixed; FCategory.ItemHeight:=22; FCategory.Color:=$00353535;
  FCategory.Font.Color:=clWhite; FCategory.ParentFont:=False;
  FCategory.OnDrawItem:=CategoryDrawItem;
  FCategory.Items.Add(U([$3059,$3079,$3066]));
  FCategory.Items.Add(U([$9053,$8DEF]));
  FCategory.Items.Add(U([$7DDA,$8DEF])); FCategory.Items.Add(U([$6C34,$7CFB]));
  FCategory.Items.Add(U([$8A18,$53F7])); FCategory.Items.Add(U([$6B69,$9053]));
  FCategory.Items.Add(U([$5EFA,$7269])); FCategory.Items.Add(U([$56F3,$5F62]));
  FCategory.Items.Add(U([$6587,$5B57])); FCategory.Items.Add(U([$305D,$306E,$4ED6]));
  FCategory.ItemIndex:=0; FCategory.OnChange:=CategoryChange;
  FGallery:=TScrollBox.Create(Self); FGallery.Parent:=Self; FGallery.SetBounds(6,48,162,ClientHeight-54);
  FGallery.Anchors:=[akLeft,akTop,akRight,akBottom]; FGallery.BorderStyle:=bsNone;
  FGallery.Color:=Color; FGallery.HorzScrollBar.Visible:=False;
  FGallery.OnMouseWheel:=PresetMouseWheel;
  FillPresets; ActivateFirstPreset;
end;

procedure TMapToolsPanel.AddCategoryHeader(const Title:string);
var LabelControl:TLabel;
begin
  FRowTop:=FRowTop+FRowHeight+5;
  LabelControl:=TLabel.Create(Self);
  LabelControl.Parent:=FGallery;
  LabelControl.SetBounds(6,FRowTop,146,18);
  LabelControl.Caption:=Title;
  LabelControl.Font.Color:=clWhite;
  LabelControl.Font.Style:=[fsBold];
  LabelControl.ParentFont:=False;
  Inc(FRowTop,22);
  FRowHeight:=0;
  FGroupItemCount:=0;
end;

procedure TMapToolsPanel.AddPreset(Preset:Integer; const Title:string);
var B:TMapPresetButton; CardHeight:Integer;
begin
  if (FGroupItemCount>0) and (FGroupItemCount mod 2=0) then begin
    Inc(FRowTop,FRowHeight+4);
    FRowHeight:=0;
  end;
  if Preset in [10..15] then CardHeight:=78 else CardHeight:=64;
  FRowHeight:=Max(FRowHeight,CardHeight);
  B:=TMapPresetButton.Create(Self); B.Parent:=FGallery;
  if FFirstPreset=nil then FFirstPreset:=B;
  B.SetBounds(4+(FGroupItemCount mod 2)*76,FRowTop,72,CardHeight);
  Inc(FGroupItemCount);
  B.Tag:=Preset; B.Title:=Title;
  B.EditorState:=FState;
  B.Document:=FDocument;
  B.OnClick:=PresetClick; B.OnMouseWheel:=PresetMouseWheel;
  B.ShowHint:=True; B.Hint:=Title;
end;

procedure TMapToolsPanel.FillCategoryPresets(Index:Integer);
begin
  case Index of
    0: begin AddPreset(0,U([$76F4,$7DDA])); AddPreset(1,U([$92ED,$89D2,$9023,$7D9A])); AddPreset(2,U([$30D9,$30B8,$30A7,$9023,$7D9A])); end;
    1: begin AddPreset(10,'JR '+U([$76F4,$7DDA])); AddPreset(11,'JR '+U([$92ED,$89D2])); AddPreset(12,'JR '+U([$30D9,$30B8,$30A7]));
      AddPreset(13,U([$79C1,$9244,$76F4,$7DDA])); AddPreset(14,U([$79C1,$9244,$92ED,$89D2])); AddPreset(15,U([$79C1,$9244,$30D9,$30B8,$30A7])); end;
    2: begin AddPreset(20,U([$5DDD,$76F4,$7DDA])); AddPreset(21,U([$5DDD,$92ED,$89D2])); AddPreset(22,U([$5DDD,$30D9,$30B8,$30A7]));
      AddPreset(23,U([$5186])); AddPreset(24,U([$56DB,$89D2])); AddPreset(25,U([$89D2,$4E38])); AddPreset(26,U([$9589,$3058,$305F,$30D1,$30B9])); AddPreset(27,U([$30D9,$30B8,$30A7,$30D1,$30B9])); end;
    3: begin AddPreset(100,U([$99C5])); AddPreset(101,U([$4FE1,$53F7])); AddPreset(102,U([$6A2A,$65AD,$6B69,$9053]));
      AddPreset(103,U([$6B69,$9053,$6A4B])); AddPreset(104,U([$756A,$53F7])); AddPreset(105,U([$99D0,$8ECA,$5834]));
      AddPreset(106,U([$65B9,$4F4D])); AddPreset(107,U([$9053,$8DEF,$756A,$53F7])); AddPreset(109,U([$77E2,$5370])); end;
    4: begin AddPreset(200,U([$968E,$6BB5])+' '+U([$4E0A,$308A]));
      AddPreset(201,U([$968E,$6BB5])+' '+U([$4E0B,$308A]));
      AddPreset(202,U([$6B69,$9053,$6A4B])); end;
    5: begin AddPreset(300,U([$5EFA,$7269])+' '+U([$56DB,$89D2]));
      AddPreset(301,U([$5EFA,$7269])+' '+U([$89D2,$4E38]));
      AddPreset(302,U([$5EFA,$7269])+' '+U([$89D2,$4E38,$56DB,$89D2])); end;
    6: begin AddPreset(310,U([$76F4,$7DDA])); AddPreset(311,U([$81EA,$7531,$66F2,$7DDA]));
      AddPreset(312,U([$9023,$7D9A])); AddPreset(313,U([$56DB,$89D2]));
      AddPreset(314,U([$89D2,$4E38])); AddPreset(315,U([$9589,$3058,$305F,$56F3,$5F62]));
      AddPreset(316,U([$89D2,$4E38,$56DB,$89D2])); AddPreset(317,U([$5186])); end;
    7: begin AddPreset(320,U([$6587,$5B57])); AddPreset(321,U([$7D4C,$8DEF,$6587,$5B57])); end;
    8: begin AddPreset(330,U([$5F27,$5F62])); AddPreset(331,U([$5F27])); end;
  end;
end;

procedure TMapToolsPanel.FillPresets;
var I:Integer;
begin
  FFirstPreset:=nil;
  while FGallery.ControlCount>0 do FGallery.Controls[FGallery.ControlCount-1].Free;
  FRowTop:=4; FRowHeight:=0; FGroupItemCount:=0;
  if FCategory.ItemIndex=0 then
    for I:=0 to FCategory.Items.Count-2 do begin
      AddCategoryHeader(FCategory.Items[I+1]);
      FillCategoryPresets(I);
    end
  else
    FillCategoryPresets(FCategory.ItemIndex-1);
  FGallery.VertScrollBar.Position:=0;
end;

procedure TMapToolsPanel.ActivateFirstPreset;
begin
  if FFirstPreset<>nil then PresetClick(FFirstPreset);
end;

procedure TMapToolsPanel.CategoryChange(Sender:TObject);
begin
  if Assigned(FOnCategoryChange) then FOnCategoryChange(Self);
  FillPresets;
  ActivateFirstPreset;
end;

procedure TMapToolsPanel.PresetMouseWheel(Sender:TObject; Shift:TShiftState;
  WheelDelta:Integer; MousePos:TPoint; var Handled:Boolean);
begin
  Handled:=(WheelDelta<>0) and
    (FGallery.VertScrollBar.Range>FGallery.ClientHeight);
  if Handled then
    FGallery.VertScrollBar.Position:=Max(0,
      FGallery.VertScrollBar.Position-MulDiv(WheelDelta,64,WHEEL_DELTA));
end;

procedure TMapToolsPanel.RefreshState;
var I:Integer;
begin
  if FGallery=nil then Exit;
  for I:=0 to FGallery.ControlCount-1 do
    FGallery.Controls[I].Invalidate;
end;

procedure TMapToolsPanel.CategoryDrawItem(Control:TWinControl; Index:Integer;
  Rect:TRect; State:TOwnerDrawState);
begin
  FCategory.Canvas.Brush.Color:=$00353535; FCategory.Canvas.FillRect(Rect);
  FCategory.Canvas.Font.Color:=clWhite;
  if (Index>=0) and (Index<FCategory.Items.Count) then
    FCategory.Canvas.TextOut(Rect.Left+6,Rect.Top+3,FCategory.Items[Index]);
end;

procedure TMapToolsPanel.ActivateLine(const Kind:string; Tool:TVectArtEditorTool;
  VertexKind:TMapRakuVertexKind; Color:TColor);
var FromSelected:Boolean;
begin FState.CurrentTool:=vetSelect; FState.OpenGroup:=nil; FState.PendingSymbol:=-1;
  FState.MapElement:=Kind; FState.CreationColor:=Color; FState.NextVertexKind:=VertexKind;
  if FState.LineStrokeWidth<2 then FState.LineStrokeWidth:=12;
  FState.CurrentTool:=Tool;
  if Kind='road' then
    FState.CreationColor:=FState.MapPlacementColor(FDocument,FromSelected)
  else if Kind='river' then
    FState.CreationColor:=FState.MapPlacementColor(FDocument,FromSelected);
end;

procedure TMapToolsPanel.ActivateWaterShape(Tool:TVectArtEditorTool; VertexKind:TMapRakuVertexKind);
begin FState.CurrentTool:=vetSelect; FState.OpenGroup:=nil; FState.PendingSymbol:=-1;
  FState.MapElement:=''; FState.CreationColor:=$00E8A050; FState.NextVertexKind:=VertexKind;
  FState.CurrentTool:=Tool; end;

procedure TMapToolsPanel.ActivateSymbol(SymbolIndex:Integer);
begin FState.CurrentTool:=vetSelect; FState.OpenGroup:=nil; FState.MapElement:='';
  FState.PendingSymbolLabel:=MapSymbolDefaultLabel(SymbolIndex);
  FState.PendingSymbol:=SymbolIndex; end;

procedure TMapToolsPanel.ActivateGeneric(Tool:TVectArtEditorTool);
begin
  FState.CurrentTool:=vetSelect;
  FState.OpenGroup:=nil;
  FState.PendingSymbol:=-1;
  FState.MapElement:='';
  FState.ActivateTool(Tool);
end;

procedure TMapToolsPanel.PresetClick(Sender:TObject);
var P:Integer; Kind:string; Base:Integer;
begin
  P:=TControl(Sender).Tag;
  FState.EndMapPlacement;
  if P in [200..202] then begin
    if P=200 then Kind:='stairs-up' else if P=201 then Kind:='stairs-down'
    else Kind:='pedestrian-bridge';
    FState.LineStrokeWidth:=18;
    ActivateLine(Kind,vetLine,slvkSharp,clBlack);
  end
  else if (P>=100) and (P<200) then ActivateSymbol(P-100)
  else if P in [0..2] then begin
    if P=0 then ActivateLine('road',vetLine,slvkSharp,$00E4E4E4)
    else if P=1 then ActivateLine('road',vetPath,slvkSharp,$00E4E4E4)
    else ActivateLine('road',vetPath,slvkBezier,$00E4E4E4); end
  else if P in [10..15] then begin Base:=(P-10) mod 3; if P<13 then Kind:='jr' else Kind:='rail';
    if Base=0 then ActivateLine(Kind,vetLine,slvkSharp,clBlack)
    else if Base=1 then ActivateLine(Kind,vetPath,slvkSharp,clBlack)
    else ActivateLine(Kind,vetPath,slvkBezier,clBlack); end
  else if P in [20..22] then begin
    if P=20 then ActivateLine('river',vetLine,slvkSharp,$00E8A050)
    else if P=21 then ActivateLine('river',vetPath,slvkSharp,$00E8A050)
    else ActivateLine('river',vetPath,slvkBezier,$00E8A050); end
  else if P in [23..27] then
    case P of
      23:ActivateWaterShape(vetEllipse,slvkSharp); 24:ActivateWaterShape(vetRectangle,slvkSharp);
      25:ActivateWaterShape(vetRoundedRectangle,slvkSharp); 26:ActivateWaterShape(vetShape,slvkSharp);
      27:ActivateWaterShape(vetShape,slvkBezier);
    end
  else if (P>=300) and (P<=302) then
    case P of
      300:ActivateGeneric(vetRectangle);
      301:ActivateGeneric(vetEllipse);
      302:ActivateGeneric(vetRoundedRectangle);
    end
  else if (P>=310) and (P<=317) then
    case P of
      310:ActivateGeneric(vetLine);
      311:ActivateGeneric(vetFreehand);
      312:ActivateGeneric(vetPath);
      313:ActivateGeneric(vetRectangle);
      314:ActivateGeneric(vetEllipse);
      315:ActivateGeneric(vetShape);
      316:ActivateGeneric(vetRoundedRectangle);
      317:ActivateGeneric(vetArcShape);
    end
  else if (P>=320) and (P<=321) then
    if P=320 then ActivateGeneric(vetText)
    else ActivateGeneric(vetTextPath)
  else if (P>=330) and (P<=331) then
    if P=330 then ActivateGeneric(vetShape)
    else ActivateGeneric(vetArcShape);
  if (FState.MapElement='road') or (FState.MapElement='river') then
    FState.BeginMapPlacement(FDocument);
  FDocument.SetSelectedLayers([]);
  FState.ActiveMapPreset:=P;
  RefreshState;
end;
end.
