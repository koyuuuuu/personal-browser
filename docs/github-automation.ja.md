# GitHubへの毎回のログインを省く運用

更新日: 2026-10-24。対象は非公開の`koyuuuuu/personal-browser`。

## 採用する方法

現在のGitHub連携を継続使用し、依頼に応じたソース変更、コミット、CI起動、失敗ログ確認、修正、IPA取得をCodex側で行う。ユーザーが毎回GitHub画面へログインしてRun workflowを押す運用にはしない。今回も連携ツールとCLIの両方で、追加ログインなしに非公開リポジトリの読み取りに成功した。前回は同じ連携でコミットとmacOS CI実行、IPA取得まで成功している。

GitHubのブラウザログインと、Codexに接続済みのGitHub認証は別。前回案内した非公開Actions成果物のURLをブラウザで開くとGitHubログインが求められるが、Codexからの操作にも毎回ログインが必要なことを意味しない。

今後はCodexが成果物を取得・検査し、利用中のクライアントで開けるファイル参照または実在するワークスペースのファイルリンクを渡す。GitHub側のURLは検証記録・代替の取得方法として添える。ソースは非公開を維持し、本人が公開を承認したIPAと配信JSONだけを専用の公開リポジトリへ配信する。通常はSideStoreからGitHubへのログインなしで取得できる。ファイルリンクをiPhoneへ保存できるかはクライアントの対応に依存する。

## 選択肢の比較

| 方法 | 利用者の操作 | 今回の判断 |
|---|---|---|
| 現在のGitHub連携＋設定済みCLI認証 | 通常の開発作業はCodex側。接続失効等の場合のみ再接続 | 採用。追加の認証情報は不要 |
| Actions内の`GITHUB_TOKEN` | ジョブごとにGitHubが発行。ブラウザログイン不要 | 既存CIが利用。会話側の認証とは別 |
| 専用GitHub App | 初回のApp作成・権限・秘密鍵の管理が必要 | 現在の連携で足りているので追加しない |
| 公開配布先だけに限定したFine-grained token | 初回作成と期限切れ時の交換 | BROWSER_DISTRIBUTION_TOKENとして非公開側のActions Secretsに保存。コードやチャットには保存しない |
| 非公開成果物をブラウザで直接取得 | GitHubのブラウザセッションが必要 | 代替手段として残す |

Actionsの`GITHUB_TOKEN`はジョブ用の認証であり、会話が終了した後もCodexが常駐して修正し続ける仕組みではない。現在は依頼を受けて作業を実行する方式。イベント駆動のAI修復や常駐実行を追加する場合は、対応機能、認証、AIの利用枠と費用を別に検討する。公式Codex Actionを無料で無制限の自動修復とみなさない。

## 継続するための実行手順

1. 既存の連携で対象リポジトリを読み、認証が有効か確認する。読み取り可能なのに新規ログインを求めない。
2. 依頼された変更を実装し、必要な検査を行ってコミットする。
3. mainへのアプリ関連pushで自動CIが始まる。Codexは対象SHAの実行を確認し、重複する手動起動を避ける。文書のみの変更ではmacOSを使わない。
4. 失敗したらログ・画面添付を確認し、原因を修正して必要な再検証を行う。無限リトライは置かない。
5. 成功したIPAは非公開Releaseと公開の配布専用Releaseに保存し、配信JSONを更新する。Codexが取得可能性とハッシュを確認し、ユーザーはSideStoreで既存アプリを削除せず更新する。

この手順をリポジトリ直下の[AGENTS.md](../AGENTS.md)へ記載した。別のCodex作業でも参照できるが、新しい作業環境が同じ接続・権限を必ず引き継ぐことまでは保証しない。接続の解除、権限変更、認証失効等が発生した場合は、その時点で必要な再接続を案内する。

無料枠を抑えるため、必要なコード変更をまとめてpushし、定期ビルドや認証確認だけのmacOSビルドは追加しない。SideStoreとApple認証はユーザーのiPhone側で扱う。週ごとの署名更新にGitHubログインや新しいIPA生成は不要。

## 一次資料

- [OpenAI: Connecting GitHub to ChatGPT](https://help.openai.com/en/articles/11145903-connecting-github-to-chatgpt)
- [GitHub: GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)
- [OpenAI: Codex Action](https://github.com/openai/codex-action)
