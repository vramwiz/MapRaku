// 配置候補の描画を担当し、選択状態と地図の実描画に使う色・模様を反映する。
unit MapRakuPresetButtonPainter;
interface
uses Vcl.Graphics, MapRakuDocument;
type TMapRakuSymbolPreview = procedure of object;
procedure PaintMapPresetButton(ACanvas: TCanvas; AWidth, AHeight, APreset: Integer;
  const ATitle: string; ADocument: TVectArtDocument; ASelected, AFocused: Boolean;
  ASymbolPreview: TMapRakuSymbolPreview);
implementation
uses System.Classes, System.Math, System.Types, System.Skia, Winapi.Windows,
  Vcl.Imaging.pngimage, MapRakuRailRenderer, MapRakuToolPalette;

procedure PaintMapPresetButton(ACanvas: TCanvas; AWidth, AHeight, APreset: Integer;
  const ATitle: string; ADocument: TVectArtDocument; ASelected, AFocused: Boolean;
  ASymbolPreview: TMapRakuSymbolPreview);
var R:TRect; Y:Integer;
  procedure LinePreview(Color:TColor; Rail:Boolean; Curved:Boolean;
    Secondary:TColor=clWhite);
  var P:array[0..3] of TPoint;
  begin
    ACanvas.Pen.Color:=Color; ACanvas.Pen.Width:=IfThen(Rail,7,5);
    P[0]:=Point(8,28); P[1]:=Point(25,16); P[2]:=Point(45,38); P[3]:=Point(64,20);
    if Curved then ACanvas.PolyBezier([P[0],P[1],P[2],P[3]])
    else if (APreset=0) or (APreset=10) or (APreset=13) or
      (APreset=20) or (APreset=340) then begin ACanvas.MoveTo(8,27); ACanvas.LineTo(64,27); end
    else ACanvas.Polyline(P);
    if Rail then begin ACanvas.Pen.Color:=Secondary; ACanvas.Pen.Width:=2;
      if Curved then ACanvas.PolyBezier([P[0],P[1],P[2],P[3]])
      else if (APreset=0) or (APreset=10) or (APreset=13) or
        (APreset=20) or (APreset=340) then begin ACanvas.MoveTo(8,27); ACanvas.LineTo(64,27); end
      else ACanvas.Polyline(P); end;
  end;
  // 本描画と同じ破線・枕木規則を縮図にも使い、表示比率を一致させる。
  procedure RailPreview(JR:Boolean);
  var
    Background:TColor;
    Builder:ISkPathBuilder;
    Image:TPngImage;
    Layer:TVectArtPathLayer;
    RGB:TColor;
    ShapeKind:Integer;
    Stream:TMemoryStream;
    Surface:ISkSurface;
  begin
    if (ADocument<>nil) and (ADocument.CanvasLayer<>nil) then
      Background:=ADocument.CanvasLayer.BackgroundColor
    else Background:=clWhite;
    RGB:=ColorToRGB(Background);
    Surface:=TSkSurface.MakeRaster(64,41);
    Surface.Canvas.Clear($FF000000 or (Cardinal(RGB and $FF) shl 16) or
      Cardinal(RGB and $FF00) or (Cardinal(RGB shr 16) and $FF));
    Builder:=TSkPathBuilder.Create;
    ShapeKind:=(APreset-10) mod 3;
    case ShapeKind of
      0: begin Builder.MoveTo(PointF(4,21)); Builder.LineTo(PointF(60,21)); end;
      1: begin Builder.MoveTo(PointF(4,31)); Builder.LineTo(PointF(29,9));
        Builder.LineTo(PointF(60,31)); end;
    else
      begin Builder.MoveTo(PointF(4,31));
        Builder.CubicTo(PointF(21,0),PointF(41,43),PointF(60,13)); end;
    end;
    Layer:=TVectArtPathLayer.Create('Rail preview',[],False);
    try
      if JR then Layer.MapElement:='jr' else Layer.MapElement:='rail';
      Layer.StrokeWidth:=10;
      if ADocument<>nil then
        DrawMapRail(Surface.Canvas,Builder.Detach,Layer,
          ADocument.CanvasLayer,1)
      else
        DrawMapRail(Surface.Canvas,Builder.Detach,Layer,nil,1);
    finally
      Layer.Free;
    end;
    Stream:=TMemoryStream.Create;
    Image:=TPngImage.Create;
    try
      Surface.MakeImageSnapshot.EncodeToStream(Stream);
      Stream.Position:=0;
      Image.LoadFromStream(Stream);
      ACanvas.Draw(4,5,Image);
    finally
      Image.Free;
      Stream.Free;
    end;
  end;
begin
  if ASelected then ACanvas.Brush.Color:=MAPRAKU_TOOL_SELECTED_COLOR
  else ACanvas.Brush.Color:=$00303030;
  ACanvas.FillRect(Rect(0,0,AWidth,AHeight));
  if ASelected then begin
    ACanvas.Pen.Color:=MAPRAKU_TOOL_SELECTED_BORDER;
    ACanvas.Pen.Width:=2;
  end else begin
    ACanvas.Pen.Color:=IfThen(AFocused,$00D77800,$00606060);
    ACanvas.Pen.Width:=1;
  end;
  ACanvas.Brush.Style:=bsClear;
  R:=Rect(0,0,AWidth,AHeight); Dec(R.Right); Dec(R.Bottom); ACanvas.Rectangle(R);
  ACanvas.Pen.Width:=1;
  case APreset of
    // 記号は実レイヤーから作った縮図をボタン側でキャッシュする。
    100..199,343..344: ASymbolPreview;
    0..2: if ADocument<>nil then
      LinePreview(ADocument.CanvasLayer.RoadPresetColor,False,APreset=2)
      else LinePreview($00E4E4E4,False,APreset=2);
    10..12: RailPreview(True);
    13..15: RailPreview(False);
    20..22: if ADocument<>nil then
      LinePreview(ADocument.CanvasLayer.RiverPresetColor,False,APreset=22)
      else LinePreview($00E8A050,False,APreset=22);
    340..342: LinePreview(clRed,False,APreset=342);
    23: begin ACanvas.Brush.Style:=bsSolid; ACanvas.Brush.Color:=$00E8A050;
      ACanvas.Pen.Color:=$00C08030; ACanvas.Ellipse(15,10,57,42); end;
    24: begin ACanvas.Brush.Style:=bsSolid; ACanvas.Brush.Color:=$00E8A050;
      ACanvas.Rectangle(14,10,58,42); end;
    25: begin ACanvas.Brush.Style:=bsSolid; ACanvas.Brush.Color:=$00E8A050;
      ACanvas.RoundRect(14,10,58,42,14,14); end;
    26,27: begin ACanvas.Brush.Style:=bsSolid; ACanvas.Brush.Color:=$00E8A050;
      ACanvas.Polygon([Point(10,34),Point(22,12),Point(45,9),Point(63,29),Point(42,42)]); end;
    200..202: begin
      ACanvas.Brush.Style:=bsSolid; ACanvas.Brush.Color:=clWhite;
      ACanvas.Pen.Color:=clBlack; ACanvas.Rectangle(12,10,60,40);
      for Y:=14 to 38 do if ((Y-14) mod 5)=0 then begin
        ACanvas.MoveTo(14+(Y-14) div 3,Y); ACanvas.LineTo(58-(Y-14) div 3,Y);
      end;
    end;
    300,313: begin ACanvas.Pen.Color:=clWhite;
      ACanvas.Rectangle(14,12,58,39); end;
    301,314: begin ACanvas.Pen.Color:=clWhite;
      ACanvas.Ellipse(15,11,57,40); end;
    302,316: begin ACanvas.Pen.Color:=clWhite;
      ACanvas.RoundRect(14,11,58,40,11,11); end;
    310: begin ACanvas.Pen.Color:=clWhite;
      ACanvas.MoveTo(10,37); ACanvas.LineTo(61,13); end;
    311,312: begin ACanvas.Pen.Color:=clWhite;
      ACanvas.Polyline([Point(9,34),Point(20,17),Point(34,27),
        Point(48,11),Point(63,32)]); end;
    315,330: begin ACanvas.Pen.Color:=clWhite;
      ACanvas.Polygon([Point(11,35),Point(23,12),Point(44,17),
        Point(60,36)]); end;
    317,331: begin ACanvas.Pen.Color:=clWhite;
      ACanvas.Arc(14,10,58,42,58,27,14,27); end;
    320,321: begin ACanvas.Font.Color:=clWhite;
      ACanvas.Font.Name:='Segoe UI'; ACanvas.Font.Height:=-26;
      ACanvas.Font.Style:=[fsBold]; ACanvas.TextOut(28,8,'T');
      ACanvas.Font.Style:=[]; end;
  else
    ACanvas.Brush.Style:=bsSolid; ACanvas.Brush.Color:=clWhite; ACanvas.Pen.Color:=clBlack;
    ACanvas.Ellipse(23,10,49,36); ACanvas.Font.Color:=clBlack;
    ACanvas.TextOut(31,15,Copy(ATitle,1,1));
  end;
  ACanvas.Brush.Style:=bsClear; ACanvas.Font.Color:=clWhite;
  if APreset in [10..15] then ACanvas.Font.Height:=-13
  else ACanvas.Font.Height:=-11;
  Y:=AHeight-18; R:=Rect(2,Y,AWidth-2,AHeight-2);
  DrawText(ACanvas.Handle,PChar(ATitle),Length(ATitle),R,
    DT_CENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
end;

end.
