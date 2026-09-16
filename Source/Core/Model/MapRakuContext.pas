// デザイナーFrame群がホストアプリケーションから受け取る共通サービス境界を提供する。
// Contextは各サービスを所有せず、ホスト側がFrameより長いライフサイクルを保証する。
unit MapRakuContext;

interface

uses
  MapRakuDocument, MapRakuEditHistory,
  MapRakuEditorState;

type
  // デザイナーFrameを別アプリケーションへ組み込む際の単一の接続口を表す。
  IVectArtDesignerContext = interface
    ['{4697CD46-87BB-44B1-94B6-C6444D6D11C0}']
    function GetDocument: TVectArtDocument;
    function GetEditHistory: TVectArtEditHistory;
    function GetEditorState: TVectArtEditorState;
    property Document: TVectArtDocument read GetDocument;
    property EditHistory: TVectArtEditHistory read GetEditHistory;
    property EditorState: TVectArtEditorState read GetEditorState;
  end;

  // 既存のDocument、履歴、編集状態をContextとして公開する標準アダプター。
  TVectArtDesignerContext = class(TInterfacedObject, IVectArtDesignerContext)
  private
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
  protected
    function GetDocument: TVectArtDocument;
    function GetEditHistory: TVectArtEditHistory;
    function GetEditorState: TVectArtEditorState;
  public
    // 渡されたサービスへの非所有参照を保持する。呼び出し側が各インスタンスを所有する。
    constructor Create(ADocument: TVectArtDocument;
      AEditHistory: TVectArtEditHistory; AEditorState: TVectArtEditorState);
  end;

implementation

constructor TVectArtDesignerContext.Create(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory; AEditorState: TVectArtEditorState);
begin
  inherited Create;
  FDocument := ADocument;
  FEditHistory := AEditHistory;
  FEditorState := AEditorState;
end;

function TVectArtDesignerContext.GetDocument: TVectArtDocument;
begin
  Result := FDocument;
end;

function TVectArtDesignerContext.GetEditHistory: TVectArtEditHistory;
begin
  Result := FEditHistory;
end;

function TVectArtDesignerContext.GetEditorState: TVectArtEditorState;
begin
  Result := FEditorState;
end;

end.
