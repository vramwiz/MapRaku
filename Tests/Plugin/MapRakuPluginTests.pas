// DLL登録・映像合成・編集確定を疑似ホストから検証し、実AviUtl2での確認と区別する。
unit MapRakuPluginTests;

interface
procedure RunPluginTests(const PluginFile: string);
procedure ServePluginEditor;

implementation

uses System.SysUtils, System.Classes, System.UITypes, System.JSON, Winapi.Windows,
  Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  AviUtl2FilterTypes, MapRakuDocument, MapRakuDocumentJson,
  MapRakuPluginDocument, MapRakuFilterContext, MapRakuPluginRender,
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
    Accept: Boolean;
    SawEndpoint: Boolean;
    SawEditor: Boolean;
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
      Check(FindPluginItem(Table, 'マーカー画像の基準点') <> nil,
        'Missing marker image anchor parameter');
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
var I, J: Integer; Form: TMainForm; Button: TButton;
begin
  for I := 0 to Screen.FormCount - 1 do
    if (Screen.Forms[I] is TMainForm) and Screen.Forms[I].Visible then
    begin
      TTimer(Sender).Enabled := False;
      Form := TMainForm(Screen.Forms[I]);
      SawEditor := True;
      SawEndpoint := AutomationPipeShortName.StartsWith('MapRaku.Plugin.') and
        (AutomationHostKind = 'aviutl2');
      Form.Document.SetCanvasSize(640, 360);
      // 実際に配置された確定ボタンを押し、モーダル戻り値と保存データを確認する。
      for J := 0 to Form.ComponentCount - 1 do
        if Form.Components[J] is TPanel then
          for var K := 0 to TPanel(Form.Components[J]).ComponentCount - 1 do
            if TPanel(Form.Components[J]).Components[K] is TButton then
            begin
              Button := TButton(TPanel(Form.Components[J]).Components[K]);
              if (Accept and (Button.Caption = '適用')) or
                (not Accept and (Button.Caption = '取消')) then
              begin
                Button.Click;
                Exit;
              end;
            end;
      Form.ModalResult := mrAbort;
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
    Driver.Accept := False; Timer.Enabled := True;
    Applied := EditMapRaku('', nil, 0, 0, W, H, Updated, ErrorText);
    Check(Driver.SawEditor and Driver.SawEndpoint, 'Hosted editor was not shown: ' + ErrorText);
    Check(not Applied and (Updated = '') and (ErrorText = ''), 'Cancel modified host data');
    PreviousPipe := AutomationPipeShortName;
    Driver.Accept := True; Timer.Enabled := True;
    Applied := EditMapRaku('', nil, 0, 0, W, H, Updated, ErrorText);
    Check(Applied and (ErrorText = ''), 'Apply failed: ' + ErrorText);
    Check(AutomationPipeShortName <> PreviousPipe, 'Reopened editor reused old endpoint');
    Check(TryDeserializeVectArtDocument(Updated, Doc, ErrorText), 'Apply JSON invalid');
    Check(Doc.CanvasLayer.Width = 640, 'Apply lost edits');
  finally Application.OnException := nil; Doc.Free; Timer.Free; Driver.Free; end;
  Writeln('PASS common modal UI, cancel/apply, fresh endpoint');
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

procedure RunPluginTests(const PluginFile: string);
begin
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  try
    TestContexts;
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
