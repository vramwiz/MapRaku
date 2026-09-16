// レイヤー一覧のクリック選択、範囲選択の基準点、ドラッグ待ちの単一選択を管理する。
// 座標の当たり判定とドラッグ開始の判断はコントロールが担当する。
unit MapRakuLayerSelection;

interface

uses
  System.Classes, MapRakuDocument, MapRakuEditorState;

type
  TMapRakuLayerSelection = class
  private
    FDocument     : TVectArtDocument;        // 選択を反映する文書。所有しない。
    FEditorState  : TVectArtEditorState;     // グループ内の選択を反映する状態。
    FAnchorIndex  : Integer;                 // 文書・グループ内で共通の1基点範囲アンカー。
    FAnchorParent : TMapRakuGroupLayer; // 範囲アンカーの親。nilなら文書直下。
    FPendingLayer : TVectArtLayer;           // ドラッグせず離した場合だけ単一選択する行。
    FPendingParent: TMapRakuGroupLayer; // 保留行の親。nilなら文書直下。
    procedure SelectGroupChildRange(AnchorIndex, TargetIndex: Integer; KeepExisting: Boolean);
  public
    // 行選択を反映する。選択済みの複数行はドラッグ判定まで維持する。
    procedure SelectLayer(Document: TVectArtDocument; State: TVectArtEditorState;
      Parent: TMapRakuGroupLayer; Layer: TVectArtLayer; SourceIndex: Integer; Shift: TShiftState);
    // 同じ行の上でドラッグせず離したクリックを単一選択として確定する。
    procedure CompleteClick(Layer: TVectArtLayer; SourceIndex: Integer);
    // 階層変更や並べ替えにより使えなくなった範囲アンカーを解除する。
    procedure ResetAnchor;
    // 新規操作・ドラッグ終了時に保留していたクリックを取り消す。
    procedure ResetClick;
    property PendingLayer: TVectArtLayer read FPendingLayer;
  end;

implementation

uses
  System.Generics.Collections, System.Math;

procedure TMapRakuLayerSelection.SelectLayer(Document: TVectArtDocument;
  State: TVectArtEditorState; Parent: TMapRakuGroupLayer; Layer: TVectArtLayer;
  SourceIndex: Integer; Shift: TShiftState);
var
  AnchorChildIndex: Integer;
begin
  FDocument := Document;
  FEditorState := State;
  if FAnchorParent <> Parent then
  begin
    FAnchorIndex := -1;
    FAnchorParent := Parent;
  end;
  if Parent <> nil then
  begin
    if FEditorState.OpenGroup <> Parent then
      FEditorState.OpenGroupInDocument(FDocument, Parent);
    FDocument.SetSelectedLayers([]);
    if ssShift in Shift then
    begin
      if FAnchorIndex <= 0 then
      begin
        FAnchorIndex := SourceIndex + 1;
        for AnchorChildIndex := 0 to Parent.ChildCount - 1 do
          if Parent[AnchorChildIndex] = FEditorState.OpenGroupChild then
          begin
            FAnchorIndex := AnchorChildIndex + 1;
            Break;
          end;
      end;
      SelectGroupChildRange(FAnchorIndex, SourceIndex + 1,
        ssCtrl in Shift);
    end
    else if ssCtrl in Shift then
    begin
      FEditorState.ToggleOpenGroupChild(Layer);
      FAnchorIndex := SourceIndex + 1;
    end
    else
    begin
      if not FEditorState.IsOpenGroupChildSelected(Layer) or
        (FEditorState.OpenGroupChildCount <= 1) then
        FEditorState.OpenGroupChild := Layer
      else
      begin
        FPendingLayer := Layer;
        FPendingParent := Parent;
      end;
      FAnchorIndex := SourceIndex + 1;
    end;
  end
  else if ssShift in Shift then
  begin
    FEditorState.OpenGroup := nil;
    if FAnchorIndex <= 0 then
      if FDocument.SelectedIndex > 0 then
        FAnchorIndex := FDocument.SelectedIndex
      else
        FAnchorIndex := SourceIndex;
    FDocument.SelectLayerRange(FAnchorIndex, SourceIndex,
      ssCtrl in Shift);
  end
  else if ssCtrl in Shift then
  begin
    FEditorState.OpenGroup := nil;
    FDocument.ToggleSelectedLayer(SourceIndex);
    FAnchorIndex := SourceIndex;
  end
  else
  begin
    FEditorState.OpenGroup := nil;
    if not FDocument.IsLayerSelected(SourceIndex) or
      (FDocument.SelectionCount <= 1) then
      FDocument.SelectedIndex := SourceIndex
    else
    begin
      FPendingLayer := Layer;
      FPendingParent := nil;
    end;
    FAnchorIndex := SourceIndex;
  end;
end;

procedure TMapRakuLayerSelection.CompleteClick(Layer: TVectArtLayer; SourceIndex: Integer);
begin
  if (Layer = nil) or (Layer <> FPendingLayer) then Exit;
  if FPendingParent <> nil then FEditorState.OpenGroupChild := Layer
  else FDocument.SelectedIndex := SourceIndex;
  ResetClick;
end;

procedure TMapRakuLayerSelection.ResetAnchor;
begin
  FAnchorIndex := -1;
  FAnchorParent := nil;
end;

procedure TMapRakuLayerSelection.ResetClick;
begin
  FPendingLayer := nil;
  FPendingParent := nil;
end;

procedure TMapRakuLayerSelection.SelectGroupChildRange(AnchorIndex,
  TargetIndex: Integer; KeepExisting: Boolean);
var
  I: Integer;
  FirstIndex: Integer;
  LastIndex: Integer;
  Layer: TVectArtLayer;
  Selected: TList<TVectArtLayer>;
begin
  if (FEditorState = nil) or (FEditorState.OpenGroup = nil) then
    Exit;
  Selected := TList<TVectArtLayer>.Create;
  try
    if KeepExisting then
      for Layer in FEditorState.GetOpenGroupChildren do
        Selected.Add(Layer);
    FirstIndex := Min(AnchorIndex, TargetIndex) - 1;
    LastIndex := Max(AnchorIndex, TargetIndex) - 1;
    for I := FirstIndex to LastIndex do
      if (I >= 0) and (I < FEditorState.OpenGroup.ChildCount) then
      begin
        Layer := FEditorState.OpenGroup[I];
        if Selected.IndexOf(Layer) < 0 then
          Selected.Add(Layer);
      end;
    FEditorState.SetOpenGroupChildren(Selected.ToArray);
  finally
    Selected.Free;
  end;
end;

end.
