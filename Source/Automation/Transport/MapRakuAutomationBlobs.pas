// 画像等を有限容量のメモリに保持し、Named Pipeだけで分割送受信する。
unit MapRakuAutomationBlobs;
interface
uses System.JSON, System.SysUtils, System.Generics.Collections;
const
  AUTOMATION_CHUNK_BYTES = 192 * 1024;
  AUTOMATION_BLOB_BYTES = 16 * 1024 * 1024;
type
  TAutomationBlob = class
    Data: TBytes;
    Received: Integer;
    Mime: string;
    Digest: string;
  end;
  TAutomationBlobs = class
  private
    FItems: TObjectDictionary<string,TAutomationBlob>;
    FBytes: Int64;
    function Find(const Id: string): TAutomationBlob;
    function Allocate(Size: Integer; const Mime: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    function Store(const Data: TBytes; const Mime: string): TJSONObject;
    function Get(const Id: string; const Mime: string): TBytes;
    function Handle(const Command: string; Root: TJSONObject): TJSONObject;
  end;
implementation
uses System.NetEncoding, System.Hash, MapRakuAutomationValues;
constructor TAutomationBlobs.Create;
begin
  inherited;
  FItems := TObjectDictionary<string,TAutomationBlob>.Create([doOwnsValues]);
end;
destructor TAutomationBlobs.Destroy;
begin
  FItems.Free;
  inherited;
end;
function TAutomationBlobs.Find(const Id: string): TAutomationBlob;
begin
  Require(FItems.TryGetValue(Id, Result), 'Unknown blob_id.');
end;
function TAutomationBlobs.Allocate(Size: Integer; const Mime: string): string;
var Id: TGUID; B: TAutomationBlob;
begin
  Require((Size > 0) and (Size <= AUTOMATION_BLOB_BYTES), 'Blob must be 1..16 MiB.');
  // 勝手な追い出しは途中の転送を壊すため、満杯なら明示的なreleaseを求める。
  Require((FItems.Count < 32) and (FBytes + Size <= 64 * 1024 * 1024),
    'Blob storage full; release unused blobs.');
  CreateGUID(Id);
  Result := GUIDToString(Id);
  B := TAutomationBlob.Create;
  try
    SetLength(B.Data, Size);
    B.Mime := Mime;
    FItems.Add(Result, B);
  except
    B.Free;
    raise;
  end;
  Inc(FBytes, Size);
end;
function Descriptor(const Id: string; B: TAutomationBlob): TJSONObject;
var Hash: THashSHA2;
begin
  Result := TJSONObject.Create;
  Result.AddPair('blob_id', Id);
  Result.AddPair('mime', B.Mime);
  Result.AddPair('size', TJSONNumber.Create(Length(B.Data)));
  Result.AddPair('received', TJSONNumber.Create(B.Received));
  if B.Received = Length(B.Data) then begin
    if B.Digest = '' then begin
      Hash := THashSHA2.Create;
      Hash.Update(B.Data);
      B.Digest := LowerCase(Hash.HashAsString);
    end;
    Result.AddPair('sha256', B.Digest);
  end;
end;
function TAutomationBlobs.Store(const Data: TBytes; const Mime: string): TJSONObject;
var Id: string; B: TAutomationBlob;
begin
  Id := Allocate(Length(Data), Mime);
  B := Find(Id);
  B.Data := Copy(Data);
  B.Received := Length(Data);
  Result := Descriptor(Id, B);
end;
function TAutomationBlobs.Get(const Id, Mime: string): TBytes;
var B: TAutomationBlob;
begin
  B := Find(Id);
  Require(B.Received = Length(B.Data), 'Blob upload is incomplete.');
  Require(B.Mime = Mime, 'Unexpected blob MIME type.');
  Result := Copy(B.Data);
end;
function TAutomationBlobs.Handle(const Command: string; Root: TJSONObject): TJSONObject;
var Id, Encoded: string; B: TAutomationBlob; Data: TBytes; Offset, Count: Integer;
begin
  if Command = 'begin_blob' then begin
    Id := Allocate(Int(Root,'size',0,1,AUTOMATION_BLOB_BYTES), Str(Root,'mime'));
    Exit(Descriptor(Id, Find(Id)));
  end;
  Id := Str(Root,'blob_id');
  if Command = 'release_blob' then begin
    if FItems.TryGetValue(Id, B) then begin
      Dec(FBytes, Length(B.Data));
      FItems.Remove(Id);
    end;
    Exit(TJSONObject.Create);
  end;
  B := Find(Id);
  Offset := Int(Root,'offset',0,0,Length(B.Data));
  if Command = 'write_blob' then begin
    Encoded := Str(Root,'base64');
    Require(Length(Encoded) <= AUTOMATION_CHUNK_BYTES * 4 div 3, 'Chunk too large.');
    Data := TNetEncoding.Base64.DecodeStringToBytes(Encoded);
    Count := Length(Data);
    Require((Count > 0) and (Offset + Count <= Length(B.Data)), 'Invalid chunk range.');
    if Offset < B.Received then begin
      // 応答が失われた後の同一チャンク再送だけを許し、既受信部分の書換えは拒否する。
      Require((Offset + Count <= B.Received) and
        CompareMem(@B.Data[Offset], @Data[0], Count), 'Conflicting chunk retry.');
    end else begin
      Require(Offset = B.Received, 'Chunks must be uploaded in order.');
      Move(Data[0], B.Data[Offset], Count);
      Inc(B.Received, Count);
    end;
    Exit(Descriptor(Id, B));
  end;
  Require(Command = 'read_blob', 'Unknown blob command.');
  Require(B.Received = Length(B.Data), 'Blob upload is incomplete.');
  Count := Int(Root,'count',AUTOMATION_CHUNK_BYTES,1,AUTOMATION_CHUNK_BYTES);
  if Offset + Count > Length(B.Data) then Count := Length(B.Data) - Offset;
  Result := Descriptor(Id, B);
  Result.AddPair('offset', TJSONNumber.Create(Offset));
  Result.AddPair('base64', TNetEncoding.Base64.EncodeBytesToString(Copy(B.Data,Offset,Count)));
end;
end.
