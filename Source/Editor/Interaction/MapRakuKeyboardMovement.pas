// 選択図形のキーボード微移動とUndo履歴への登録を担当する。
unit MapRakuKeyboardMovement;

interface

uses
  System.Classes, MapRakuDocument, MapRakuEditHistory;

// 矢印キーを選択した矩形系・楕円弧・画像の移動として処理した場合にTrueを返す。
function HandleSelectionNudge(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory; Key: Word;
  Shift: TShiftState): Boolean;

implementation

uses
  System.Generics.Collections, System.Types, Winapi.Windows,
  MapRakuEditCommands, MapRakuGroupTransformCommands;

const
  NUDGE_DISTANCE       = 1;
  FAST_NUDGE_DISTANCE  = 10;

function HandleSelectionNudge(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory; Key: Word;
  Shift: TShiftState): Boolean;
var
  Command: TVectArtCompoundCommand;
  Distance: Single;
  DX: Single;
  DY: Single;
  I: Integer;
  ImageIndex: Integer;
  ImageIndices: TList<Integer>;
  ImagePointIndex: Integer;
  Indices: TList<Integer>;
  NewImagePoints: TArray<TVectArtImagePoints>;
  NewBounds: TArray<TRectF>;
  OldImagePoints: TArray<TVectArtImagePoints>;
  OldBounds: TArray<TRectF>;
  HasTransform: Boolean;
begin
  Result := False;
  if (ADocument = nil) or (AEditHistory = nil) or
    (ssCtrl in Shift) or (ssAlt in Shift) or
    not (Key in [VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN]) then
    Exit;
  Distance := NUDGE_DISTANCE;
  if ssShift in Shift then
    Distance := FAST_NUDGE_DISTANCE;
  DX := 0;
  DY := 0;
  case Key of
    VK_LEFT:  DX := -Distance;
    VK_UP:    DY := -Distance;
    VK_RIGHT: DX := Distance;
    VK_DOWN:  DY := Distance;
  end;

  HasTransform := False;
  for I := 1 to ADocument.LayerCount - 1 do
    if ADocument.IsLayerSelected(I) then
    begin
      if ADocument[I].Locked then Exit;
      HasTransform := HasTransform or not ADocument[I].Transform.IsIdentity or
        (ADocument[I] is TMapRakuGroupLayer);
    end;
  if HasTransform then
  begin
    Command := TVectArtCompoundCommand.Create;
    for I := 1 to ADocument.LayerCount - 1 do
      if ADocument.IsLayerSelected(I) then
        Command.Add(TMapRakuTranslateLayerCommand.Create(ADocument, ADocument[I], DX, DY));
    Command.Execute;
    AEditHistory.AddApplied(Command);
    Exit(True);
  end;

  Indices := TList<Integer>.Create;
  ImageIndices := TList<Integer>.Create;
  try
    for I := 1 to ADocument.LayerCount - 1 do
      if ADocument.IsLayerSelected(I) then
      begin
        // マウス移動と同様、ロックを含む選択全体は移動しない。
        if ADocument[I].Locked then
          Exit;
        if (ADocument[I] is TMapRakuRectangleLineLayer) or
          (ADocument[I] is TVectArtRectangleLayer) or
          (ADocument[I] is TMapRakuArcLayer) then
          Indices.Add(I)
        else if ADocument[I] is TVectArtImageLayer then
          ImageIndices.Add(I);
      end;
    if (Indices.Count = 0) and (ImageIndices.Count = 0) then
      Exit;

    SetLength(OldBounds, Indices.Count);
    SetLength(NewBounds, Indices.Count);
    SetLength(OldImagePoints, ImageIndices.Count);
    SetLength(NewImagePoints, ImageIndices.Count);
    Command := TVectArtCompoundCommand.Create;
    try
      ADocument.BeginUpdate;
      try
        for I := 0 to Indices.Count - 1 do
        begin
          if ADocument[Indices[I]] is TMapRakuRectangleLineLayer then
            OldBounds[I] := TMapRakuRectangleLineLayer(
              ADocument[Indices[I]]).Bounds
          else if ADocument[Indices[I]] is TMapRakuArcLayer then
            OldBounds[I] := TMapRakuArcLayer(
              ADocument[Indices[I]]).Bounds
          else
            OldBounds[I] := TVectArtRectangleLayer(
              ADocument[Indices[I]]).Bounds;
          NewBounds[I] := OldBounds[I];
          NewBounds[I].Offset(DX, DY);
          if ADocument[Indices[I]] is TMapRakuRectangleLineLayer then
            ADocument.SetRectangleLineBounds(Indices[I], NewBounds[I])
          else if ADocument[Indices[I]] is TMapRakuArcLayer then
            ADocument.SetArcBounds(Indices[I], NewBounds[I])
          else
            ADocument.SetRectangleBounds(Indices[I], NewBounds[I]);
        end;
        for ImageIndex := 0 to ImageIndices.Count - 1 do
        begin
          OldImagePoints[ImageIndex] := TVectArtImageLayer(
            ADocument[ImageIndices[ImageIndex]]).Points;
          NewImagePoints[ImageIndex] := OldImagePoints[ImageIndex];
          for ImagePointIndex := 0 to High(NewImagePoints[ImageIndex]) do
            NewImagePoints[ImageIndex][ImagePointIndex].Offset(DX, DY);
          ADocument.SetImagePoints(ImageIndices[ImageIndex],
            NewImagePoints[ImageIndex]);
        end;
      finally
        ADocument.EndUpdate;
      end;
      if Indices.Count > 0 then
        Command.Add(TVectArtBoundsCommand.Create(ADocument,
          Indices.ToArray, OldBounds, NewBounds));
      for ImageIndex := 0 to ImageIndices.Count - 1 do
        Command.Add(TVectArtImagePointsCommand.Create(ADocument,
          ImageIndices[ImageIndex], OldImagePoints[ImageIndex],
          NewImagePoints[ImageIndex]));
      AEditHistory.AddApplied(Command);
      Command := nil;
      Result := True;
    finally
      Command.Free;
    end;
  finally
    ImageIndices.Free;
    Indices.Free;
  end;
end;

end.
