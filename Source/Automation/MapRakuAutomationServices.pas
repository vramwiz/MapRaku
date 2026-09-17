// 画像転送・参照条件・保存コピー等、編集履歴を直接変更しないパイプ操作を仲介する。
unit MapRakuAutomationServices;
interface
uses System.JSON, MapRakuDocument, MapRakuCanvas;
function HandleAutomationService(const Command: string; Root: TJSONObject;
  Document: TVectArtDocument; Canvas: TVectArtCanvasControl): string;
function ReadAutomationFile(Root: TJSONObject): TJSONObject;
function AutomationMutation(const Command: string): Boolean;
implementation
uses System.SysUtils, System.IOUtils, MapRakuAutomationWire, MapRakuAutomationValues,
  MapRakuAutomationSession, MapRakuAutomationReference, MapRakuAutomationSchema,
  MapRakuAutomationValidation, MapRakuDocumentJson, MapRakuFile;
function AutomationMutation(const Command: string): Boolean;
begin
  Result := (Command = 'apply_batch') or (Command = 'replace_document') or
    (Command = 'undo') or (Command = 'redo') or (Command = 'set_reference') or
    (Command = 'clear_reference') or (Command = 'begin_blob') or
    (Command = 'load_file') or (Command = 'save_copy');
end;
function CheckedFileName(Root: TJSONObject): string;
begin
  Result := Str(Root,'path');
  Require(TPath.IsPathRooted(Result) and SameText(ExtractFileExt(Result),'.mapraku'),
    'path must be an absolute .mapraku filename.');
end;
function ReadAutomationFile(Root: TJSONObject): TJSONObject;
var D: TVectArtDocument; ErrorText: string; Skipped: Integer; Report: TJSONObject;
begin
  D := TVectArtDocument.Create;
  try
    Require(TryLoadVectArtDocumentFromJsonFile(CheckedFileName(Root),D,Skipped,ErrorText),ErrorText);
    Require(Skipped = 0,'File contains missing images; automatic load refused.');
    Report := ValidateAutomationMap(D); Report.Free;
    Result := TJSONObject.ParseJSONValue(SerializeVectArtDocument(D)) as TJSONObject;
  finally D.Free; end;
end;
function HandleAutomationService(const Command: string; Root: TJSONObject;
  Document: TVectArtDocument; Canvas: TVectArtCanvasControl): string;
var Payload: TJSONObject; Path: string; D: TVectArtDocument; ErrorText: string;
begin
  Result := ''; Payload := nil;
  if (Command = 'begin_blob') or (Command = 'write_blob') or
    (Command = 'read_blob') or (Command = 'release_blob') then
    Payload := AutomationSession.Blobs.Handle(Command,Root)
  else if Command = 'get_request_result' then Payload := AutomationSession.Receipt(Str(Root,'lookup_id'))
  else if Command = 'get_map_schema' then Payload := AutomationMapSchema
  else if Command = 'get_reference' then Payload := GetAutomationReference(Canvas)
  else if Command = 'clear_reference' then Payload := ClearAutomationReference(Canvas)
  else if Command = 'get_reference_image' then begin
    Require((Canvas <> nil) and (AutomationSession.ReferenceToken = Canvas.ReferenceBackgroundToken),
      'Reference image is no longer current.');
    Require(Length(AutomationSession.ReferenceImage) > 0, 'No reference image registered.');
    Payload := AutomationSession.Blobs.Store(AutomationSession.ReferenceImage,'image/png');
  end
  else if Command = 'set_reference' then Payload := SetAutomationReference(Root,Document,Canvas)
  else if Command = 'save_copy' then begin
    Path := CheckedFileName(Root);
    Require(not TFile.Exists(Path) or Bool(Root,'overwrite'), 'File exists; overwrite must be explicit.');
    SaveMapFile(Document,Path);
    Payload := TJSONObject.Create;
    Payload.AddPair('path',Path);
    Payload.AddPair('state_token',StateToken(SerializeVectArtDocument(Document)));
  end else if Command = 'validate_document' then begin
    D := TVectArtDocument.Create;
    try
      Require(TryDeserializeVectArtDocument(Obj(Root.GetValue('document')).ToJSON,D,ErrorText),ErrorText);
      Payload := ValidateAutomationMap(D);
    finally D.Free; end;
  end else if Command = 'preview_file' then begin
    Payload := TJSONObject.Create;
    try Payload.AddPair('document',ReadAutomationFile(Root));
    except Payload.Free; raise; end;
  end;
  if Payload <> nil then Result := OkResponse(Command,TJSONPair.Create('result',Payload));
end;
end.
