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
  begin
    Result := TryDeserializeVectArtDocument(SerializedData, Document,
      ErrorMessage);
    if Result then Document.CanvasLayer.Transparent := True;
    Exit;
  end;
  if (OutputWidth > 0) and (OutputHeight > 0) and
    (OutputWidth <= MAX_PLUGIN_CANVAS_DIMENSION) and
    (OutputHeight <= MAX_PLUGIN_CANVAS_DIMENSION) then
    Document.SetCanvasSize(OutputWidth, OutputHeight);
  // ホスト映像を編集画面の下地に表示し、空の地図を白く見せない。
  Document.CanvasLayer.Transparent := True;
  Result := True;
end;

end.
