// Object Propertiesが直接参照するレイヤー属性をUndo／Redo可能にする。
// レイヤーの単色、不透明度、線属性、線端変更をUndo／Redo可能にする。
unit MapRakuObjectPropertyCommands;

interface

uses
  Vcl.Graphics, MapRakuDocument, MapRakuEditCommands;

type
  TMapRakuLayerColorTarget = (slctFill, slctStroke);

  TMapRakuLayerColorCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FNewColor: TColor;
    FOldColor: TColor;
    FTarget: TMapRakuLayerColorTarget;
    procedure Apply(Value: TColor);
  public
    // 適用済みの塗り色または線色変更を保持し、同じLayer参照へ再適用する。
    constructor Create(ADocument: TVectArtDocument; ALayer: TVectArtLayer;
      ATarget: TMapRakuLayerColorTarget; OldColor, NewColor: TColor);
    // 保存した新色を反映し、Documentの変更通知を発生させる。
    procedure Execute; override;
    // 保存した旧色を復元し、Documentの変更通知を発生させる。
    procedure Undo; override;
  end;

  TMapRakuLayerOpacityCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FNewValue: Single;
    FOldValue: Single;
    procedure Apply(Value: Single);
  public
    // 適用済み不透明度変更を保持し、グループ内Layerにも同じ値を復元できるようにする。
    constructor Create(ADocument: TVectArtDocument; ALayer: TVectArtLayer;
      OldValue, NewValue: Single);
    // 保存した新しい不透明度を反映し、Documentの変更通知を発生させる。
    procedure Execute; override;
    // 保存した変更前の不透明度を復元し、Documentの変更通知を発生させる。
    procedure Undo; override;
  end;

  TMapRakuLayerStrokeCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FNewColor: TColor;
    FNewStyle: TVectArtMifStrokeStyle;
    FNewWidth: Single;
    FOldColor: TColor;
    FOldStyle: TVectArtMifStrokeStyle;
    FOldWidth: Single;
    procedure Apply(Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
  public
    // 線色・線幅・線種を一組で保持し、他属性を失わずUndo／Redoする。
    constructor Create(ADocument: TVectArtDocument; ALayer: TVectArtLayer;
      OldColor: TColor; OldWidth: Single; OldStyle: TVectArtMifStrokeStyle;
      NewColor: TColor; NewWidth: Single; NewStyle: TVectArtMifStrokeStyle);
    // 保存した新しい線属性一式を反映し、Documentの変更通知を発生させる。
    procedure Execute; override;
    // 保存した変更前の線属性一式を復元し、Documentの変更通知を発生させる。
    procedure Undo; override;
  end;

  TMapRakuLayerLineCapCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FNewValue: TVectArtLineCap;
    FOldValue: TVectArtLineCap;
    procedure Apply(Value: TVectArtLineCap);
  public
    // 円弧または開いたPathの線端変更を同じLayer参照へ再適用する。
    constructor Create(ADocument: TVectArtDocument; ALayer: TVectArtLayer;
      OldValue, NewValue: TVectArtLineCap);
    // 保存した新しい線端を反映し、Documentの変更通知を発生させる。
    procedure Execute; override;
    // 保存した変更前の線端を復元し、Documentの変更通知を発生させる。
    procedure Undo; override;
  end;

implementation

uses
  System.Math;

procedure TMapRakuLayerColorCommand.Apply(Value: TColor);
begin
  if (FDocument = nil) or (FLayer = nil) then
    Exit;
  Value := ColorToRGB(Value);
  if FTarget = slctFill then
  begin
    if FLayer is TVectArtRectangleLayer then
      TVectArtRectangleLayer(FLayer).FillColor := Value
    else if FLayer is TMapRakuShapeLayer then
      TMapRakuShapeLayer(FLayer).FillColor := Value
    else
      Exit;
  end
  else if FLayer is TMapRakuRectangleLineLayer then
    TMapRakuRectangleLineLayer(FLayer).StrokeColor := Value
  else if FLayer is TMapRakuArcLayer then
    TMapRakuArcLayer(FLayer).StrokeColor := Value
  else if FLayer is TVectArtPathLayer then
    TVectArtPathLayer(FLayer).StrokeColor := Value
  else if FLayer is TMapRakuShapeLayer then
    TMapRakuShapeLayer(FLayer).StrokeColor := Value
  else
    Exit;
  FDocument.Changed;
end;

constructor TMapRakuLayerColorCommand.Create(
  ADocument: TVectArtDocument; ALayer: TVectArtLayer;
  ATarget: TMapRakuLayerColorTarget; OldColor, NewColor: TColor);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := ALayer;
  FTarget := ATarget;
  FOldColor := ColorToRGB(OldColor);
  FNewColor := ColorToRGB(NewColor);
end;

procedure TMapRakuLayerColorCommand.Execute;
begin
  Apply(FNewColor);
end;

procedure TMapRakuLayerColorCommand.Undo;
begin
  Apply(FOldColor);
end;

procedure TMapRakuLayerOpacityCommand.Apply(Value: Single);
begin
  if (FDocument = nil) or (FLayer = nil) then
    Exit;
  Value := EnsureRange(Value, 0.0, 1.0);
  if SameValue(FLayer.Opacity, Value) then
    Exit;
  FLayer.Opacity := Value;
  FDocument.Changed;
end;

constructor TMapRakuLayerOpacityCommand.Create(
  ADocument: TVectArtDocument; ALayer: TVectArtLayer;
  OldValue, NewValue: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := ALayer;
  FOldValue := EnsureRange(OldValue, 0.0, 1.0);
  FNewValue := EnsureRange(NewValue, 0.0, 1.0);
end;

procedure TMapRakuLayerOpacityCommand.Execute;
begin
  Apply(FNewValue);
end;

procedure TMapRakuLayerOpacityCommand.Undo;
begin
  Apply(FOldValue);
end;

procedure TMapRakuLayerStrokeCommand.Apply(Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle);
begin
  if (FDocument = nil) or (FLayer = nil) then
    Exit;
  Color := ColorToRGB(Color);
  Width := Max(Width, 0.0);
  if FLayer is TMapRakuRectangleLineLayer then
  begin
    TMapRakuRectangleLineLayer(FLayer).StrokeColor := Color;
    TMapRakuRectangleLineLayer(FLayer).StrokeWidth := Width;
    TMapRakuRectangleLineLayer(FLayer).StrokeStyle := Style;
  end
  else if FLayer is TMapRakuArcLayer then
  begin
    TMapRakuArcLayer(FLayer).StrokeColor := Color;
    TMapRakuArcLayer(FLayer).StrokeWidth := Width;
    TMapRakuArcLayer(FLayer).StrokeStyle := Style;
  end
  else if FLayer is TVectArtPathLayer then
  begin
    TVectArtPathLayer(FLayer).StrokeColor := Color;
    TVectArtPathLayer(FLayer).StrokeWidth := Width;
    TVectArtPathLayer(FLayer).MifStrokeStyle := Style;
  end
  else
    Exit;
  FDocument.Changed;
end;

constructor TMapRakuLayerStrokeCommand.Create(
  ADocument: TVectArtDocument; ALayer: TVectArtLayer; OldColor: TColor;
  OldWidth: Single; OldStyle: TVectArtMifStrokeStyle; NewColor: TColor;
  NewWidth: Single; NewStyle: TVectArtMifStrokeStyle);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := ALayer;
  FOldColor := ColorToRGB(OldColor);
  FOldWidth := OldWidth;
  FOldStyle := OldStyle;
  FNewColor := ColorToRGB(NewColor);
  FNewWidth := NewWidth;
  FNewStyle := NewStyle;
end;

procedure TMapRakuLayerStrokeCommand.Execute;
begin
  Apply(FNewColor, FNewWidth, FNewStyle);
end;

procedure TMapRakuLayerStrokeCommand.Undo;
begin
  Apply(FOldColor, FOldWidth, FOldStyle);
end;

procedure TMapRakuLayerLineCapCommand.Apply(Value: TVectArtLineCap);
begin
  if (FDocument = nil) or (FLayer = nil) then
    Exit;
  if FLayer is TMapRakuArcLayer then
    TMapRakuArcLayer(FLayer).LineCap := Value
  else if (FLayer is TVectArtPathLayer) and
    not TVectArtPathLayer(FLayer).Closed then
    TVectArtPathLayer(FLayer).LineCap := Value
  else
    Exit;
  FDocument.Changed;
end;

constructor TMapRakuLayerLineCapCommand.Create(
  ADocument: TVectArtDocument; ALayer: TVectArtLayer;
  OldValue, NewValue: TVectArtLineCap);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := ALayer;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TMapRakuLayerLineCapCommand.Execute;
begin
  Apply(FNewValue);
end;

procedure TMapRakuLayerLineCapCommand.Undo;
begin
  Apply(FOldValue);
end;

end.
