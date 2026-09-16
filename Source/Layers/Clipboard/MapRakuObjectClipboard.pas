// 選択レイヤーを専用クリップボード形式へ転送し、検証したデータを挿入コマンドへ渡す。
unit MapRakuObjectClipboard;

interface

uses
  MapRakuDocument, MapRakuEditorState, MapRakuEditHistory;

// 開いたグループを優先し、積層順の選択だけを返す。背景は含まない。
function ClipboardSelection(Document: TVectArtDocument; State: TVectArtEditorState): TArray<TVectArtLayer>;
// 専用形式の有無を返す。通常の文字列や画像は貼り付け対象にしない。
function CanPasteObjects(State: TVectArtEditorState): Boolean;
// 選択を独立したJSONとして専用形式へ格納する。
procedure CopyObjects(Document: TVectArtDocument; State: TVectArtEditorState);
// 検証済みのデータを現在の階層の最前面へ同じ座標で挿入し、1件の履歴へまとめる。
procedure PasteObjects(Document: TVectArtDocument; State: TVectArtEditorState; History: TVectArtEditHistory);

implementation

uses
  Winapi.Windows, System.SysUtils, Vcl.Clipbrd,
  MapRakuDocumentJson, MapRakuGroupCommands, MapRakuInsertObjectsCommand;

function ObjectFormat: Word;
begin
  Result := RegisterClipboardFormat('MapRaku.Objects.JSON.v15');
end;

function ClipboardSelection(Document: TVectArtDocument; State: TVectArtEditorState): TArray<TVectArtLayer>;
var
  I, Count: Integer;
begin
  Result := nil;
  if Document = nil then Exit;
  if (State <> nil) and (State.OpenGroup <> nil) then
  begin
    SetLength(Result, State.OpenGroupChildCount);
    Count := 0;
    for I := 0 to State.OpenGroup.ChildCount - 1 do
      if State.IsOpenGroupChildSelected(State.OpenGroup[I]) then
      begin
        Result[Count] := State.OpenGroup[I];
        Inc(Count);
      end;
    SetLength(Result, Count);
  end
  else
  begin
    for I := 1 to Document.LayerCount - 1 do
      if Document.IsLayerSelected(I) then Result := Result + [Document[I]];
  end;
end;

function CanPasteObjects(State: TVectArtEditorState): Boolean;
begin
  Result := ((State = nil) or (State.OpenGroup = nil) or not State.OpenGroup.Locked) and
    Clipboard.HasFormat(ObjectFormat);
end;

// クリップボード監視アプリが更新直後に短時間占有する場合だけ再試行する。
procedure OpenObjectClipboard;
var
  Attempt: Integer;
begin
  for Attempt := 1 to 10 do
    try
      Clipboard.Open;
      Exit;
    except
      on E: EClipboardException do
      begin
        if Attempt = 10 then raise;
        Sleep(10);
      end;
    end;
end;

procedure CopyObjects(Document: TVectArtDocument; State: TVectArtEditorState);
var
  Snapshot: TVectArtDocument;
  Layers: TArray<TVectArtLayer>;
  Layer, Duplicate: TVectArtLayer;
  Value: string;
  Data: HGLOBAL;
  Target: Pointer;
  ByteCount: NativeUInt;
begin
  Layers := ClipboardSelection(Document, State);
  if Length(Layers) = 0 then Exit;
  Snapshot := TVectArtDocument.Create;
  try
    for Layer in Layers do
    begin
      Duplicate := CloneMapRakuLayer(Layer, Layer.Name);
      Duplicate.Locked := Layer.Locked;
      Snapshot.InsertLayer(Snapshot.LayerCount, Duplicate);
    end;
    Value := SerializeVectArtDocument(Snapshot);
  finally
    Snapshot.Free;
  end;
  ByteCount := (NativeUInt(Length(Value)) + 1) * SizeOf(Char);
  Data := GlobalAlloc(GMEM_MOVEABLE, ByteCount);
  if Data = 0 then RaiseLastOSError;
  try
    Target := GlobalLock(Data);
    if Target = nil then RaiseLastOSError;
    try
      Move(PChar(Value)^, Target^, ByteCount);
    finally
      GlobalUnlock(Data);
    end;
    OpenObjectClipboard;
    try
      Clipboard.Clear;
      Clipboard.SetAsHandle(ObjectFormat, Data);
      Data := 0;
    finally
      Clipboard.Close;
    end;
  finally
    if Data <> 0 then GlobalFree(Data);
  end;
end;

procedure PasteObjects(Document: TVectArtDocument; State: TVectArtEditorState; History: TVectArtEditHistory);
var
  Data: THandle;
  Source: PChar;
  Value, ErrorText: string;
  Size, Count: NativeUInt;
  Snapshot: TVectArtDocument;
  Layers: TArray<TVectArtLayer>;
  I: Integer;
  Command: TMapRakuInsertObjectsCommand;
begin
  if (Document = nil) or not CanPasteObjects(State) then Exit;
  OpenObjectClipboard;
  try
    Data := Clipboard.GetAsHandle(ObjectFormat);
    Size := GlobalSize(Data);
    if (Size < SizeOf(Char)) or (Size > 256 * 1024 * 1024) or (Size mod SizeOf(Char) <> 0) then Exit;
    Source := GlobalLock(Data);
    if Source = nil then Exit;
    try
      Count := 0;
      while (Count < Size div SizeOf(Char)) and (Source[Count] <> #0) do Inc(Count);
      if Count = Size div SizeOf(Char) then Exit;
      SetString(Value, Source, Count);
    finally
      GlobalUnlock(Data);
    end;
  finally
    Clipboard.Close;
  end;
  Snapshot := TVectArtDocument.Create;
  try
    if not TryDeserializeVectArtDocument(Value, Snapshot, ErrorText) then Exit;
    if Snapshot.LayerCount <= 1 then Exit;
    SetLength(Layers, Snapshot.LayerCount - 1);
    for I := 0 to High(Layers) do Layers[I] := Snapshot.ExtractLayer(1);
    Command := TMapRakuInsertObjectsCommand.Create(Document, State, Layers);
    try
      Command.Execute;
      if History <> nil then
      begin
        History.AddApplied(Command);
        Command := nil;
      end;
    finally
      Command.Free;
    end;
  finally
    Snapshot.Free;
  end;
end;

end.
