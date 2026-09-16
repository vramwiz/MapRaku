// 複数選択を外接範囲で整列し、両端を固定した均等間隔配置を1件のUndo／Redoとして扱う。
unit MapRakuLayerArrangementOperations;

interface

uses
  MapRakuDocument, MapRakuEditHistory, MapRakuEditorState;

type
  TMapRakuArrangement = (slaAlignLeft, slaAlignHorizontalCenter,
    slaAlignRight, slaAlignTop, slaAlignVerticalCenter, slaAlignBottom,
    slaDistributeHorizontal, slaDistributeVertical);

// 現在の同階層選択が、指定した整列または均等配置を実行できる場合にTrueを返す。
function CanArrangeMapRakuSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Arrangement: TMapRakuArrangement): Boolean;
// 選択へ指定配置を適用し、移動全体を1件の履歴へ追加する。
procedure ArrangeMapRakuSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Arrangement: TMapRakuArrangement);

implementation

uses
  System.Math, System.Types, MapRakuEditCommands,
  MapRakuLayerGeometry;

type
  TMapRakuArrangementCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FDX: TArray<Single>;
    FDY: TArray<Single>;
    FLayers: TArray<TVectArtLayer>;
    procedure Apply(Factor: Single);
  public
    constructor Create(ADocument: TVectArtDocument;
      const Layers: TArray<TVectArtLayer>; const DX, DY: TArray<Single>);
    procedure Execute; override;
    procedure Undo; override;
  end;

function SelectedLayers(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): TArray<TVectArtLayer>;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) then
    Exit(EditorState.GetOpenGroupChildren);
  Result := nil;
  if Document = nil then
    Exit;
  Indices := Document.GetSelectedLayerIndices;
  SetLength(Result, Length(Indices));
  for I := 0 to High(Indices) do
    Result[I] := Document[Indices[I]];
end;

function IsDistribution(Arrangement: TMapRakuArrangement): Boolean;
begin
  Result := Arrangement in [slaDistributeHorizontal,
    slaDistributeVertical];
end;

function TryLayerBounds(const Layers: TArray<TVectArtLayer>;
  out Bounds: TArray<TRectF>; out SelectionBounds: TRectF): Boolean;
var
  I: Integer;
begin
  Result := Length(Layers) > 0;
  if not Result then
    Exit;
  SetLength(Bounds, Length(Layers));
  for I := 0 to High(Layers) do
  begin
    if (Layers[I] = nil) or Layers[I].Locked or
      (Layers[I] is TVectArtCanvasLayer) or
      not TryGetMapRakuLayerBounds(Layers[I], Bounds[I]) then
      Exit(False);
    if I = 0 then
      SelectionBounds := Bounds[I]
    else
      SelectionBounds := TRectF.Union(SelectionBounds, Bounds[I]);
  end;
end;

function CanArrangeMapRakuSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Arrangement: TMapRakuArrangement): Boolean;
var
  Bounds: TArray<TRectF>;
  Layers: TArray<TVectArtLayer>;
  SelectionBounds: TRectF;
begin
  Layers := SelectedLayers(Document, EditorState);
  Result := (Length(Layers) >= 2) and
    (not IsDistribution(Arrangement) or (Length(Layers) >= 3)) and
    TryLayerBounds(Layers, Bounds, SelectionBounds);
end;

function CenterCoordinate(const Bounds: TRectF;
  Horizontal: Boolean): Single;
begin
  if Horizontal then
    Result := Bounds.CenterPoint.X
  else
    Result := Bounds.CenterPoint.Y;
end;

procedure SortByCenter(var Order: TArray<Integer>;
  const Bounds: TArray<TRectF>; Horizontal: Boolean);
var
  I: Integer;
  J: Integer;
  Value: Integer;
begin
  for I := 1 to High(Order) do
  begin
    Value := Order[I];
    J := I - 1;
    while (J >= 0) and (CenterCoordinate(Bounds[Order[J]], Horizontal) >
      CenterCoordinate(Bounds[Value], Horizontal)) do
    begin
      Order[J + 1] := Order[J];
      Dec(J);
    end;
    Order[J + 1] := Value;
  end;
end;

procedure BuildDistributionDeltas(const Bounds: TArray<TRectF>;
  Horizontal: Boolean; var DX, DY: TArray<Single>);
var
  AvailableSpan: Single;
  Cursor: Single;
  Gap: Single;
  I: Integer;
  Index: Integer;
  Order: TArray<Integer>;
  TotalSize: Single;
begin
  SetLength(Order, Length(Bounds));
  for I := 0 to High(Order) do
    Order[I] := I;
  SortByCenter(Order, Bounds, Horizontal);
  TotalSize := 0;
  for I := 0 to High(Bounds) do
    if Horizontal then
      TotalSize := TotalSize + Bounds[I].Width
    else
      TotalSize := TotalSize + Bounds[I].Height;
  if Horizontal then
    AvailableSpan := Bounds[Order[High(Order)]].Right -
      Bounds[Order[0]].Left
  else
    AvailableSpan := Bounds[Order[High(Order)]].Bottom -
      Bounds[Order[0]].Top;
  Gap := (AvailableSpan - TotalSize) / (Length(Order) - 1);
  if Horizontal then
    Cursor := Bounds[Order[0]].Right + Gap
  else
    Cursor := Bounds[Order[0]].Bottom + Gap;
  for I := 1 to High(Order) - 1 do
  begin
    Index := Order[I];
    if Horizontal then
    begin
      DX[Index] := Cursor - Bounds[Index].Left;
      Cursor := Cursor + Bounds[Index].Width + Gap;
    end
    else
    begin
      DY[Index] := Cursor - Bounds[Index].Top;
      Cursor := Cursor + Bounds[Index].Height + Gap;
    end;
  end;
end;

procedure BuildArrangementDeltas(const Bounds: TArray<TRectF>;
  const SelectionBounds: TRectF; Arrangement: TMapRakuArrangement;
  out DX, DY: TArray<Single>);
var
  I: Integer;
begin
  SetLength(DX, Length(Bounds));
  SetLength(DY, Length(Bounds));
  if Arrangement = slaDistributeHorizontal then
  begin
    BuildDistributionDeltas(Bounds, True, DX, DY);
    Exit;
  end;
  if Arrangement = slaDistributeVertical then
  begin
    BuildDistributionDeltas(Bounds, False, DX, DY);
    Exit;
  end;
  for I := 0 to High(Bounds) do
    case Arrangement of
      slaAlignLeft:
        DX[I] := SelectionBounds.Left - Bounds[I].Left;
      slaAlignHorizontalCenter:
        DX[I] := SelectionBounds.CenterPoint.X - Bounds[I].CenterPoint.X;
      slaAlignRight:
        DX[I] := SelectionBounds.Right - Bounds[I].Right;
      slaAlignTop:
        DY[I] := SelectionBounds.Top - Bounds[I].Top;
      slaAlignVerticalCenter:
        DY[I] := SelectionBounds.CenterPoint.Y - Bounds[I].CenterPoint.Y;
      slaAlignBottom:
        DY[I] := SelectionBounds.Bottom - Bounds[I].Bottom;
    end;
end;

function HasMovement(const DX, DY: TArray<Single>): Boolean;
var
  I: Integer;
begin
  for I := 0 to Min(High(DX), High(DY)) do
    if not SameValue(DX[I], 0, 0.0001) or
      not SameValue(DY[I], 0, 0.0001) then
      Exit(True);
  Result := False;
end;

constructor TMapRakuArrangementCommand.Create(
  ADocument: TVectArtDocument; const Layers: TArray<TVectArtLayer>;
  const DX, DY: TArray<Single>);
begin
  inherited Create;
  FDocument := ADocument;
  FLayers := Copy(Layers);
  FDX := Copy(DX);
  FDY := Copy(DY);
end;

procedure TMapRakuArrangementCommand.Apply(Factor: Single);
var
  I: Integer;
begin
  if FDocument = nil then
    Exit;
  FDocument.BeginUpdate;
  try
    for I := 0 to Min(High(FLayers), Min(High(FDX), High(FDY))) do
      TranslateMapRakuLayer(FLayers[I], FDX[I] * Factor,
        FDY[I] * Factor);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuArrangementCommand.Execute;
begin
  Apply(1);
end;

procedure TMapRakuArrangementCommand.Undo;
begin
  Apply(-1);
end;

procedure ArrangeMapRakuSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Arrangement: TMapRakuArrangement);
var
  Bounds: TArray<TRectF>;
  Command: TMapRakuArrangementCommand;
  DX: TArray<Single>;
  DY: TArray<Single>;
  Layers: TArray<TVectArtLayer>;
  SelectionBounds: TRectF;
begin
  if not CanArrangeMapRakuSelection(Document, EditorState,
    Arrangement) then
    Exit;
  Layers := SelectedLayers(Document, EditorState);
  if not TryLayerBounds(Layers, Bounds, SelectionBounds) then
    Exit;
  BuildArrangementDeltas(Bounds, SelectionBounds, Arrangement, DX, DY);
  if not HasMovement(DX, DY) then
    Exit;
  Command := TMapRakuArrangementCommand.Create(Document, Layers,
    DX, DY);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

end.
