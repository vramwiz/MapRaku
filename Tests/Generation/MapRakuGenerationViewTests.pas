// 参照範囲の色・周辺マスクと送信用画像の一致、ページ移動による条件保持を検証する。
unit MapRakuGenerationViewTests;
interface
procedure CheckGenerationReferenceView;
implementation
uses System.SysUtils, System.Types, System.Classes, System.JSON, System.IOUtils,
  System.Skia, Vcl.Forms, Vcl.Controls, Vcl.Skia, Vcl.StdCtrls, Vcl.ExtCtrls,
  MapRakuGenerationImage, MapRakuTraceOptions, MapRakuReferenceView,
  MapRakuRenderBuffer, MapRakuTestSupport, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState, MapRakuCanvas, MapRakuGenerationSession, MapRakuGenerationForm,
  MapRakuDarkDialogControls, HorizontalTrackBarControl;

function Capture(View: TMapRakuReferenceView): ISkImage;
var Surface: ISkSurface; Draw: TSkPaintBox;
begin
  Surface := TSkSurface.MakeRaster(View.Width,View.Height);
  Draw := View.Controls[0] as TSkPaintBox;
  Draw.OnDraw(Draw,Surface.Canvas,TRectF.Create(0,0,View.Width,View.Height),1);
  Result := Surface.MakeImageSnapshot;
end;

function ReadPixel(const Image: ISkImage; X,Y: Integer): TVectArtRgbaPixel;
var Buffer: TVectArtRenderBuffer; Info: TSkImageInfo;
begin
  Buffer := TVectArtRenderBuffer.Create;
  try
    Buffer.SetSize(Image.Width,Image.Height);
    Info := TSkImageInfo.Create(Image.Width,Image.Height,TSkColorType.RGBA8888,TSkAlphaType.Unpremul);
    Check(Image.ReadPixels(Info,Buffer.Data,Buffer.Stride),'Read reference pixels');
    Result := Buffer.Pixels[Y*Image.Width+X];
  finally Buffer.Free; end;
end;

procedure CheckReferencePixels;
var Surface: ISkSurface; Image, ResultImage: ISkImage; Paint: ISkPaint;
  Bytes, Output: TBytes; Stream: TBytesStream; Options: TMapRakuTraceOptions;
  View: TMapRakuReferenceView; Host: TForm; Inside, Outside: TVectArtRgbaPixel;
begin
  Surface := TSkSurface.MakeRaster(320,180); Surface.Canvas.Clear($FF80C0F0);
  Stream := TBytesStream.Create; Host := TForm.Create(nil);
  View := TMapRakuReferenceView.Create(Host); View.Parent := Host;
  try
    Surface.MakeImageSnapshot.EncodeToStream(Stream); Bytes := Copy(Stream.Bytes,0,Stream.Size);
    TFile.WriteAllBytes('TestOutput/reference-test.png',Bytes);
    View.SetBounds(0,0,800,600); View.LoadImage('TestOutput/reference-test.png');
    Options := TMapRakuTraceOptions.Default;
    Check(GenerationImageHash(BuildGenerationReference(Bytes,Options))=GenerationImageHash(Bytes),'Identity image must retain exact bytes');
    Options.Zoom := 2; View.Options := Options; Image := Capture(View);
    Inside := ReadPixel(Image,400,300); Outside := ReadPixel(Image,30,300);
    Check((Inside.R=128) and (Inside.G=192) and (Inside.B=240),'Crop area must keep original colors');
    Check((Outside.R<Inside.R div 2) and (Outside.G<Inside.G div 2) and
      (Outside.B<Inside.B div 2),'Outside must show the same image darkened');
    Output := BuildGenerationReference(Bytes,Options); ResultImage := TSkImage.MakeFromEncoded(Output);
    Inside := ReadPixel(ResultImage,3,90);
    Check((Inside.R=128) and (Inside.G=192) and (Inside.B=240),'Trace image must exclude shade and crop marks');
    Paint := TSkPaint.Create; Paint.Color := $FFFF0000;
    Surface.Canvas.DrawRect(TRectF.Create(0,0,160,180),Paint); Stream.Clear;
    Surface.MakeImageSnapshot.EncodeToStream(Stream); Bytes := Copy(Stream.Bytes,0,Stream.Size);
    Options := TMapRakuTraceOptions.Default; Options.Rotation := 180;
    ResultImage := TSkImage.MakeFromEncoded(BuildGenerationReference(Bytes,Options));
    Inside := ReadPixel(ResultImage,300,90); Outside := ReadPixel(ResultImage,20,90);
    Check((Inside.R=255) and (Inside.G=0) and (Outside.R=128),'Baked rotation must move source pixels');
    Options := TMapRakuTraceOptions.Default; Options.PanX := 0.5;
    ResultImage := TSkImage.MakeFromEncoded(BuildGenerationReference(Bytes,Options));
    Inside := ReadPixel(ResultImage,20,90);
    Check((Inside.R=255) and (Inside.G=255) and (Inside.B=255),'Panned uncovered image area must be white');
    if TFile.Exists('Artifacts/image-workflow-tokyo/source-map.png') then begin
      View.LoadImage('Artifacts/image-workflow-tokyo/source-map.png');
      Options.Zoom := 1.15; Options.PanX := 0.02; Options.PanY := -0.01; Options.Rotation := -17;
      View.Options := Options; Capture(View).EncodeToFile('TestOutput/reference-viewport.png');
    end;
  finally Host.Free; Stream.Free; end;
end;

function Button(Form: TForm; const Caption: string): TDarkDialogButton;
begin
  Result := nil;
  for var I := 0 to Form.ComponentCount-1 do
    if (Form.Components[I] is TDarkDialogButton) and
      (TDarkDialogButton(Form.Components[I]).Caption=Caption) then Exit(TDarkDialogButton(Form.Components[I]));
  Check(False,'Missing workflow button: '+Caption);
end;

procedure RefreshWorkflow(Form: TForm);
begin
  for var I := 0 to Form.ComponentCount-1 do
    if Form.Components[I] is TTimer then
      TTimer(Form.Components[I]).OnTimer(nil);
end;

procedure CheckCompletedPreview(Form: TMapRakuGenerationForm; Session: TMapRakuGenerationSession);
var Reply: TJSONObject; ResultHost, ReferenceHost: TWinControl; Image: TImage; Height: Integer;
begin
  ResultHost := Form.FindComponent('GenerationResultHost') as TWinControl;
  ReferenceHost := (Form.FindComponent('GenerationReference') as TWinControl).Parent;
  Image := Form.FindComponent('GenerationResultPreview') as TImage;
  Check(not ResultHost.Visible,'Result should be hidden before data completes');
  Session.PrepareTrace;
  Reply := TJSONObject.Create;
  try
    for var Key in TArray<string>.Create('generation_id','span_m','north_clockwise_degrees','canvas_width','canvas_height') do
      Reply.AddPair(Key,Session.Request.GetValue(Key).Clone as TJSONValue);
    Reply.AddPair('outcome','ready').AddPair('place_label','プレビュー試験')
      .AddPair('message','完成した地図を参照画像と上下に比較する試験')
      .AddPair('latitude',TJSONNumber.Create(0)).AddPair('longitude',TJSONNumber.Create(0))
      .AddPair('sources',TJSONArray.Create).AddPair('warnings',TJSONArray.Create)
      .AddPair('source_image_sha256',Session.ImageHash).AddPair('trace_options_token',Session.TraceOptions.Token)
      .AddPair('operations_json','{"operations":[{"op":"add","spec":{"kind":"road","id":"preview-road","vertices":[{"x":-100,"y":0},{"x":100,"y":0}]}}]}');
    Session.Submit(Reply);
  finally Reply.Free; end;
  RefreshWorkflow(Form);
  Check(ResultHost.Visible and ReferenceHost.Visible and (Image.Picture.Width>0),'Show both source and completed result');
  Check((ResultHost.Top>=ReferenceHost.Top+ReferenceHost.Height) and
    (ResultHost.Height>Form.ScaleValue(180)) and (ReferenceHost.Height>Form.ScaleValue(180)),
    'Completed preview must sit below a usable reference image');
  Height := Form.ScaleValue(220); ResultHost.Height := Height; RefreshWorkflow(Form);
  Check(ResultHost.Height=Height,'Polling must retain the splitter adjustment');
  Form.ClientHeight := Form.ScaleValue(640);
  Check(ResultHost.Visible and (ResultHost.Height>Form.ScaleValue(180)) and
    (ReferenceHost.Height>Form.ScaleValue(180)),'Both previews fit after shrinking the window');
  var Options := TJSONObject.Create.AddPair('simplification',TJSONNumber.Create(83));
  try Session.ConfigureTrace(Options); finally Options.Free; end;
  RefreshWorkflow(Form);
  Check(not ResultHost.Visible and ReferenceHost.Visible,'Changed conditions must hide the obsolete result');
end;

procedure CheckPageNavigation;
var Owner: TForm; Form: TMapRakuGenerationForm; Document: TVectArtDocument;
  History: TVectArtEditHistory; State: TVectArtEditorState; Canvas: TVectArtCanvasControl;
  Session: TMapRakuGenerationSession; Request: TJSONObject; SourceHash, Token: string;
  Slider: THorizontalTrackBarControl;
begin
  Owner := TForm.Create(nil); Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create; State := TVectArtEditorState.Create;
  Canvas := TVectArtCanvasControl.Create(Owner); Canvas.Parent := Owner;
  Session := TMapRakuGenerationSession.Create(Document,History,State,Canvas);
  Form := nil; Request := TJSONObject.Create.AddPair('place_query','ページ保持試験の駅').AddPair('instructions','駅を中心に');
  try
    Session.Prepare(Request); Session.SubmitImage(TFile.ReadAllBytes('TestOutput/reference-test.png'));
    SourceHash := Session.ImageHash;
    Form := TMapRakuGenerationForm.CreateForSession(Owner,Session);
    Check(Button(Form,'画像を作成').Visible and not Button(Form,'採用').Visible,'Initial image page');
    Button(Form,'地図データ作成へ →').OnClick(nil);
    Check(Button(Form,'作成開始').Visible and Button(Form,'← 画像作成へ戻る').Visible,'Explicit next page');
    Slider := nil;
    for var I := 0 to Form.ComponentCount-1 do
      if Form.Components[I] is THorizontalTrackBarControl then Slider := THorizontalTrackBarControl(Form.Components[I]);
    Check(Slider<>nil,'Simplification slider'); Slider.Position := 82;
    Check(Session.TraceOptions.Simplification=82,'Slider must update shared trace options');
    Token := Session.TraceOptions.Token;
    Button(Form,'← 画像作成へ戻る').OnClick(nil);
    Check(Button(Form,'画像を作成').Visible,'Back to image page');
    Check((TEdit(Form.FindComponent('PlaceQuery')).Text='ページ保持試験の駅') and
      (Trim(TMemo(Form.FindComponent('MapInstructions')).Text)='駅を中心に'),'Page inputs retained');
    Button(Form,'地図データ作成へ →').OnClick(nil);
    Check((Session.ImageHash=SourceHash) and (Session.TraceOptions.Token=Token) and
      (Session.State='image_ready'),'Navigation must preserve image/options without starting a worker');
    CheckCompletedPreview(Form,Session);
  finally
    Request.Free; Form.Free; Session.Free; State.Free; History.Free; Document.Free; Owner.Free;
  end;
end;

procedure CheckGenerationReferenceView;
begin
  CheckReferencePixels; CheckPageNavigation;
  Writeln('PASS: crop colors, outside shade, clean trace PNG, rotation/pan, pages, simplification, stacked result and splitter');
end;
end.
