// 編集メニューと、操作中にレイヤー一覧を再描画せず確定後に更新する契約を検証する。
unit MapRakuEditorRefreshTests;
interface
procedure CheckEditorRefresh;
implementation
uses System.Classes, System.Types, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls,
  Winapi.Windows, Winapi.Messages, MapRakuMainForm, MapRakuDocument, MapRakuLayerPanelFrame,
  MapRakuLayerList, MapRakuEditActionsUI, MapRakuTestSupport, MapRakuDarkDialogControls;
type
  TMenuReceiver = class
    Count: Integer;
    procedure Execute(Sender: TObject);
  end;
  TInvalidateRecorder = class
    Original: TWndMethod;
    Count: Integer;
    procedure Receive(var Message: TMessage);
  end;

procedure TInvalidateRecorder.Receive(var Message: TMessage);
begin
  if (Message.Msg=CM_INVALIDATE) and (Message.WParam=0) then Inc(Count);
  Original(Message);
end;

procedure TMenuReceiver.Execute(Sender: TObject);
begin Inc(Count); end;

function GenerationItem(EditUI: TVectArtEditActionsUI): TPanel;
begin
  Result := nil;
  for var I := 0 to EditUI.Menu.Popup.ControlCount-1 do
    if (EditUI.Menu.Popup.Controls[I] is TPanel) and
      (TPanel(EditUI.Menu.Popup.Controls[I]).Caption='地名から地図を作成...') then
      Exit(TPanel(EditUI.Menu.Popup.Controls[I]));
  Check(False,'Generation menu entry missing');
end;

procedure CheckGenerationMenu;
var Host: TForm; Bar: TPanel; EditUI: TVectArtEditActionsUI; Receiver: TMenuReceiver;
  Item: TPanel;
begin
  Host := TForm.Create(nil); Receiver := TMenuReceiver.Create;
  try
    Bar := TPanel.Create(Host); Bar.Parent := Host;
    EditUI := TVectArtEditActionsUI.CreateForHosts(Host,Host,Bar);
    EditUI.OnGenerationRequest := Receiver.Execute; Item := GenerationItem(EditUI);
    Check(Item.Visible and Item.Enabled,'Generation must be available without a selection');
    EditUI.CanvasSettingsVisible := False;
    Check(Item.Visible and (Item.Top+Item.Height<=EditUI.Menu.Popup.Height),'Generation menu must fit plugin without canvas settings');
    EditUI.CanvasSettingsVisible := True;
    Check(Item.Visible and (Item.Top+Item.Height<=EditUI.Menu.Popup.Height),'Generation menu must fit standalone');
    Item.OnClick(Item);
    Check((Receiver.Count=1) and not EditUI.Menu.Visible,'Menu must execute once and close');
  finally Host.Free; Receiver.Free; end;
end;

procedure CheckDeferredLayerRefresh;
var Form: TMainForm; Layers: TVectArtLayerListControl; EditUI: TVectArtEditActionsUI;
  Timer: TTimer; Path: TVectArtPathData; Recorder: TInvalidateRecorder;
begin
  Form := TMainForm.Create(nil); Recorder := TInvalidateRecorder.Create;
  Layers := nil;
  try
    Form.HandleNeeded; Layers := nil; EditUI := nil;
    for var I := 0 to Form.ComponentCount-1 do begin
      if Form.Components[I] is TLayerPanelFrame then Layers := TLayerPanelFrame(Form.Components[I]).LayerList;
      if Form.Components[I] is TVectArtEditActionsUI then EditUI := TVectArtEditActionsUI(Form.Components[I]);
      if Form.Components[I] is TDarkDialogButton then
        Check(TDarkDialogButton(Form.Components[I]).Caption<>'地名から地図を作成','Toolbar generation button must be removed');
    end;
    Check((Layers<>nil) and (EditUI<>nil),'Editor UI fixtures');
    Check(Assigned(EditUI.OnGenerationRequest) and Assigned(GenerationItem(EditUI).OnClick),'Shared main form must connect generation menu');
    Timer := Form.FindComponent('LayerRefreshTimer') as TTimer;
    Path := Road('road',PointF(-100,0),PointF(100,0)); Form.Document.InsertPath(1,Path);
    Layers.HandleNeeded; Recorder.Original := Layers.WindowProc; Layers.WindowProc := Recorder.Receive;
    Form.Document.BeginInteractiveUpdate;
    try
      for var I := 1 to 10 do begin
        Path.Vertices[0].Position.Y := I; TVectArtPathLayer(Form.Document[1]).Vertices := Path.Vertices;
        Form.Document.Changed;
        if Odd(I) then EditUI.EditorState.NextVertexKind := slvkBezier
        else EditUI.EditorState.NextVertexKind := slvkSharp;
        Timer.OnTimer(nil);
        Check(Timer.Enabled and (Recorder.Count=0),
          'Interactive document/state changes must not invalidate the layer list');
      end;
    finally Form.Document.EndInteractiveUpdate; end;
    Check(not Timer.Enabled,'Ending edit must stop polling');
    Check(Recorder.Count=1,'Ending edit must refresh the layer list once');
    Form.Document.Changed;
    Check(Recorder.Count=2,'Normal document changes must still update layers');
  finally
    if (Layers<>nil) and Assigned(Recorder.Original) then Layers.WindowProc := Recorder.Original;
    Form.Free; Recorder.Free;
  end;
end;

procedure CheckEditorRefresh;
begin
  CheckGenerationMenu; CheckDeferredLayerRefresh;
  Writeln('PASS: shared generation menu, no toolbar button, deferred layer repaint and final refresh');
end;
end.
