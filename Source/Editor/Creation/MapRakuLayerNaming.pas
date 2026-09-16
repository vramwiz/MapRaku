// 新規レイヤーへ重複しない表示名を割り当てる共通規則を提供する。
unit MapRakuLayerNaming;

interface

uses
  MapRakuDocument;

// Prefixと連番を組み合わせ、Document内で未使用の最初の名前を返す。
function NextMapRakuLayerName(Document: TVectArtDocument;
  const Prefix: string): string;

implementation

uses
  System.SysUtils;

function NextMapRakuLayerName(Document: TVectArtDocument;
  const Prefix: string): string;
var
  Candidate: string;
  Found: Boolean;
  I: Integer;
  Number: Integer;
begin
  Number := 1;
  repeat
    Candidate := Prefix + ' ' + Number.ToString;
    Found := False;
    for I := 1 to Document.LayerCount - 1 do
      if SameText(Document[I].Name, Candidate) then
      begin
        Found := True;
        Break;
      end;
    Inc(Number);
  until not Found;
  Result := Candidate;
end;

end.
