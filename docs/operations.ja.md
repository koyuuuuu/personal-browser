# Windows・iPhoneでの導入と運用

対象: iPhone 12 / iOS 18.4.1。新規SwiftUI＋WKWebViewの初期ソースを実装済み。初回macOSビルドはまだ。以下は公式資料に基づく導入設計で、実機での完了記録ではない。

## 事前に決めること

- ベースは新規SwiftUI＋WKWebViewに決定済み。現在の実装範囲は[実装状況](implementation-status.ja.md)。
- GitHubの公開可否・配置先を確認する。公開でも履歴・Cookie・認証情報・ペアリング情報は入れない。
- 以後変えない個人用Bundle IDを決める。アプリ更新でIDや署名アカウントを変えると別アプリ扱いになり、データを引き継げないことがある。
- GitHubのBillingで他の利用を含む無料枠と、超過時に停止する予算設定を確認する。アカウント全体の有料設定はCIのYAMLだけでは制御できない。

## 初回導入

1. WindowsへGitと必要な編集環境を入れる。本体の採用後、リポジトリを準備する。GitHubのアカウント操作は本人への確認後に行う。
2. ActionsでSimulatorビルドとテストを実行し、実機用arm64の未署名IPAを取得する。ActionsアーティファクトはZIPなので展開して、中の`.ipa`を選ぶ。SHA-256がビルド記録と一致することを確認する。
3. [SideStoreの最新Prerequisites](https://docs.sidestore.io/docs/installation/prerequisites)に従い、WindowsにiloaderとAppleの端末接続ソフトを準備する。古い手順のWireGuard前提を混ぜない。現在の公式手順ではLocalDevVPNを使う。
4. iPhoneにLocalDevVPNを入れ、WindowsへUSB接続して信頼する。[Install](https://docs.sidestore.io/docs/installation/install)に従ってiloaderでSideStore Stableをインストールする。Apple Accountの入力・2FAは本人が行う。
5. iPhone側で開発元を信頼し、Developer Modeを有効にする。Wi-FiとLocalDevVPNを有効にしてSideStoreへログインし、SideStore自身の最初の手動更新を成功させる。
6. IPAをiPhoneの「ファイル」に移す。SideStoreのMy Appsから追加し、署名・インストールする。Apple AccountやペアリングファイルはGitHubに送らない。
7. 起動・HTTPS閲覧・検索・タブ・履歴等を確認し、端末再起動後と同じBundle IDでの上書き更新後にもデータが残るか確認する。

SideStoreと個人ブラウザで無料署名の同時アプリ枠を2つ使う。App Storeから入れるLocalDevVPNはこの無料開発署名のアプリ枠とは別。追加のShare ExtensionやWidgetは初期構成に含めない。

## 署名を保つ運用

7日の期限直前ではなく、毎日更新を試みる。SideStoreのバックグラウンド更新を有効にし、必要なら「ショートカット」アプリの個人用オートメーションで自宅Wi-Fi接続時や日次に更新を実行する。インストールしたバージョンが提供する「Refresh All Apps」等のアクションを実機で確認する。存在しないアクション名やURLスキームを前提に配布しない。

まず、Wi-Fi＋LocalDevVPN有効・ロック解除中に手動更新を試し、その後自動実行を試す。更新は本アプリとSideStore自身の両方を対象とする。ロック中・再起動後・低電力モード・VPN併用・Apple認証の再要求によって成功しない場合があるため、最初の2週間は残り日数を毎日目視で確認する。

「更新を実行した通知」だけでは成功判定しない。SideStoreで両方の残り期間が更新されたことと、本体が起動できることを確認する。手動での確認用リマインダーを残す。証明書の更新時刻をブラウザ本体が独自に推測して成功扱いする機能は入れない。

## 失敗・失効時

1. 失効前: Wi-Fi、LocalDevVPN、SideStoreの認証状態、空きアプリ/App ID枠を確認し、手動で更新する。
2. SideStoreが起動できない: WindowsとUSBを使う公式の復旧手順を確認する。同じアカウントとアプリIDでの上書き復旧を優先する。
3. ペアリングエラー: 公式手順でiloaderからペアリングを再作成する。[Common issues](https://docs.sidestore.io/docs/troubleshooting/common-issues)を参照する。
4. インストールできない: IPAの実機/Simulator、最低OS、署名の対応権限、App ID上限を分けて確認する。Apple署名の問題を、コード再ビルドだけで直そうとしない。
5. データ保全: ブラウザのアンインストールを先に行わない。削除はローカルデータの消失につながる。エクスポート機能を追加した後は、定期的にブックマーク・設定を端末外へ保存する。

## 実機受け入れ試験

| 試験 | 合格条件 | 状態 |
|---|---|---|
| 初回起動 | iPhone 12 / iOS 18.4.1で起動する | 未実施 |
| Web互換性 | 日常サイト、ログイン、戻る/進むが使える | 未実施 |
| 保存 | 強制終了・端末再起動後にも通常データが残る | 未実施 |
| 上書き更新 | 同一IDの新IPAでブックマーク・設定等を維持 | 未実施 |
| 手動再署名 | SideStoreと本体の期限が延長され、起動できる | 未実施 |
| 自動更新 | 実際の生活条件で毎日の更新成功を記録 | 未実施 |
| 7日超の継続 | 少なくとも14日間、期限失効せず利用 | 未実施 |
| 復旧 | Windowsからの復旧手順を確認 | 未実施 |

## IPA検査ツール

Python 3.11以上の標準ライブラリだけで実行できる。

```powershell
py -3 scripts/inspect_ipa.py path/to/browser.ipa --target-ios 18.4.1 --unsigned
py -3 -W error -m unittest discover -s scripts -p "test_*.py" -v
```

このツールは初期構成のthin arm64実機ビルドを対象とし、汎用の全IPA形式には対応しない。Info.plist、Mach-OのCPUとplatform、実行権限、最低OS、拡張混入、ZIP整合性等を確認する。Apple署名の暗号学的検証、全依存frameworkの互換性、実機インストールや起動を保証するものではない。
