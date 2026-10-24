import SwiftUI

@MainActor
struct UpdateSettingsView: View {
    @EnvironmentObject var updates: UpdateChecker

    var body: some View {
        Form {
            Section {
                Toggle("アプリ内の更新通知", isOn: $updates.enabled)
                    .accessibilityIdentifier("updateNotificationsToggle")
            } footer: {
                Text("オンにすると起動中に1日1回まで更新を確認します。オフでは自動通信も通知も行いません。アプリの更新・署名はSideStoreで行います。")
            }
            Section {
                Button("今すぐ更新を確認") { Task { await updates.check() } }
                    .disabled(updates.checking)
                if updates.checking { ProgressView("確認中…") }
                if let status = updates.status { Text(status).font(.callout) }
                Button("SideStoreを開く") { updates.openSideStore() }
                Button("配信ソースURLをコピー") { UIPasteboard.general.string = updates.sourceAddress }
            } header: { Text("SideStoreのソース") }
            footer: { Text("初回だけ、コピーしたURLをSideStoreのソースに追加してください。次回以降はSideStoreから既存アプリを削除せずに更新できます。") }
            Section("現在のアプリ") {
                LabeledContent("バージョン", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("ビルド", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                Text("更新や旧版への切り替えでも、最新の履歴とブックマークを保持します。アプリは削除せず、同じApple AccountでSideStoreから更新してください。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("アプリの更新")
        .task(id: updates.enabled) {
            if updates.enabled { await updates.check(automatically: true) }
        }
    }
}
