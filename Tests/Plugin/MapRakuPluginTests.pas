// DLL登録・映像合成・編集確定を疑似ホストから検証し、実AviUtl2での確認と区別する。
unit MapRakuPluginTests;

interface
procedure RunPluginTests(const PluginFile: string);
procedure ServePluginEditor;

implementation

uses System.SysUtils, System.Classes, System.UITypes, System.Types, System.Math,
  System.JSON, System.Skia, Winapi.Windows,
  Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  AviUtl2FilterTypes, MapRakuDocument, MapRakuDocumentJson,
  MapRakuPluginDocument, MapRakuFilterContext, MapRakuPluginRender,
  MapRakuPluginRouteMarker, MapRakuCanvasPreview,
  MapRakuRenderer, MapRakuEditorHost, MapRakuMainForm, MapRakuCanvas,
  MapRakuAutomationWire, MapRakuAutomationFactory,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap;

type
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TFinalize = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  PStringItem = ^TFILTER_ITEM_STRING;
  PButtonItem = ^TFILTER_ITEM_BUTTON;
  PTrackItem = ^TFILTER_ITEM_TRACK;
  TModalDriver = class
    SawEditor: Boolean;
    SawActionButtons: Boolean;
    procedure Tick(Sender: TObject);
    procedure HandleException(Sender: TObject; E: Exception);
  end;

const W = 80; H = 48;
var Returned: TBytes; SetCount: Integer;

procedure TModalDriver.HandleException(Sender: TObject; E: Exception);
begin
  // 非同期VCL例外も失敗にし、テストがダイアログで止まったり成功扱いにならないようにする。
  Writeln('FAIL VCL: ', E.ClassName, ': ', E.Message);
  Flush(Output);
  Halt(1);
end;

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

function FindPluginItem(Table: PFILTER_PLUGIN_TABLE;
  const Name: string): Pointer;
var I: Integer; Item: Pointer; ItemName: PWideChar;
begin
  Result := nil;
  if (Table = nil) or (Table^.Items = nil) then Exit;
  I := 0;
  while True do
  begin
    Item := PPointer(NativeUInt(Table^.Items) + NativeUInt(I) * SizeOf(Pointer))^;
    if Item = nil then Exit;
    ItemName := PPointer(NativeUInt(Item) + SizeOf(Pointer))^;
    if (ItemName <> nil) and (string(ItemName) = Name) then Exit(Item);
    Inc(I);
  end;
end;

procedure GetImage(Buffer: PPIXEL_RGBA); cdecl;
var I: Integer;
begin
  for I := 0 to W * H - 1 do
  begin
    Buffer^ := Default(TPIXEL_RGBA);
    Buffer^.R := 23; Buffer^.G := 45; Buffer^.B := 67; Buffer^.A := 255;
    Inc(Buffer);
  end;
end;

procedure SetImage(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  Check((Width = W) and (Height = H), 'Wrong output size');
  SetLength(Returned, Width * Height * 4);
  Move(Buffer^, Returned[0], Length(Returned));
  Inc(SetCount);
end;

procedure AddMapFixture(Doc: TVectArtDocument);
const Specs: array[0..2] of string = (
  '{"kind":"road","width":8,"vertices":[{"x":-35,"y":0},{"x":35,"y":0}]}',
  '{"kind":"jr","width":5,"vertices":[{"x":-10,"y":-20},{"x":-10,"y":20}]}',
  '{"kind":"rectangle","x":10,"y":-18,"width":12,"height":10,"color":255}');
var Spec: TJSONObject; Text: string;
begin
  for Text in Specs do
  begin
    Spec := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try Doc.InsertLayer(Doc.LayerCount, CreateAutomationLayer(Spec, Doc));
    finally Spec.Free; end;
  end;
end;

procedure TestDll(const PluginFile: string);
var Module: HMODULE; Init: TInitialize; Done: TFinalize; Table: PFILTER_PLUGIN_TABLE;
  GetTable: TGetTable; Data: PStringItem; Button: PButtonItem;
  Video: TFILTER_PROC_VIDEO; Obj: TOBJECT_INFO; Doc: TVectArtDocument;
  Json: string; Expected: TVectArtRenderBuffer;
begin
  Module := LoadLibrary(PChar(PluginFile));
  if Module = 0 then RaiseLastOSError;
  try
    Init := TInitialize(GetProcAddress(Module, 'InitializePlugin'));
    Done := TFinalize(GetProcAddress(Module, 'UninitializePlugin'));
    GetTable := TGetTable(GetProcAddress(Module, 'GetFilterPluginTable'));
    Check(Assigned(Init) and Assigned(Done) and Assigned(GetTable), 'Missing exports');
    Check(Init(0) = 1, 'Initialization failed');
    try
      Table := GetTable();
      Check((string(Table^.Name) = '地図') and (string(Table^.Label_) = 'SYNC'), 'Registration mismatch');
      Check(Table = GetTable(), 'Registration must be stable');
      Button := PButtonItem(FindPluginItem(Table, '編集'));
      Data := PStringItem(FindPluginItem(Table, '地図データ'));
      Check((string(Button^.Name) = '編集') and Assigned(Button^.Callback), 'Missing editor');
      Check((Data <> nil) and (string(Data^.Name) = '地図データ'), 'Missing data item');
      Check((PTrackItem(FindPluginItem(Table, '進行位置')) <> nil) and
        (PTrackItem(FindPluginItem(Table, '進行位置'))^.Step = 0.01),
        'Missing progress parameter');
      Check((FindPluginItem(Table,'透明度')<>nil) and
        (FindPluginItem(Table,'下側透明度')<>nil),
        'Missing normal/underpass transparency controls');
      Check((PTrackItem(FindPluginItem(Table,'透明度'))^.Value=0) and
        (PTrackItem(FindPluginItem(Table,'下側透明度'))^.Value=100),
        'Transparency defaults must be normal opaque and underpass transparent');
      Check(FindPluginItem(Table, '基準点') <> nil,
        'Missing marker image anchor parameter');
      Check((FindPluginItem(Table, 'ポインターの種類') <> nil) and
        (FindPluginItem(Table, 'ポインター色') <> nil) and
        (FindPluginItem(Table, 'ポインターサイズ') <> nil),
        'Missing direction pointer parameters');
      Check((FindPluginItem(Table, 'アニメーション') <> nil) and
        (FindPluginItem(Table, '揺れ') <> nil) and
        (FindPluginItem(Table, '揺れ量') <> nil) and
        (FindPluginItem(Table, '揺れ速度') <> nil) and
        (FindPluginItem(Table, '揺れ補助') <> nil),
        'Missing marker animation parameters');
      Obj := Default(TOBJECT_INFO); Obj.ID := 41; Obj.EffectID := 1;
      Obj.Width := W; Obj.Height := H;
      Video := Default(TFILTER_PROC_VIDEO); Video.Object_ := @Obj;
      Video.GetImageData := GetImage; Video.SetImageData := SetImage;
      Doc := TVectArtDocument.Create; Expected := TVectArtRenderBuffer.Create;
      try
        SetCount := 0; Data^.Value := '';
        Check(Table^.Func_Proc_Video(@Video) = 1, 'Empty callback failed');
        Check(SetCount = 0, 'Unconfigured map must pass through');
        Doc.SetCanvasSize(W, H);
        Doc.CanvasLayer.BackgroundColor := RGB(91, 123, 157);
        Json := SerializeVectArtDocument(Doc); Data^.Value := PChar(Json);
        Table^.Func_Proc_Video(@Video);
        Check((SetCount = 1) and (Returned[0] = 91) and (Returned[3] = 255), 'Opaque background missing');
        Doc.CanvasLayer.Transparent := True;
        Json := SerializeVectArtDocument(Doc); Data^.Value := PChar(Json);
        Table^.Func_Proc_Video(@Video);
        Check((Returned[0] = 23) and (Returned[2] = 67), 'Transparent composition failed');
        Data^.Value := '{broken'; Table^.Func_Proc_Video(@Video);
        Check(Returned[0] = 23, 'Invalid JSON destroyed last valid document');
        Obj.EffectID := 2; Data^.Value := ''; SetCount := 0;
        Table^.Func_Proc_Video(@Video);
        Check(SetCount = 0, 'Second effect inherited first effect state');
        Obj.EffectID := 1; Data^.Value := ''; SetCount := 0;
        Table^.Func_Proc_Video(@Video);
        Check(SetCount = 0, 'Clearing saved data did not restore passthrough');
        Doc.CanvasLayer.Transparent := False;
        AddMapFixture(Doc);
        Json := SerializeVectArtDocument(Doc); Data^.Value := PChar(Json);
        Table^.Func_Proc_Video(@Video);
        RenderMapRakuPlugin(Doc, Expected, W, H);
        Check(CompareMem(Expected.Data, @Returned[0], Length(Returned)), 'DLL render differs from common render');
      finally
        Data^.Value := ''; Expected.Free; Doc.Free;
      end;
    finally Done(); end;
    Check(Init(0) = 1, 'Reinitialization failed');
    Done();
  finally FreeLibrary(Module); end;
  Writeln('PASS DLL exports, registration, background, alpha, object isolation, map render parity, reload');
end;

procedure TModalDriver.Tick(Sender: TObject);
var I, J, K: Integer; Form: TMainForm; Panel: TPanel;
  Button: TButton;
begin
  for I := 0 to Screen.FormCount - 1 do
    if (Screen.Forms[I] is TMainForm) and Screen.Forms[I].Visible then
    begin
      TTimer(Sender).Enabled := False;
      Form := TMainForm(Screen.Forms[I]);
      SawEditor := True;
      Form.Document.SetCanvasSize(640, 360);
      // ホスト画面には下部の操作パネルを置かない。右上の×と同じCancel結果で
      // 閉じても、呼び出し側が現在のDocumentを確定することを検証する。
      for J := 0 to Form.ComponentCount - 1 do
        if Form.Components[J] is TPanel then
        begin
          Panel := TPanel(Form.Components[J]);
          for K := 0 to Panel.ComponentCount - 1 do
            if Panel.Components[K] is TButton then
            begin
              Button := TButton(Panel.Components[K]);
              SawActionButtons := SawActionButtons or
                (Button.Caption = '適用') or (Button.Caption = '取消');
            end;
        end;
      Form.ModalResult := mrCancel;
    end;
end;

procedure TestModal;
var Driver: TModalDriver; Timer: TTimer; Updated, ErrorText, PreviousPipe: string;
  Applied: Boolean; Doc: TVectArtDocument;
begin
  Driver := TModalDriver.Create; Timer := TTimer.Create(nil);
  Application.OnException := Driver.HandleException;
  Doc := TVectArtDocument.Create;
  try
    Timer.Interval := 100; Timer.OnTimer := Driver.Tick;
    Timer.Enabled := True;
    Applied := EditMapRaku('', nil, 0, 0, W, H, Updated, ErrorText);
    Check(Driver.SawEditor and not Driver.SawActionButtons,
      'Hosted editor still has apply/cancel controls: ' + ErrorText);
    Check(Applied and (ErrorText = ''), 'Closing editor did not apply data');
    Check(TryDeserializeVectArtDocument(Updated, Doc, ErrorText),
      'Closing editor produced invalid JSON');
    Check(Doc.CanvasLayer.Width = 640, 'Closing editor lost edits');
    PreviousPipe := AutomationPipeShortName;
    Timer.Enabled := True;
    Applied := EditMapRaku('', nil, 0, 0, W, H, Updated, ErrorText);
    Check(Applied and (ErrorText = ''), 'Apply failed: ' + ErrorText);
    Check(AutomationPipeShortName <> PreviousPipe, 'Reopened editor reused old endpoint');
    Check(TryDeserializeVectArtDocument(Updated, Doc, ErrorText), 'Apply JSON invalid');
    Check(Doc.CanvasLayer.Width = 640, 'Apply lost edits');
  finally Application.OnException := nil; Doc.Free; Timer.Free; Driver.Free; end;
  Writeln('PASS hosted editor close/apply and full editing area');
end;

procedure TestBackgrounds;
var Canvas: TVectArtCanvasControl; Doc: TVectArtDocument; Pixels: TBytes;
  Bitmap: TBitmap;
begin
  Canvas := TVectArtCanvasControl.Create(nil); Doc := TVectArtDocument.Create;
  Bitmap := TBitmap.Create;
  try
    Canvas.Document := Doc; Doc.CanvasLayer.Transparent := True;
    SetLength(Pixels, 4); Pixels[0] := 42; Pixels[3] := 255;
    Canvas.SetHostBackgroundRgba(Pixels, 1, 1);
    Check(Canvas.DisplayBackgroundKind = 'host', 'Host background missing');
    Canvas.CopyReferenceBackground(Bitmap);
    Check(Bitmap.Empty, 'Host must not replace AI source');
    Pixels[0] := 84; Canvas.SetReferenceBackgroundRgba(Pixels, 1, 1);
    Check(Canvas.DisplayBackgroundKind = 'reference', 'AI source priority failed');
    Canvas.SetReferenceBackgroundRgba(nil, 0, 0);
    Check(Canvas.DisplayBackgroundKind = 'host', 'Clearing source lost host image');
    Doc.CanvasLayer.Transparent := False;
    Check(Canvas.DisplayBackgroundKind = 'none', 'Opaque canvas should hide host');
  finally Canvas.Free; Doc.Free; Bitmap.Free; end;
  Writeln('PASS host/source background separation');
end;

procedure TestContexts;
var Contexts: TMapRakuFilterContexts; Video: TFILTER_PROC_VIDEO; Obj: TOBJECT_INFO;
  First, Second: TMapRakuFilterContext;
begin
  Contexts := TMapRakuFilterContexts.Create;
  try
    Video := Default(TFILTER_PROC_VIDEO); Obj := Default(TOBJECT_INFO);
    Video.Object_ := @Obj; Obj.ID := 1; Obj.EffectID := 1;
    First := Contexts.GetContext(@Video);
    Check(Contexts.FindByObjectLocation(0, 0, 0) = First, 'Context lookup failed');
    Obj.EffectID := 2; Second := Contexts.GetContext(@Video);
    Check(First <> Second, 'Effect contexts must differ');
    Check(Contexts.FindByObjectLocation(0, 0, 0) = nil, 'Ambiguous location returned wrong effect');
    Check(Contexts.FindByKey(1, 1) = First, 'ID lookup failed');
  finally Contexts.Free; end;
  Writeln('PASS context identity and ambiguous background suppression');
end;

procedure TestMarkerAnimation;
var Motion: TMapRakuPluginRouteMotion; Base, Position: TPointF;
  Angle: Single;
begin
  Base := PointF(40, 30);
  Motion := Default(TMapRakuPluginRouteMotion);
  Motion.AnimationAmount := 10;
  Motion.AnimationSpeed := 0.5;
  Motion.AnimationMode := 2;
  Motion.ProgressPercent := 0;
  ApplyMapRakuPluginMarkerAnimation(Motion, Base, 15, Position, Angle);
  Check(SameValue(Position.X, Base.X) and SameValue(Position.Y, Base.Y) and
    SameValue(Angle, 15),
    'Animation changed route start');
  Motion.ProgressPercent := 50;
  ApplyMapRakuPluginMarkerAnimation(Motion, Base, 15, Position, Angle);
  Check((Position.Y < Base.Y) and SameValue(Angle, 15),
    'Bounce was not upward only');
  Motion.ProgressPercent := 100;
  ApplyMapRakuPluginMarkerAnimation(Motion, Base, 15, Position, Angle);
  Check(SameValue(Position.X, Base.X) and SameValue(Position.Y, Base.Y) and
    SameValue(Angle, 15),
    'Animation changed route end');
  Motion.AnimationMode := 4;
  Motion.AnimationSpeed := 0.5;
  Motion.ProgressPercent := 50;
  ApplyMapRakuPluginMarkerAnimation(Motion, Base, 15, Position, Angle);
  Check(SameValue(Position.X, Base.X) and SameValue(Position.Y, Base.Y) and
    SameValue(Angle, 25),
    'Swing did not add to base angle');
  Writeln('PASS marker animation endpoints, bounce, and swing');
end;

procedure AddRouteCrossingFixture(Doc: TVectArtDocument);
var Data: TVectArtPathData; Marker: TMapRakuGroupLayer; I: Integer;
begin
  Doc.SetCanvasSize(W,H);
  Doc.CanvasLayer.Transparent:=True;
  Data:=Default(TVectArtPathData);
  Data.Visible:=True; Data.Opacity:=1; Data.StrokeWidth:=6;
  Data.StrokeColor:=clRed; Data.MapElement:='route'; Data.RouteId:='crossing-test';
  SetLength(Data.Vertices,2);
  Data.Vertices[0].Position:=PointF(-35,0);
  Data.Vertices[1].Position:=PointF(35,0);
  Doc.InsertPath(1,Data);
  Doc.InsertLayer(2,TMapRakuLevelBoundaryLayer.Create);
  Data.MapElement:='road'; Data.RouteId:=''; Data.StrokeColor:=clWhite;
  Data.StrokeWidth:=8; Data.Opacity:=0.5;
  Data.Vertices[0].Position:=PointF(0,-24);
  Data.Vertices[1].Position:=PointF(0,24);
  Doc.InsertPath(3,Data);
  for I:=0 to 1 do begin
    Marker:=TMapRakuGroupLayer.Create('marker');
    if I=0 then Marker.RouteMarkerKind:='start' else Marker.RouteMarkerKind:='end';
    Marker.RoutePathId:='crossing-test'; Marker.HasRouteMarkerPosition:=True;
    Marker.RouteMarkerPosition:=PointF(-35+70*I,0);
    Doc.InsertLayer(Doc.LayerCount,Marker);
  end;
end;

procedure TestRouteCrossingClip;
var Doc:TVectArtDocument; Buffer,Image,Road:TVectArtRenderBuffer;
  Motion:TMapRakuPluginRouteMotion; I,X,Y:Integer; Kind:TMapRakuCrossingKind;
  Bitmap:TBitmap; Row:PByte; Surface:ISkSurface;
  procedure Draw;
  begin
    Buffer.Clear;
    DrawMapRakuPluginRouteLayer(Doc,Buffer,Motion,1,Image);
  end;
  procedure CheckHidden;
  begin
    Check(Buffer.Pixels[24*W+40].A=0,'Route ink leaked through crossing');
    Check(Buffer.Pixels[24*W+28].A=0,'Trail leaked into bridge margin');
    Check(Buffer.Pixels[24*W+10].A>0,'Trail before crossing disappeared');
  end;
begin
  Doc:=TVectArtDocument.Create; Buffer:=TVectArtRenderBuffer.Create;
  Image:=TVectArtRenderBuffer.Create; Road:=TVectArtRenderBuffer.Create;
  Bitmap:=TBitmap.Create;
  try
    AddRouteCrossingFixture(Doc); Buffer.SetSize(W,H);
    Motion:=Default(TMapRakuPluginRouteMotion);
    Motion.ProgressPercent:=50; Motion.RouteDisplay:=1; Motion.RouteColor:=clRed;
    Motion.DrawMarker:=True; Motion.MarkerScale:=100; Motion.MarkerTransparency:=0; Motion.MarkerUnderpassTransparency:=100;
    Motion.MarkerColor:=clBlue;
    Draw; CheckHidden;
    // 移動ピン単体とSpace用プレビューも中央の高架下では描画されない。
    Motion.RouteDisplay:=0; Draw;
    for Y:=9 to 38 do
      for X:=27 to 52 do
        Check(Buffer.Pixels[Y*W+X].A=0,'Built-in marker leaked under bridge');
    RenderRoutePreviewBitmap(Doc,TVectArtPathLayer(Doc[1]),PointF(0,0),1,Bitmap);
    for Y:=9 to 38 do begin
      Row:=Bitmap.ScanLine[Y];
      for X:=0 to Bitmap.Width-1 do Check(Row[X*4+3]=0,'Space preview leaked');
    end;
    Motion.ProgressPercent:=10; Draw;
    Check(Buffer.Pixels[14*W+12].A>0,'Marker before crossing disappeared');
    Motion.ProgressPercent:=90; Draw;
    Check(Buffer.Pixels[14*W+68].A>0,'Marker after crossing disappeared');
    // 透過画像、回転、拡大、オフセット後も、共通道路クリップ外へだけ描く。
    Image.SetSize(32,32);
    for I:=0 to Image.PixelCount-1 do begin
      Image.Pixels[I].R:=255; Image.Pixels[I].A:=128;
    end;
    Motion.ProgressPercent:=50; Motion.MarkerScale:=140;
    Motion.MarkerRotation:=2; Motion.RotationCorrection:=20;
    Motion.MarkerOffsetX:=3; Motion.PointerKind:=1; Motion.PointerSize:=12;
    Motion.PointerColor:=clLime; Motion.RouteDisplay:=1;
    for Kind in [mckOverpass,mckBridge,mckRailOverpass,mckUnderpass,mckTunnel] do begin
      Doc.SetCrossingRelation(Doc[1].PersistentId,Doc[3].PersistentId,
        Kind,Doc[3].PersistentId);
      Draw; CheckHidden;
      RenderVectArtDocumentRange(Doc,Road,W,H,1,1);
      for X:=5 to 74 do
        if Road.Pixels[24*W+X].A=0 then
          Check(Buffer.Pixels[24*W+X].A=0,'Route differs from road gap');
    end;
    // 出力画像は同じバッファから保存し、目視確認にも使う。
    Surface:=TSkSurface.MakeRasterDirect(TSkImageInfo.Create(W,H,
      TSkColorType.RGBA8888,TSkAlphaType.Unpremul),Buffer.Data,Buffer.Stride);
    Surface.MakeImageSnapshot.EncodeToFile('TestOutput/route-crossing-clip.png',
      TSkEncodedImageFormat.PNG);
    Surface:=nil;
    Doc.SetCrossingRelation(Doc[1].PersistentId,Doc[3].PersistentId,
      mckOverpass,Doc[1].PersistentId);
    Draw;
    Check(Buffer.Pixels[24*W+40].A>0,'Upper route incorrectly clipped');
    Doc.SetCrossingRelation(Doc[1].PersistentId,Doc[3].PersistentId,
      mckNormal,Doc[3].PersistentId);
    Draw;
    Check(Buffer.Pixels[24*W+40].A>0,'Normal crossing incorrectly clipped');
  finally Bitmap.Free; Road.Free; Image.Free; Buffer.Free; Doc.Free; end;
  Writeln('PASS route trail, built-in/image marker, pointer, Space preview and crossing clips');
end;

procedure TestRouteCrossingSegments;
var Doc:TVectArtDocument; Buffer,Road:TVectArtRenderBuffer;
  Motion:TMapRakuPluginRouteMotion; Data:TVectArtPathData;
  Vertices:TArray<TMapRakuVertex>; X:Integer;
begin
  Doc:=TVectArtDocument.Create; Buffer:=TVectArtRenderBuffer.Create;
  Road:=TVectArtRenderBuffer.Create;
  try
    AddRouteCrossingFixture(Doc);
    // 斜交と縦横で異なる出力倍率でも、道路の切断と同じ位置になる。
    Vertices:=Copy(TVectArtPathLayer(Doc[3]).Vertices);
    Vertices[0].Position.X:=-12; Vertices[1].Position.X:=12;
    Doc.SetPathVertices(3,Vertices);
    Motion:=Default(TMapRakuPluginRouteMotion);
    Motion.ProgressPercent:=100; Motion.RouteDisplay:=1; Motion.RouteColor:=clRed;
    Buffer.SetSize(W*2,H*3); Buffer.Clear;
    DrawMapRakuPluginRouteLayer(Doc,Buffer,Motion,1,nil);
    RenderVectArtDocumentRange(Doc,Road,W*2,H*3,1,1);
    for X:=12 to 147 do
      if Road.Pixels[72*W*2+X].A=0 then
        Check(Buffer.Pixels[72*W*2+X].A=0,'Scaled diagonal crossing gap differs');
    // 同じ論理ルートを下層と上層に分割。通過済み下層の隠れ方を保持する。
    Vertices:=Copy(TVectArtPathLayer(Doc[1]).Vertices);
    Vertices[1].Position.X:=0; Doc.SetPathVertices(1,Vertices);
    Data:=Default(TVectArtPathData); Data.Visible:=True; Data.Opacity:=1;
    Data.MapElement:='route'; Data.RouteId:='crossing-test'; Data.StrokeWidth:=6;
    Data.Vertices:=Copy(Vertices); Data.Vertices[0].Position.X:=0;
    Data.Vertices[1].Position.X:=35; Doc.InsertPath(4,Data);
    Vertices[0].Position:=PointF(-15,-24); Vertices[1].Position:=PointF(-15,24);
    Doc.SetPathVertices(3,Vertices);
    Doc.SetCrossingRelation(Doc[1].PersistentId,Doc[3].PersistentId,
      mckOverpass,Doc[3].PersistentId);
    Buffer.SetSize(W,H); Buffer.Clear;
    Motion.ProgressPercent:=75;
    DrawMapRakuPluginRouteLayer(Doc,Buffer,Motion,1,nil);
    DrawMapRakuPluginRouteLayer(Doc,Buffer,Motion,4,nil);
    Check(Buffer.Pixels[24*W+25].A=0,'Completed lower segment lost its clip');
    Check(Buffer.Pixels[24*W+52].A>0,'Upper segment trail disappeared');
    Check(Buffer.Pixels[24*W+70].A=0,'Unreached segment trail appeared');
    Motion.DrawMarker:=True; Motion.RouteDisplay:=0; Motion.ProgressPercent:=25;
    Motion.MarkerScale:=100; Motion.MarkerTransparency:=0; Motion.MarkerUnderpassTransparency:=100; Buffer.Clear;
    DrawMapRakuPluginRouteLayer(Doc,Buffer,Motion,1,nil);
    DrawMapRakuPluginRouteLayer(Doc,Buffer,Motion,4,nil);
    Check(Buffer.Pixels[14*W+22].A=0,'Lower segment marker lost its clip');
    Motion.ProgressPercent:=75; Buffer.Clear;
    DrawMapRakuPluginRouteLayer(Doc,Buffer,Motion,1,nil);
    DrawMapRakuPluginRouteLayer(Doc,Buffer,Motion,4,nil);
    Check(Buffer.Pixels[14*W+57].A>0,'Upper segment inherited lower clip');
  finally Road.Free; Buffer.Free; Doc.Free; end;
  Writeln('PASS diagonal/scaled crossing and lower-to-upper route segments');
end;

procedure TestMarkerTransparency;
const Values: array[0..2] of Integer = (0,50,100);
var Doc:TVectArtDocument; Buffer,Image:TVectArtRenderBuffer;
  Motion:TMapRakuPluginRouteMotion; Normal,Lower,I:Integer;
  procedure Draw;
  begin
    Buffer.Clear;
    DrawMapRakuPluginRouteLayer(Doc,Buffer,Motion,1,Image);
  end;
begin
  Doc:=TVectArtDocument.Create; Buffer:=TVectArtRenderBuffer.Create;
  Image:=TVectArtRenderBuffer.Create;
  try
    AddRouteCrossingFixture(Doc); Buffer.SetSize(W,H);
    Image.SetSize(60,40);
    for I:=0 to Image.PixelCount-1 do begin
      Image.Pixels[I].R:=255; Image.Pixels[I].A:=255;
    end;
    Motion:=Default(TMapRakuPluginRouteMotion);
    Motion.ProgressPercent:=50; Motion.DrawMarker:=True; Motion.MarkerScale:=100;
    for Normal in Values do
      for Lower in Values do begin
        Motion.MarkerTransparency:=Normal;
        Motion.MarkerUnderpassTransparency:=Lower;
        Draw;
        Check(Abs(Buffer.Pixels[24*W+15].A-(100-Normal)*255/100)<=1,
          'Normal transparency must be independent: 0 opaque, 100 transparent');
        Check(Abs(Buffer.Pixels[24*W+40].A-(100-Lower)*255/100)<=1,
          'Underpass transparency must be independent: 0 opaque, 100 transparent');
      end;
    for I:=0 to Image.PixelCount-1 do Image.Pixels[I].A:=128;
    Motion.MarkerTransparency:=50; Motion.MarkerUnderpassTransparency:=50;
    Draw;
    Check(Abs(Buffer.Pixels[24*W+15].A-64)<=1,'PNG source alpha not retained');
    Check(Abs(Buffer.Pixels[24*W+40].A-64)<=1,'PNG underpass source alpha not retained');
    Image.SetSize(0,0); Draw;
    Check(Abs(Buffer.Pixels[14*W+40].A-128)<=1,
      'Overlapping pin shapes applied transparency more than once');
    Motion.DrawMarker:=False; Motion.RouteDisplay:=1; Motion.RouteColor:=clRed;
    Motion.MarkerTransparency:=100; Motion.MarkerUnderpassTransparency:=0;
    Draw;
    Check(Buffer.Pixels[24*W+15].A=255,'Marker transparency changed trail');
    Check(Buffer.Pixels[24*W+40].A=0,'Underpass marker transparency exposed trail');
  finally Image.Free; Buffer.Free; Doc.Free; end;
  Writeln('PASS independent normal/underpass transparency 0/50/100, PNG alpha and unchanged trail');
end;

procedure TestRouteCrossingVideo;
var Doc:TVectArtDocument; Context:TMapRakuFilterContext;
  Motion:TMapRakuPluginRouteMotion; Video:TFILTER_PROC_VIDEO; Obj:TOBJECT_INFO;
  Index:Integer;
begin
  Doc:=TVectArtDocument.Create; Context:=TMapRakuFilterContext.Create;
  try
    AddRouteCrossingFixture(Doc);
    Obj:=Default(TOBJECT_INFO); Obj.Width:=W; Obj.Height:=H;
    Video:=Default(TFILTER_PROC_VIDEO); Video.Object_:=@Obj;
    Video.GetImageData:=GetImage; Video.SetImageData:=SetImage;
    Motion:=Default(TMapRakuPluginRouteMotion);
    Motion.DisplayWidth:=W; Motion.DisplayHeight:=H; Motion.ScrollStartRate:=0;
    Motion.ProgressPercent:=50; Motion.RouteDisplay:=1; Motion.RouteColor:=clRed;
    Motion.MarkerScale:=100; Motion.MarkerTransparency:=0; Motion.MarkerUnderpassTransparency:=100; Motion.MarkerColor:=clBlue;
    Check(Context.UpdateSerializedData(SerializeVectArtDocument(Doc)),'Fixture load');
    Check(Context.RenderVideo(@Video,Motion),'Video render');
    Index:=(24*W+28)*4;
    Check((Returned[Index]=23) and (Returned[Index+1]=45) and
      (Returned[Index+2]=67),'Bridge margin must preserve input background');
    Index:=(14*W+40)*4;
    Check((Returned[Index]>23) and (Returned[Index+2]>67),
      'Translucent bridge replaced by final marker');
    Motion.MarkerTransparency:=100; Motion.MarkerUnderpassTransparency:=0;
    Check(Context.RenderVideo(@Video,Motion),'Underpass-only marker video render');
    Check((Returned[Index]=0) and (Returned[Index+1]=0) and
      (Returned[Index+2]=255),'Underpass opacity was overwritten by upper road');
    Motion.MarkerTransparency:=0; Motion.MarkerUnderpassTransparency:=100;
    Motion.ProgressPercent:=100;
    Check(Context.RenderVideo(@Video,Motion),'Cached video render');
    Index:=(24*W+52)*4;
    Check((Returned[Index]=23) and (Returned[Index+2]=67),'Cached trail leaked');
    Doc[3].Visible:=False;
    Check(Context.UpdateSerializedData(SerializeVectArtDocument(Doc)),'Updated fixture');
    Check(Context.RenderVideo(@Video,Motion),'Invalidated video render');
    Check(Returned[Index]=255,'Hidden bridge did not invalidate clip mask');
  finally Context.Free; Doc.Free; end;
  Writeln('PASS final video bridge gap, translucent upper path, cached progress and invalidation');
end;

procedure RunPluginTests(const PluginFile: string);
begin
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  try
    TestContexts;
    TestMarkerAnimation;
    TestRouteCrossingClip;
    TestRouteCrossingSegments;
    TestMarkerTransparency;
    TestRouteCrossingVideo;
    TestBackgrounds;
    TestModal;
    TestDll(PluginFile);
    TestModal;
  finally TTextRendererSkiaRuntime.Release; end;
end;

procedure ServePluginEditor;
var Form: TMainForm; Sink: TModalDriver;
begin
  Sink := TModalDriver.Create;
  Application.OnException := Sink.HandleException;
  Form := nil;
  try
    Form := TMainForm.CreateHosted(nil);
    Form.Caption := '地図 - パイプ検証';
    Form.ShowModal;
  finally Form.Free; Application.OnException := nil; Sink.Free; end;
end;

end.
