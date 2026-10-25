# Personal iPhone Browser

iPhone 12 / iOS 18.4.1向けの個人用ブラウザ。SwiftUIとWKWebViewで新規実装し、Windowsで編集、クラウドmacOSでビルド、SideStoreで実機へ導入・再署名する。

**初期版0.1.0（build 6）のビルド・UIテスト・未署名IPA生成に成功。2026-10-24に本人がiPhoneで利用できたと報告。全機能・継続再署名の検証はこれから。** 非公開の[koyuuuuu/personal-browser](https://github.com/koyuuuuu/personal-browser)で無料枠内・超過時停止の方針。支払い方法は未登録との本人回答を受けてCIを実行した。

[v0.1.0の保存済みリリース](https://github.com/koyuuuuu/personal-browser/releases/tag/v0.1.0)から、ビルド元のソースとIPA保管先を参照できる。IPAは非公開の`ipa-archive`ブランチに保存し、Actionsの1日保持期限が過ぎても取得できる。約323 KiB、arm64実機用、最低iOS 17.0。SideStoreで個人用に署名して導入する。[検証記録](docs/validation-2026-10-22.json)にハッシュとビルド元を記録した。

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

mainへのアプリ・テスト・ビルド・配信コードのpushで、Linux検査、標準`macos-15`でのCore/UIテスト、新旧版のデータ互換性検査、未署名IPA生成、Release保存、SideStoreソース更新を自動実行する。文書のみの変更はビルドしない。手動実行も可能だがpushと重複して起動しない。Actions成果物は1日保持し、配布版のIPAはReleaseへ残す。macOSとXcodeがある場合は`bash scripts/ios_ci.sh`でも実行できる。

アプリ本体に第三者のブラウザソースや外部パッケージを組み込んでいない。0.2.0ではCore 19件（LinuxとmacOS）、Simulator UI 5件、Python検査30件、新旧版を往復するデータ互換性検査に成功。アカウントの課金設定変更やAppleの署名操作は行っていない。

0.2.0では更新通知設定とSideStore配信パイプラインを実装した。mainへのアプリ関連pushでテスト・IPA生成・Release保存・配信JSON更新を行う。公開するのは承認された配布専用リポジトリのIPA・JSON・アイコンのみ。非公開の本体ソースと最新の端末内データは維持する。公開配信の初回認証設定は[配信手順](docs/distribution.ja.md)を参照。

2026-10-24: [run #10](https://github.com/koyuuuuu/personal-browser/actions/runs/40094049156)で0.2.0 build 10の公開配信まで成功。SideStoreのSourcesに `https://raw.githubusercontent.com/koyuuuuu/personal-browser-distribution/main/source.json` を一度追加する。公開するのはIPA・JSON・アイコンと説明文のみ。最新データの新旧版互換性はCI成功、実機での上書き更新は初回受け入れ確認待ち。[配信検証記録](docs/delivery-validation-2026-10-24.json)。

0.3.0ではPiP・共有の改善、広告ブロック、遅延読み込みの500タブとタイル表示、お気に入りホーム・背景画像、ブックマークフォルダ、Safariデータの取り込み、リンク長押しメニュー、Watch HTML連携、ページ内検索・ダウンロードを追加。[使い方・制約・今後の候補](docs/changes-0.3.0.ja.md)を参照。

0.4.0では横画面の細い自動非表示バー、表示設定、左右のアドレスバーボタン、通常タブの画像の永続保存、背景位置・ズーム、末尾スワイプでの新規タブ、接続先／証明書別の確認と記憶を追加。[使い方と制約](docs/changes-0.4.0.ja.md)を参照。

0.4.1ではタブ削除の待機・横スライドを廃止し、画像と横画面配置を修正。再生制御と縦画面バーをbuild 14へ戻した。[変更と原因分析](docs/changes-0.4.1.ja.md)、[検証記録](docs/validation-0.4.1-2026-10-25.json)。

0.4.2 build 27では横画面ホームの操作領域、ネイティブのタブ一覧・スワイプ削除、アドレスバーの指に追従するタブ遷移、午前・午後別の履歴、アドレス候補、5％刻みの倍率ボタン、Safari取り込み、縦横バーのスクロール判定を改善。[使い方と変更点](docs/changes-0.4.2.ja.md)、[検証記録](docs/validation-0.4.2-2026-10-25.json)。
