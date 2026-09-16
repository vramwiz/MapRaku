// KeyDown／KeyPressと実行条件を対応付ける、フォーム共通のショートカット表を提供する。
unit ShortcutAction;

interface

uses
  System.Classes, System.SysUtils, Vcl.Controls;

type
  TShortcutEventKind = (sekKeyDown, sekKeyPress);
  TShortcutActionCanExecuteEvent = function: Boolean of object;
  TShortcutItemCanExecute = reference to function: Boolean;

  TShortcutActionItem = record
    Kind: TShortcutEventKind;
    KeyW: Word;
    KeyC: Char;
    Shift: TShiftState;
    Proc: TProc;
    CanExecute: TShortcutItemCanExecute;
  end;
  PShortcutActionItem = ^TShortcutActionItem;

  TShortcutAction = class
  private
    FList: TList;
    FEnabled: Boolean;
    FOnCanExecute: TShortcutActionCanExecuteEvent;
    function CanExecute: Boolean;
    procedure CheckDuplicate(Kind: TShortcutEventKind; KeyW: Word;
      KeyC: Char; Shift: TShiftState);
    function GetCount: Integer;
    function GetItem(Index: Integer): TShortcutActionItem;
  public
    constructor Create;
    destructor Destroy; override;
    // 修飾キーを含むKeyDown操作を登録する。同じ組み合わせの重複登録は例外にする。
    procedure Add(Key: Word; Shift: TShiftState; AProc: TProc); overload;
    procedure Add(Key: Word; Shift: TShiftState; AProc: TProc;
      ACanExecute: TShortcutItemCanExecute); overload;
    // 文字入力として受け取るKeyPress操作を登録する。
    procedure Add(Key: Char; AProc: TProc); overload;
    procedure Add(Key: Char; AProc: TProc;
      ACanExecute: TShortcutItemCanExecute); overload;
    // 登録済みの操作と保持している匿名メソッドをすべて解放する。
    procedure Clear;
    // 一致するKeyDown操作を実行し、処理したキーを0へ変更する。
    function KeyDown(var Key: Word; Shift: TShiftState): Boolean;
    // 一致するKeyPress操作を実行し、処理した文字を#0へ変更する。
    function ProcessKeyPress(var Key: Char): Boolean;
    property Enabled: Boolean read FEnabled write FEnabled;
    property OnCanExecute: TShortcutActionCanExecuteEvent read FOnCanExecute
      write FOnCanExecute;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TShortcutActionItem read GetItem; default;
  end;

implementation

const
  KEYBOARD_SHIFT_STATES = [ssShift, ssAlt, ssCtrl];

function NormalizedShift(const Shift: TShiftState): TShiftState;
begin
  Result := Shift * KEYBOARD_SHIFT_STATES;
end;

constructor TShortcutAction.Create;
begin
  inherited Create;
  FList := TList.Create;
  FEnabled := True;
end;

destructor TShortcutAction.Destroy;
begin
  Clear;
  FList.Free;
  inherited Destroy;
end;

procedure TShortcutAction.Add(Key: Word; Shift: TShiftState; AProc: TProc);
begin
  Add(Key, Shift, AProc, nil);
end;

procedure TShortcutAction.Add(Key: Word; Shift: TShiftState; AProc: TProc;
  ACanExecute: TShortcutItemCanExecute);
var
  Item: PShortcutActionItem;
begin
  Shift := NormalizedShift(Shift);
  CheckDuplicate(sekKeyDown, Key, #0, Shift);
  New(Item);
  Item^.Kind := sekKeyDown;
  Item^.KeyW := Key;
  Item^.KeyC := #0;
  Item^.Shift := Shift;
  Item^.Proc := AProc;
  Item^.CanExecute := ACanExecute;
  FList.Add(Item);
end;

procedure TShortcutAction.Add(Key: Char; AProc: TProc);
begin
  Add(Key, AProc, nil);
end;

procedure TShortcutAction.Add(Key: Char; AProc: TProc;
  ACanExecute: TShortcutItemCanExecute);
var
  Item: PShortcutActionItem;
begin
  CheckDuplicate(sekKeyPress, 0, Key, []);
  New(Item);
  Item^.Kind := sekKeyPress;
  Item^.KeyW := 0;
  Item^.KeyC := Key;
  Item^.Shift := [];
  Item^.Proc := AProc;
  Item^.CanExecute := ACanExecute;
  FList.Add(Item);
end;

function TShortcutAction.CanExecute: Boolean;
begin
  Result := FEnabled;
  if Result and Assigned(FOnCanExecute) then
    Result := FOnCanExecute();
end;

procedure TShortcutAction.CheckDuplicate(Kind: TShortcutEventKind;
  KeyW: Word; KeyC: Char; Shift: TShiftState);
var
  I: Integer;
  Item: PShortcutActionItem;
begin
  for I := 0 to FList.Count - 1 do
  begin
    Item := PShortcutActionItem(FList[I]);
    if (Item^.Kind = Kind) and
      (((Kind = sekKeyDown) and (Item^.KeyW = KeyW) and
        (Item^.Shift = Shift)) or
       ((Kind = sekKeyPress) and (Item^.KeyC = KeyC))) then
      raise EArgumentException.Create('Shortcut is already registered');
  end;
end;

procedure TShortcutAction.Clear;
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
    Dispose(PShortcutActionItem(FList[I]));
  FList.Clear;
end;

function TShortcutAction.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TShortcutAction.GetItem(Index: Integer): TShortcutActionItem;
begin
  Result := PShortcutActionItem(FList[Index])^;
end;

function TShortcutAction.KeyDown(var Key: Word;
  Shift: TShiftState): Boolean;
var
  I: Integer;
  Item: PShortcutActionItem;
begin
  Result := False;
  if not CanExecute then
    Exit;
  Shift := NormalizedShift(Shift);
  for I := 0 to FList.Count - 1 do
  begin
    Item := PShortcutActionItem(FList[I]);
    if (Item^.Kind = sekKeyDown) and (Item^.KeyW = Key) and
      (Item^.Shift = Shift) then
    begin
      if Assigned(Item^.CanExecute) and not Item^.CanExecute() then
        Exit;
      if Assigned(Item^.Proc) then
        Item^.Proc();
      Key := 0;
      Exit(True);
    end;
  end;
end;

function TShortcutAction.ProcessKeyPress(var Key: Char): Boolean;
var
  I: Integer;
  Item: PShortcutActionItem;
begin
  Result := False;
  if not CanExecute then
    Exit;
  for I := 0 to FList.Count - 1 do
  begin
    Item := PShortcutActionItem(FList[I]);
    if (Item^.Kind = sekKeyPress) and (Item^.KeyC = Key) then
    begin
      if Assigned(Item^.CanExecute) and not Item^.CanExecute() then
        Exit;
      if Assigned(Item^.Proc) then
        Item^.Proc();
      Key := #0;
      Exit(True);
    end;
  end;
end;

end.
