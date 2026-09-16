// キャンバス操作と属性UIが共有する描画スタイル変更をUndo／Redo可能にする。
unit MapRakuPaintCommands;

interface

uses
  MapRakuDocument, MapRakuEditCommands, MapRakuPaintStyles;

type
  TMapRakuSetLayerPaintStyleCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FNewValue: TMapRakuPaintStyle;
    FOldValue: TMapRakuPaintStyle;
    procedure Apply(const Value: TMapRakuPaintStyle);
  public
    // 適用前後の描画スタイルを値として保持し、同じレイヤーへ復元できるようにする。
    constructor Create(Document: TVectArtDocument; Layer: TVectArtLayer;
      const OldValue, NewValue: TMapRakuPaintStyle);
    // 保存した変更後の描画スタイルを反映し、Documentへ変更を通知する。
    procedure Execute; override;
    // 保存した変更前の描画スタイルを復元し、Documentへ変更を通知する。
    procedure Undo; override;
  end;

implementation

procedure TMapRakuSetLayerPaintStyleCommand.Apply(
  const Value: TMapRakuPaintStyle);
begin
  if (FDocument = nil) or (FLayer = nil) then
    Exit;
  FLayer.PaintStyle := Value;
  FDocument.Changed;
end;

constructor TMapRakuSetLayerPaintStyleCommand.Create(
  Document: TVectArtDocument; Layer: TVectArtLayer;
  const OldValue, NewValue: TMapRakuPaintStyle);
begin
  inherited Create;
  FDocument := Document;
  FLayer := Layer;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TMapRakuSetLayerPaintStyleCommand.Execute;
begin
  Apply(FNewValue);
end;

procedure TMapRakuSetLayerPaintStyleCommand.Undo;
begin
  Apply(FOldValue);
end;

end.
