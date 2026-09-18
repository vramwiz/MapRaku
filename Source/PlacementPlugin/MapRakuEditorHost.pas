// AviUtl2の文字列データと共通デザイナー画面を接続するプラグイン用ホスト。
unit MapRakuEditorHost;

interface

uses
  System.SysUtils;

// 適用だけがTrueを返す。取消では元データを保持し、ErrorMessageを空にする。
function EditMapRaku(const SerializedData: string;
  const BackgroundPixels: TBytes; BackgroundWidth, BackgroundHeight: Integer;
  CanvasWidth, CanvasHeight: Integer;
  out UpdatedData, ErrorMessage: string): Boolean;

implementation

uses
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls,
  System.UITypes, MapRakuDocumentJson, MapRakuPluginDocument,
  MapRakuMainForm, MapRakuAutomationWire;

procedure AddSessionControls(EditorForm: TMainForm);
var Panel: TPanel; Button: TButton; Endpoint: TEdit;
begin
  Panel := TPanel.Create(EditorForm);
  Panel.Parent := EditorForm;
  Panel.Align := alBottom;
  Panel.Height := 38;
  Panel.BevelOuter := bvNone;
  Button := TButton.Create(Panel);
  Button.Parent := Panel;
  Button.Align := alRight;
  Button.Width := 100;
  Button.Caption := '取消';
  Button.ModalResult := mrCancel;
  // EnterとEscは既存の作図操作に使うため、既定／取消キーには割り当てない。
  Button := TButton.Create(Panel);
  Button.Parent := Panel;
  Button.Align := alRight;
  Button.Width := 100;
  Button.Caption := '適用';
  Button.ModalResult := mrOk;
  Endpoint := TEdit.Create(Panel);
  Endpoint.Parent := Panel;
  Endpoint.Align := alClient;
  Endpoint.ReadOnly := True;
  Endpoint.Text := AutomationPipeShortName;
  Endpoint.Hint := 'AI接続先（コピーしてSet-MapRakuEndpointへ渡す）';
  Endpoint.ShowHint := True;
end;

function EnterEditorDpiContext: DPI_AWARENESS_CONTEXT;
begin
  try
    // 編集Formを96 DPI座標でWindowsに拡大させ、固定描画部品の寸法差を防ぐ。
    Result := SetThreadDpiAwarenessContext(
      DPI_AWARENESS_CONTEXT_UNAWARE_GDISCALED);
    if not IsValidDpiAwarenessContext(Result) then
      Result := SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_UNAWARE);
  except
    // APIを持たない旧環境ではホストのDPIコンテキストを維持する。
    Result := Default(DPI_AWARENESS_CONTEXT);
  end;
end;

procedure RestoreEditorDpiContext(PreviousContext: DPI_AWARENESS_CONTEXT);
begin
  if not IsValidDpiAwarenessContext(PreviousContext) then
    Exit;
  try
    SetThreadDpiAwarenessContext(PreviousContext);
  except
    // 編集Formは破棄済みのため、復元APIが失敗しても終了処理を継続する。
  end;
end;

function EditMapRaku(const SerializedData: string;
  const BackgroundPixels: TBytes; BackgroundWidth, BackgroundHeight: Integer;
  CanvasWidth, CanvasHeight: Integer;
  out UpdatedData, ErrorMessage: string): Boolean;
var
  EditorForm: TMainForm;
  PreviousDpiContext: DPI_AWARENESS_CONTEXT;
begin
  Result := False;
  UpdatedData := SerializedData;
  ErrorMessage := '';
  EditorForm := nil;
  PreviousDpiContext := EnterEditorDpiContext;
  try
    try
      EditorForm := TMainForm.CreateHosted(nil);
      EditorForm.Caption := '地図 - 編集';
      EditorForm.Position := poScreenCenter;
      EditorForm.SetFileDropCaptionEnabled(True);
      EditorForm.SetHostBackgroundRgba(BackgroundPixels,
        BackgroundWidth, BackgroundHeight);
      if not InitializeMapRakuPluginDocument(EditorForm.Document,
        SerializedData, CanvasWidth, CanvasHeight,
        ErrorMessage) then
        Exit;
      AddSessionControls(EditorForm);
      if EditorForm.ShowModal <> mrOk then Exit;
      UpdatedData := SerializeVectArtDocument(EditorForm.Document);
      Result := True;
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    EditorForm.Free;
    RestoreEditorDpiContext(PreviousDpiContext);
  end;
end;

end.
