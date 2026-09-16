// Named Pipeの待受とUTF-8メッセージ交換をワーカースレッドで行う。
// 要求処理だけは通知先ウィンドウのスレッドへ戻し、VCLとDocumentを安全に操作する。
unit PipeServerTThread;

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils, Winapi.Messages;

const
  WM_PIPE_NOTIFY = WM_USER + 100;

type
  TPipeServerState = (psConnectWait, psReceive);

  TPipeServerConfig = record
    PipeName: string;      // 「\\.\pipe\」を除いた名前。
    BufferSize: Cardinal; // 1要求および1応答の最大バイト数。
    MaxInstances: Cardinal;
    IsDuplex: Boolean;
  end;

  TPipeServerTThreadReceiveEvent = procedure(Sender: TObject;
    const ReceivedStr: string; var SendStr: string) of object;

  TPipeServerTThread = class(TThread)
  private
    FState: TPipeServerState;
    FConfig: TPipeServerConfig;
    FRecvText: string;
    FSendText: string;
    FPipeHandle: THandle;
    FOnReceive: TPipeServerTThreadReceiveEvent;
    FMainWnd: HWND;
    FEventHandle: THandle;
    procedure Connect;
    procedure Receive;
    procedure PipeClose;
    function PipeOpen(const Config: TPipeServerConfig): THandle;
  protected
    procedure DoReceive(const ReceivedStr: string; var SendStr: string);
    procedure Execute; override;
  public
    constructor Create(const PipeName: string; BufferSize: Cardinal;
      IsDuplex: Boolean; MaxInstances: Cardinal; MainWnd: HWND);
    destructor Destroy; override;
    // WM_PIPE_NOTIFYを受けたVCLスレッドから呼び、保留中の要求を処理する。
    procedure ProcessMainThread;
    // 終了時にVCLスレッドの応答待ちを解除する。
    procedure ReleaseWait;
    // VCLのHandle再生成後に、要求処理を行う現在の通知先へ差し替える。
    procedure SetNotifyWindow(MainWnd: HWND);
    property OnReceive: TPipeServerTThreadReceiveEvent read FOnReceive
      write FOnReceive;
  end;

implementation

constructor TPipeServerTThread.Create(const PipeName: string;
  BufferSize: Cardinal; IsDuplex: Boolean; MaxInstances: Cardinal;
  MainWnd: HWND);
begin
  // 派生する受信側がOnReceiveを設定し終えるまで、待受スレッドを開始しない。
  inherited Create(True);
  FConfig.PipeName := PipeName;
  FConfig.BufferSize := BufferSize;
  FConfig.IsDuplex := IsDuplex;
  FConfig.MaxInstances := MaxInstances;
  FMainWnd := MainWnd;
  FEventHandle := CreateEvent(nil, False, False, nil);
  FPipeHandle := INVALID_HANDLE_VALUE;
  FState := psConnectWait;
  FreeOnTerminate := False;
end;

destructor TPipeServerTThread.Destroy;
begin
  if FEventHandle <> 0 then
    CloseHandle(FEventHandle);
  inherited Destroy;
end;

function TPipeServerTThread.PipeOpen(
  const Config: TPipeServerConfig): THandle;
var
  FullName: string;
  OpenMode: DWORD;
  PipeMode: DWORD;
begin
  if Config.IsDuplex then
    OpenMode := PIPE_ACCESS_DUPLEX
  else
    OpenMode := PIPE_ACCESS_INBOUND;
  PipeMode := PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT;
  FullName := '\\.\pipe\' + Config.PipeName;
  Result := CreateNamedPipe(PChar(FullName), OpenMode, PipeMode,
    Config.MaxInstances, Config.BufferSize, Config.BufferSize, 0, nil);
end;

procedure TPipeServerTThread.PipeClose;
begin
  if FPipeHandle = INVALID_HANDLE_VALUE then
    Exit;
  DisconnectNamedPipe(FPipeHandle);
  CloseHandle(FPipeHandle);
  FPipeHandle := INVALID_HANDLE_VALUE;
end;

procedure TPipeServerTThread.Connect;
var
  ErrorCode: DWORD;
begin
  PipeClose;
  FPipeHandle := PipeOpen(FConfig);
  if FPipeHandle = INVALID_HANDLE_VALUE then
  begin
    Sleep(50);
    Exit;
  end;
  if ConnectNamedPipe(FPipeHandle, nil) then
  begin
    FState := psReceive;
    Exit;
  end;
  ErrorCode := GetLastError;
  if ErrorCode = ERROR_PIPE_CONNECTED then
  begin
    FState := psReceive;
    Exit;
  end;
  PipeClose;
  Sleep(50);
end;

procedure TPipeServerTThread.DoReceive(const ReceivedStr: string;
  var SendStr: string);
begin
  FRecvText := ReceivedStr;
  FSendText := '';
  ResetEvent(FEventHandle);
  PostMessage(FMainWnd, WM_PIPE_NOTIFY, WPARAM(Self), 0);
  while not Terminated do
    if WaitForSingleObject(FEventHandle, 50) = WAIT_OBJECT_0 then
      Break;
  if Terminated then
    SendStr := ''
  else
    SendStr := FSendText;
end;

procedure TPipeServerTThread.ProcessMainThread;
begin
  try
    if Assigned(FOnReceive) then
      FOnReceive(Self, FRecvText, FSendText);
  finally
    SetEvent(FEventHandle);
  end;
end;

procedure TPipeServerTThread.Receive;
var
  Buffer: TBytes;
  BytesRead: DWORD;
  BytesWritten: DWORD;
  ReceivedStr: string;
  SendBytes: TBytes;
  SendStr: string;
begin
  SetLength(Buffer, FConfig.BufferSize);
  BytesRead := 0;
  if (Length(Buffer) = 0) or
    not ReadFile(FPipeHandle, Buffer[0], Length(Buffer), BytesRead, nil) or
    (BytesRead = 0) then
  begin
    PipeClose;
    FState := psConnectWait;
    Exit;
  end;
  ReceivedStr := TEncoding.UTF8.GetString(Buffer, 0, BytesRead);
  SendStr := '';
  DoReceive(ReceivedStr, SendStr);
  if FConfig.IsDuplex then
  begin
    SendBytes := TEncoding.UTF8.GetBytes(SendStr);
    BytesWritten := 0;
    if Length(SendBytes) > 0 then
      WriteFile(FPipeHandle, SendBytes[0], Length(SendBytes),
        BytesWritten, nil);
    FlushFileBuffers(FPipeHandle);
  end;
  PipeClose;
  FState := psConnectWait;
end;

procedure TPipeServerTThread.ReleaseWait;
begin
  if FEventHandle <> 0 then
    SetEvent(FEventHandle);
end;

procedure TPipeServerTThread.SetNotifyWindow(MainWnd: HWND);
begin
  FMainWnd := MainWnd;
end;

procedure TPipeServerTThread.Execute;
begin
  while not Terminated do
    case FState of
      psConnectWait: Connect;
      psReceive: Receive;
    end;
  PipeClose;
end;

end.
