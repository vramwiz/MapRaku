# 東京駅丸の内口の画像から作った地図

アプリ内の実Codexがネイティブ画像生成で作った案内図を、画像読取で編集可能な地図へ変換したサンプル。AI生成の元画像なので地理的な精度・縮尺は別途確認する。

| ファイル | 内容 |
|---|---|
| [source-map.png](source-map.png) | 実際の画像生成機能で作った元地図、1920×1080 |
| [editable-map.png](editable-map.png) | 元画像の全範囲から作った56レイヤーのプレビュー |
| [tokyo-marunouchi.mapraku](tokyo-marunouchi.mapraku) | 元の範囲を読み取った編集可能な地図 |
| [simplified-reference.png](simplified-reference.png) | 倍率115%、移動(0.02,−0.01)、回転−17度で切り出した読取対象 |
| [simplified-map.png](simplified-map.png) | 上記の範囲を簡略化80で読み取った29レイヤーのプレビュー |
| [tokyo-marunouchi-simplified.mapraku](tokyo-marunouchi-simplified.mapraku) | 簡略化後の編集可能な地図 |
| [reference-viewport.png](reference-viewport.png) | トンボ・範囲外の暗い表示・近くの回転アイコン。実コントロールの描画を非表示で出力した画像 |

画像生成と読取はモデルによる実処理。固定応答の通信試験とは別に行った。最初の56レイヤーは旧UIのOKで採用した。簡略化後の29レイヤーは試験専用の共通プラグイン編集画面からNamed Pipeで採用・保存し、Undo／Redoで元の空文書と生成結果を復元できた。どちらも配置操作列の手修正は行っていない。

画像の受渡しはPNG blob、読取への添付はlocalImage。元画像と読取対象PNGのSHA-256、簡略化を含む条件トークンを検証している。簡略化は形状整理の目安で、すべての線を厳密に水平垂直へ強制するものではない。

`image-stage.json`、`trace-stage.json`、`simplified-stage.json` は受信した条件・結果・地図データ。`validation.json`、`simplified-validation.json` は実生成、採用前の文書保持、画像の一致、採用・保存・Undo／Redoの検証記録。新しい2ページ画面での実マウス操作はEscで停止したため、`reference-viewport.png` は実操作が成功した証拠には使用しない。
