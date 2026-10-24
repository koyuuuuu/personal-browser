import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmWebsiteClear = false
    @State private var confirmHistoryClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("アプリの更新") { UpdateSettingsView() }
                        .accessibilityIdentifier("updateSettingsLink")
                    NavigationLink("ブラウザ機能") { FeatureSettingsView(store: store) }
                        .accessibilityIdentifier("featureSettingsLink")
                    NavigationLink("データの取り込み・書き出し") { LibraryTransferView(store: store) }
                }
                Section("操作") {
                    NavigationLink("表示・操作") { PresentationSettingsView(store: store) }.accessibilityIdentifier("presentationSettingsLink")
                    Picker("縦画面のバーの位置", selection: setting(\.toolbarPosition)) {
                        Text("上").tag(ToolbarPosition.top)
                        Text("下").tag(ToolbarPosition.bottom)
                    }
                    .accessibilityIdentifier("toolbarPositionPicker")
                    Picker("検索エンジン", selection: setting(\.searchEngine)) {
                        ForEach(SearchEngine.allCases, id: \.self) { engine in
                            Text(engine.label).tag(engine)
                        }
                    }
                    Toggle("スワイプで戻る・進む", isOn: setting(\.swipeNavigation))
                }
                Section {
                    ForEach(store.snapshot.settings.actions) { action in
                        Label(action.label, systemImage: action.symbol)
                    }
                    .onMove { source, destination in
                        var settings = store.snapshot.settings
                        settings.actions.move(fromOffsets: source, toOffset: destination)
                        store.updateSettings(settings)
                    }
                    .onDelete { offsets in
                        var settings = store.snapshot.settings
                        settings.actions.remove(atOffsets: offsets)
                        store.updateSettings(settings)
                    }
                    let missing = BrowserAction.allCases.filter { !store.snapshot.settings.actions.contains($0) }
                    if !missing.isEmpty {
                        Menu("ボタンを追加", systemImage: "plus") {
                            ForEach(missing) { action in
                                Button(action.label, systemImage: action.symbol) {
                                    var settings = store.snapshot.settings
                                    settings.actions.append(action)
                                    store.updateSettings(settings)
                                }
                            }
                        }
                    }
                } header: { Text("ツールバーのボタン") }
                footer: { Text("編集から順序と表示を変更できます。メニューボタンは常に表示されます。") }
                Section("端末内のデータ") {
                    Button("閲覧履歴を消去", role: .destructive) { confirmHistoryClear = true }
                    Button("タブを閉じてWebサイトデータを消去", role: .destructive) { confirmWebsiteClear = true }
                        .disabled(store.isClearingData)
                    if store.persistenceBlocked {
                        Text("保存を停止しています。元のデータを退避して保存先を再作成できます。")
                            .foregroundStyle(.orange)
                        Button("保存データを退避・再作成") { store.recoverStorage() }
                    }
                }
                Section("このアプリ") {
                    LabeledContent("バージョン", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    LabeledContent("タブ上限", value: "\(BrowserStore.maximumTabs)")
                    Text("通常タブのURL・履歴・ブックマーク・設定を端末に保存します。プライベートタブも匿名通信にはなりません。手動で追加したブックマークは保存されます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .confirmationDialog("すべてのタブを閉じ、CookieとWebサイトデータを消去します。サイトからログアウトされます。", isPresented: $confirmWebsiteClear, titleVisibility: .visible) {
                Button("タブとWebサイトデータを消去", role: .destructive) {
                    store.clearWebsiteData()
                    dismiss()
                }
            }
            .confirmationDialog("閲覧履歴をすべて消去しますか？", isPresented: $confirmHistoryClear, titleVisibility: .visible) {
                Button("履歴を消去", role: .destructive) { store.clearHistory() }
            }
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<BrowserSettings, Value>) -> Binding<Value> {
        Binding {
            store.snapshot.settings[keyPath: keyPath]
        } set: { value in
            var settings = store.snapshot.settings
            settings[keyPath: keyPath] = value
            store.updateSettings(settings)
        }
    }
}
