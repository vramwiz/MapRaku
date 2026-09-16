// 右上ツールバーの線属性変更をレイヤー種別へ振り分け、複数選択のUndo履歴を構築する。
unit MapRakuLineToolbarOperations;

interface

uses
  Vcl.Graphics, MapRakuDocument, MapRakuEditHistory;

// 開いた線レイヤーの共通属性を返す。閉じたPathや非対応レイヤーではFalseを返す。
function TryReadMapRakuToolbarLine(Layer: TVectArtLayer;
  out Color: TColor; out Width: Single; out Style: TVectArtMifStrokeStyle;
  out LineCap: TVectArtLineCap): Boolean;
// 選択済み線の線端を変更する。矩形線は線端を持たず、変更対象から除外される。
procedure ApplyMapRakuToolbarLineCap(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  Value: TVectArtLineCap);
// 選択済み線の線種を変更し、複数選択の変更を1件のUndo履歴へまとめる。
procedure ApplyMapRakuToolbarLineStyle(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  Value: TVectArtMifStrokeStyle);
// 選択済み線の幅を変更する。RecordHistory=Falseはドラッグ中のプレビュー更新に使用する。
procedure ApplyMapRakuToolbarLineWidth(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  Value: Single; RecordHistory: Boolean);
// ドラッグ開始時の線幅と現在値から、既に適用済みの変更履歴だけを追加する。
procedure RecordMapRakuToolbarLineWidths(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  const OldWidths: TArray<Single>);
// 選択済みの開いたPathを均一幅または初期100%の可変幅へ切り替える。
procedure ApplyMapRakuToolbarWidthMode(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  Value: TMapRakuStrokeWidthMode);

implementation

uses
  System.Math, MapRakuEditCommands;

type
  // Document直下とグループ内のどちらにも同じUndo処理を適用する。
  TLayerStrokeCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FOldColor, FNewColor: TColor;
    FOldWidth, FNewWidth: Single;
    FOldStyle, FNewStyle: TVectArtMifStrokeStyle;
    procedure Apply(Color: TColor; Width: Single; Style: TVectArtMifStrokeStyle);
  public
    constructor Create(ADocument: TVectArtDocument; ALayer: TVectArtLayer;
      OldColor: TColor; OldWidth: Single; OldStyle: TVectArtMifStrokeStyle;
      NewColor: TColor; NewWidth: Single; NewStyle: TVectArtMifStrokeStyle);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TLayerLineCapCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FOldValue, FNewValue: TVectArtLineCap;
    procedure Apply(Value: TVectArtLineCap);
  public
    constructor Create(ADocument: TVectArtDocument; ALayer: TVectArtLayer;
      OldValue, NewValue: TVectArtLineCap);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TLayerWidthPointsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtPathLayer;
    FOldValue, FNewValue: TArray<TMapRakuStrokeWidthPoint>;
    procedure Apply(const Value: TArray<TMapRakuStrokeWidthPoint>);
  public
    constructor Create(ADocument: TVectArtDocument; ALayer: TVectArtPathLayer;
      const OldValue, NewValue: TArray<TMapRakuStrokeWidthPoint>);
    procedure Execute; override;
    procedure Undo; override;
  end;

procedure SetLineStroke(Document: TVectArtDocument; Layer: TVectArtLayer;
  Color: TColor; Width: Single; Style: TVectArtMifStrokeStyle);
begin
  if Layer is TMapRakuRectangleLineLayer then
  begin
    TMapRakuRectangleLineLayer(Layer).StrokeColor := Color;
    TMapRakuRectangleLineLayer(Layer).StrokeWidth := Width;
    TMapRakuRectangleLineLayer(Layer).StrokeStyle := Style;
  end
  else if Layer is TMapRakuArcLayer then
  begin
    TMapRakuArcLayer(Layer).StrokeColor := Color;
    TMapRakuArcLayer(Layer).StrokeWidth := Width;
    TMapRakuArcLayer(Layer).StrokeStyle := Style;
  end
  else if Layer is TVectArtPathLayer then
  begin
    TVectArtPathLayer(Layer).StrokeColor := Color;
    TVectArtPathLayer(Layer).StrokeWidth := Width;
    TVectArtPathLayer(Layer).MifStrokeStyle := Style;
  end;
  Document.Changed;
end;

procedure SetLineCap(Document: TVectArtDocument; Layer: TVectArtLayer;
  Value: TVectArtLineCap);
begin
  if Layer is TMapRakuArcLayer then
    TMapRakuArcLayer(Layer).LineCap := Value
  else if Layer is TVectArtPathLayer then
    TVectArtPathLayer(Layer).LineCap := Value;
  Document.Changed;
end;

procedure TLayerStrokeCommand.Apply(Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle);
begin
  if (FDocument <> nil) and (FLayer <> nil) then
    SetLineStroke(FDocument, FLayer, Color, Width, Style);
end;

constructor TLayerStrokeCommand.Create(ADocument: TVectArtDocument;
  ALayer: TVectArtLayer; OldColor: TColor; OldWidth: Single;
  OldStyle: TVectArtMifStrokeStyle; NewColor: TColor; NewWidth: Single;
  NewStyle: TVectArtMifStrokeStyle);
begin
  inherited Create; FDocument := ADocument; FLayer := ALayer;
  FOldColor := OldColor; FOldWidth := OldWidth; FOldStyle := OldStyle;
  FNewColor := NewColor; FNewWidth := NewWidth; FNewStyle := NewStyle;
end;

procedure TLayerStrokeCommand.Execute; begin Apply(FNewColor, FNewWidth, FNewStyle); end;
procedure TLayerStrokeCommand.Undo; begin Apply(FOldColor, FOldWidth, FOldStyle); end;

procedure TLayerLineCapCommand.Apply(Value: TVectArtLineCap);
begin
  if (FDocument <> nil) and (FLayer <> nil) then SetLineCap(FDocument, FLayer, Value);
end;

constructor TLayerLineCapCommand.Create(ADocument: TVectArtDocument;
  ALayer: TVectArtLayer; OldValue, NewValue: TVectArtLineCap);
begin inherited Create; FDocument := ADocument; FLayer := ALayer;
  FOldValue := OldValue; FNewValue := NewValue; end;
procedure TLayerLineCapCommand.Execute; begin Apply(FNewValue); end;
procedure TLayerLineCapCommand.Undo; begin Apply(FOldValue); end;

procedure TLayerWidthPointsCommand.Apply(
  const Value: TArray<TMapRakuStrokeWidthPoint>);
begin
  if (FDocument = nil) or (FLayer = nil) then Exit;
  FLayer.WidthPoints := Copy(Value); FDocument.Changed;
end;

constructor TLayerWidthPointsCommand.Create(ADocument: TVectArtDocument;
  ALayer: TVectArtPathLayer; const OldValue,
  NewValue: TArray<TMapRakuStrokeWidthPoint>);
begin inherited Create; FDocument := ADocument; FLayer := ALayer;
  FOldValue := Copy(OldValue); FNewValue := Copy(NewValue); end;
procedure TLayerWidthPointsCommand.Execute; begin Apply(FNewValue); end;
procedure TLayerWidthPointsCommand.Undo; begin Apply(FOldValue); end;

procedure AddAppliedCommand(History: TVectArtEditHistory;
  Command: TVectArtCompoundCommand);
begin
  if (Command <> nil) and (Command.Count > 0) and (History <> nil) then
    History.AddApplied(Command)
  else
    Command.Free;
end;

function TryReadMapRakuToolbarLine(Layer: TVectArtLayer;
  out Color: TColor; out Width: Single; out Style: TVectArtMifStrokeStyle;
  out LineCap: TVectArtLineCap): Boolean;
begin
  Result := True;
  if Layer is TMapRakuRectangleLineLayer then
  begin
    Color := TMapRakuRectangleLineLayer(Layer).StrokeColor;
    Width := TMapRakuRectangleLineLayer(Layer).StrokeWidth;
    Style := TMapRakuRectangleLineLayer(Layer).StrokeStyle;
    LineCap := vlcSquare;
  end
  else if Layer is TMapRakuArcLayer then
  begin
    Color := TMapRakuArcLayer(Layer).StrokeColor;
    Width := TMapRakuArcLayer(Layer).StrokeWidth;
    Style := TMapRakuArcLayer(Layer).StrokeStyle;
    LineCap := TMapRakuArcLayer(Layer).LineCap;
  end
  else if (Layer is TVectArtPathLayer) and
    not TVectArtPathLayer(Layer).Closed then
  begin
    Color := TVectArtPathLayer(Layer).StrokeColor;
    Width := TVectArtPathLayer(Layer).StrokeWidth;
    Style := TVectArtPathLayer(Layer).MifStrokeStyle;
    LineCap := TVectArtPathLayer(Layer).LineCap;
  end
  else
    Result := False;
end;

procedure ApplyMapRakuToolbarLineCap(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  Value: TVectArtLineCap);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  I: Integer;
  OldLineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if Document = nil then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Layers) do
    begin
      if Layers[I] is TMapRakuRectangleLineLayer then
        Continue;
      if not TryReadMapRakuToolbarLine(Layers[I], Color,
        Width, Style, OldLineCap) or (OldLineCap = Value) then
        Continue;
      Command.Add(TLayerLineCapCommand.Create(Document, Layers[I],
        OldLineCap, Value));
      SetLineCap(Document, Layers[I], Value);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

procedure ApplyMapRakuToolbarLineStyle(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  Value: TVectArtMifStrokeStyle);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  I: Integer;
  LineCap: TVectArtLineCap;
  OldStyle: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if Document = nil then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Layers) do
    begin
      if not TryReadMapRakuToolbarLine(Layers[I], Color,
        Width, OldStyle, LineCap) or (OldStyle = Value) then
        Continue;
      Command.Add(TLayerStrokeCommand.Create(Document, Layers[I], Color,
        Width, OldStyle, Color, Width, Value));
      SetLineStroke(Document, Layers[I], Color, Width, Value);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

procedure ApplyMapRakuToolbarLineWidth(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  Value: Single; RecordHistory: Boolean);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  I: Integer;
  Layer: TVectArtLayer;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if Document = nil then
    Exit;
  Value := Max(Value, 0.1);
  Command := nil;
  if RecordHistory then
    Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Layers) do
    begin
      Layer := Layers[I];
      if not TryReadMapRakuToolbarLine(Layer, Color, Width, Style,
        LineCap) or SameValue(Width, Value) then
        Continue;
      if Command <> nil then
        Command.Add(TLayerStrokeCommand.Create(Document, Layer, Color,
          Width, Style, Color, Value, Style));
      SetLineStroke(Document, Layer, Color, Value, Style);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

procedure RecordMapRakuToolbarLineWidths(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  const OldWidths: TArray<Single>);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  I: Integer;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if (Document = nil) or (History = nil) then Exit;
  Command := TVectArtCompoundCommand.Create;
  for I := 0 to Min(High(Layers), High(OldWidths)) do
    if TryReadMapRakuToolbarLine(Layers[I], Color, Width, Style,
      LineCap) and not SameValue(OldWidths[I], Width) then
      Command.Add(TLayerStrokeCommand.Create(Document, Layers[I], Color,
        OldWidths[I], Style, Color, Width, Style));
  AddAppliedCommand(History, Command);
end;

procedure ApplyMapRakuToolbarWidthMode(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Layers: TArray<TVectArtLayer>;
  Value: TMapRakuStrokeWidthMode);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  NewValue: TArray<TMapRakuStrokeWidthPoint>;
  OldValue: TArray<TMapRakuStrokeWidthPoint>;
  Path: TVectArtPathLayer;
begin
  if Document = nil then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Layers) do
    begin
      if not (Layers[I] is TVectArtPathLayer) then
        Continue;
      Path := TVectArtPathLayer(Layers[I]);
      if Path.Closed then
        Continue;
      OldValue := Path.WidthPoints;
      if Value = slwmVariable then
      begin
        if Length(OldValue) > 0 then
          Continue;
        NewValue := UniformMapRakuStrokeWidthPoints;
      end
      else
      begin
        if Length(OldValue) = 0 then
          Continue;
        NewValue := nil;
      end;
      Command.Add(TLayerWidthPointsCommand.Create(Document, Path,
        OldValue, NewValue));
      Path.WidthPoints := Copy(NewValue);
      Document.Changed;
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

end.
