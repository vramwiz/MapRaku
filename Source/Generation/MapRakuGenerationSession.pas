// 単独版・プラグイン共通の地名生成セッション。UIスレッド上で条件固定・検証・Undo適用する。
unit MapRakuGenerationSession;
interface
uses System.Classes, System.SysUtils, System.JSON, MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState, MapRakuCanvas, MapRakuCodexJob, MapRakuTraceOptions;
type
  TMapRakuGenerationSession = class
  private
    FDocument: TVectArtDocument; // MainForm所有。セッションより長く生存する。
    FHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    FCanvas: TVectArtCanvasControl;
    FJob: TMapRakuCodexJob;
    FRequest, FReply, FCandidate, FRepairBaseline, FTraceRequest: TJSONObject;
    FState, FMessage, FBaseToken, FBackgroundToken, FDirectory, FPreviewPath, FSource: string;
    FBaseRevision: Int64;
    FRepairAttempted, FVerifiedSearch: Boolean;
    FImageWorkflow, FImageJob, FTraceMode: Boolean;
    FImageBytes: TBytes;
    FImagePath, FImageHash, FImageNote: string;
    FTraceBytes: TBytes;
    FTraceHash: string;
    FResultToken: string;
    FTraceOptions: TMapRakuTraceOptions;
    FOnShow: TNotifyEvent;
    procedure CheckEditor;
    procedure BuildCandidate(Reply: TJSONObject; out Candidate: TJSONObject);
    procedure CheckGenerationId(Root: TJSONObject);
    procedure StartRepair(Reply: TJSONObject; const ErrorText: string);
    function EffectiveRequest: TJSONObject;
    function CreateTraceRequest: TJSONObject;
    procedure CheckTraceReply(Reply: TJSONObject);
  public
    constructor Create(Document: TVectArtDocument; History: TVectArtEditHistory;
      EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl);
    destructor Destroy; override;
    procedure Poll;
    procedure Prepare(Input: TJSONObject);
    procedure Start;
    procedure StartImage;
    procedure SubmitImage(const Bytes: TBytes);
    procedure PrepareTrace;
    procedure ConfigureTrace(Input: TJSONObject);
    procedure TraceImage;
    procedure Cancel;
    procedure Submit(Reply: TJSONObject);
    procedure Apply;
    function Status: TJSONObject;
    function Handle(const Command: string; Root: TJSONObject): string;
    property State: string read FState;
    property MessageText: string read FMessage;
    property Request: TJSONObject read FRequest;
    property Reply: TJSONObject read FReply;
    property PreviewPath: string read FPreviewPath;
    property ImagePath: string read FImagePath;
    property ImageHash: string read FImageHash;
    property ImageNote: string read FImageNote;
    property TraceOptions: TMapRakuTraceOptions read FTraceOptions;
    property ResultToken: string read FResultToken;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
  end;
implementation
uses System.IOUtils, System.Math, Winapi.Windows, MapRakuGenerationContract,
  MapRakuAutomationValues, MapRakuAutomationWire, MapRakuAutomationSession,
  MapRakuAutomationBatch, MapRakuDocumentJson, MapRakuAutomationDocumentCommand,
  MapRakuExport, MapRakuGenerationImage;

constructor TMapRakuGenerationSession.Create(Document: TVectArtDocument; History: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl);
begin
  inherited Create; FDocument := Document; FHistory := History;
  FEditorState := EditorState; FCanvas := Canvas; FState := 'idle';
  FMessage := '地名と作成範囲を入力してください。';
  FTraceOptions := TMapRakuTraceOptions.Default;
end;
destructor TMapRakuGenerationSession.Destroy;
begin
  // ワーカーはモデルを参照しない。所有する処理を止めてから文書の所有者へ戻る。
  FreeAndNil(FJob); FRequest.Free; FReply.Free; FCandidate.Free; FRepairBaseline.Free; FTraceRequest.Free; inherited;
end;

procedure TMapRakuGenerationSession.CheckEditor;
begin
  Require((FCanvas<>nil) and not FCanvas.AutomationBusy,
    '作図・文字入力・ドラッグを確定してから操作してください。');
end;

procedure TMapRakuGenerationSession.Prepare(Input: TJSONObject);
var Normalized, Snapshot: TJSONObject; Id: string;
begin
  Poll; Require(FJob=nil, '地図の生成処理が動作中です。'); CheckEditor;
  Require(AutomationSession.Conditions=nil, '元地図画像を解除してから地名生成を開始してください。');
  Normalized := NormalizeGenerationRequest(Input,FDocument.CanvasLayer.Width,FDocument.CanvasLayer.Height);
  FreeAndNil(FRequest); FRequest := Normalized;
  FreeAndNil(FReply); FreeAndNil(FCandidate); FreeAndNil(FRepairBaseline); FPreviewPath := '';
  FRepairAttempted := False; FVerifiedSearch := False;
  FImageWorkflow := False; FImageJob := False; FTraceMode := False;
  FImageBytes := nil; FImagePath := ''; FImageHash := ''; FImageNote := '';
  FreeAndNil(FTraceRequest); FTraceOptions := TMapRakuTraceOptions.Default; FTraceBytes := nil; FTraceHash := '';
  FResultToken := '';
  FBaseToken := StateToken(SerializeVectArtDocument(FDocument));
  FBaseRevision := FDocument.Revision;
  Snapshot := TJSONObject.ParseJSONValue(SerializeVectArtDocument(FDocument)) as TJSONObject;
  try FRequest.AddPair('canvas_appearance',Snapshot.GetValue('canvas').Clone as TJSONValue);
  finally Snapshot.Free; end;
  FBackgroundToken := FCanvas.ReferenceBackgroundToken;
  Id := Str(FRequest,'generation_id');
  FDirectory := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'MapRaku\Generation\'+Id);
  ForceDirectories(FDirectory);
  TFile.WriteAllText(TPath.Combine(FDirectory,'request.json'),FRequest.ToJSON,TEncoding.UTF8);
  FState := 'prepared'; FSource := 'external_pipe'; FMessage := '生成条件を固定しました。Codexへ送信できます。';
end;

procedure TMapRakuGenerationSession.Start;
var Schema: TJSONObject;
begin
  Require((FState='prepared') and (FJob=nil), '送信する生成条件を準備してください。');
  Schema := GenerationOutputSchema;
  try
    FJob := TMapRakuCodexJob.Create(GenerationPrompt(FRequest),Schema,FDirectory);
    FJob.BeginRun;
  finally Schema.Free; end;
  FState := 'running'; FSource := 'codex_app_server'; FMessage := 'Codexへ地図の作成を依頼しています。';
end;

procedure TMapRakuGenerationSession.StartImage;
begin
  Require((FState='prepared') and (FJob=nil), '元地図画像の作成条件を準備してください。');
  FImageWorkflow := True; FImageJob := True; FTraceMode := False;
  FJob := TMapRakuCodexJob.CreateImage(GenerationImagePrompt(FRequest),FDirectory); FJob.BeginRun;
  FState := 'image_running'; FSource := 'codex_image_generation';
  FMessage := '元地図画像を作成しています。完了後に画像を確認してください。';
end;

procedure TMapRakuGenerationSession.SubmitImage(const Bytes: TBytes);
var Normalized: TBytes; Path: string;
begin
  Require((FJob=nil) and (FRequest<>nil), '処理の終了後に元地図画像を渡してください。');
  Require((FState='prepared') or (FState='image_ready') or (FState='receiving') or
    (FState='failed') or (FState='cancelled'), '元地図画像を受信できる状態ではありません。');
  Normalized := NormalizeGenerationImage(Bytes,Round(Num(FRequest,'canvas_width',0)),Round(Num(FRequest,'canvas_height',0)));
  Path := TPath.Combine(FDirectory,'source-image.png');
  TFile.WriteAllBytes(Path,Normalized); FImagePath := Path;
  FImageBytes := Normalized; FImageHash := GenerationImageHash(FImageBytes);
  FreeAndNil(FTraceRequest); FTraceOptions := TMapRakuTraceOptions.Default; FTraceBytes := nil; FTraceHash := '';
  FImageWorkflow := True; FTraceMode := False; FImageJob := False;
  FreeAndNil(FReply); FreeAndNil(FCandidate); FreeAndNil(FRepairBaseline); FPreviewPath := '';
  FResultToken := '';
  FState := 'image_ready'; FMessage := '元地図画像を確認し、よければ「地図データ作成へ」で次のページへ進んでください。';
end;

procedure TMapRakuGenerationSession.ConfigureTrace(Input: TJSONObject);
var Next: TMapRakuTraceOptions;
begin
  Poll; Require((FJob=nil) and (Length(FImageBytes)>0),'元地図画像の受信後、処理を開始する前に調整してください。');
  Next := ReadTraceOptions(Input,FTraceOptions);
  if Next.Token=FTraceOptions.Token then Exit;
  FTraceOptions := Next;
  // 範囲や簡略化を変えた結果へ、以前の候補を採用できないようにする。
  FreeAndNil(FReply); FreeAndNil(FCandidate); FreeAndNil(FRepairBaseline); FreeAndNil(FTraceRequest);
  FTraceBytes := nil; FTraceHash := ''; FPreviewPath := ''; FTraceMode := False; FResultToken := '';
  FState := 'image_ready'; FMessage := '参照範囲・向き・簡略化を調整しました。「作成開始」で地図データを作成できます。';
end;

function TMapRakuGenerationSession.EffectiveRequest: TJSONObject;
begin
  Result := FRequest;
  if FTraceMode and (FTraceRequest<>nil) then Result := FTraceRequest;
end;

function TMapRakuGenerationSession.CreateTraceRequest: TJSONObject;
var North: Double;
begin
  Result := FRequest.Clone as TJSONObject;
  North := Num(FRequest,'north_clockwise_degrees',0)+FTraceOptions.Rotation;
  North := North-Floor(North/360)*360;
  Result.RemovePair('north_clockwise_degrees').Free;
  Result.AddPair('north_clockwise_degrees',TJSONNumber.Create(North));
  Result.RemovePair('span_m').Free;
  Result.AddPair('span_m',TJSONNumber.Create(Max(1,Round(Num(FRequest,'span_m',1000)/FTraceOptions.Zoom))));
  Result.AddPair('trace_options',FTraceOptions.ToJson);
  Result.AddPair('trace_options_token',FTraceOptions.Token);
end;

procedure TMapRakuGenerationSession.CheckTraceReply(Reply: TJSONObject);
begin
  ValidateGenerationReply(EffectiveRequest,Reply,not FTraceMode);
  if FTraceMode then begin
    Require(Str(Reply,'source_image_sha256')=FTraceHash,'読み取り対象の参照画像が一致しません。');
    Require(Str(Reply,'trace_options_token')=FTraceOptions.Token,'作成対象の範囲・向き・簡略化が一致しません。');
  end;
end;

procedure TMapRakuGenerationSession.PrepareTrace;
begin
  Poll; Require((FJob=nil) and (Length(FImageBytes)>0), '元地図画像を先に作成してください。');
  CheckEditor;
  Require((FBaseToken=StateToken(SerializeVectArtDocument(FDocument))) and
    (FBackgroundToken=FCanvas.ReferenceBackgroundToken), '元の地図が変更されました。画像作成の条件を準備し直してください。');
  FreeAndNil(FReply); FreeAndNil(FCandidate); FreeAndNil(FRepairBaseline); FPreviewPath := '';
  FRepairAttempted := False; FTraceMode := True; FImageJob := False; FResultToken := '';
  FreeAndNil(FTraceRequest); FTraceRequest := CreateTraceRequest;
  FTraceBytes := BuildGenerationReference(FImageBytes,FTraceOptions); FTraceHash := GenerationImageHash(FTraceBytes);
  TFile.WriteAllBytes(TPath.Combine(FDirectory,'trace-reference.png'),FTraceBytes);
  FState := 'prepared'; FSource := 'external_image_trace';
  FMessage := '確認した元地図画像からの読み取り条件を準備しました。';
end;

procedure TMapRakuGenerationSession.TraceImage;
var Schema: TJSONObject;
begin
  PrepareTrace;
  Schema := GenerationOutputSchema(True);
  try
    FJob := TMapRakuCodexJob.Create(GenerationTracePrompt(EffectiveRequest,FTraceHash),Schema,FDirectory);
    FJob.SetReferenceImage(FTraceBytes); FJob.BeginRun;
  finally Schema.Free; end;
  FState := 'tracing'; FSource := 'codex_image_trace';
  FMessage := '参照範囲と簡略化の条件で地図データを作成しています。';
end;

procedure TMapRakuGenerationSession.Cancel;
begin
  if FJob<>nil then begin
    FJob.Terminate; CancelSynchronousIo(FJob.Handle);
    FState := 'cancelling'; FMessage := '生成を中止しています。';
  end else if FState='prepared' then begin
    FState := 'cancelled'; FMessage := '生成を中止しました。';
  end else Require(FState='cancelled', '中止できる生成処理がありません。');
end;

procedure TMapRakuGenerationSession.BuildCandidate(Reply: TJSONObject; out Candidate: TJSONObject);
var Batch, Base: TJSONObject; Parsed: TJSONValue; Blank: TVectArtDocument; ErrorText, Action: string;
  HasPath: Boolean;
begin
  Candidate := nil; Parsed := nil; Base := nil; Blank := TVectArtDocument.Create;
  try
    Parsed := TJSONObject.ParseJSONValue(Str(Reply,'operations_json')); Batch := Obj(Parsed);
    HasPath := False;
    for var Value in Arr(Batch,'operations') do begin
      var Op := Obj(Value); Action := Str(Op,'op');
      Require((Action='add') or (Action='connect') or (Action='crossing'),
        '地名生成ではadd/connect/crossingだけを使えます。');
      if Action='add' then begin
        var Spec := Obj(Op.GetValue('spec'));
        Require(Str(Spec,'id')<>'', '生成部品には一意のidが必要です。');
        HasPath := HasPath or (Str(Spec,'kind')='road') or (Str(Spec,'kind')='jr') or
          (Str(Spec,'kind')='rail') or (Str(Spec,'kind')='river');
      end;
    end;
    Require(HasPath, '地図に道路・線路・川がありません。');
    // 保存済み配色と透過設定は引き継ぎ、既存レイヤーを生成対象へ混ぜない。
    var CanvasJson := FRequest.GetValue('canvas_appearance').Clone as TJSONValue;
    Base := TJSONObject.Create.AddPair('appId','MapRaku').AddPair('version',TJSONNumber.Create(1))
      .AddPair('canvas',CanvasJson);
    Obj(CanvasJson).RemovePair('width').Free;
    Obj(CanvasJson).AddPair('width',FRequest.GetValue('canvas_width').Clone as TJSONValue);
    Obj(CanvasJson).RemovePair('height').Free;
    Obj(CanvasJson).AddPair('height',FRequest.GetValue('canvas_height').Clone as TJSONValue);
    Base.AddPair('layers',TJSONArray.Create).AddPair('crossingRelations',TJSONArray.Create)
      .AddPair('selectedIndex',TJSONNumber.Create(-1));
    Require(TryDeserializeVectArtDocument(Base.ToJSON,Blank,ErrorText),ErrorText);
    Candidate := BuildAutomationBatch(Blank,Batch);
  finally Base.Free; Parsed.Free; Blank.Free; end;
end;

procedure TMapRakuGenerationSession.Submit(Reply: TJSONObject);
var Candidate, Accepted: TJSONObject; Temp: TVectArtDocument; ErrorText, Path: string;
begin
  Require((FState='prepared') or (FState='receiving'), '結果を受信できる生成処理がありません。');
  CheckTraceReply(Reply);
  Candidate := nil; Accepted := nil;
  try
    if Str(Reply,'outcome')='ready' then begin
      BuildCandidate(Reply,Candidate);
      Temp := TVectArtDocument.Create;
      try
        Require(TryDeserializeVectArtDocument(Candidate.ToJSON,Temp,ErrorText),ErrorText);
        Path := TPath.Combine(FDirectory,'preview.png');
        ExportMapPreviewPng(Temp,Path,1280);
      finally Temp.Free; end;
      TFile.WriteAllText(TPath.Combine(FDirectory,'candidate.mapraku'),Candidate.ToJSON,TEncoding.UTF8);
    end else Path := '';
    Accepted := Reply.Clone as TJSONObject;
    TFile.WriteAllText(TPath.Combine(FDirectory,'response.json'),Accepted.ToJSON,TEncoding.UTF8);
    FreeAndNil(FCandidate); FCandidate := Candidate; Candidate := nil;
    if FCandidate<>nil then FResultToken := StateToken(FCandidate.ToJSON) else FResultToken := '';
    FreeAndNil(FReply); FReply := Accepted; Accepted := nil; FPreviewPath := Path;
    FState := Str(FReply,'outcome'); FMessage := Str(FReply,'message');
    if FTraceMode and (FState='ready') then
      FMessage := '地図データができました。作成結果を確認して「採用」を押してください。';
  finally Candidate.Free; Accepted.Free; end;
end;

procedure TMapRakuGenerationSession.StartRepair(Reply: TJSONObject; const ErrorText: string);
var Envelope, Schema: TJSONObject;
begin
  if FTraceMode then Envelope := TJSONObject.ParseJSONValue(GenerationTracePrompt(EffectiveRequest,FTraceHash)) as TJSONObject
  else Envelope := TJSONObject.ParseJSONValue(GenerationPrompt(FRequest)) as TJSONObject;
  Schema := GenerationOutputSchema(FTraceMode);
  try
    Envelope.AddPair('previous_response',Reply.Clone as TJSONValue);
    Envelope.AddPair('validation_error',ErrorText);
    Envelope.AddPair('repair_instructions','検証エラーの操作だけを修正してください。不要なconnectは取り除けます。'+
      '場所・範囲・方角・寸法・出典・生成IDは維持してください。再検索は不要です。');
    FRepairAttempted := True;
    FreeAndNil(FRepairBaseline); FRepairBaseline := Reply.Clone as TJSONObject;
    FJob := TMapRakuCodexJob.Create(Envelope.ToJSON,Schema,FDirectory,True);
    if FTraceMode then FJob.SetReferenceImage(FTraceBytes);
    FJob.BeginRun;
    FState := 'running'; FMessage := '配置データの検証結果をCodexへ返し、修正しています。';
  finally Schema.Free; Envelope.Free; end;
end;

procedure TMapRakuGenerationSession.Poll;
var ReplyValue: TJSONValue; Completed: TMapRakuCodexJob;
begin
  if (FJob=nil) or (WaitForSingleObject(FJob.Handle,0)<>WAIT_OBJECT_0) then Exit;
  Completed := FJob; FJob := nil;
  try
    if FState='cancelling' then begin
      FState := 'cancelled'; FMessage := '生成を中止しました。'; Exit;
    end;
    try
      Require(Completed.Success,Completed.ErrorText);
      if FImageJob then begin
        FState := 'receiving'; SubmitImage(Completed.ImageBytes);
        FImageNote := Completed.Answer; Exit;
      end;
      FVerifiedSearch := FVerifiedSearch or Completed.WebSearchCompleted;
      FState := 'receiving'; ReplyValue := TJSONObject.ParseJSONValue(Completed.Answer);
      try
        TFile.WriteAllText(TPath.Combine(FDirectory,'last-raw-response.json'),Completed.Answer,TEncoding.UTF8);
        CheckTraceReply(Obj(ReplyValue));
        if (FRepairBaseline<>nil) and (Str(Obj(ReplyValue),'outcome')='ready') then begin
          // 構造修正が別の場所や新しい出典への差替えになっていないことを確認する。
          Require((Str(Obj(ReplyValue),'place_label')=Str(FRepairBaseline,'place_label')) and
            (Num(Obj(ReplyValue),'latitude',0)=Num(FRepairBaseline,'latitude',0)) and
            (Num(Obj(ReplyValue),'longitude',0)=Num(FRepairBaseline,'longitude',0)) and
            (Arr(Obj(ReplyValue),'sources').ToJSON=Arr(FRepairBaseline,'sources').ToJSON),
            '配置操作の修正で場所または出典が変更されました。結果を採用していません。');
        end;
        if not FTraceMode and (Str(Obj(ReplyValue),'outcome')='ready') then
          Require(FVerifiedSearch, '場所の検索完了を確認できないため、地図を採用していません。');
        try Submit(Obj(ReplyValue));
        except on E: EArgumentException do begin
          if FRepairAttempted then raise;
          StartRepair(Obj(ReplyValue),E.Message);
        end; end;
      finally ReplyValue.Free; end;
    except on E: Exception do begin FState := 'failed'; FMessage := E.Message; end; end;
  finally Completed.Free; end;
end;

procedure TMapRakuGenerationSession.Apply;
var Current: string; Command: TMapRakuAutomationDocumentCommand;
begin
  Poll; Require((FState='ready') and (FCandidate<>nil), '反映できる地図がありません。');
  CheckEditor; Current := SerializeVectArtDocument(FDocument);
  Require((FBaseToken=StateToken(Current)) and (FBackgroundToken=FCanvas.ReferenceBackgroundToken),
    '生成開始後に地図または背景が変更されました。現在の地図から生成し直してください。');
  Command := TMapRakuAutomationDocumentCommand.Create(FDocument,Current,FCandidate.ToJSON);
  try
    FEditorState.OpenGroup := nil;
    Command.Execute; FHistory.AddApplied(Command); Command := nil;
  finally Command.Free; end;
  FState := 'applied'; FMessage := '地図を反映しました。元に戻す操作で復元できます。';
end;

function TMapRakuGenerationSession.Status: TJSONObject;
begin
  Poll; Result := TJSONObject.Create.AddPair('state',FState).AddPair('message',FMessage).AddPair('source',FSource)
    .AddPair('busy',TJSONBool.Create(FJob<>nil));
  if FJob<>nil then Result.AddPair('stage',FJob.Stage);
  if FRequest<>nil then Result.AddPair('generation_id',Str(FRequest,'generation_id'));
  Result.AddPair('image_workflow',TJSONBool.Create(FImageWorkflow));
  Result.AddPair('has_image',TJSONBool.Create(Length(FImageBytes)>0));
  if FImageHash<>'' then Result.AddPair('image_sha256',FImageHash);
  Result.AddPair('trace_options',FTraceOptions.ToJson);
  Result.AddPair('trace_options_token',FTraceOptions.Token);
  if FResultToken<>'' then Result.AddPair('candidate_token',FResultToken);
  if FTraceHash<>'' then Result.AddPair('trace_image_sha256',FTraceHash);
  Result.AddPair('can_trace',TJSONBool.Create((Length(FImageBytes)>0) and (FJob=nil) and
    (FBaseRevision=FDocument.Revision) and (FBackgroundToken=FCanvas.ReferenceBackgroundToken)));
  Result.AddPair('repair_attempted',TJSONBool.Create(FRepairAttempted));
  Result.AddPair('can_apply',TJSONBool.Create((FState='ready') and
    (FBaseRevision=FDocument.Revision) and
    (FBackgroundToken=FCanvas.ReferenceBackgroundToken)));
end;

procedure TMapRakuGenerationSession.CheckGenerationId(Root: TJSONObject);
begin
  Require((FRequest<>nil) and (Str(Root,'generation_id')=Str(FRequest,'generation_id')),
    '対象の生成IDが一致しません。現在の生成状態を取得してください。');
end;

function TMapRakuGenerationSession.Handle(const Command: string; Root: TJSONObject): string;
var Payload, Schema: TJSONObject;
begin
  Poll;
  if (Command='generation_prepare') or (Command='generation_start') or (Command='generation_start_image') then begin
    Require(Bool(Root,'apply'), 'apply: trueが必要です。');
    Require(Str(Root,'state_token')=StateToken(SerializeVectArtDocument(FDocument)), '地図の状態が変更されました。');
    Prepare(Obj(Root.GetValue('request')));
    if Command='generation_start' then Start;
    if Command='generation_start_image' then StartImage;
  end else if (Command='generation_cancel') or (Command='generation_submit_result') or (Command='generation_apply') or
    (Command='generation_submit_image') or (Command='generation_trace_image') or (Command='generation_prepare_trace') or
    (Command='generation_set_trace_options') then begin
    Require(Bool(Root,'apply'), 'apply: trueが必要です。'); CheckGenerationId(Root);
    if Command='generation_cancel' then Cancel
    else if Command='generation_set_trace_options' then begin
      Require(Str(Root,'image_sha256')=FImageHash,'調整する元地図画像が一致しません。');
      ConfigureTrace(Obj(Root.GetValue('options')));
    end
    else if Command='generation_submit_image' then begin
      SubmitImage(AutomationSession.Blobs.Get(Str(Root,'blob_id'),'image/png'));
      FSource := 'external_image_pipe'; FImageNote := '外部から受信した元地図画像です。';
    end
    else if (Command='generation_trace_image') or (Command='generation_prepare_trace') then begin
      Require(Str(Root,'image_sha256')=FImageHash, '確認した元地図画像のハッシュが一致しません。');
      if Root.GetValue('trace_options_token')<>nil then
        Require(Str(Root,'trace_options_token')=FTraceOptions.Token,'参照範囲・向き・簡略化が変更されました。');
      if Command='generation_trace_image' then TraceImage else PrepareTrace;
    end
    else if Command='generation_submit_result' then Submit(Obj(Root.GetValue('response')))
    else begin
      Require(Str(Root,'state_token')=FBaseToken, '生成元の状態トークンが一致しません。'); Apply;
    end;
  end else if Command='generation_show' then begin
    if Assigned(FOnShow) then FOnShow(Self);
  end else Require((Command='generation_status') or (Command='generation_get_request') or
    (Command='generation_get_result') or (Command='generation_get_image') or
    (Command='generation_get_trace_image'), '未対応の地名生成コマンドです。');
  Payload := Status;
  try
    if Command='generation_get_request' then begin
      Require(FRequest<>nil, '生成条件がありません。');
      Payload.AddPair('request',EffectiveRequest.Clone as TJSONValue);
      if FImageWorkflow then begin
        if Length(FImageBytes)>0 then begin
          var QueryRequest := CreateTraceRequest;
          var QueryImage := BuildGenerationReference(FImageBytes,FTraceOptions);
          Payload.RemovePair('request').Free; Payload.AddPair('request',QueryRequest);
          Payload.AddPair('prompt',GenerationTracePrompt(QueryRequest,GenerationImageHash(QueryImage)));
          Payload.AddPair('output_schema',GenerationOutputSchema(True));
        end else Payload.AddPair('prompt',GenerationImagePrompt(FRequest));
      end else begin
        Payload.AddPair('prompt',GenerationPrompt(FRequest)); Schema := GenerationOutputSchema;
        Payload.AddPair('output_schema',Schema);
      end;
      Payload.AddPair('state_token',FBaseToken);
    end;
    if Command='generation_get_image' then begin
      Require(Length(FImageBytes)>0, '元地図画像がまだありません。');
      Payload.AddPair('image',AutomationSession.Blobs.Store(FImageBytes,'image/png'));
      Payload.AddPair('request',FRequest.Clone as TJSONValue);
      Payload.AddPair('note',FImageNote);
    end;
    if Command='generation_get_trace_image' then begin
      Require(Length(FImageBytes)>0,'元地図画像がまだありません。');
      var Preview := BuildGenerationReference(FImageBytes,FTraceOptions);
      Payload.AddPair('image',AutomationSession.Blobs.Store(Preview,'image/png'));
      Payload.AddPair('trace_image_sha256',GenerationImageHash(Preview));
    end;
    if Command='generation_get_result' then begin
      Require(FReply<>nil, 'まだ結果を受信していません。');
      Payload.AddPair('request',EffectiveRequest.Clone as TJSONValue);
      Payload.AddPair('response',FReply.Clone as TJSONValue);
      if FCandidate<>nil then Payload.AddPair('document',FCandidate.Clone as TJSONValue);
      Payload.AddPair('state_token',FBaseToken);
    end;
    Result := OkResponse(Command,TJSONPair.Create('generation',Payload)); Payload := nil;
  finally Payload.Free; end;
end;
end.
