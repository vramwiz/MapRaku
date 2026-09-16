// Windows IMEの開閉状態を編集セッションの境界で一時退避・復元する。
unit WindowsImeController;

interface

uses
  Winapi.Windows;

type
  TWindowsImeState = record
    WasOpen: Boolean; // 退避時にIMEが開いていた場合はTrue。
    Valid: Boolean;   // WasOpenを復元可能な状態ならTrue。
  end;

// WindowHandleに関連付いたIMEの状態をStateへ保存し、IMEを閉じる。
procedure SuspendWindowsIme(WindowHandle: HWND;
  var State: TWindowsImeState);
// 保存済みの状態をWindowHandleのIMEへ復元する。未保存なら何もしない。
procedure RestoreWindowsIme(WindowHandle: HWND;
  var State: TWindowsImeState);

implementation

uses
  Winapi.Imm;

procedure SuspendWindowsIme(WindowHandle: HWND;
  var State: TWindowsImeState);
var
  InputContext: HIMC;
begin
  State.Valid := False;
  if (WindowHandle = 0) or not IsWindow(WindowHandle) then
    Exit;
  InputContext := ImmGetContext(WindowHandle);
  if InputContext = 0 then
    Exit;
  try
    State.WasOpen := ImmGetOpenStatus(InputContext);
    State.Valid := True;
    if State.WasOpen then
      ImmSetOpenStatus(InputContext, False);
  finally
    ImmReleaseContext(WindowHandle, InputContext);
  end;
end;

procedure RestoreWindowsIme(WindowHandle: HWND;
  var State: TWindowsImeState);
var
  InputContext: HIMC;
begin
  if not State.Valid or (WindowHandle = 0) or
    not IsWindow(WindowHandle) then
    Exit;
  InputContext := ImmGetContext(WindowHandle);
  if InputContext = 0 then
    Exit;
  try
    ImmSetOpenStatus(InputContext, State.WasOpen);
    State.Valid := False;
  finally
    ImmReleaseContext(WindowHandle, InputContext);
  end;
end;

end.
