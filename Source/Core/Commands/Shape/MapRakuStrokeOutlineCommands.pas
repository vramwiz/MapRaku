// 開いた線Pathを同じ位置の閉じたShapeへ置換し、Undoで元のPathへ戻す。
unit MapRakuStrokeOutlineCommands;

interface

uses
  MapRakuDocument, MapRakuEditHistory, MapRakuEditorState;

function ExecuteMapRakuStrokeOutline(Document: TVectArtDocument;
  EditorState: TVectArtEditorState; EditHistory: TVectArtEditHistory;
  PathLayer: TVectArtPathLayer): Boolean;

implementation

uses
  System.SysUtils, Vcl.Graphics, MapRakuEditCommands,
  MapRakuStrokeOutlineGeometry;

type
  TMapRakuStrokeOutlineCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FIndex: Integer;
    FParent: TMapRakuGroupLayer;
    FOriginal: TVectArtPathLayer;
    FOriginalInDocument: Boolean;
    FOutlined: TMapRakuShapeLayer;
    FOutlinedInDocument: Boolean;
    procedure SelectCurrent(Index: Integer);
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState; AParent: TMapRakuGroupLayer;
      Index: Integer;
      Original: TVectArtPathLayer; Outlined: TMapRakuShapeLayer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

constructor TMapRakuStrokeOutlineCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  AParent: TMapRakuGroupLayer; Index: Integer;
  Original: TVectArtPathLayer;
  Outlined: TMapRakuShapeLayer);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FParent := AParent;
  FIndex := Index;
  FOriginal := Original;
  FOutlined := Outlined;
  FOriginalInDocument := True;
end;

destructor TMapRakuStrokeOutlineCommand.Destroy;
begin
  if not FOriginalInDocument then
    FOriginal.Free;
  if not FOutlinedInDocument then
    FOutlined.Free;
  inherited Destroy;
end;

procedure TMapRakuStrokeOutlineCommand.Execute;
begin
  if (FDocument = nil) or not FOriginalInDocument then
    Exit;
  FDocument.BeginUpdate;
  try
    if FParent <> nil then
      FOriginal := TVectArtPathLayer(FParent.ExtractChild(FIndex))
    else
      FOriginal := TVectArtPathLayer(FDocument.ExtractLayer(FIndex));
    FOriginalInDocument := False;
    if FParent <> nil then
      FParent.InsertChild(FIndex, FOutlined)
    else
      FDocument.InsertLayer(FIndex, FOutlined);
    FOutlinedInDocument := True;
    SelectCurrent(FIndex);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuStrokeOutlineCommand.SelectCurrent(Index: Integer);
begin
  if FParent <> nil then
  begin
    FDocument.SetSelectedLayers([]);
    FEditorState.SetOpenGroupChildren([FParent[Index]]);
  end
  else
    FDocument.SetSelectedLayers([Index]);
  if FEditorState <> nil then
    FEditorState.ValidateSelectedFilter(FDocument);
end;

procedure TMapRakuStrokeOutlineCommand.Undo;
begin
  if (FDocument = nil) or not FOutlinedInDocument then
    Exit;
  FDocument.BeginUpdate;
  try
    if FParent <> nil then
      FOutlined := TMapRakuShapeLayer(FParent.ExtractChild(FIndex))
    else
      FOutlined := TMapRakuShapeLayer(FDocument.ExtractLayer(FIndex));
    FOutlinedInDocument := False;
    if FParent <> nil then
      FParent.InsertChild(FIndex, FOriginal)
    else
      FDocument.InsertLayer(FIndex, FOriginal);
    FOriginalInDocument := True;
    SelectCurrent(FIndex);
  finally
    FDocument.EndUpdate;
  end;
end;

function ExecuteMapRakuStrokeOutline(Document: TVectArtDocument;
  EditorState: TVectArtEditorState; EditHistory: TVectArtEditHistory;
  PathLayer: TVectArtPathLayer): Boolean;
var
  Command: TMapRakuStrokeOutlineCommand;
  Contours: TArray<TMapRakuContour>;
  I: Integer;
  Index: Integer;
  Parent: TMapRakuGroupLayer;
  Shape: TMapRakuShapeLayer;
begin
  Result := False;
  if (Document = nil) or (PathLayer = nil) or PathLayer.Locked or
    PathLayer.Closed then
    Exit;
  Index := -1;
  Parent := nil;
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) and
    EditorState.IsOpenGroupChildSelected(PathLayer) then
  begin
    Parent := EditorState.OpenGroup;
    for I := 0 to Parent.ChildCount - 1 do
      if Parent[I] = PathLayer then
      begin
        Index := I;
        Break;
      end;
  end
  else
    for I := 1 to Document.LayerCount - 1 do
      if Document[I] = PathLayer then
      begin
        Index := I;
        Break;
      end;
  if Index < 0 then
    Exit;
  Contours := BuildMapRakuStrokeOutlineContours(PathLayer);
  if Length(Contours) = 0 then
    Exit;
  Shape := TMapRakuShapeLayer.Create(PathLayer.Name + ' outline',
    Contours);
  Shape.FillColor := PathLayer.StrokeColor;
  Shape.FillRule := slfrEvenOdd;
  Shape.Locked := PathLayer.Locked;
  Shape.Opacity := PathLayer.Opacity;
  Shape.PaintStyle := PathLayer.PaintStyle;
  Shape.StrokeWidth := 0;
  Shape.Transform := PathLayer.Transform;
  Shape.Visible := PathLayer.Visible;
  for I := 0 to PathLayer.FilterCount - 1 do
    Shape.AddFilter(PathLayer.Filters[I].Clone);
  Command := TMapRakuStrokeOutlineCommand.Create(Document,
    EditorState, Parent, Index, PathLayer, Shape);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
  Result := True;
end;

end.
