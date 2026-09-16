// テキスト描画バックエンドが実装する共通インターフェースを定義する。
unit TextRenderer;

interface

uses
  TextRendererTypes;

type
  TCustomTextRenderer = class abstract
  public
    // 診断や表示に使うバックエンド名を返す。
    function BackendName: string; virtual; abstract;
    // 描画要求をラスター画像へ変換し、処理時間と描画量を返す。
    function Render(const ARequest: TTextRenderRequest;
      out AMetrics: TTextRenderMetrics): TTextRenderImage; virtual; abstract;
  end;

implementation

end.
