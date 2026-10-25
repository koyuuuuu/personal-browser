# 洗浄済み履歴の公開先への移行

移行先は `koyuuuuu/personal-browser-public`。旧 `personal-browser` は非公開のまま保持する。旧コミットのキャッシュがある旧リポジトリ自体を公開しない。

移すものは、no-replyで洗浄したmain・distribution・ipa-archiveの3ブランチと配信済み9タグ。新旧ID対応表も含める。個人メールを含む古いオブジェクトや、履歴洗浄前のバックアップは移さない。

- SideStoreの配布先は従来のpersonal-browser-distributionを維持する。
- 新ソース側でActionsのカウンターが1から始まるため、IPAと配信検証の両方で1000を加えた番号を使う。初回はbuild1001となる。
- 配信済み8件の版情報をinherited-releases.jsonに固定。公開済みIPAを匿名で取得してハッシュを検証し、初期版も含めた9版を以後の配信JSONに残す。公開CIから旧非公開リポジトリを読む必要はない。
- Bundle IDとデータschemaは維持する。旧IPAと新旧ID対応も維持する。
- 新リポジトリのActions Secretには、配布先だけへのContents読み書きを許したBROWSER_DISTRIBUTION_TOKENが必要。旧リポジトリのSecret値を読み出してコピーすることはできない。新ソース側へ設定されるまでは、新版のRelease保存まで進み、既存SideStore配信は更新しない。

## 初回の作成

GitHub連携は新規リポジトリ作成APIで403となったため、本人が https://github.com/new で `personal-browser-public` をPublicとして作成する。README・.gitignore・Licenseは追加せず空で作成する。旧personal-browserはPrivateのまま。作成後、Codexが空であることを確認し、洗浄済みrefだけを送信して標準Actionsで再検証する。

公開までの準備コミットには個人メールを使用しない。元の非公開GitHubから直接mirror pushする操作は禁止する。
