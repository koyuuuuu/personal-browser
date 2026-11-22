import SwiftUI

@MainActor
struct AudioMixingSettingsView: View {
    @ObservedObject private var audio = AudioMixingController.shared
    @ObservedObject private var background = BackgroundAudioController.shared
    var body: some View {
        Form {
            Section {
                Toggle("ホーム画面でも動画の音声を継続", isOn: Binding(get: { background.enabled }, set: { background.setEnabled($0) }))
                    .accessibilityIdentifier("backgroundAudioToggle")
            } header: { Text("バックグラウンド再生") } footer: {
                Text("再生中の動画を保ったまま、iPhoneのホーム画面へ戻っても音声を継続します。手動停止・通話・イヤホン切断後は自動で再開しません。サイトやiOSの制約で継続できない場合があります。")
            }
            if let error = background.message { Section { Text(error).foregroundStyle(.orange) } }
            Section {
                Toggle("複数音源の同時再生を優先", isOn: Binding(get: { audio.enabled }, set: { audio.setEnabled($0) }))
                    .accessibilityIdentifier("concurrentAudioToggle")
                Toggle("Web音声を非排他モードにする", isOn: Binding(get: { audio.nonExclusiveWebAudio }, set: { audio.setNonExclusiveWebAudio($0) }))
                    .disabled(!audio.enabled).accessibilityIdentifier("nonExclusiveWebAudioToggle")
            } footer: {
                Text("再生前に他アプリとの音声ミックスを準備し、対応するページへ非排他の音声セッションを要求します。再生中のタブは保持します。それぞれの音源は手動で再生してください。オフでは従来の再生方式を使います。")
            }
            Section("対応範囲と制約") {
                Text("複数タブ・ページ内の音声、Apple Musicなどとの同時再生を試せますが、iOS・WebKit・サイト・他アプリの排他制御により停止する場合があります。YouTube、DRM、全画面動画、PiPを含む全ての組み合わせの同時再生は保証できません。")
                Text("バックグラウンドへ移る際は、対象動画の音声継続を非排他モードより優先します。前面へ戻ると元のWeb音声モードに戻します。既に止まった音源は手動で再開してください。")
                Text("この設定は他アプリの音声設定やサイトの停止命令を変更しません。停止した音源の強制再開や、音声・動画の自動再生は行いません。")
            }
            if let error = audio.errorMessage { Section { Text(error).foregroundStyle(.orange) } }
        }
        .navigationTitle("音声・バックグラウンド再生")
    }
}
