import SwiftUI
import UniformTypeIdentifiers

/// Snapshot the form identities before authentication/sheet presentation.
struct PasswordPageRequest {
    let targets: [PasswordFormTarget]
    let isPrivate: Bool
    @MainActor init(tab: BrowserTab) { targets = PasswordFormController.shared.targets(for: tab); isPrivate = tab.isPrivate }
}

@MainActor
struct PasswordVaultView: View {
    let page: PasswordPageRequest?
    @ObservedObject private var vault = PasswordVault.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var search = ""
    @State private var message: String?
    @State private var editing: PasswordRecord?
    @State private var deleting: PasswordRecord?
    @State private var importing = false
    @State private var recoveryPicker = false
    @State private var incoming: PasswordImportResult?
    @State private var replace = false
    @State private var backupSheet = false
    @State private var backupInput: Data?
    @State private var pendingRecovery: [PasswordRecord]?
    @State private var document = EncryptedPasswordDocument()
    @State private var exporting = false
    @State private var pendingExport = false
    @State private var confirmRecovery = false
    @State private var flow = UUID()
    @State private var busy = false
    private var matching: [PasswordRecord] {
        vault.records.filter { record in
            (search.isEmpty || record.site.display.localizedCaseInsensitiveContains(search) || record.username.localizedCaseInsensitiveContains(search) || record.title.localizedCaseInsensitiveContains(search))
        }.sorted { ($0.site.display, $0.username) < ($1.site.display, $1.username) }
    }
    var body: some View {
        Form {
            if !vault.unlocked {
                Section {
                    Label("保管庫はロック中です", systemImage: "lock.fill")
                    Button("保管庫を開く") { perform { try await vault.unlock() } }
                        .accessibilityIdentifier("unlockPasswordVaultButton")
                    if vault.needsRecovery { Text("暗号化ファイルは保持しています。同じ署名アカウントで開くか、暗号化バックアップから復元してください。") }
                    Button("暗号化バックアップから復元") { recoveryPicker = true; importing = true }
                }
            } else {
                pageSection
            #if DEBUG
            if PasswordVault.fixture, vault.unlocked {
                Button("検証CSVを読み込む") {
                    do { incoming = try PasswordCSV.parse(Data("name,url,username,password\nFixture,http://127.0.0.1:18765,fixture-user,fixture-secret\n".utf8)); replace = false }
                    catch { show(error) }
                }.accessibilityIdentifier("importPasswordFixtureButton")
            }
            #endif
                Section("保存済みアカウント（\(vault.records.count)件）") {
                    TextField("サイト・アカウントを検索", text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if matching.isEmpty { Text("保存されたパスワードはありません").foregroundStyle(.secondary) }
                    ForEach(matching) { record in
                        Button { editing = record } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title.isEmpty ? record.site.display : record.title).foregroundStyle(.primary)
                                Text(record.site.display).font(.caption).foregroundStyle(.secondary)
                                Text(record.username.isEmpty ? "ユーザー名なし" : record.username).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("passwordRecord-" + record.site.host)
                        .swipeActions { Button("削除", role: .destructive) { deleting = record } }
                    }
                    Button("アカウントを追加", systemImage: "plus") {
                        if let site = try? PasswordOrigin("https://example.com") { editing = PasswordRecord(site: site, username: "", password: "") }
                    }.accessibilityIdentifier("addPasswordRecordButton")
                }
                if let incoming {
                    Section("取り込み内容の確認") {
                        let preview = try? PasswordImportResult.merged(incoming.records, into: vault.records, replace: replace)
                        Text("読み取り \(incoming.records.count)件・対象外 \(incoming.skipped)件・確認コードを除外 \(incoming.ignoredCodes)件")
                        Text("重複 \(preview?.duplicates ?? 0)件・内容の異なる既存アカウント \(preview?.conflicts ?? 0)件")
                        Toggle("同じサイト・ユーザー名の既存内容を置換", isOn: $replace)
                        Button("確認して取り込む") {
                            do { try vault.importRecords(incoming.records, replace: replace); self.incoming = nil; message = "取り込みが完了しました。" }
                            catch { show(error) }
                        }.accessibilityIdentifier("confirmPasswordImportButton")
                        Button("取り消す", role: .cancel) { self.incoming = nil }
                    }
                }
                Section("取り込み・バックアップ") {
                    Button("Safari・Braveのパスワードを取り込む") { recoveryPicker = false; importing = true }
                    Button("暗号化バックアップを読み込む") { recoveryPicker = false; backupInput = nil; importing = true }
                    Button("暗号化バックアップを書き出す") { backupInput = nil; backupSheet = true }
                    Text("CSV、Safariの書き出しZIP、暗号化JSONに対応。重複は追加せず、既存内容は置換を選んだ場合だけ変更します。平文の書き出しは行いません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section { Button("今すぐロック", systemImage: "lock") { vault.lock() }.accessibilityIdentifier("lockPasswordVaultButton") }
            }
            Section("自動入力の設定") {
                Toggle("ログインフォームに入力ボタンを表示", isOn: Binding(get: { vault.showInputButton }, set: { vault.setShowInput($0) }))
                Toggle("プライベートタブでも入力を許可", isOn: Binding(get: { vault.allowPrivateFill }, set: { vault.setPrivateFill($0) }))
                Picker("自動ロック", selection: Binding(get: { vault.lockSeconds }, set: { vault.setLockSeconds($0) })) {
                    Text("30秒").tag(30); Text("1分").tag(60); Text("5分").tag(300)
                }
                Text("端末認証後にアカウントを選ぶと入力します。自動送信はしません。HTTPSの同じサイト・ポートのみ対象で、証明書に問題があるページ、HTTP、別サイトの埋め込みフォームには入力しません。バックグラウンドではすぐロックします。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Safari・Braveからの移行") {
                Text("Safari／Appleの「パスワード」でパスワードを書き出し、CSVまたはパスワードを含むSafari ZIPを「ファイル」へ保存して上のボタンで選びます。Braveはパスワード設定からCSVを書き出します。iPhone版に書き出しがない場合は同期済みPC版などで行ってください。")
                Text("他アプリやiCloudキーチェーンを直接読み取る機能ではありません。パスキー・確認コード・Cookieは移行しません。CSVは暗号化されていません。取り込み後、保存したCSVやZIPを「最近削除した項目」も含めて削除してください。チャットやGitHubには送らないでください。")
                Text("この保管庫は端末専用です。Apple Account・署名IDの変更、端末パスコードの解除、アプリ削除で鍵が利用できなくなる場合があります。事前に暗号化バックアップを作成し、パスフレーズは別に保管してください。Appleのパスワード保管庫とは同期しません。")
            }.font(.footnote)

            if let message { Section { Text(message).accessibilityIdentifier("passwordVaultStatus") } }
        }
        .disabled(busy || vault.busy)
        .navigationTitle("パスワード")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } } }
        .overlay { if phase != .active { Color(uiColor: .systemBackground).overlay(Label("保管庫", systemImage: "lock.fill")).ignoresSafeArea() } }
        .privacySensitive()
        .sheet(item: $editing) { record in PasswordRecordEditor(record: record) }
        .sheet(isPresented: $backupSheet, onDismiss: {
            backupInput = nil
            if pendingExport { pendingExport = false; exporting = true }
            if pendingRecovery != nil { confirmRecovery = true }
        }) {
            PasswordBackupView(input: backupInput, recovery: recoveryPicker) { values in
                if recoveryPicker { pendingRecovery = values }
                else { do { try vault.importRecords(values, replace: false); message = "バックアップを取り込みました。" } catch { show(error) } }
            } exported: { data in document = EncryptedPasswordDocument(data: data); pendingExport = true }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: recoveryPicker ? [.json] : [.commaSeparatedText, .plainText, .zip, .json]) { result in
            guard case .success(let url) = result else { return }
            let token = flow
            perform {
                guard recoveryPicker || vault.unlocked else { throw PasswordVaultError.locked }
                if url.pathExtension.lowercased() == "json" {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    backupInput = try PasswordVault.readLimited(url, limit: 12 * 1024 * 1024)
                    guard token == flow else { throw PasswordVaultError.locked }
                    backupSheet = true
                } else {
                    guard vault.unlocked else { throw PasswordVaultError.locked }
                    // Bounded parsing on a worker; plaintext stays in process memory.
                    let values = try await Task.detached { try PasswordImportReader.read(url) }.value
                    guard vault.unlocked, token == flow else { throw PasswordVaultError.locked }
                    incoming = values; replace = false
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "PersonalBrowser-passwords-encrypted") { _ in document = EncryptedPasswordDocument() }
        .confirmationDialog("このアカウントを保管庫から削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("削除", role: .destructive) { if let value = deleting { do { try vault.delete(value) } catch { show(error) } }; deleting = nil }
        }
        .confirmationDialog("バックアップで保管庫全体を置き換えます。現在の保管庫は読み込まれず、新しい端末専用の鍵を作成します。", isPresented: $confirmRecovery, titleVisibility: .visible) {
            Button("認証して保管庫を復元", role: .destructive) {
                guard let values = pendingRecovery else { return }; pendingRecovery = nil
                perform { try await vault.replaceFromBackup(values); message = "保管庫を復元しました。" }
            }
        }
        .onChange(of: vault.unlocked) { _, open in if !open { clear() } }
        .onChange(of: phase) { _, value in if value == .background { clear(); vault.lock() } }
        .onDisappear { clear(); vault.lock() }
    }
    @ViewBuilder private var pageSection: some View {
        if let page {
            Section("このページへの入力・保存") {
                if page.targets.isEmpty { Text("対応するログインフォームが見つかりません。保管庫から手動で登録できます。") }
                ForEach(Array(page.targets.enumerated()), id: \.element.id) { index, target in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(target.site.display).font(.headline)
                        if page.targets.count > 1 { Text("入力欄 \(index + 1)").font(.caption) }
                        if target.currentPassword, !page.isPrivate || vault.allowPrivateFill {
                            ForEach(vault.records.filter { $0.site == target.site }) { record in
                                Button("\(record.username.isEmpty ? "ユーザー名なし" : record.username) を入力", systemImage: "key") {
                                    perform { try await PasswordFormController.shared.fill(record, into: target); vault.lock(); dismiss() }
                                }.accessibilityIdentifier("fillSavedPasswordButton")
                            }
                        }
                        if !page.isPrivate {
                            Button("このフォームの入力内容を確認して保存") {
                                perform { editing = try await PasswordFormController.shared.capture(target) }
                            }
                        }
                    }
                }
                Text("サイトが移動・更新された場合は入力を中止します。フォーム内容は「確認して保存」を押した場合だけ読み取ります。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func clear() {
        flow = UUID(); incoming = nil; editing = nil; deleting = nil; pendingRecovery = nil
        backupInput = nil; backupSheet = false; importing = false; pendingExport = false; confirmRecovery = false; search = ""; message = nil
    }
    private func show(_ error: Error) { message = (error as? PasswordVaultError)?.errorDescription ?? "処理できませんでした。ファイル形式と保管庫の状態を確認してください。" }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { @MainActor in defer { busy = false }; do { try await operation() } catch { show(error) } }
    }
}

@MainActor
private struct PasswordRecordEditor: View {
    @State var record: PasswordRecord
    @ObservedObject private var vault = PasswordVault.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var site = ""
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("アカウント") {
                    TextField("Webサイト（https://…）", text: $site).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("passwordSiteField")
                    TextField("表示名", text: $record.title)
                    TextField("ユーザー名", text: $record.username).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("passwordUsernameField")
                    SecureField("パスワード", text: $record.password).textContentType(.none).accessibilityIdentifier("passwordSecretField")
                    TextField("メモ", text: $record.notes, axis: .vertical)
                    Text("サイトのパスや検索条件は保存せず、通信方式・ホスト・ポートを照合します。HTTPの登録は保管のみで自動入力できません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Text(message) }
            }
            .navigationTitle("アカウントを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { wipe(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    do { record.site = try PasswordOrigin(site); try vault.save(record); wipe(); dismiss() }
                    catch { message = (error as? PasswordVaultError)?.errorDescription ?? "保存できませんでした。" }
                }.disabled(!vault.unlocked).accessibilityIdentifier("savePasswordRecordButton") }
            }
            .onAppear { site = record.site.display }
            .onChange(of: vault.unlocked) { _, open in if !open { wipe(); dismiss() } }
            .overlay { if phase != .active { Color(uiColor: .systemBackground).ignoresSafeArea() } }
            .privacySensitive()
        }
    }
    private func wipe() { record.username = ""; record.password = ""; record.notes = ""; site = "" }
}

@MainActor
private struct PasswordBackupView: View {
    let input: Data?
    let recovery: Bool
    let restored: ([PasswordRecord]) -> Void
    let exported: (Data) -> Void
    @ObservedObject private var vault = PasswordVault.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var busy = false
    @State private var active = true
    var body: some View {
        NavigationStack {
            Form {
                Text(input == nil ? "12文字以上の専用パスフレーズで暗号化します。このフレーズを失うと復元できません。" : "バックアップのパスフレーズを入力してください。")
                SecureField("パスフレーズ", text: $passphrase).textContentType(.none)
                if input == nil { SecureField("確認用パスフレーズ", text: $confirmation).textContentType(.none) }
                Button(input == nil ? "暗号化して書き出す" : "復号して確認") { run() }.disabled(busy || passphrase.count < 12 || (input == nil && passphrase != confirmation))
                if let message { Text(message) }
            }
            .navigationTitle("暗号化バックアップ")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { cancel(); dismiss() } } }
            .onChange(of: vault.unlocked) { _, open in if !open && !recovery { cancel(); dismiss() } }
            .onChange(of: phase) { _, value in if value == .background { cancel(); dismiss() } }
            .onDisappear { cancel() }
            .overlay { if phase != .active { Color(uiColor: .systemBackground).ignoresSafeArea() } }.privacySensitive()
        }
    }
    private func cancel() { active = false; passphrase = ""; confirmation = "" }
    private func run() {
        guard !busy, recovery || vault.unlocked else { return }
        busy = true
        let secret = passphrase, source = input, values = vault.records, token = vault.revision
        passphrase = ""; confirmation = ""
        Task { @MainActor in
            defer { busy = false }
            do {
                if let source {
                    let result = try await Task.detached { try PasswordCryptography.restore(source, passphrase: secret) }.value
                    guard active, phase == .active, recovery || (vault.unlocked && vault.revision == token) else { throw PasswordVaultError.locked }
                    restored(result)
                } else {
                    let data = try await Task.detached { try PasswordCryptography.backup(values, passphrase: secret) }.value
                    guard active, phase == .active, vault.unlocked, vault.revision == token else { throw PasswordVaultError.locked }
                    exported(data)
                }
                dismiss()
            } catch { message = (error as? PasswordVaultError)?.errorDescription ?? "バックアップを処理できませんでした。" }
        }
    }
}
