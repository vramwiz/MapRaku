// 複数レイヤーの共通塗り連続変更を1件のUndoへまとめる。
unit MapRakuPaintStyleGesture;

interface

uses MapRakuContext, MapRakuDocument, MapRakuPaintStyles;

type
  TMapRakuPaintStyleGesture = class
  private
    FContext: IVectArtDesignerContext;       // 操作中だけ保持する対象文書と履歴。
    FLayers: TArray<TVectArtLayer>;          // 開始時に確定した変更対象。
    FStyles: TArray<TMapRakuPaintStyle>; // 変更前の不変スナップショット。
  public
    // 選択中の未ロック対象を確定し、対話更新を開始する。
    procedure Start(const Context: IVectArtDesignerContext);
    // 開始時の対象だけへ値を反映する。未開始ならFalseを返す。
    function Apply(const Style: TMapRakuPaintStyle): Boolean;
    // 変更がある対象を複合履歴へ追加し、対話更新を閉じる。
    procedure Finish;
    // 終了漏れがあれば操作を確定して参照を解放する。
    destructor Destroy; override;
  end;

implementation

uses System.Generics.Collections, MapRakuColorTargets, MapRakuEditCommands,
  MapRakuPaintCommands, MapRakuObjectPropertySelection;

procedure TMapRakuPaintStyleGesture.Start(const Context: IVectArtDesignerContext);
var Layer: TVectArtLayer; Targets: TList<TVectArtLayer>; I: Integer;
begin
  Finish;
  if (Context = nil) or (Context.Document = nil) or MapRakuUsesCreationPaint(Context) then Exit;
  Targets := TList<TVectArtLayer>.Create;
  try
    for Layer in MapRakuSelectedColorLayers(Context) do if not Layer.Locked then Targets.Add(Layer);
    FLayers := Targets.ToArray;
  finally
    Targets.Free;
  end;
  if Length(FLayers) = 0 then Exit;
  SetLength(FStyles, Length(FLayers));
  for I := 0 to High(FLayers) do FStyles[I] := FLayers[I].PaintStyle;
  FContext := Context;
  FContext.Document.BeginInteractiveUpdate;
end;

function TMapRakuPaintStyleGesture.Apply(const Style: TMapRakuPaintStyle): Boolean;
var Layer: TVectArtLayer;
begin
  Result := FContext <> nil;
  if not Result then Exit;
  for Layer in FLayers do
    if not Layer.PaintStyle.SameAs(Style) then
    begin
      Layer.PaintStyle := Style;
      FContext.Document.Changed;
    end;
end;

procedure TMapRakuPaintStyleGesture.Finish;
var Command: TVectArtCompoundCommand; I: Integer; Context: IVectArtDesignerContext;
begin
  if FContext = nil then Exit;
  Context := FContext;
  FContext := nil;
  Command := TVectArtCompoundCommand.Create;
  try
    for I := 0 to High(FLayers) do
      if not FStyles[I].SameAs(FLayers[I].PaintStyle) then
        Command.Add(TMapRakuSetLayerPaintStyleCommand.Create(Context.Document,
          FLayers[I], FStyles[I], FLayers[I].PaintStyle));
    if (Command.Count > 0) and (Context.EditHistory <> nil) then
    begin
      Context.EditHistory.AddApplied(Command);
      Command := nil;
    end;
  finally
    Command.Free;
    FLayers := nil;
    FStyles := nil;
    Context.Document.EndInteractiveUpdate;
  end;
end;

destructor TMapRakuPaintStyleGesture.Destroy;
begin
  Finish;
  inherited;
end;

end.
