// 元画像を座標条件と共に登録し、向きや対象範囲が生成途中で変わることを検出する。
unit MapRakuAutomationReference;
interface
uses System.JSON, MapRakuDocument, MapRakuCanvas;
function SetAutomationReference(Root: TJSONObject; Document: TVectArtDocument;
  Canvas: TVectArtCanvasControl): TJSONObject;
function GetAutomationReference(Canvas: TVectArtCanvasControl): TJSONObject;
function ClearAutomationReference(Canvas: TVectArtCanvasControl): TJSONObject;
implementation
uses System.SysUtils, System.Classes, System.Types, System.Math, Vcl.Graphics, Vcl.Imaging.pngimage,
  MapRakuAutomationValues, MapRakuAutomationSession;
function BigEndian(const Bytes: TBytes; Offset: Integer): Cardinal;
begin
  Result := (Cardinal(Bytes[Offset]) shl 24) or (Cardinal(Bytes[Offset+1]) shl 16) or
    (Cardinal(Bytes[Offset+2]) shl 8) or Bytes[Offset+3];
end;
function DecodeReference(const Bytes: TBytes; out Width,Height: Integer): TBytes;
var Stream: TBytesStream; Png: TPngImage; Bitmap: TBitmap;
  X,Y: Integer; Row: PByte; Dest: PByte;
begin
  // 圧縮率の高い巨大PNGをデコードする前に寸法を制限し、VCLスレッドのメモリを守る。
  Require((Length(Bytes) >= 33) and (BigEndian(Bytes,0) = $89504E47) and
    (BigEndian(Bytes,4) = $0D0A1A0A) and (BigEndian(Bytes,12) = $49484452), 'Expected PNG.');
  Require((BigEndian(Bytes,16) > 0) and (BigEndian(Bytes,16) <= 4096) and
    (BigEndian(Bytes,20) > 0) and (BigEndian(Bytes,20) <= 4096), 'PNG dimensions must be 1..4096.');
  Stream := TBytesStream.Create(Bytes); Png := TPngImage.Create; Bitmap := TBitmap.Create;
  try
    Png.LoadFromStream(Stream);
    Width := Png.Width; Height := Png.Height;
    Bitmap.PixelFormat := pf32bit; Bitmap.SetSize(Width,Height);
    Bitmap.Canvas.Brush.Color := clWhite;
    Bitmap.Canvas.FillRect(Rect(0,0,Width,Height));
    Bitmap.Canvas.Draw(0,0,Png);
    SetLength(Result,Width*Height*4);
    Dest := @Result[0];
    for Y := 0 to Height-1 do begin
      Row := Bitmap.ScanLine[Y];
      for X := 0 to Width-1 do begin
        Dest[0] := Row[2]; Dest[1] := Row[1]; Dest[2] := Row[0]; Dest[3] := 255;
        Inc(Dest,4); Inc(Row,4);
      end;
    end;
  finally
    Bitmap.Free; Png.Free; Stream.Free;
  end;
end;
function GetAutomationReference(Canvas: TVectArtCanvasControl): TJSONObject;
var Current: Boolean; Conditions: TJSONObject;
begin
  Require(Canvas <> nil, 'Canvas unavailable.');
  Result := TJSONObject.Create;
  Result.AddPair('background_token',Canvas.ReferenceBackgroundToken);
  Conditions := AutomationSession.Conditions;
  Current := (Conditions <> nil) and (AutomationSession.ReferenceToken = Canvas.ReferenceBackgroundToken);
  if Current then Current := (Num(Conditions,'canvas_width',0)=Canvas.Document.CanvasLayer.Width) and
    (Num(Conditions,'canvas_height',0)=Canvas.Document.CanvasLayer.Height);
  Result.AddPair('conditions_current',TJSONBool.Create(Current));
  if Conditions <> nil then Result.AddPair('conditions',Conditions.Clone as TJSONValue);
end;
function ClearAutomationReference(Canvas: TVectArtCanvasControl): TJSONObject;
begin
  Require(Canvas <> nil, 'Canvas unavailable.');
  Canvas.SetReferenceBackgroundRgba(nil,0,0);
  FreeAndNil(AutomationSession.Conditions);
  AutomationSession.ReferenceImage := nil;
  AutomationSession.ReferenceToken := '';
  Result := GetAutomationReference(Canvas);
end;
function SetAutomationReference(Root: TJSONObject; Document: TVectArtDocument;
  Canvas: TVectArtCanvasControl): TJSONObject;
var Conditions, Saved: TJSONObject; Bytes,Pixels: TBytes; Width,Height: Integer;
begin
  Require(Canvas <> nil, 'Canvas unavailable.');
  Require(Str(Root,'background_token') = Canvas.ReferenceBackgroundToken, 'Reference changed; fetch new snapshot.');
  Conditions := Obj(Root.GetValue('conditions'));
  Require(Conditions.GetValue('north_clockwise_degrees') <> nil, 'Declare the fixed north direction.');
  Num(Conditions,'north_clockwise_degrees',0,-360,360);
  // 元画像は生成前に回転・切出し済みとし、座標対応の曖昧な二重回転を行わない。
  Require(Bool(Conditions,'image_already_oriented'), 'Supply a pre-oriented, cropped PNG.');
  Bytes := AutomationSession.Blobs.Get(Str(Root,'blob_id'),'image/png');
  Pixels := DecodeReference(Bytes,Width,Height);
  Require(Abs(Width / Height - Document.CanvasLayer.Width / Document.CanvasLayer.Height) < 0.002,
    'Reference and canvas must have the same aspect ratio.');
  Saved := Conditions.Clone as TJSONObject;
  try
    Saved.AddPair('source_width',TJSONNumber.Create(Width));
    Saved.AddPair('source_height',TJSONNumber.Create(Height));
    Saved.AddPair('canvas_width',TJSONNumber.Create(Document.CanvasLayer.Width));
    Saved.AddPair('canvas_height',TJSONNumber.Create(Document.CanvasLayer.Height));
    Canvas.SetReferenceBackgroundRgba(Pixels,Width,Height);
    AutomationSession.Conditions.Free;
    AutomationSession.Conditions := Saved;
    Saved := nil;
    AutomationSession.ReferenceToken := Canvas.ReferenceBackgroundToken;
    AutomationSession.ReferenceImage := Bytes;
    Result := GetAutomationReference(Canvas);
  finally
    Saved.Free;
  end;
end;
end.
