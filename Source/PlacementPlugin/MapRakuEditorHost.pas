// AviUtl2の文字列データと共通デザイナー画面を接続するプラグイン用ホスト。
unit MapRakuEditorHost;

interface

uses
  System.SysUtils;

// 編集画面を閉じた時点のDocumentを返す。ホスト内では取消操作を設けない。
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
      // 下部の適用／取消パネルを置かず、右上の×を含む通常の閉じる操作を
      // 確定として扱う。確保していた高さはそのまま編集領域へ戻る。
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
