// AviUtl2から編集画面へ渡すDocumentの読込と、新規キャンバス寸法の決定を担当する。
unit MapRakuPluginDocument;

interface

uses
  MapRakuDocument;

// 保存済みデータを優先して読み込み、未保存時だけ有効な出力寸法をキャンバスへ適用する。
function InitializeMapRakuPluginDocument(Document: TVectArtDocument;
  const SerializedData: string; OutputWidth, OutputHeight: Integer;
  out ErrorMessage: string): Boolean;

implementation

uses
  MapRakuDocumentJson;

const
  MAX_PLUGIN_CANVAS_DIMENSION = 16384; // 異常な映像寸法による巨大Document生成を防ぐ上限。

function InitializeMapRakuPluginDocument(Document: TVectArtDocument;
  const SerializedData: string; OutputWidth, OutputHeight: Integer;
  out ErrorMessage: string): Boolean;
begin
  ErrorMessage := '';
  if Document = nil then
  begin
    ErrorMessage := 'Document is not assigned';
    Exit(False);
  end;
  if SerializedData <> '' then
    Exit(TryDeserializeVectArtDocument(SerializedData, Document,
      ErrorMessage));
  if (OutputWidth > 0) and (OutputHeight > 0) and
    (OutputWidth <= MAX_PLUGIN_CANVAS_DIMENSION) and
    (OutputHeight <= MAX_PLUGIN_CANVAS_DIMENSION) then
    Document.SetCanvasSize(OutputWidth, OutputHeight);
  Result := True;
end;

end.
