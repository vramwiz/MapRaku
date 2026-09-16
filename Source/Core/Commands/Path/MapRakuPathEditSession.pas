// 複数経路に及ぶ1回の編集を、復元可能なプレビューと単一の履歴へまとめる。
unit MapRakuPathEditSession;
interface
uses MapRakuDocument, MapRakuEditCommands;
type
  TMapRakuPathVertexState = record
    Path: TVectArtPathLayer; // 非所有参照。経路の寿命は文書と編集履歴が管理する。
    Vertices: TArray<TMapRakuVertex>;
  end;
  // 端点接続など、複数経路へ及ぶ1操作の変更をまとめて復元・履歴化する。
  TMapRakuPathEditSession = class
  private
    FDocument: TVectArtDocument;
    FBefore: TArray<TMapRakuPathVertexState>;
  public
    constructor Create(Document: TVectArtDocument);
    // 初回だけ編集前頂点を記録する。相手経路も変更する前に登録する。
    procedure Track(Path: TVectArtPathLayer);
    // 仮編集を開始時へ戻す。通知と再描画は呼び出し元がまとめて行う。
    procedure Restore;
    // 変更がなければnil。返したコマンドの所有権は呼び出し元へ渡す。
    function CaptureCommand: TVectArtEditCommand;
  end;

implementation
uses MapRakuPathOperations;
type
  TMapRakuPathVerticesCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FBefore, FAfter: TArray<TMapRakuPathVertexState>;
  public
    procedure Execute; override;
    procedure Undo; override;
  end;

procedure TMapRakuPathVerticesCommand.Execute;
var S: TMapRakuPathVertexState;
begin
  for S in FAfter do S.Path.Vertices:=S.Vertices;
  FDocument.Changed;
end;

procedure TMapRakuPathVerticesCommand.Undo;
var S: TMapRakuPathVertexState;
begin
  for S in FBefore do S.Path.Vertices:=S.Vertices;
  FDocument.Changed;
end;

constructor TMapRakuPathEditSession.Create(Document: TVectArtDocument);
begin inherited Create; FDocument:=Document; end;

procedure TMapRakuPathEditSession.Track(Path: TVectArtPathLayer);
var S: TMapRakuPathVertexState;
begin
  if Path=nil then Exit;
  for S in FBefore do if S.Path=Path then Exit;
  S.Path:=Path; S.Vertices:=Path.Vertices; FBefore:=FBefore+[S];
end;

procedure TMapRakuPathEditSession.Restore;
var S: TMapRakuPathVertexState;
begin for S in FBefore do S.Path.Vertices:=S.Vertices; end;

function TMapRakuPathEditSession.CaptureCommand: TVectArtEditCommand;
var S,A: TMapRakuPathVertexState; C: TMapRakuPathVerticesCommand;
begin
  C:=TMapRakuPathVerticesCommand.Create; C.FDocument:=FDocument;
  for S in FBefore do
    if not MapRakuPathVerticesEqual(S.Vertices,S.Path.Vertices) then begin
      C.FBefore:=C.FBefore+[S]; A.Path:=S.Path; A.Vertices:=S.Path.Vertices;
      C.FAfter:=C.FAfter+[A];
    end;
  if Length(C.FBefore)=0 then begin C.Free; Exit(nil); end;
  Result:=C;
end;

end.
