# 初期実装の状態

2026-10-22（日本時間）。ユーザーの選択により、新規SwiftUI＋WKWebViewを採用した。

## 実装した範囲

- URL/検索入力、戻る・進む・再読み込み・停止。
- 最大12タブ、タブの追加・選択・削除。
- 通常タブのURL復元、ブックマーク、直近1,000件までの履歴。
- プライベートタブ。専用の非永続Webデータストアを使用し、タブURL・履歴は保存しない。ユーザーが手動で追加したブックマークは保存する。
- 検索エンジンの変更、バーの上下配置、ツールバーボタンの追加・削除・並べ替え、戻るジェスチャー設定。
- ページURLの共有、JavaScriptのalert/confirm/prompt、WebKitから渡された構成を使うポップアップ用タブ。
- 電話・メール等の外部URLを開く前の確認。
- 履歴消去、全タブを閉じてCookie等のWebデータ消去。
- 保存データのバージョン検証・atomic書き込み。壊れた保存ファイルを勝手に上書きせず、退避して再作成できる。
- Xcodeプロジェクト、オリジナルの仮アイコン、UIテスト、CI、未署名IPAの検査。

これはソースコード上の実装範囲で、すべての機能が実機検証済みという意味ではない。

## ファイル構成

| 場所 | 役割 |
|---|---|
| `Sources/BrowserCore` | URL解決、モデル、保存。Foundationのみ |
| `Tests/BrowserCoreTests` | プライベート情報の除外、保存、入力解決等のテスト |
| `App/BrowserTab.swift` | WKWebViewの所有・delegate・読み込み状態 |
| `App/BrowserStore.swift` | タブ、履歴、設定、保存の制御 |
| `App/BrowserViews.swift` | SwiftUIの閲覧画面・ツールバー・タブ一覧・ライブラリ |
| `App/SettingsView.swift` | UIと操作のカスタマイズ |
| `PersonalBrowser.xcodeproj` | アプリ本体とUIテストの2ターゲット。配布するのは本体だけ |
| `scripts/generate_project.py` | 外部ジェネレーター不要の決定的なプロジェクト生成 |
| `.github/workflows/tooling.yml` | 軽量な検査・Coreテスト。課金停止設定の確認後にLinux自動実行へ切替可能 |
| `.github/workflows/ios.yml` | 手動実行のmacOSテスト・実機用未署名IPA生成 |

アプリ本体に第三者ブラウザのコードや外部パッケージを組み込んでいない。CoreはSwift Packageとして別にテストし、iOSアプリでは同じソースファイルをコンパイルする。

## 検証記録

| 項目 | 状態 |
|---|---|
| Linux / Swift 6.0.3でCoreテスト | 16件成功 |
| PythonのIPA検査・プロジェクト検査 | 18件成功 |
| Swiftの構文検査 | App・Core・UIテストの構文検査に成功 |
| XcodeによるiOS型検査・ビルド | 未実施。クラウドmacOSが必要 |
| SimulatorでのUIテスト | 4件作成、未実行 |
| IPA生成・Apple署名・実機起動 | 未実施 |
| 7日をまたぐ再署名 | 未実施 |

LinuxでのSwift構文検査では、UIKit/SwiftUI/WebKitのAPIの型整合性までは確認できない。最初のmacOS実行でそのエラーが出る可能性があり、ログを取得して修正する。

## 既知の制約と次の段階

- ファイルのダウンロード保存、ページ内検索、ブックマークのインポート/エクスポート、タブの休止は次段階。
- 最初の版はWebKitを持つタブを最大12個まで保持する。iPhone 12でメモリと電池消費を測定し、休止・遅延生成を追加する。
- 復元するのは通常タブのURLで、各タブの戻る/進む履歴やフォーム入力までは復元しない。
- カメラ・マイク、ファイル選択、位置情報、パスキー、認証ポップアップ、動画・DRM等のサイト互換性は実機で個別に確認する。
- 通常ページのTLS検証を緩める処理は入れていない。HTTPページの表示はWebKitに限定して許可する。
- 既定ブラウザ、Share Extension、Widget、Sync、Pushは含めていない。
- 保存データの全面的な暗号化やバックアップ機能は実装していない。通常データはアプリのサンドボックスとiOSのファイル保護を使用する。

## GitHubを使う前に必要な確認

1. 非公開・無料枠内・超過時停止に決定済み。アカウント側の停止設定は未確認。
2. 配置先は`koyuuuuu/personal-browser`。非公開設定と読み書き権限を確認済み。
3. 本人のBilling画面で無料枠と超過時停止を確認。
4. 最初の実機導入前にBundle IDを固定する。現在の`local.personalbrowser.app`は仮の初期値で、Repository Variablesの`BROWSER_BUNDLE_ID`で変更できる。

GitHubアカウントの課金設定変更、CIの実行、Apple Accountの操作はまだ行っていない。
