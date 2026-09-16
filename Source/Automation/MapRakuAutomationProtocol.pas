// Codex向けMapRaku専用JSONプロトコルを解析し、Documentと履歴へ安全に接続する。
unit MapRakuAutomationProtocol;

interface

uses
  MapRakuDocument, MapRakuEditHistory, MapRakuEditorState, MapRakuCanvas;

const
  SCREEN_LAYOUT_AUTOMATION_PIPE_SHORT_NAME = 'MapRaku.v1';
  SCREEN_LAYOUT_AUTOMATION_PIPE_NAME = '\\.\pipe\MapRaku.v1';
  SCREEN_LAYOUT_AUTOMATION_PROTOCOL = 'MapRaku';
  SCREEN_LAYOUT_AUTOMATION_VERSION = 1;

// VCLスレッド上で1要求を処理し、必ずJSON応答を返す。
function HandleMapRakuAutomationRequest(const RequestText: string;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl = nil): string;

implementation

uses
  System.Hash, System.JSON, System.SysUtils, Vcl.Graphics,
  MapRakuAutomationVisuals, MapRakuAutomationText, MapRakuAutomationLayout,
  MapRakuAutomationDocumentCommand, MapRakuDocumentJson;

const
  MAX_REQUEST_CHARS = 4 * 1024 * 1024;

function StateToken(const JsonText: string): string;
begin
  Result := 'sha256:' + LowerCase(THashSHA2.GetHashString(JsonText));
end;

procedure AddHeader(Root: TJSONObject; const Command, Status: string);
begin
  Root.AddPair('protocol', SCREEN_LAYOUT_AUTOMATION_PROTOCOL);
  Root.AddPair('protocol_version', TJSONNumber.Create(
    SCREEN_LAYOUT_AUTOMATION_VERSION));
  Root.AddPair('command', Command);
  Root.AddPair('status', Status);
end;

function ErrorResponse(const Command, Code, MessageText: string): string;
var
  ErrorJson: TJSONObject;
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Command, 'error');
    ErrorJson := TJSONObject.Create;
    ErrorJson.AddPair('code', Code);
    ErrorJson.AddPair('message', MessageText);
    Root.AddPair('error', ErrorJson);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function OkResponse(const Command: string; Payload: TJSONPair): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Command, 'ok');
    if Payload <> nil then
      Root.AddPair(Payload);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function JsonString(Root: TJSONObject; const Name: string;
  out Value: string): Boolean;
var
  JsonValue: TJSONValue;
begin
  JsonValue := Root.GetValue(Name);
  Result := JsonValue is TJSONString;
  if Result then
    Value := TJSONString(JsonValue).Value
  else
    Value := '';
end;

function ApplyRequested(Root: TJSONObject): Boolean;
var
  Value: TJSONValue;
begin
  Value := Root.GetValue('apply');
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

function ValidateIncomingDocument(Root: TJSONObject;
  out NormalizedJson, ErrorMessage: string): Boolean;
var
  Incoming: TJSONValue;
  TempDocument: TVectArtDocument;
begin
  Result := False;
  NormalizedJson := '';
  ErrorMessage := '';
  Incoming := Root.GetValue('document');
  if not (Incoming is TJSONObject) then
  begin
    ErrorMessage := 'document must be a JSON object.';
    Exit;
  end;
  TempDocument := TVectArtDocument.Create;
  try
    if not TryDeserializeVectArtDocument(Incoming.ToJSON, TempDocument,
      ErrorMessage) then
      Exit;
    NormalizedJson := SerializeVectArtDocument(TempDocument);
    Result := True;
  finally
    TempDocument.Free;
  end;
end;

function BuildCapabilities(const Command: string): string;
var
  Commands: TJSONArray;
  ResultJson: TJSONObject;
begin
  ResultJson := TJSONObject.Create;
  Commands := TJSONArray.Create;
  Commands.Add('get_capabilities');
  Commands.Add('get_editor_state');
  Commands.Add('get_document');
  Commands.Add('get_canvas_snapshot');
  Commands.Add('render_preview');
  Commands.Add('measure_text');
  Commands.Add('list_fonts');
  Commands.Add('get_layout_geometry');
  Commands.Add('get_creation_schema');
  Commands.Add('preview_replace_document');
  Commands.Add('replace_document');
  Commands.Add('undo');
  Commands.Add('redo');
  ResultJson.AddPair('commands', Commands);
  ResultJson.AddPair('pipe', SCREEN_LAYOUT_AUTOMATION_PIPE_NAME);
  ResultJson.AddPair('max_image_edge', TJSONNumber.Create(2048));
  ResultJson.AddPair('image_transport', 'local_png_path');
  ResultJson.AddPair('background_token_supported', TJSONBool.Create(True));
  ResultJson.AddPair('max_request_bytes', TJSONNumber.Create(
    MAX_REQUEST_CHARS));
  Result := OkResponse(Command, TJSONPair.Create('capabilities', ResultJson));
end;

function BuildEditorState(const Command: string; Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory): string;
var
  DocumentJson: string;
  State: TJSONObject;
begin
  DocumentJson := SerializeVectArtDocument(Document);
  State := TJSONObject.Create;
  State.AddPair('state_token', StateToken(DocumentJson));
  State.AddPair('canvas_width', TJSONNumber.Create(Document.CanvasLayer.Width));
  State.AddPair('canvas_height', TJSONNumber.Create(Document.CanvasLayer.Height));
  State.AddPair('layer_count', TJSONNumber.Create(Document.LayerCount - 1));
  State.AddPair('selection_count', TJSONNumber.Create(Document.SelectionCount));
  State.AddPair('can_undo', TJSONBool.Create(EditHistory.CanUndo));
  State.AddPair('can_redo', TJSONBool.Create(EditHistory.CanRedo));
  Result := OkResponse(Command, TJSONPair.Create('editor', State));
end;

function BuildDocument(const Command: string;
  Document: TVectArtDocument): string;
var
  DocumentJson: string;
  DocumentValue: TJSONValue;
  Root: TJSONObject;
begin
  DocumentJson := SerializeVectArtDocument(Document);
  DocumentValue := TJSONObject.ParseJSONValue(DocumentJson);
  if DocumentValue = nil then
    Exit(ErrorResponse(Command, 'serialize_failed',
      'The current document could not be encoded as JSON.'));
  Root := TJSONObject.Create;
  Root.AddPair('state_token', StateToken(DocumentJson));
  Root.AddPair('document', DocumentValue);
  Result := OkResponse(Command, TJSONPair.Create('snapshot', Root));
end;

function HandleReplace(const Command: string; Root: TJSONObject;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Apply: Boolean): string;
var
  CurrentJson: string;
  ErrorMessage: string;
  ExpectedToken: string;
  NormalizedJson: string;
  ResultJson: TJSONObject;
  ReplaceCommand: TMapRakuAutomationDocumentCommand;
begin
  CurrentJson := SerializeVectArtDocument(Document);
  if not JsonString(Root, 'state_token', ExpectedToken) then
    Exit(ErrorResponse(Command, 'state_token_required',
      'state_token is required.'));
  if ExpectedToken <> StateToken(CurrentJson) then
    Exit(ErrorResponse(Command, 'state_changed',
      'The editor document changed. Get a new snapshot before retrying.'));
  if not ValidateIncomingDocument(Root, NormalizedJson, ErrorMessage) then
    Exit(ErrorResponse(Command, 'invalid_document', ErrorMessage));
  if Apply and not ApplyRequested(Root) then
    Exit(ErrorResponse(Command, 'apply_required',
      'replace_document requires apply: true.'));

  if Apply and (NormalizedJson <> CurrentJson) then
  begin
    if EditorState <> nil then
      EditorState.OpenGroup := nil;
    ReplaceCommand := TMapRakuAutomationDocumentCommand.Create(
      Document, CurrentJson, NormalizedJson);
    try
      ReplaceCommand.Execute;
      EditHistory.AddApplied(ReplaceCommand);
      ReplaceCommand := nil;
    finally
      ReplaceCommand.Free;
    end;
    NormalizedJson := SerializeVectArtDocument(Document);
  end;

  ResultJson := TJSONObject.Create;
  ResultJson.AddPair('applied', TJSONBool.Create(Apply));
  ResultJson.AddPair('changed', TJSONBool.Create(NormalizedJson <> CurrentJson));
  ResultJson.AddPair('state_token', StateToken(NormalizedJson));
  Result := OkResponse(Command, TJSONPair.Create('change', ResultJson));
end;

function HandleHistory(const Command: string; Root: TJSONObject;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; UndoOperation: Boolean): string;
var
  CurrentJson: string;
  ExpectedToken: string;
  ResultJson: TJSONObject;
begin
  CurrentJson := SerializeVectArtDocument(Document);
  if not JsonString(Root, 'state_token', ExpectedToken) or
    (ExpectedToken <> StateToken(CurrentJson)) then
    Exit(ErrorResponse(Command, 'state_changed',
      'Get the current editor state before changing history.'));
  if not ApplyRequested(Root) then
    Exit(ErrorResponse(Command, 'apply_required',
      Command + ' requires apply: true.'));
  if UndoOperation and not EditHistory.CanUndo then
    Exit(ErrorResponse(Command, 'undo_unavailable', 'There is nothing to undo.'));
  if not UndoOperation and not EditHistory.CanRedo then
    Exit(ErrorResponse(Command, 'redo_unavailable', 'There is nothing to redo.'));
  if EditorState <> nil then
    EditorState.OpenGroup := nil;
  if UndoOperation then
    EditHistory.Undo
  else
    EditHistory.Redo;
  CurrentJson := SerializeVectArtDocument(Document);
  ResultJson := TJSONObject.Create;
  ResultJson.AddPair('applied', TJSONBool.Create(True));
  ResultJson.AddPair('state_token', StateToken(CurrentJson));
  Result := OkResponse(Command, TJSONPair.Create('change', ResultJson));
end;

function CheckVisualState(const Command: string; Root: TJSONObject;
  Document: TVectArtDocument; Canvas: TVectArtCanvasControl;
  RequireTokens: Boolean): string;
var
  Token: string;
begin
  Result := '';
  if Canvas = nil then
    Exit(ErrorResponse(Command, 'editor_unavailable', 'Canvas is not available.'));
  if Canvas.TextEditing or Canvas.TransformDragging then
    Exit(ErrorResponse(Command, 'editor_busy', 'Finish the current text edit or transform first.'));
  if RequireTokens then
    if not JsonString(Root, 'state_token', Token) or
      (Token <> StateToken(SerializeVectArtDocument(Document))) then
      Exit(ErrorResponse(Command, 'state_changed', 'Get a new canvas snapshot.'));
  if RequireTokens or (Root.GetValue('background_token') <> nil) then
    if not JsonString(Root, 'background_token', Token) or
      (Token <> Canvas.ReferenceBackgroundToken) then
      Exit(ErrorResponse(Command, 'background_changed', 'Get a new canvas snapshot.'));
end;

function HandleVisual(const Command: string; Root: TJSONObject;
  Document: TVectArtDocument; Canvas: TVectArtCanvasControl; Preview: Boolean): string;
var
  Target: TVectArtDocument;
  Background: TBitmap;
  Snapshot, Images: TJSONObject;
  JsonText, ErrorMessage: string;
  MaxEdge: Integer;
  Value: TJSONValue;
begin
  Result := CheckVisualState(Command, Root, Document, Canvas, Preview);
  if Result <> '' then Exit;
  MaxEdge := 1280;
  Value := Root.GetValue('max_edge');
  if Value <> nil then
    if not (Value is TJSONNumber) or not TryStrToInt(Value.Value, MaxEdge) then
      Exit(ErrorResponse(Command, 'invalid_argument', 'max_edge must be an integer.'));
  if (MaxEdge < 64) or (MaxEdge > 2048) then
    Exit(ErrorResponse(Command, 'invalid_argument', 'max_edge must be from 64 to 2048.'));
  Target := nil;
  Background := TBitmap.Create;
  Snapshot := TJSONObject.Create;
  try
    JsonText := SerializeVectArtDocument(Document);
    Snapshot.AddPair('state_token', StateToken(JsonText));
    Snapshot.AddPair('background_token', Canvas.ReferenceBackgroundToken);
    if Preview then
    begin
      if not ValidateIncomingDocument(Root, JsonText, ErrorMessage) then
        Exit(ErrorResponse(Command, 'invalid_document', ErrorMessage));
      Target := TVectArtDocument.Create;
      if not TryDeserializeVectArtDocument(JsonText, Target, ErrorMessage) then
        Exit(ErrorResponse(Command, 'invalid_document', ErrorMessage));
    end;
    Canvas.CopyReferenceBackground(Background);
    if Preview then
      Images := BuildMapRakuAutomationImages(Target, Background, MaxEdge)
    else
      Images := BuildMapRakuAutomationImages(Document, Background, MaxEdge);
    Snapshot.AddPair('images', Images);
    Snapshot.AddPair('document', TJSONObject.ParseJSONValue(JsonText));
    Snapshot.AddPair('candidate_state_token', StateToken(JsonText));
    Snapshot.AddPair('applied', TJSONBool.Create(False));
    Result := OkResponse(Command, TJSONPair.Create('snapshot', Snapshot));
    Snapshot := nil;
  finally
    Snapshot.Free;
    Background.Free;
    Target.Free;
  end;
end;

function HandleMapRakuAutomationRequest(const RequestText: string;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl): string;
var
  Command: string;
  Json: TJSONValue;
  Root: TJSONObject;
  Geometry: TJSONObject;
begin
  Command := '';
  if TEncoding.UTF8.GetByteCount(RequestText) > MAX_REQUEST_CHARS then
    Exit(ErrorResponse(Command, 'request_too_large',
      'The request exceeds the 4 MiB limit.'));
  if (Document = nil) or (EditHistory = nil) then
    Exit(ErrorResponse(Command, 'editor_unavailable',
      'The MapRaku editor is not ready.'));
  Json := TJSONObject.ParseJSONValue(RequestText);
  try
    try
      if not (Json is TJSONObject) then
        Exit(ErrorResponse(Command, 'invalid_json',
          'Request must be a JSON object.'));
      Root := TJSONObject(Json);
      if not JsonString(Root, 'command', Command) then
        Exit(ErrorResponse(Command, 'invalid_command', 'command is required.'));
      if SameText(Command, 'get_capabilities') then
        Result := BuildCapabilities(Command)
      else if SameText(Command, 'get_editor_state') then
        Result := BuildEditorState(Command, Document, EditHistory)
      else if SameText(Command, 'get_document') then
        Result := BuildDocument(Command, Document)
      else if SameText(Command, 'get_canvas_snapshot') then
        Result := HandleVisual(Command, Root, Document, Canvas, False)
      else if SameText(Command, 'render_preview') then
        Result := HandleVisual(Command, Root, Document, Canvas, True)
      else if SameText(Command, 'measure_text') then
        Result := OkResponse(Command, TJSONPair.Create('measurement', MeasureMapRakuAutomationText(Root)))
      else if SameText(Command, 'list_fonts') then
        Result := OkResponse(Command, TJSONPair.Create('fonts', MapRakuAutomationFonts))
      else if SameText(Command, 'get_creation_schema') then
        Result := OkResponse(Command, TJSONPair.Create('schema', MapRakuAutomationCreationSchema))
      else if SameText(Command, 'get_layout_geometry') then
      begin
        Geometry := MapRakuAutomationGeometry(Document);
        Geometry.AddPair('state_token', StateToken(SerializeVectArtDocument(Document)));
        Result := OkResponse(Command, TJSONPair.Create('geometry', Geometry));
      end
      else if SameText(Command, 'preview_replace_document') then
        Result := HandleReplace(Command, Root, Document, EditHistory,
          EditorState, False)
      else if SameText(Command, 'replace_document') then
      begin
        if Root.GetValue('background_token') <> nil then
        begin
          Result := CheckVisualState(Command, Root, Document, Canvas, True);
          if Result <> '' then Exit;
        end;
        Result := HandleReplace(Command, Root, Document, EditHistory,
          EditorState, True);
      end
      else if SameText(Command, 'undo') then
        Result := HandleHistory(Command, Root, Document, EditHistory,
          EditorState, True)
      else if SameText(Command, 'redo') then
        Result := HandleHistory(Command, Root, Document, EditHistory,
          EditorState, False)
      else
        Result := ErrorResponse(Command, 'unknown_command',
          'The command is not supported.');
    except
      on E: EArgumentException do
        Result := ErrorResponse(Command, 'invalid_argument', E.Message);
      on E: Exception do
        Result := ErrorResponse(Command, 'internal_error', E.Message);
    end;
  finally
    Json.Free;
  end;
end;

end.
