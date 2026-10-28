// RIGMMakerの通信を基に、専用app-serverのプロセスと匿名パイプを所有する。
// VCL・Documentには触れず、中止時は自分で起動したプロセスツリーだけを終了する。
unit MapRakuCodexTransport;
interface
uses System.Classes, System.JSON, Winapi.Windows;
type
  TMapRakuCodexTransport = class
  private
    FProcess, FJob, FInput, FOutput, FStderr: THandle;
    FOutputBytes, FErrorBytes: RawByteString;
    FScan: Integer;
    FDirectory, FLogPath, FDiagnostic: string;
    FOwner: TThread; // 所有しない。通信を行うワーカー。
    procedure ReadBytes(Pipe: THandle; var Bytes: RawByteString);
    procedure Log(const Kind, Value: string);
    procedure LogJson(const Kind: string; Value: TJSONObject);
  public
    constructor Create(Owner: TThread; const Directory: string);
    destructor Destroy; override;
    procedure Open;
    procedure Send(Value: TJSONObject); // 所有権を受け取る。
    function Receive(Deadline: UInt64): TJSONObject; // 呼出側所有。
    property LogPath: string read FLogPath;
  end;
function FindMapRakuCodex: string;
implementation
uses System.SysUtils, System.IOUtils;

procedure CloseOwned(var Handle: THandle);
begin
  if (Handle<>0) and (Handle<>INVALID_HANDLE_VALUE) then CloseHandle(Handle);
  Handle := 0;
end;

function FindMapRakuCodex: string;
var Buffer: array[0..32767] of Char; Count: DWORD; Part: PChar; Latest: TDateTime;
begin
  Result := GetEnvironmentVariable('CODEX_PIPE_EXE');
  if Result<>'' then begin
    Result := TPath.GetFullPath(Result);
    if not FileExists(Result) then raise Exception.Create('CODEX_PIPE_EXEの実行ファイルがありません。');
    Exit;
  end;
  Part := nil; Count := SearchPath(nil,'codex.exe',nil,Length(Buffer),Buffer,Part);
  if (Count>0) and (Count<DWORD(Length(Buffer))) then Exit(string(Buffer));
  // ExplorerやAviUtl2からの起動でも、デスクトップ版と同じ導入先を解決する。
  var Root := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'OpenAI\Codex\bin');
  Latest := 0;
  if DirectoryExists(Root) then for var Folder in TDirectory.GetDirectories(Root) do begin
    var Candidate := TPath.Combine(Folder,'codex.exe');
    if FileExists(Candidate) and (TFile.GetLastWriteTimeUtc(Candidate)>Latest) then begin
      Result := Candidate; Latest := TFile.GetLastWriteTimeUtc(Candidate);
    end;
  end;
  if Result='' then raise Exception.Create('codex.exeが見つかりません。Codexの導入・PATHを確認してください。');
end;

constructor TMapRakuCodexTransport.Create(Owner: TThread; const Directory: string);
begin
  inherited Create; FOwner := Owner; FDirectory := Directory;
  ForceDirectories(FDirectory); FLogPath := TPath.Combine(FDirectory,'protocol.log');
end;

destructor TMapRakuCodexTransport.Destroy;
begin
  CloseOwned(FInput);
  if FProcess<>0 then WaitForSingleObject(FProcess,300);
  // app-serverを残すと生成が継続するため、所有するJob全体を確実に閉じる。
  CloseOwned(FJob); CloseOwned(FProcess); CloseOwned(FOutput); CloseOwned(FStderr);
  inherited;
end;

procedure TMapRakuCodexTransport.Log(const Kind, Value: string);
begin
  TFile.AppendAllText(FLogPath,FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now)+
    ' '+Kind+' '+Value+sLineBreak,TEncoding.UTF8);
end;

procedure RedactImage(Value: TJSONValue);
begin
  if Value is TJSONObject then begin
    var O := TJSONObject(Value);
    for var Key in TArray<string>.Create('result','url') do
      if (O.GetValue(Key) is TJSONString) and
        (((Key='result') and (O.GetValue('type')<>nil) and (O.GetValue('type').Value='imageGeneration')) or
        ((Key='url') and O.GetValue(Key).Value.StartsWith('data:image/'))) then begin
        var Count := Length(O.GetValue(Key).Value);
        O.RemovePair(Key).Free; O.AddPair(Key,Format('<image data: %d characters>',[Count]));
      end;
    for var Pair in O do RedactImage(Pair.JsonValue);
  end else if Value is TJSONArray then for var Item in TJSONArray(Value) do RedactImage(Item);
end;

procedure TMapRakuCodexTransport.LogJson(const Kind: string; Value: TJSONObject);
var CopyValue: TJSONValue;
begin
  CopyValue := Value.Clone as TJSONValue;
  try RedactImage(CopyValue); Log(Kind,CopyValue.ToJSON); finally CopyValue.Free; end;
end;

procedure TMapRakuCodexTransport.Open;
var Security: TSecurityAttributes; Startup: TStartupInfo; Info: TProcessInformation;
  Limits: TJobObjectExtendedLimitInformation; ChildInput, ChildOutput, ChildError: THandle;
  Executable, Command: string;
begin
  Executable := FindMapRakuCodex; Command := '"'+Executable+'" app-server --listen stdio://';
  UniqueString(Command); ChildInput := 0; ChildOutput := 0; ChildError := 0;
  ZeroMemory(@Security,SizeOf(Security)); Security.nLength := SizeOf(Security); Security.bInheritHandle := True;
  try
    if not CreatePipe(ChildInput,FInput,@Security,0) then RaiseLastOSError;
    if not SetHandleInformation(FInput,HANDLE_FLAG_INHERIT,0) then RaiseLastOSError;
    if not CreatePipe(FOutput,ChildOutput,@Security,0) then RaiseLastOSError;
    if not SetHandleInformation(FOutput,HANDLE_FLAG_INHERIT,0) then RaiseLastOSError;
    if not CreatePipe(FStderr,ChildError,@Security,0) then RaiseLastOSError;
    if not SetHandleInformation(FStderr,HANDLE_FLAG_INHERIT,0) then RaiseLastOSError;
    FJob := CreateJobObject(nil,nil); if FJob=0 then RaiseLastOSError;
    ZeroMemory(@Limits,SizeOf(Limits)); Limits.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if not SetInformationJobObject(FJob,JobObjectExtendedLimitInformation,@Limits,SizeOf(Limits)) then RaiseLastOSError;
    ZeroMemory(@Startup,SizeOf(Startup)); Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW; Startup.wShowWindow := SW_HIDE;
    Startup.hStdInput := ChildInput; Startup.hStdOutput := ChildOutput; Startup.hStdError := ChildError;
    ZeroMemory(@Info,SizeOf(Info));
    if not CreateProcess(PChar(Executable),PChar(Command),nil,nil,True,CREATE_NO_WINDOW or CREATE_SUSPENDED,
      nil,PChar(FDirectory),Startup,Info) then RaiseLastOSError;
    FProcess := Info.hProcess;
    try
      if not AssignProcessToJobObject(FJob,FProcess) then begin
        var Error := GetLastError; TerminateProcess(FProcess,1); RaiseLastOSError(Error);
      end;
      if ResumeThread(Info.hThread)=DWORD(-1) then RaiseLastOSError;
    finally CloseHandle(Info.hThread); end;
  finally CloseOwned(ChildInput); CloseOwned(ChildOutput); CloseOwned(ChildError); end;
end;

procedure TMapRakuCodexTransport.Send(Value: TJSONObject);
var Bytes: TBytes; Written, Offset: DWORD;
begin
  try
    if FOwner.CheckTerminated then raise EAbort.Create('生成を中止しました。');
    LogJson('SEND',Value); Bytes := TEncoding.UTF8.GetBytes(Value.ToJSON+#10); Offset := 0;
    while Offset<DWORD(Length(Bytes)) do begin
      if not WriteFile(FInput,Bytes[Offset],Length(Bytes)-Offset,Written,nil) then RaiseLastOSError;
      if Written=0 then raise Exception.Create('Codexへの送信が終了しました。');
      Inc(Offset,Written);
    end;
  finally Value.Free; end;
end;

procedure TMapRakuCodexTransport.ReadBytes(Pipe: THandle; var Bytes: RawByteString);
var Available, Count: DWORD; Buffer: array[0..65535] of Byte; Part: RawByteString;
begin
  if not PeekNamedPipe(Pipe,nil,0,nil,@Available,nil) or (Available=0) then Exit;
  if Available>SizeOf(Buffer) then Available := SizeOf(Buffer);
  if not ReadFile(Pipe,Buffer[0],Available,Count,nil) then RaiseLastOSError;
  SetString(Part,PAnsiChar(@Buffer[0]),Count); Bytes := Bytes+Part;
  if Length(Bytes)>64*1024*1024 then raise Exception.Create('Codexの応答が64MiBを超えました。');
end;

function TMapRakuCodexTransport.Receive(Deadline: UInt64): TJSONObject;
var Position: Integer; Line: RawByteString; Parsed: TJSONValue; Available, ExitStatus: DWORD;
begin
  repeat
    if FOwner.CheckTerminated then raise EAbort.Create('生成を中止しました。');
    ReadBytes(FStderr,FErrorBytes); Position := Pos(AnsiChar(#10),FErrorBytes);
    while Position>0 do begin
      Line := Copy(FErrorBytes,1,Position-1); Delete(FErrorBytes,1,Position);
      FDiagnostic := Trim(UTF8ToString(Line)); Log('STDERR',FDiagnostic);
      Position := Pos(AnsiChar(#10),FErrorBytes);
    end;
    ReadBytes(FOutput,FOutputBytes); Position := Pos(AnsiChar(#10),FOutputBytes,FScan+1);
    if Position>0 then begin
      Line := Copy(FOutputBytes,1,Position-1); Delete(FOutputBytes,1,Position); FScan := 0;
      if Trim(UTF8ToString(Line))='' then Continue;
      Parsed := TJSONObject.ParseJSONValue(UTF8ToString(Line));
      if not (Parsed is TJSONObject) then begin Parsed.Free; raise Exception.Create('CodexのJSON応答が不正です。'); end;
      LogJson('RECV',TJSONObject(Parsed)); Exit(TJSONObject(Parsed));
    end;
    FScan := Length(FOutputBytes);
    if WaitForSingleObject(FProcess,0)=WAIT_OBJECT_0 then begin
      Available := 0; PeekNamedPipe(FOutput,nil,0,nil,@Available,nil); if Available>0 then Continue;
      GetExitCodeProcess(FProcess,ExitStatus);
      raise Exception.CreateFmt('Codexが終了しました（%d）。%s',[ExitStatus,FDiagnostic]);
    end;
    if GetTickCount64>=Deadline then raise Exception.Create('Codexの応答がタイムアウトしました。');
    Sleep(10);
  until False;
end;
end.
