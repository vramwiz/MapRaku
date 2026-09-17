// レイヤーのグループ化と解除を、所有権を保ったままUndo／Redo可能にする。
unit MapRakuGroupCommands;

interface

uses
  MapRakuDocument, MapRakuEditHistory, MapRakuEditorState;

// トップレベルの現在選択をグループ化できるかを返す。
function CanGroupSelectedLayers(Document: TVectArtDocument): Boolean;
// トップレベルの単一選択を解除できるグループかを返す。
function CanUngroupSelectedLayer(Document: TVectArtDocument): Boolean;
// 現在選択を1グループへ置き換え、操作を履歴へ追加する。
procedure GroupSelectedLayers(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
// 選択グループを子へ展開し、操作を履歴へ追加する。
procedure UngroupSelectedLayer(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
// 開いているグループの子選択へ編集操作を適用できるかを返す。
function CanEditOpenGroupChild(EditorState: TVectArtEditorState): Boolean;
// 選択中の直下子をグループから取り外し、操作を履歴へ追加する。
procedure DeleteOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
// 選択中の直下子を再帰複製し、同じ親へ挿入する。
procedure DuplicateOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
// 選択子を指定方向へ1段移動できるかを返す。
function CanMoveOpenGroupChild(EditorState: TVectArtEditorState;
  Delta: Integer): Boolean;
// 選択子を親グループ内で指定段数移動する。範囲外の段数は先頭または末尾へ制限する。
procedure MoveOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Delta: Integer);
// トップレベル選択がグループだけで構成され複製可能かを返す。
function CanDuplicateSelectedGroups(Document: TVectArtDocument): Boolean;
// 選択グループを入れ子構造ごと再帰複製する。
procedure DuplicateSelectedGroups(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
// レイヤーとそのフィルターを、所有権を共有せず再帰複製する。
function CloneMapRakuLayer(Source: TVectArtLayer;
  const NewName: string): TVectArtLayer;
// 開いているグループの子選択を内部グループ化できるかを返す。
function CanGroupOpenGroupChildren(EditorState: TVectArtEditorState): Boolean;
// 選択中の直下子が解除可能な内部グループかを返す。
function CanUngroupOpenGroupChild(EditorState: TVectArtEditorState): Boolean;
// 選択中の直下子を新しい内部グループへまとめる。
procedure GroupOpenGroupChildren(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
// 選択中の内部グループを解除し、子を現在の親へ展開する。
procedure UngroupOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
// トップレベルと開いたグループを区別せず、現在選択をグループ化できるか返す。
function CanGroupCurrentSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): Boolean;
// トップレベルと開いたグループを区別せず、現在選択をグループ化する。
procedure GroupCurrentSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
// 現在選択がグループ化解除の対象か返す。
function CanUngroupCurrentSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): Boolean;
// 現在選択のグループ化を解除する。
procedure UngroupCurrentSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);

implementation

uses
  System.Classes, System.Generics.Collections, System.Math, System.SysUtils,
  System.Types,
  MapRakuMapCommands, MapRakuEditCommands, MapRakuGroupChildCommands,
  MapRakuLayerGeometry, MapRakuPathOperations,
  MapRakuShapeOperations;

type
  TMapRakuGroupCommand = class(TVectArtEditCommand)
  private
    FBeforeSelection: TArray<Integer>;
    FDocument: TVectArtDocument;
    FGroup: TMapRakuGroupLayer;
    FGroupInDocument: Boolean;
    FGroupIndex: Integer;
    FOriginalIndices: TArray<Integer>;
  public
    constructor Create(ADocument: TVectArtDocument;
      const OriginalIndices: TArray<Integer>; const GroupName: string);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuUngroupCommand = class(TVectArtEditCommand)
  private
    FChildCount: Integer;
    FDocument: TVectArtDocument;
    FGroup: TMapRakuGroupLayer;
    FGroupInDocument: Boolean;
    FGroupIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; GroupIndex: Integer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  TMapRakuDuplicateGroupsCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FDocument: TVectArtDocument;
    FDuplicates: TArray<TVectArtLayer>;
    FDuplicatesInDocument: Boolean;
    FIndices: TArray<Integer>;
  public
    constructor Create(ADocument: TVectArtDocument;
      const BeforeSelection, Indices: TArray<Integer>;
      const Duplicates: TArray<TVectArtLayer>);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

function OpenGroupChildIndex(EditorState: TVectArtEditorState): Integer;
var
  I: Integer;
begin
  Result := -1;
  if (EditorState = nil) or (EditorState.OpenGroup = nil) or
    (EditorState.OpenGroupChild = nil) then
    Exit;
  for I := 0 to EditorState.OpenGroup.ChildCount - 1 do
    if EditorState.OpenGroup[I] = EditorState.OpenGroupChild then
      Exit(I);
end;

function CanEditOpenGroupChild(EditorState: TVectArtEditorState): Boolean;
var
  Layer: TVectArtLayer;
  Layers: TArray<TVectArtLayer>;
begin
  Result := (EditorState <> nil) and
    (EditorState.OpenGroupChildCount > 0) and
    (OpenGroupChildIndex(EditorState) >= 0) and
    (EditorState.OpenGroup <> nil);
  if not Result then
    Exit;
  Layers := EditorState.GetOpenGroupChildren;
  for Layer in Layers do
    if Layer.Locked then
      Exit(False);
end;

function OpenGroupSelectedIndices(
  EditorState: TVectArtEditorState): TArray<Integer>;
var
  I: Integer;
  Indices: TList<Integer>;
begin
  Indices := TList<Integer>.Create;
  try
    if (EditorState <> nil) and (EditorState.OpenGroup <> nil) then
      for I := 0 to EditorState.OpenGroup.ChildCount - 1 do
        if EditorState.IsOpenGroupChildSelected(
          EditorState.OpenGroup[I]) then
          Indices.Add(I);
    Result := Indices.ToArray;
  finally
    Indices.Free;
  end;
end;

function CanGroupOpenGroupChildren(
  EditorState: TVectArtEditorState): Boolean;
begin
  Result := CanEditOpenGroupChild(EditorState) and
    (EditorState.OpenGroupChildCount >= 2) and
    (Length(OpenGroupSelectedIndices(EditorState)) =
      EditorState.OpenGroupChildCount);
end;

function CanUngroupOpenGroupChild(
  EditorState: TVectArtEditorState): Boolean;
begin
  Result := CanEditOpenGroupChild(EditorState) and
    (EditorState.OpenGroupChildCount = 1) and
    (EditorState.OpenGroupChild is TMapRakuGroupLayer);
end;

function NextChildGroupName(Parent: TMapRakuGroupLayer): string;
var
  Count: Integer;
  I: Integer;
begin
  Count := 0;
  for I := 0 to Parent.ChildCount - 1 do
    if Parent[I] is TMapRakuGroupLayer then
      Inc(Count);
  Result := Format('グループ %d', [Count + 1]);
end;

procedure GroupOpenGroupChildren(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
var
  Command: TMapRakuGroupChildrenCommand;
begin
  if (Document = nil) or not CanGroupOpenGroupChildren(EditorState) then
    Exit;
  Command := TMapRakuGroupChildrenCommand.Create(Document, EditorState,
    EditorState.OpenGroup, OpenGroupSelectedIndices(EditorState),
    NextChildGroupName(EditorState.OpenGroup));
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure UngroupOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
var
  Command: TMapRakuUngroupChildCommand;
begin
  if (Document = nil) or not CanUngroupOpenGroupChild(EditorState) then
    Exit;
  Command := TMapRakuUngroupChildCommand.Create(Document, EditorState,
    EditorState.OpenGroup, OpenGroupChildIndex(EditorState));
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

function CanGroupCurrentSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): Boolean;
begin
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) then
    Result := CanGroupOpenGroupChildren(EditorState)
  else
    Result := CanGroupSelectedLayers(Document);
end;

procedure GroupCurrentSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
begin
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) then
    GroupOpenGroupChildren(Document, EditHistory, EditorState)
  else
    GroupSelectedLayers(Document, EditHistory);
end;

function CanUngroupCurrentSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): Boolean;
begin
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) then
    Result := CanUngroupOpenGroupChild(EditorState)
  else
    Result := CanUngroupSelectedLayer(Document);
end;

procedure UngroupCurrentSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
begin
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) then
    UngroupOpenGroupChild(Document, EditHistory, EditorState)
  else
    UngroupSelectedLayer(Document, EditHistory);
end;

function CanMoveOpenGroupChild(EditorState: TVectArtEditorState;
  Delta: Integer): Boolean;
var
  Index: Integer;
begin
  Result := CanEditOpenGroupChild(EditorState);
  if not Result then
    Exit;
  for Index in OpenGroupSelectedIndices(EditorState) do
  begin
    if (Delta > 0) and
      (Index < EditorState.OpenGroup.ChildCount - 1) and
      not EditorState.IsOpenGroupChildSelected(
        EditorState.OpenGroup[Index + 1]) then
      Exit(True);
    if (Delta < 0) and (Index > 0) and
      not EditorState.IsOpenGroupChildSelected(
        EditorState.OpenGroup[Index - 1]) then
      Exit(True);
  end;
  Result := False;
end;

procedure CopyCommonLayerValues(Source, Target: TVectArtLayer);
var
  I: Integer;
begin
  Target.Locked := False;
  Target.FlipHorizontal := Source.FlipHorizontal;
  Target.Transform := Source.Transform;
  Target.FlipVertical := Source.FlipVertical;
  Target.Opacity := Source.Opacity;
  Target.PaintStyle := Source.PaintStyle;
  Target.Visible := Source.Visible;
  for I := 0 to Source.FilterCount - 1 do
    Target.AddFilter(Source.Filters[I].Clone);
end;

function CloneMapRakuLayer(Source: TVectArtLayer;
  const NewName: string): TVectArtLayer;
var
  Arc: TMapRakuArcLayer;
  ArcShape: TMapRakuEllipseArcShapeLayer;
  ChildClone: TVectArtLayer;
  Group: TMapRakuGroupLayer;
  I: Integer;
  Image: TVectArtImageLayer;
  Path: TVectArtPathLayer;
  Rectangle: TVectArtRectangleLayer;
  RectangleLine: TMapRakuRectangleLineLayer;
  Rounded: TMapRakuRoundedRectangleLayer;
  RoundedLine: TMapRakuRoundedRectangleLineLayer;
  Shape: TMapRakuShapeLayer;
  TextLayer: TMapRakuTextLayer;
  TextPath: TMapRakuTextPathLayer;
begin
  if Source is TMapRakuGroupLayer then
  begin
    Group := TMapRakuGroupLayer.Create(NewName);
    for I := 0 to TMapRakuGroupLayer(Source).ChildCount - 1 do
    begin
      ChildClone := CloneMapRakuLayer(
        TMapRakuGroupLayer(Source)[I],
        TMapRakuGroupLayer(Source)[I].Name);
      ChildClone.Locked := TMapRakuGroupLayer(Source)[I].Locked;
      Group.AddChild(ChildClone);
    end;
    Group.MapSymbol := TMapRakuGroupLayer(Source).MapSymbol;
    Group.MapSurface := TMapRakuGroupLayer(Source).MapSurface;
    Result := Group;
  end
  else if Source is TMapRakuRoundedRectangleLineLayer then
  begin
    RoundedLine := TMapRakuRoundedRectangleLineLayer(Source);
    Result := TMapRakuRoundedRectangleLineLayer.Create(NewName,
      RoundedLine.Bounds, RoundedLine.CornerRadii);
    TMapRakuRoundedRectangleLineLayer(Result).RotationDegrees :=
      RoundedLine.RotationDegrees;
    TMapRakuRoundedRectangleLineLayer(Result).StrokeColor :=
      RoundedLine.StrokeColor;
    TMapRakuRoundedRectangleLineLayer(Result).StrokeStyle :=
      RoundedLine.StrokeStyle;
    TMapRakuRoundedRectangleLineLayer(Result).StrokeWidth :=
      RoundedLine.StrokeWidth;
  end
  else if Source is TMapRakuEllipseLineLayer then
  begin
    RectangleLine := TMapRakuRectangleLineLayer(Source);
    Result := TMapRakuEllipseLineLayer.Create(NewName,
      RectangleLine.Bounds);
    TMapRakuEllipseLineLayer(Result).RotationDegrees :=
      RectangleLine.RotationDegrees;
    TMapRakuEllipseLineLayer(Result).StrokeColor :=
      RectangleLine.StrokeColor;
    TMapRakuEllipseLineLayer(Result).StrokeStyle :=
      RectangleLine.StrokeStyle;
    TMapRakuEllipseLineLayer(Result).StrokeWidth :=
      RectangleLine.StrokeWidth;
  end
  else if Source is TMapRakuRectangleLineLayer then
  begin
    RectangleLine := TMapRakuRectangleLineLayer(Source);
    Result := TMapRakuRectangleLineLayer.Create(NewName,
      RectangleLine.Bounds);
    TMapRakuRectangleLineLayer(Result).RotationDegrees :=
      RectangleLine.RotationDegrees;
    TMapRakuRectangleLineLayer(Result).StrokeColor :=
      RectangleLine.StrokeColor;
    TMapRakuRectangleLineLayer(Result).StrokeStyle :=
      RectangleLine.StrokeStyle;
    TMapRakuRectangleLineLayer(Result).StrokeWidth :=
      RectangleLine.StrokeWidth;
  end
  else if Source is TMapRakuArcLayer then
  begin
    Arc := TMapRakuArcLayer(Source);
    Result := TMapRakuArcLayer.Create(NewName, Arc.Bounds);
    TMapRakuArcLayer(Result).LineCap := Arc.LineCap;
    TMapRakuArcLayer(Result).RotationDegrees := Arc.RotationDegrees;
    TMapRakuArcLayer(Result).StartAngleDegrees := Arc.StartAngleDegrees;
    TMapRakuArcLayer(Result).StrokeColor := Arc.StrokeColor;
    TMapRakuArcLayer(Result).StrokeStyle := Arc.StrokeStyle;
    TMapRakuArcLayer(Result).StrokeWidth := Arc.StrokeWidth;
    TMapRakuArcLayer(Result).SweepAngleDegrees := Arc.SweepAngleDegrees;
  end
  else if Source is TMapRakuEllipseArcShapeLayer then
  begin
    ArcShape := TMapRakuEllipseArcShapeLayer(Source);
    Result := TMapRakuEllipseArcShapeLayer.Create(NewName,
      ArcShape.Bounds, ArcShape.FillColor);
    TMapRakuEllipseArcShapeLayer(Result).RotationDegrees :=
      ArcShape.RotationDegrees;
    TMapRakuEllipseArcShapeLayer(Result).StartAngleDegrees :=
      ArcShape.StartAngleDegrees;
    TMapRakuEllipseArcShapeLayer(Result).SweepAngleDegrees :=
      ArcShape.SweepAngleDegrees;
  end
  else if Source is TMapRakuRoundedRectangleLayer then
  begin
    Rounded := TMapRakuRoundedRectangleLayer(Source);
    Result := TMapRakuRoundedRectangleLayer.Create(NewName,
      Rounded.Bounds, Rounded.FillColor, Rounded.CornerRadii);
    TMapRakuRoundedRectangleLayer(Result).RotationDegrees :=
      Rounded.RotationDegrees;
  end
  else if Source is TMapRakuTextPathLayer then
  begin
    TextPath := TMapRakuTextPathLayer(Source);
    Result := TMapRakuTextPathLayer.Create(NewName, TextPath.Bounds,
      TextPath.Text, TextPath.FontFamily, TextPath.FontSize,
      TextPath.WrapWidth, TextPath.FillColor,
      TextPath.EditablePathVertices);
    TMapRakuTextPathLayer(Result).Attachment := TextPath.Attachment;
    TMapRakuTextPathLayer(Result).Alignment := TextPath.Alignment;
    TMapRakuTextPathLayer(Result).FontStyle := TextPath.FontStyle;
    TMapRakuTextPathLayer(Result).LetterSpacingRatio :=
      TextPath.LetterSpacingRatio;
    TMapRakuTextPathLayer(Result).IndividualLetterSpacingRatios :=
      TextPath.IndividualLetterSpacingRatios;
    TMapRakuTextPathLayer(Result).CharacterPathOffsets :=
      TextPath.CharacterPathOffsets;
    TMapRakuTextPathLayer(Result).CharacterPositionManual :=
      TextPath.CharacterPositionManual;
    TMapRakuTextPathLayer(Result).CharacterScales :=
      TextPath.CharacterScales;
    TMapRakuTextPathLayer(Result).LineSpacingRatio :=
      TextPath.LineSpacingRatio;
    TMapRakuTextPathLayer(Result).RotationDegrees :=
      TextPath.RotationDegrees;
    TMapRakuTextPathLayer(Result).TransformMode :=
      TextPath.TransformMode;
  end
  else if Source is TMapRakuTextLayer then
  begin
    TextLayer := TMapRakuTextLayer(Source);
    Result := TMapRakuTextLayer.Create(NewName, TextLayer.Bounds,
      TextLayer.Text, TextLayer.FontFamily, TextLayer.FontSize,
      TextLayer.WrapWidth, TextLayer.FillColor);
    TMapRakuTextLayer(Result).Alignment := TextLayer.Alignment;
    TMapRakuTextLayer(Result).FontStyle := TextLayer.FontStyle;
    TMapRakuTextLayer(Result).LetterSpacingRatio :=
      TextLayer.LetterSpacingRatio;
    TMapRakuTextLayer(Result).IndividualLetterSpacingRatios :=
      TextLayer.IndividualLetterSpacingRatios;
    TMapRakuTextLayer(Result).LineSpacingRatio :=
      TextLayer.LineSpacingRatio;
    TMapRakuTextLayer(Result).RotationDegrees :=
      TextLayer.RotationDegrees;
    TMapRakuTextLayer(Result).TransformMode :=
      TextLayer.TransformMode;
  end
  else if Source is TMapRakuEllipseLayer then
  begin
    Rectangle := TVectArtRectangleLayer(Source);
    Result := TMapRakuEllipseLayer.Create(NewName, Rectangle.Bounds,
      Rectangle.FillColor);
    TMapRakuEllipseLayer(Result).RotationDegrees :=
      Rectangle.RotationDegrees;
  end
  else if Source is TVectArtRectangleLayer then
  begin
    Rectangle := TVectArtRectangleLayer(Source);
    Result := TVectArtRectangleLayer.Create(NewName, Rectangle.Bounds,
      Rectangle.FillColor);
    TVectArtRectangleLayer(Result).RotationDegrees :=
      Rectangle.RotationDegrees;
  end
  else if Source is TVectArtImageLayer then
  begin
    Image := TVectArtImageLayer(Source);
    Result := TVectArtImageLayer.Create(NewName, Copy(Image.PngData),
      Image.Points, Image.SourceKind, Image.SourceFileName);
  end
  else if Source is TMapRakuShapeLayer then
  begin
    Shape := TMapRakuShapeLayer(Source);
    Result := TMapRakuShapeLayer.Create(NewName,
      CloneMapRakuShapeContours(Shape.Contours));
    TMapRakuShapeLayer(Result).FillColor := Shape.FillColor;
    TMapRakuShapeLayer(Result).FillRule := Shape.FillRule;
    TMapRakuShapeLayer(Result).StrokeColor := Shape.StrokeColor;
    TMapRakuShapeLayer(Result).StrokeStyle := Shape.StrokeStyle;
    TMapRakuShapeLayer(Result).StrokeWidth := Shape.StrokeWidth;
  end
  else if Source is TVectArtPathLayer then
  begin
    Path := TVectArtPathLayer(Source);
    Result := TVectArtPathLayer.Create(NewName,
      CloneMapRakuPathVertices(Path.Vertices), Path.Closed);
    TVectArtPathLayer(Result).LineCap := Path.LineCap;
    TVectArtPathLayer(Result).MifStrokeStyle := Path.MifStrokeStyle;
    TVectArtPathLayer(Result).StrokeColor := Path.StrokeColor;
    TVectArtPathLayer(Result).MapElement := Path.MapElement;
    TVectArtPathLayer(Result).MapColorOverride := Path.MapColorOverride;
    TVectArtPathLayer(Result).StrokeWidth := Path.StrokeWidth;
    TVectArtPathLayer(Result).WidthPoints := Path.WidthPoints;
  end
  else
    raise EArgumentException.Create('Unsupported group child layer type');
  CopyCommonLayerValues(Source, Result);
end;

function GroupChildCopyName(Group: TMapRakuGroupLayer;
  const SourceName: string): string;
var
  Found: Boolean;
  I: Integer;
  Number: Integer;
begin
  Result := SourceName + ' Copy';
  Number := 2;
  while True do
  begin
    Found := False;
    for I := 0 to Group.ChildCount - 1 do
      if SameText(Group[I].Name, Result) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Exit;
    Result := SourceName + ' Copy ' + Number.ToString;
    Inc(Number);
  end;
end;

function CanDuplicateSelectedGroups(Document: TVectArtDocument): Boolean;
var
  I: Integer;
begin
  Result := (Document <> nil) and (Document.SelectionCount > 0);
  if not Result then
    Exit;
  for I := 1 to Document.LayerCount - 1 do
    if Document.IsLayerSelected(I) and
      (Document[I].Locked or
       not (Document[I] is TMapRakuGroupLayer)) then
      Exit(False);
end;

function DocumentCopyName(UsedNames: TStrings;
  const SourceName: string): string;
var
  Number: Integer;
begin
  Result := SourceName + ' Copy';
  Number := 2;
  while UsedNames.IndexOf(Result) >= 0 do
  begin
    Result := SourceName + ' Copy ' + Number.ToString;
    Inc(Number);
  end;
  UsedNames.Add(Result);
end;

procedure DuplicateSelectedGroups(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
var
  BeforeSelection: TArray<Integer>;
  Command: TMapRakuDuplicateGroupsCommand;
  Duplicates: TArray<TVectArtLayer>;
  I: Integer;
  Indices: TArray<Integer>;
  UsedNames: TStringList;
begin
  if not CanDuplicateSelectedGroups(Document) then
    Exit;
  BeforeSelection := Document.GetSelectedLayerIndices;
  Indices := Copy(BeforeSelection);
  SetLength(Duplicates, Length(Indices));
  UsedNames := TStringList.Create;
  try
    UsedNames.CaseSensitive := False;
    for I := 0 to Document.LayerCount - 1 do
      UsedNames.Add(Document[I].Name);
    for I := 0 to High(Indices) do
    begin
      Duplicates[I] := CloneMapRakuLayer(Document[Indices[I]],
        DocumentCopyName(UsedNames, Document[Indices[I]].Name));
      TranslateMapRakuLayer(Duplicates[I], 24, 24);
      Indices[I] := Indices[I] + I + 1;
    end;
  finally
    UsedNames.Free;
  end;
  Command := TMapRakuDuplicateGroupsCommand.Create(Document,
    BeforeSelection, Indices, Duplicates);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure DeleteOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
var
  BatchCommand: TMapRakuDeleteGroupChildrenCommand;
  Command: TMapRakuDeleteGroupChildCommand;
  Indices: TArray<Integer>;
begin
  if (Document = nil) or not CanEditOpenGroupChild(EditorState) then
    Exit;
  Indices := OpenGroupSelectedIndices(EditorState);
  if Length(Indices) > 1 then
  begin
    BatchCommand := TMapRakuDeleteGroupChildrenCommand.Create(Document,
      EditorState, EditorState.OpenGroup, Indices);
    BatchCommand.Execute;
    if EditHistory <> nil then
      EditHistory.AddApplied(BatchCommand)
    else
      BatchCommand.Free;
    Exit;
  end;
  Command := TMapRakuDeleteGroupChildCommand.Create(Document,
    EditorState, EditorState.OpenGroup, Indices[0]);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure DuplicateOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
var
  BatchCommand: TMapRakuDuplicateGroupChildrenCommand;
  Command: TMapRakuDuplicateGroupChildCommand;
  Duplicate: TVectArtLayer;
  Duplicates: TArray<TVectArtLayer>;
  I: Integer;
  Index: Integer;
  Indices: TArray<Integer>;
  Sources: TArray<TVectArtLayer>;
begin
  if (Document = nil) or not CanEditOpenGroupChild(EditorState) then
    Exit;
  Indices := OpenGroupSelectedIndices(EditorState);
  if Length(Indices) > 1 then
  begin
    SetLength(Sources, Length(Indices));
    SetLength(Duplicates, Length(Indices));
    for I := 0 to High(Indices) do
    begin
      Sources[I] := EditorState.OpenGroup[Indices[I]];
      Duplicates[I] := CloneMapRakuLayer(Sources[I],
        GroupChildCopyName(EditorState.OpenGroup, Sources[I].Name));
      TranslateMapRakuLayer(Duplicates[I], 24, 24);
      Indices[I] := Indices[I] + I + 1;
    end;
    BatchCommand := TMapRakuDuplicateGroupChildrenCommand.Create(
      Document, EditorState, EditorState.OpenGroup, Indices, Sources,
      Duplicates);
    BatchCommand.Execute;
    if EditHistory <> nil then
      EditHistory.AddApplied(BatchCommand)
    else
      BatchCommand.Free;
    Exit;
  end;
  Index := Indices[0];
  Duplicate := CloneMapRakuLayer(EditorState.OpenGroupChild,
    GroupChildCopyName(EditorState.OpenGroup,
      EditorState.OpenGroupChild.Name));
  TranslateMapRakuLayer(Duplicate, 24, 24);
  Command := TMapRakuDuplicateGroupChildCommand.Create(Document,
    EditorState, EditorState.OpenGroup, Index + 1, Duplicate);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure MoveOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Delta: Integer);
var
  AfterOrder: TArray<TVectArtLayer>;
  BeforeOrder: TArray<TVectArtLayer>;
  Command: TMapRakuMoveGroupChildCommand;
  I: Integer;
  Index: Integer;
  J: Integer;
  Step: Integer;
  StepCount: Integer;
  ReorderCommand: TMapRakuReorderGroupChildrenCommand;
  Temp: TVectArtLayer;
begin
  if (Document = nil) or not CanMoveOpenGroupChild(EditorState, Delta) then
    Exit;
  if EditorState.OpenGroupChildCount > 1 then
  begin
    SetLength(BeforeOrder, EditorState.OpenGroup.ChildCount);
    for I := 0 to High(BeforeOrder) do
      BeforeOrder[I] := EditorState.OpenGroup[I];
    AfterOrder := Copy(BeforeOrder);
    if Abs(Delta) > 1 then StepCount := Length(AfterOrder) else StepCount := 1;
    for Step := 1 to StepCount do
      if Delta > 0 then
        for I := High(AfterOrder) - 1 downto 0 do
          if EditorState.IsOpenGroupChildSelected(AfterOrder[I]) and
            not EditorState.IsOpenGroupChildSelected(AfterOrder[I + 1]) then
          begin
            Temp := AfterOrder[I];
            AfterOrder[I] := AfterOrder[I + 1];
            AfterOrder[I + 1] := Temp;
          end
      else
        for J := 1 to High(AfterOrder) do
          if EditorState.IsOpenGroupChildSelected(AfterOrder[J]) and
            not EditorState.IsOpenGroupChildSelected(AfterOrder[J - 1]) then
          begin
            Temp := AfterOrder[J];
            AfterOrder[J] := AfterOrder[J - 1];
            AfterOrder[J - 1] := Temp;
          end;
    ReorderCommand := TMapRakuReorderGroupChildrenCommand.Create(
      Document, EditorState.OpenGroup, BeforeOrder, AfterOrder);
    ReorderCommand.Execute;
    if EditHistory <> nil then
      EditHistory.AddApplied(ReorderCommand)
    else
      ReorderCommand.Free;
    Exit;
  end;
  Index := OpenGroupChildIndex(EditorState);
  Command := TMapRakuMoveGroupChildCommand.Create(Document,
    EditorState.OpenGroup, Index, EnsureRange(Index + Delta, 0,
      EditorState.OpenGroup.ChildCount - 1));
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

{ TMapRakuDuplicateGroupsCommand }

constructor TMapRakuDuplicateGroupsCommand.Create(
  ADocument: TVectArtDocument; const BeforeSelection,
  Indices: TArray<Integer>; const Duplicates: TArray<TVectArtLayer>);
begin
  inherited Create;
  FDocument := ADocument;
  FBeforeSelection := Copy(BeforeSelection);
  FIndices := Copy(Indices);
  FAfterSelection := Copy(Indices);
  FDuplicates := Copy(Duplicates);
end;

destructor TMapRakuDuplicateGroupsCommand.Destroy;
var
  Layer: TVectArtLayer;
begin
  if not FDuplicatesInDocument then
    for Layer in FDuplicates do
      Layer.Free;
  inherited Destroy;
end;

procedure TMapRakuDuplicateGroupsCommand.Execute;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := 0 to High(FIndices) do
      FDocument.InsertLayer(FIndices[I], FDuplicates[I]);
    FDuplicatesInDocument := True;
    FDocument.SetSelectedLayers(FAfterSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuDuplicateGroupsCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := High(FIndices) downto 0 do
      FDocument.ExtractLayer(FIndices[I]);
    FDuplicatesInDocument := False;
    FDocument.SetSelectedLayers(FBeforeSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

function NextGroupName(Document: TVectArtDocument): string;
var
  Count: Integer;
  I: Integer;
begin
  Count := 0;
  for I := 1 to Document.LayerCount - 1 do
    if Document[I] is TMapRakuGroupLayer then
      Inc(Count);
  Result := Format('グループ %d', [Count + 1]);
end;

function CanGroupSelectedLayers(Document: TVectArtDocument): Boolean;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  Result := (Document <> nil) and (Document.SelectionCount >= 2);
  if not Result then
    Exit;
  Indices := Document.GetSelectedLayerIndices;
  for I := 0 to High(Indices) do
    if Document[Indices[I]].Locked then
      Exit(False);
end;

function CanUngroupSelectedLayer(Document: TVectArtDocument): Boolean;
begin
  Result := (Document <> nil) and (Document.SelectionCount = 1) and
    (Document.SelectedIndex > 0) and
    (Document[Document.SelectedIndex] is TMapRakuGroupLayer) and
    not Document[Document.SelectedIndex].Locked;
end;

procedure GroupSelectedLayers(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
var
  Command: TMapRakuGroupCommand;
begin
  if not CanGroupSelectedLayers(Document) then
    Exit;
  Command := TMapRakuGroupCommand.Create(Document,
    Document.GetSelectedLayerIndices, NextGroupName(Document));
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure UngroupSelectedLayer(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
var
  Command: TMapRakuUngroupCommand;
begin
  if not CanUngroupSelectedLayer(Document) then
    Exit;
  Command := TMapRakuUngroupCommand.Create(Document,
    Document.SelectedIndex);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

{ TMapRakuGroupCommand }

constructor TMapRakuGroupCommand.Create(ADocument: TVectArtDocument;
  const OriginalIndices: TArray<Integer>; const GroupName: string);
var I: Integer;
begin
  inherited Create;
  FDocument := ADocument;
  FOriginalIndices := Copy(OriginalIndices);
  FBeforeSelection := Copy(OriginalIndices);
  FGroup := TMapRakuGroupLayer.Create(GroupName);
  FGroup.MapSurface := True;
  for I in OriginalIndices do
    if not IsMapTree(ADocument[I]) then FGroup.MapSurface := False;
end;

destructor TMapRakuGroupCommand.Destroy;
begin
  if not FGroupInDocument then
    FGroup.Free;
  inherited Destroy;
end;

procedure TMapRakuGroupCommand.Execute;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := High(FOriginalIndices) downto 0 do
      FGroup.InsertChild(0, FDocument.ExtractLayer(FOriginalIndices[I]));
    FGroupIndex := FOriginalIndices[High(FOriginalIndices)] -
      High(FOriginalIndices);
    FGroupIndex := FDocument.InsertLayer(FGroupIndex, FGroup);
    FGroupInDocument := True;
    FDocument.SetSelectedLayers([FGroupIndex]);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuGroupCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    FDocument.ExtractLayer(FGroupIndex);
    FGroupInDocument := False;
    for I := 0 to High(FOriginalIndices) do
      FDocument.InsertLayer(FOriginalIndices[I], FGroup.ExtractChild(0));
    FDocument.SetSelectedLayers(FBeforeSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

{ TMapRakuUngroupCommand }

constructor TMapRakuUngroupCommand.Create(ADocument: TVectArtDocument;
  GroupIndex: Integer);
begin
  inherited Create;
  FDocument := ADocument;
  FGroupIndex := GroupIndex;
  FGroup := TMapRakuGroupLayer(ADocument[GroupIndex]);
  FChildCount := FGroup.ChildCount;
  FGroupInDocument := True;
end;

destructor TMapRakuUngroupCommand.Destroy;
begin
  if not FGroupInDocument then
    FGroup.Free;
  inherited Destroy;
end;

procedure TMapRakuUngroupCommand.Execute;
var
  Child: TVectArtLayer;
  I: Integer;
  Selection: TArray<Integer>;
begin
  FDocument.BeginUpdate;
  try
    FDocument.ExtractLayer(FGroupIndex);
    FGroupInDocument := False;
    SetLength(Selection, FChildCount);
    for I := High(Selection) downto 0 do
    begin
      Child := FGroup.ExtractChild(FGroup.ChildCount - 1);
      FDocument.InsertLayer(FGroupIndex, Child);
      Selection[I] := FGroupIndex + I;
    end;
    FDocument.SetSelectedLayers(Selection);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TMapRakuUngroupCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := FGroupIndex + FChildCount - 1 downto FGroupIndex do
      FGroup.InsertChild(0, FDocument.ExtractLayer(I));
    FGroupIndex := FDocument.InsertLayer(FGroupIndex, FGroup);
    FGroupInDocument := True;
    FDocument.SetSelectedLayers([FGroupIndex]);
  finally
    FDocument.EndUpdate;
  end;
end;

end.
