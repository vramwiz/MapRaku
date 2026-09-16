// 外部画像参照を保存先からの相対パスにし、同一フォルダの一時ファイルから置換保存する。
unit MapRakuFile;
interface
uses MapRakuDocument;
procedure SaveMapFile(Document: TVectArtDocument; const FileName: string);
implementation
uses Winapi.Windows, System.Generics.Collections, System.SysUtils, System.Classes, System.IOUtils, System.JSON, MapRakuDocumentJson;
procedure RelativeImages(Value: TJSONValue; const BaseFile: string);
var O: TJSONObject; A: TJSONArray; P: TJSONPair; I: Integer; Source: string;
begin
  if Value is TJSONArray then begin
    A := TJSONArray(Value);
    for I := 0 to A.Count - 1 do RelativeImages(A.Items[I],BaseFile);
  end else if Value is TJSONObject then begin
    O := TJSONObject(Value);
    if O.GetValue<string>('type','') = 'image' then begin
      Source := O.GetValue<string>('sourceFile','');
      if Source <> '' then begin
        P := O.RemovePair('sourceFile'); P.Free;
        O.AddPair('sourceFile',ExtractRelativePath(BaseFile,ExpandFileName(Source)));
      end;
    end;
    for I := 0 to O.Count - 1 do RelativeImages(O.Pairs[I].JsonValue,BaseFile);
  end;
end;
procedure SaveMapFile(Document: TVectArtDocument; const FileName: string);
var Root: TJSONValue; TempName, Target: string; Id: TGUID;
begin
  Target := ExpandFileName(FileName);
  CreateGUID(Id); TempName := Target + '.' + GUIDToString(Id) + '.tmp';
  Root := TJSONObject.ParseJSONValue(SerializeVectArtDocument(Document));
  try
    RelativeImages(Root,Target);
    TFile.WriteAllText(TempName,Root.ToJSON,TEncoding.UTF8);
    if not MoveFileEx(PChar(TempName),PChar(Target),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally
    Root.Free;
    if TFile.Exists(TempName) then TFile.Delete(TempName);
  end;
end;
end.
