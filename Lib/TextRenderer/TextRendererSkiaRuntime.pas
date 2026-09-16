// Skia APIの動的結合とプロセス内参照カウントを管理する。
unit TextRendererSkiaRuntime;

interface

type
  TTextRendererSkiaRuntime = class sealed
  public
    // 指定DLLを初期化する。同じパスへの複数取得は参照数として保持する。
    class procedure Acquire(const ALibraryFileName: string); static;
    // この管理クラスを通してSkiaが取得済みならTrueを返す。
    class function IsAcquired: Boolean; static;
    // 参照数を減らし、最後の利用者が解放した時点でSkiaを終了する。
    class procedure Release; static;
  end;

implementation

uses
  TextRendererSkiaBootstrap,
  System.Skia,
  System.Skia.API,
  System.SysUtils,
  Winapi.Windows;

var
  RuntimeFileName: string;
  RuntimeLibraryHandle: HMODULE;
  RuntimeLock: TRTLCriticalSection;
  RuntimeReferenceCount: Integer;

class procedure TTextRendererSkiaRuntime.Acquire(const ALibraryFileName: string);
var
  ExpandedFileName: string;
begin
  ExpandedFileName := ExpandFileName(ALibraryFileName);
  EnterCriticalSection(RuntimeLock);
  try
    if RuntimeReferenceCount > 0 then
    begin
      if not SameText(RuntimeFileName, ExpandedFileName) then
        raise EInvalidOp.CreateFmt(
          'Skia runtime is already loaded from a different path: %s',
          [RuntimeFileName]);
      Inc(RuntimeReferenceCount);
      Exit;
    end;

    RuntimeLibraryHandle := LoadLibrary(PChar(ExpandedFileName));
    if RuntimeLibraryHandle = 0 then
      raise EOSError.CreateFmt('Cannot load Skia runtime: %s (error %d)',
        [ExpandedFileName, GetLastError]);
    try
      // Delphi 37 does not initialize the dynamically bound Skia API from the
      // System.Skia.API unit initialization section. Bind its entry points
      // before TSkGraphics calls sk4d_graphics_init.
      SkInitialize;
      TSkGraphics.Init;
      RuntimeFileName := ExpandedFileName;
      RuntimeReferenceCount := 1;
    except
      SkFinalize;
      FreeLibrary(RuntimeLibraryHandle);
      RuntimeLibraryHandle := 0;
      raise;
    end;
  finally
    LeaveCriticalSection(RuntimeLock);
  end;
end;

class function TTextRendererSkiaRuntime.IsAcquired: Boolean;
begin
  EnterCriticalSection(RuntimeLock);
  try
    Result := RuntimeReferenceCount > 0;
  finally
    LeaveCriticalSection(RuntimeLock);
  end;
end;

class procedure TTextRendererSkiaRuntime.Release;
begin
  EnterCriticalSection(RuntimeLock);
  try
    if RuntimeReferenceCount = 0 then
      Exit;
    Dec(RuntimeReferenceCount);
    if RuntimeReferenceCount > 0 then
      Exit;

    try
      TSkGraphics.PurgeAllCaches;
    finally
      SkFinalize;
      FreeLibrary(RuntimeLibraryHandle);
      RuntimeLibraryHandle := 0;
      RuntimeFileName := '';
    end;
  finally
    LeaveCriticalSection(RuntimeLock);
  end;
end;

initialization
  InitializeCriticalSection(RuntimeLock);

finalization
  while RuntimeReferenceCount > 0 do
    TTextRendererSkiaRuntime.Release;
  DeleteCriticalSection(RuntimeLock);

end.
