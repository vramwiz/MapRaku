// 内蔵パターンの定義と値を保持する。描画資源を持たず、配列は変更時に複製する。
unit MapRakuPatternStyle;

interface

uses Vcl.Graphics;

type
  TMapRakuPatternKind = (slptHatch, slptDots, slptGrid,
    slptChecker, slptWave, slptHoneycomb);
  TMapRakuPatternParameter = record
    Id: string;             // 保存用の安定ID。
    Caption: string;        // UIの項目名。
    Minimum: Single;        // 許容する下限（文書の論理単位）。
    Maximum: Single;        // 許容する上限。
    DefaultValue: Single;   // 種類を初めて選ぶときの値。
  end;
  TMapRakuPatternValue = record
    Id: string;             // 定義のパラメーターID。
    Value: Single;          // 倍率に依存しない設定値。
  end;
  TMapRakuPatternColor = record
    Id: string;             // 色数を固定しない保存用ID。
    Color: TColor;          // VCL色。
    Opacity: Single;        // 0は透明、1は不透明。
  end;
  TMapRakuPatternStyle = record
  private
    FId: string;                                  // 選択した内蔵定義。
    FValues: TArray<TMapRakuPatternValue>;     // 安定IDで保存する数値。
    FColors: TArray<TMapRakuPatternColor>;     // 拡張可能な色スロット。
    FFlipHorizontal: Boolean; // オブジェクトのローカル左右反転を模様の向きにも適用する。
    FFlipVertical: Boolean;   // オブジェクトのローカル上下反転を模様の向きにも適用する。
  public
    // 定義の既定値を生成し、前景色にBaseColorを使用する。
    class function Create(Kind: TMapRakuPatternKind;
      BaseColor: TColor): TMapRakuPatternStyle; static;
    // 未知のIDは例外にし、現在の定義を返す。
    function Kind: TMapRakuPatternKind;
    // 配列を複製して返す。呼び出し側の編集は元の値に影響しない。
    function Values: TArray<TMapRakuPatternValue>;
    // 色スロットの配列も独立したコピーとして返す。
    function Colors: TArray<TMapRakuPatternColor>;
    // 指定IDの数値を返す。未定義IDは例外にする。
    function Number(const Id: string): Single;
    // 範囲と有限値を検証し、コピー後に数値を変更する。
    procedure SetNumber(const Id: string; Value: Single);
    // 指定IDの色を取得する。未定義IDは例外にする。
    function Slot(const Id: string): TMapRakuPatternColor;
    // 色と不透明度を検証し、コピー後に対象スロットを変更する。
    procedure SetSlot(const Value: TMapRakuPatternColor);
    // ID、全設定値、色が一致するときにTrueを返す。
    function SameAs(const Other: TMapRakuPatternStyle): Boolean;
    property Id: string read FId;
    property FlipHorizontal: Boolean read FFlipHorizontal write FFlipHorizontal;
    property FlipVertical: Boolean read FFlipVertical write FFlipVertical;
  end;

const
  PATTERN_IDS: array[TMapRakuPatternKind] of string =
    ('hatch', 'dots', 'grid', 'checker', 'wave', 'honeycomb'); // 保存ID。順番や翻訳に依存させない。
  PATTERN_NAMES: array[TMapRakuPatternKind] of string =
    ('斜線', 'ドット', '格子', '市松', '波線', 'ハニカム'); // 選択UIの表示名。

// 内蔵定義を解決し、未知のIDを拒否する。
function MapRakuPatternKind(const Id: string): TMapRakuPatternKind;
// 選択した種類に必要な項目だけを定義順で返す。
function MapRakuPatternParameters(Kind: TMapRakuPatternKind): TArray<TMapRakuPatternParameter>;
// 色スロットIDを種類固有の表示名へ変換する。
function MapRakuPatternColorName(Kind: TMapRakuPatternKind; const Id: string): string;
// 定義の色スロット一覧を返す。色数を増やす定義はここへ追加できる。
function MapRakuPatternDefaultColors(Kind: TMapRakuPatternKind;
  BaseColor: TColor): TArray<TMapRakuPatternColor>;

implementation

uses System.SysUtils, System.Math;

function Parameter(const Id, Caption: string;
  MinValue, MaxValue, DefaultValue: Single): TMapRakuPatternParameter;
begin
  Result.Id := Id;
  Result.Caption := Caption;
  Result.Minimum := MinValue;
  Result.Maximum := MaxValue;
  Result.DefaultValue := DefaultValue;
end;

function MapRakuPatternParameters(Kind: TMapRakuPatternKind): TArray<TMapRakuPatternParameter>;
begin
  case Kind of
    slptHatch: Result := [Parameter('width', '線幅', 0.1, 1024, 2),
      Parameter('spacing', '間隔', 1, 1024, 16)];
    slptDots: Result := [Parameter('size', '点サイズ', 0.1, 1024, 6),
      Parameter('spacing', '間隔', 1, 1024, 16)];
    slptGrid: Result := [Parameter('width', '線幅', 0.1, 1024, 2),
      Parameter('spacingX', '横間隔', 1, 1024, 24), Parameter('spacingY', '縦間隔', 1, 1024, 24)];
    slptChecker: Result := [Parameter('size', 'マスサイズ', 1, 1024, 16)];
    slptWave: Result := [Parameter('width', '線幅', 0.1, 1024, 2),
      Parameter('amplitude', '振幅', 0.1, 256, 6), Parameter('period', '周期', 1, 1024, 32),
      Parameter('spacing', '行間隔', 1, 1024, 24)];
    slptHoneycomb: Result := [Parameter('size', '六角形半径', 1, 256, 14),
      Parameter('width', '線幅', 0.1, 1024, 2), Parameter('spacing', '間隔', 0, 256, 0)];
  end;
  Result := Result + [Parameter('angle', '角度', -180, 180, 0),
    Parameter('offsetX', '横移動', -4096, 4096, 0), Parameter('offsetY', '縦移動', -4096, 4096, 0)];
  if Kind = slptHatch then Result[Length(Result) - 3].DefaultValue := 45;
end;

function MapRakuPatternKind(const Id: string): TMapRakuPatternKind;
var K: TMapRakuPatternKind;
begin
  for K := Low(K) to High(K) do
    if PATTERN_IDS[K] = Id then Exit(K);
  raise EConvertError.Create('Unknown pattern: ' + Id);
end;

function MapRakuPatternColorName(Kind: TMapRakuPatternKind; const Id: string): string;
begin
  if Id = 'background' then Exit('背景色');
  if Id <> 'foreground' then Exit(Id);
  case Kind of
    slptDots: Result := '点の色';
    slptChecker: Result := '前景色';
  else Result := '線の色';
  end;
end;

function MapRakuPatternDefaultColors(Kind: TMapRakuPatternKind;
  BaseColor: TColor): TArray<TMapRakuPatternColor>;
begin
  // 初期6種はいずれも前景と背景を使う。保存側とUI側は要素数をこの定義から取得する。
  Result := nil;
  SetLength(Result, 2);
  Result[0].Id := 'foreground';
  Result[0].Color := ColorToRGB(BaseColor);
  Result[0].Opacity := 1;
  Result[1].Id := 'background';
  Result[1].Color := clWhite;
  Result[1].Opacity := 0;
end;

class function TMapRakuPatternStyle.Create(Kind: TMapRakuPatternKind;
  BaseColor: TColor): TMapRakuPatternStyle;
var P: TMapRakuPatternParameter; I: Integer;
begin
  Result := Default(TMapRakuPatternStyle);
  Result.FId := PATTERN_IDS[Kind];
  for P in MapRakuPatternParameters(Kind) do
  begin
    I := Length(Result.FValues);
    SetLength(Result.FValues, I + 1);
    Result.FValues[I].Id := P.Id;
    Result.FValues[I].Value := P.DefaultValue;
  end;
  Result.FColors := MapRakuPatternDefaultColors(Kind, BaseColor);
end;

function TMapRakuPatternStyle.Kind: TMapRakuPatternKind;
begin
  Result := MapRakuPatternKind(FId);
end;

function TMapRakuPatternStyle.Values: TArray<TMapRakuPatternValue>;
begin
  Result := Copy(FValues);
end;

function TMapRakuPatternStyle.Colors: TArray<TMapRakuPatternColor>;
begin
  Result := Copy(FColors);
end;

function TMapRakuPatternStyle.Number(const Id: string): Single;
var V: TMapRakuPatternValue;
begin
  for V in FValues do if V.Id = Id then Exit(V.Value);
  raise EConvertError.Create('Unknown pattern parameter: ' + Id);
end;

procedure TMapRakuPatternStyle.SetNumber(const Id: string; Value: Single);
var P: TMapRakuPatternParameter; I: Integer;
begin
  for P in MapRakuPatternParameters(Kind) do
    if P.Id = Id then
    begin
      if IsNan(Value) or IsInfinite(Value) or (Value < P.Minimum) or (Value > P.Maximum) then
        raise EConvertError.Create('Pattern parameter out of range: ' + Id);
      FValues := Copy(FValues);
      for I := 0 to High(FValues) do if FValues[I].Id = Id then
      begin
        FValues[I].Value := Value;
        Exit;
      end;
    end;
  raise EConvertError.Create('Unknown pattern parameter: ' + Id);
end;

function TMapRakuPatternStyle.Slot(const Id: string): TMapRakuPatternColor;
var C: TMapRakuPatternColor;
begin
  for C in FColors do if C.Id = Id then Exit(C);
  raise EConvertError.Create('Unknown pattern color: ' + Id);
end;

procedure TMapRakuPatternStyle.SetSlot(const Value: TMapRakuPatternColor);
var I: Integer;
begin
  if IsNan(Value.Opacity) or IsInfinite(Value.Opacity) or (Value.Opacity < 0) or (Value.Opacity > 1) then
    raise EConvertError.Create('Pattern opacity out of range');
  for I := 0 to High(FColors) do if FColors[I].Id = Value.Id then
  begin
    FColors := Copy(FColors);
    FColors[I] := Value;
    FColors[I].Color := ColorToRGB(Value.Color);
    Exit;
  end;
  raise EConvertError.Create('Unknown pattern color: ' + Value.Id);
end;

function TMapRakuPatternStyle.SameAs(const Other: TMapRakuPatternStyle): Boolean;
var I: Integer;
begin
  Result := (FId = Other.FId) and (Length(FValues) = Length(Other.FValues)) and
    (Length(FColors) = Length(Other.FColors)) and
    (FFlipHorizontal = Other.FFlipHorizontal) and
    (FFlipVertical = Other.FFlipVertical);
  if not Result then Exit;
  for I := 0 to High(FValues) do
    if (FValues[I].Id <> Other.FValues[I].Id) or (FValues[I].Value <> Other.FValues[I].Value) then Exit(False);
  for I := 0 to High(FColors) do
    if (FColors[I].Id <> Other.FColors[I].Id) or (FColors[I].Color <> Other.FColors[I].Color) or
      (FColors[I].Opacity <> Other.FColors[I].Opacity) then Exit(False);
end;

end.
