// 地図要素を分類と描画サムネイルから選び、既存作成ツールへ接続する。
unit MapRakuMapPanel;
interface
uses System.Classes, System.Types, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  MapRakuDocument, MapRakuEditorState, MapRakuEditHistory;
type
  TMapPresetButton = class(TCustomControl)
  private FTitle:string;
  protected procedure Paint; override;
  public constructor Create(AOwner:TComponent); override;
    property Title:string read FTitle write FTitle;
  end;
  TMapToolsPanel = class(TPanel)
  private
    FDocument:TVectArtDocument; FState:TVectArtEditorState;
    FHistory:TVectArtEditHistory; FCategory:TComboBox; FGallery:TScrollBox;
    procedure CategoryChange(Sender:TObject); procedure PresetClick(Sender:TObject);
    procedure CategoryDrawItem(Control:TWinControl; Index:Integer; Rect:TRect;
      State:TOwnerDrawState);
    procedure FillPresets; procedure AddPreset(Preset:Integer; const Title:string);
    procedure ActivateLine(const Kind:string; Tool:TVectArtEditorTool;
      VertexKind:TMapRakuVertexKind; Color:TColor);
    procedure ActivateWaterShape(Tool:TVectArtEditorTool; VertexKind:TMapRakuVertexKind);
    procedure ActivateSymbol(SymbolIndex:Integer);
  public constructor CreateTools(Owner:TComponent; Document:TVectArtDocument;
    State:TVectArtEditorState; History:TVectArtEditHistory; Host:TWinControl);
  end;
implementation
uses System.Math, Winapi.Windows;

function U(const C:array of Word):string;
var I:Integer;
begin SetLength(Result,Length(C)); for I:=0 to High(C) do Result[I+1]:=Char(C[I]); end;

constructor TMapPresetButton.Create(AOwner:TComponent);
begin inherited; Width:=72; Height:=64; Cursor:=crHandPoint; TabStop:=True; end;

procedure TMapPresetButton.Paint;
var R:TRect; Y:Integer;
  procedure LinePreview(Color:TColor; Rail:Boolean; Curved:Boolean);
  var P:array[0..3] of TPoint;
  begin
    Canvas.Pen.Color:=Color; Canvas.Pen.Width:=IfThen(Rail,7,5);
    P[0]:=Point(8,28); P[1]:=Point(25,16); P[2]:=Point(45,38); P[3]:=Point(64,20);
    if Curved then Canvas.PolyBezier([P[0],P[1],P[2],P[3]])
    else if Tag in [0,10,13,20] then begin Canvas.MoveTo(8,27); Canvas.LineTo(64,27); end
    else Canvas.Polyline(P);
    if Rail then begin Canvas.Pen.Color:=clWhite; Canvas.Pen.Width:=2;
      if Curved then Canvas.PolyBezier([P[0],P[1],P[2],P[3]])
      else if Tag in [0,10,13,20] then begin Canvas.MoveTo(8,27); Canvas.LineTo(64,27); end
      else Canvas.Polyline(P); end;
  end;
begin
  Canvas.Brush.Color:=$00303030; Canvas.FillRect(ClientRect);
  Canvas.Pen.Color:=IfThen(Focused,$00D77800,$00606060); Canvas.Brush.Style:=bsClear;
  R:=ClientRect; Dec(R.Right); Dec(R.Bottom); Canvas.Rectangle(R);
  case Tag of
    0..2: LinePreview($00E4E4E4,False,Tag=2);
    10..15: LinePreview(clBlack,True,(Tag mod 3)=2);
    20..22: LinePreview($00E8A050,False,Tag=22);
    23: begin Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=$00E8A050;
      Canvas.Pen.Color:=$00C08030; Canvas.Ellipse(15,10,57,42); end;
    24: begin Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=$00E8A050;
      Canvas.Rectangle(14,10,58,42); end;
    25: begin Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=$00E8A050;
      Canvas.RoundRect(14,10,58,42,14,14); end;
    26,27: begin Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=$00E8A050;
      Canvas.Polygon([Point(10,34),Point(22,12),Point(45,9),Point(63,29),Point(42,42)]); end;
  else
    Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=clWhite; Canvas.Pen.Color:=clBlack;
    Canvas.Ellipse(23,10,49,36); Canvas.Font.Color:=clBlack;
    Canvas.TextOut(31,15,Copy(FTitle,1,1));
  end;
  Canvas.Brush.Style:=bsClear; Canvas.Font.Color:=clWhite; Canvas.Font.Height:=-11;
  Y:=Height-18; R:=Rect(2,Y,Width-2,Height-2);
  DrawText(Canvas.Handle,PChar(FTitle),Length(FTitle),R,
    DT_CENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
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
  FCategory.Items.Add(U([$9053,$8DEF]));
  FCategory.Items.Add(U([$7DDA,$8DEF])); FCategory.Items.Add(U([$6C34,$7CFB]));
  FCategory.Items.Add(U([$8A18,$53F7])); FCategory.ItemIndex:=0; FCategory.OnChange:=CategoryChange;
  FGallery:=TScrollBox.Create(Self); FGallery.Parent:=Self; FGallery.SetBounds(6,48,162,ClientHeight-54);
  FGallery.Anchors:=[akLeft,akTop,akRight,akBottom]; FGallery.BorderStyle:=bsNone;
  FGallery.Color:=Color; FGallery.HorzScrollBar.Visible:=False; FillPresets;
end;

procedure TMapToolsPanel.AddPreset(Preset:Integer; const Title:string);
var B:TMapPresetButton; N:Integer;
begin N:=FGallery.ControlCount; B:=TMapPresetButton.Create(Self); B.Parent:=FGallery;
  B.SetBounds(4+(N mod 2)*76,4+(N div 2)*68,72,64); B.Tag:=Preset; B.Title:=Title;
  B.OnClick:=PresetClick; B.ShowHint:=True; B.Hint:=Title;
end;

procedure TMapToolsPanel.FillPresets;
begin
  while FGallery.ControlCount>0 do FGallery.Controls[FGallery.ControlCount-1].Free;
  case FCategory.ItemIndex of
    0: begin AddPreset(0,U([$76F4,$7DDA])); AddPreset(1,U([$92ED,$89D2,$9023,$7D9A])); AddPreset(2,U([$30D9,$30B8,$30A7,$9023,$7D9A])); end;
    1: begin AddPreset(10,'JR '+U([$76F4,$7DDA])); AddPreset(11,'JR '+U([$92ED,$89D2])); AddPreset(12,'JR '+U([$30D9,$30B8,$30A7]));
      AddPreset(13,U([$79C1,$9244])+' '+U([$76F4,$7DDA])); AddPreset(14,U([$79C1,$9244])+' '+U([$92ED,$89D2])); AddPreset(15,U([$79C1,$9244])+' '+U([$30D9,$30B8,$30A7])); end;
    2: begin AddPreset(20,U([$5DDD,$76F4,$7DDA])); AddPreset(21,U([$5DDD,$92ED,$89D2])); AddPreset(22,U([$5DDD,$30D9,$30B8,$30A7]));
      AddPreset(23,U([$5186])); AddPreset(24,U([$56DB,$89D2])); AddPreset(25,U([$89D2,$4E38])); AddPreset(26,U([$9589,$3058,$305F,$30D1,$30B9])); AddPreset(27,U([$30D9,$30B8,$30A7,$30D1,$30B9])); end;
    3: begin AddPreset(100,U([$99C5])); AddPreset(101,U([$4FE1,$53F7])); AddPreset(102,U([$6A2A,$65AD,$6B69,$9053]));
      AddPreset(103,U([$6B69,$9053,$6A4B])); AddPreset(104,U([$756A,$53F7])); AddPreset(105,U([$99D0,$8ECA,$5834]));
      AddPreset(106,U([$65B9,$4F4D])); AddPreset(107,U([$9053,$8DEF,$756A,$53F7])); AddPreset(109,U([$77E2,$5370])); end;
  end;
end;

procedure TMapToolsPanel.CategoryChange(Sender:TObject); begin FillPresets; end;

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
begin FState.CurrentTool:=vetSelect; FState.OpenGroup:=nil; FState.PendingSymbol:=-1;
  FState.MapElement:=Kind; FState.CreationColor:=Color; FState.NextVertexKind:=VertexKind;
  if FState.LineStrokeWidth<2 then FState.LineStrokeWidth:=12; FState.CurrentTool:=Tool; end;

procedure TMapToolsPanel.ActivateWaterShape(Tool:TVectArtEditorTool; VertexKind:TMapRakuVertexKind);
begin FState.CurrentTool:=vetSelect; FState.OpenGroup:=nil; FState.PendingSymbol:=-1;
  FState.MapElement:=''; FState.CreationColor:=$00E8A050; FState.NextVertexKind:=VertexKind;
  FState.CurrentTool:=Tool; end;

procedure TMapToolsPanel.ActivateSymbol(SymbolIndex:Integer);
begin FState.CurrentTool:=vetSelect; FState.OpenGroup:=nil; FState.MapElement:='';
  case SymbolIndex of
    0:FState.PendingSymbolLabel:=U([$99C5]); 1:FState.PendingSymbolLabel:=U([$4FE1,$53F7]);
    2:FState.PendingSymbolLabel:=U([$6A2A,$65AD,$6B69,$9053]);
    3:FState.PendingSymbolLabel:=U([$6B69,$9053,$6A4B]); 4,7:FState.PendingSymbolLabel:='1';
    5:FState.PendingSymbolLabel:=U([$99D0,$8ECA,$5834]); 6:FState.PendingSymbolLabel:=U([$65B9,$4F4D]);
    9:FState.PendingSymbolLabel:=U([$77E2,$5370]);
  end;
  FState.PendingSymbol:=SymbolIndex; end;

procedure TMapToolsPanel.PresetClick(Sender:TObject);
var P:Integer; Kind:string; Base:Integer;
begin
  P:=TControl(Sender).Tag;
  if P>=100 then begin ActivateSymbol(P-100); Exit; end;
  if P in [0..2] then begin
    if P=0 then ActivateLine('road',vetLine,slvkSharp,$00E4E4E4)
    else if P=1 then ActivateLine('road',vetPath,slvkSharp,$00E4E4E4)
    else ActivateLine('road',vetPath,slvkBezier,$00E4E4E4); Exit; end;
  if P in [10..15] then begin Base:=(P-10) mod 3; if P<13 then Kind:='jr' else Kind:='rail';
    if Base=0 then ActivateLine(Kind,vetLine,slvkSharp,clBlack)
    else if Base=1 then ActivateLine(Kind,vetPath,slvkSharp,clBlack)
    else ActivateLine(Kind,vetPath,slvkBezier,clBlack); Exit; end;
  if P in [20..22] then begin
    if P=20 then ActivateLine('river',vetLine,slvkSharp,$00E8A050)
    else if P=21 then ActivateLine('river',vetPath,slvkSharp,$00E8A050)
    else ActivateLine('river',vetPath,slvkBezier,$00E8A050); Exit; end;
  case P of
    23:ActivateWaterShape(vetEllipse,slvkSharp); 24:ActivateWaterShape(vetRectangle,slvkSharp);
    25:ActivateWaterShape(vetRoundedRectangle,slvkSharp); 26:ActivateWaterShape(vetShape,slvkSharp);
    27:ActivateWaterShape(vetShape,slvkBezier);
  end;
end;
end.
