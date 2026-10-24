import SwiftUI

@MainActor
final class ConnectionRequest: Identifiable {
    enum Kind { case certificate, http }
    let id = UUID()
    let kind: Kind
    let url: URL
    let fingerprint: String?
    private var completion: ((Bool, Bool) -> Void)?
    init(kind: Kind, url: URL, fingerprint: String? = nil, completion: @escaping (Bool, Bool) -> Void) {
        self.kind = kind; self.url = url; self.fingerprint = fingerprint; self.completion = completion
    }
    func resolve(allow: Bool, remember: Bool = false) { let callback = completion; completion = nil; callback?(allow, remember) }
}

struct ConnectionPrompt: View {
    let request: ConnectionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var remember = false
    var body: some View {
        NavigationStack {
            Form {
                Section("接続先") { Text(ConnectionSecurity.origin(request.url) ?? request.url.host ?? "").textSelection(.enabled) }
                if request.kind == .certificate {
                    Section {
                        Text("このサーバーの証明書を検証できませんでした。接続先を確認してから続けてください。")
                        if let fingerprint = request.fingerprint { LabeledContent("証明書 SHA-256") { Text(fingerprint).font(.caption2.monospaced()).textSelection(.enabled) } }
                    }
                } else {
                    Section { Text("HTTPSで接続できませんでした。このローカルサーバーがHTTPのみで動いている場合は、HTTPで開くことができます。HTTPの通信は暗号化されません。") }
                }
                Section {
                    Toggle("この接続先では今後確認しない", isOn: $remember).accessibilityIdentifier("rememberConnectionToggle")
                } footer: { Text(request.kind == .certificate ? "チェックした場合だけ、ホスト名・ポート・この証明書の組み合わせを保存します。証明書が変わった場合は再確認します。" : "チェックした場合だけ、このホスト名とポートへのHTTP接続を保存します。") }
                Button(request.kind == .certificate ? "接続する" : "HTTPで開く") { request.resolve(allow: true, remember: remember); dismiss() }
                    .accessibilityIdentifier("allowConnectionButton")
            }
            .navigationTitle("接続の確認")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { request.resolve(allow: false); dismiss() } } }
        }
        .interactiveDismissDisabled()
        .onDisappear { request.resolve(allow: false) }
    }
}
