// 画像作成ページと地図データ作成ページを切り替え、採用まで共通セッションを編集する。
unit MapRakuGenerationForm;
interface
uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  MapRakuGenerationSession, MapRakuDarkDialogControls, MapRakuReferenceView,
  HorizontalTrackBarControl;
type
  TMapRakuGenerationForm = class(TForm)
  private
    FSession: TMapRakuGenerationSession; // MainForm所有。
    FImagePage, FDataPage: TPanel;
    FPageTitle, FPageHint, FStatus, FCanvasInfo, FLevelInfo, FTransformInfo: TLabel;
    FPlace, FSpan, FNorth: TEdit;
    FNotes, FDetails: TMemo;
    FImagePreview, FResultPreview: TImage;
    FViewer, FReferenceHost, FResultHost: TPanel;
    FResultSplitter: TSplitter;
    FReference: TMapRakuReferenceView;
    FLevel: THorizontalTrackBarControl;
    FStart, FNext, FBack, FTrace, FCancel, FApply, FReset: TDarkDialogButton;
    FTimer: TTimer;
    FPage: Integer;
    FUpdating: Boolean;
    FLoadedId, FLoadedSource, FLoadedResult, FLoadedDetails: string;
    procedure BuildShell;
    procedure BuildImagePage;
    procedure BuildDataPage;
    procedure BuildTraceSettings(Host: TWinControl);
    procedure ShowPage(Page: Integer);
    procedure StartClick(Sender: TObject);
    procedure NextClick(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure TraceClick(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure LayoutPreviews(Sender: TObject);
    procedure ReferenceChanged(Sender: TObject);
    procedure LevelChanged(Sender: TObject);
    procedure ResetReference(Sender: TObject);
    procedure RefreshStatus(Sender: TObject);
    procedure RefreshRequest;
    procedure RefreshImages;
    procedure RefreshDetails;
    procedure ShowError(const Text: string);
    procedure ApplyDarkMode(Sender: TObject);
    function ConditionsMatch: Boolean;
  public
    constructor CreateForSession(AOwner: TComponent; Session: TMapRakuGenerationSession);
  end;
implementation
uses System.SysUtils, System.JSON, System.Math, Vcl.Graphics, Vcl.Imaging.pngimage,
  Winapi.Windows, Winapi.Dwmapi, Winapi.UxTheme,
  MapRakuAutomationValues, MapRakuTraceOptions;

function Panel(Owner: TComponent; Host: TWinControl; Alignment: TAlign): TPanel;
begin
  Result := TPanel.Create(Owner); Result.Parent := Host; Result.Align := Alignment;
  Result.BevelOuter := bvNone; Result.ParentBackground := False; Result.Color := $252525;
end;
function LabelAt(Owner: TComponent; Host: TWinControl; const Text: string; X,Y,W,H: Integer): TLabel;
begin
  Result := TLabel.Create(Owner); Result.Parent := Host; Result.Caption := Text;
  Result.AutoSize := False; Result.WordWrap := True;
  Result.SetBounds(Host.ScaleValue(X),Host.ScaleValue(Y),Host.ScaleValue(W),Host.ScaleValue(H));
end;
function ButtonAt(Owner: TComponent; Host: TWinControl; const Text: string;
  X,Y,W: Integer; Click: TNotifyEvent): TDarkDialogButton;
begin
  Result := TDarkDialogButton.Create(Owner); Result.Parent := Host; Result.Caption := Text;
  Result.SetBounds(Host.ScaleValue(X),Host.ScaleValue(Y),Host.ScaleValue(W),Host.ScaleValue(32));
  Result.OnClick := Click;
end;
function EditAt(Owner: TComponent; Host: TWinControl; const Name, Text: string; X,Y,W: Integer): TEdit;
begin
  Result := TEdit.Create(Owner); Result.Parent := Host; Result.Name := Name; Result.Text := Text;
  Result.Color := COLOR_CONTROL; Result.Font.Color := COLOR_TEXT;
  Result.SetBounds(Host.ScaleValue(X),Host.ScaleValue(Y),Host.ScaleValue(W),Host.ScaleValue(28));
end;

constructor TMapRakuGenerationForm.CreateForSession(AOwner: TComponent; Session: TMapRakuGenerationSession);
begin
  inherited CreateNew(AOwner); FSession := Session;
  Name := 'MapRakuGenerationForm'; Caption := '地名から地図を作成';
  PopupParent := TCustomForm(AOwner); Position := poOwnerFormCenter;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10; Font.Color := COLOR_TEXT; Color := $252525;
  ClientWidth := ScaleValue(1000); ClientHeight := ScaleValue(760);
  Constraints.MinWidth := ScaleValue(960); Constraints.MinHeight := ScaleValue(680);
  OnShow := ApplyDarkMode; BuildShell; BuildImagePage; BuildDataPage;
  ShowPage(1); ActiveControl := FPlace;
  FTimer := TTimer.Create(Self); FTimer.Interval := 250; FTimer.OnTimer := RefreshStatus;
  RefreshStatus(nil);
end;
procedure TMapRakuGenerationForm.ApplyDarkMode(Sender: TObject);
var Dark: Winapi.Windows.BOOL;
begin
  Dark := True; DwmSetWindowAttribute(Handle,20,@Dark,SizeOf(Dark));
  SetWindowTheme(Handle,'DarkMode_Explorer',nil);
end;
procedure TMapRakuGenerationForm.BuildShell;
var Header, Footer: TPanel; CloseButton: TDarkDialogButton;
begin
  Header := Panel(Self,Self,alTop); Header.Height := ScaleValue(56);
  FPageTitle := LabelAt(Self,Header,'',16,8,960,22);
  FPageHint := LabelAt(Self,Header,'',16,32,960,20);
  Footer := Panel(Self,Self,alBottom); Footer.Height := ScaleValue(92);
  FStatus := LabelAt(Self,Footer,'',16,6,960,38); FStatus.Anchors := [akLeft,akTop,akRight];
  FStart := ButtonAt(Self,Footer,'画像を作成',16,50,180,StartClick); FStart.Primary := True;
  FNext := ButtonAt(Self,Footer,'地図データ作成へ →',212,50,220,NextClick);
  FBack := ButtonAt(Self,Footer,'← 画像作成へ戻る',16,50,170,BackClick);
  FTrace := ButtonAt(Self,Footer,'作成開始',202,50,156,TraceClick); FTrace.Primary := True;
  FCancel := ButtonAt(Self,Footer,'中止',464,50,76,CancelClick);
  FApply := ButtonAt(Self,Footer,'採用',744,50,112,ApplyClick); FApply.Anchors := [akTop,akRight];
  CloseButton := ButtonAt(Self,Footer,'閉じる',872,50,112,CloseClick); CloseButton.Anchors := [akTop,akRight];
end;
procedure TMapRakuGenerationForm.BuildImagePage;
var Inputs, ImageHost: TPanel;
begin
  FImagePage := Panel(Self,Self,alClient); Inputs := Panel(Self,FImagePage,alLeft);
  Inputs.Width := ScaleValue(308);
  LabelAt(Self,Inputs,'場所名・駅・施設',16,8,272,22);
  FPlace := EditAt(Self,Inputs,'PlaceQuery','',16,34,272); FPlace.MaxLength := 256;
  LabelAt(Self,Inputs,'市区町村も含めると場所を特定しやすくなります。',16,70,272,42);
  LabelAt(Self,Inputs,'画像の作成範囲の横幅（m）',16,122,272,22);
  FSpan := EditAt(Self,Inputs,'MapSpan','1000',16,148,128);
  LabelAt(Self,Inputs,'100～20000m',158,152,130,22);
  LabelAt(Self,Inputs,'北の向き（上から時計回りの度数）',16,188,272,22);
  FNorth := EditAt(Self,Inputs,'MapNorth','0',16,214,128);
  LabelAt(Self,Inputs,'0＝上、90＝右',158,218,130,22);
  LabelAt(Self,Inputs,'画像作成への指示',16,254,272,22);
  FNotes := TMemo.Create(Self); FNotes.Parent := Inputs; FNotes.Name := 'MapInstructions'; FNotes.Clear;
  FNotes.Color := COLOR_CONTROL; FNotes.Font.Color := COLOR_TEXT; FNotes.MaxLength := 4000;
  FNotes.SetBounds(ScaleValue(16),ScaleValue(280),ScaleValue(272),ScaleValue(260));
  FNotes.Anchors := [akLeft,akTop,akBottom]; FNotes.ScrollBars := ssVertical;
  FCanvasInfo := LabelAt(Self,Inputs,'現在の用紙サイズで作成します。',16,552,272,44);
  FCanvasInfo.Anchors := [akLeft,akBottom];
  ImageHost := Panel(Self,FImagePage,alClient); ImageHost.Color := $F0F0F0;
  ImageHost.Caption := '場所と指示から作成した元地図画像'; ImageHost.Font.Color := clBlack;
  FImagePreview := TImage.Create(Self); FImagePreview.Parent := ImageHost; FImagePreview.Align := alClient;
  FImagePreview.Proportional := True; FImagePreview.Stretch := True; FImagePreview.Center := True;
end;
procedure TMapRakuGenerationForm.BuildDataPage;
var Settings, ViewBar, ResultBar: TPanel;
begin
  FDataPage := Panel(Self,Self,alClient); Settings := Panel(Self,FDataPage,alRight);
  Settings.Width := ScaleValue(292); BuildTraceSettings(Settings);
  FDetails := TMemo.Create(Self); FDetails.Parent := Settings; FDetails.Align := alClient;
  FDetails.ReadOnly := True; FDetails.ScrollBars := ssVertical;
  FDetails.Color := COLOR_CONTROL; FDetails.Font.Color := COLOR_TEXT;
  FViewer := Panel(Self,FDataPage,alClient); FViewer.OnResize := LayoutPreviews;
  FReferenceHost := Panel(Self,FViewer,alClient);
  ViewBar := Panel(Self,FReferenceHost,alTop); ViewBar.Height := ScaleValue(36);
  LabelAt(Self,ViewBar,'参照地図',12,6,240,24);
  FReset := ButtonAt(Self,ViewBar,'範囲・向きを戻す',552,0,152,ResetReference);
  FReset.Anchors := [akTop,akRight];
  FReference := TMapRakuReferenceView.Create(Self); FReference.Parent := FReferenceHost; FReference.Align := alClient;
  FReference.Name := 'GenerationReference';
  FReference.OnChange := ReferenceChanged;
  FResultHost := Panel(Self,FViewer,alBottom); FResultHost.Name := 'GenerationResultHost';
  FResultHost.Color := $F0F0F0; FResultHost.Height := ScaleValue(270); FResultHost.Visible := False;
  ResultBar := Panel(Self,FResultHost,alTop); ResultBar.Height := ScaleValue(28);
  LabelAt(Self,ResultBar,'作成結果のプレビュー',12,3,360,22);
  FResultPreview := TImage.Create(Self); FResultPreview.Parent := FResultHost; FResultPreview.Align := alClient;
  FResultPreview.Name := 'GenerationResultPreview';
  FResultPreview.Proportional := True; FResultPreview.Stretch := True; FResultPreview.Center := True;
  FResultSplitter := TSplitter.Create(Self); FResultSplitter.Parent := FViewer;
  FResultSplitter.Align := alBottom; FResultSplitter.Height := ScaleValue(6);
  FResultSplitter.Top := 0; FResultSplitter.Color := COLOR_BUTTON_BORDER;
  FResultSplitter.MinSize := ScaleValue(180); FResultSplitter.Visible := False;
end;

procedure TMapRakuGenerationForm.LayoutPreviews(Sender: TObject);
begin
  if (FResultHost=nil) or not FResultHost.Visible then Exit;
  // 参照側のトンボ・操作表示の余白を加え、上下の地図画像を同程度の大きさにする。
  FResultHost.Height := Max(ScaleValue(180),(FViewer.ClientHeight-ScaleValue(126)) div 2);
end;
procedure TMapRakuGenerationForm.BuildTraceSettings(Host: TWinControl);
var Top: TPanel;
begin
  Top := Panel(Self,Host,alTop); Top.Height := ScaleValue(268);
  LabelAt(Self,Top,'簡略化（あいまいさ）',16,12,260,22);
  FLevelInfo := LabelAt(Self,Top,'',16,40,260,44);
  FLevel := THorizontalTrackBarControl.Create(Self); FLevel.Parent := Top;
  FLevel.SetBounds(ScaleValue(16),ScaleValue(90),ScaleValue(260),ScaleValue(32));
  FLevel.SetRange(0,100); FLevel.Position := 50; FLevel.Frequency := 25; FLevel.OnChange := LevelChanged;
  LabelAt(Self,Top,'小さい：元の形を優先'+sLineBreak+'大きい：道を水平・垂直へ整理し、建物を簡略化',16,132,260,66);
  LabelAt(Self,Top,'接続・分岐・交差と、施設の位置関係を保つ目安です。',16,200,260,44);
  FTransformInfo := LabelAt(Self,Top,'',16,244,260,22);
end;
procedure TMapRakuGenerationForm.ShowPage(Page: Integer);
begin
  FPage := Page; FImagePage.Visible := Page=1; FDataPage.Visible := Page=2;
  FStart.Visible := Page=1; FNext.Visible := Page=1; FBack.Visible := Page=2;
  FTrace.Visible := Page=2; FApply.Visible := Page=2;
  if Page=1 then begin
    FPageTitle.Caption := '1 / 2　場所と指示から元地図画像を作成';
    FPageHint.Caption := '画像を確認したら「地図データ作成へ」で次のページへ進みます。';
    ActiveControl := FPlace;
  end else begin
    FPageTitle.Caption := '2 / 2　参照範囲・向きと簡略化を調整して地図データを作成';
    FPageHint.Caption := '明るいトンボ内を作成します。トンボ付近の回転アイコンを左右へドラッグして向きを調整できます。';
    ActiveControl := FReference;
  end;
end;
procedure TMapRakuGenerationForm.ShowError(const Text: string);
begin FStatus.Caption := Text; FDetails.Lines.Add('操作できません: '+Text); end;
function TMapRakuGenerationForm.ConditionsMatch: Boolean;
var Span: Integer; North: Double;
begin
  Result := (FSession.Request<>nil) and TryStrToInt(FSpan.Text,Span) and TryStrToFloat(FNorth.Text,North);
  if Result then Result := (Trim(FPlace.Text)=Str(FSession.Request,'place_query')) and
    (Span=Num(FSession.Request,'span_m',0)) and (North=Num(FSession.Request,'north_clockwise_degrees',0)) and
    (Trim(FNotes.Text)=Str(FSession.Request,'instructions'));
end;
procedure TMapRakuGenerationForm.StartClick(Sender: TObject);
var Input: TJSONObject; Span: Integer; North: Double;
begin
  try
    if not TryStrToInt(FSpan.Text,Span) then raise EArgumentException.Create('作成範囲は整数で入力してください。');
    if not TryStrToFloat(FNorth.Text,North) then raise EArgumentException.Create('北の向きは数値で入力してください。');
    Input := TJSONObject.Create.AddPair('place_query',FPlace.Text).AddPair('span_m',TJSONNumber.Create(Span))
      .AddPair('north_clockwise_degrees',TJSONNumber.Create(North)).AddPair('instructions',FNotes.Text);
    try FSession.Prepare(Input); FSession.StartImage; finally Input.Free; end;
    RefreshStatus(nil);
  except on E: Exception do ShowError(E.Message); end;
end;
procedure TMapRakuGenerationForm.NextClick(Sender: TObject);
begin
  if not ConditionsMatch or (FSession.ImagePath='') then begin ShowError('元地図画像を作成・確認してから進んでください。'); Exit; end;
  ShowPage(2); RefreshStatus(nil);
end;
procedure TMapRakuGenerationForm.BackClick(Sender: TObject);
begin ShowPage(1); RefreshStatus(nil); end;
procedure TMapRakuGenerationForm.TraceClick(Sender: TObject);
begin
  try FLoadedResult := ''; FSession.TraceImage; RefreshStatus(nil);
  except on E: Exception do ShowError(E.Message); end;
end;
procedure TMapRakuGenerationForm.ApplyClick(Sender: TObject);
begin
  try FSession.Apply; Close;
  except on E: Exception do ShowError(E.Message); end;
end;
procedure TMapRakuGenerationForm.CancelClick(Sender: TObject);
begin try FSession.Cancel; RefreshStatus(nil); except on E: Exception do ShowError(E.Message); end; end;
procedure TMapRakuGenerationForm.CloseClick(Sender: TObject);
begin Close; end;
procedure TMapRakuGenerationForm.ReferenceChanged(Sender: TObject);
var Root: TJSONObject;
begin
  if FUpdating then Exit;
  Root := FReference.Options.ToJson;
  try
    try FSession.ConfigureTrace(Root); RefreshStatus(nil);
    except on E: Exception do ShowError(E.Message); end;
  finally Root.Free; end;
end;
procedure TMapRakuGenerationForm.LevelChanged(Sender: TObject);
var Options: TMapRakuTraceOptions;
begin
  if FUpdating then Exit;
  Options := FSession.TraceOptions; Options.Simplification := FLevel.Position;
  FReference.Options := Options; ReferenceChanged(FReference);
end;
procedure TMapRakuGenerationForm.ResetReference(Sender: TObject);
var Options: TMapRakuTraceOptions;
begin
  Options := TMapRakuTraceOptions.Default; Options.Simplification := FSession.TraceOptions.Simplification;
  FReference.Options := Options; ReferenceChanged(FReference);
end;
procedure TMapRakuGenerationForm.RefreshRequest;
var Request: TJSONObject; Id: string;
begin
  Request := FSession.Request; if Request=nil then Exit;
  Id := Str(Request,'generation_id');
  if Id<>FLoadedId then begin
    FLoadedId := Id; FLoadedSource := ''; FLoadedResult := ''; FLoadedDetails := '';
    FPlace.Text := Str(Request,'place_query'); FSpan.Text := IntToStr(Round(Num(Request,'span_m',1000)));
    FNorth.Text := FloatToStr(Num(Request,'north_clockwise_degrees',0)); FNotes.Text := Str(Request,'instructions');
    FImagePreview.Picture.Assign(nil); FResultPreview.Picture.Assign(nil); FReference.LoadImage(''); ShowPage(1);
  end;
  FCanvasInfo.Caption := Format('用紙: %d × %dpx',[Round(Num(Request,'canvas_width',0)),Round(Num(Request,'canvas_height',0))]);
end;
procedure TMapRakuGenerationForm.RefreshImages;
begin
  if FLoadedSource<>FSession.ImageHash then begin
    FLoadedSource := FSession.ImageHash; FReference.LoadImage(FSession.ImagePath);
    if FSession.ImagePath<>'' then FImagePreview.Picture.LoadFromFile(FSession.ImagePath);
  end;
  if (FSession.PreviewPath<>'') and (FLoadedResult<>FSession.ResultToken) then begin
    FLoadedResult := FSession.ResultToken; FResultPreview.Picture.LoadFromFile(FSession.PreviewPath);
  end;
end;
procedure TMapRakuGenerationForm.RefreshDetails;
var Key, Text: string; Reply: TJSONObject;
begin
  Key := FSession.State+'|'+FSession.ResultToken+'|'+FSession.TraceOptions.Token;
  if FLoadedDetails=Key then Exit;
  FLoadedDetails := Key; FDetails.Clear; Reply := FSession.Reply;
  if Reply=nil then begin
    FDetails.Lines.Add('参照地図の枠内をもとに作成します。');
    FDetails.Lines.Add('範囲・向き・簡略化を調整して「作成開始」を押してください。');
    Exit;
  end;
  FDetails.Lines.Add('場所: '+Str(Reply,'place_label')); FDetails.Lines.Add(Str(Reply,'message'));
  for var Warning in Arr(Reply,'warnings') do begin
    Text := Warning.Value;
    if Pos('sources',Text)>0 then Text := '元画像に緯度・経度や出典の記載はありません。';
    FDetails.Lines.Add('・'+Text);
  end;
end;
procedure TMapRakuGenerationForm.RefreshStatus(Sender: TObject);
var Status: TJSONObject; Busy, HasImage: Boolean;
begin
  Status := FSession.Status;
  try
    FUpdating := True;
    try
      RefreshRequest; RefreshImages; RefreshDetails;
      FReference.Options := FSession.TraceOptions; FLevel.Position := FSession.TraceOptions.Simplification;
    finally FUpdating := False; end;
    Busy := Bool(Status,'busy'); HasImage := Bool(Status,'has_image');
    FStart.Enabled := not Busy; FNext.Enabled := HasImage and ConditionsMatch;
    FTrace.Enabled := Bool(Status,'can_trace') and not Busy; FApply.Enabled := Bool(Status,'can_apply') and not Busy;
    FCancel.Enabled := Busy and (FSession.State<>'cancelling');
    FPlace.Enabled := not Busy; FSpan.Enabled := not Busy; FNorth.Enabled := not Busy; FNotes.Enabled := not Busy;
    FReference.Enabled := HasImage and not Busy; FLevel.Enabled := HasImage and not Busy;
    FReset.Enabled := HasImage and not Busy;
    if FResultHost.Visible<>(FSession.PreviewPath<>'') then begin
      FViewer.DisableAlign;
      try
        FResultHost.Visible := FSession.PreviewPath<>'';
        FResultSplitter.Visible := FResultHost.Visible;
        LayoutPreviews(nil);
      finally FViewer.EnableAlign; end;
    end;
    FLevelInfo.Caption := Format('%d / 100　%s',[FLevel.Position,TraceSimplificationCaption(FLevel.Position)]);
    FTransformInfo.Caption := Format('倍率 %.0f%% ／ 回転 %.1f°',[FSession.TraceOptions.Zoom*100,FSession.TraceOptions.Rotation]);
    FStatus.Caption := Str(Status,'stage',FSession.MessageText);
    if (FSession.State='ready') and not FApply.Enabled then FStatus.Caption := '元の地図が変更されています。作成条件を準備し直してください。';
  finally Status.Free; end;
end;
end.
