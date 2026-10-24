import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
struct FeatureSettingsView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject private var blocker = ContentBlocking.shared
    @State private var imageSelection: PhotosPickerItem?
    @State private var host = ""
    var body: some View {
        Form {
            Section {
                Text(blocker.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("blockingRuleStatus")
                Toggle("広告をブロック", isOn: feature(\.blockAdvertisements)).accessibilityIdentifier("adBlockingToggle")
                ForEach(store.features.blockingExceptions, id: \.self) { domain in Text(domain) }
                    .onDelete { offsets in var value = store.features; value.blockingExceptions.remove(atOffsets: offsets); store.updateFeatures(value) }
                HStack {
                    TextField("除外するドメイン", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("追加") { addException() }.disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let domain = store.selectedTab?.url?.host {
                    Button("このサイトを除外（\(domain)）") { host = domain; addException() }
                }
            } header: { Text("広告ブロック") }
            footer: { Text("既知の広告配信ドメインからの第三者リクエストをWebKitで遮断します。サイト内配信の動画広告など、すべての広告を除去するものではありません。変更後はページを再読み込みしてください。除外はサブドメインにも適用します。") }
            Section("タブと操作") {
                Toggle("アドレスバーをスワイプしてタブを切り替え", isOn: feature(\.swipeAddressToSwitchTabs))
                Toggle("タブ追加時のアニメーション", isOn: feature(\.animateNewTabs))
                Stepper("保持するWebページ数：\(store.features.maximumLiveTabs)", value: feature(\.maximumLiveTabs), in: 2...8)
                Text("タブは最大500個。非選択・非再生のページは休止し、選択時にURLから再読み込みします。休止したページの入力内容や戻る履歴は復元されません。動画・PiP再生中のページは休止しません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("ホーム画面") {
                Stepper("お気に入りの列数：\(store.features.favoriteColumns)", value: feature(\.favoriteColumns), in: 3...6)
                Toggle("背景画像を表示", isOn: feature(\.showHomeBackground))
                PhotosPicker(selection: $imageSelection, matching: .images) { Label("背景画像を選ぶ", systemImage: "photo") }
                if store.homeBackground != nil { Button("背景画像を削除", role: .destructive) { store.setHomeBackground(nil) } }
                Text("サイトのアイコンはドメインの頭文字で表示します。ホーム表示時に各サイトへの通信は行いません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("ピクチャーインピクチャーを許可", isOn: feature(\.enablePictureInPicture))
                Toggle("新しいウィンドウを開くリンクを許可", isOn: feature(\.allowPopups))
            } header: { Text("動画・サイトの動作") }
            footer: { Text("PiPの設定は新しく読み込むWebViewに適用されます。サイトや動画配信方式によって利用できない場合があります。") }
            Section {
                TextField("https://…/watch.html", text: feature(\.watchHTMLAddress))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("現在のWatch HTMLを接続先にする") { store.useCurrentWatchHTML() }
                    .disabled(store.selectedTab?.url.map { !["/watch", "/watch.html"].contains($0.path.lowercased()) } ?? true)
                Button("コピーしたWatch HTMLのURLを設定") {
                    if let url = UIPasteboard.general.url ?? UIPasteboard.general.string.flatMap({ URL(string: $0) }), url.scheme == "https", WebURLPolicy.allows(url) {
                        var prefs = store.features; prefs.watchHTMLAddress = url.absoluteString; store.updateFeatures(prefs)
                    } else { store.notice = "HTTPSのWatch HTMLのURLをコピーしてください。" }
                }
                Text("自作ビデオサーバーの接続先を保存します。メニューの「コピーしたリンクをWatch HTMLで解析」またはリンクの長押しから、urlパラメータで入力欄へ渡します。トンネルのトークンやパスワードは入力しません。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Watch HTMLとの連携") }
            Section("リンクを開くアプリ") {
                ForEach(ExternalApplication.allCases) { app in
                    Toggle(app.label, isOn: Binding(get: { store.features.externalApplications.contains(app.rawValue) }, set: { enabled in
                        var prefs = store.features
                        prefs.externalApplications.removeAll { $0 == app.rawValue }; if enabled { prefs.externalApplications.append(app.rawValue) }
                        store.updateFeatures(prefs)
                    }))
                }
                Text("リンクの長押し → アプリで開く、で階層メニューを表示します。未インストールのアプリは開けません。その他のアプリはiOSの共有シートから選択します。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("ブラウザ機能")
        .task { _ = await blocker.rules() }
        .task(id: imageSelection) {
            guard let imageSelection else { return }
            do {
                if let data = try await imageSelection.loadTransferable(type: Data.self) {
                    guard data.count <= 40 * 1024 * 1024 else { store.notice = "40MB以下の画像を選んでください。"; return }
                    store.setHomeBackground(data)
                }
            } catch { store.notice = "画像を読み込めませんでした。" }
        }
    }
    private func feature<Value>(_ path: WritableKeyPath<FeaturePreferences, Value>) -> Binding<Value> {
        Binding(get: { store.features[keyPath: path] }, set: { newValue in var prefs = store.features; prefs[keyPath: path] = newValue; store.updateFeatures(prefs) })
    }
    private func addException() {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let url = URL(string: value.contains("://") ? value : "https://" + value), WebURLPolicy.allows(url), let domain = url.host, domain.contains("."), !domain.contains(" ") else { store.notice = "有効なドメイン名を入力してください。"; return }
        var prefs = store.features
        if !prefs.blockingExceptions.contains(domain) { prefs.blockingExceptions.append(domain) }
        store.updateFeatures(prefs); host = ""
    }
}

struct BrowserLibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
struct LibraryTransferView: View {
    @ObservedObject var store: BrowserStore
    @State private var kind = LibraryImportKind.bookmarks
    @State private var importing = false
    @State private var exporting = false
    @State private var busy = false
    @State private var pages: [ImportedPage] = []
    @State private var status: String?
    @State private var document = BrowserLibraryDocument()
    var body: some View {
        Form {
            Section("取り込む種類") {
                Picker("種類", selection: $kind) { ForEach(LibraryImportKind.allCases) { value in Text(value.label).tag(value) } }.disabled(!pages.isEmpty || busy)
                Button("HTML・CSV・JSON・Safari ZIPを選択") { importing = true }.disabled(busy)
                if busy { ProgressView("読み込み中…") }
                if !pages.isEmpty {
                    Text("\(pages.count)件を読み取りました。既存データと同じURLは重複登録しません。")
                    Button("\(kind.label)に取り込む") { let count = store.importPages(pages, kind: kind); status = "\(count)件を追加しました。"; pages = [] }
                    Button("取り消す", role: .cancel) { pages = [] }
                }
                if let status { Text(status).font(.callout) }
            }
            Section {
                Text("他アプリの保存領域やアカウントを直接読むことはできません。PCなどで書き出したブックマークHTML、URLとタイトルを含むCSV、Chrome/FirefoxのブックマークJSON、またはこのアプリの書き出しJSONを選択してください。履歴は最新1,000件を保持します。")
                Text("Safariで使用中のパスワードは、同じApple Accountの「パスワード」アプリ／iCloudキーチェーンをそのまま利用できます。iOSの「設定 → 一般 → 自動入力とパスワード」で有効にしてください。このアプリからAppleの保管庫へ直接登録するAPIはありません。パスワードCSVはApple側の対応する読み込み機能で扱い、ここには取り込みません。Safari ZIP内のパスワードファイルも読み込みません。")
            } header: { Text("他ブラウザからの移行") }
            Section("書き出し") {
                Button("ブックマーク・お気に入り・履歴をJSONに保存") {
                    do { document = BrowserLibraryDocument(data: try LibraryTransfer.export(bookmarks: store.snapshot.bookmarks, history: store.snapshot.history, extras: store.extras)); exporting = true }
                    catch { status = "書き出しできませんでした。" }
                }
                Text("閲覧データを含むため、保存先と共有先を確認してください。Cookieとパスワードは含みません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("データの取り込み・書き出し")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.html, .commaSeparatedText, .json, .plainText, .zip], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                busy = true; pages = []; status = nil
                let selectedKind = kind
                Task {
                    do {
                        let result = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                            let data = try handle.read(upToCount: 20 * 1024 * 1024 + 1) ?? Data()
                            return try SafariImport.parse(data, kind: selectedKind)
                        }.value
                        pages = result
                    } catch { status = error.localizedDescription }
                    busy = false
                }
            } catch { status = "ファイルを選択できませんでした。" }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "PersonalBrowser-library") { result in
            if case .failure = result { status = "書き出しを完了できませんでした。" }
        }
    }
}
