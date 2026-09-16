// 非破壊フィルターの種類と編集可能な値だけを保持する。
// 描画、永続化、UI操作には依存しない。
unit MapRakuFilters;

interface

uses
  Vcl.Graphics;

type
  TMapRakuFilterKind = (slfkOutline, slfkShadow, slfkBlur);

  // 全フィルターに共通する有効状態と、派生型を判別する不変の種類を持つ。
  TMapRakuFilter = class
  private
    FEnabled: Boolean;
    FKind: TMapRakuFilterKind;
  protected
    constructor Create(AKind: TMapRakuFilterKind);
  public
    // 元インスタンスと所有権を共有しない完全な複製を返す。
    function Clone: TMapRakuFilter; virtual; abstract;
    // UIへ表示する種類名を返す。
    function DisplayName: string;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Kind: TMapRakuFilterKind read FKind;
  end;

  TMapRakuOutlineFilter = class(TMapRakuFilter)
  private
    FColor: TColor;
    FWidth: Single;
  public
    // UIとJSONで共通使用する初期値を設定する。
    constructor Create;
    // 有効状態、色、幅を独立したインスタンスへ複製する。
    function Clone: TMapRakuFilter; override;
    property Color: TColor read FColor write FColor;
    property Width: Single read FWidth write FWidth;
  end;

  TMapRakuShadowFilter = class(TMapRakuFilter)
  private
    FBlurRadius: Single;
    FColor: TColor;
    FOffsetX: Single;
    FOffsetY: Single;
    FOpacity: Single;
  public
    // UIとJSONで共通使用する初期値を設定する。
    constructor Create;
    // 有効状態を含む影の全パラメーターを複製する。
    function Clone: TMapRakuFilter; override;
    property BlurRadius: Single read FBlurRadius write FBlurRadius;
    property Color: TColor read FColor write FColor;
    property OffsetX: Single read FOffsetX write FOffsetX;
    property OffsetY: Single read FOffsetY write FOffsetY;
    property Opacity: Single read FOpacity write FOpacity;
  end;

  TMapRakuBlurFilter = class(TMapRakuFilter)
  private
    FRadius: Single;
  public
    // UIとJSONで共通使用する初期値を設定する。
    constructor Create;
    // 有効状態と半径を独立したインスタンスへ複製する。
    function Clone: TMapRakuFilter; override;
    property Radius: Single read FRadius write FRadius;
  end;

// 指定した種類を追加UIと同じ初期値で生成し、呼び出し側へ所有権を渡す。
function CreateDefaultMapRakuFilter(
  Kind: TMapRakuFilterKind): TMapRakuFilter;
// 同じ種類のフィルター間で、有効状態を含む編集可能値をすべてコピーする。
procedure AssignMapRakuFilter(Target, Source: TMapRakuFilter);

implementation

uses
  System.SysUtils;

procedure AssignMapRakuFilter(Target, Source: TMapRakuFilter);
begin
  if (Target = nil) or (Source = nil) then
    raise EArgumentNilException.Create('Filter');
  if Target.Kind <> Source.Kind then
    raise EArgumentException.Create('Filter kinds do not match');
  Target.Enabled := Source.Enabled;
  case Target.Kind of
    slfkOutline:
    begin
      TMapRakuOutlineFilter(Target).Color :=
        TMapRakuOutlineFilter(Source).Color;
      TMapRakuOutlineFilter(Target).Width :=
        TMapRakuOutlineFilter(Source).Width;
    end;
    slfkShadow:
    begin
      TMapRakuShadowFilter(Target).BlurRadius :=
        TMapRakuShadowFilter(Source).BlurRadius;
      TMapRakuShadowFilter(Target).Color :=
        TMapRakuShadowFilter(Source).Color;
      TMapRakuShadowFilter(Target).OffsetX :=
        TMapRakuShadowFilter(Source).OffsetX;
      TMapRakuShadowFilter(Target).OffsetY :=
        TMapRakuShadowFilter(Source).OffsetY;
      TMapRakuShadowFilter(Target).Opacity :=
        TMapRakuShadowFilter(Source).Opacity;
    end;
    slfkBlur:
      TMapRakuBlurFilter(Target).Radius :=
        TMapRakuBlurFilter(Source).Radius;
  end;
end;

{ TMapRakuFilter }

constructor TMapRakuFilter.Create(AKind: TMapRakuFilterKind);
begin
  inherited Create;
  FKind := AKind;
  FEnabled := True;
end;

function TMapRakuFilter.DisplayName: string;
begin
  case FKind of
    slfkOutline:
      Result := '縁取り';
    slfkShadow:
      Result := '影';
    slfkBlur:
      Result := 'ぼかし';
  else
    raise EArgumentOutOfRangeException.Create('Unknown filter kind');
  end;
end;

{ TMapRakuOutlineFilter }

function TMapRakuOutlineFilter.Clone: TMapRakuFilter;
var
  CopyFilter: TMapRakuOutlineFilter;
begin
  CopyFilter := TMapRakuOutlineFilter.Create;
  CopyFilter.Enabled := Enabled;
  CopyFilter.Color := Color;
  CopyFilter.Width := Width;
  Result := CopyFilter;
end;

constructor TMapRakuOutlineFilter.Create;
begin
  inherited Create(slfkOutline);
  FColor := clBlack;
  FWidth := 4.0;
end;

{ TMapRakuShadowFilter }

function TMapRakuShadowFilter.Clone: TMapRakuFilter;
var
  CopyFilter: TMapRakuShadowFilter;
begin
  CopyFilter := TMapRakuShadowFilter.Create;
  CopyFilter.Enabled := Enabled;
  CopyFilter.BlurRadius := BlurRadius;
  CopyFilter.Color := Color;
  CopyFilter.OffsetX := OffsetX;
  CopyFilter.OffsetY := OffsetY;
  CopyFilter.Opacity := Opacity;
  Result := CopyFilter;
end;

constructor TMapRakuShadowFilter.Create;
begin
  inherited Create(slfkShadow);
  FBlurRadius := 6.0;
  FColor := clBlack;
  FOffsetX := 8.0;
  FOffsetY := 8.0;
  FOpacity := 0.75;
end;

{ TMapRakuBlurFilter }

function TMapRakuBlurFilter.Clone: TMapRakuFilter;
var
  CopyFilter: TMapRakuBlurFilter;
begin
  CopyFilter := TMapRakuBlurFilter.Create;
  CopyFilter.Enabled := Enabled;
  CopyFilter.Radius := Radius;
  Result := CopyFilter;
end;

constructor TMapRakuBlurFilter.Create;
begin
  inherited Create(slfkBlur);
  FRadius := 4.0;
end;

function CreateDefaultMapRakuFilter(
  Kind: TMapRakuFilterKind): TMapRakuFilter;
begin
  case Kind of
    slfkOutline:
      Result := TMapRakuOutlineFilter.Create;
    slfkShadow:
      Result := TMapRakuShadowFilter.Create;
    slfkBlur:
      Result := TMapRakuBlurFilter.Create;
  else
    raise EArgumentOutOfRangeException.Create('Unknown filter kind');
  end;
end;

end.
