// 色ピッカーが編集する作成色、レイヤー色、グラデーション点、フィルター色を解決する。
unit MapRakuColorTargets;

interface

uses
  Vcl.Graphics, MapRakuContext, MapRakuDocument,
  MapRakuFilters, MapRakuObjectPropertyCommands,
  MapRakuObjectPropertySelection;

// 選択中の有効なフィルターと、そのフィルターを所有するレイヤーを返す。
function MapRakuSelectedFilter(const Context: IVectArtDesignerContext;
  out Layer: TVectArtLayer; out Filter: TMapRakuFilter): Boolean;
// 作成ツール中など、ピッカーが配置済みオブジェクトではなく作成既定値を編集する場合にTrueを返す。
function MapRakuUsesCreationPaint(
  const Context: IVectArtDesignerContext): Boolean;
// 単一選択されたグラデーションの現在点を返し、点未選択時は始点を対象にする。
function MapRakuSelectedGradientStop(
  const Context: IVectArtDesignerContext; out Layer: TVectArtLayer;
  out StopId: Integer; out Color: TColor): Boolean;
// 色を持つフィルターから現在色を取得する。
function TryGetMapRakuFilterColor(Filter: TMapRakuFilter;
  out Value: TColor): Boolean;
// 色を持つフィルターへVCL色を設定する。非対応フィルターでは何もしない。
procedure SetMapRakuFilterColor(Filter: TMapRakuFilter;
  Value: TColor);
// レイヤー種別と色対象に応じて、互換用の塗り色または線色を更新する。
procedure SetMapRakuLayerColor(Layer: TVectArtLayer;
  Target: TMapRakuLayerColorTarget; Value: TColor);

implementation

uses
  MapRakuEditorState, MapRakuPaintStyles;

function MapRakuSelectedFilter(const Context: IVectArtDesignerContext;
  out Layer: TVectArtLayer; out Filter: TMapRakuFilter): Boolean;
var
  I: Integer;
begin
  Layer := nil;
  Filter := nil;
  Result := False;
  if (Context = nil) or (Context.EditorState = nil) then
    Exit;
  Layer := Context.EditorState.SelectedFilterLayer;
  Filter := Context.EditorState.SelectedFilter;
  if (Layer = nil) or (Filter = nil) then
    Exit;
  for I := 0 to Layer.FilterCount - 1 do
    if Layer.Filters[I] = Filter then
      Exit(True);
  Layer := nil;
  Filter := nil;
end;

function MapRakuUsesCreationPaint(
  const Context: IVectArtDesignerContext): Boolean;
begin
  Result := (Context <> nil) and (Context.EditorState <> nil) and
    (Context.EditorState.CurrentTool <> vetSelect);
end;

function MapRakuSelectedGradientStop(
  const Context: IVectArtDesignerContext; out Layer: TVectArtLayer;
  out StopId: Integer; out Color: TColor): Boolean;
var
  Layers: TArray<TVectArtLayer>;
begin
  Layer := nil;
  StopId := SCREEN_LAYOUT_GRADIENT_STOP_NONE;
  Color := clNone;
  Result := False;
  if (Context = nil) or (Context.EditorState = nil) or
    (Context.EditorState.CurrentTool <> vetSelect) or
    (Context.EditorState.SelectedFilter <> nil) then
    Exit;
  Layers := MapRakuSelectedColorLayers(Context);
  if (Length(Layers) <> 1) or
    (Layers[0].PaintStyle.Kind <> slpkGradient) then
    Exit;
  Layer := Layers[0];
  StopId := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  if Context.EditorState.SelectedGradientLayer = Layer then
    StopId := Context.EditorState.SelectedGradientStopId;
  if not Layer.PaintStyle.GetGradientStopColor(StopId, Color) then
    StopId := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  Result := Layer.PaintStyle.GetGradientStopColor(StopId, Color);
end;

function TryGetMapRakuFilterColor(Filter: TMapRakuFilter;
  out Value: TColor): Boolean;
begin
  Result := True;
  if Filter is TMapRakuOutlineFilter then
    Value := TMapRakuOutlineFilter(Filter).Color
  else if Filter is TMapRakuShadowFilter then
    Value := TMapRakuShadowFilter(Filter).Color
  else
  begin
    Value := clNone;
    Result := False;
  end;
end;

procedure SetMapRakuFilterColor(Filter: TMapRakuFilter;
  Value: TColor);
begin
  Value := ColorToRGB(Value);
  if Filter is TMapRakuOutlineFilter then
    TMapRakuOutlineFilter(Filter).Color := Value
  else if Filter is TMapRakuShadowFilter then
    TMapRakuShadowFilter(Filter).Color := Value;
end;

procedure SetMapRakuLayerColor(Layer: TVectArtLayer;
  Target: TMapRakuLayerColorTarget; Value: TColor);
begin
  Value := ColorToRGB(Value);
  if Target = slctFill then
  begin
    if Layer is TVectArtRectangleLayer then
      TVectArtRectangleLayer(Layer).FillColor := Value
    else if Layer is TMapRakuShapeLayer then
      TMapRakuShapeLayer(Layer).FillColor := Value;
  end
  else if Layer is TMapRakuRectangleLineLayer then
    TMapRakuRectangleLineLayer(Layer).StrokeColor := Value
  else if Layer is TMapRakuArcLayer then
    TMapRakuArcLayer(Layer).StrokeColor := Value
  else if Layer is TVectArtPathLayer then
  begin
    TVectArtPathLayer(Layer).StrokeColor := Value;
    if (TVectArtPathLayer(Layer).MapElement = 'road') or
      (TVectArtPathLayer(Layer).MapElement = 'river') then
      TVectArtPathLayer(Layer).MapColorOverride := True;
  end
  else if Layer is TMapRakuShapeLayer then
    TMapRakuShapeLayer(Layer).StrokeColor := Value;
end;

end.
