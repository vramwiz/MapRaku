// 画像を不変の文字列として共有し、履歴や複製から独立したテクスチャ配置を保持する。
unit MapRakuTextureStyle;

interface

type
  TMapRakuTextureFit = (sltfCover, sltfContain, sltfStretch, sltfOriginal);
  TMapRakuTextureRepeat = (sltrNone, sltrRepeat, sltrMirror);
  TMapRakuTextureStyle = record
    Data: string;                       // 元画像のBase64。空なら未設定。コピー時は文字列を共有する。
    FileName: string;                   // 表示用の元ファイル名。読み込みに外部パスは使用しない。
    Fit: TMapRakuTextureFit;       // オブジェクト範囲への初期配置方法。
    RepeatMode: TMapRakuTextureRepeat; // 画像の外側を透明、反復、鏡像反復にする。
    Scale: Single;                      // 初期配置に対する倍率。1が等倍。
    OffsetX: Single;                    // オブジェクト幅に対する中心からの移動量。
    OffsetY: Single;                    // オブジェクト高さに対する中心からの移動量。
    Angle: Single;                      // オブジェクトに対する画像回転角（度）。
    FlipHorizontal: Boolean;            // オブジェクトのローカル左右反転を画像配置にも適用する。
    FlipVertical: Boolean;              // オブジェクトのローカル上下反転を画像配置にも適用する。
    // 未設定画像と中央配置を準備する。
    class function DefaultStyle: TMapRakuTextureStyle; static;
    // 埋め込み画像と配置がすべて等しいかを返す。
    function SameAs(const Other: TMapRakuTextureStyle): Boolean;
  end;

implementation

class function TMapRakuTextureStyle.DefaultStyle: TMapRakuTextureStyle;
begin
  Result := Default(TMapRakuTextureStyle);
  Result.Scale := 1;
end;

function TMapRakuTextureStyle.SameAs(const Other: TMapRakuTextureStyle): Boolean;
begin
  Result := (Data = Other.Data) and (FileName = Other.FileName) and (Fit = Other.Fit) and
    (RepeatMode = Other.RepeatMode) and (Scale = Other.Scale) and (OffsetX = Other.OffsetX) and
    (OffsetY = Other.OffsetY) and (Angle = Other.Angle) and
    (FlipHorizontal = Other.FlipHorizontal) and
    (FlipVertical = Other.FlipVertical);
end;

end.
