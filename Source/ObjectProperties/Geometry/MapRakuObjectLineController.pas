// 線属性Frameと選択レイヤーを同期し、連続操作を1件のUndo履歴へまとめる。
unit MapRakuObjectLineController;

interface

uses
  System.Classes, Vcl.Graphics, MapRakuContext, MapRakuDocument,
  MapRakuLinePropertiesFrame;

type
  TMapRakuObjectLineController = class
  private
    FContext: IVectArtDesignerContext;
    FFrame: TMapRakuLinePropertiesFrame;
    FOnChanged: TNotifyEvent;
    FWidthDocumentUpdateActive: Boolean;
    FWidthGestureActive: Boolean;
    FWidthStartLayers: TArray<TVectArtLayer>;
    FWidthStartValues: TArray<Single>;
    procedure CapChanged(Sender: TObject);
    procedure StyleChanged(Sender: TObject);
    procedure WidthChanged(Sender: TObject);
    procedure WidthGestureEnd(Sender: TObject);
    procedure WidthGestureStart(Sender: TObject);
  public
    // Frameの操作イベントを線属性編集へ接続する。Frameの所有権は取得しない。
    constructor Create(AFrame: TMapRakuLinePropertiesFrame);
    // 編集対象のContextを交換する。呼び出し側はContext内サービスの寿命を保証する。
    procedure SetContext(const Value: IVectArtDesignerContext);
    // 現在選択の線属性とロック状態をFrameへ反映し、表示要否も更新する。
    procedure Refresh;
    // Documentへ属性を反映した後、他の表示同期が必要なことを呼び出し側へ通知する。
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Math, MapRakuEditCommands,
  MapRakuObjectPropertyCommands, MapRakuObjectPropertySelection;

procedure TMapRakuObjectLineController.CapChanged(Sender: TObject);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  Document: TVectArtDocument;
  HasCap: Boolean;
  Layer: TVectArtLayer;
  NewCap: TVectArtLineCap;
  OldCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewCap := FFrame.LineCap;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for Layer in MapRakuSelectedLineLayers(FContext) do
      if not Layer.Locked and TryReadMapRakuLineLayer(Layer, Color,
        Width, Style, OldCap, HasCap) and HasCap and (OldCap <> NewCap) then
      begin
        Command.Add(TMapRakuLayerLineCapCommand.Create(Document, Layer,
          OldCap, NewCap));
        if Layer is TMapRakuArcLayer then
          TMapRakuArcLayer(Layer).LineCap := NewCap
        else
          TVectArtPathLayer(Layer).LineCap := NewCap;
        Document.Changed;
      end;
  finally
    Document.EndUpdate;
  end;
  if (Command.Count > 0) and (FContext.EditHistory <> nil) then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

constructor TMapRakuObjectLineController.Create(
  AFrame: TMapRakuLinePropertiesFrame);
begin
  inherited Create;
  FFrame := AFrame;
  FFrame.OnCapChange := CapChanged;
  FFrame.OnStyleChange := StyleChanged;
  FFrame.OnWidthChange := WidthChanged;
  FFrame.OnWidthGestureEnd := WidthGestureEnd;
  FFrame.OnWidthGestureStart := WidthGestureStart;
end;

procedure TMapRakuObjectLineController.Refresh;
var
  Color: TColor;
  Enabled: Boolean;
  HasCap: Boolean;
  HasCapAny: Boolean;
  I: Integer;
  Layers: TArray<TVectArtLayer>;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  Layers := MapRakuSelectedLineLayers(FContext);
  FFrame.Visible := Length(Layers) > 0;
  if (Length(Layers) = 0) or not TryReadMapRakuLineLayer(Layers[0],
    Color, Width, Style, LineCap, HasCap) then
    Exit;
  Enabled := True;
  HasCapAny := HasCap;
  for I := 0 to High(Layers) do
  begin
    Enabled := Enabled and not Layers[I].Locked;
    if TryReadMapRakuLineLayer(Layers[I], Color, Width, Style, LineCap,
      HasCap) then
      HasCapAny := HasCapAny or HasCap;
  end;
  TryReadMapRakuLineLayer(Layers[0], Color, Width, Style, LineCap,
    HasCap);
  FFrame.StrokeWidth := Width;
  FFrame.StrokeStyle := Style;
  FFrame.LineCap := LineCap;
  FFrame.LineCapVisible := HasCapAny;
  FFrame.ControlsEnabled := Enabled;
end;

procedure TMapRakuObjectLineController.SetContext(
  const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  Refresh;
end;

procedure TMapRakuObjectLineController.StyleChanged(Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  Document: TVectArtDocument;
  HasCap: Boolean;
  Layer: TVectArtLayer;
  LineCap: TVectArtLineCap;
  NewStyle: TVectArtMifStrokeStyle;
  OldColor: TColor;
  OldStyle: TVectArtMifStrokeStyle;
  OldWidth: Single;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewStyle := FFrame.StrokeStyle;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for Layer in MapRakuSelectedLineLayers(FContext) do
      if not Layer.Locked and TryReadMapRakuLineLayer(Layer, OldColor,
        OldWidth, OldStyle, LineCap, HasCap) and (OldStyle <> NewStyle) then
      begin
        Command.Add(TMapRakuLayerStrokeCommand.Create(Document, Layer,
          OldColor, OldWidth, OldStyle, OldColor, OldWidth, NewStyle));
        if Layer is TMapRakuRectangleLineLayer then
          TMapRakuRectangleLineLayer(Layer).StrokeStyle := NewStyle
        else if Layer is TMapRakuArcLayer then
          TMapRakuArcLayer(Layer).StrokeStyle := NewStyle
        else
          TVectArtPathLayer(Layer).MifStrokeStyle := NewStyle;
        Document.Changed;
      end;
  finally
    Document.EndUpdate;
  end;
  if (Command.Count > 0) and (FContext.EditHistory <> nil) then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TMapRakuObjectLineController.WidthChanged(Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  Document: TVectArtDocument;
  HasCap: Boolean;
  Layer: TVectArtLayer;
  LineCap: TVectArtLineCap;
  NewWidth: Single;
  OldColor: TColor;
  OldStyle: TVectArtMifStrokeStyle;
  OldWidth: Single;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewWidth := FFrame.StrokeWidth;
  Command := nil;
  if not FWidthGestureActive then
    Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for Layer in MapRakuSelectedLineLayers(FContext) do
      if not Layer.Locked and TryReadMapRakuLineLayer(Layer, OldColor,
        OldWidth, OldStyle, LineCap, HasCap) and
        not SameValue(OldWidth, NewWidth) then
      begin
        if Command <> nil then
          Command.Add(TMapRakuLayerStrokeCommand.Create(Document, Layer,
            OldColor, OldWidth, OldStyle, OldColor, NewWidth, OldStyle));
        if Layer is TMapRakuRectangleLineLayer then
          TMapRakuRectangleLineLayer(Layer).StrokeWidth := NewWidth
        else if Layer is TMapRakuArcLayer then
          TMapRakuArcLayer(Layer).StrokeWidth := NewWidth
        else
          TVectArtPathLayer(Layer).StrokeWidth := NewWidth;
        Document.Changed;
      end;
  finally
    Document.EndUpdate;
  end;
  if (Command <> nil) and (Command.Count > 0) and
    (FContext.EditHistory <> nil) then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TMapRakuObjectLineController.WidthGestureEnd(Sender: TObject);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  HasCap: Boolean;
  I: Integer;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if not FWidthGestureActive then
    Exit;
  FWidthGestureActive := False;
  Command := TVectArtCompoundCommand.Create;
  for I := 0 to Min(High(FWidthStartLayers), High(FWidthStartValues)) do
    if TryReadMapRakuLineLayer(FWidthStartLayers[I], Color, Width,
      Style, LineCap, HasCap) and
      not SameValue(FWidthStartValues[I], Width) then
      Command.Add(TMapRakuLayerStrokeCommand.Create(FContext.Document,
        FWidthStartLayers[I], Color, FWidthStartValues[I], Style,
        Color, Width, Style));
  if (Command.Count > 0) and (FContext.EditHistory <> nil) then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FWidthStartLayers := nil;
  FWidthStartValues := nil;
  if FWidthDocumentUpdateActive then
  begin
    FWidthDocumentUpdateActive := False;
    FContext.Document.EndInteractiveUpdate;
  end;
end;

procedure TMapRakuObjectLineController.WidthGestureStart(
  Sender: TObject);
var
  Color: TColor;
  HasCap: Boolean;
  I: Integer;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  FWidthStartLayers := MapRakuSelectedLineLayers(FContext);
  if Length(FWidthStartLayers) = 0 then
    Exit;
  SetLength(FWidthStartValues, Length(FWidthStartLayers));
  for I := 0 to High(FWidthStartLayers) do
  begin
    if FWidthStartLayers[I].Locked then
      Exit;
    TryReadMapRakuLineLayer(FWidthStartLayers[I], Color,
      FWidthStartValues[I], Style, LineCap, HasCap);
  end;
  FWidthGestureActive := True;
  FContext.Document.BeginInteractiveUpdate;
  FWidthDocumentUpdateActive := True;
end;

end.
