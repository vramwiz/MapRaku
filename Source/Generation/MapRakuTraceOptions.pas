// 参照画像の範囲・向きと簡略化の条件を、表示・画像化・Codex指示で共用する。
unit MapRakuTraceOptions;
interface
uses System.JSON;
type
  TMapRakuTraceOptions = record
    Zoom, PanX, PanY, Rotation: Double;
    Simplification: Integer;
    class function Default: TMapRakuTraceOptions; static;
    function ToJson: TJSONObject;
    function Token: string;
    function IdentityView: Boolean;
  end;
function ReadTraceOptions(Root: TJSONObject; const Current: TMapRakuTraceOptions): TMapRakuTraceOptions;
function TraceSimplificationCaption(Value: Integer): string;
implementation
uses System.SysUtils, System.Math, System.Hash, MapRakuAutomationValues;

class function TMapRakuTraceOptions.Default: TMapRakuTraceOptions;
begin
  Result := System.Default(TMapRakuTraceOptions); Result.Zoom := 1; Result.Simplification := 50;
end;
function TMapRakuTraceOptions.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create.AddPair('zoom',TJSONNumber.Create(Zoom))
    .AddPair('pan_x',TJSONNumber.Create(PanX)).AddPair('pan_y',TJSONNumber.Create(PanY))
    .AddPair('rotation_degrees',TJSONNumber.Create(Rotation))
    .AddPair('simplification',TJSONNumber.Create(Simplification));
end;
function TMapRakuTraceOptions.Token: string;
var Root: TJSONObject;
begin
  Root := ToJson;
  try Result := 'sha256:'+LowerCase(THashSHA2.GetHashString(Root.ToJSON)); finally Root.Free; end;
end;
function TMapRakuTraceOptions.IdentityView: Boolean;
begin Result := (Zoom=1) and (PanX=0) and (PanY=0) and (Rotation=0); end;

function ReadTraceOptions(Root: TJSONObject; const Current: TMapRakuTraceOptions): TMapRakuTraceOptions;
begin
  for var Pair in Root do Require(Pos(','+Pair.JsonString.Value+',',
    ',zoom,pan_x,pan_y,rotation_degrees,simplification,')>0,'未対応の読み取り条件です: '+Pair.JsonString.Value);
  Result.Zoom := Num(Root,'zoom',Current.Zoom,0.1,10);
  Result.PanX := Num(Root,'pan_x',Current.PanX,-4,4);
  Result.PanY := Num(Root,'pan_y',Current.PanY,-4,4);
  Result.Rotation := Num(Root,'rotation_degrees',Current.Rotation,-36000,36000);
  Result.Rotation := Result.Rotation-Floor((Result.Rotation+180)/360)*360;
  Result.Simplification := Int(Root,'simplification',Current.Simplification,0,100);
end;

function TraceSimplificationCaption(Value: Integer): string;
begin
  if Value=0 then Result := '元の形を優先'
  else if Value<35 then Result := '小さな凹凸や細部を整理'
  else if Value<70 then Result := '道の曲がり・建物の輪郭を整理'
  else Result := '道を水平・垂直へ、建物を簡単に';
end;
end.
