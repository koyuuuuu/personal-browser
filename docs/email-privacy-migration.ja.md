# メール非公開化と配信済み版の対応

全ブランチ・タグの作者／コミッターメールを `266257694+koyuuuuu@users.noreply.github.com` へ置き換える。通常のコミット履歴・ファイルから個人メールを除く。将来のCodex操作はリポジトリ設定と明示した作者・コミッターでno-replyを使用する。

`distribution/history-rewrite.json` は旧新コミット、各ref、配信済み版のIPA SHA-256と元のbuild-info SHA-256を記録する。元のIPAとbuild-info資産は差し替えず、記録内の古いsource_commitはこの対応表で新履歴へ解決する。互換性検査は新しい基準コミットを使う。配信済みタグのApp/Sources/Tests/UITests/Xcode projectのtreeは旧新で一致することを検査済み。

GitHubの古いオブジェクトの扱いには注意が必要。force pushだけでは、GitHub上の古いSHAによるキャッシュ参照が消えるとは限らない。旧SHAへアクセスすると個人メールが読める状態なら、この同じリポジトリを公開してよいとは扱わない。GitHub Supportへキャッシュ・参照の削除を相談するか、旧リポジトリを非公開のまま保持し、洗浄済み履歴だけを新しいリポジトリへ移す。後者でもタグ名・IPAハッシュと対応表は保持できる。

本人がGitHubのWeb画面や別PCからコミットする場合は、https://github.com/settings/emails の「Keep my email addresses private」と「Block command line pushes that expose my email」を有効にし、別PCのGitのuser.emailも上記no-replyへ設定する。アカウント設定はこの連携のAPIでは変更できない。

今後、古い履歴を持つcloneからmerge/pushしない。GitHub側を更新した後、古いcloneは取り直す。ローカルの元履歴バックアップは非公開の作業領域だけに保管し、公開リポジトリへアップロードしない。

参考: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository
