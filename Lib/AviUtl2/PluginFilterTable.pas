// Syncroh2のPluginFilterTableを共通Lib向けに移植したGUI項目登録ヘルパー。
unit PluginFilterTable;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.UITypes,
  AviUtl2FilterTypes;

procedure SetupPluginTable(Flag: Integer; Name, Label_, Information: PWideChar;
  VideoProc: TFuncProcVideo; AudioProc: TFuncProcAudio);

procedure AddFile(var Item: TFILTER_ITEM_FILE; Name, Value,
  FileFilter: PWideChar);
procedure AddButton(var Item: TFILTER_ITEM_BUTTON; Name: PWideChar;
  Callback: TFILTER_ITEM_BUTTON_CALLBACK);
procedure AddString(var Item: TFILTER_ITEM_STRING; Name, Value: PWideChar);
procedure AddColor(var Item: TFILTER_ITEM_COLOR; Name: PWideChar;
  Color: TColor; Alpha: Byte = 255);
procedure AddTrack(var Item: TFILTER_ITEM_TRACK; Name: PWideChar;
  Value, S, E, Step: Double);
procedure AddCheck(var Item: TFILTER_ITEM_CHECK; Name: PWideChar;
  Value: Integer);
procedure AddText(var Item: TFILTER_ITEM_TEXT; Name: PWideChar;
  const Value: WideString);
procedure AddData(var Item: TFILTER_ITEM_DATA; Name: PWideChar;
  Buffer: PWideChar; Size: Integer);
procedure AddSelect(var Item: TFILTER_ITEM_SELECT; Name: LPCWSTR;
  Value: Integer; List: Pointer);
procedure AddGroup(var Item: TFILTER_ITEM_GROUP; Name: PWideChar;
  DefaultVisible: Integer);

procedure ClearSelectList;
procedure AddSelectList(var List: array of TFILTER_ITEM_SELECT_ITEM;
  Name: PWideChar; Value: Integer);

procedure GetData(const Item: TFILTER_ITEM_DATA; out Buffer: PWideChar;
  out Size: Integer);
procedure SetData(var Item: TFILTER_ITEM_DATA; Buffer: PWideChar;
  Size: Integer);

function GetColor(const Item: TFILTER_ITEM_COLOR): TColor;
procedure SetColor(var Item: TFILTER_ITEM_COLOR; Color: TColor;
  Alpha: PByte = nil);

var
  GTable: TFILTER_PLUGIN_TABLE;

implementation

const
  MAX_GUI_ITEMS = 100;

type
  TGuiItemIndex = 0..(MAX_GUI_ITEMS - 1);

var
  FItemIndex: Integer;
  Items: array[TGuiItemIndex] of Pointer;
  FSelectIndex: Integer;

function ColorToRGBValue(Color: TColor): Cardinal;
begin
  if Color < 0 then
    Result := GetSysColor(Color and $FF)
  else
    Result := Cardinal(Color);
end;

procedure RegisterItem(Item: Pointer);
begin
  if FItemIndex >= High(Items) then
    raise ERangeError.Create('AviUtl2 GUI item capacity exceeded');

  Items[FItemIndex] := Item;
  Inc(FItemIndex);
  Items[FItemIndex] := nil;
end;

procedure SetupPluginTable(Flag: Integer; Name, Label_, Information: PWideChar;
  VideoProc: TFuncProcVideo; AudioProc: TFuncProcAudio);
begin
  GTable.Flag := Flag;
  GTable.Name := Name;
  GTable.Label_ := Label_;
  GTable.Information := Information;
  GTable.Items := @Items[0];
  GTable.Func_Proc_Video := VideoProc;
  GTable.Func_Proc_Audio := AudioProc;
end;

procedure AddFile(var Item: TFILTER_ITEM_FILE; Name, Value,
  FileFilter: PWideChar);
begin
  Item.ItemType := 'file';
  Item.Name := Name;
  Item.Value := Value;
  Item.FileFilter := FileFilter;
  RegisterItem(@Item);
end;

procedure AddButton(var Item: TFILTER_ITEM_BUTTON; Name: PWideChar;
  Callback: TFILTER_ITEM_BUTTON_CALLBACK);
begin
  Item.ItemType := 'button';
  Item.Name := Name;
  Item.Callback := Callback;
  RegisterItem(@Item);
end;

procedure AddString(var Item: TFILTER_ITEM_STRING; Name, Value: PWideChar);
begin
  Item.ItemType := 'string';
  Item.Name := Name;
  Item.Value := Value;
  RegisterItem(@Item);
end;

procedure AddColor(var Item: TFILTER_ITEM_COLOR; Name: PWideChar;
  Color: TColor; Alpha: Byte);
var
  RGBColor: TColor;
begin
  Item.ItemType := 'color';
  Item.Name := Name;
  RGBColor := TColor(ColorToRGBValue(Color));
  Item.R := GetRValue(RGBColor);
  Item.G := GetGValue(RGBColor);
  Item.B := GetBValue(RGBColor);
  Item.X := Alpha;
  RegisterItem(@Item);
end;

procedure AddTrack(var Item: TFILTER_ITEM_TRACK; Name: PWideChar;
  Value, S, E, Step: Double);
begin
  Item.ItemType := 'track';
  Item.Name := Name;
  Item.Value := Value;
  Item.S := S;
  Item.E := E;
  Item.Step := Step;
  RegisterItem(@Item);
end;

procedure AddCheck(var Item: TFILTER_ITEM_CHECK; Name: PWideChar;
  Value: Integer);
begin
  Item.ItemType := 'check';
  Item.Name := Name;
  Item.Value := Byte(Value <> 0);
  RegisterItem(@Item);
end;

procedure AddText(var Item: TFILTER_ITEM_TEXT; Name: PWideChar;
  const Value: WideString);
begin
  Item.ItemType := 'text';
  Item.Name := Name;
  Item.Value := PWideChar(Value);
  RegisterItem(@Item);
end;

procedure AddData(var Item: TFILTER_ITEM_DATA; Name: PWideChar;
  Buffer: PWideChar; Size: Integer);
begin
  Item.ItemType := 'data';
  Item.Name := Name;
  Item.Value := Buffer;
  Item.Size := Size;
  Item.DefaultValue := Item.Value;
  RegisterItem(@Item);
end;

procedure AddSelect(var Item: TFILTER_ITEM_SELECT; Name: LPCWSTR;
  Value: Integer; List: Pointer);
begin
  Item.ItemType := 'select';
  Item.Name := Name;
  Item.Value := Value;
  Item.List := List;
  RegisterItem(@Item);
  ClearSelectList;
end;

procedure ClearSelectList;
begin
  FSelectIndex := 0;
end;

procedure AddSelectList(var List: array of TFILTER_ITEM_SELECT_ITEM;
  Name: PWideChar; Value: Integer);
begin
  if FSelectIndex >= High(List) then
    Exit;

  List[FSelectIndex].Name := Name;
  List[FSelectIndex].Value := Value;
  Inc(FSelectIndex);
  List[FSelectIndex].Name := nil;
  List[FSelectIndex].Value := 0;
end;

procedure AddGroup(var Item: TFILTER_ITEM_GROUP; Name: PWideChar;
  DefaultVisible: Integer);
begin
  Item.ItemType := 'group';
  Item.Name := Name;
  Item.DefaultVisible := Byte(DefaultVisible <> 0);
  RegisterItem(@Item);
end;

procedure GetData(const Item: TFILTER_ITEM_DATA; out Buffer: PWideChar;
  out Size: Integer);
begin
  Buffer := Item.Value;
  Size := Item.Size;
end;

procedure SetData(var Item: TFILTER_ITEM_DATA; Buffer: PWideChar;
  Size: Integer);
begin
  Item.Value := Buffer;
  Item.Size := Size;
  Item.DefaultValue := Buffer;
end;

function GetColor(const Item: TFILTER_ITEM_COLOR): TColor;
begin
  Result := TColor(RGB(Item.R, Item.G, Item.B));
end;

procedure SetColor(var Item: TFILTER_ITEM_COLOR; Color: TColor;
  Alpha: PByte);
var
  RGBColor: TColor;
begin
  RGBColor := TColor(ColorToRGBValue(Color));
  Item.R := GetRValue(RGBColor);
  Item.G := GetGValue(RGBColor);
  Item.B := GetBValue(RGBColor);
  if Alpha <> nil then
    Item.X := Alpha^;
end;

end.
