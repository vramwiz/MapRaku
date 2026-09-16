// 専用領域だけでファイルD&Dを受け付け、ホバー可否をWindowsと表示側へ伝える。
unit MapRakuTextureDropTarget;

interface

uses System.Types, Winapi.Windows, Winapi.ActiveX;

type
  TTextureDropCheck = reference to function(const Point: TPoint; Hover: Boolean): Boolean;
  TTextureDropFile = reference to function(const FileName: string): Boolean;
  TMapRakuTextureDropTarget = class(TInterfacedObject, IDropTarget)
  private
    FCheck: TTextureDropCheck; // スクリーン座標の受け入れ判定とホバー表示。
    FLoad: TTextureDropFile;   // 検証済みの単一ファイルを受け取る処理。
    FHasFile: Boolean;        // 今回のドラッグが単一ファイルならTrue。
    function DragEnter(const dataObj: IDataObject; grfKeyState: Longint;
      pt: TPoint; var dwEffect: Longint): HResult; stdcall;
    function DragOver(grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult; stdcall;
    function DragLeave: HResult; stdcall;
    function Drop(const dataObj: IDataObject; grfKeyState: Longint;
      pt: TPoint; var dwEffect: Longint): HResult; stdcall;
  public
    // コールバックの所有者は登録解除まで生存させる。
    constructor Create(const Check: TTextureDropCheck; const Load: TTextureDropFile);
  end;

implementation

uses Winapi.ShellAPI, System.SysUtils;

function SingleDroppedFile(const Data: IDataObject): string;
var
  Format: TFormatEtc;
  Medium: TStgMedium;
  N: UINT;
begin
  Result := '';
  if Data = nil then Exit;
  Format := Default(TFormatEtc);
  Format.cfFormat := CF_HDROP;
  Format.dwAspect := DVASPECT_CONTENT;
  Format.lindex := -1;
  Format.tymed := TYMED_HGLOBAL;
  if Data.GetData(Format, Medium) <> S_OK then Exit;
  try
    if DragQueryFile(Medium.hGlobal, $FFFFFFFF, nil, 0) <> 1 then Exit;
    N := DragQueryFile(Medium.hGlobal, 0, nil, 0);
    SetLength(Result, N);
    DragQueryFile(Medium.hGlobal, 0, PChar(Result), N + 1);
  finally
    ReleaseStgMedium(Medium);
  end;
end;

constructor TMapRakuTextureDropTarget.Create(const Check: TTextureDropCheck; const Load: TTextureDropFile);
begin
  inherited Create;
  FCheck := Check;
  FLoad := Load;
end;

function TMapRakuTextureDropTarget.DragEnter(const dataObj: IDataObject; grfKeyState: Longint;
  pt: TPoint; var dwEffect: Longint): HResult;
begin
  FHasFile := SingleDroppedFile(dataObj) <> '';
  Result := DragOver(grfKeyState, pt, dwEffect);
end;

function TMapRakuTextureDropTarget.DragOver(grfKeyState: Longint;
  pt: TPoint; var dwEffect: Longint): HResult;
begin
  if FCheck(pt, FHasFile) and FHasFile and ((dwEffect and DROPEFFECT_COPY) <> 0) then
    dwEffect := DROPEFFECT_COPY
  else
    dwEffect := DROPEFFECT_NONE;
  Result := S_OK;
end;

function TMapRakuTextureDropTarget.DragLeave: HResult;
begin
  FCheck(TPoint.Zero, False);
  FHasFile := False;
  Result := S_OK;
end;

function TMapRakuTextureDropTarget.Drop(const dataObj: IDataObject; grfKeyState: Longint;
  pt: TPoint; var dwEffect: Longint): HResult;
var
  FileName: string;
begin
  Result := S_OK;
  dwEffect := DROPEFFECT_NONE;
  try
    FileName := SingleDroppedFile(dataObj);
    if (FileName <> '') and FCheck(pt, True) then
    begin
      if FLoad(FileName) then dwEffect := DROPEFFECT_COPY;
    end;
  except
    // COM境界へDelphi例外を漏らさない。読み込み側がエラーを表示する。
    Result := E_FAIL;
  end;
  DragLeave;
end;

end.
