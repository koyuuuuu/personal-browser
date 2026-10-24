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

タブ、URL/検索、ブックマーク、履歴、通常タブの復元、プライベートタブ、共有、ツールバーの位置・ボタン順の変更を実装。ファイルのダウンロード保存等は次段階。

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
