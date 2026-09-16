// AviUtl2の映像コールバックをオブジェクト固有のコンテキストへ接続する。
unit PluginFilterContextManager;

interface

uses
  System.Generics.Collections, System.SyncObjs, AviUtl2FilterTypes;

type
  TPluginFilterContextItem = class
  private
    FEffectID: Int64;
    FFrameE: Integer;
    FFrameS: Integer;
    FLayer: Integer;
    FObjectID: Int64;
  public
    property EffectID: Int64 read FEffectID;
    property FrameE: Integer read FFrameE;
    property FrameS: Integer read FFrameS;
    property Layer: Integer read FLayer;
    property ObjectID: Int64 read FObjectID;
  end;

  TPluginFilterContextList<T: TPluginFilterContextItem, constructor> = class(TObjectList<T>)
  private
    FLock: TCriticalSection;
    function FindByKeyUnlocked(const AObjectID, AEffectID: Int64): T;
    function FindByObjectLocationUnlocked(ALayer, AFrameS, AFrameE: Integer): T;
  protected
    // 映像コールバックからAviUtl2オブジェクトの固有IDを取得する。
    function TryGetObjectID(Video: PFILTER_PROC_VIDEO; out AObjectID: Int64): Boolean; virtual;
    // 生成直後のコンテキストに固有IDとプラグイン固有の初期値を設定する。
    procedure InitNewContext(const Context: T; const AObjectID,
      AEffectID: Int64); virtual;
  public
    constructor Create;
    destructor Destroy; override;
    // 対象オブジェクトのコンテキストを取得し、未生成なら一度だけ生成する。
    function GetContext(Video: PFILTER_PROC_VIDEO): T;
    // 固有IDに対応する生成済みコンテキストを返す。未生成ならnilを返す。
    function FindByKey(const AObjectID, AEffectID: Int64): T;
    // 編集APIで取得できるレイヤーと配置範囲から生成済みコンテキストを取得する。
    function FindByObjectLocation(ALayer, AFrameS, AFrameE: Integer): T;
  end;

implementation

constructor TPluginFilterContextList<T>.Create;
begin
  inherited Create(True);
  FLock := TCriticalSection.Create;
end;

destructor TPluginFilterContextList<T>.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

function TPluginFilterContextList<T>.FindByKeyUnlocked(const AObjectID,
  AEffectID: Int64): T;
var
  Context: T;
begin
  Result := nil;
  for Context in Self do
    if (Context.ObjectID = AObjectID) and (Context.EffectID = AEffectID) then
      Exit(Context);
end;

function TPluginFilterContextList<T>.FindByObjectLocationUnlocked(ALayer,
  AFrameS, AFrameE: Integer): T;
var
  Context: T;
begin
  Result := nil;
  for Context in Self do
    if (Context.Layer = ALayer) and (Context.FrameS = AFrameS) and
      (Context.FrameE = AFrameE) then
      Exit(Context);
end;

function TPluginFilterContextList<T>.TryGetObjectID(Video: PFILTER_PROC_VIDEO;
  out AObjectID: Int64): Boolean;
begin
  Result := (Video <> nil) and (Video^.Object_ <> nil);
  if Result then
    AObjectID := Video^.Object_^.ID
  else
    AObjectID := 0;
end;

procedure TPluginFilterContextList<T>.InitNewContext(const Context: T;
  const AObjectID, AEffectID: Int64);
begin
  Context.FObjectID := AObjectID;
  Context.FEffectID := AEffectID;
end;

function TPluginFilterContextList<T>.FindByKey(const AObjectID,
  AEffectID: Int64): T;
begin
  FLock.Acquire;
  try
    Result := FindByKeyUnlocked(AObjectID, AEffectID);
  finally
    FLock.Release;
  end;
end;

function TPluginFilterContextList<T>.FindByObjectLocation(ALayer, AFrameS,
  AFrameE: Integer): T;
begin
  FLock.Acquire;
  try
    Result := FindByObjectLocationUnlocked(ALayer, AFrameS, AFrameE);
  finally
    FLock.Release;
  end;
end;

function TPluginFilterContextList<T>.GetContext(Video: PFILTER_PROC_VIDEO): T;
var
  EffectID: Int64;
  ObjectID: Int64;
begin
  Result := nil;
  if not TryGetObjectID(Video, ObjectID) then
    Exit;
  EffectID := Video^.Object_^.EffectID;

  FLock.Acquire;
  try
    Result := FindByKeyUnlocked(ObjectID, EffectID);
    if Result <> nil then
    begin
      Result.FLayer := Video^.Object_^.Layer;
      Result.FFrameS := Video^.Object_^.FrameS;
      Result.FFrameE := Video^.Object_^.FrameE;
    end
    else
    begin
      Result := T.Create;
      try
        InitNewContext(Result, ObjectID, EffectID);
        Result.FLayer := Video^.Object_^.Layer;
        Result.FFrameS := Video^.Object_^.FrameS;
        Result.FFrameE := Video^.Object_^.FrameE;
        Add(Result);
      except
        Result.Free;
        raise;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

end.
