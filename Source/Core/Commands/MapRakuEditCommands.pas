// Undo／Redo対象となるDocument編集コマンドを提供する。
unit MapRakuEditCommands;

interface

uses
  System.Generics.Collections, System.Types, Vcl.Graphics,
  MapRakuDocument;

type
  TVectArtLayerBooleanProperty = (vlbpVisible, vlbpLocked);

  TVectArtEditCommand = class abstract
  public
    procedure Execute; virtual; abstract;
    procedure Undo; virtual; abstract;
  end;

  TVectArtCompoundCommand = class(TVectArtEditCommand)
  private
    FCommands: TObjectList<TVectArtEditCommand>;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(Command: TVectArtEditCommand);
    procedure Execute; override;
    procedure Undo; override;
    property Count: Integer read GetCount;
  end;

  TVectArtBoundsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndices: TArray<Integer>;
    FNewBounds: TArray<TRectF>;
    FOldBounds: TArray<TRectF>;
    procedure ApplyBounds(const Values: TArray<TRectF>);
  public
    constructor Create(ADocument: TVectArtDocument;
      const LayerIndices: TArray<Integer>; const OldBounds,
      NewBounds: TArray<TRectF>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtFillColorCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewColor: TColor;
    FOldColor: TColor;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldColor, NewColor: TColor);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtRotationCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: Single;
    FOldValue: Single;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuArcAnglesCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewStartAngle: Single;
    FNewSweepAngle: Single;
    FOldStartAngle: Single;
    FOldSweepAngle: Single;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldStartAngle, OldSweepAngle, NewStartAngle, NewSweepAngle: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuRoundedRectangleRadiiCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: TMapRakuCornerRadii;
    FOldValue: TMapRakuCornerRadii;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldValue, NewValue: TMapRakuCornerRadii);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtImagePointsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewPoints: TVectArtImagePoints;
    FOldPoints: TVectArtImagePoints;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldPoints, NewPoints: TVectArtImagePoints);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtStrokeCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewColor: TColor;
    FNewStyle: TVectArtMifStrokeStyle;
    FNewWidth: Single;
    FOldColor: TColor;
    FOldStyle: TVectArtMifStrokeStyle;
    FOldWidth: Single;
    procedure Apply(Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldColor: TColor; OldWidth: Single; OldStyle: TVectArtMifStrokeStyle;
      NewColor: TColor; NewWidth: Single; NewStyle: TVectArtMifStrokeStyle);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtPathLineCapCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: TVectArtLineCap;
    FOldValue: TVectArtLineCap;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: TVectArtLineCap);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuPathWidthPointsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: TArray<TMapRakuStrokeWidthPoint>;
    FOldValue: TArray<TMapRakuStrokeWidthPoint>;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldValue, NewValue: TArray<TMapRakuStrokeWidthPoint>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLayerBooleanCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: Boolean;
    FOldValue: Boolean;
    FPropertyKind: TVectArtLayerBooleanProperty;
    procedure ApplyValue(Value: Boolean);
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      PropertyKind: TVectArtLayerBooleanProperty; OldValue,
      NewValue: Boolean);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLayerOpacityCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: Single;
    FOldValue: Single;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  System.Math;

procedure TVectArtCompoundCommand.Add(Command: TVectArtEditCommand);
begin
  if Command <> nil then FCommands.Add(Command);
end;

constructor TVectArtCompoundCommand.Create;
begin
  inherited Create;
  FCommands := TObjectList<TVectArtEditCommand>.Create(True);
end;

destructor TVectArtCompoundCommand.Destroy;
begin
  FCommands.Free;
  inherited Destroy;
end;

procedure TVectArtCompoundCommand.Execute;
var
  Command: TVectArtEditCommand;
begin
  for Command in FCommands do Command.Execute;
end;

function TVectArtCompoundCommand.GetCount: Integer;
begin
  Result := FCommands.Count;
end;

procedure TVectArtCompoundCommand.Undo;
var
  I: Integer;
begin
  for I := FCommands.Count - 1 downto 0 do FCommands[I].Undo;
end;

procedure TVectArtBoundsCommand.ApplyBounds(const Values: TArray<TRectF>);
var
  I: Integer;
begin
  if FDocument = nil then Exit;
  for I := 0 to Min(High(FLayerIndices), High(Values)) do
    if FDocument[FLayerIndices[I]] is TMapRakuRectangleLineLayer then
      FDocument.SetRectangleLineBounds(FLayerIndices[I], Values[I])
    else if FDocument[FLayerIndices[I]] is TMapRakuArcLayer then
      FDocument.SetArcBounds(FLayerIndices[I], Values[I])
    else
      FDocument.SetRectangleBounds(FLayerIndices[I], Values[I]);
end;

constructor TVectArtBoundsCommand.Create(ADocument: TVectArtDocument;
  const LayerIndices: TArray<Integer>; const OldBounds,
  NewBounds: TArray<TRectF>);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndices := Copy(LayerIndices);
  FOldBounds := Copy(OldBounds);
  FNewBounds := Copy(NewBounds);
end;

procedure TVectArtBoundsCommand.Execute;
begin
  ApplyBounds(FNewBounds);
end;

procedure TVectArtBoundsCommand.Undo;
begin
  ApplyBounds(FOldBounds);
end;

constructor TVectArtFillColorCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldColor, NewColor: TColor);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldColor := OldColor;
  FNewColor := NewColor;
end;

procedure TVectArtFillColorCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetRectangleFillColor(FLayerIndex, FNewColor);
end;

procedure TVectArtFillColorCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetRectangleFillColor(FLayerIndex, FOldColor);
end;

constructor TVectArtRotationCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtRotationCommand.Execute;
begin
  if FDocument <> nil then
    if FDocument[FLayerIndex] is TMapRakuRectangleLineLayer then
      FDocument.SetRectangleLineRotation(FLayerIndex, FNewValue)
    else if FDocument[FLayerIndex] is TMapRakuArcLayer then
      FDocument.SetArcRotation(FLayerIndex, FNewValue)
    else
      FDocument.SetRectangleRotation(FLayerIndex, FNewValue);
end;

procedure TVectArtRotationCommand.Undo;
begin
  if FDocument <> nil then
    if FDocument[FLayerIndex] is TMapRakuRectangleLineLayer then
      FDocument.SetRectangleLineRotation(FLayerIndex, FOldValue)
    else if FDocument[FLayerIndex] is TMapRakuArcLayer then
      FDocument.SetArcRotation(FLayerIndex, FOldValue)
    else
      FDocument.SetRectangleRotation(FLayerIndex, FOldValue);
end;

constructor TMapRakuArcAnglesCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer; OldStartAngle,
  OldSweepAngle, NewStartAngle, NewSweepAngle: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldStartAngle := OldStartAngle;
  FOldSweepAngle := OldSweepAngle;
  FNewStartAngle := NewStartAngle;
  FNewSweepAngle := NewSweepAngle;
end;

procedure TMapRakuArcAnglesCommand.Execute;
begin
  if (FDocument <> nil) and (FLayerIndex > 0) and
    (FLayerIndex < FDocument.LayerCount) and
    (FDocument[FLayerIndex] is TMapRakuEllipseArcShapeLayer) then
    FDocument.SetEllipseArcShapeAngles(FLayerIndex, FNewStartAngle,
      FNewSweepAngle)
  else if FDocument <> nil then
    FDocument.SetArcAngles(FLayerIndex, FNewStartAngle, FNewSweepAngle);
end;

procedure TMapRakuArcAnglesCommand.Undo;
begin
  if (FDocument <> nil) and (FLayerIndex > 0) and
    (FLayerIndex < FDocument.LayerCount) and
    (FDocument[FLayerIndex] is TMapRakuEllipseArcShapeLayer) then
    FDocument.SetEllipseArcShapeAngles(FLayerIndex, FOldStartAngle,
      FOldSweepAngle)
  else if FDocument <> nil then
    FDocument.SetArcAngles(FLayerIndex, FOldStartAngle, FOldSweepAngle);
end;

constructor TMapRakuRoundedRectangleRadiiCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer;
  const OldValue, NewValue: TMapRakuCornerRadii);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TMapRakuRoundedRectangleRadiiCommand.Execute;
begin
  if (FDocument <> nil) and (FLayerIndex > 0) and
    (FLayerIndex < FDocument.LayerCount) and
    (FDocument[FLayerIndex] is TMapRakuRoundedRectangleLineLayer) then
    FDocument.SetRoundedRectangleLineCornerRadii(FLayerIndex, FNewValue)
  else if FDocument <> nil then
    FDocument.SetRoundedRectangleCornerRadii(FLayerIndex, FNewValue);
end;

procedure TMapRakuRoundedRectangleRadiiCommand.Undo;
begin
  if (FDocument <> nil) and (FLayerIndex > 0) and
    (FLayerIndex < FDocument.LayerCount) and
    (FDocument[FLayerIndex] is TMapRakuRoundedRectangleLineLayer) then
    FDocument.SetRoundedRectangleLineCornerRadii(FLayerIndex, FOldValue)
  else if FDocument <> nil then
    FDocument.SetRoundedRectangleCornerRadii(FLayerIndex, FOldValue);
end;

constructor TVectArtImagePointsCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; const OldPoints, NewPoints: TVectArtImagePoints);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldPoints := OldPoints;
  FNewPoints := NewPoints;
end;

procedure TVectArtImagePointsCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetImagePoints(FLayerIndex, FNewPoints);
end;

procedure TVectArtImagePointsCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetImagePoints(FLayerIndex, FOldPoints);
end;

procedure TVectArtStrokeCommand.Apply(Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle);
begin
  if FDocument = nil then
    Exit;
  if FDocument[FLayerIndex] is TMapRakuRectangleLineLayer then
    FDocument.SetRectangleLineStroke(FLayerIndex, Color, Width, Style)
  else if FDocument[FLayerIndex] is TMapRakuArcLayer then
    FDocument.SetArcStroke(FLayerIndex, Color, Width, Style)
  else if FDocument[FLayerIndex] is TVectArtPathLayer then
    FDocument.SetPathStroke(FLayerIndex, Color, Width, Style);
end;

constructor TVectArtStrokeCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldColor: TColor; OldWidth: Single;
  OldStyle: TVectArtMifStrokeStyle; NewColor: TColor; NewWidth: Single;
  NewStyle: TVectArtMifStrokeStyle);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldColor := OldColor;
  FOldWidth := OldWidth;
  FOldStyle := OldStyle;
  FNewColor := NewColor;
  FNewWidth := NewWidth;
  FNewStyle := NewStyle;
end;

procedure TVectArtStrokeCommand.Execute;
begin
  Apply(FNewColor, FNewWidth, FNewStyle);
end;

procedure TVectArtStrokeCommand.Undo;
begin
  Apply(FOldColor, FOldWidth, FOldStyle);
end;

constructor TVectArtPathLineCapCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: TVectArtLineCap);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtPathLineCapCommand.Execute;
begin
  if FDocument <> nil then
    if FDocument[FLayerIndex] is TMapRakuArcLayer then
      FDocument.SetArcLineCap(FLayerIndex, FNewValue)
    else
      FDocument.SetPathLineCap(FLayerIndex, FNewValue);
end;

procedure TVectArtPathLineCapCommand.Undo;
begin
  if FDocument <> nil then
    if FDocument[FLayerIndex] is TMapRakuArcLayer then
      FDocument.SetArcLineCap(FLayerIndex, FOldValue)
    else
      FDocument.SetPathLineCap(FLayerIndex, FOldValue);
end;

constructor TMapRakuPathWidthPointsCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer;
  const OldValue, NewValue: TArray<TMapRakuStrokeWidthPoint>);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := Copy(OldValue);
  FNewValue := Copy(NewValue);
end;

procedure TMapRakuPathWidthPointsCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetPathWidthPoints(FLayerIndex, FNewValue);
end;

procedure TMapRakuPathWidthPointsCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetPathWidthPoints(FLayerIndex, FOldValue);
end;

procedure TVectArtLayerBooleanCommand.ApplyValue(Value: Boolean);
begin
  if FDocument = nil then Exit;
  case FPropertyKind of
    vlbpVisible: FDocument.SetLayerVisible(FLayerIndex, Value);
    vlbpLocked: FDocument.SetLayerLocked(FLayerIndex, Value);
  end;
end;

constructor TVectArtLayerBooleanCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; PropertyKind: TVectArtLayerBooleanProperty; OldValue,
  NewValue: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FPropertyKind := PropertyKind;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtLayerBooleanCommand.Execute;
begin
  ApplyValue(FNewValue);
end;

procedure TVectArtLayerBooleanCommand.Undo;
begin
  ApplyValue(FOldValue);
end;

constructor TVectArtLayerOpacityCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtLayerOpacityCommand.Execute;
begin
  if FDocument <> nil then FDocument.SetLayerOpacity(FLayerIndex, FNewValue);
end;

procedure TVectArtLayerOpacityCommand.Undo;
begin
  if FDocument <> nil then FDocument.SetLayerOpacity(FLayerIndex, FOldValue);
end;

end.
