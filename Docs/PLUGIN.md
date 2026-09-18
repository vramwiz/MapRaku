# AviUtl2「地図」プラグイン

`SYNC_MapRaku_Filter.dproj` は、参照元 `D:\DelphiProg\test\SYNC_ScreenLayout` のプラグインプロジェクトをコピーして地図用に変更したもの。登録グループは **SYNC**、表示名は **地図**。単独アプリと同じ編集画面・地図モデル・描画・パイプ処理をコンパイルする。ホスト連携だけを `Source/PlacementPlugin` に置く。

## ビルドと配置

```powershell
.\Tools\build-plugin.ps1 -Config Debug
.\Tools\build-plugin.ps1 -Config Release
```

IDE／スクリプトのどちらでも、Debug／Releaseのビルド前に `C:\ProgramData\aviutl2\Plugin\SYNC_MapRaku` を作成し、ビルド後に生成DLLを `SYNC_MapRaku_Filter.auf2` として、`sk4d.dll` と一緒に自動コピーする。配布用の同じ2ファイルも `Win64/Plugin/<構成>` に生成する。コピー失敗はビルド失敗として扱うため、ビルド前にAviUtl2を終了する。参照元のプラグイン配置先は変更しない。

IDEの実行ホストは両構成とも `D:\aviutl2_v2.1.6a\aviutl2.exe`、作業ディレクトリは同じフォルダー。F9とCtrl+Shift+F9（デバッグなしで実行）ではAviUtl2を起動する。IDEの出力先は `.\Win64\Plugin\$(Config)` とし、ここに `$(MSBuildProjectDirectory)` を使わない。後者はビルドできても、デバッグなし実行で「ディレクトリ名が無効です」になることを確認した。設定変更前からIDEで開いている場合は、ディスク上のプロジェクトを再読み込みする。

単独版は引き続き `MapRaku.dproj` でビルドする。プラグインと単独版の中間ファイル・出力先・UIレイアウト保存先は分離している。

## 編集と保存

「地図」の「編集」ボタンで共通UIを開く。「適用」で編集結果のJSONを対象の「地図データ」へ保存する。「取消」またはウィンドウを閉じる操作では元データを維持する。Enter／Escは作図操作用とし、適用／取消ボタンには割り当てていない。

新規文書は取得できた映像寸法で初期化し、保存済み文書は元の用紙寸法を維持する。用紙サイズと色の設定は利用できる。出力時はホストの映像寸法へ合わせて描画するため、用紙と出力の縦横比が違う場合は縦横の拡大率も異なる。元地図画像の条件を固定した後は、既存のパイプの寸法制約に従う。

未設定の効果は入力映像をそのまま通す。適用済み地図は、背景が不透明なら背景色を含め、透明なら入力映像へ重ねる。ホストから取得した映像は編集中の補助画像で、AIの元地図画像とは別に保持する。元地図画像が優先され、解除後は透明キャンバスでホスト映像を表示する。補助画像は地図データには保存しない。

## AI接続

編集画面下部に表示する `MapRaku.Plugin.<PID>.{GUID}` を接続先に使う。毎回の編集で名前を変え、古い編集への指示が次の文書へ適用されないようにする。単独アプリは従来の `MapRaku.v1`。

```powershell
Import-Module .\Tools\Automation\MapRakuPipe.psm1 -Force
Get-MapRakuEndpoints
Set-MapRakuEndpoint 'MapRaku.Plugin.<PID>.{編集画面に表示されたGUID}'
Invoke-MapRakuPipe @{command='get_capabilities'}
```

応答の `host_kind`、`process_id`、`pipe_name` で接続先を確認する。選択後に接続が切れても、クライアントは別の編集へ自動接続しない。指示・地図データ・画像の交換はすべてパイプを通し、通常の配置・Undo／Redo・画像転送を利用できる。AIの反映先は開いている編集文書であり、AviUtl2への確定は画面の「適用」で行う。

## 検証範囲と次の確認

`Tools/test-plugin.ps1 -Config Debug|Release` は疑似ホストでDLL登録、背景色・透明合成、道路／線路を含む共通描画との一致、効果別の状態分離、不正JSONからの保護、共通UIの適用／取消、再編集を検証する。`Tools/test-pipe.ps1 -Config Debug|Release -PluginEditor` はホスト用編集モードで全配置種類・21配置・5交差・Undo／Redo・画像転送・保存再読込を検証する。

ビルド時の配置とコピー元・配置先のハッシュ一致は確認済み。IDEのF9起動と地図DLLのロードを確認し、デバッグなし実行の修正後起動はユーザーが確認済み。AviUtl2本体でのプロジェクト保存と再読込、GPU背景取得、DPI、同一オブジェクトへの複数「地図」の編集対象指定は未確認。背景コンテキストが位置情報から一意に決まらない場合は、別効果の映像を誤表示せず背景取得を省略する。

Skiaの共有ストリームコールバックが解放済みDLLを指す実行違反を防ぐため、プラグインのコードはプロセス終了まで保持する。`UninitializePlugin` では文書・画像・描画状態を解放できるが、DLL差替えにはAviUtl2の終了が必要。
