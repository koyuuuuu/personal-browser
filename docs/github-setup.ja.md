# 非公開GitHubの設定と実行

2026-10-22（日本時間）。非公開・無料枠内・超過時停止の方針に決定済み。
ユーザーが作成した[koyuuuuu/personal-browser](https://github.com/koyuuuuu/personal-browser)のPrivate設定と読み書き権限を確認済み。ソース配置と[macOS CI run #6](https://github.com/koyuuuuu/personal-browser/actions/runs/39704611315)が完了し、UIテスト・未署名IPA生成に成功。本人から支払い方法未登録と回答を得た。アカウントの利用量・予算をAPIで確認したものではない。

## 実際の連携確認結果

毎回のログインは不要。現在の連携とCLI認証で、追加ログインなしに対象リポジトリへアクセスできることを再確認した。以後はCodexが必要なCI起動・修正・IPA取得まで担当する。[継続運用](github-automation.ja.md)を参照。非公開のActions URLをブラウザで開く際のログインと、Codexの接続認証は別である。

`koyuuuuu`へのGitHub連携と、GitHub CLIでの同アカウントへの認証を確認した。非公開の`personal-browser`作成をCLIで実行したが、GitHubの作成APIが`403: Resource not accessible by integration`を返し、作成できなかった。ユーザーの許可不足ではなく、現在の連携に与えられたGitHub側の権限による制限である。

連携はリポジトリ選択式（`selected`）。ユーザーによる作成後、対象の非公開リポジトリへアクセスできることを確認した。全リポジトリへのアクセス許可は必要ない。

配置先は`https://github.com/koyuuuuu/personal-browser`。パスワードやトークンをチャットに貼る必要はない。リポジトリ作成・ソース配置は完了。CIのログを確認して修正し、ビルド・テスト・IPA生成に成功した。実機検証はこれから。

参考: [リポジトリ作成APIと必要な権限](https://docs.github.com/en/rest/repos/repos#create-a-repository-for-the-authenticated-user)。

## 配置先

今回の配置先は作成済みの`koyuuuuu/personal-browser`。以下は別環境へ作り直す場合の手順。

GitHub画面で新規作成する場合は[New repository](https://github.com/new)を開き、以下を指定する。

- Owner: 使用する個人アカウント。
- Repository name: `personal-browser`（別名でもよい）。
- Visibility: **Private**。
- 初期ファイル: 既存コードがない場合はREADMEを1つ作っておくと、GitHub連携から初回コミットを配置しやすい。

現在利用できるGitHub連携には、リポジトリ新規作成やアカウントの課金設定変更の機能がない。作成が必要な場合はGitHub画面で行い、URLを伝える。GitHubの接続がリポジトリを選択式で許可する方式なら、新しいリポジトリも対象に追加する。

## 無料枠と有料利用の停止

GitHubの本人のアカウント設定でBillingのUsageとBudgetsを確認する。

1. 契約プランと今月のActions無料枠の残りを確認する。他リポジトリの使用も含む。
2. 支払い方法がある場合は、Actionsと関連ストレージについて、有料の追加利用を許可しない予算設定を確認する。通知だけでなく、`Stop usage when budget limit is reached`を有効にする。
3. 支払い方法がなく、GitHubが無料枠の超過使用をブロックする状態なら、その状態を維持する。有料化するためのカード登録はこの開発手順に含めない。
4. 今回は支払い方法未登録という本人の回答に基づきCIを実行する。パスワード、トークン、カード番号、Apple Accountの認証情報をチャットに貼る必要はない。

停止設定はGitHubアカウント側で行う。リポジトリのワークフローだけで、月の残り枠や課金停止設定を検証・変更することはできない。GitHubの現在の予算画面で利用できる設定に従い、追加有料利用が許可されている間はCIを実行しない。

参考: [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)、[Product usage included](https://docs.github.com/en/billing/reference/product-usage-included)。

## 初回配置と実行

Privateであることとアクセス権を確認し、ソースを配置する。今回は支払い方法未登録との回答を受け、CI実行へ進んだ。
2026-10-24の自動配信要件により、mainへのアプリ・ビルド・配信コードのpushでLinux検査とmacOS検証・IPA生成を開始する。文書だけの変更や保管・配布ブランチの変更では開始しない。手動実行も可能だが、同じSHAのpush実行と重複させない。

公開するのは専用のpersonal-browser-distributionに置くIPA・JSON・アイコンのみ。ソース側はPrivateを維持する。公開配布先へのContents書き込みだけを許可したDISTRIBUTION_TOKENを非公開側のActions Secretsへ保存する。[配信構成と初回設定](distribution.ja.md)を参照。

成果物の一時保持は1日。配布版のIPAはReleaseに残す。毎週の署名RefreshにはmacOSビルドもGitHubログインも不要。
