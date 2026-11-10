import SwiftUI

@MainActor
struct PasswordSaveBanner: View {
    @ObservedObject var tab: BrowserTab
    let allowed: Bool
    @ObservedObject private var forms = PasswordFormController.shared
    @ObservedObject private var vault = PasswordVault.shared
    @Environment(\.scenePhase) private var phase
    @State private var accountID: UUID?
    @State private var busy = false
    @State private var error = false
    private var offer: PasswordSaveOffer? {
        guard let value = forms.saveOffer, value.tabID == tab.id, Date() < value.expiresAt,
              !tab.isPrivate, let url = tab.url, (try? PasswordOrigin(url)) == value.record.site else { return nil }
        return value
    }
    private func proposal(_ value: PasswordSaveOffer) -> PasswordSavePolicy.Proposal? {
        guard vault.unlocked else { return nil }
        return try? PasswordSavePolicy.proposal(value.record, records: vault.records,
            passwordChange: value.passwordChange, accountID: accountID)
    }
    var body: some View {
        VStack(spacing: 0) {
            if let offer, allowed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(offer.record.site.host) のパスワードを保存・更新しますか？")
                        .font(.callout).accessibilityIdentifier("passwordSaveOfferTitle")
                    Text("送信した内容の保存です。ログインや変更の成功を確認してから確定してください。")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        if vault.unlocked {
                            if proposal(offer) == .chooseAccount {
                                Menu("更新するアカウント") {
                                    ForEach(vault.records.filter { $0.site == offer.record.site }) { record in
                                        Button(record.username.isEmpty ? "ユーザー名なし" : record.username) { accountID = record.id }
                                    }
                                }.accessibilityIdentifier("passwordUpdateAccountMenu")
                            } else {
                                Text(displayUsername(offer))
                                    .font(.caption).lineLimit(1)
                                Button(actionTitle(proposal(offer))) {
                                    do { try forms.acceptSaveOffer(offer.id, tab: tab, accountID: accountID) }
                                    catch { error = true }
                                }.buttonStyle(.borderedProminent).accessibilityIdentifier("confirmPasswordSaveButton")
                            }
                        } else {
                            Button("認証して保存内容を確認") { unlock(offer.id) }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("unlockPasswordSaveButton")
                        }
                        Spacer(minLength: 0)
                        Button("今回はしない") { forms.dismissSaveOffer() }
                            .accessibilityIdentifier("dismissPasswordSaveButton")
                    }
                }.padding(8).background(.regularMaterial).privacySensitive()
                    .opacity(phase == .active ? 1 : 0).disabled(busy || phase != .active || !tab.passwordPageTrusted)
            }
        }
        .onChange(of: forms.saveOffer?.id) { _, _ in accountID = nil }
        .onChange(of: tab.url) { _, _ in forms.keepSaveOffer(for: tab) }
        .onChange(of: tab.id) { _, _ in forms.keepSaveOffer(for: tab) }
        .alert("保存できませんでした", isPresented: $error) {
            Button("OK", role: .cancel) {}
        } message: { Text("ページと保管庫の状態を確認してください。") }
    }
    private func displayUsername(_ offer: PasswordSaveOffer) -> String {
        let username: String
        switch proposal(offer) {
        case .update(let value), .insert(let value): username = value.username
        default: username = offer.record.username
        }
        return username.isEmpty ? "ユーザー名なし" : username
    }
    private func actionTitle(_ proposal: PasswordSavePolicy.Proposal?) -> String {
        switch proposal {
        case .update: "更新"
        case .unchanged: "保存済み"
        default: "保存"
        }
    }
    private func unlock(_ id: UUID) {
        guard !busy else { return }; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await vault.unlock()
                forms.keepSaveOffer(for: tab)
                guard let current = forms.saveOffer, current.id == id else { return }
                if proposal(current) == .unchanged { forms.dismissSaveOffer() }
            } catch { error = true }
        }
    }
}
