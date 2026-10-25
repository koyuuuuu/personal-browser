# SideStoreへの自動配信

現在は本人の指示で本体の`koyuuuuu/personal-browser`も公開済み。0.5.0 build38を配信し、本人がSideStoreで更新できたと報告した。[今回の配信記録](validation-0.5.0-build38.json)。以下は現在の構成。

## 構成と妥当性

- 公開ソース: `koyuuuuu/personal-browser`。
- 公開配布先: `koyuuuuu/personal-browser-distribution`。IPA、必要なアイコン、SideStore/AltStore ClassicソースJSONだけを置く。この配布先にはSwiftソースや端末内のデータを置かない。
- 当初の非公開ソース運用で用意した公開配布先を継続利用する。この方式ならSideStoreにGitHubのパスワードやトークンを渡す必要がない。
- GitHub Releasesと公開リポジトリ内の配信JSONを利用する。追加のホスティング契約・有料Apple Developer契約は不要。現在のビルドは公開リポジトリの標準Actionsランナーを利用する。有料ランナーや課金設定は追加しない。

## 自動化する流れ

1. mainへのアプリ・テスト・ビルド・配信コードのpushでCI開始。文書だけの変更や保管ブランチの更新では開始しない。
2. Python検査とプロジェクト整合性を確認。
3. macOSでCoreテスト、UIテスト、旧版と新版のデータ互換性を検査。
4. 実機用の未署名IPAをビルドし、固定Bundle ID、OS、形式、バージョンを検査。
5. ソースリポジトリのGitHub ReleaseへIPA・build-info.json・SHA256SUMS.txtを保存。タグは`v0.2.0-build.7`等とし、元のソースSHAへ固定する。
6. 生成した配信JSONと全版の検査記録を、ソース側のdistributionブランチに保存。
7. 承認された公開配布先へ、検査済みIPAだけをReleaseとして複製。すべての参照IPAが取得可能になった後でsource.jsonを更新する。
8. SideStoreでソースを更新すると、新しいバージョンを確認できる。iPhone側の「更新」操作は残る。

新しい版の判定にはユーザー向けバージョンとビルド番号の両方を使う。同じ0.2.0でも新しいビルドを区別できる。公開済みのタグ・IPAは差し替えない。失敗したビルドを配信JSONの先頭に載せない。

## 初回だけ必要な設定

公開リポジトリは作成済み。本人はSecret名をBROWSER_DISTRIBUTION_TOKENとして保存した。ワークフローはそのSecretをプログラム内のDISTRIBUTION_TOKEN環境変数へ渡す。作り直す場合は次の手順で設定する。現在の連携は新規リポジトリ作成APIとActions Secret設定APIで403になるため、こちらから設定したことにはできない。

1. https://github.com/settings/personal-access-tokens/new でFine-grained tokenを作成。
2. Resource ownerはkoyuuuuu、Repository accessはOnly select repositoriesで **personal-browser-distributionのみ** を選ぶ。
3. Repository permissionsのContentsをRead and writeにする。ソースリポジトリへの権限は付けない。
4. トークン値を https://github.com/koyuuuuu/personal-browser/settings/secrets/actions/new で、名前 **BROWSER_DISTRIBUTION_TOKEN** のSecretとして保存する。
5. トークン値をチャットやソースへ貼らない。期限が切れたときは、このSecretを更新する。

ソース側のRelease保存にはGitHubがジョブごとに発行するGITHUB_TOKENを使う。BROWSER_DISTRIBUTION_TOKENは公開配布先への書き込み専用。公開用トークンが未設定なら、ソース側Releaseと配信JSONの生成まで進み、公開配信が未設定であることをCIに表示する。設定後はpublishジョブだけの再実行で配信でき、macOSの再ビルドは不要。

## iPhone側の初回設定

SideStoreのSourcesから次のURLを追加する。

https://raw.githubusercontent.com/koyuuuuu/personal-browser-distribution/main/source.json

現在の配信先頭は0.5.0 build38。復帰基準の0.4.2 build27と初期版を含め、10版を配信JSONに保持する。最新IPAを認証情報なしで取得し、SHA-256・サイズ・Bundle ID・版番号をRelease記録と照合した。[最新配信記録](validation-0.5.0-build38.json)、[初回配信の記録](delivery-validation-2026-10-24.json)を参照。既存アプリの削除は不要。同じApple Account・元のBundle IDで更新する。

ブラウザ0.2.0以降の「設定 → アプリの更新」から、通知をオン・オフできる。初期値はオフ。オンの場合は起動中・アプリへ戻った時に最大1日1回確認し、新しい版があれば画面内で案内する。OSのプッシュ通知や常駐処理は使わない。「今すぐ更新を確認」は手動で使え、SideStoreを開く操作とソースURLのコピーもできる。

SideStoreの署名Refreshは既存アプリの署名期限を延ばすもの。新機能の入ったIPAへの更新と同じ操作ではない。通知をオフにしてもSideStore側での配信確認・署名更新は独立して動く。

## 最新データを維持する方針

- Bundle IDはlocal.personalbrowser.appで固定。
- 保存先は従来のApplication Support/PersonalBrowser/browser.json、共通データ形式はschema 1のまま。
- 更新通知の設定はUserDefaultsに分離し、ブックマーク・履歴のJSONへ追加しない。
- アプリ機能を旧版へ戻す場合も、端末にある最新データを継続して使い、過去のバックアップへ置き換えない。
- 互換性テストは旧版の保存→新版で追記→旧版で最新データを読んで追記→新版で再確認を行う。単に新旧の初期データが読めることだけでは済ませない。
- 将来もこの共通形式を破壊する改修はCIで拒否する。旧版が扱えない追加データは別ファイル等に分離し、互換性を維持してから配信する。

実際のSideStoreによる上書きと端末のサンドボックス保持は、ユーザーのiPhoneでも最初の更新時に確認する。CIは署名済みの実機更新そのものを代行した証拠ではない。

## 旧機能版への切り替え

source.jsonには旧版も残す。SideStoreが提供する過去バージョン選択や、こちらから渡す旧IPAで上書きできる。アプリを削除しない。新しい版番号で旧機能へ戻す修正版を配信する方法も使える。どちらも端末の最新データを保持する方針で行う。

## 一次資料

- https://faq.altstore.io/developers/make-a-source
- https://faq.altstore.io/developers/updating-apps
- https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication
