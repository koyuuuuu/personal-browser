# 非公開GitHubへの配置前の設定

2026-10-22（日本時間）。非公開・無料枠内・超過時停止の方針に決定済み。
ユーザーが作成した[koyuuuuu/personal-browser](https://github.com/koyuuuuu/personal-browser)のPrivate設定と読み書き権限を確認済み。アカウントの利用量・課金停止設定は確認待ち。クラウドCIはまだ実行していない。

## 実際の連携確認結果

`koyuuuuu`へのGitHub連携と、GitHub CLIでの同アカウントへの認証を確認した。非公開の`personal-browser`作成をCLIで実行したが、GitHubの作成APIが`403: Resource not accessible by integration`を返し、作成できなかった。ユーザーの許可不足ではなく、現在の連携に与えられたGitHub側の権限による制限である。

連携はリポジトリ選択式（`selected`）。ユーザーによる作成後、対象の非公開リポジトリへアクセスできることを確認した。全リポジトリへのアクセス許可は必要ない。

配置先は`https://github.com/koyuuuuu/personal-browser`。パスワードやトークンをチャットに貼る必要はない。リポジトリ作成は完了しており、CI実行と実機検証はこれから。

参考: [リポジトリ作成APIと必要な権限](https://docs.github.com/en/rest/repos/repos#create-a-repository-for-the-authenticated-user)。

## 配置先

既存の専用リポジトリがあれば、そのURLを指定する。まだない場合の名前は`personal-browser`を提案する。

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
4. 設定を確認したことを共有する。パスワード、トークン、カード番号、Apple Accountの認証情報をチャットに貼る必要はない。

停止設定はGitHubアカウント側で行う。リポジトリのワークフローだけで、月の残り枠や課金停止設定を検証・変更することはできない。GitHubの現在の予算画面で利用できる設定に従い、追加有料利用が許可されている間はCIを実行しない。

参考: [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)、[Product usage included](https://docs.github.com/en/billing/reference/product-usage-included)。

## 初回配置と実行

Privateであることとアクセス権を確認し、ソースを配置する。停止設定の確認は、その後のCI実行前に必要。
現在のワークフローはLinux・macOSとも手動起動だけに限定し、コードを置いただけでは実行しない。

最初に軽量チェックを手動実行し、その後macOSの`iOS tests and unsigned IPA`を1回実行する。エラー修正はログを確認し、必要な再実行だけ行う。使用時間と成果物容量を測定し、残り無料枠に応じて頻度を決める。

課金停止設定が確認できたら、必要に応じてLinux検査にpush/PRトリガーを追加して自動化する。macOSは手動実行、成果物保持は1日のまま。
