# Personal iPhone Browser

iPhone 12 / iOS 18.4.1向けの個人用ブラウザ。SwiftUIとWKWebViewで新規実装し、Windowsで編集、クラウドmacOSでビルド、SideStoreで実機へ導入・再署名する。

**初期版0.1.0（build 6）のビルド・UIテスト・未署名IPA生成に成功。iPhone実機での署名・起動は未検証。** 非公開の[koyuuuuu/personal-browser](https://github.com/koyuuuuu/personal-browser)で無料枠内・超過時停止の方針。支払い方法は未登録との本人回答を受けてCIを実行した。

[成功したCIとIPA](https://github.com/koyuuuuu/personal-browser/actions/runs/39704611315)のArtifactsから`PersonalBrowser-6`をダウンロードし、ZIPを展開して`PersonalBrowser.ipa`を取り出す。GitHub側の保持期限は2026-10-23 10:17（日本時間）。IPAは約323 KiB、arm64実機用、最低iOS 17.0。SideStoreで個人用に署名して導入する。[検証記録](docs/validation-2026-10-22.json)にハッシュとビルド元を記録した。

- [実現性と無料運用の条件](docs/feasibility.ja.md)
- [GitHubの無料利用枠でできること](docs/free-tier.ja.md)
- [非公開GitHubリポジトリと超過時停止の設定](docs/github-setup.ja.md)
- [実装範囲・検証状況・既知の制約](docs/implementation-status.ja.md)
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

以後のコード変更時は、Actionsの「iOS tests and unsigned IPA」を手動実行する。標準`macos-15`ランナーでCore/UIテストを通してから未署名IPAを生成する。成果物の保存は1日。現在はLinux・macOSとも手動起動だけに限定し、push/PRでは実行しない。必要に応じてLinux検査の自動実行を追加できる。macOSとXcodeがある場合は`bash scripts/ios_ci.sh`でも実行できる。

アプリ本体に第三者のブラウザソースや外部パッケージを組み込んでいない。Core 16件（LinuxとmacOS）、Simulator UI 4件、ローカルPython検査20件に成功。アカウントの課金設定変更やAppleの署名操作は行っていない。
