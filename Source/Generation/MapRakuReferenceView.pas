// 参照範囲をホイール・移動・回転アイコンで調整する。送信用PNGと同じ変換で描画する。
unit MapRakuReferenceView;
interface
uses System.Classes, System.Types, System.Skia, Vcl.Controls, Vcl.Skia, MapRakuTraceOptions;
type
  TMapRakuReferenceView = class(TCustomControl)
  private
    FDraw: TSkPaintBox;
    FImage: ISkImage;
    FOptions, FDragOptions: TMapRakuTraceOptions;
    FDragOrigin: TPoint;
    FDragKind: (rdNone, rdPan, rdRotate);
    FOnChange: TNotifyEvent;
    function Logical(Value: Integer): Integer;
    function FrameRect: TRectF;
    function RotationRect: TRect;
    procedure DrawCropMarks(const Canvas: ISkCanvas; const Frame: TRectF);
    procedure DrawOutsideShade(const Canvas: ISkCanvas; const Frame: TRectF);
    procedure DrawReference(Sender: TObject; const Canvas: ISkCanvas; const Dest: TRectF; const Opacity: Single);
    procedure SetOptions(const Value: TMapRakuTraceOptions);
    procedure CommitOptions(const Value: TMapRakuTraceOptions);
    procedure DrawMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DrawMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure DrawMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadImage(const FileName: string);
    property Options: TMapRakuTraceOptions read FOptions write SetOptions;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;
implementation
uses System.SysUtils, System.Math, System.IOUtils, System.JSON, System.UITypes,
  MapRakuGenerationImage;

constructor TMapRakuReferenceView.Create(AOwner: TComponent);
begin
  inherited; TabStop := True; DoubleBuffered := True;
  FOptions := TMapRakuTraceOptions.Default;
  FDraw := TSkPaintBox.Create(Self); FDraw.Parent := Self; FDraw.Align := alClient;
  FDraw.OnDraw := DrawReference; FDraw.OnMouseDown := DrawMouseDown; FDraw.OnMouseMove := DrawMouseMove;
  FDraw.OnMouseUp := DrawMouseUp;
  FDraw.ShowHint := True; FDraw.Hint := 'トンボの内側を地図データにします。ホイールで拡大縮小、左ドラッグで移動。トンボ付近の回転アイコンを左右へドラッグ。';
end;
function TMapRakuReferenceView.Logical(Value: Integer): Integer;
begin Result := Round(Value*CurrentPPI/96); end;
function TMapRakuReferenceView.FrameRect: TRectF;
var Ratio, W, H: Single;
begin
  Ratio := 16/9; if FImage<>nil then Ratio := FImage.Width/FImage.Height;
  W := Max(1,ClientWidth-Logical(112)); H := Max(1,ClientHeight-Logical(112));
  W := Min(W,H*Ratio); H := W/Ratio;
  Result := TRectF.Create((ClientWidth-W)/2,(ClientHeight-H)/2,
    (ClientWidth+W)/2,(ClientHeight+H)/2);
end;
function TMapRakuReferenceView.RotationRect: TRect;
var Frame: TRectF; X,Y,R: Integer;
begin
  Frame := FrameRect; X := Round(Frame.Right)+Logical(25); Y := Round(Frame.Top)-Logical(25);
  R := Logical(17); Result := Rect(X-R,Y-R,X+R,Y+R);
end;
procedure TMapRakuReferenceView.LoadImage(const FileName: string);
begin
  if FileName='' then FImage := nil else FImage := TSkImage.MakeFromEncoded(TFile.ReadAllBytes(FileName));
  FDragKind := rdNone; FDraw.Redraw;
end;
procedure TMapRakuReferenceView.SetOptions(const Value: TMapRakuTraceOptions);
begin
  if (FOptions.Zoom=Value.Zoom) and (FOptions.PanX=Value.PanX) and (FOptions.PanY=Value.PanY) and
    (FOptions.Rotation=Value.Rotation) and (FOptions.Simplification=Value.Simplification) then Exit;
  FOptions := Value; FDraw.Redraw;
end;
procedure TMapRakuReferenceView.CommitOptions(const Value: TMapRakuTraceOptions);
var Root: TJSONObject;
begin
  Root := Value.ToJson;
  try FOptions := ReadTraceOptions(Root,FOptions); finally Root.Free; end;
  FDraw.Redraw;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TMapRakuReferenceView.DrawOutsideShade(const Canvas: ISkCanvas; const Frame: TRectF);
var Paint: ISkPaint;
begin
  Paint := TSkPaint.Create; Paint.Color := $A6000000;
  // 暗い部分は確認用。送信用PNGにはマスクもトンボも含めない。
  Canvas.DrawRect(TRectF.Create(0,0,ClientWidth,Frame.Top),Paint);
  Canvas.DrawRect(TRectF.Create(0,Frame.Bottom,ClientWidth,ClientHeight),Paint);
  Canvas.DrawRect(TRectF.Create(0,Frame.Top,Frame.Left,Frame.Bottom),Paint);
  Canvas.DrawRect(TRectF.Create(Frame.Right,Frame.Top,ClientWidth,Frame.Bottom),Paint);
end;

procedure TMapRakuReferenceView.DrawCropMarks(const Canvas: ISkCanvas; const Frame: TRectF);
var Paint: ISkPaint; X,Y,SX,SY,Gap,Len: Single;
begin
  Paint := TSkPaint.Create; Paint.AntiAlias := True; Paint.Style := TSkPaintStyle.Stroke;
  Gap := Logical(6); Len := Logical(21);
  for var Pass := 0 to 1 do begin
    if Pass=0 then begin Paint.Color := $FF151515; Paint.StrokeWidth := Logical(4); end
    else begin Paint.Color := $FFF2F2F2; Paint.StrokeWidth := Logical(2); end;
    for var Corner := 0 to 3 do begin
      SX := -1; X := Frame.Left; if Odd(Corner) then begin SX := 1; X := Frame.Right; end;
      SY := -1; Y := Frame.Top; if Corner>=2 then begin SY := 1; Y := Frame.Bottom; end;
      Canvas.DrawLine(X+SX*Gap,Y,X+SX*Len,Y,Paint);
      Canvas.DrawLine(X,Y+SY*Gap,X,Y+SY*Len,Paint);
    end;
  end;
  Paint.Color := $FFCCCCCC; Paint.StrokeWidth := Logical(1); Canvas.DrawRect(Frame,Paint);
end;

procedure TMapRakuReferenceView.DrawReference(Sender: TObject; const Canvas: ISkCanvas;
  const Dest: TRectF; const Opacity: Single);
var Paint: ISkPaint; Font: ISkFont; Frame: TRectF; Knob: TRect; Color: TAlphaColor;
begin
  Canvas.Clear($FF252525); Frame := FrameRect; Knob := RotationRect;
  DrawGenerationReference(Canvas,FImage,Frame,TRectF.Create(0,0,ClientWidth,ClientHeight),FOptions);
  DrawOutsideShade(Canvas,Frame); DrawCropMarks(Canvas,Frame);
  Paint := TSkPaint.Create; Paint.AntiAlias := True;
  Color := $FFE6E6E6; if not Enabled then Color := $FF888888;
  Paint.Color := Color;
  Font := TSkFont.Create(TSkTypeface.MakeFromName('Yu Gothic UI',TSkFontStyle.Normal),Logical(12));
  Canvas.DrawSimpleText('明るい枠内を地図データにします',Logical(12),Logical(23),Font,Paint);
  Canvas.DrawSimpleText(Format('%.0f%%   回転 %.1f°',[FOptions.Zoom*100,FOptions.Rotation]),
    Frame.Left,ClientHeight-Logical(13),Font,Paint);
  Canvas.DrawSimpleText('ホイール：拡大縮小　ドラッグ：移動',Frame.Left,ClientHeight-Logical(33),Font,Paint);
  Paint.Color := $FF386A92;
  Canvas.DrawCircle(Knob.CenterPoint.X,Knob.CenterPoint.Y,Logical(17),Paint);
  Font := TSkFont.Create(TSkTypeface.MakeFromName('Segoe UI Symbol',TSkFontStyle.Normal),Logical(25));
  Paint.Color := Color;
  Canvas.DrawSimpleText('↻',Knob.CenterPoint.X-Logical(11),Knob.CenterPoint.Y+Logical(9),Font,Paint);
end;

procedure TMapRakuReferenceView.DrawMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin MouseDown(Button,Shift,X,Y); end;
procedure TMapRakuReferenceView.DrawMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin MouseMove(Shift,X,Y); end;
procedure TMapRakuReferenceView.DrawMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin MouseUp(Button,Shift,X,Y); end;
procedure TMapRakuReferenceView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if not Enabled or (FImage=nil) or (Button<>mbLeft) then Exit;
  if RotationRect.Contains(Point(X,Y)) then FDragKind := rdRotate
  else if FrameRect.Contains(PointF(X,Y)) then FDragKind := rdPan else Exit;
  SetFocus; FDragOrigin := Point(X,Y); FDragOptions := FOptions; MouseCapture := True;
end;
procedure TMapRakuReferenceView.MouseMove(Shift: TShiftState; X, Y: Integer);
var Next: TMapRakuTraceOptions; Frame: TRectF;
begin
  inherited;
  if not Enabled then Exit;
  if FDragKind=rdNone then begin
    if RotationRect.Contains(Point(X,Y)) then Cursor := crSizeWE else Cursor := crSizeAll;
    FDraw.Cursor := Cursor; Exit;
  end;
  Next := FDragOptions; Frame := FrameRect;
  if FDragKind=rdPan then begin
    Next.PanX := EnsureRange(FDragOptions.PanX+(X-FDragOrigin.X)/Max(1,Frame.Width),-4.0,4.0);
    Next.PanY := EnsureRange(FDragOptions.PanY+(Y-FDragOrigin.Y)/Max(1,Frame.Height),-4.0,4.0);
  end else begin
    Next.Rotation := FDragOptions.Rotation+(X-FDragOrigin.X)*0.5;
    if ssShift in Shift then Next.Rotation := Round(Next.Rotation/15)*15;
  end;
  CommitOptions(Next);
end;
procedure TMapRakuReferenceView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin inherited; if Button=mbLeft then begin FDragKind := rdNone; MouseCapture := False; end; end;

function TMapRakuReferenceView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var Next: TMapRakuTraceOptions; Frame: TRectF; CursorPoint: TPoint; Factor, CX, CY: Double;
begin
  Result := False;
  if not Enabled or (FImage=nil) or (FDragKind<>rdNone) then Exit;
  Frame := FrameRect; CursorPoint := ScreenToClient(MousePos); Next := FOptions;
  Next.Zoom := EnsureRange(FOptions.Zoom*Power(1.15,WheelDelta/120),0.1,10.0);
  Factor := Next.Zoom/FOptions.Zoom;
  CX := Frame.CenterPoint.X+FOptions.PanX*Frame.Width;
  CY := Frame.CenterPoint.Y+FOptions.PanY*Frame.Height;
  Next.PanX := EnsureRange((CursorPoint.X+(CX-CursorPoint.X)*Factor-Frame.CenterPoint.X)/Frame.Width,-4.0,4.0);
  Next.PanY := EnsureRange((CursorPoint.Y+(CY-CursorPoint.Y)*Factor-Frame.CenterPoint.Y)/Frame.Height,-4.0,4.0);
  CommitOptions(Next); Result := True;
end;
end.
