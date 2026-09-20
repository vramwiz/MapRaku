// 地図のシリアライズ値と解析済みDocumentをAviUtl2オブジェクト単位で保持する。
unit MapRakuFilterContext;

interface

uses
  AviUtl2FilterTypes, PluginFilterContextManager, MapRakuFrameCapture,
  System.SysUtils, System.Types, System.Math, System.Generics.Collections, Winapi.Windows, MapRakuDocument, MapRakuRenderer,
  MapRakuPluginRouteMarker, MapRakuCrossingRenderer, MapRakuRouteProgress;

type
  TMapRakuFilterContext = class(TPluginFilterContextItem)
  private
    FFrameCapture: TMapRakuFrameCapture;
    FDocument: TVectArtDocument;
    FRouteCache: TMapRakuRouteProgressData;
    FRouteCacheRevision: Int64;
    FRouteBuildCount: Integer;
    FLastAttemptedData: string;
    FLastError: string;
    FOutputBuffer: TVectArtRenderBuffer;
    FRouteOverlayBuffer: TVectArtRenderBuffer;
    FMapLayerBuffer: TVectArtRenderBuffer;
    FMarkerBuffer: TVectArtRenderBuffer;
    FMarkerImage: TVectArtRenderBuffer;
    FMarkerImageFileName: string;
    FRouteClipMasks: TObjectList<TVectArtRenderBuffer>;
    FStaticLayerBuffers: TObjectList<TVectArtRenderBuffer>;
    FStaticRouteLayerIndices: TList<Integer>;
    FStaticMapBuffer: TVectArtRenderBuffer;
    FStaticHasPixels: TArray<Boolean>;
    FRouteGroupEnd: TArray<Boolean>;
    FRouteCompositeGroupCount: Integer;
    FStaticCacheRevision: Int64;
    FStaticCacheWidth: Integer;
    FStaticCacheHeight: Integer;
    FStaticCacheHasRoute: Boolean;
    FStaticCacheData: string;
    FLastPerformanceLogTick: UInt64;
    FProcessWaitMs, FProcessUpdateMs, FProcessCaptureMs: Double;
    FViewportBuffer: TVectArtRenderBuffer;
    FOutputHeight: Integer;                 // 最後に描画した有効な出力高さ。
    FOutputSizeLock: TRTLCriticalSection;   // 映像処理と設定画面の寸法共有を保護する。
    FOutputWidth: Integer;                  // 最後に描画した有効な出力幅。
    FOverlayBuffer: TVectArtRenderBuffer;
    FRenderedRevision: Int64;
    FSerializedData: string;
    FRenderLock: TRTLCriticalSection;
    procedure UpdateRouteCache;
    procedure UpdateStaticMapCache(Width, Height: Integer; HasRoute: Boolean);
    procedure UpdateMarkerImage(const FileName: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure ProcessVideo(Video: PFILTER_PROC_VIDEO; const Value: string;
      const Motion: TMapRakuPluginRouteMotion);
    // 対象オブジェクト評価時のAviUtl2合成済み背景を更新する。
    procedure CaptureBackground(Video: PFILTER_PROC_VIDEO);
    // 設定画面が使用する最新背景を呼び出し側所有の配列で返す。
    function CopyBackground(out Pixels: TBytes; out Width, Height: Integer;
      out Status: string): Boolean;
    // 映像コールバックが最後に使用した有効な出力寸法をスレッド安全に返す。
    function CopyOutputSize(out Width, Height: Integer): Boolean;
    // 共通レンダラーのRGBAを入力映像へ合成してAviUtl2へ返す。
    function RenderVideo(Video: PFILTER_PROC_VIDEO;
      const Motion: TMapRakuPluginRouteMotion): Boolean;
    // 設定値が変わったときだけDocumentを更新し、解析失敗時は直前の正常状態を保つ。
    function UpdateSerializedData(const Value: string): Boolean;
    property RouteCompositeGroupCount: Integer read FRouteCompositeGroupCount;
    property RouteBuildCount: Integer read FRouteBuildCount;
    property Document: TVectArtDocument read FDocument;
    property LastError: string read FLastError;
    property SerializedData: string read FSerializedData;
  end;

  TMapRakuFilterContexts = class(TPluginFilterContextList<TMapRakuFilterContext>);

implementation

uses
  MapRakuDocumentJson, MapRakuPluginRender, MapRakuPluginViewport, System.Diagnostics,
  System.IOUtils, Vcl.Imaging.pngimage;

procedure WritePerformanceLog(LastTick: PUInt64; Width, Height, Layers: Integer;
  MapMilliseconds, ViewportMilliseconds, CompositeMilliseconds,
  TotalMilliseconds: Double; const Detail: string);
var NowTick: UInt64; FileName, Line: string;
begin
  NowTick:=GetTickCount64;
  if (NowTick-LastTick^)<1000 then Exit;
  LastTick^:=NowTick;
  Line:=Format('%s %dx%d layers=%d map=%.2fms viewport=%.2fms output=%.2fms total=%.2fms',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now),Width,Height,Layers,
     MapMilliseconds,ViewportMilliseconds,CompositeMilliseconds,TotalMilliseconds]);
  Line:=Line+Format(' pid=%d ',[GetCurrentProcessId])+Detail;
{$IFDEF DEBUG}
  Line:=Line+' build=Debug';
{$ELSE}
  Line:=Line+' build=Release';
{$ENDIF}
  OutputDebugString(PChar('MapRaku performance: '+Line));
  try
    FileName:=TPath.Combine(TPath.GetTempPath,'MapRakuPluginPerformance.log');
    TFile.AppendAllText(FileName,Line+sLineBreak,TEncoding.UTF8);
  except
    // 診断ログの失敗で映像コールバックを止めない。
  end;
end;

constructor TMapRakuFilterContext.Create;
begin
  inherited Create;
  InitializeCriticalSection(FOutputSizeLock);
  InitializeCriticalSection(FRenderLock);
  FDocument := TVectArtDocument.Create;
  FFrameCapture := TMapRakuFrameCapture.Create;
  FOutputBuffer := TVectArtRenderBuffer.Create;
  FRouteOverlayBuffer := TVectArtRenderBuffer.Create;
  FMapLayerBuffer := TVectArtRenderBuffer.Create;
  FMarkerBuffer := TVectArtRenderBuffer.Create;
  FMarkerImage := TVectArtRenderBuffer.Create;
  FRouteClipMasks := TObjectList<TVectArtRenderBuffer>.Create(True);
  FStaticLayerBuffers := TObjectList<TVectArtRenderBuffer>.Create(True);
  FStaticRouteLayerIndices := TList<Integer>.Create;
  FStaticMapBuffer := TVectArtRenderBuffer.Create;
  FStaticCacheRevision := -1;
  FRouteCacheRevision := -1;
  FViewportBuffer := TVectArtRenderBuffer.Create;
  FOverlayBuffer := TVectArtRenderBuffer.Create;
  FRenderedRevision := -1;
end;

destructor TMapRakuFilterContext.Destroy;
begin
  DeleteCriticalSection(FOutputSizeLock);
  DeleteCriticalSection(FRenderLock);
  FOverlayBuffer.Free;
  FMapLayerBuffer.Free;
  FMarkerBuffer.Free;
  FMarkerImage.Free;
  FStaticMapBuffer.Free;
  FRouteClipMasks.Free;
  FStaticLayerBuffers.Free;
  FStaticRouteLayerIndices.Free;
  FViewportBuffer.Free;
  FRouteOverlayBuffer.Free;
  FOutputBuffer.Free;
  FFrameCapture.Free;
  FDocument.Free;
  inherited Destroy;
end;

procedure TMapRakuFilterContext.UpdateMarkerImage(const FileName: string);
var Png:TPngImage; X,Y:Integer; Row,Alpha:PByte; Pixel:PVectArtRgbaPixel;
begin
  // フレームごとのファイルI/Oを避ける。読込失敗は直前の画像を残さず空にして、
  // 削除・破損した外部ファイルが映像コールバックを失敗させないようにする。
  if FileName=FMarkerImageFileName then Exit;
  FMarkerImageFileName:=FileName; FMarkerImage.SetSize(0,0);
  if (FileName='') or not TFile.Exists(FileName) then Exit;
  try
    Png:=TPngImage.Create;
    try
      Png.LoadFromFile(FileName);
      if (Png.Width<=0)or(Png.Height<=0)or(Png.Width>4096)or(Png.Height>4096) then Exit;
      FMarkerImage.SetSize(Png.Width,Png.Height); Pixel:=FMarkerImage.Data;
      for Y:=0 to Png.Height-1 do begin
        Row:=Png.Scanline[Y]; Alpha:=PByte(Png.AlphaScanline[Y]);
        for X:=0 to Png.Width-1 do begin
          Pixel^.B:=Row[X*3]; Pixel^.G:=Row[X*3+1]; Pixel^.R:=Row[X*3+2]; Pixel^.A:=Alpha[X]; Inc(Pixel);
        end;
      end;
    finally Png.Free; end;
  except
    FMarkerImage.SetSize(0,0);
  end;
end;

procedure TMapRakuFilterContext.UpdateStaticMapCache(Width, Height: Integer;
  HasRoute: Boolean);
var I,J, FirstLayerIndex: Integer; Layer: TVectArtRenderBuffer; Pixel: NativeInt;
  Crossings: TMapCrossingRenderContext;
begin
  // 進行位置以外の地図は再生中に変化しない。ルート前後の範囲を平坦化して、
  // 動的な軌跡だけを正しいレイヤー順へ差し込めるようにする。
  if (FStaticCacheRevision=FDocument.Revision) and
     (FStaticCacheWidth=Width) and (FStaticCacheHeight=Height) and
     (FStaticCacheHasRoute=HasRoute) and (FStaticCacheData=FSerializedData) then Exit;
  FRouteClipMasks.Clear;
  FStaticLayerBuffers.Clear;
  FStaticRouteLayerIndices.Clear;
  FStaticHasPixels:=nil; FRouteGroupEnd:=nil; FRouteCompositeGroupCount:=0;
  if not HasRoute then
    RenderMapRakuPlugin(FDocument,FStaticMapBuffer,Width,Height)
  else begin
    for I:=1 to FDocument.LayerCount-1 do
      if (FDocument[I] is TVectArtPathLayer) and
         (TVectArtPathLayer(FDocument[I]).MapElement='route') then
        FStaticRouteLayerIndices.Add(I);
    // 非表示化する前のルートで交差を解決し、進行位置だけの変化では再計算しない。
    Crossings:=TMapCrossingRenderContext.Create(FDocument);
    try
      for I:=0 to FStaticRouteLayerIndices.Count-1 do begin
        Layer:=TVectArtRenderBuffer.Create;
        FRouteClipMasks.Add(Layer);
        Crossings.RenderLowerMask(Layer,FDocument[FStaticRouteLayerIndices[I]],
          Width,Height,TRectF.Create(-FDocument.CanvasLayer.Width*0.5,
          -FDocument.CanvasLayer.Height*0.5,FDocument.CanvasLayer.Width*0.5,
          FDocument.CanvasLayer.Height*0.5));
      end;
    finally Crossings.Free; end;
    FirstLayerIndex:=1;
    for I:=0 to FStaticRouteLayerIndices.Count do begin
      Layer:=TVectArtRenderBuffer.Create;
      if I<FStaticRouteLayerIndices.Count then
        RenderMapRakuPluginRange(FDocument,Layer,Width,Height,
          FirstLayerIndex,FStaticRouteLayerIndices[I])
      else
        RenderMapRakuPluginRange(FDocument,Layer,Width,Height,
          FirstLayerIndex,FDocument.LayerCount-1);
      FStaticLayerBuffers.Add(Layer);
      if I<FStaticRouteLayerIndices.Count then
        FirstLayerIndex:=FStaticRouteLayerIndices[I]+1;
    end;
  end;
  if HasRoute then begin
    SetLength(FStaticHasPixels,FStaticLayerBuffers.Count);
    for I:=0 to FStaticLayerBuffers.Count-1 do
      for Pixel:=0 to FStaticLayerBuffers[I].PixelCount-1 do
        if FStaticLayerBuffers[I].Pixels[Pixel].A<>0 then begin
          FStaticHasPixels[I]:=True; Break;
        end;
    SetLength(FRouteGroupEnd,FStaticRouteLayerIndices.Count);
    for I:=0 to High(FRouteGroupEnd) do begin
      FRouteGroupEnd[I]:=(I=High(FRouteGroupEnd)) or FStaticHasPixels[I+1];
      if I<High(FRouteGroupEnd) then
        for J:=FStaticRouteLayerIndices[I]+1 to FStaticRouteLayerIndices[I+1]-1 do
          if FDocument[J] is TMapRakuLevelBoundaryLayer then FRouteGroupEnd[I]:=True;
      if FRouteGroupEnd[I] then Inc(FRouteCompositeGroupCount);
    end;
    // 軌跡なしでは静止部分を一枚にまとめ、進行位置だけの変更で再合成しない。
    FStaticMapBuffer.SetSize(Width,Height); FStaticMapBuffer.Clear;
    for I:=0 to FStaticLayerBuffers.Count-1 do
      if FStaticHasPixels[I] then
        CompositeVectArtRgba(FStaticLayerBuffers[I],FStaticMapBuffer.Data,Width,Height);
  end;
  // ルートを一時非表示にするレンダラーはDocumentのRevisionを更新するため、
  // すべてのキャッシュ更新後の値を基準にする。
  FStaticCacheRevision:=FDocument.Revision;
  FStaticCacheWidth:=Width; FStaticCacheHeight:=Height;
  FStaticCacheHasRoute:=HasRoute;
  FStaticCacheData:=FSerializedData;
end;

procedure TMapRakuFilterContext.UpdateRouteCache;
var I:Integer; RouteId,ErrorText:string;
begin
  if FRouteCacheRevision=FDocument.Revision then Exit;
  FRouteCache:=Default(TMapRakuRouteProgressData);
  for I:=1 to FDocument.LayerCount-1 do
    if (FDocument[I] is TVectArtPathLayer) and
      (TVectArtPathLayer(FDocument[I]).MapElement='route') then
    begin
      RouteId:=MapRakuRouteIdentifier(TVectArtPathLayer(FDocument[I]));
      Inc(FRouteBuildCount);
      if not TryBuildMapRakuRoute(FDocument,RouteId,FRouteCache,ErrorText) then
        FRouteCache:=Default(TMapRakuRouteProgressData);
      Break;
    end;
  FRouteCacheRevision:=FDocument.Revision;
end;
procedure TMapRakuFilterContext.ProcessVideo(Video: PFILTER_PROC_VIDEO;
  const Value: string; const Motion: TMapRakuPluginRouteMotion);
var Watch: TStopwatch; WaitMs: Double;
begin
  Watch:=TStopwatch.StartNew;
  // 同じ効果の並列評価で文書の差替えと描画バッファの書込みを交差させない。
  EnterCriticalSection(FRenderLock);
  WaitMs:=Watch.Elapsed.TotalMilliseconds;
  try
    FProcessWaitMs:=WaitMs;
    Watch:=TStopwatch.StartNew;
    UpdateSerializedData(Value);
    FProcessUpdateMs:=Watch.Elapsed.TotalMilliseconds;
    Watch:=TStopwatch.StartNew;
    CaptureBackground(Video);
    FProcessCaptureMs:=Watch.Elapsed.TotalMilliseconds;
    RenderVideo(Video, Motion);
  finally
    FProcessWaitMs:=0; FProcessUpdateMs:=0; FProcessCaptureMs:=0;
    LeaveCriticalSection(FRenderLock);
  end;
end;

function TMapRakuFilterContext.RenderVideo(Video: PFILTER_PROC_VIDEO;
  const Motion: TMapRakuPluginRouteMotion): Boolean;
var
  Height: Integer;
  HasRoute: Boolean;
  I: Integer;
  MarkerMotion, TrailMotion: TMapRakuPluginRouteMotion;
  CompositeWatch, MapWatch, TotalWatch, ViewportWatch, Phase: TStopwatch;
  StaticMs,RouteMs,TrailDrawMs,BlendMs,MarkerDrawMs,MarkerBlendMs: Double;
  StaticRebuilt:Boolean;
  InputMs, CompositeMs, SubmitMs: Double;
  Width: Integer;
begin
  Result := False;
  TotalWatch:=TStopwatch.StartNew;
  if (Video = nil) or not Assigned(Video^.SetImageData) then
    Exit;
  Width := 0;
  Height := 0;
  if Video^.Object_ <> nil then
  begin
    Width := Video^.Object_^.Width;
    Height := Video^.Object_^.Height;
  end;
  if ((Width <= 0) or (Height <= 0)) and (Video^.Scene <> nil) then
  begin
    Width := Video^.Scene^.Width;
    Height := Video^.Scene^.Height;
  end;
  if (Width <= 0) or (Height <= 0) or
    (Width > 16384) or (Height > 16384) then
    Exit;
  EnterCriticalSection(FOutputSizeLock);
  try
    FOutputWidth := Width;
    FOutputHeight := Height;
  finally
    LeaveCriticalSection(FOutputSizeLock);
  end;

  // 未設定では入力映像を維持する。取消しただけで白い地図を出さない。
  if FSerializedData = '' then Exit(True);
  UpdateMarkerImage(Motion.MarkerFileName);
  MapWatch:=TStopwatch.StartNew;
  HasRoute:=False;
  for I:=1 to FDocument.LayerCount-1 do
    HasRoute:=HasRoute or ((FDocument[I] is TVectArtPathLayer) and
      (TVectArtPathLayer(FDocument[I]).MapElement='route'));
  StaticRebuilt:=(FStaticCacheRevision<>FDocument.Revision) or
    (FStaticCacheWidth<>Width) or (FStaticCacheHeight<>Height) or
    (FStaticCacheHasRoute<>HasRoute) or (FStaticCacheData<>FSerializedData);
  Phase:=TStopwatch.StartNew;
  UpdateStaticMapCache(Width,Height,HasRoute);
  StaticMs:=Phase.Elapsed.TotalMilliseconds; Phase:=TStopwatch.StartNew;
  UpdateRouteCache;
  RouteMs:=Phase.Elapsed.TotalMilliseconds;
  TrailDrawMs:=0; MarkerDrawMs:=0; MarkerBlendMs:=0;
  Phase:=TStopwatch.StartNew;
  if not HasRoute then begin
    FOverlayBuffer.SetSize(Width,Height); FOverlayBuffer.Clear;
    CompositeVectArtRgba(FStaticMapBuffer,FOverlayBuffer.Data,Width,Height);
    BlendMs:=Phase.Elapsed.TotalMilliseconds;
  end else begin
    // 動画用ルートを本来のレイヤー順へ差し込む。各レイヤーの交差クリップは
    // 既存レンダラーが生成し、後の上側レイヤーが移動体を覆う。
    FOverlayBuffer.SetSize(Width,Height);
    TrailMotion:=Motion; TrailMotion.DrawMarker:=False;
    if Motion.RouteDisplay<>1 then begin
      Move(FStaticMapBuffer.Data^,FOverlayBuffer.Data^,Width*Height*4);
      BlendMs:=Phase.Elapsed.TotalMilliseconds;
    end else begin
      // 最下部は透明バッファへの合成ではなく、キャッシュのコピーで初期化する。
      Move(FStaticLayerBuffers[0].Data^,FOverlayBuffer.Data^,Width*Height*4);
      BlendMs:=Phase.Elapsed.TotalMilliseconds;
      for I:=0 to FStaticRouteLayerIndices.Count-1 do begin
        Phase:=TStopwatch.StartNew;
        if (I=0) or FRouteGroupEnd[I-1] then begin
          FRouteOverlayBuffer.SetSize(Width,Height); FRouteOverlayBuffer.Clear;
        end;
        DrawMapRakuPluginRouteLayer(FDocument,FRouteOverlayBuffer,TrailMotion,
          FStaticRouteLayerIndices[I],FMarkerImage,FRouteClipMasks[I],@FRouteCache);
        TrailDrawMs:=TrailDrawMs+Phase.Elapsed.TotalMilliseconds;
        Phase:=TStopwatch.StartNew;
        if FRouteGroupEnd[I] then begin
          CompositeVectArtRgba(FRouteOverlayBuffer,FOverlayBuffer.Data,Width,Height);
          if FStaticHasPixels[I+1] then
            CompositeVectArtRgba(FStaticLayerBuffers[I+1],FOverlayBuffer.Data,Width,Height);
        end;
        BlendMs:=BlendMs+Phase.Elapsed.TotalMilliseconds;
      end;
    end;
    // 頂点で隣接区間の軌跡に覆われないよう、マーカーだけを最後に重ねる。
    // 共通クリップの内外へ通常／道路の下の透明度を適用済み。
    // 道路の下を表示する設定も、上側道路の上塗りで失わない。
    Phase:=TStopwatch.StartNew;

    MarkerMotion:=Motion; MarkerMotion.RouteDisplay:=0; MarkerMotion.DrawMarker:=True;
    for I:=0 to FStaticRouteLayerIndices.Count-1 do
      DrawMapRakuPluginRouteLayer(FDocument,FOverlayBuffer,MarkerMotion,
        FStaticRouteLayerIndices[I],FMarkerImage,FRouteClipMasks[I],@FRouteCache);
    MarkerDrawMs:=Phase.Elapsed.TotalMilliseconds; Phase:=TStopwatch.StartNew;

    MarkerBlendMs:=Phase.Elapsed.TotalMilliseconds;
  end;
  MapWatch.Stop;
  ViewportWatch:=TStopwatch.StartNew;
  RenderMapRakuPluginViewport(FDocument,FOverlayBuffer,FViewportBuffer,Motion,@FRouteCache);
  ViewportWatch.Stop;
  CompositeWatch:=TStopwatch.StartNew;
  Phase:=TStopwatch.StartNew;
  FOutputBuffer.SetSize(Width, Height);
  if Assigned(Video^.GetImageData) then
    Video^.GetImageData(PPIXEL_RGBA(FOutputBuffer.Data))
  else
    FOutputBuffer.Clear;
  InputMs:=Phase.Elapsed.TotalMilliseconds; Phase:=TStopwatch.StartNew;
  CompositeVectArtRgba(FViewportBuffer, FOutputBuffer.Data, Width, Height);
  CompositeMs:=Phase.Elapsed.TotalMilliseconds; Phase:=TStopwatch.StartNew;
  Video^.SetImageData(PPIXEL_RGBA(FOutputBuffer.Data), Width, Height);
  SubmitMs:=Phase.Elapsed.TotalMilliseconds;
  CompositeWatch.Stop;
  TotalWatch.Stop;
  WritePerformanceLog(@FLastPerformanceLogTick,Width,Height,FDocument.LayerCount,
    MapWatch.Elapsed.TotalMilliseconds,ViewportWatch.Elapsed.TotalMilliseconds,
    CompositeWatch.Elapsed.TotalMilliseconds,TotalWatch.Elapsed.TotalMilliseconds,
    Format('static_rebuilt=%s static=%.3f route=%.3f route_builds=%d route_groups=%d trail=%.3f layer_blend=%.3f marker=%.3f marker_blend=%.3f input=%.3f composite=%.3f submit=%.3f lock_wait=%.3f update=%.3f capture=%.3f process=%.3f diag=2',
      [BoolToStr(StaticRebuilt,True),StaticMs,RouteMs,FRouteBuildCount,FRouteCompositeGroupCount,
       TrailDrawMs,BlendMs,MarkerDrawMs,MarkerBlendMs,InputMs,CompositeMs,SubmitMs,
       FProcessWaitMs,FProcessUpdateMs,FProcessCaptureMs,
       FProcessWaitMs+FProcessUpdateMs+FProcessCaptureMs+TotalWatch.Elapsed.TotalMilliseconds]));
  Result := True;
end;

procedure TMapRakuFilterContext.CaptureBackground(
  Video: PFILTER_PROC_VIDEO);
begin
  FFrameCapture.Capture(Video);
end;

function TMapRakuFilterContext.CopyBackground(out Pixels: TBytes;
  out Width, Height: Integer; out Status: string): Boolean;
begin
  Result := FFrameCapture.CopyRgba(Pixels, Width, Height, Status);
end;

function TMapRakuFilterContext.CopyOutputSize(out Width,
  Height: Integer): Boolean;
begin
  EnterCriticalSection(FOutputSizeLock);
  try
    Width := FOutputWidth;
    Height := FOutputHeight;
  finally
    LeaveCriticalSection(FOutputSizeLock);
  end;
  Result := (Width > 0) and (Height > 0);
end;

function TMapRakuFilterContext.UpdateSerializedData(const Value: string): Boolean;
var
  ErrorMessage: string;
  NewDocument: TVectArtDocument;
begin
  if Value = FLastAttemptedData then
    Exit(FLastError = '');

  FLastAttemptedData := Value;
  FLastError := '';
  NewDocument := TVectArtDocument.Create;
  try
    if (Value <> '') and
      not TryDeserializeVectArtDocument(Value, NewDocument, ErrorMessage) then
    begin
      FLastError := ErrorMessage;
      Exit(False);
    end;
    FRouteCache:=Default(TMapRakuRouteProgressData);
    FRouteCacheRevision:=-1;
    FDocument.Free;
    FDocument := NewDocument;
    NewDocument := nil;
    FRenderedRevision := -1;
    FSerializedData := Value;
    Result := True;
  finally
    NewDocument.Free;
  end;
end;

end.
