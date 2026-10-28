program MapRakuCodexFixture;
{$APPTYPE CONSOLE}
// 実Codexを呼ばず、app-serverの正常完了・不正接続の修正・中止を再現する試験専用プロセス。
uses System.SysUtils, System.JSON, System.Generics.Collections, System.IOUtils,
  System.Hash, System.NetEncoding, Winapi.Windows;

procedure Send(Value: TJSONObject);
var Bytes: TBytes; Written: DWORD;
begin
  try
    Bytes := TEncoding.UTF8.GetBytes(Value.ToJSON+#10);
    if not WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),Bytes[0],Length(Bytes),Written,nil) then RaiseLastOSError;
  finally Value.Free; end;
end;

function ReplyFor(Request: TJSONObject; Repair: Boolean; Trace: Boolean = False): TJSONObject;
var Ops: string;
begin
  Ops := '{"operations":['+
    '{"op":"add","spec":{"kind":"road","id":"a","name":"試験道路A","vertices":[{"x":-100,"y":0},{"x":0,"y":0},{"x":100,"y":0}]}},'+
    '{"op":"add","spec":{"kind":"road","id":"b","name":"試験道路B","vertices":[{"x":0,"y":0},{"x":0,"y":100}]}}';
  if Trace then Ops := Ops+
    ',{"op":"add","spec":{"kind":"polygon","id":"fixture-poly","name":"不整形施設","color":14540253,"vertices":[{"x":120,"y":60},{"x":180,"y":40},{"x":200,"y":100},{"x":140,"y":120}]}},'+
    '{"op":"add","spec":{"kind":"text","id":"fixture-text","text":"施設","x":130,"y":60,"width":80,"height":30,"rotation":-30}}';
  if not Repair then Ops := Ops+',{"op":"connect","id":"b","endpoint":0,"target":"a","target_endpoint":1}';
  Ops := Ops+']}';
  Result := TJSONObject.Create;
  for var Field in TArray<string>.Create('generation_id','span_m','north_clockwise_degrees','canvas_width','canvas_height') do
    Result.AddPair(Field,Request.GetValue(Field).Clone as TJSONValue);
  Result.AddPair('outcome','ready').AddPair('place_label','通信試験の架空駅')
    .AddPair('latitude',TJSONNumber.Create(35)).AddPair('longitude',TJSONNumber.Create(139))
    .AddPair('message','app-server通信の疑似応答。実地図ではありません。')
    .AddPair('sources',TJSONObject.ParseJSONValue('[{"title":"試験用出典","url":"https://example.invalid/fixture"}]'))
    .AddPair('warnings',TJSONObject.ParseJSONValue('["疑似応答による検証"]')).AddPair('operations_json',Ops);
  if Repair and (GetEnvironmentVariable('MAPRAKU_CODEX_FIXTURE_MODE')='tamper') then begin
    Result.RemovePair('latitude').Free; Result.AddPair('latitude',TJSONNumber.Create(36));
  end;
end;

procedure SendItem(Item: TJSONObject);
begin
  Send(TJSONObject.Create.AddPair('method','item/completed').AddPair('params',TJSONObject.Create
    .AddPair('threadId','fixture-thread').AddPair('turnId','fixture-turn').AddPair('item',Item)));
end;
procedure FinishTurn;
begin
  Send(TJSONObject.ParseJSONValue('{"method":"turn/completed","params":{"threadId":"fixture-thread",'+
    '"turn":{"id":"fixture-turn","status":"completed"}}}') as TJSONObject);
end;
procedure GenerateFixtureImage;
var Item: TJSONObject; Mode, Path: string;
begin
  Mode := GetEnvironmentVariable('MAPRAKU_CODEX_FIXTURE_MODE');
  if Mode<>'image_missing' then begin
    Path := GetEnvironmentVariable('MAPRAKU_CODEX_FIXTURE_PNG');
    Item := TJSONObject.Create.AddPair('type','imageGeneration').AddPair('status','completed');
    if Mode='image_base64' then Item.AddPair('result',TNetEncoding.Base64.EncodeBytesToString(TFile.ReadAllBytes(Path)))
    else Item.AddPair('savedPath',Path);
    SendItem(Item);
  end else SendItem(TJSONObject.Create.AddPair('type','agentMessage').AddPair('text','画像のパスだけを返す試験応答'));
  FinishTurn;
end;

procedure CheckAttachedImage(Envelope, Params: TJSONObject);
var Path, Digest: string; Hash: THashSHA2;
begin
  Path := '';
  for var Value in TJSONArray(Params.GetValue('input')) do
    if TJSONObject(Value).GetValue('type').Value='localImage' then
      Path := TJSONObject(Value).GetValue('path').Value;
  if (Path='') or not TPath.IsPathRooted(Path) then raise Exception.Create('Native image attachment missing');
  Hash := THashSHA2.Create; Hash.Update(TFile.ReadAllBytes(Path)); Digest := LowerCase(Hash.HashAsString);
  if Digest<>Envelope.GetValue('source_image_sha256').Value then raise Exception.Create('Image input hash mismatch');
end;

procedure CompleteTurn(Params: TJSONObject);
var Envelope, Request, Reply, Item: TJSONObject; Trace: Boolean;
begin
  if GetEnvironmentVariable('MAPRAKU_CODEX_FIXTURE_MODE')='wait' then Sleep(60000);
  if Params.GetValue('outputSchema')=nil then begin GenerateFixtureImage; Exit; end;
  Envelope := TJSONObject.ParseJSONValue(TJSONObject(TJSONArray(Params.GetValue('input'))[0]).GetValue('text').Value) as TJSONObject;
  try
    Request := Envelope.GetValue('request') as TJSONObject;
    Trace := Envelope.GetValue('source_image_sha256')<>nil;
    if Trace then CheckAttachedImage(Envelope,Params);
    Reply := ReplyFor(Request,Envelope.GetValue('validation_error')<>nil,Trace);
    if Trace then begin
      Reply.AddPair('trace_options_token',Request.GetValue('trace_options_token').Value);
      if GetEnvironmentVariable('MAPRAKU_CODEX_FIXTURE_MODE')='image_hash_mismatch' then Reply.AddPair('source_image_sha256','wrong-image')
      else Reply.AddPair('source_image_sha256',Envelope.GetValue('source_image_sha256').Value);
    end;
    try
      if not Trace and (Envelope.GetValue('validation_error')=nil) then
        Send(TJSONObject.ParseJSONValue('{"method":"item/completed","params":{"threadId":"fixture-thread",'+
          '"turnId":"fixture-turn","item":{"type":"webSearch","id":"fixture-search"}}}') as TJSONObject);
      Item := TJSONObject.Create.AddPair('type','agentMessage').AddPair('phase','final_answer').AddPair('text',Reply.ToJSON);
      SendItem(Item); FinishTurn;
    finally Reply.Free; end;
  finally Envelope.Free; end;
end;

var Line, Method: string; MessageValue, Params, Response: TJSONObject;
begin
  SetTextCodePage(Input,CP_UTF8);
  while not Eof(Input) do begin
    Readln(Line); MessageValue := TJSONObject.ParseJSONValue(Line) as TJSONObject;
    if MessageValue=nil then Continue;
    try
      Method := MessageValue.GetValue('method').Value;
      if Method='initialized' then Continue;
      Params := MessageValue.GetValue('params') as TJSONObject;
      Response := TJSONObject.Create.AddPair('id',MessageValue.GetValue('id').Clone as TJSONValue);
      if Method='initialize' then Response.AddPair('result',TJSONObject.Create)
      else if Method='thread/start' then Response.AddPair('result',TJSONObject.ParseJSONValue('{"thread":{"id":"fixture-thread"}}'))
      else Response.AddPair('result',TJSONObject.ParseJSONValue('{"turn":{"id":"fixture-turn"}}'));
      Send(Response);
      if Method='turn/start' then CompleteTurn(Params);
    finally MessageValue.Free; end;
  end;
end.
