// 配置DocumentのJSON入出力を、呼び出し側へ単一の窓口として公開する。
unit MapRakuDocumentJson;

interface

uses
  MapRakuDocument;

// Documentを現行の埋め込み用JSONへ変換する。
function SerializeVectArtDocument(Document: TVectArtDocument): string;
// 専用JSONをDocumentへ適用する。旧形式との互換変換は行わない。
function TryDeserializeVectArtDocument(const Text: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
// JSONファイルを読み込み、存在しない外部参照だけを除外してDocumentへ適用する。
function TryLoadVectArtDocumentFromJsonFile(const FileName: string;
  Document: TVectArtDocument; out SkippedReferenceCount: Integer;
  out ErrorMessage: string): Boolean;

implementation

uses
  MapRakuDocumentJsonReader, MapRakuDocumentJsonWriter;

function SerializeVectArtDocument(Document: TVectArtDocument): string;
begin
  Result := MapRakuDocumentJsonWriter.SerializeVectArtDocument(Document);
end;

function TryDeserializeVectArtDocument(const Text: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
begin
  Result := MapRakuDocumentJsonReader.TryDeserializeVectArtDocument(
    Text, Document, ErrorMessage);
end;

function TryLoadVectArtDocumentFromJsonFile(const FileName: string;
  Document: TVectArtDocument; out SkippedReferenceCount: Integer;
  out ErrorMessage: string): Boolean;
begin
  Result := MapRakuDocumentJsonReader.TryLoadVectArtDocumentFromJsonFile(
    FileName, Document, SkippedReferenceCount, ErrorMessage);
end;

end.
