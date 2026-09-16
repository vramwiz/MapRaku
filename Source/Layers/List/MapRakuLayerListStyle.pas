// レイヤー一覧の配色と96 DPI基準の寸法を、描画と当たり判定で共有する。
unit MapRakuLayerListStyle;

interface

uses Vcl.Graphics;

const
  COLOR_LIST_BACKGROUND        = TColor($001A1A1A); // 行間と一覧外周の背景。
  COLOR_ROW_BACKGROUND         = TColor($00272727); // 未選択行の背景。
  COLOR_ROW_BORDER             = TColor($00424242); // 未選択行の外枠。
  COLOR_ROW_SELECTED           = TColor($005C4729); // 複数選択の行は青みのある背景で区別する。
  COLOR_ROW_ACTIVE_BACKGROUND  = TColor($00865E24); // アクティブ行は背景全体を明るい青へ変える。
  COLOR_ROW_ACTIVE             = TColor($00F0B963); // 減算の左辺にもなるアクティブ行の識別色。
  COLOR_TEXT_PRIMARY           = TColor($00E6E6E6); // 有効な状態アイコンの前景色。
  COLOR_TEXT_SECONDARY         = TColor($00A8A8A8); // 状態アイコンの輪郭色。
  COLOR_THUMB_BORDER           = TColor($00606060); // サムネイルの境界色。
  LAYER_GAP                    = 6;               // 行どうしの間隔。
  LAYER_LIST_PADDING           = 8;               // 一覧の外周余白。
  LAYER_ROW_HEIGHT             = 82;              // 1行の高さ。
  LOCK_BUTTON_TOP              = 45;              // 行上端からロックボタンまでの距離。
  STATE_BUTTON_SIZE            = 20;              // 状態ボタンの当たり判定サイズ。
  STATE_COLUMN_LEFT            = 4;               // 行左端から状態列までの距離。
  THUMBNAIL_CHECKER_SIZE       = 6;               // 透明背景の市松1マスの寸法。
  THUMBNAIL_HEIGHT             = 54;              // サムネイル表示領域の高さ。
  THUMBNAIL_WIDTH              = 96;              // サムネイル表示領域の最大幅。
  VISIBILITY_BUTTON_TOP        = 17;              // 行上端から表示ボタンまでの距離。


implementation

end.
