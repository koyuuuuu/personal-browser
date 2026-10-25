import SwiftUI

@MainActor
struct LibraryView: View {
    @ObservedObject var store: BrowserStore
    let showHistory: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if showHistory { HistoryList(store: store) }
                else { BookmarkFolderList(store: store, folderID: nil) }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } } }
            .navigationDestination(for: UUID.self) { id in BookmarkFolderList(store: store, folderID: id) }
        }
    }
}

@MainActor
struct BookmarkFolderList: View {
    @ObservedObject var store: BrowserStore
    let folderID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var creatingFolder = false
    @State private var folderName = ""
    @State private var editing: Bookmark?
    @State private var editingFolder: BookmarkFolder?
    private var folders: [BookmarkFolder] { store.extras.folders.filter { $0.parentID == folderID && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) } }
    private var bookmarks: [Bookmark] { store.snapshot.bookmarks.filter {
        (query.isEmpty ? store.extras.bookmarkFolders[$0.id.uuidString] == folderID : true)
            && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query))
    } }
    var body: some View {
        List {
            ForEach(folders) { folder in
                NavigationLink(value: folder.id) { Label(folder.name, systemImage: "folder") }
                    .contextMenu {
                        Button("名前・移動先を編集", systemImage: "pencil") { editingFolder = folder }
                        Button("フォルダを削除（中身は上の階層へ）", systemImage: "trash", role: .destructive) { store.deleteFolder(folder.id) }
                    }
            }
            .onMove { source, destination in store.moveFolders(folders.map(\.id), source: source, destination: destination) }
            .moveDisabled(!query.isEmpty)
            ForEach(bookmarks) { item in
                Button { store.open(item.url); closeLibrary() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).foregroundStyle(.primary).lineLimit(1)
                        Text(item.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .contextMenu {
                    Button("編集", systemImage: "pencil") { editing = item }
                    Menu("フォルダへ移動", systemImage: "folder") {
                        Button("すべてのブックマーク") { store.moveBookmark(item.id, folder: nil) }
                        ForEach(store.extras.folders) { folder in Button(folderPath(folder)) { store.moveBookmark(item.id, folder: folder.id) } }
                    }
                    Button("お気に入りに追加", systemImage: "star") { _ = store.importPages([ImportedPage(title: item.title, url: item.url)], kind: .favorites) }
                    Button("新しいタブで開く", systemImage: "plus.square") { _ = store.newTab(url: item.url); closeLibrary() }
                    Button("リンクをコピー", systemImage: "doc.on.doc") { UIPasteboard.general.url = item.url }
                    Button("削除", systemImage: "trash", role: .destructive) { store.deleteBookmark(item.id) }
                }
            }
            .onDelete { offsets in let ids = offsets.map { bookmarks[$0].id }; for id in ids { store.deleteBookmark(id) } }
            .onMove { source, destination in store.reorderBookmarks(bookmarks.map(\.id), source: source, destination: destination) }
            .moveDisabled(!query.isEmpty)
            if folders.isEmpty && bookmarks.isEmpty { Text("ブックマークはありません").foregroundStyle(.secondary) }
        }
        .searchable(text: $query, prompt: "ブックマークを検索")
        .navigationTitle(folderID.flatMap { id in store.extras.folders.first { $0.id == id }?.name } ?? "ブックマーク")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("フォルダを作成", systemImage: "folder.badge.plus") { folderName = ""; creatingFolder = true }.accessibilityIdentifier("createFolderButton")
                EditButton()
            }
        }
        .alert("新しいフォルダ", isPresented: $creatingFolder) {
            TextField("フォルダ名", text: $folderName)
            Button("作成") { store.createFolder(name: folderName, parent: folderID) }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(item: $editing) { item in BookmarkEditor(item: item, save: store.updateBookmark) }
        .sheet(item: $editingFolder) { folder in FolderEditor(store: store, folder: folder) }
    }
    private func closeLibrary() {
        // Dismissing the whole presentation also works from a nested folder.
        NotificationCenter.default.post(name: .closeBrowserLibrary, object: nil)
    }
    private func folderPath(_ folder: BookmarkFolder) -> String {
        var names = [folder.name], parent = folder.parentID, seen = Set<UUID>()
        while let id = parent, seen.insert(id).inserted, let value = store.extras.folders.first(where: { $0.id == id }) { names.insert(value.name, at: 0); parent = value.parentID }
        return names.joined(separator: " / ")
    }
}

extension Notification.Name { static let closeBrowserLibrary = Notification.Name("PersonalBrowser.closeLibrary") }

struct BookmarkEditor: View {
    @State var item: Bookmark
    let save: (Bookmark) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    init(item: Bookmark, save: @escaping (Bookmark) -> Void) {
        _item = State(initialValue: item); _address = State(initialValue: item.url.absoluteString); self.save = save
    }
    private var validURL: URL? { URL(string: address).flatMap { WebURLPolicy.allows($0) ? $0 : nil } }
    var body: some View {
        NavigationStack {
            Form {
                TextField("タイトル", text: $item.title)
                TextField("URL", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .navigationTitle("編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { if let url = validURL { item.url = url; save(item); dismiss() } }.disabled(validURL == nil) }
            }
        }
    }
}

@MainActor
struct FolderEditor: View {
    @ObservedObject var store: BrowserStore
    @State var folder: BookmarkFolder
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("フォルダ名", text: $folder.name)
                Picker("移動先", selection: $folder.parentID) {
                    Text("すべてのブックマーク").tag(nil as UUID?)
                    ForEach(store.extras.folders.filter { store.extras.canMoveFolder(folder.id, to: $0.id) }) { parent in Text(parent.name).tag(Optional(parent.id)) }
                }
            }
            .navigationTitle("フォルダを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { store.updateFolder(folder); dismiss() }.disabled(folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}

@MainActor
struct HistoryList: View {
    @ObservedObject var store: BrowserStore
    @State private var query = ""
    @State private var confirmClear = false
    @State private var expanded = Set<Date>()
    private var groups: [HistoryPeriod] { HistoryPresentation.periods(store.snapshot.history) }
    var body: some View {
        List {
            ForEach(groups) { group in
                let matches = group.entries.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query) }
                if !matches.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if !expanded.insert(group.id).inserted { expanded.remove(group.id) }
                        }
                    } label: {
                        HStack {
                            Image(systemName: expanded.contains(group.id) ? "folder.fill" : "folder")
                            Text(group.id, format: .dateTime.year().month().day().weekday())
                            Text(group.afternoon ? "午後" : "午前")
                            Spacer()
                            Text("\(group.entries.count)").foregroundStyle(.secondary)
                            Image(systemName: expanded.contains(group.id) ? "chevron.down" : "chevron.right").font(.caption)
                        }.font(.subheadline).foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("historyPeriod")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { store.deleteHistory(Set(group.entries.map(\.id))) } label: { Label("まとめて削除", systemImage: "xmark") }
                    }
                    if expanded.contains(group.id) || !query.isEmpty {
                        ForEach(matches) { item in
                            Button { store.open(item.url); NotificationCenter.default.post(name: .closeBrowserLibrary, object: nil) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).foregroundStyle(.primary).lineLimit(1)
                                    Text(item.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text(item.visitedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                                }.padding(.leading, 20)
                            }
                            .accessibilityIdentifier("historyEntry-" + item.id.uuidString)
                            .swipeActions { Button("削除", systemImage: "xmark", role: .destructive) { store.deleteHistory([item.id]) } }
                        }
                    }
                }
            }
            if store.snapshot.history.isEmpty { Text("履歴はありません").foregroundStyle(.secondary) }
        }
        .searchable(text: $query, prompt: "履歴を検索").navigationTitle("履歴")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("消去", role: .destructive) { confirmClear = true }.disabled(store.snapshot.history.isEmpty) } }
        .confirmationDialog("閲覧履歴をすべて消去しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("履歴を消去", role: .destructive) { store.clearHistory() }
        }
    }
}

@MainActor
struct DownloadsView: View {
    @ObservedObject var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var confirmDelete: URL?
    var body: some View {
        NavigationStack {
            List {
                ForEach(files, id: \.self) { url in
                    HStack {
                        Text(String(url.lastPathComponent.dropFirst(9))).font(.callout).lineLimit(2)
                        Spacer()
                        ShareLink(item: url) { Label("共有・ファイルに保存", systemImage: "square.and.arrow.up").labelStyle(.iconOnly) }
                    }
                    .swipeActions { Button("削除", role: .destructive) { confirmDelete = url } }
                }
                if files.isEmpty { Text("ダウンロードしたファイルはありません").foregroundStyle(.secondary) }
            }
            .navigationTitle("ダウンロード")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } } }
            .onAppear { files = store.downloadedFiles }
            .confirmationDialog("このファイルを削除しますか？", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if let url = confirmDelete { do { try FileManager.default.removeItem(at: url); files = store.downloadedFiles } catch { store.notice = "ファイルを削除できませんでした。" } }
                    confirmDelete = nil
                }
            }
        }
    }
}
