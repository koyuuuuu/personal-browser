import SwiftUI

@MainActor
struct AudioSourcesView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject private var audio = AudioSourcesController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var includeStopped = true
    @State private var reloadTab: BrowserTab?
    private var visible: [BrowserAudioSource] {
        audio.sources.filter { includeStopped || $0.playing || $0.muted || $0.mode == "gain" || $0.mode == "busy" || !$0.reason.isEmpty && $0.mode == "candidate" }
    }
    var body: some View {
        List {
            Section {
                Toggle("停止中の音源も表示", isOn: $includeStopped)
                Text("ページ内の音声・動画を個別に操作します。音量は元の音に対する0〜100%です。端末全体やApple Musicなど他アプリの音量は変更しません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if visible.isEmpty {
                Section { Text("検出した音源がありません。ページで音声・動画を再生してから開いてください。") }
            }
            ForEach(store.tabs.filter { tab in visible.contains { $0.tabID == tab.id } }) { tab in
                Section {
                    ForEach(visible.filter { $0.tabID == tab.id }) { source in
                        AudioSourceRow(source: source) {
                            store.select(tab)
                            audio.enable(source)
                            dismiss()
                        }
                    }
                    if audio.sources.contains(where: { $0.tabID == tab.id && $0.mode == "gain" }) {
                        Button("元の再生方式に戻す（ページ再読込）") { reloadTab = tab }
                            .accessibilityIdentifier("resetAudioRouteButton")
                    }
                } header: { Text((tab.isPrivate ? "プライベート · " : "") + tab.title) }
            }
            Section("対応範囲") {
                Text("個別ミュートは検出したプレーヤーに適用します。音量調整は対応する直接ファイルのみ、選んだ音源をCORS付きで読み直して有効にします。操作後はページ上の確認ボタンを押してください。")
                Text("YouTubeで一般的なBlob・MSE、ライブ、DRM、アプリ独自のWeb Audio、ネイティブプレーヤーには音量調整できません。全画面・PiP・バックグラウンドではiOSやサイトの制限が残ります。音量制御はページ再読込で解除されます。")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("音声ミキサー")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        .confirmationDialog("このタブのページを再読込しますか？", isPresented: Binding(get: { reloadTab != nil }, set: { if !$0 { reloadTab = nil } }), titleVisibility: .visible) {
            Button("再読込して制御を解除", role: .destructive) { reloadTab?.existingWebView?.reload(); reloadTab = nil }
            Button("キャンセル", role: .cancel) { reloadTab = nil }
        } message: { Text("このタブの音量制御が解除され、全ての音源が元の読込方式に戻ります。再生やページへの未送信の入力が中断される場合があります。保存済みデータは消去しません。") }
    }
}

@MainActor
private struct AudioSourceRow: View {
    let source: BrowserAudioSource
    let enable: () -> Void
    @ObservedObject private var audio = AudioSourcesController.shared
    @State private var level: Double
    @State private var editing = false
    @State private var lastSent = Date.distantPast
    init(source: BrowserAudioSource, enable: @escaping () -> Void) {
        self.source = source; self.enable = enable
        _level = State(initialValue: source.volume)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(source.label.isEmpty ? (source.kind == "video" ? "動画 " : "音声 ") + source.sourceID : source.label,
                  systemImage: source.kind == "video" ? "play.rectangle" : "waveform")
                .font(.headline)
            Text(source.playing ? "再生中" : "停止中").font(.caption).foregroundStyle(.secondary)
            Toggle("ミュート", isOn: Binding(get: { source.muted }, set: { audio.setMuted(source, $0) }))
                .accessibilityIdentifier("audioMute-" + source.sourceID)
            if source.mode == "gain" {
                HStack {
                    Slider(value: $level, in: 0...1, step: 0.01) { Text("音量") } onEditingChanged: { value in
                        editing = value
                        if !value { audio.setVolume(source, level) }
                    }
                    .accessibilityIdentifier("audioGain-" + source.sourceID)
                    .accessibilityValue("\(Int((source.actualVolume * 100).rounded()))%")
                    Text("\(Int((level * 100).rounded()))%")
                        .monospacedDigit().frame(width: 48).accessibilityIdentifier("audioLevel-" + source.sourceID)
                }
                if !source.reason.isEmpty { Button("ページで制御音源を再生", action: enable) }
            } else if source.mode == "candidate" {
                Button("音量調整を有効にする（音源再読込）", action: enable)
                    .accessibilityIdentifier("enableAudioGain-" + source.sourceID)
            } else if source.mode == "busy" {
                ProgressView("音源を確認中…")
            } else { Text("音量調整は非対応").font(.caption) }
            if !source.reason.isEmpty { Text(source.reason).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 6)
        .onChange(of: source.volume) { _, value in if !editing { level = value } }
        .onChange(of: level) { _, value in
            if Date().timeIntervalSince(lastSent) >= 0.06 {
                lastSent = Date(); audio.setVolume(source, value)
            }
        }
    }
}
