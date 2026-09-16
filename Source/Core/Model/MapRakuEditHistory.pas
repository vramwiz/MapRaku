// 適用済み編集コマンドのUndo／Redo位置と破棄を管理する。
unit MapRakuEditHistory;

interface

uses
  System.Classes, System.Generics.Collections,
  MapRakuEditCommands;

type
  TVectArtEditHistory = class
  private
    FCommands: TObjectList<TVectArtEditCommand>;
    FOnChanged: TNotifyEvent;
    FPosition: Integer;
    function GetCanRedo: Boolean;
    function GetCanUndo: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddApplied(Command: TVectArtEditCommand);
    procedure Clear;
    procedure Redo;
    procedure Undo;
    property CanRedo: Boolean read GetCanRedo;
    property CanUndo: Boolean read GetCanUndo;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

procedure TVectArtEditHistory.AddApplied(Command: TVectArtEditCommand);
begin
  if Command = nil then
    Exit;
  while FCommands.Count > FPosition do
    FCommands.Delete(FCommands.Count - 1);
  FCommands.Add(Command);
  FPosition := FCommands.Count;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditHistory.Clear;
begin
  FCommands.Clear;
  FPosition := 0;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

constructor TVectArtEditHistory.Create;
begin
  inherited Create;
  FCommands := TObjectList<TVectArtEditCommand>.Create(True);
end;

destructor TVectArtEditHistory.Destroy;
begin
  FCommands.Free;
  inherited Destroy;
end;

function TVectArtEditHistory.GetCanRedo: Boolean;
begin
  Result := FPosition < FCommands.Count;
end;

function TVectArtEditHistory.GetCanUndo: Boolean;
begin
  Result := FPosition > 0;
end;

procedure TVectArtEditHistory.Redo;
begin
  if not CanRedo then
    Exit;
  FCommands[FPosition].Execute;
  Inc(FPosition);
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditHistory.Undo;
begin
  if not CanUndo then
    Exit;
  Dec(FPosition);
  FCommands[FPosition].Undo;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

end.
