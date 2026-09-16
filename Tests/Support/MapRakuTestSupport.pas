// 地図テスト共通の検査と標準経路データを提供する。
unit MapRakuTestSupport;
interface
uses System.Types, MapRakuDocument;
// 不成立時は例外を送出し、テスト実行を失敗させる。
procedure Check(Value: Boolean; const Message: string);
// 接続・描画比較の基準となる2頂点の経路を作る。
function Road(const Kind: string; A, B: TPointF): TVectArtPathData;
implementation
uses System.SysUtils, Vcl.Graphics;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); end;
function Road(const Kind: string; A, B: TPointF): TVectArtPathData;
begin
  Result := Default(TVectArtPathData);
  Result.MapElement := Kind; Result.Name := Kind; Result.Visible := True;
  Result.Opacity := 1; Result.StrokeWidth := 24; Result.StrokeColor := clWhite;
  Result.LineCap := vlcRound;
  SetLength(Result.Vertices, 2);
  Result.Vertices[0].Position := A; Result.Vertices[1].Position := B;
end;
end.
