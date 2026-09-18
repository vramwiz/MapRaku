// MapRaku編集画面の生存期間だけ専用Named Pipeを公開する。
unit MapRakuAutomationPipeServer;

interface

uses
  Winapi.Windows, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState, MapRakuCanvas;

function StartMapRakuAutomationPipeServer(NotifyWindow: HWND;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl; out ErrorMessage: string; Hosted: Boolean = False): Boolean;
procedure StopMapRakuAutomationPipeServer;
procedure ProcessMapRakuAutomationPipeMessage(WParam: WPARAM);
// 表示時に確定したForm Handleを通知先として再設定する。
procedure UpdateMapRakuAutomationPipeNotifyWindow(NotifyWindow: HWND);

implementation

uses
  System.SysUtils, PipeServerTThread, MapRakuAutomationProtocol, MapRakuAutomationWire, MapRakuAutomationSession;

const
  PIPE_BUFFER_SIZE = 4 * 1024 * 1024;

type
  TMapRakuAutomationPipeServer = class
  private
    FDocument: TVectArtDocument;       // MainForm所有。サーバー停止まで生存する。
    FEditHistory: TVectArtEditHistory; // MainForm所有。
    FEditorState: TVectArtEditorState; // MainForm所有。
    FCanvas: TVectArtCanvasControl; // MainForm所有。背景画像の複写に使用する。
    FThread: TPipeServerTThread;
    FPipeName: string;
    procedure Receive(Sender: TObject; const ReceivedStr: string;
      var SendStr: string);
  public
    constructor Create(NotifyWindow: HWND; Document: TVectArtDocument;
      EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl);
    destructor Destroy; override;
    procedure ProcessMessage(WParam: WPARAM);
    procedure UpdateNotifyWindow(NotifyWindow: HWND);
  end;

var
  Server: TMapRakuAutomationPipeServer;

constructor TMapRakuAutomationPipeServer.Create(NotifyWindow: HWND;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl);
begin
  inherited Create;
  FDocument := Document;
  FEditHistory := EditHistory;
  FEditorState := EditorState;
  FCanvas := Canvas;
  FPipeName := '\\.\pipe\' + AutomationPipeShortName;
  FThread := TPipeServerTThread.Create(
    AutomationPipeShortName, PIPE_BUFFER_SIZE, True, 1,
    NotifyWindow);
  FThread.OnReceive := Receive;
  FThread.Start;
end;

destructor TMapRakuAutomationPipeServer.Destroy;
var
  PipeHandle: THandle;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.ReleaseWait;
    // 接続済みクライアントが読書きを止めていても、終了待ちでUIを固めない。
    CancelSynchronousIo(FThread.Handle);
    PipeHandle := CreateFile(PChar(FPipeName),
      GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
    if PipeHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(PipeHandle);
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  inherited Destroy;
end;

procedure TMapRakuAutomationPipeServer.Receive(Sender: TObject;
  const ReceivedStr: string; var SendStr: string);
begin
  SendStr := HandleMapRakuAutomationRequest(ReceivedStr, FDocument,
    FEditHistory, FEditorState, FCanvas);
  if TEncoding.UTF8.GetByteCount(SendStr) > PIPE_BUFFER_SIZE then
    SendStr := ErrorResponse('', 'response_too_large', 'Response exceeds 4 MiB; reduce document size.');
end;

procedure TMapRakuAutomationPipeServer.ProcessMessage(WParam: WPARAM);
begin
  if (FThread <> nil) and (WParam = NativeUInt(FThread)) then
    FThread.ProcessMainThread;
end;

procedure TMapRakuAutomationPipeServer.UpdateNotifyWindow(
  NotifyWindow: HWND);
begin
  if FThread <> nil then
    FThread.SetNotifyWindow(NotifyWindow);
end;

function StartMapRakuAutomationPipeServer(NotifyWindow: HWND;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl; out ErrorMessage: string; Hosted: Boolean): Boolean;
var Token: TGUID;
begin
  Result := False;
  ErrorMessage := '';
  if Server <> nil then
  begin
    ErrorMessage := 'Another MapRaku editor already owns the automation pipe.';
    Exit;
  end;
  try
    AutomationPipeShortName := SCREEN_LAYOUT_AUTOMATION_PIPE_SHORT_NAME;
    AutomationHostKind := 'standalone';
    if Hosted then
    begin
      // DLLと単独アプリ、再編集を別名にし、古い接続先への誤適用を防ぐ。
      CreateGUID(Token);
      AutomationPipeShortName := 'MapRaku.Plugin.' + IntToStr(GetCurrentProcessId) +
        '.' + GUIDToString(Token);
      AutomationHostKind := 'aviutl2';
    end;
    Server := TMapRakuAutomationPipeServer.Create(NotifyWindow,
      Document, EditHistory, EditorState, Canvas);
    Result := True;
  except
    on E: Exception do
    begin
      FreeAndNil(Server);
      ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

procedure StopMapRakuAutomationPipeServer;
begin
  FreeAndNil(Server);
  ResetAutomationSession;
end;

procedure ProcessMapRakuAutomationPipeMessage(WParam: WPARAM);
begin
  if Server <> nil then
    Server.ProcessMessage(WParam);
end;

procedure UpdateMapRakuAutomationPipeNotifyWindow(NotifyWindow: HWND);
begin
  if Server <> nil then
    Server.UpdateNotifyWindow(NotifyWindow);
end;

end.
