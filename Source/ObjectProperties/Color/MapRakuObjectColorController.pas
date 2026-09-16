// 埋め込みカラーピッカーを、選択オブジェクトまたは選択フィルターへ双方向同期する。
// 作成色とグラデーション点も含む対象解決はMapRakuColorTargetsへ委譲する。
unit MapRakuObjectColorController;

interface

uses
  System.Classes, Vcl.Graphics, MapRakuColorPickerFrame,
  MapRakuContext, MapRakuDocument, MapRakuFilters,
  MapRakuObjectPropertyCommands, MapRakuPaintStyles, MapRakuPaintStyleGesture;

type
  TMapRakuObjectColorController = class
  private
    FPaintGesture: TMapRakuPaintStyleGesture; // 共通塗りの複数選択履歴。
    FColorDocumentUpdateActive: Boolean;
    FColorGestureActive: Boolean;
    FColorGestureFilter: TMapRakuFilter;
    FColorGestureGradientLayer: TVectArtLayer;
    FColorGestureOldParameters: TMapRakuFilter;
    FColorGestureOldPaintStyle: TMapRakuPaintStyle;
    FColorStartLayers: TArray<TVectArtLayer>;
    FColorStartTargets: TArray<TMapRakuLayerColorTarget>;
    FColorStartValues: TArray<TColor>;
    FContext: IVectArtDesignerContext;
    FCreationTargetStateKnown: Boolean;
    FFrame: TMapRakuColorPickerFrame;
    FLastUsesCreationPaint: Boolean;
    FOnChanged: TNotifyEvent;
    FOpacityDocumentUpdateActive: Boolean;
    FOpacityGestureActive: Boolean;
    FOpacityGestureGradientLayer: TVectArtLayer;
    FOpacityGestureOldPaintStyle: TMapRakuPaintStyle;
    FOpacityGestureFilter: TMapRakuFilter;
    FOpacityGestureOldParameters: TMapRakuFilter;
    FOpacityStartLayers: TArray<TVectArtLayer>;
    FOpacityStartValues: TArray<Single>;
    FRefreshing: Boolean;
    FUpdatingColor: Boolean;
    procedure PaintGestureStart(Sender: TObject);
    procedure PaintGestureEnd(Sender: TObject);
    procedure ColorChanged(Sender: TObject);
    procedure ColorGestureEnd(Sender: TObject);
    procedure ColorGestureStart(Sender: TObject);
    procedure GradientStopSelected(Sender: TObject);
    procedure AdoptVisiblePickerAsCreationPaint;
    procedure OpacityChanged(Sender: TObject);
    procedure PaintStyleChanged(Sender: TObject);
    procedure OpacityGestureEnd(Sender: TObject);
    procedure OpacityGestureStart(Sender: TObject);
  public
    // FrameのイベントをDocument編集へ接続する。Frameの所有権は取得しない。
    constructor Create(AFrame: TMapRakuColorPickerFrame);
    // 未確定の対話更新を閉じ、保持中のフィルタースナップショットを破棄する。
    destructor Destroy; override;
    // 編集対象のContextを交換する。呼び出し側はContext内サービスの寿命を保証する。
    procedure SetContext(const Value: IVectArtDesignerContext);
    // フィルター、グラデーション点、レイヤー、作成色の優先順でFrameへ現在値を反映する。
    procedure Refresh;
    // Documentへ属性を反映した後、他の表示同期が必要なことを呼び出し側へ通知する。
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Math, MapRakuEditCommands, MapRakuFilterCommands,
  MapRakuColorTargets, MapRakuEditorState, MapRakuPaintCommands,
  MapRakuObjectPropertySelection;

procedure AddAppliedCommand(const Context: IVectArtDesignerContext;
  Command: TVectArtEditCommand);
begin
  if (Command <> nil) and (Context <> nil) and
    (Context.EditHistory <> nil) then
    Context.EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

constructor TMapRakuObjectColorController.Create(
  AFrame: TMapRakuColorPickerFrame);
begin
  inherited Create;
  FFrame := AFrame;
  FPaintGesture := TMapRakuPaintStyleGesture.Create;
  FFrame.OnPaintGestureStart := PaintGestureStart;
  FFrame.OnPaintGestureEnd := PaintGestureEnd;
  FFrame.OnChange := ColorChanged;
  FFrame.OnColorGestureEnd := ColorGestureEnd;
  FFrame.OnColorGestureStart := ColorGestureStart;
  FFrame.OnGradientStopSelect := GradientStopSelected;
  FFrame.OnOpacityChange := OpacityChanged;
  FFrame.OnOpacityGestureEnd := OpacityGestureEnd;
  FFrame.OnOpacityGestureStart := OpacityGestureStart;
  FFrame.OnPaintStyleChange := PaintStyleChanged;
end;

procedure TMapRakuObjectColorController.PaintGestureStart(Sender: TObject);
begin
  FPaintGesture.Start(FContext);
end;

procedure TMapRakuObjectColorController.PaintGestureEnd(Sender: TObject);
begin
  FPaintGesture.Finish;
end;

procedure TMapRakuObjectColorController.AdoptVisiblePickerAsCreationPaint;
begin
  if (FContext = nil) or (FContext.EditorState = nil) then
    Exit;
  // 無効な対象（画像やぼかしなど）は表示値を作成既定へ上書きしない。
  if FFrame.ColorEnabled then
    FContext.EditorState.CreationPaintStyle := FFrame.PaintStyle;
  if FFrame.OpacityEnabled and (not (FFrame.PaintStyle.Kind in [slpkGradient, slpkPattern])) then
    FContext.EditorState.RectangleOpacity := FFrame.Opacity / 100.0;
end;

procedure TMapRakuObjectColorController.PaintStyleChanged(
  Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  Filter: TMapRakuFilter;
  Layer: TVectArtLayer;
  NewStyle: TMapRakuPaintStyle;
  OldStyle: TMapRakuPaintStyle;
begin
  if FRefreshing or (FContext = nil) or (FContext.EditorState = nil) or
    (FContext.Document = nil) then
    Exit;
  NewStyle := FFrame.PaintStyle;
  if not FPaintGesture.Apply(NewStyle) and not MapRakuUsesCreationPaint(FContext) and
    not MapRakuSelectedFilter(FContext, Layer, Filter) then
  begin
    Command := TVectArtCompoundCommand.Create;
    FContext.Document.BeginUpdate;
    try
      for Layer in MapRakuSelectedColorLayers(FContext) do
        if not Layer.Locked then
        begin
          OldStyle := Layer.PaintStyle;
          if OldStyle.SameAs(NewStyle) then
            Continue;
          Command.Add(TMapRakuSetLayerPaintStyleCommand.Create(
            FContext.Document, Layer, OldStyle, NewStyle));
          Layer.PaintStyle := NewStyle;
          FContext.Document.Changed;
        end;
    finally
      FContext.Document.EndUpdate;
    end;
    if Command.Count > 0 then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
  end;
  // 選択対象へ適用したモードを、次回作成用にも同時に採用する。
  FContext.EditorState.CreationPaintStyle := NewStyle;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

destructor TMapRakuObjectColorController.Destroy;
begin
  FPaintGesture.Free;
  if FColorDocumentUpdateActive and (FContext <> nil) and
    (FContext.Document <> nil) then
    FContext.Document.EndInteractiveUpdate;
  if FOpacityDocumentUpdateActive and (FContext <> nil) and
    (FContext.Document <> nil) then
    FContext.Document.EndInteractiveUpdate;
  FColorGestureOldParameters.Free;
  FOpacityGestureOldParameters.Free;
  inherited Destroy;
end;

procedure TMapRakuObjectColorController.ColorChanged(Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  Document: TVectArtDocument;
  Filter: TMapRakuFilter;
  Layer: TVectArtLayer;
  NewColor: TColor;
  NewParameters: TMapRakuFilter;
  NewStyle: TMapRakuPaintStyle;
  OldColor: TColor;
  OldParameters: TMapRakuFilter;
  OldStyle: TMapRakuPaintStyle;
  StopId: Integer;
  Target: TMapRakuLayerColorTarget;
begin
  if FRefreshing or FUpdatingColor or (FContext = nil) or
    (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewColor := ColorToRGB(FFrame.SelectedColor);
  if MapRakuSelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not TryGetMapRakuFilterColor(Filter, OldColor) then
      Exit;
    if ColorToRGB(OldColor) = NewColor then
    begin
      if FContext.EditorState <> nil then
        FContext.EditorState.CreationPaintStyle := FFrame.PaintStyle;
      Exit;
    end;
    if FColorGestureActive then
    begin
      SetMapRakuFilterColor(Filter, NewColor);
      Document.Changed;
    end
    else
    begin
      OldParameters := Filter.Clone;
      SetMapRakuFilterColor(Filter, NewColor);
      Document.Changed;
      NewParameters := Filter.Clone;
      try
        AddAppliedCommand(FContext,
          TMapRakuSetFilterParametersCommand.Create(Document, Filter,
            OldParameters, NewParameters));
      finally
        NewParameters.Free;
        OldParameters.Free;
      end;
    end;
  end
  else if MapRakuSelectedGradientStop(FContext, Layer, StopId,
    OldColor) then
  begin
    if Layer.Locked then
      Exit;
    OldStyle := Layer.PaintStyle;
    NewStyle := FFrame.PaintStyle;
    if OldStyle.SameAs(NewStyle) then
      Exit;
    Layer.PaintStyle := NewStyle;
    Document.Changed;
    if not FColorGestureActive then
      AddAppliedCommand(FContext, TMapRakuSetLayerPaintStyleCommand.Create(
        Document, Layer, OldStyle, NewStyle));
  end
  else if not MapRakuUsesCreationPaint(FContext) then
  begin
    Command := nil;
    if not FColorGestureActive then
      Command := TVectArtCompoundCommand.Create;
    Document.BeginUpdate;
    try
      for Layer in MapRakuSelectedColorLayers(FContext) do
        if not Layer.Locked and TryGetMapRakuLayerColor(Layer, OldColor,
          Target) and (ColorToRGB(OldColor) <> NewColor) then
        begin
          if Command <> nil then
            Command.Add(TMapRakuLayerColorCommand.Create(Document,
              Layer, Target, OldColor, NewColor));
          SetMapRakuLayerColor(Layer, Target, NewColor);
          Document.Changed;
        end;
    finally
      Document.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
  end;
  // 対象を先に更新してから、確定色を次回作成用にも必ず採用する。
  // EditorStateの同期通知がピッカーを古い対象色へ戻すことを防ぐ。
  if FContext.EditorState <> nil then
    FContext.EditorState.CreationPaintStyle := FFrame.PaintStyle;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TMapRakuObjectColorController.ColorGestureEnd(Sender: TObject);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  CurrentColor: TColor;
  I: Integer;
  Target: TMapRakuLayerColorTarget;
begin
  if not FColorGestureActive then
    Exit;
  FColorGestureActive := False;
  if FColorGestureGradientLayer <> nil then
  begin
    if not FColorGestureOldPaintStyle.SameAs(
      FColorGestureGradientLayer.PaintStyle) then
      AddAppliedCommand(FContext, TMapRakuSetLayerPaintStyleCommand.Create(
        FContext.Document, FColorGestureGradientLayer,
        FColorGestureOldPaintStyle, FColorGestureGradientLayer.PaintStyle));
  end
  else if (FColorGestureFilter <> nil) and
    (FColorGestureOldParameters <> nil) then
  begin
    if TryGetMapRakuFilterColor(FColorGestureOldParameters, Color) and
      TryGetMapRakuFilterColor(FColorGestureFilter, CurrentColor) and
      (ColorToRGB(Color) <> ColorToRGB(CurrentColor)) then
      AddAppliedCommand(FContext,
        TMapRakuSetFilterParametersCommand.Create(FContext.Document,
          FColorGestureFilter, FColorGestureOldParameters,
          FColorGestureFilter));
  end
  else
  begin
    Command := TVectArtCompoundCommand.Create;
    for I := 0 to Min(High(FColorStartLayers),
      High(FColorStartValues)) do
      if TryGetMapRakuLayerColor(FColorStartLayers[I], Color, Target) and
        (ColorToRGB(Color) <> ColorToRGB(FColorStartValues[I])) then
        Command.Add(TMapRakuLayerColorCommand.Create(FContext.Document,
          FColorStartLayers[I], FColorStartTargets[I],
          FColorStartValues[I], Color));
    if Command.Count > 0 then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
  end;
  FColorGestureFilter := nil;
  FColorGestureGradientLayer := nil;
  FColorGestureOldParameters.Free;
  FColorGestureOldParameters := nil;
  FColorStartLayers := nil;
  FColorStartTargets := nil;
  FColorStartValues := nil;
  if FColorDocumentUpdateActive then
  begin
    FColorDocumentUpdateActive := False;
    FContext.Document.EndInteractiveUpdate;
  end;
end;

procedure TMapRakuObjectColorController.ColorGestureStart(
  Sender: TObject);
var
  Color: TColor;
  Filter: TMapRakuFilter;
  I: Integer;
  Layer: TVectArtLayer;
  StopId: Integer;
  Target: TMapRakuLayerColorTarget;
begin
  if FColorGestureActive or (FContext = nil) or
    (FContext.Document = nil) then
    Exit;
  if MapRakuSelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not TryGetMapRakuFilterColor(Filter, Color) then
      Exit;
    FColorGestureFilter := Filter;
    FColorGestureOldParameters := Filter.Clone;
  end
  else if MapRakuSelectedGradientStop(FContext, Layer, StopId,
    Color) then
  begin
    if Layer.Locked then
      Exit;
    FColorGestureGradientLayer := Layer;
    FColorGestureOldPaintStyle := Layer.PaintStyle;
  end
  else if MapRakuUsesCreationPaint(FContext) then
    Exit
  else
  begin
    FColorStartLayers := MapRakuSelectedColorLayers(FContext);
    if Length(FColorStartLayers) = 0 then
      Exit;
    SetLength(FColorStartTargets, Length(FColorStartLayers));
    SetLength(FColorStartValues, Length(FColorStartLayers));
    for I := 0 to High(FColorStartLayers) do
    begin
      if FColorStartLayers[I].Locked or
        not TryGetMapRakuLayerColor(FColorStartLayers[I],
          FColorStartValues[I], Target) then
      begin
        FColorStartLayers := nil;
        FColorStartTargets := nil;
        FColorStartValues := nil;
        Exit;
      end;
      FColorStartTargets[I] := Target;
    end;
  end;
  FColorGestureActive := True;
  FContext.Document.BeginInteractiveUpdate;
  FColorDocumentUpdateActive := True;
end;

procedure TMapRakuObjectColorController.GradientStopSelected(
  Sender: TObject);
var
  Color: TColor;
  Layer: TVectArtLayer;
  StopId: Integer;
begin
  if not MapRakuSelectedGradientStop(FContext, Layer, StopId,
    Color) then
    Exit;
  FContext.EditorState.SelectGradientStop(Layer, FFrame.GradientStopId);
end;

procedure TMapRakuObjectColorController.OpacityChanged(Sender: TObject);
var
  StopId: Integer;
  Color: TColor;
  OldStyle, NewStyle: TMapRakuPaintStyle;
  Command: TVectArtCompoundCommand;
  Document: TVectArtDocument;
  Filter: TMapRakuFilter;
  Layer: TVectArtLayer;
  NewParameters: TMapRakuFilter;
  NewValue: Single;
  OldParameters: TMapRakuFilter;
  OldValue: Single;
begin
  if FRefreshing or (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewValue := FFrame.Opacity / 100.0;
  if MapRakuSelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not (Filter is TMapRakuShadowFilter) then
      Exit;
    OldValue := TMapRakuShadowFilter(Filter).Opacity;
    if SameValue(OldValue, NewValue) then
      Exit;
    if FOpacityGestureActive then
    begin
      TMapRakuShadowFilter(Filter).Opacity := NewValue;
      Document.Changed;
    end
    else
    begin
      OldParameters := Filter.Clone;
      TMapRakuShadowFilter(Filter).Opacity := NewValue;
      Document.Changed;
      NewParameters := Filter.Clone;
      try
        AddAppliedCommand(FContext,
          TMapRakuSetFilterParametersCommand.Create(Document, Filter,
            OldParameters, NewParameters));
      finally
        NewParameters.Free;
        OldParameters.Free;
      end;
    end;
  end
  else if MapRakuSelectedGradientStop(FContext, Layer, StopId, Color) then
  begin
    if Layer.Locked then
      Exit;
    OldStyle := Layer.PaintStyle;
    NewStyle := OldStyle;
    if not NewStyle.SetGradientStopOpacity(StopId, NewValue) then
      Exit;
    Layer.PaintStyle := NewStyle;
    Document.Changed;
    if not FOpacityGestureActive then
      AddAppliedCommand(FContext, TMapRakuSetLayerPaintStyleCommand.Create(
        Document, Layer, OldStyle, NewStyle));
    FContext.EditorState.CreationPaintStyle := NewStyle;
  end
  else if MapRakuUsesCreationPaint(FContext) then
  begin
    if FContext.EditorState <> nil then
    begin
      if FFrame.PaintStyle.Kind = slpkGradient then
        FContext.EditorState.CreationPaintStyle := FFrame.PaintStyle
      else
        FContext.EditorState.RectangleOpacity := NewValue;
    end;
  end
  else
  begin
    Command := nil;
    if not FOpacityGestureActive then
      Command := TVectArtCompoundCommand.Create;
    Document.BeginUpdate;
    try
      for Layer in MapRakuSelectedOpacityLayers(FContext) do
        if not Layer.Locked then
        begin
          OldValue := Layer.Opacity;
          if SameValue(OldValue, NewValue) then
            Continue;
          if Command <> nil then
            Command.Add(TMapRakuLayerOpacityCommand.Create(Document,
              Layer, OldValue, NewValue));
          Layer.Opacity := NewValue;
          Document.Changed;
        end;
    finally
      Document.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
    if FContext.EditorState <> nil then
      FContext.EditorState.RectangleOpacity := NewValue;
  end;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TMapRakuObjectColorController.OpacityGestureEnd(
  Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
begin
  if not FOpacityGestureActive then
    Exit;
  FOpacityGestureActive := False;
  if FOpacityGestureGradientLayer <> nil then
  begin
    if not FOpacityGestureOldPaintStyle.SameAs(FOpacityGestureGradientLayer.PaintStyle) then
      AddAppliedCommand(FContext, TMapRakuSetLayerPaintStyleCommand.Create(
        FContext.Document, FOpacityGestureGradientLayer, FOpacityGestureOldPaintStyle,
        FOpacityGestureGradientLayer.PaintStyle));
  end
  else if (FOpacityGestureFilter is TMapRakuShadowFilter) and
    (FOpacityGestureOldParameters <> nil) then
  begin
    if not SameValue(
      TMapRakuShadowFilter(FOpacityGestureOldParameters).Opacity,
      TMapRakuShadowFilter(FOpacityGestureFilter).Opacity) then
      AddAppliedCommand(FContext,
        TMapRakuSetFilterParametersCommand.Create(FContext.Document,
          FOpacityGestureFilter, FOpacityGestureOldParameters,
          FOpacityGestureFilter));
  end
  else
  begin
    Command := TVectArtCompoundCommand.Create;
    for I := 0 to Min(High(FOpacityStartLayers),
      High(FOpacityStartValues)) do
      if not SameValue(FOpacityStartValues[I],
        FOpacityStartLayers[I].Opacity) then
        Command.Add(TMapRakuLayerOpacityCommand.Create(FContext.Document,
          FOpacityStartLayers[I], FOpacityStartValues[I],
          FOpacityStartLayers[I].Opacity));
    if Command.Count > 0 then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
  end;
  FOpacityGestureGradientLayer := nil;
  FOpacityGestureFilter := nil;
  FOpacityGestureOldParameters.Free;
  FOpacityGestureOldParameters := nil;
  FOpacityStartLayers := nil;
  FOpacityStartValues := nil;
  if FOpacityDocumentUpdateActive then
  begin
    FOpacityDocumentUpdateActive := False;
    FContext.Document.EndInteractiveUpdate;
  end;
end;

procedure TMapRakuObjectColorController.OpacityGestureStart(
  Sender: TObject);
var
  Color: TColor;
  StopId: Integer;
  Filter: TMapRakuFilter;
  I: Integer;
  Layer: TVectArtLayer;
begin
  if FOpacityGestureActive or (FContext = nil) or
    (FContext.Document = nil) then
    Exit;
  if MapRakuSelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not (Filter is TMapRakuShadowFilter) then
      Exit;
    FOpacityGestureFilter := Filter;
    FOpacityGestureOldParameters := Filter.Clone;
  end
  else if MapRakuSelectedGradientStop(FContext, Layer, StopId, Color) then
  begin
    if Layer.Locked then
      Exit;
    FOpacityGestureGradientLayer := Layer;
    FOpacityGestureOldPaintStyle := Layer.PaintStyle;
  end
  else if MapRakuUsesCreationPaint(FContext) then
    Exit
  else
  begin
    FOpacityStartLayers := MapRakuSelectedOpacityLayers(FContext);
    if Length(FOpacityStartLayers) = 0 then
      Exit;
    for I := 0 to High(FOpacityStartLayers) do
      if FOpacityStartLayers[I].Locked then
      begin
        FOpacityStartLayers := nil;
        Exit;
      end;
    SetLength(FOpacityStartValues, Length(FOpacityStartLayers));
    for I := 0 to High(FOpacityStartLayers) do
      FOpacityStartValues[I] := FOpacityStartLayers[I].Opacity;
  end;
  FOpacityGestureActive := True;
  FContext.Document.BeginInteractiveUpdate;
  FOpacityDocumentUpdateActive := True;
end;

procedure TMapRakuObjectColorController.Refresh;
var
  DisplayStyle: TMapRakuPaintStyle;
  StopOpacity: Single;
  ColorEnabled: Boolean;
  ColorLayers: TArray<TVectArtLayer>;
  ColorValue: TColor;
  CreationPaintActive: Boolean;
  Filter: TMapRakuFilter;
  I: Integer;
  Layer: TVectArtLayer;
  OpacityEnabled: Boolean;
  OpacityLayers: TArray<TVectArtLayer>;
  StopId: Integer;
  Target: TMapRakuLayerColorTarget;
begin
  if FRefreshing then
    Exit;
  FRefreshing := True;
  try
    CreationPaintActive := MapRakuUsesCreationPaint(FContext);
    if FCreationTargetStateKnown and CreationPaintActive and
      not FLastUsesCreationPaint then
      AdoptVisiblePickerAsCreationPaint;
    FCreationTargetStateKnown := True;
    FLastUsesCreationPaint := CreationPaintActive;

    if MapRakuSelectedFilter(FContext, Layer, Filter) then
    begin
      FFrame.PaintModeEnabled := False;
      FFrame.TargetCaption := '色：' + Filter.DisplayName;
      ColorEnabled := not Layer.Locked and TryGetMapRakuFilterColor(Filter,
        ColorValue);
      FFrame.ColorEnabled := ColorEnabled;
      if ColorEnabled then
      begin
        FUpdatingColor := True;
        try
          FFrame.PaintStyle := TMapRakuPaintStyle.Solid(ColorValue);
        finally
          FUpdatingColor := False;
        end;
      end;
      OpacityEnabled := not Layer.Locked and
        (Filter is TMapRakuShadowFilter);
      FFrame.OpacityEnabled := OpacityEnabled;
      if Filter is TMapRakuShadowFilter then
        FFrame.Opacity := Round(EnsureRange(
          TMapRakuShadowFilter(Filter).Opacity, 0.0, 1.0) * 100)
      else
        FFrame.Opacity := 100;
      Exit;
    end;

    if CreationPaintActive then
    begin
      FFrame.PaintModeEnabled := True;
      FFrame.TargetCaption := '作成色';
      FFrame.ColorEnabled := True;
      FFrame.OpacityEnabled := True;
      FUpdatingColor := True;
      try
        FFrame.PaintStyle := FContext.EditorState.CreationPaintStyle;
      finally
        FUpdatingColor := False;
      end;
      if not (FFrame.PaintStyle.Kind in [slpkGradient, slpkPattern]) then
        FFrame.Opacity := Round(EnsureRange(FContext.EditorState.RectangleOpacity, 0.0, 1.0) * 100);
      Exit;
    end;

    FFrame.TargetCaption := '色';
    ColorLayers := MapRakuSelectedColorLayers(FContext);
    OpacityLayers := MapRakuSelectedOpacityLayers(FContext);
    if (Length(ColorLayers) = 0) and (Length(OpacityLayers) = 0) and
      (FContext <> nil) and (FContext.EditorState <> nil) then
    begin
      FFrame.PaintModeEnabled := True;
      FFrame.TargetCaption := '作成色';
      FFrame.ColorEnabled := True;
      FFrame.OpacityEnabled := True;
      FUpdatingColor := True;
      try
        FFrame.PaintStyle := FContext.EditorState.CreationPaintStyle;
      finally
        FUpdatingColor := False;
      end;
      if not (FFrame.PaintStyle.Kind in [slpkGradient, slpkPattern]) then
        FFrame.Opacity := Round(EnsureRange(FContext.EditorState.RectangleOpacity, 0.0, 1.0) * 100);
      Exit;
    end;
    ColorEnabled := Length(ColorLayers) > 0;
    FFrame.PaintModeEnabled := True;
    for I := 0 to High(ColorLayers) do
      ColorEnabled := ColorEnabled and not ColorLayers[I].Locked;
    FFrame.ColorEnabled := ColorEnabled;
    if (Length(ColorLayers) > 0) and
      TryGetMapRakuLayerColor(ColorLayers[0], ColorValue, Target) then
    begin
      FUpdatingColor := True;
      try
        if ColorLayers[0].PaintStyle.Kind = slpkGradient then
        begin
          FFrame.PaintStyle := ColorLayers[0].PaintStyle;
          if MapRakuSelectedGradientStop(FContext, Layer, StopId,
            ColorValue) then
          begin
            FFrame.GradientStopId := StopId;
            FFrame.TargetCaption := 'グラデーション色';
          end;
        end
        else
        begin
          DisplayStyle := ColorLayers[0].PaintStyle;
          DisplayStyle.SolidColor := ColorValue;
          FFrame.PaintStyle := DisplayStyle;
        end;
      finally
        FUpdatingColor := False;
      end;
    end;

    OpacityEnabled := Length(OpacityLayers) > 0;
    for I := 0 to High(OpacityLayers) do
      OpacityEnabled := OpacityEnabled and not OpacityLayers[I].Locked;
    FFrame.OpacityEnabled := OpacityEnabled;
    if MapRakuSelectedGradientStop(FContext, Layer, StopId, ColorValue) and
      Layer.PaintStyle.GetGradientStopOpacity(StopId, StopOpacity) then
    begin
      FFrame.OpacityEnabled := not Layer.Locked;
      FFrame.Opacity := Round(StopOpacity * 100);
    end
    else if (Length(OpacityLayers) > 0) and (FFrame.PaintStyle.Kind <> slpkPattern) then
      FFrame.Opacity := Round(EnsureRange(OpacityLayers[0].Opacity,
        0.0, 1.0) * 100);
  finally
    FRefreshing := False;
  end;
end;

procedure TMapRakuObjectColorController.SetContext(
  const Value: IVectArtDesignerContext);
begin
  if FColorGestureActive then
    ColorGestureEnd(Self);
  if FOpacityGestureActive then
    OpacityGestureEnd(Self);
  FPaintGesture.Finish;
  FContext := Value;
  FCreationTargetStateKnown := False;
  FLastUsesCreationPaint := False;
  Refresh;
end;

end.
