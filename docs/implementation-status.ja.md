# 実装と検証の状態

2026-10-24更新。ユーザーの選択により、新規SwiftUI＋WKWebViewを採用した。初期版の利用報告と0.2.0のCI検証を分けて記録する。

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
- mainへのpushからIPA生成・Release保存・SideStoreソース生成までの自動化。別の公開リポジトリにはIPA・JSON・アイコンのみを配布する。
- 初期値オフのアプリ内更新通知、設定のオン・オフ、手動確認、SideStoreを開く操作。
- schema 1と保存先を維持し、新旧版で最新のブックマーク・履歴を読み書きする互換性検査。

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
| `.github/workflows/tooling.yml` | 軽量な検査・Coreテスト。無料枠を抑える手動実行。必要に応じてLinux自動実行へ切替可能 |
| `.github/workflows/ios.yml` | mainへのアプリ関連pushで検査・macOSテスト・IPA生成・配信。手動も可能 |
| `App/UpdateChecker.swift` / `UpdateSettingsView.swift` | 更新通知・設定。schema 1のデータと分離 |
| `scripts/distribution.py` / `publish_release.py` | Release保管・公開バイナリ配信・SideStoreソース生成 |

アプリ本体に第三者ブラウザのコードや外部パッケージを組み込んでいない。CoreはSwift Packageとして別にテストし、iOSアプリでは同じソースファイルをコンパイルする。

## 検証記録

| 項目 | 状態 |
|---|---|
| Linux / Swift 6.0.3でCoreテスト | 19件成功 |
| PythonのIPA検査・プロジェクト検査・配信検査（ローカル） | 30件成功 |
| Swiftの構文検査 | App・Core・UIテストの構文検査に成功 |
| XcodeによるiOS型検査・ビルド | Xcode 16.4でDebug Simulator / Release実機arm64の両方に成功 |
| SimulatorでのUIテスト | 0.2.0で5件成功。更新通知の初期値オフとオン・オフを追加 |
| IPA生成・構造検査 | 0.2.0 build 9、376,835 bytesの生成・取得後検査に成功。初期版build 6のIPAも保持 |
| 最新データの互換性 | 旧版→新版→旧版→新版で追記し、すべての最新ブックマーク・履歴の保持を確認 |
| Apple署名・iPhoneでの実機起動 | 2026-10-24に本人がブラウザを利用できたと報告。個別機能の受け入れ試験は別途 |
| 7日をまたぐ再署名 | 未実施 |

0.2.0は[run #9](https://github.com/koyuuuuu/personal-browser/actions/runs/40091434579)、ソース`5f13a56089c19c70293e55c5eb6ee7292fcc1b67`でPython 30件・Core 19件・UI 5件・互換性検査・Release生成に成功。取得したIPAの構造とSHA-256一致も確認済み。[新しい検証記録](validation-2026-10-24.json)を参照。公開配信の最終状態は[配信手順](distribution.ja.md)を参照。

初期版のGitHub Actions [run #6](https://github.com/koyuuuuu/personal-browser/actions/runs/39704611315)、ビルド元`438292f5622801bf56525381576b789f65e4d203`で成功。macOS上でもCore 16件に成功した。UIテストは危険なURLの拒否、プライベートタブの追加と一覧、設定によるバーの上下配置、オフラインHTML表示とJavaScriptによるページ内操作を確認する。

初回のFileManager API引数ラベル、SDKより新しいSimulatorの選択を修正した。SwiftUI MenuのAXタップ位置取得の問題には、スクリーンショットで配置を確認し、画面内のボタン中央への物理タッチと操作結果の検査で対応した。iOS 18.4.1の実機で同じテストを完了した意味ではない。詳細は[検証記録](validation-2026-10-22.json)を参照。

## 既知の制約と次の段階

- ファイルのダウンロード保存、ページ内検索、ブックマークのインポート/エクスポート、タブの休止は次段階。
- 最初の版はWebKitを持つタブを最大12個まで保持する。iPhone 12でメモリと電池消費を測定し、休止・遅延生成を追加する。
- 復元するのは通常タブのURLで、各タブの戻る/進む履歴やフォーム入力までは復元しない。
- カメラ・マイク、ファイル選択、位置情報、パスキー、認証ポップアップ、動画・DRM等のサイト互換性は実機で個別に確認する。
- 通常ページのTLS検証を緩める処理は入れていない。HTTPページの表示はWebKitに限定して許可する。
- 既定ブラウザ、Share Extension、Widget、Sync、Pushは含めていない。
- 保存データの全面的な暗号化やバックアップ機能は実装していない。通常データはアプリのサンドボックスとiOSのファイル保護を使用する。

## GitHubと次の実機検証

- 非公開の`koyuuuuu/personal-browser`へ配置済み。
- 本人から支払い方法未登録と回答を得て、必要なCIを実行した。利用残高や予算設定をAPIで確認・変更したものではない。
- mainへのアプリ関連pushで検査・ビルド・配信を自動実行。文書のみの変更では起動しない。一時成果物は1日保持し、IPAはReleaseへ残す。毎週の再署名ではビルドしない。
- 初回IPAのBundle IDは`local.personalbrowser.app`で固定する。以後、同じApple AccountとアプリIDで更新する。
- 署名・インストール・実機起動後の利用開始を本人が報告。次は保存と上書き更新、14日間の再署名継続を検証する。[導入手順](operations.ja.md)を参照。

## 版の保存

初期版を`v0.1.0`タグと非公開リリースで固定した。ビルド元は上記のCI成功コミット。実際の未署名IPAとハッシュを非公開の`ipa-archive`ブランチへ保存済み。[版管理・復旧手順](versioning.ja.md)を参照。
