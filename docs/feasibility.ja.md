# 実現性と技術選定

調査日: 2026-10-21。料金・署名制限・対応OSは変更されるため、実機導入時にも公式資料を確認する。

## 結論

Windowsで編集し、GitHub ActionsのmacOSでテスト・未署名IPA生成、WindowsとiPhoneでSideStoreを初期設定し、以後iPhoneで再署名する構成は実現可能。ただし本環境ではmacOSも実機も使えていないため、エンドツーエンドの成功を検証済みとはしない。

「無料で利用できる」と「完全放置で必ず動き続ける」は別の条件。後者はiOSの実行制御、Apple認証、SideStoreの互換性に左右される。失効時のWindowsからの復旧経路が必要。

| 要件 | 評価 | 条件 |
|---|---|---|
| Windowsだけを所有して開発 | 可能 | Apple SDKを使うコンパイル・SimulatorはクラウドmacOSに置く |
| UI・操作を自由に変更 | 可能 | SwiftUIで自前UI、WKWebViewでページ表示 |
| Safariアプリに依存しない | 可能 | Safariを呼び出すラッパーではなく独立したアプリ |
| AppleのWebKitからも独立 | 今回は対象外 | WKWebViewはOSのWebKitを使う。独自エンジンは別の大規模開発・許可要件 |
| 無料Apple Accountで実機利用 | 可能 | 7日以内に再署名。端末あたり同時3アプリ、App ID等の上限あり [1] |
| 無料で継続CI | 条件付き | 公開リポジトリ＋標準ランナー。非公開はプランの無料枠内 [2] |
| 完全自動の署名更新 | 保証不可 | SideStoreのバックグラウンド更新と端末側の定期実行を試験し、手動復旧も残す [3][4] |
| iOSの既定ブラウザに指定 | 無料構成の前提にしない | Appleのmanaged entitlementが必要。未署名IPAにキーを足すだけでは解決しない [5] |
| App Store / TestFlight | 無料構成の対象外 | Apple Developer Program等が必要 [1] |
| Codexによる無制限・無料の自動修復 | 保証不可 | 認証方式と利用枠に依存。公式Actions連携はAPIキー等を要求 [8][9] |

## ベースと技術の比較

以下は採用提案。ユーザーの確認前にFirefox等のコードを取り込まない。

| 案 | 利点 | この用途の負担 | 推奨 |
|---|---|---|---|
| SwiftUI + WKWebViewを新規実装 | UI・状態・操作の設計が簡単。アプリ拡張・外部依存を抑えられる | ダウンロード、認証ポップアップなどを段階的に実装する必要 | 第一候補 |
| Firefox iOS / Focus iOSをフォーク | 既存のブラウザ機能と多くのテスト | 大きな既存設計、ビルドセットアップ、サービスや権限の整理、ブランド差し替え、MPL対応 [6] | 高機能を早期に大量に必要とする場合 |
| Brave iOSをフォーク | 多機能 | 旧brave-iosリポジトリは2024年にarchiveされ、現在のソース先を使う必要がある [7]。個人用MVPには大きい | 初期候補から外す |
| Flutter / React Native | 他OSにもUIを展開しやすい | iOSビルドには結局macOSが必要。WKWebView連携のための層が増える | iPhone専用では利点が小さい |
| PWA | インストール・署名更新が簡単 | 任意サイトを自由に表示する汎用ブラウザにはiframe等の制約がある | 不適 |

技術選定の判断: UI変更の自由度を最優先するなら新規SwiftUI/WKWebView構成が有利。ユーザーの希望により既存OSSの詳細比較を追加し、既存OSSを採る場合はFirefox iOS / Fennecを第一候補とした。[詳細比較](oss-comparison.ja.md)を参照。ベースは未決定。どちらの案もOSのWebKitを使い、描画エンジン自作は行わない。

## 無料運用の設計

CIはApple認証情報を持たず、`CODE_SIGNING_ALLOWED=NO`で実機arm64アプリを生成し、`Payload/PersonalBrowser.app`をIPAにまとめる。これはそのままiPhoneへ入れられる署名済み成果物ではない。SideStoreが個人用に再署名してインストールする。

GitHub公式資料では公開リポジトリの標準ランナーは無料。アーティファクト保存は別に上限を意識し、短期間だけ保持する。非公開の場合は月間枠、macOSの消費、保存容量、既存リポジトリとの共用を確認する。古い記事の固定倍率だけで無料ビルド回数を約束しない。課金を許可する設定はユーザー自身が確認する。[2]

署名更新のためにCIを毎週回す必要はない。同じインストール済みアプリをSideStoreで再署名する。コード変更時だけ新しいIPAをビルドする。

SideStoreはアプリ本体とは別の導入・更新ツールとして扱う。SideStoreのソースコードやAGPLライブラリを本体へ組み込まない。無料署名枠はSideStoreと本アプリで2つ使用する。初期版にはShare Extension、Widget、App Group、iCloud、Push、既定ブラウザ権限などを追加しない。

## 検証の境界

1. この環境: ソース、設定、生成スクリプトの検査と、利用可能ならOS非依存Swiftテスト。
2. ユーザー確認後のGitHub: macOSビルド、Simulatorの単体/UIテスト、実機用IPA構造・アーキテクチャ検査。
3. ユーザーのiPhone: 起動、ページ表示、Cookie、再署名、7日をまたぐ連続利用、上書き更新でのデータ維持。

SimulatorではSideStore、無料Apple署名、実機の電池消費、VPNとの相性、実際のバックグラウンド再署名を証明できない。

## 一次資料

1. [Apple: Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)
2. [GitHub: Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)、[runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)
3. [SideStore: FAQ](https://docs.sidestore.io/docs/faq)
4. [SideStore: Prerequisites](https://docs.sidestore.io/docs/installation/prerequisites)、[Install](https://docs.sidestore.io/docs/installation/install)、[Common issues](https://docs.sidestore.io/docs/troubleshooting/common-issues)
5. [Apple: Preparing your app to be the default web browser](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser)
6. [Mozilla: firefox-ios README](https://github.com/mozilla-mobile/firefox-ios/blob/main/README.md)、[LICENSE](https://github.com/mozilla-mobile/firefox-ios/blob/main/LICENSE)
7. [Brave: archived brave-ios](https://github.com/brave/brave-ios)
8. [OpenAI: codex-action](https://github.com/openai/codex-action)
9. [OpenAI: Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
