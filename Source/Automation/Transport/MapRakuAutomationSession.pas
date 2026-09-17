// エディター生存期間内の再送記録・画像・固定した生成条件を保持する。
unit MapRakuAutomationSession;
interface
uses System.JSON, System.SysUtils, System.Generics.Collections, MapRakuAutomationBlobs;
type
  TAutomationReceipt = record
    RequestText, ResponseText: string;
  end;
  TAutomationSession = class
  private
    FReceipts: TDictionary<string,TAutomationReceipt>;
    FReceiptBytes: Int64;
  public
    Blobs: TAutomationBlobs;
    Conditions: TJSONObject;
    ReferenceToken: string;
    ReferenceImage: TBytes;
    constructor Create;
    destructor Destroy; override;
    function Lookup(const Id, RequestText: string; out ResponseText: string): Boolean;
    procedure Remember(const Id, RequestText, ResponseText: string);
    function Receipt(const Id: string): TJSONObject;
  end;
function AutomationSession: TAutomationSession;
procedure ResetAutomationSession;
implementation
uses System.Hash, MapRakuAutomationValues;
var Session: TAutomationSession;
constructor TAutomationSession.Create;
begin
  inherited;
  FReceipts := TDictionary<string,TAutomationReceipt>.Create;
  Blobs := TAutomationBlobs.Create;
end;
destructor TAutomationSession.Destroy;
begin
  Conditions.Free;
  Blobs.Free;
  FReceipts.Free;
  inherited;
end;
function TAutomationSession.Lookup(const Id, RequestText: string;
  out ResponseText: string): Boolean;
var R: TAutomationReceipt;
begin
  Require((Id <> '') and (Length(Id) <= 128), 'request_id is required (1..128 characters).');
  Result := FReceipts.TryGetValue(Id, R);
  if Result then begin
    Require(R.RequestText = THashSHA2.GetHashString(RequestText),
      'request_id was already used for a different request.');
    ResponseText := R.ResponseText;
  end else
    // 未照会の結果を追い出すと二重適用を招くので、容量超過時は新規変更を止める。
    Require((FReceipts.Count < 2048) and (FReceiptBytes < 16 * 1024 * 1024),
      'Receipt storage full; restart the editor before another mutation.');
end;
procedure TAutomationSession.Remember(const Id, RequestText, ResponseText: string);
var R: TAutomationReceipt;
begin
  R.RequestText := THashSHA2.GetHashString(RequestText);
  R.ResponseText := ResponseText;
  FReceipts.Add(Id, R);
  Inc(FReceiptBytes, Length(ResponseText) * SizeOf(Char));
end;
function TAutomationSession.Receipt(const Id: string): TJSONObject;
var R: TAutomationReceipt;
begin
  Result := TJSONObject.Create;
  Result.AddPair('known', TJSONBool.Create(FReceipts.TryGetValue(Id, R)));
  if FReceipts.ContainsKey(Id) then
    Result.AddPair('response', TJSONObject.ParseJSONValue(R.ResponseText));
end;
function AutomationSession: TAutomationSession;
begin
  if Session = nil then Session := TAutomationSession.Create;
  Result := Session;
end;
procedure ResetAutomationSession;
begin
  FreeAndNil(Session);
end;
initialization
  Session := nil;
finalization
  Session.Free;
end.
