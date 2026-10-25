# 共有したリンクをPersonal Browserで開く

0.5.0から利用可能。SideStore・無料Apple Accountのまま、追加のEntitlementなしで使えます。

## iPhoneのショートカットを一度作成する

1. Appleの「ショートカット」アプリで「＋」を押し、名前を「Personal Browserで開く」にします。
2. 詳細（ⓘ）で「共有シートに表示」をオンにします。入力タイプは「URL」と「SafariのWebページ」にします。
3. 「入力からURLを取得」を追加し、入力を「ショートカットの入力」にします。
4. 「リストから項目を取得」を追加し、「最初の項目」を選びます。
5. 「もし」で取得結果が「値がない」場合は「このショートカットを停止」を置きます。入力のない起動ではリンクを送信しません。
6. 「URLエンコード」で取得した**URL全体**をエンコードします（「デコード」ではありません）。
7. 「テキスト」に `mybrowser://open?url=` と入力し、その直後に手順6の結果を変数として挿入します。空白や改行は挟みません。
8. 「URLを開く」に手順7のテキストを渡します。

アクション名はiOSの言語・版により少し異なります。Safariなどの共有ボタンから「Personal Browserで開く」を選ぶと新しいタブで開きます。初回はiOSの起動確認が出る場合があります。アプリが終了中でもバックグラウンドでも受信します。タブ上限500では既存タブを消さずに上限を通知します。

例：`https://example.com/?a=1&b=2#part` は
`mybrowser://open?url=https%3A%2F%2Fexample.com%2F%3Fa%3D1%26b%3D2%23part` です。
`&`・`+`・`#`・日本語を含むリンクを壊さないため、エンコードはURL全体に一度だけ行います。HTTP/HTTPS以外、埋め込みID/パスワード、不正な入力は拒否します。

## デフォルトブラウザとの違い

通常のデフォルトブラウザ指定にはAppleの承認が必要な `com.apple.developer.web-browser` Entitlementを使います。無料Personal Team署名ではこの構成にできないため、今回登録するのは `mybrowser` のみです。iOSの既定ブラウザ一覧には追加されません。

このブラウザ内の「このタブで開く」「新しいタブで開く」は、そのサイトをブラウザ優先にします。「アプリで開く → 対応するアプリ」で起動に成功するとアプリ優先を記憶します。X/twitter、YouTube/youtu.beはそれぞれまとめます。iOS全体のUniversal Links設定を変更する機能ではありません。

今後はApp Intent「Personal BrowserでURLを開く」を実装すれば、上記のURLエンコードとテキスト連結を一つのショートカットアクションに置き換えられます。これもiOSの既定ブラウザ登録そのものを代替するものではありません。

参考：
- https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser
- https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app
- https://support.apple.com/guide/shortcuts/run-a-shortcut-from-another-app-apd163eb9f95/ios
