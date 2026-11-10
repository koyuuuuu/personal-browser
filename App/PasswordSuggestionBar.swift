import SwiftUI

/// Own-vault candidates. The system's QuickType UI remains owned by iOS.
@MainActor
struct PasswordSuggestionBar: View {
    @ObservedObject var tab: BrowserTab
    let allowed: Bool
    let openVault: (PasswordPageRequest) -> Void
    @ObservedObject private var forms = PasswordFormController.shared
    @ObservedObject private var vault = PasswordVault.shared
    @Environment(\.scenePhase) private var phase
    @ScaledMetric private var rowHeight = 44.0
    @State private var busy = false
    @State private var pinned: PasswordFormTarget?
    @State private var error = false
    private var targets: [PasswordFormTarget] { forms.targets(for: tab).filter(\.currentPassword) }
    private var target: PasswordFormTarget? {
        let focused = targets.filter(\.focused)
        if busy { return pinned?.tabID == tab.id ? pinned : nil }
        return focused.count == 1 ? focused.first : nil
    }
    private var eligible: Bool {
        allowed && phase != .background && vault.showInputButton && tab.passwordOriginTrusted && (!tab.isPrivate || vault.allowPrivateFill)
    }
    private var accounts: [PasswordRecord] {
        guard vault.unlocked, let target else { return [] }
        return vault.records.filter { $0.site == target.site }
    }
    private struct Request: Hashable {
        let target: PasswordFormTarget?
        let revision: UUID
        let enabled: Bool
        let allowed: Bool
        let count: Int
    }
    var body: some View {
        VStack(spacing: 0) {
            if (eligible || busy), let target {
                HStack(spacing: 6) {
                    Label(target.site.host, systemImage: "key.fill")
                        .font(.caption).lineLimit(1).frame(maxWidth: 110)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if !vault.unlocked {
                                Button("保存済みパスワードを入力", systemImage: "lock.open") { unlockAndFill(target) }
                                    .accessibilityIdentifier("unlockAndFillPasswordButton")
                            } else {
                                ForEach(accounts) { record in
                                    Button(record.username.isEmpty ? "ユーザー名なしで入力" : record.username, systemImage: "person.crop.circle") {
                                        run(target) { token in try await forms.fill(record, into: target, interactionID: token) }
                                    }.accessibilityIdentifier("inlineSavedPasswordButton")
                                }
                                if accounts.isEmpty {
                                    Button("保存情報なし・登録", systemImage: "plus") { openVault(PasswordPageRequest(tab: tab)) }
                                }
                            }
                        }.font(.callout).buttonStyle(.bordered).padding(.vertical, 2)
                    }
                    Button { forms.dismissKeyboard(for: tab.id) } label: {
                        Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: rowHeight)
                    }.accessibilityLabel("キーボードを閉じる").accessibilityIdentifier("passwordKeyboardDismissButton")
                }
                .padding(.horizontal, 6).frame(height: max(44, rowHeight))
                .background(.bar).overlay(alignment: .top) { Divider() }
                .opacity(phase == .active ? 1 : 0) // Keep layout/responder stable during Face ID.
                .disabled(busy || phase != .active).privacySensitive()
            }
        }
        .task(id: Request(target: targets.count == 1 ? targets.first : nil, revision: vault.revision,
                          enabled: vault.automaticallyFill, allowed: allowed && phase == .active, count: targets.count)) {
            guard eligible, allowed, phase == .active, !busy, targets.count == 1, let target = targets.first,
                  let record = PasswordAutomaticFillPolicy.candidate(records: vault.records, site: target.site,
                    enabled: vault.automaticallyFill, unlocked: vault.unlocked, isPrivate: tab.isPrivate,
                    formCount: targets.count, isMainFrame: target.isMainFrame, eligible: target.eligibleForAutomaticFill) else { return }
            do { try await forms.fillAutomatically(record, into: target) }
            catch { /* No automatic authentication, repeated attempts or submit. */ }
        }
        .alert("入力できませんでした", isPresented: $error) {
            Button("OK", role: .cancel) {}
        } message: { Text("ページと保管庫の状態を確認して、入力欄を選び直してください。") }
    }
    private func unlockAndFill(_ target: PasswordFormTarget) {
        run(target) { token in
            try await vault.unlock()
            let values = vault.records.filter { $0.site == target.site }
            if values.count == 1, let value = values.first { try await forms.fill(value, into: target, interactionID: token) }
        }
    }
    private func run(_ target: PasswordFormTarget, _ action: @escaping @MainActor (UUID) async throws -> Void) {
        guard !busy else { return }; pinned = target; busy = true
        let token = forms.interactionID
        Task { @MainActor in
            defer { busy = false; pinned = nil }
            do { try await action(token) }
            catch { error = true }
        }
    }
}
