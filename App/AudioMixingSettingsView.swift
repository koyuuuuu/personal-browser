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
                Text("再生中のタブを保持し、Web音声の非排他モードがオンなら他アプリとの同時再生を優先します。それぞれの音源は手動で再生してください。音量ゼロやサイトのミュートはそのままです。")
            }
            Section("対応範囲と制約") {
                Text("複数タブ・ページ内の音声、Apple Musicなどとの同時再生を試せますが、iOS・WebKit・サイト・他アプリの排他制御により停止する場合があります。YouTube、DRM、全画面動画、PiPを含む全ての組み合わせの同時再生は保証できません。")
                Text("Web音声の非排他モードは、WebKitの仕様により消音スイッチに従う場合があります。消音中の再生を優先する場合は非排他モードをオフにしてください。他アプリの排他制御や、背景・全画面での同時再生は保証できません。")
                Text("この設定は他アプリの音声設定やサイトの停止命令を変更しません。停止した音源の強制再開や、音声・動画の自動再生は行いません。")
            }
            if let error = audio.errorMessage { Section { Text(error).foregroundStyle(.orange) } }
        }
        .navigationTitle("音声・バックグラウンド再生")
    }
}
