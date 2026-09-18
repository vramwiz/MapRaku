// 応答の共通ヘッダーと状態トークンを一箇所で定義し、各コマンドの形式を揃える。
unit MapRakuAutomationWire;
interface
uses System.JSON;
const
  SCREEN_LAYOUT_AUTOMATION_PIPE_SHORT_NAME = 'MapRaku.v1';
  SCREEN_LAYOUT_AUTOMATION_PIPE_NAME = '\\.\pipe\MapRaku.v1';
  SCREEN_LAYOUT_AUTOMATION_PROTOCOL = 'MapRaku';
  SCREEN_LAYOUT_AUTOMATION_VERSION = 2;
  MAX_REQUEST_CHARS = 4 * 1024 * 1024;
var
  AutomationPipeShortName: string = SCREEN_LAYOUT_AUTOMATION_PIPE_SHORT_NAME;
  AutomationHostKind: string = 'standalone';
function StateToken(const JsonText: string): string;
procedure AddHeader(Root: TJSONObject; const Command, Status: string);
function ErrorResponse(const Command, Code, MessageText: string): string;
function OkResponse(const Command: string; Payload: TJSONPair): string;
implementation
uses System.Hash, System.SysUtils, Winapi.Windows;
function StateToken(const JsonText: string): string;
begin Result := 'sha256:' + LowerCase(THashSHA2.GetHashString(JsonText)); end;
procedure AddHeader(Root: TJSONObject; const Command, Status: string);
begin
  Root.AddPair('protocol', SCREEN_LAYOUT_AUTOMATION_PROTOCOL);
  Root.AddPair('protocol_version', TJSONNumber.Create(SCREEN_LAYOUT_AUTOMATION_VERSION));
  Root.AddPair('pipe_name', AutomationPipeShortName);
  Root.AddPair('host_kind', AutomationHostKind);
  Root.AddPair('process_id', TJSONNumber.Create(GetCurrentProcessId));
  Root.AddPair('command', Command);
  Root.AddPair('status', Status);
end;
function ErrorResponse(const Command, Code, MessageText: string): string;
var Root, ErrorJson: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root,Command,'error');
    ErrorJson := TJSONObject.Create;
    ErrorJson.AddPair('code',Code); ErrorJson.AddPair('message',MessageText);
    Root.AddPair('error',ErrorJson);
    Result := Root.ToJSON;
  finally Root.Free; end;
end;
function OkResponse(const Command: string; Payload: TJSONPair): string;
var Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root,Command,'ok');
    if Payload <> nil then Root.AddPair(Payload);
    Result := Root.ToJSON;
  finally Root.Free; end;
end;
end.
