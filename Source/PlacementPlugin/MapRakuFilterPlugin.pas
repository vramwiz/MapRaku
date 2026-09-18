// AviUtl2へ「地図」を登録し、編集ボタンとシリアライズ文字列項目だけを公開する。
unit MapRakuFilterPlugin;

interface

uses
  System.SysUtils, AviUtl2FilterTypes;

// AviUtl2へ渡すフィルターテーブルを返す。
function GetMapRakuFilterTable: PFILTER_PLUGIN_TABLE;
// 描画ランタイムとオブジェクト別の描画状態を確保する。
procedure InitializeMapRakuFilter;
// コールバック終了後に描画状態とランタイムを解放する。
procedure FinalizeMapRakuFilter;

implementation

uses
  PluginFilterTable, MapRakuEditorHost, MapRakuFilterContext,
  System.UITypes, TextRendererSkiaBootstrap, TextRendererSkiaRuntime,
  Vcl.Dialogs, Winapi.Windows;

const
  FILTER_EFFECT_NAME = '地図';
  LAYOUT_DATA_ITEM_NAME = '地図データ';
  GET_MODULE_HANDLE_EX_FLAG_PIN = $00000001;
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS = $00000004;

function GetModuleHandleExW(Flags: DWORD; ModuleName: PWideChar;
  out Module: HMODULE): BOOL; stdcall; external kernel32 name 'GetModuleHandleExW';

var
  EditButton: TFILTER_ITEM_BUTTON;
  LayoutDataItem: TFILTER_ITEM_STRING;
  MapRakuContexts: TMapRakuFilterContexts;
  MapRakuSkiaAcquired: Boolean;

procedure EditButtonCallback(Edit: PEDIT_SECTION); cdecl;
var
  BackgroundHeight: Integer;
  BackgroundPixels: TBytes;
  BackgroundStatus: string;
  BackgroundWidth: Integer;
  CanvasHeight: Integer;
  CanvasWidth: Integer;
  Context: TMapRakuFilterContext;
  CurrentData: string;
  DataPointer: PAnsiChar;
  ErrorMessage: string;
  Obj: OBJECT_HANDLE;
  ObjectLocation: TOBJECT_LAYER_FRAME;
  UpdatedData: string;
  Utf8Data: UTF8String;
begin
  try
    if (Edit = nil) or not Assigned(Edit^.GetFocusObject) or
      not Assigned(Edit^.GetObjectLayerFrame) or
      not Assigned(Edit^.GetObjectItemValue) or
      not Assigned(Edit^.SetObjectItemValue) then
      raise EInvalidOp.Create('AviUtl2の編集APIを取得できませんでした。');
    Obj := Edit^.GetFocusObject();
    if Obj = nil then
      raise EInvalidOp.Create('編集対象のオブジェクトを取得できませんでした。');

    DataPointer := Edit^.GetObjectItemValue(Obj, FILTER_EFFECT_NAME,
      LAYOUT_DATA_ITEM_NAME);
    if DataPointer = nil then
      CurrentData := ''
    else
      CurrentData := string(UTF8String(DataPointer));

    BackgroundPixels := nil;
    BackgroundWidth := 0;
    BackgroundHeight := 0;
    CanvasWidth := 0;
    CanvasHeight := 0;
    ObjectLocation := Edit^.GetObjectLayerFrame(Obj);
    if MapRakuContexts <> nil then
    begin
      Context := MapRakuContexts.FindByObjectLocation(
        ObjectLocation.Layer, ObjectLocation.StartFrame,
        ObjectLocation.EndFrame);
      if Context <> nil then
      begin
        Context.CopyBackground(BackgroundPixels, BackgroundWidth,
          BackgroundHeight, BackgroundStatus);
        Context.CopyOutputSize(CanvasWidth, CanvasHeight);
      end;
    end;
    if (CanvasWidth <= 0) or (CanvasHeight <= 0) then
    begin
      // 映像コールバック前の編集では、取得済みの参照背景寸法を代替値にする。
      CanvasWidth := BackgroundWidth;
      CanvasHeight := BackgroundHeight;
    end;

    if not EditMapRaku(CurrentData, BackgroundPixels,
      BackgroundWidth, BackgroundHeight, CanvasWidth, CanvasHeight,
      UpdatedData, ErrorMessage) then
    begin
      if ErrorMessage <> '' then
        raise EInvalidOp.Create('地図を編集できませんでした。'#13#10 + ErrorMessage);
      Exit;
    end;

    Utf8Data := UTF8String(UpdatedData);
    if not Edit^.SetObjectItemValue(Obj, FILTER_EFFECT_NAME,
      LAYOUT_DATA_ITEM_NAME, PAnsiChar(Utf8Data)) then
      raise EInvalidOp.Create('地図データをAviUtl2へ保存できませんでした。');
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

function PassThroughVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Context: TMapRakuFilterContext;
  SerializedData: string;
begin
  Result := 1;
  try
    // AviUtl2は呼び出し対象の現在値を項目レコードへ設定してから呼び出す。
    if LayoutDataItem.Value = nil then
      SerializedData := ''
    else
      SerializedData := string(LayoutDataItem.Value);
    if MapRakuContexts <> nil then
    begin
      Context := MapRakuContexts.GetContext(Video);
      if Context <> nil then
      begin
        Context.ProcessVideo(Video, SerializedData);
      end;
    end;
  except
    // Delphi例外をAviUtl2の映像コールバック境界より外へ漏らさない。
  end;
end;

procedure InitializeMapRakuFilter;
var Module: HMODULE;
begin
  // Skiaのストリームコールバックは共有DLL内に残る。コードだけはプロセス終了まで
  // 保持し、他のSkia利用者が解放済みのDelphi関数を呼ぶ実行違反を防ぐ。
  // 文書・画像・描画状態はUninitializePluginで通常どおり解放する。
  if IsLibrary and not GetModuleHandleExW(
    GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS or GET_MODULE_HANDLE_EX_FLAG_PIN,
    PChar(@InitializeMapRakuFilter), Module) then RaiseLastOSError;
  if not MapRakuSkiaAcquired then
  begin
    TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
    MapRakuSkiaAcquired := True;
  end;
  try
    if MapRakuContexts = nil then
      MapRakuContexts := TMapRakuFilterContexts.Create;
  except
    if MapRakuSkiaAcquired then
    begin
      TTextRendererSkiaRuntime.Release;
      MapRakuSkiaAcquired := False;
    end;
    raise;
  end;
end;

procedure FinalizeMapRakuFilter;
begin
  FreeAndNil(MapRakuContexts);
  if MapRakuSkiaAcquired then
  begin
    TTextRendererSkiaRuntime.Release;
    MapRakuSkiaAcquired := False;
  end;
end;

function GetMapRakuFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if GTable.Name = nil then
  begin
    AddButton(EditButton, '編集', EditButtonCallback);
    AddString(LayoutDataItem, LAYOUT_DATA_ITEM_NAME, '');
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER,
      FILTER_EFFECT_NAME,
      'SYNC',
      '道路・線路・施設を配置する地図フィルター',
      PassThroughVideo,
      nil);
  end;
  Result := @GTable;
end;

end.
