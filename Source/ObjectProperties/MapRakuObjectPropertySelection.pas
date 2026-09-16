// Object Propertiesが扱う現在選択を、属性別の編集対象へ分類する。
unit MapRakuObjectPropertySelection;

interface

uses
  Vcl.Graphics, MapRakuContext, MapRakuDocument,
  MapRakuObjectPropertyCommands;

// 塗り色または線色を持つ選択レイヤーだけを、現在の編集階層を保って返す。
function MapRakuSelectedColorLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
// 不透明度を変更できる全選択レイヤーを、トップレベルとグループ内の双方から返す。
function MapRakuSelectedOpacityLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
// 線幅、線種、線端を持つ選択レイヤーだけを返す。
function MapRakuSelectedLineLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
// 単一選択中のレイヤーを、トップレベルとグループ内の双方から返す。
function MapRakuSelectedSingleLayer(
  const Context: IVectArtDesignerContext): TVectArtLayer;
// Layerの主要色と、ピッカーが塗り・線のどちらを変更すべきかを返す。
function TryGetMapRakuLayerColor(Layer: TVectArtLayer;
  out Value: TColor; out Target: TMapRakuLayerColorTarget): Boolean;
// 線編集GUIへ表示する共通属性を読み、線端を持たない閉じた線も区別する。
function TryReadMapRakuLineLayer(Layer: TVectArtLayer;
  out Color: TColor; out Width: Single; out Style: TVectArtMifStrokeStyle;
  out LineCap: TVectArtLineCap; out HasLineCap: Boolean): Boolean;
// 旧属性領域に残した円弧角度UIが現在選択に必要かを返す。
function MapRakuSelectionNeedsArcProperties(
  const Context: IVectArtDesignerContext): Boolean;

implementation

uses
  System.Generics.Collections;

function SelectedLayers(const Context: IVectArtDesignerContext):
  TArray<TVectArtLayer>;
var
  Count: Integer;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLayer;
begin
  SetLength(Result, 0);
  if (Context = nil) or (Context.Document = nil) then
    Exit;
  Count := 0;
  // 子選択リストは編集終了直後の通知中にも残り得るため、開いているGroupも確認する。
  if (Context.EditorState <> nil) and
    (Context.EditorState.OpenGroup <> nil) and
    (Context.EditorState.OpenGroupChildCount > 0) then
  begin
    Result := Context.EditorState.GetOpenGroupChildren;
    for Layer in Result do
      if Layer <> nil then
        Inc(Count);
    if Count <> Length(Result) then
    begin
      SetLength(Result, Count);
      Count := 0;
      for Layer in Context.EditorState.GetOpenGroupChildren do
        if Layer <> nil then
        begin
          Result[Count] := Layer;
          Inc(Count);
        end;
    end;
    Exit;
  end;

  Indices := Context.Document.GetSelectedLayerIndices;
  SetLength(Result, Length(Indices));
  for I := 0 to High(Indices) do
    if (Indices[I] > 0) and (Indices[I] < Context.Document.LayerCount) then
    begin
      Result[Count] := Context.Document[Indices[I]];
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

function MapRakuSelectedColorLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
var
  Layer: TVectArtLayer;
  Layers: TList<TVectArtLayer>;
  Target: TMapRakuLayerColorTarget;
  Value: TColor;
begin
  Layers := TList<TVectArtLayer>.Create;
  try
    for Layer in SelectedLayers(Context) do
      if TryGetMapRakuLayerColor(Layer, Value, Target) then
        Layers.Add(Layer);
    Result := Layers.ToArray;
  finally
    Layers.Free;
  end;
end;

function MapRakuSelectedOpacityLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
begin
  Result := SelectedLayers(Context);
end;

function MapRakuSelectedLineLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
var
  HasLineCap: Boolean;
  Layer: TVectArtLayer;
  Layers: TList<TVectArtLayer>;
  LineCap: TVectArtLineCap;
  Color: TColor;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  Layers := TList<TVectArtLayer>.Create;
  try
    for Layer in SelectedLayers(Context) do
      if TryReadMapRakuLineLayer(Layer, Color, Width, Style, LineCap,
        HasLineCap) then
        Layers.Add(Layer);
    Result := Layers.ToArray;
  finally
    Layers.Free;
  end;
end;

function MapRakuSelectedSingleLayer(
  const Context: IVectArtDesignerContext): TVectArtLayer;
var
  Layers: TArray<TVectArtLayer>;
begin
  Layers := SelectedLayers(Context);
  if Length(Layers) = 1 then
    Result := Layers[0]
  else
    Result := nil;
end;

function TryGetMapRakuLayerColor(Layer: TVectArtLayer;
  out Value: TColor; out Target: TMapRakuLayerColorTarget): Boolean;
begin
  Result := True;
  if Layer is TVectArtRectangleLayer then
  begin
    Target := slctFill;
    Value := TVectArtRectangleLayer(Layer).FillColor;
  end
  else if Layer is TMapRakuShapeLayer then
  begin
    Target := slctFill;
    Value := TMapRakuShapeLayer(Layer).FillColor;
  end
  else
  begin
    Target := slctStroke;
    if Layer is TMapRakuRectangleLineLayer then
      Value := TMapRakuRectangleLineLayer(Layer).StrokeColor
    else if Layer is TMapRakuArcLayer then
      Value := TMapRakuArcLayer(Layer).StrokeColor
    else if Layer is TVectArtPathLayer then
      Value := TVectArtPathLayer(Layer).StrokeColor
    else
      Result := False;
  end;
end;

function TryReadMapRakuLineLayer(Layer: TVectArtLayer;
  out Color: TColor; out Width: Single; out Style: TVectArtMifStrokeStyle;
  out LineCap: TVectArtLineCap; out HasLineCap: Boolean): Boolean;
begin
  Result := True;
  HasLineCap := False;
  LineCap := vlcSquare;
  if Layer is TMapRakuRectangleLineLayer then
  begin
    Color := TMapRakuRectangleLineLayer(Layer).StrokeColor;
    Width := TMapRakuRectangleLineLayer(Layer).StrokeWidth;
    Style := TMapRakuRectangleLineLayer(Layer).StrokeStyle;
  end
  else if Layer is TMapRakuArcLayer then
  begin
    Color := TMapRakuArcLayer(Layer).StrokeColor;
    Width := TMapRakuArcLayer(Layer).StrokeWidth;
    Style := TMapRakuArcLayer(Layer).StrokeStyle;
    LineCap := TMapRakuArcLayer(Layer).LineCap;
    HasLineCap := True;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Color := TVectArtPathLayer(Layer).StrokeColor;
    Width := TVectArtPathLayer(Layer).StrokeWidth;
    Style := TVectArtPathLayer(Layer).MifStrokeStyle;
    LineCap := TVectArtPathLayer(Layer).LineCap;
    HasLineCap := not TVectArtPathLayer(Layer).Closed;
  end
  else
    Result := False;
end;

function MapRakuSelectionNeedsArcProperties(
  const Context: IVectArtDesignerContext): Boolean;
var
  Layer: TVectArtLayer;
begin
  Result := False;
  if (Context = nil) or (Context.Document = nil) then
    Exit;
  Layer := nil;
  if (Context.EditorState <> nil) and
    (Context.EditorState.OpenGroupChildCount = 1) then
    Layer := Context.EditorState.OpenGroupChild
  else if Context.Document.SelectionCount = 1 then
    Layer := Context.Document[Context.Document.SelectedIndex];
  Result := (Layer is TMapRakuArcLayer) or
    (Layer is TMapRakuEllipseArcShapeLayer);
end;

end.
