# Personal iPhone Browser

iPhone 12 / iOS 18.4.1向けの個人用ブラウザ。SwiftUIとWKWebViewで新規実装し、Windowsで編集、クラウドmacOSでビルド、SideStoreで実機へ導入・再署名する。

**最新配信版は0.9.0 build 52。音声の同時再生を優先する任意設定を追加。** [リリース](https://github.com/koyuuuuu/personal-browser-distribution/releases/tag/v0.9.0-build.52)、[配信記録](docs/validation-0.9.0-2026-10-31.json)。本体ソースは[koyuuuuu/personal-browser](https://github.com/koyuuuuu/personal-browser)で公開し、標準の公開リポジトリ用Actionsランナーを利用する。有料ランナーや課金設定は追加していない。

[v0.1.0の保存済みリリース](https://github.com/koyuuuuu/personal-browser/releases/tag/v0.1.0)から、初期版のビルド元とIPA保管先を参照できる。初期IPAは`ipa-archive`ブランチ、新版はGitHub Releasesに保存し、Actionsの1日保持期限が過ぎても取得できる。arm64実機用、最低iOS 17.0。SideStoreで個人用に署名して導入する。現在は本体リポジトリ全体が公開されている。

- [実現性と無料運用の条件](docs/feasibility.ja.md)
- [GitHubの無料利用枠でできること](docs/free-tier.ja.md)
- [非公開GitHubリポジトリと超過時停止の設定](docs/github-setup.ja.md)
- [毎回のGitHubログインを省くCodex運用](docs/github-automation.ja.md)
- [実装範囲・検証状況・既知の制約](docs/implementation-status.ja.md)
- [バージョン管理と旧版へ戻す手順](docs/versioning.ja.md)
- [SideStoreへの自動配信と初回設定](docs/distribution.ja.md)
- [OSSの詳細比較・Firefox採用時の改修箇所](docs/oss-comparison.ja.md)
- [アーキテクチャとCI・Codexの運用設計](docs/architecture.ja.md)
- [Windows・SideStoreの導入・更新・復旧手順](docs/operations.ja.md)

タブ、URL/検索、ブックマーク・お気に入り、履歴、通常タブの復元、プライベートタブ、共有、ファイルのダウンロード、ツールバーの位置・ボタン順の変更を実装。

```sh
python3 -W error -m unittest discover -s scripts -p 'test_*.py' -v
python3 scripts/generate_project.py --check
swift test
python3 scripts/inspect_ipa.py browser.ipa --target-ios 18.4.1 --unsigned
```

Swiftファイルを追加・削除したら`python3 scripts/generate_project.py`でプロジェクトを再生成する。Windowsでは`py -3`を利用でき、CoreのSwiftテストはWSL等のSwift環境かCIで実行する。

mainへのアプリ・テスト・ビルド・配信コードのpushで、Linux検査、標準`macos-15`でのCoreテスト、未署名IPA生成・検査を自動実行する。UIテストは変更した機能の代表ケースのみ、旧版とのデータ互換性検査は保存処理等を変更した場合のみ実行する。アプリ本体やリリース設定の変更時はRelease保存・SideStoreソース更新も行う。検証設定だけの変更では同じアプリを再配信しない。[検証の実行条件](docs/verification-policy.ja.md)。文書のみの変更はビルドしない。手動実行も可能だがpushと重複して起動しない。Actions成果物は1日保持し、配布版のIPAはReleaseへ残す。macOSとXcodeがある場合は`bash scripts/ios_ci.sh`でも実行できる。

アプリ本体に第三者のブラウザソースや外部パッケージを組み込んでいない。0.2.0ではCore 19件（LinuxとmacOS）、Simulator UI 5件、Python検査30件、新旧版を往復するデータ互換性検査に成功。アカウントの課金設定変更やAppleの署名操作は行っていない。

0.2.0では更新通知設定とSideStore配信パイプラインを実装した。mainへのアプリ関連pushでテスト・IPA生成・Release保存・配信JSON更新を行う。公開するのは承認された配布専用リポジトリのIPA・JSON・アイコンのみ。非公開の本体ソースと最新の端末内データは維持する。公開配信の初回認証設定は[配信手順](docs/distribution.ja.md)を参照。

2026-10-24: [run #10](https://github.com/koyuuuuu/personal-browser/actions/runs/40094049156)で0.2.0 build 10の公開配信まで成功。SideStoreのSourcesに `https://raw.githubusercontent.com/koyuuuuu/personal-browser-distribution/main/source.json` を一度追加する。公開するのはIPA・JSON・アイコンと説明文のみ。最新データの新旧版互換性はCI成功、実機での上書き更新は初回受け入れ確認待ち。[配信検証記録](docs/delivery-validation-2026-10-24.json)。

0.3.0ではPiP・共有の改善、広告ブロック、遅延読み込みの500タブとタイル表示、お気に入りホーム・背景画像、ブックマークフォルダ、Safariデータの取り込み、リンク長押しメニュー、Watch HTML連携、ページ内検索・ダウンロードを追加。[使い方・制約・今後の候補](docs/changes-0.3.0.ja.md)を参照。

0.4.0では横画面の細い自動非表示バー、表示設定、左右のアドレスバーボタン、通常タブの画像の永続保存、背景位置・ズーム、末尾スワイプでの新規タブ、接続先／証明書別の確認と記憶を追加。[使い方と制約](docs/changes-0.4.0.ja.md)を参照。

0.4.1ではタブ削除の待機・横スライドを廃止し、画像と横画面配置を修正。再生制御と縦画面バーをbuild 14へ戻した。[変更と原因分析](docs/changes-0.4.1.ja.md)、[検証記録](docs/validation-0.4.1-2026-10-25.json)。

0.4.2 build 27では横画面ホームの操作領域、ネイティブのタブ一覧・スワイプ削除、アドレスバーの指に追従するタブ遷移、午前・午後別の履歴、アドレス候補、5％刻みの倍率ボタン、Safari取り込み、縦横バーのスクロール判定を改善。[使い方と変更点](docs/changes-0.4.2.ja.md)、[検証記録](docs/validation-0.4.2-2026-10-25.json)。

0.5.0 build 38を配信済み。お気に入りの配置変更・編集、検索語表示、リンク処理、軽量なタブ遷移、外部URL受信、任意のホーム検索候補を追加。[変更点と検証状況](docs/changes-0.5.0.ja.md)、[共有ショートカット手順](docs/shortcuts.ja.md)。検索候補は設定の「ホーム画面に検索候補を表示」で有効にする（初期オフ）。今回は本人の即時配信指示により追加テストを省略し、実機用ビルド・IPAと配信情報の照合を実施。0.4.2 build27のIPAは復帰先として保持する。

2026-10-26: 利用者の指示で全ブランチ・タグの履歴を監査したうえ、本体ソースを公開する方針へ変更。以前の非公開方針の記述は当時の運用記録。[公開前の確認](docs/publication-audit-2026-10-26.ja.md)。標準の公開リポジトリ用Actionsランナーを使い、有料ランナーや課金設定は追加しない。

0.6.0 build42を配信済み。Python48件・Core58件・変更範囲のUI4件と実機用ビルドに成功。更新可能な広告フィルターとサイト独自のお気に入りアイコンを追加。[構成・設定・ライセンス](docs/changes-0.6.0.ja.md)。

0.7.0 build45を配信済み。Python49件・Core63件・変更範囲のUI4件と旧版とのデータ互換性検査に成功。リンク・メニューで開くタブを元タブの隣へ配置し、タブを見ていた順に戻る／進むボタンを追加。ツールバーとタブ一覧の＋は末尾追加を維持。[仕様と設定](docs/changes-0.7.0.ja.md)。

0.8.0 build46を配信済み。選択メニューへの検索項目とWebKit制約時の画面内ボタン、mybrowser://search?text=、Googleの初期値を追加。既存の検索エンジン設定を維持。[使い方](docs/changes-0.8.0.ja.md)、[共有ショートカット手順](docs/shortcuts.ja.md)。

0.9.0 build52を配信済み。「設定 → 音声の同時再生」で音声ミックス準備とWeb非排他モードを切替可能。初期オフで従来方式を維持。実際のaudio要素・別タブ・停止操作・設定保持の代表UI1件を確認。YouTube・Apple Music・全画面・PiP等の全組合せは保証しない。[使い方・制約](docs/changes-0.9.0.ja.md)。
