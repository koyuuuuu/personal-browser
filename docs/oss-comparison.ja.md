# OSSベースの詳細比較と採用案

調査日: 2026-10-21。対象端末: iPhone 12 / iOS 18.4.1。
状態: 以下は採用前の比較記録。2026-10-22（日本時間）にユーザーが新規SwiftUI＋WKWebViewを選択した。候補のソースを読み、ビルド設定・権限・依存関係を確認したが、候補間のmacOSコンパイル時間、IPA容量、無料署名後の起動は未計測。

## 選択の要点

**既存OSSをベースにするならFirefox iOSの開発用Fennec構成を第一候補とする。** タブ、履歴、ブックマーク、ダウンロード等の既存機能を残せるため、日常利用に必要な機能を作り直す量が小さい。ただし、そのまま無料署名で使えるという意味ではない。最初の開発目標は、UI改造に先立つ「無料署名対応版の起動とデータ保持の確認」にする。

UIと操作体系を根本から自由に設計することを最優先するなら、新規SwiftUI/WKWebView構成にも利点がある。既存Firefoxを選ぶ場合はUIKitを許容し、必要な画面からSwiftUIを追加する。最初から全画面をSwiftUIへ書き換えると、既存OSSの利点が薄れる。

## 比較

表の「負担」はソース構成からの評価であり、実測した工数ではない。

| 候補 | 日常ブラウザ機能 | UIの自由度と変更箇所 | 無料署名への調整 | 継続保守 | 今回の評価 |
|---|---|---|---|---|---|
| Firefox iOS / Fennec | タブ・履歴・ブックマーク・ダウンロード等の土台がある | UIKit主体。Toolbar、Browser画面、TabManager、Redux等に分かれ、広いUI変更は複数層に及ぶ | App Group、Push、既定ブラウザ等を整理。拡張を外すだけでなく共有ストレージ利用を修正 | 上流の更新は活発。独自変更が多いほどマージが増える | **既存OSSなら第一候補** |
| Firefox Focus iOS | 閲覧と追跡防止が中心。Firefox同等のタブ・履歴・保存構成を前提にできない | BrowserViewController中心のUIKitと一部SwiftUI。小さいがプライバシー用途の設計 | Siri、App Group、Content Blocker等を整理 | Firefoxと同一monorepoで保守。日常用の永続データを追加すると独自部分が増える | 単一ページ・使い捨て閲覧が中心なら候補 |
| DuckDuckGo iOS | タブ、履歴、ブックマーク等の豊富な土台 | UIKit/SwiftUI混在。MainViewControllerは調査時点で約1万行あり、サービスとの接点が多い | 多数のApp Group、AutoFill、Network Extension、既定ブラウザ等を整理。専用フォントの私有依存も除去 | iOS/macOS共通部と製品サービスへの追随が必要 | Firefoxより今回の利点が小さい |
| Brave iOS（現行brave-core内） | 高機能。ブロック機能等もある | SwiftのUIに加えBraveCoreとの接点がある | 署名・拡張・Brave固有機能の整理が必要 | Chromium系の取得・ネイティブ構成まで含む重いビルド系 | 無料クラウドCI中心では不利 |
| DuckDuckGo BareBonesBrowser | 動作確認用の最小ブラウザ | SwiftUIで小さく読みやすい | 本体の構成は比較的単純 | テスト・トリアージ用途で、日常用製品の保守を期待できない | 学習・試作にはよいが、採用利点は小さい |
| 新規SwiftUI/WKWebView | 基本機能から段階的に作る | 最も設計しやすい | 最初から本体1ターゲット・通常サンドボックスで設計可能 | 上流UIとの競合はない。機能互換性は自分で検証 | UIの自由度を最大化する案 |

## Firefox iOS: 具体的に確認したこと

調査固定コミット: `d051e7e844992d153a93e8786f5a1fdba20a82c0`。

- [開発用README](https://github.com/mozilla-mobile/firefox-ios/blob/d051e7e844992d153a93e8786f5a1fdba20a82c0/firefox-ios/README.md) は `Fennec` schemeを指定する。公式配布用Firefox構成をそのまま模倣する必要はない。
- [Fennec.xcconfig](https://github.com/mozilla-mobile/firefox-ios/blob/d051e7e844992d153a93e8786f5a1fdba20a82c0/firefox-ios/Client/Configuration/Fennec.xcconfig) にはMozillaのBundle ID、developer channel、開発用フラグがある。個人用Bundle ID・表示名・設定を別構成にまとめる。
- [FennecApplication.entitlements](https://github.com/mozilla-mobile/firefox-ios/blob/d051e7e844992d153a93e8786f5a1fdba20a82c0/firefox-ios/Client/Entitlements/FennecApplication.entitlements) には、Push、AutoFill Provider、multipath、App Group、Keychain Group、既定ブラウザ等の権限がある。**Fennecも無料署名向け最小構成ではない。**
- [Xcode project](https://github.com/mozilla-mobile/firefox-ios/blob/d051e7e844992d153a93e8786f5a1fdba20a82c0/firefox-ios/Client.xcodeproj/project.pbxproj) にはShareTo、ActionExtension、CredentialProvider、NotificationService、WidgetKitExtension等のターゲットがある。個人用schemeから不要なターゲット依存・埋め込みフェーズを外す。
- 同プロジェクトの直接のリモートSPM参照にはGlean、Sentry、Kingfisher、Fuzi、GCDWebServer、swift-certificates、ModifiedCopyMacro等がある。これは依存全体の件数ではない。RustMozillaAppServicesやローカルパッケージも存在する。
- [bootstrap.sh](https://github.com/mozilla-mobile/firefox-ios/blob/d051e7e844992d153a93e8786f5a1fdba20a82c0/bootstrap.sh) はNodeの依存解決・JSビルドに加え、別リポジトリのスクリプトを取得する。上流commitだけの固定では依存取得全体は再現可能にならない。採用後にロックファイルと取得するスクリプトの参照を点検する。
- [TabManagement](https://github.com/mozilla-mobile/firefox-ios/tree/d051e7e844992d153a93e8786f5a1fdba20a82c0/firefox-ios/Client/TabManagement)、[Browser UI](https://github.com/mozilla-mobile/firefox-ios/tree/d051e7e844992d153a93e8786f5a1fdba20a82c0/firefox-ios/Client/Frontend/Browser) が拡張の主要な入口になる。

無料署名対応で特に重要なのは、App Groupのentitlement削除後に、共有ディレクトリ・共有UserDefaults・共有Keychainを本体のサンドボックスへ移すこと。コード上の前提を残すと、ビルドできてもデータが保存できない、または起動時に失敗する可能性がある。調査段階では個々のアクセス箇所をすべて監査済みではない。

MozillaのSync、実験配信、テレメトリー、クラッシュ送信は個人用ビルドで無効にする方針。ライブラリの削除は機能フラグによる無効化と分け、起動・閲覧を確認してから必要に応じて行う。Mozillaアカウントやサービスを自分の個人アプリからそのまま利用できるとは仮定しない。

ライセンスはMPL-2.0。改変した対象ファイルの配布時の扱い、依存ライセンス表示、商標は別々に確認する。個人用の名称・アイコンに変更し、Mozillaの公式製品と誤認される配布をしない。ライセンスの存在とブランドの自由使用は同じではない。

## Focusと軽量ライブラリについて

Focusの現行ソースは[firefox-ios内](https://github.com/mozilla-mobile/firefox-ios/tree/d051e7e844992d153a93e8786f5a1fdba20a82c0/focus-ios)にある。旧focus-iosを起点にしない。[Focus権限](https://github.com/mozilla-mobile/firefox-ios/blob/d051e7e844992d153a93e8786f5a1fdba20a82c0/focus-ios/Focus.entitlements)にもApp Group等がある。見た目が軽いことだけで無料署名が簡単とは判断しない。

Mozillaの[SampleBrowser](https://github.com/mozilla-mobile/firefox-ios/blob/d051e7e844992d153a93e8786f5a1fdba20a82c0/SampleBrowser/README.md)は上流自身が製品向けではない技術プレビューと説明している。BrowserKit/WebEngineの部品だけを使う案も、安定した独立ライブラリとしての保証を別に確認する必要がある。

[BareBonesBrowser](https://github.com/duckduckgo/BareBonesBrowser/tree/fb4b7d592d8cd2d2450877eca6c3f131bd817f0c)はSwiftUIでApache-2.0だが、[README](https://github.com/duckduckgo/BareBonesBrowser/blob/fb4b7d592d8cd2d2450877eca6c3f131bd817f0c/README.md)でテスト用途と明記され、アプリは非永続Webデータストアを使う。[WebView.swift](https://github.com/duckduckgo/BareBonesBrowser/blob/fb4b7d592d8cd2d2450877eca6c3f131bd817f0c/Sources/BareBonesBrowserKit/WebView.swift)ではSwiftUIのupdateでreloadし、暫定的な読み込み失敗でもreloadするため、日常利用向けにはライフサイクルやリトライ方針を変える必要がある。採用してもタブ・履歴・保存などをほぼ追加実装するので、新規実装との差が小さい。

## DuckDuckGoとBraveの注意点

[DuckDuckGo README](https://github.com/duckduckgo/apple-browsers/blob/cf5f29d0e50223f5597b0e88ccfab81fb53711dd/README.md)で、privateなDuckSansFontパッケージを外部開発者が外す手順を確認した。Apache-2.0のソースと専用フォントの権利は別。フォントを取得・転載する案は採らない。[本体entitlements](https://github.com/duckduckgo/apple-browsers/blob/cf5f29d0e50223f5597b0e88ccfab81fb53711dd/iOS/DuckDuckGo/DuckDuckGo.entitlements)にも多数の製品機能の権限がある。

Braveは旧brave-iosではなく[現行のios/brave-ios](https://github.com/brave/brave-core/blob/1be046a44537900c7b14a8d3b04de4c572df1870/ios/brave-ios/README.md)を比較した。公式手順はBraveCoreを先に初期化し、iOS用Xcodeプロジェクトからビルドする構成。Chromium系の取得やビルド環境まで含むため、今回の無料CI構成で最初に選ぶ理由は弱い。ただし「iOSのページ描画がChromiumだから重い」という意味ではない。

## 実装を始める場合の最初の到達点

Firefox採用の場合、最初から自由なUIの完成を約束せず、次の順序にする。

1. 公開可否とGitHubリポジトリを確認し、互換性を確認した上流commit/tagを固定する。調査対象mainを自動的に本番採用しない。
2. 上流状態のSimulatorビルドを成功させ、環境問題と改変の問題を区別できる基準を残す。
3. 個人用scheme、Bundle ID、表示名、アプリ本体だけのビルドを用意する。不要な権限と共有ストレージ利用を対応づけて整理する。
4. 未署名arm64 IPAをCIで生成し、SideStore経由でiOS 18.4.1に入れて起動・保存・再署名を検証する。
5. ツールバー位置、ボタン順、ジェスチャー等を設定モデルで変えられるようにし、独自UIを段階的に追加する。
6. 上流更新用ブランチと個人用機能のコミットを分け、定期的な取り込みをCIで検査する。

ビルド失敗時はログを保存しCodexが修正できる形にする。上流更新の追随やエラーの自動修正のために、課金されるAI APIを黙って追加しない。

## 未決事項

- ベース: 新規SwiftUI＋WKWebViewに決定済み。
- GitHubへの公開可否、ユーザー名、リポジトリ名。まだユーザーアカウントへ変更していない。
- 希望する最初のUI変更。採用・無料署名対応の検証後に具体化する。

候補間のビルド時間・メモリ・IPA容量は、同一macOSランナーで測定するまでは数値比較しない。全候補をビルドするためにユーザーのCI枠を消費することは、承認前には行わない。
