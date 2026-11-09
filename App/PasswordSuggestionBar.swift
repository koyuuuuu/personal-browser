import SwiftUI

/// Apple owns its credential list and authentication. This bar never reads it.
@MainActor
struct PasswordSuggestionBar: View {
    @ObservedObject var tab: BrowserTab
    let allowed: Bool
    let openVault: (PasswordPageRequest) -> Void
    @ObservedObject private var forms = PasswordFormController.shared
    @ObservedObject private var vault = PasswordVault.shared
    @Environment(\.scenePhase) private var phase
    @State private var busy = false
    @State private var status: String?
    @State private var dismissedDocument: String?
    private var targets: [PasswordFormTarget] { forms.targets(for: tab).filter(\.currentPassword) }
    private var target: PasswordFormTarget? {
        targets.first(where: \.focused) ?? targets.first(where: \.isMainFrame) ?? targets.first
    }
    private var context: String { target.map { $0.epoch.uuidString + $0.documentID } ?? "" }
    private var visible: Bool {
        allowed && phase == .active && vault.showInputButton && tab.passwordPageTrusted && target != nil && dismissedDocument != context
    }
    private var accounts: [PasswordRecord] {
        guard vault.unlocked, !tab.isPrivate || vault.allowPrivateFill, let target else { return [] }
        return vault.records.filter { $0.site == target.site }
    }
    private struct Request: Hashable {
        let target: PasswordFormTarget?
        let revision: UUID
        let enabled: Bool
        let visible: Bool
        let formCount: Int
    }
    var body: some View {
        Group {
            if visible, let target {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Label(target.site.host, systemImage: "key.fill").font(.caption).lineLimit(1)
                        Spacer()
                        Button { forms.dismissKeyboard(for: tab.id) } label: { Image(systemName: "keyboard.chevron.compact.down") }
                            .accessibilityLabel("キーボードを閉じる").accessibilityIdentifier("passwordKeyboardDismissButton")
                        Button { openVault(PasswordPageRequest(tab: tab)) } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("パスワード保管庫").accessibilityIdentifier("passwordInputButton")
                        Button { dismissedDocument = context } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("パスワード候補を閉じる")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button("Appleのパスワード", systemImage: "key") {
                                run { try await forms.focusForAppleAutoFill(target); status = "キーボード上の候補、または鍵のボタンから選択してください。" }
                            }.accessibilityIdentifier("applePasswordSuggestionButton")
                            if !vault.unlocked, !tab.isPrivate || vault.allowPrivateFill {
                                Button("ブラウザの保管庫で入力", systemImage: "lock.open") { unlockAndFill(target) }
                                    .accessibilityIdentifier("unlockAndFillPasswordButton")
                            }
                            ForEach(accounts) { record in
                                Button(record.username.isEmpty ? "ユーザー名なしで入力" : record.username, systemImage: "person.crop.circle") {
                                    run { try await forms.fill(record, into: target); status = "入力しました。ログインはページのボタンで行ってください。" }
                                }.accessibilityIdentifier("inlineSavedPasswordButton")
                            }
                            if vault.unlocked && accounts.isEmpty {
                                Button("保管庫へ登録・取り込み") { openVault(PasswordPageRequest(tab: tab)) }
                            }
                        }.buttonStyle(.bordered).font(.caption)
                    }
                    if let status { Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                }.padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.bar).overlay(alignment: .top) { Divider() }
                    .disabled(busy).privacySensitive().accessibilityIdentifier("passwordSuggestionBar")
            }
        }
        .task(id: Request(target: target, revision: vault.revision, enabled: vault.automaticallyFill, visible: visible, formCount: targets.count)) {
            guard visible, !busy, let target,
                  let record = PasswordAutomaticFillPolicy.candidate(records: vault.records, site: target.site,
                    enabled: vault.automaticallyFill, unlocked: vault.unlocked, isPrivate: tab.isPrivate,
                    formCount: targets.count, isMainFrame: target.isMainFrame, eligible: target.eligibleForAutomaticFill) else { return }
            do { try await forms.fillAutomatically(record, into: target) }
            catch { /* No repeated prompts, automatic unlocks, or retries. */ }
        }
        .onChange(of: context) { _, _ in status = nil }
        .onChange(of: vault.unlocked) { _, value in if !value { status = nil } }
    }
    private func unlockAndFill(_ target: PasswordFormTarget) {
        run {
            try await vault.unlock()
            let values = vault.records.filter { $0.site == target.site }
            if values.count == 1, let value = values.first {
                try await forms.fill(value, into: target); status = "入力しました。ログインはページのボタンで行ってください。"
            } else { status = values.isEmpty ? "保管庫へアカウントを登録・取り込みしてください。" : "入力するアカウントを下部の候補から選択してください。" }
        }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await action() }
            catch { status = "入力できませんでした。ページと保管庫の状態を確認してください。" }
        }
    }
}
