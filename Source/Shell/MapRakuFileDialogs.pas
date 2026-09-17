// 地図JSONの開く・保存先指定を一箇所にまとめ、画面本体の文書状態から切り離す。
unit MapRakuFileDialogs;

interface

uses System.Classes;

function ChooseMapFileToOpen(Owner: TComponent; WindowHandle: NativeUInt;
  const CurrentFileName: string; out FileName: string): Boolean;
function ChooseMapFileToSave(Owner: TComponent; WindowHandle: NativeUInt;
  const CurrentFileName: string; out FileName: string): Boolean;

implementation

uses System.SysUtils, System.IOUtils, Vcl.Dialogs;

function ChooseMapFileToOpen(Owner: TComponent; WindowHandle: NativeUInt;
  const CurrentFileName: string; out FileName: string): Boolean;
var Dialog: TFileOpenDialog;
begin
  FileName := '';
  Dialog := TFileOpenDialog.Create(Owner);
  try
    Dialog.Title := '地図を開く';
    Dialog.DefaultExtension := 'mapraku';
    Dialog.Options := [fdoFileMustExist, fdoPathMustExist, fdoForceFileSystem];
    with Dialog.FileTypes.Add do begin
      DisplayName := 'ちずらく地図 (*.mapraku)';
      FileMask := '*.mapraku';
    end;
    Dialog.FileTypeIndex := 1;
    if CurrentFileName <> '' then begin
      Dialog.DefaultFolder := ExtractFilePath(CurrentFileName);
      Dialog.FileName := ExtractFileName(CurrentFileName);
    end else
      Dialog.DefaultFolder := TPath.GetDocumentsPath;
    Result := Dialog.Execute(WindowHandle);
    if Result then FileName := Dialog.FileName;
  finally Dialog.Free; end;
end;

function ChooseMapFileToSave(Owner: TComponent; WindowHandle: NativeUInt;
  const CurrentFileName: string; out FileName: string): Boolean;
var Dialog: TFileSaveDialog;
begin
  FileName := '';
  Dialog := TFileSaveDialog.Create(Owner);
  try
    Dialog.Title := '名前を付けて保存';
    Dialog.DefaultExtension := 'mapraku';
    if CurrentFileName <> '' then begin
      Dialog.FileName := ExtractFileName(CurrentFileName);
      Dialog.DefaultFolder := ExtractFilePath(CurrentFileName);
    end else begin
      Dialog.FileName := '地図.mapraku';
      Dialog.DefaultFolder := TPath.GetDocumentsPath;
    end;
    // 既存ファイルの上書きはOSの確認ダイアログを必ず経由させる。
    Dialog.Options := [fdoOverWritePrompt, fdoPathMustExist, fdoForceFileSystem];
    with Dialog.FileTypes.Add do begin
      DisplayName := 'ちずらく地図 (*.mapraku)';
      FileMask := '*.mapraku';
    end;
    Dialog.FileTypeIndex := 1;
    Result := Dialog.Execute(WindowHandle);
    if Result then FileName := Dialog.FileName;
  finally Dialog.Free; end;
end;

end.
