# 0.9.0：音声の同時再生を優先する設定

「設定 → 音声の同時再生」に次を追加した。

- **複数音源の同時再生を優先**：初期オフ。オンでは再生前にAVAudioSessionへplayback／mixWithOthersを設定し、他アプリと混ぜられるセッションを準備する。音が出るメディアの開始時にアクティブ化を要求する。
- **Web音声を非排他モードにする**：上記をオンにすると利用可能。初期オン。対応するWebKitでは公開のnavigator.audioSession.typeへambientを要求する。画面ロック・消音スイッチ・背景再生との相性が悪ければ、こちらだけオフにしてネイティブ側のミックス準備を使える。

各音源は手動で再生する。複数タブ、同じページの複数audio要素、Apple Music等との同時再生を試せる。元から再生中のHTMLメディアを保持する仕組みを維持し、オンではWKWebViewの公開requestMediaPlaybackStateも使って、再生中と報告されたWebViewを保持する。読み込んでいないタブを一斉に起動しない。

設定は独立したUserDefaultsキーへ保存し、タブ・履歴・ブックマーク・Cookieや既存設定の形式を変えない。オフで従来のbuild14由来のmediaScript／updateMediaを使う。この2つは0.8.0から変更していない。切替時に音声セッションを非アクティブ化せず、プレーヤーのplay／pauseを置き換えたり、止まった音源を勝手に再開したりしない。追加するミックス準備では、録音・通話用のセッションを上書きしない。

## できることの境界

これは**公開APIで同時再生を優先する要求**であり、全サイト・全動画・全アプリを強制的に同時再生する機能ではない。

- iOSのWebKitには音声付き動画の同時再生を制限する経路があり、通常のaudio要素が複数動くことからYouTube動画も複数動くとは判断できない。
- YouTubeの再生ポリシー、サイトが行うpause、DRM、ネイティブ全画面、PiP、iOSや他アプリ側の排他・割り込みは解除できない。サイト・OSの版や音源の組合せによって停止する。
- ambientのWeb Audio Sessionは非排他だが、消音スイッチ・ロック・バックグラウンド再生の扱いも変わり得る。問題がある場合はWeb側の設定だけオフにする。API未対応やPermissions Policyによる拒否時にはネイティブ側の準備だけで動作する。
- オフも従来どおりmixWithOthersを再生開始後に要求するので、同時再生を禁止するスイッチではない。オンは開始前の準備とWeb側の非排他要求を追加する。
- コントロールセンターの再生操作や出力先はiOSが制御する。全音源の独立した操作や、複数PiPウィンドウは提供しない。音源数が増えるとメモリ・電池・通信の消費が増える。

Apple Musicを先に再生してからブラウザで各音源を開始する順序を試せる。停止した音源は手動で再開する。実機でのYouTube・Apple Music・他アプリ・全画面・ロック・PiPの組合せは個別の確認対象とし、Simulatorのaudio要素テストから成功を推定しない。

## 実装と確認範囲

隔離ワールドへのJavaScript実行は、約10行のObjective-Cブリッジで同じ公開APIを直接呼ぶ。SDKのSwift補助ライブラリlibswiftWebKit.dylibを実行環境が読み込めない問題を避けるためで、非公開APIは使わない。

AudioMixingControllerが公開AVAudioSession、WKUserScriptの隔離されたdefaultClientワールド、navigator.audioSession、WKWebView.requestMediaPlaybackStateを使う。ページ移動・再読込・BFCache復帰でもその時点の設定を取得する。非排他要求はページ全体に作用するので、トップ文書だけで設定・復元し、フレーム同士の競合を避ける。もとのタイプを保持し、オフで自分が設定したambientだけを戻す。ページのJavaScript、HTMLMediaElement.play/pause、AudioContextのコンストラクタは改変しない。

ネイティブUI検査は1ケースに限定し、実際のPCM音声を持つaudio要素2つの時間が同時に進むこと、別タブの音源を開始して戻っても再生が続くこと、明示したpauseを勝手に取り消さないこと、設定の再起動保持を確認する。スピーカーの波形や他アプリの音声ミックスをSimulatorから実証したとは扱わない。保存形式を変更していないため旧版データ往復の再実行は不要。

参考：

- https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers
- https://www.w3.org/TR/audio-session/
- https://github.com/WebKit/WebKit/blob/main/Source/WebCore/Modules/audiosession/DOMAudioSession.cpp
- https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/ios/MediaSessionManagerIOS.mm

## 配信結果

0.9.0 build52をSideStoreへ配信済み。Python52件・Core66件・関連UI1件と実機用ビルド、最新IPAの公開配信照合に成功。保存形式変更がないため旧版データ往復は再実行していない。音声要素の進行・タブ切替・停止操作・設定保持はSimulatorで確認し、Apple Music／YouTube／他アプリ／実機スピーカーの混音や全画面等は未確認。[配信記録](validation-0.9.0-2026-10-31.json)。
