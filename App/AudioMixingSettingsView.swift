import SwiftUI

@MainActor
struct AudioMixingSettingsView: View {
    @ObservedObject private var audio = AudioMixingController.shared
    var body: some View {
        Form {
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
                Text("非排他モードでは消音スイッチや画面ロック・バックグラウンドで音が止まる場合があります。その場合はWeb音声の非排他モードをオフにしてください。既に止まった音源は手動で再開してください。")
                Text("この設定は他アプリの音声設定やサイトの停止命令を変更しません。停止した音源の強制再開や、音声・動画の自動再生は行いません。")
            }
            if let error = audio.errorMessage { Section { Text(error).foregroundStyle(.orange) } }
        }
        .navigationTitle("音声の同時再生")
    }
}
