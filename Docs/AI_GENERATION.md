# 地名から地図を作成

単独アプリとAviUtl2プラグインの共通編集画面で「編集」→「地名から地図を作成...」を開く。画像作成と地図データ作成を2ページに分け、Codex通信、画像の変換、候補の検証、プレビュー、採用とUndo／Redoを共用する。

## 使い方

1. 「編集」メニューの「地名から地図を作成...」を開く。
2. 画像作成ページで場所名、範囲の横幅（100～20000m）、北の向き、追加の指示を入力し、「画像を作成」を押す。北は0度が上、90度が右。画像の縦横比は開始時の用紙に合わせる。
3. 元地図画像を確認し、よければ「地図データ作成へ →」で次のページへ進む。画像ができただけではデータ化を開始しない。
4. 地図データ作成ページで参照範囲・向き・簡略化を調整する。明るいトンボ内がデータ化の範囲。外側は暗く表示するが、位置合わせのために元画像を表示し続ける。
5. ホイールで拡大縮小、枠内の左ドラッグで移動する。右上のトンボのすぐ近くにある回転アイコンを左右へドラッグして回転する。Shiftを押しながら回転すると15度刻み。「範囲・向きを戻す」は簡略化を保ったまま倍率・移動・回転を初期化する。
6. 専用の「簡略化（あいまいさ）」スライダーを調整し、「作成開始」を押す。参照範囲だけをPNGに切り出してCodexへ送り、道路・線路・建物・文字などの編集可能な部品にする。表示用の暗いフィルター、トンボ、回転アイコンは送信画像に入らない。
7. 完成すると参照画像の下に「作成結果のプレビュー」を表示する。上下を同時に比較でき、境界のドラッグで表示の高さを調整できる。問題がなければ「採用」。現在の地図を置き換え、1回のUndoで反映前へ戻せる。保存は通常のファイル操作で行う。プラグインは編集画面を閉じるとホストへ確定する。

「← 画像作成へ戻る」で前のページに戻れる。ページ移動では元画像や調整条件を失わず、Codexも呼ばない。場所や画像への指示を変えた場合は「画像を作成」で新しい画像を作ってから次へ進む。範囲・向き・簡略化を変えると以前の地図候補は無効になり、下段プレビューを隠す。作成し直すまで採用できない。

| 簡略化 | Codexへ渡す目安 |
|---|---|
| 0 | 元の形状を優先する |
| 1～34 | 小さな凹凸や細部を整理する |
| 35～69 | 道の曲がりと建物の輪郭を整理する |
| 70～100 | 道を原則水平・垂直や直角の折れ線へ、建物を矩形や少ない頂点へ整理する。細街路や施設の細部、必要に応じて並行線路を省略・集約する |

値は形状整理の指示の強さであり、幾何形状を強制する後処理ではない。主要道路の接続・分岐・交差、施設が道のどちら側にあるかを保持するよう指示する。プレビューを確認して必要な箇所は通常の編集で調整する。

生成・プレビューの段階では編集文書を変更しない。生成開始後に元の文書や背景が変わると採用を拒否する。背景として元地図画像を登録している場合は、それを解除してから開始する。プラグインのホスト映像は利用できる。この画面を閉じても生成は継続し、開き直すと状態を表示する。編集画面そのものを終了すると所有する生成処理も終了する。

## Codexとの通信と画像の固定

RIGMMakerの `Source/Integrations/RigmCodexClient.pas` を参照し、専用の `codex app-server --listen stdio://` を非表示で起動する。匿名パイプの改行区切りUTF-8 JSONで `initialize` → `thread/start` → `turn/start` を送る。既存のCodexログインとモデル設定を利用し、専用のephemeral会話を作る。モデルは `CODEX_PIPE_MODEL` で指定することもできる。実行ファイルは `CODEX_PIPE_EXE`、PATH、`%LOCALAPPDATA%\OpenAI\Codex\bin` の順で探す。

画像作成はネイティブの画像生成機能を有効にし、正常完了した `imageGeneration` 通知からPNGを取得する。文章中のパスだけでは画像生成の成功にしない。savedPathまたはbase64に対応し、画像枚数・形式・寸法・容量を検査する。画像全体を保持し、用紙比率との差は白い余白で補う。

データ作成は調整済みの範囲をPNGへ変換し、そのコピーをジョブ専用の `source-input.png` に固定して `localImage` 入力で渡す。参照ビューと送信用PNGは同じ描画変換を使う。画像全体が用紙全体に対応し、枠外は読み取り対象にしない。変換済み画像の方角は元の方角＋回転、範囲の横幅は元の横幅÷倍率を使う。移動による中心緯度・経度の補正は行わず、画像で不明な中心座標は0、出典URLは空として扱う。

元画像のSHA-256、変換済みPNGのSHA-256、範囲・向き・簡略化をまとめた `trace_options_token` を区別する。応答には変換済み画像の `source_image_sha256` と条件トークンをそのまま返すよう求め、不一致は拒否する。画像読取ではWeb検索と新しい画像生成を行わない。ワーカーにVCLや編集文書への参照は渡さない。

対象thread／turnの正常完了、構造化JSON、生成ID・条件・画像の一致、部品の構造を検証して候補にする。構造エラーは元の応答とエラーをCodexへ返して1回修正する。修正時も同じ画像・条件を使い、場所と出典の変更を拒否する。画像作成・読取・修正は推論medium、各生成処理の期限は15分。中止は所有するapp-serverの子プロセスだけに作用する。

公式仕様: [Codex App Server](https://learn.chatgpt.com/docs/app-server)。

## Named Pipe操作

既存の [AIパイプ連携](AI_PIPE.md) の接続先、request_id、再送記録、画像blobを共用する。コマンドは `get_capabilities` で列挙する。

| コマンド | 用途 |
|---|---|
| `generation_show` | 共通画面を表示する |
| `generation_prepare` | 場所・指示・用紙・生成元文書を固定する |
| `generation_start_image` | 条件を準備して元地図画像の作成を開始する |
| `generation_submit_image` | prepareした生成IDにPNG blobを渡す |
| `generation_get_image` | 元画像のPNG blobと元の条件を取得する |
| `generation_set_trace_options` | 範囲・向き・簡略化を変更する。以前の候補は無効になる |
| `generation_get_trace_image` | 現在のトンボ内に対応するPNG blobを取得する |
| `generation_prepare_trace` | 外部Codexへ渡す読取画像・条件を固定する |
| `generation_trace_image` | 現在の画像・条件からアプリ内のCodex読取を開始する |
| `generation_get_request` | 正規化条件・prompt・output_schema・生成元state_tokenを取得する。状態や候補は変更しない |
| `generation_status` | 状態・進捗・画像・条件トークン・採用可否を取得する |
| `generation_submit_result` | prepareした生成IDの構造化応答を渡す |
| `generation_get_result` | 条件・応答・検証済みDocumentを取得する |
| `generation_cancel` | 生成処理を中止する |
| `generation_apply` | 候補を1回のUndo単位で採用する |

変更要求には `request_id` と `apply:true` が必要。prepare/start_imageには現在の `state_token` と `request`、以降の変更には `generation_id` を指定する。submit_imageは `blob_id`、set_trace_optionsは元画像の `image_sha256` と `options`、trace_image/prepare_traceは元画像の `image_sha256` を指定する。後者には現在の `trace_options_token` を渡して古い条件での開始を防げる。applyには生成元の `state_token` も必要。

`options` は部分指定でき、省略した項目は保持する。倍率 `zoom` は0.1～10、移動 `pan_x/pan_y` は枠幅・高さに対する割合（各−4～4）、回転 `rotation_degrees` は時計回りの度数（−180以上180未満へ正規化）、`simplification` は0～100の整数。

```powershell
Import-Module .\Tools\Automation\MapRakuPipe.psm1 -Force
# プラグインはGet-MapRakuEndpointsで対象を選びSet-MapRakuEndpointで固定する。
$start = New-MapRakuMutation 'generation_start_image'
$start.request = @{
    place_query = '東京都千代田区 東京駅 丸の内口'
    span_m = 1000
    north_clockwise_degrees = 0
    instructions = '主要道路と駅を中心に、文字を少なくしてください。'
}
$job = (Invoke-MapRakuPipe $start).generation
# 数秒おきに状態を確認し、image_ready後に画像を確認する。
$status = (Invoke-MapRakuPipe @{command='generation_status'}).generation
$source = (Invoke-MapRakuPipe @{command='generation_get_image'}).generation
$png = Receive-MapRakuBlob $source.image
$change = New-MapRakuMutation 'generation_set_trace_options'
$change.generation_id = $job.generation_id
$change.image_sha256 = $status.image_sha256
$change.options = @{zoom=1.15;pan_x=0.02;pan_y=-0.01;rotation_degrees=-17;simplification=80}
$status = (Invoke-MapRakuPipe $change).generation
$trace = New-MapRakuMutation 'generation_trace_image'
$trace.generation_id = $job.generation_id
$trace.image_sha256 = $status.image_sha256
$trace.trace_options_token = $status.trace_options_token
Invoke-MapRakuPipe $trace
```

外部Codexで画像を作る場合はprepare → PNGをblob送信 → submit_image。外部で読取する場合はprepare_trace → get_request/get_trace_image → promptとPNGとoutput_schemaをモデルへ送る → submit_resultのresponseへ結果JSONを返す。候補画像はget_resultのdocumentを通常のrender_previewへ渡してPNG blobを受信する。

状態は `idle/prepared/image_running/image_ready/tracing/running/receiving/cancelling/cancelled/ready/needs_clarification/failed/applied`。受付の応答を失ったら、新しい開始を送る前に `get_request_result` で元のrequest_idを照会する。従来の `generation_start` はWeb検索から直接データを作る互換経路として残すが、UIは画像を先に確認する経路を使う。

## 検証とサンプル

`Tools/test-image-generation.ps1 -Config Debug|Release` は、自分で起動した単独版を疑似app-serverにつなぐ。`-PluginEditor` は疑似ホストの共通編集画面を使い、先に該当構成の `Tools/test-plugin.ps1` を実行する。試験用app-serverは `Tools/test-codex-generation.ps1` が生成する。通常の試験はモデルを呼ばない。`-Live` の場合だけ実モデルで画像作成・読取を行う。

画像のパス／base64受信、画像完了通知の欠落、画像ハッシュの不一致、変換画像の添付、方角と倍率の反映、条件トークン、簡略化の変更による旧候補無効化、読取だけの照会が状態を変えないこと、採用前の文書保持、採用・Undo／Redoを検証する。`Tools/test.ps1` はトンボ内の元色・枠外の暗さ・送信用画像からマスクを除くこと・回転／移動、非表示フォームでのページ往復とスライダー値保持を検証し、`TestOutput/reference-viewport.png` に参照ビューの描画を出力する。

実Codexによる東京駅のサンプルは [Artifacts/image-workflow-tokyo](../Artifacts/image-workflow-tokyo/README.md)。実際の画像生成と画像読取、56レイヤーの元の候補、範囲・回転・簡略化80を指定した29レイヤーの候補を保存した。後者は手作業で操作列を修正せず、パイプによる採用・保存・Undo／Redoまで検証した。新ページの実マウス操作はユーザーのEscで停止したため、ホイール／ドラッグ操作の実画面確認と実AviUtl2内の操作は残る。

実行時の条件・画像・応答・候補・プレビュー・通信ログは `%LOCALAPPDATA%\MapRaku\Generation\<生成ID>` に保存する。元画像はAIが生成した案内図で、縮尺・形状・施設の位置は地理的な精度を保証するものではない。広域・複雑な交差・別の地域での品質評価は引き続き必要。
