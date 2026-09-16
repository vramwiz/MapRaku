// AviUtl2の文字列データと共通デザイナー画面を接続するプラグイン用ホスト。
unit MapRakuEditorHost;

interface

uses
  System.SysUtils;

// 保存値と参照背景を編集画面へ渡し、確定後のversion 15 JSONまたは失敗理由を返す。
function EditMapRaku(const SerializedData: string;
  const BackgroundPixels: TBytes; BackgroundWidth, BackgroundHeight: Integer;
  CanvasWidth, CanvasHeight: Integer;
  out UpdatedData, ErrorMessage: string): Boolean;

implementation

uses
  Winapi.Windows, Vcl.Forms, MapRakuDocumentJson, MapRakuPluginDocument,
  MapRakuMainForm;

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
      EditorForm := TMainForm.Create(nil);
      EditorForm.Caption := '画面レイアウト - 編集';
      EditorForm.Position := poScreenCenter;
      EditorForm.SetFileDropCaptionEnabled(True);
      EditorForm.SetCanvasSettingsVisible(False);
      EditorForm.SetReferenceBackgroundRgba(BackgroundPixels,
        BackgroundWidth, BackgroundHeight);
      if not InitializeMapRakuPluginDocument(EditorForm.Document,
        SerializedData, CanvasWidth, CanvasHeight,
        ErrorMessage) then
        Exit;
      EditorForm.ShowModal;
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
