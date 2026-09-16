// 外部自動化が適用するDocument全体の差し替えを、1件のUndo／Redoとして保持する。
unit MapRakuAutomationDocumentCommand;

interface

uses
  MapRakuDocument, MapRakuEditCommands;

type
  TMapRakuAutomationDocumentCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument; // MainFormが所有し、履歴より長く生存する。
    FNewJson: string;            // 検証済みの適用後スナップショット。
    FOldJson: string;            // 適用直前の復元用スナップショット。
    procedure Apply(const JsonText: string);
  public
    constructor Create(ADocument: TVectArtDocument; const OldJson,
      NewJson: string);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  System.SysUtils, MapRakuDocumentJson;

constructor TMapRakuAutomationDocumentCommand.Create(
  ADocument: TVectArtDocument; const OldJson, NewJson: string);
begin
  inherited Create;
  FDocument := ADocument;
  FOldJson := OldJson;
  FNewJson := NewJson;
end;

procedure TMapRakuAutomationDocumentCommand.Apply(const JsonText: string);
var
  ErrorMessage: string;
begin
  if not TryDeserializeVectArtDocument(JsonText, FDocument, ErrorMessage) then
    raise EInvalidOp.Create('Automation document restore failed: ' +
      ErrorMessage);
end;

procedure TMapRakuAutomationDocumentCommand.Execute;
begin
  Apply(FNewJson);
end;

procedure TMapRakuAutomationDocumentCommand.Undo;
begin
  Apply(FOldJson);
end;

end.
