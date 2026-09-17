// 最近使った地図ファイルを重複なく新しい順に保持し、設定ファイルへ保存する。
unit MapRakuRecentFiles;

interface

uses System.Classes;

type
  TMapRakuRecentFiles = class
  private
    FItems: TStringList;
    function GetCount: Integer;
    function GetItem(Index: Integer): string;
  public
    const MaxCount = 10;
    constructor Create;
    destructor Destroy; override;
    procedure Load(const IniFileName: string);
    procedure Save(const IniFileName: string);
    procedure Touch(const FileName: string);
    property Count: Integer read GetCount;
    property Items[Index: Integer]: string read GetItem; default;
  end;

implementation

uses System.SysUtils, System.IniFiles;

constructor TMapRakuRecentFiles.Create;
begin
  inherited;
  FItems := TStringList.Create;
end;

destructor TMapRakuRecentFiles.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TMapRakuRecentFiles.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TMapRakuRecentFiles.GetItem(Index: Integer): string;
begin
  Result := FItems[Index];
end;

procedure TMapRakuRecentFiles.Touch(const FileName: string);
var
  I: Integer;
  Normalized: string;
begin
  if FileName = '' then Exit;
  Normalized := ExpandFileName(FileName);
  for I := FItems.Count - 1 downto 0 do
    if SameText(FItems[I], Normalized) then FItems.Delete(I);
  FItems.Insert(0, Normalized);
  while FItems.Count > MaxCount do FItems.Delete(FItems.Count - 1);
end;

procedure TMapRakuRecentFiles.Load(const IniFileName: string);
var
  Ini: TMemIniFile;
  I: Integer;
  FileName: string;
begin
  FItems.Clear;
  if (IniFileName = '') or not FileExists(IniFileName) then Exit;
  Ini := TMemIniFile.Create(IniFileName, TEncoding.UTF8);
  try
    // Touchは先頭へ入れるため、逆順に読めば保存時の並びを保てる。
    for I := MaxCount - 1 downto 0 do
    begin
      FileName := Ini.ReadString('RecentFiles', 'File' + IntToStr(I), '');
      if FileName <> '' then Touch(FileName);
    end;
  finally Ini.Free; end;
end;

procedure TMapRakuRecentFiles.Save(const IniFileName: string);
var
  Ini: TMemIniFile;
  I: Integer;
begin
  if IniFileName = '' then Exit;
  Ini := TMemIniFile.Create(IniFileName, TEncoding.UTF8);
  try
    Ini.EraseSection('RecentFiles');
    for I := 0 to FItems.Count - 1 do
      Ini.WriteString('RecentFiles', 'File' + IntToStr(I), FItems[I]);
    Ini.UpdateFile;
  finally Ini.Free; end;
end;

end.
