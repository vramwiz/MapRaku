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
  MapRakuPluginRouteMarker,
  System.UITypes, TextRendererSkiaBootstrap, TextRendererSkiaRuntime,
  Vcl.Dialogs, Winapi.Windows;

const
  FILTER_EFFECT_NAME = '地図';
  LAYOUT_DATA_ITEM_NAME = '地図データ';
  // TFILTER_ITEM_FILE は表示名とワイルドカードを NUL で区切る Windows 形式。
  // "|" 区切りは解釈されず、ファイル種類の表示へそのまま出てしまう。
  MARKER_PNG_FILE_FILTER = 'PNG画像 (*.png)'#0'*.png'#0#0;
  GET_MODULE_HANDLE_EX_FLAG_PIN = $00000001;
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS = $00000004;

function GetModuleHandleExW(Flags: DWORD; ModuleName: PWideChar;
  out Module: HMODULE): BOOL; stdcall; external kernel32 name 'GetModuleHandleExW';

var
  EditButton: TFILTER_ITEM_BUTTON;
  ProgressItem, MarkerScaleItem, MarkerTransparencyItem, MarkerUnderpassTransparencyItem, MarkerOffsetXItem,
    MarkerOffsetYItem, RotationCorrectionItem, DisplayWidthItem,
    DisplayHeightItem, ScrollStartItem, AnimationAmountItem,
    AnimationSpeedItem, AnimationAuxItem, PointerSizeItem: TFILTER_ITEM_TRACK;
  MarkerFileItem: TFILTER_ITEM_FILE;
  MarkerFileValue: array[0..32767] of WideChar;
  MarkerColorItem: TFILTER_ITEM_COLOR;
  MarkerSelectItem, MarkerRotationItem: TFILTER_ITEM_SELECT;
  MarkerImageAnchorItem: TFILTER_ITEM_SELECT;
  RouteDisplayItem, AnimationModeItem, PointerKindItem: TFILTER_ITEM_SELECT;
  AnimationGroupItem, MarkerGroupItem: TFILTER_ITEM_GROUP;
  MarkerSelectList: array[0..1] of TFILTER_ITEM_SELECT_ITEM;
  MarkerRotationList: array[0..3] of TFILTER_ITEM_SELECT_ITEM;
  MarkerImageAnchorList: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  RouteDisplayList: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  AnimationModeList: array[0..5] of TFILTER_ITEM_SELECT_ITEM;
  PointerKindList: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  RouteColorItem: TFILTER_ITEM_COLOR;
  PointerColorItem: TFILTER_ITEM_COLOR;
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
  Motion: TMapRakuPluginRouteMotion;
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
        Motion.ProgressPercent := ProgressItem.Value;
        Motion.MarkerColor := GetColor(MarkerColorItem);
        Motion.MarkerTransparency := MarkerTransparencyItem.Value;
        Motion.MarkerUnderpassTransparency := MarkerUnderpassTransparencyItem.Value;
        Motion.MarkerScale := MarkerScaleItem.Value;
        Motion.MarkerOffsetX := MarkerOffsetXItem.Value;
        Motion.MarkerOffsetY := MarkerOffsetYItem.Value;
        Motion.MarkerRotation := MarkerRotationItem.Value;
        Motion.MarkerImageAnchor := MarkerImageAnchorItem.Value;
        Motion.PointerKind := PointerKindItem.Value;
        Motion.PointerColor := GetColor(PointerColorItem);
        Motion.PointerSize := PointerSizeItem.Value;
        Motion.AnimationMode := AnimationModeItem.Value;
        Motion.AnimationAmount := AnimationAmountItem.Value;
        Motion.AnimationSpeed := AnimationSpeedItem.Value;
        Motion.AnimationAux := AnimationAuxItem.Value;
        if Video^.Object_ = nil then
          Motion.AnimationTime := 0
        else
          Motion.AnimationTime := Video^.Object_^.Time;
        Motion.RotationCorrection := RotationCorrectionItem.Value;
        Motion.RouteDisplay := RouteDisplayItem.Value;
        Motion.RouteColor := GetColor(RouteColorItem);
        Motion.DisplayWidth := DisplayWidthItem.Value;
        Motion.DisplayHeight := DisplayHeightItem.Value;
        Motion.ScrollStartRate := ScrollStartItem.Value;
        Motion.DrawMarker := True;
        if MarkerFileItem.Value = nil then
          Motion.MarkerFileName := ''
        else
          Motion.MarkerFileName := MarkerFileItem.Value;
        Context.ProcessVideo(Video, SerializedData, Motion);
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
    AddTrack(ProgressItem, '進行位置', 0, 0, 100, 0.01);
    AddSelectList(RouteDisplayList, 'なし', 0);
    AddSelectList(RouteDisplayList, '軌跡', 1);
    AddSelect(RouteDisplayItem, 'ルート', 0, @RouteDisplayList[0]);
    AddColor(RouteColorItem, 'ルート色', $000000FF);
    // グループは表示上の整理だけで名前空間を分けない。接頭辞なしの項目名は
    // マーカー専用として予約し、他の機能には対象名を付けて重複を防ぐ。
    AddGroup(MarkerGroupItem, 'マーカー', 1);
    // AviUtl2はファイル選択結果をValueのバッファへ書く。文字列リテラルを
    // 渡すと選択後のパスを保持できないため、プラグインが所有する領域を使う。
    AddFile(MarkerFileItem, '画像ファイル', MarkerFileValue,
      PWideChar(MARKER_PNG_FILE_FILTER));
    AddSelectList(MarkerSelectList, '標準ピン', 0);
    AddSelect(MarkerSelectItem, '種類', 0, @MarkerSelectList[0]);
    AddColor(MarkerColorItem, '色', $00FF8000);
    AddTrack(MarkerScaleItem, '拡大率', 100, 1, 1000, 1);
    AddSelectList(MarkerImageAnchorList, '中央', 0);
    AddSelectList(MarkerImageAnchorList, '下中央', 1);
    AddSelect(MarkerImageAnchorItem, '基準点', 0,
      @MarkerImageAnchorList[0]);
    AddTrack(MarkerTransparencyItem, '透明度', 0, 0, 100, 1);
    AddTrack(MarkerUnderpassTransparencyItem, '下側透明度', 100, 0, 100, 1);
    AddTrack(MarkerOffsetXItem, 'オフセットX', 0, -4096, 4096, 1);
    AddTrack(MarkerOffsetYItem, 'オフセットY', 0, -4096, 4096, 1);
    AddSelectList(MarkerRotationList, '固定', 0);
    AddSelectList(MarkerRotationList, '進行方向', 1);
    AddSelectList(MarkerRotationList, '進行方向＋回転補正', 2);
    AddSelect(MarkerRotationItem, '回転', 0, @MarkerRotationList[0]);
    AddTrack(RotationCorrectionItem, '回転補正角度', 0, -180, 180, 0.1);
    AddSelectList(PointerKindList, 'なし', 0);
    AddSelectList(PointerKindList, '三角', 1);
    AddSelect(PointerKindItem, 'ポインターの種類', 0, @PointerKindList[0]);
    AddColor(PointerColorItem, 'ポインター色', $00000000);
    AddTrack(PointerSizeItem, 'ポインターサイズ', 10, 1, 100, 1);
    AddTrack(DisplayWidthItem, '表示幅', 1920, 1, 16384, 1);
    AddTrack(DisplayHeightItem, '表示高さ', 1080, 1, 16384, 1);
    AddTrack(ScrollStartItem, 'スクロール開始率', 25, 0, 50, 1);
    // 頻繁に触らない補助設定は表示関連の後、内部JSONの直前へまとめる。
    AddGroup(AnimationGroupItem, 'アニメーション', 0);
    AddSelectList(AnimationModeList, '無し', 0);
    AddSelectList(AnimationModeList, 'バウンド（一定）', 1);
    AddSelectList(AnimationModeList, 'バウンド（進行速度）', 2);
    AddSelectList(AnimationModeList, '振り子（一定）', 3);
    AddSelectList(AnimationModeList, '振り子（進行速度）', 4);
    AddSelect(AnimationModeItem, '揺れ', 0, @AnimationModeList[0]);
    AddTrack(AnimationAmountItem, '揺れ量', 10, 0, 100, 1);
    AddTrack(AnimationSpeedItem, '揺れ速度', 2, 0, 20, 0.1);
    // 現在は位相（度）として使う。開始・終了では常に0へ収束するため、
    // 複数マーカーの揺れをずらしても端点の見た目は崩れない。
    AddTrack(AnimationAuxItem, '揺れ補助', 0, -180, 180, 1);
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
