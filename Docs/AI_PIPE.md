# AIとのパイプ連携

ちずらくを起動し、`\\.\pipe\MapRaku.v1` へUTF-8 JSONを1要求ずつ送る。1接続につき1要求・1応答のメッセージモード。応答の `protocol_version` は **2**。接続名と地図ファイルの形式バージョンは従来どおりで、画像を一時ファイル名で返す旧プロトコルとは互換でない。

AIとの指示・文書・元画像・描画結果の交換はすべてパイプを使う。画像をアプリ側の一時ファイルから直接読む必要はない。クライアントが受信した画像を表示用に保存すること、アプリが明示指示された地図ファイルを保存・読むことは、この交換とは別の処理。

## 生成の前提

プラグインでは編集画面ごとの `MapRaku.Plugin.<PID>.{GUID}` へ接続する。`Get-MapRakuEndpoints` で列挙し、画面下部と一致する名前を `Set-MapRakuEndpoint` へ渡す。応答には `pipe_name`、`host_kind`（`standalone`／`aviutl2`）、`process_id` が付く。プラグインの「適用／取消」までの扱いは [PLUGIN.md](PLUGIN.md) を参照。

画像応答の `snapshot.background_kind` は `reference`（AIの元画像）、`host`（ホスト映像）、`none`（補助画像なし）。ホスト映像は元画像条件として登録されず、`get_reference_image` の対象にもならない。`include_reference:false` は両方の補助画像を除いた完成図を返す。

- 作成前に範囲と方角を決める。入力PNGは回転・切出し済みとし、キャンバスと同じ縦横比にする。アプリは画像を自動回転しない。
- `north_clockwise_degrees` は画面の上を0度とする北方向の時計回り角度。AIはこれと元画像を基準に生成する。
- 道路・線路の形状、接続、交差を優先し、主要施設は簡単な建物・名称で表す。細部は人が調整する。
- 文書座標はキャンバス中央が原点、右が+X、下が+Y。幅W・高さHの元画像を幅CW・高さCHへ対応させると、`x = pixel_x * CW/W - CW/2`、`y = pixel_y * CH/H - CH/2`。縮小プレビューにも対応式を返す。
- 参照条件と元画像、転送データ、要求結果はアプリの起動中だけ保持する。`.mapraku`には含めない。アプリ再起動後は再登録する。条件を登録したままキャンバス寸法を変更する場合は、先に `clear_reference` する。

## 推奨する一往復

1. `get_capabilities`、`get_map_schema` で対応機能と地図部品の契約を取得する。
2. `get_document` と `get_reference` で状態トークンを取得する。
3. `apply_batch` の `canvas` 操作で用紙寸法を固定する。
4. 元画像を `begin_blob` → `write_blob` でアップロードし、`set_reference` で画像と条件を登録する。登録成功後はアップロード用blobを解放してよい。
5. 部品の `id` を決め、道路・線路等の `operations` を `preview_batch` へ送る。アプリは独立した文書で全操作を試し、候補文書を返す。
6. 候補文書を `render_preview` へ渡す。応答の画像blobを `read_blob` で受信し、元画像と比較する。
7. 確認済みの候補文書を `replace_document` へ渡して反映する。または同じ操作列を `apply_batch` へ送る。後者でIDを省略した部品には、プレビュー時とは別のIDが生成されるため、相互参照する部品にはIDを明示する。
8. 最新の文書を取得して部分修正し、再描画する。取得した全画像blobは使い終わったら `release_blob` する。

`preview_batch` はデータ検証、`render_preview` は画像化を担当する。`include_reference:false` を指定すると、参照画像を除いた完成図を確認できる。`base_image` は参照背景またはキャンバス背景、`overlay_image` は透明背景の地図、`composite_image` は両者の合成。

## 変更要求と再送

`apply_batch`、`replace_document`、`undo`、`redo`、`set_reference`、`clear_reference`、`load_file`、`save_copy` には以下を付ける。

```json
{
  "command": "apply_batch",
  "request_id": "クライアントが発行する一意なID",
  "state_token": "get_documentのsnapshot.state_token",
  "background_token": "get_referenceのresult.background_token",
  "apply": true,
  "operations": [
    {"op":"add","spec":{"kind":"road","id":"road-main","width":24,
      "vertices":[{"x":-300,"y":0},{"x":300,"y":0}]}},
    {"op":"add","spec":{"kind":"symbol","symbol":0,"label":"中央駅","x":0,"y":-80}}
  ]
}
```

`preview_batch` と `render_preview` にも両トークンが必要だが、`request_id` と `apply` は不要。`begin_blob` は一意な `request_id` が必要で、文書トークンと `apply` は不要。

要求結果は成功・失敗とも記録する。同じID・同じJSON文字列の再送は元の応答を返し、再実行しない。同じIDに異なる要求を割り当てるとエラー。タイムアウト時は `{"command":"get_request_result","lookup_id":"元のID"}` で照会する。既知なら `result.response` が元の結果。状態エラーを修正して新たに実行する場合は新しいIDを使う。記録は最大2048件・応答文字列合計約16MiBで、未確認結果を勝手に追い出さず、満杯なら新しい変更を拒否する。再起動をまたぐ再送保証はないため、再接続後は文書を読み直す。

文書や背景のトークンが変わった要求は反映しない。作図途中・文字編集中・ドラッグ中も変更を拒否する。全操作は一時文書で検証し、成功時だけ既存の履歴機構で1回のUndoとして反映する。失敗時は文書を変更しない。

## 部品と操作

`get_map_schema` に実装中のフィールド一覧・列挙値・使用例を返す。通常の `get_creation_schema` にも `map` として含める。色整数はDelphi TColorの `0x00BBGGRR`。

| 操作 | 内容 |
|---|---|
| `canvas` | `spec` で幅・高さ・背景・透過・種類別配色を設定 |
| `add` | `spec.kind` に従い最上位へ追加。道路、JR、私鉄、川、記号、建物、文字、矩形、楕円、高さ境界 |
| `update` | `id` の `changes` を適用。名称、不透明度、表示、dx/dy移動、経路の全頂点・幅・色、文字列 |
| `delete` | `id` を削除。子孫の経路に付いた交差指定も除去 |
| `connect` | `id` の `endpoint` を `target` の `target_endpoint` へ接続。端点は頂点の0始まり番号。`align` は接線調整の有無 |
| `crossing` | `a`・`b` の経路ID、`kind`、`upper`、`margin` で交差を指定 |
| `remove_crossing` | `a`・`b` の明示交差指定を解除 |

接続は既存の `ConnectEndpoint` を使う。同系列だけを対象とし、ロックされた相手は参照だけ。永続的な追従拘束は作らない。一括編集は対象または祖先がロック中なら拒否する。全文書の `replace_document` は上級用途の文書置換であり、個々のロックに基づく部分編集制限は行わない。

道路・川の色を省略すると現在の配置プリセットを使う。JR・私鉄の色はキャンバスの `jr_primary/jr_secondary/rail_primary/rail_secondary` へ設定し、経路への個別色指定は拒否する。道路・川のプリセット変更は次の配置に作用する。既存経路の色変更は各経路を明示更新する。

経路の制御点は頂点からの相対座標。`outgoingSegment` は `line` または `cubicBezier`。記号は手動配置と同じ `CreateMapSymbol` を使い、構成部品をAIに再実装させない。建物は矩形と名称の編集可能なグループ。建物・記号のx/yは中心、文字・通常図形は左上。施設をGoogle Maps等から自動検索する機能は含まない。

検証対象はIDの重複、経路の点数・座標・幅、交差の参照先、ロック、容量等。元画像との地理的な一致、交差が実際にあるか、誤読・描き落としがないかは、描画結果を見て確認する。JSONの妥当性と認識精度は別。

## 画像転送

`begin_blob` は `size` と `mime` から `result.blob_id` を返す。`write_blob` は `blob_id`、`offset`、`base64` を指定し、オフセット0から順に送る。同じチャンクの再送は許すが、受信済みバイトの変更は拒否する。未完了blobは読み出せない。

`read_blob` は `blob_id`、`offset`、`count` を指定する。応答の `size`、`received`、`sha256` と受信バイトを照合する。`release_blob` は何度呼んでもよい。プレビューは3枚の画像を返すので、使わなかった画像も解放する。

`set_reference` はPNGの `blob_id` と次の `conditions` を受け取る。

```json
{"north_clockwise_degrees":0,"image_already_oriented":true,"area":"中央駅周辺"}
```

`get_reference` は条件と最新の背景トークンを返す。`conditions_current` が偽なら条件を再登録する。`get_reference_image` は登録PNGそのものを画像blobとして返す。`clear_reference` は背景と条件を解除する。参照設定は作図補助情報なので文書のUndo対象に含めない。

制限：JSON要求・応答は4MiB、blobは1件16MiB、32件・合計64MiB、1チャンク192KiB。参照PNGは各辺4096px以下、プレビューは長辺64～2048px。大きな元画像は対象範囲を絞る。参照PNGの寸法は展開前に検査する。

## 保存と再読込

`save_copy` は絶対パスの `path` へ `.mapraku` をアプリ側で保存する。既存ファイルへの保存には `overwrite:true` を明示する。現在の保存先・保存済み表示は変更しない。

`preview_file` はパスから読み込んだ候補文書を返す。`load_file` はファイルの内容を1回のUndoで戻せる文書置換として読み込む。通常UIの「開く」と異なり、現在の保存先・履歴はリセットしない。外部画像が欠落していれば自動読込を拒否する。保存・読込はパイプの要求を受けたアプリが実行する。

## 接続用モジュールと検証

PowerShell 7から次のモジュールを使える。Codexはシェル経由でこのモジュールを呼び、返されたデータを解析する。別のAPIキーやアプリ内AI呼出しは必要ない。

```powershell
Import-Module ./Tools/Automation/MapRakuPipe.psm1
Invoke-MapRakuPipe @{command='get_map_schema'}
$request = New-MapRakuMutation 'apply_batch'
$request.operations = @(
  @{op='add';spec=@{kind='building';id='hall';name='市役所';x=100;y=100;width=120;height=70}}
)
Invoke-MapRakuPipe $request
```

`Send-MapRakuBlob` はバイト列をアップロードし、`Receive-MapRakuBlob` は受信・SHA-256照合・解放を行う。タイムアウト後は元の要求IDを照会し、新しいIDで同じ変更を即座に再実行しない。

`Tools/test-pipe.ps1` は、他のMapRakuが起動中ならテストを開始せず、専用に起動したアプリだけに接続する。既知の架空地図で全配置種類、5交差、端点接続、部分編集、削除、Undo／Redo、プレビュー、画像往復、保存・再読込、再送・異常系を検証する。アプリへの操作はすべてパイプ経由。成果物は `TestOutput/pipe-map-sample.mapraku`、同名PNG、`pipe-test-report.json`。これは配置と通信の検証であり、未提供の実地図画像に対するAI認識精度の実証ではない。

```powershell
./Tools/build.ps1 -Config Debug
./Tools/build.ps1 -Config Release
./Tools/test.ps1
./Tools/test-pipe.ps1 -Config Debug
./Tools/test-pipe.ps1 -Config Release
```
