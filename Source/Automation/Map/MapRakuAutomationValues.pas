// AI入力の型・範囲を入口で検証し、暗黙の型変換による意図しない配置を防ぐ。
unit MapRakuAutomationValues;
interface
uses System.JSON;
function Obj(Value: TJSONValue): TJSONObject;
function Arr(Root: TJSONObject; const Key: string): TJSONArray;
function Str(Root: TJSONObject; const Key: string; const Default: string = ''): string;
function Num(Root: TJSONObject; const Key: string; Default: Double;
  Min: Double = -1000000; Max: Double = 1000000): Double;
function Int(Root: TJSONObject; const Key: string; Default, Min, Max: Integer): Integer;
function Bool(Root: TJSONObject; const Key: string; Default: Boolean = False): Boolean;
procedure Require(Condition: Boolean; const MessageText: string);
implementation
uses System.SysUtils, System.Math;
procedure Require(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise EArgumentException.Create(MessageText);
end;
function Obj(Value: TJSONValue): TJSONObject;
begin
  Require(Value is TJSONObject, 'Expected JSON object.');
  Result := TJSONObject(Value);
end;
function Arr(Root: TJSONObject; const Key: string): TJSONArray;
begin
  Require(Root.GetValue(Key) is TJSONArray, Key + ' must be an array.');
  Result := TJSONArray(Root.GetValue(Key));
end;
function Str(Root: TJSONObject; const Key, Default: string): string;
var V: TJSONValue;
begin
  V := Root.GetValue(Key);
  if V = nil then Exit(Default);
  Require(V is TJSONString, Key + ' must be a string.');
  Result := V.Value;
end;
function Num(Root: TJSONObject; const Key: string; Default, Min, Max: Double): Double;
var V: TJSONValue;
begin
  V := Root.GetValue(Key);
  Result := Default;
  if V <> nil then begin
    Require(V is TJSONNumber, Key + ' must be a number.');
    Result := TJSONNumber(V).AsDouble;
  end;
  Require(not IsNan(Result) and not IsInfinite(Result) and
    (Result >= Min) and (Result <= Max), Key + ' is out of range.');
end;
function Int(Root: TJSONObject; const Key: string; Default, Min, Max: Integer): Integer;
var N: Double;
begin
  N := Num(Root, Key, Default, Min, Max);
  Require(Frac(N) = 0, Key + ' must be an integer.');
  Result := Trunc(N);
end;
function Bool(Root: TJSONObject; const Key: string; Default: Boolean): Boolean;
var V: TJSONValue;
begin
  V := Root.GetValue(Key);
  if V = nil then Exit(Default);
  Require(V is TJSONBool, Key + ' must be boolean.');
  Result := TJSONBool(V).AsBoolean;
end;
end.
