import SwiftUI

@MainActor
struct FavoritesSettingsView: View {
    @ObservedObject var store: BrowserStore
    @State private var editing: Bookmark?
    var body: some View {
        List {
            ForEach(store.extras.favorites) { item in
                Button { editing = item } label: {
                    HStack {
                        SiteIcon(url: item.url, size: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).foregroundStyle(.primary).lineLimit(1)
                            Text(item.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.accessibilityIdentifier("favoriteEditor-" + item.id.uuidString)
            }
            .onMove { store.reorderFavorites($0, destination: $1) }
            .onDelete { offsets in for id in offsets.map({ store.extras.favorites[$0].id }) { store.deleteFavorite(id) } }
            if store.extras.favorites.isEmpty { Text("お気に入りはありません").foregroundStyle(.secondary) }
        }
        .navigationTitle("お気に入り")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("お気に入りを追加", systemImage: "plus") { editing = Bookmark(title: "", url: URL(string: "about:blank")!) }
                EditButton()
            }
        }
        .sheet(item: $editing) { item in BookmarkEditor(item: item, save: store.saveFavorite) }
    }
}

@MainActor
struct ExternalLinksSettingsView: View {
    @ObservedObject var store: BrowserStore
    var body: some View {
        List {
            Section("ほかのアプリから開く") {
                Text("共有シートのショートカットから、このブラウザの新しいタブへリンクを送れます。")
                Text("mybrowser://open?url=（URLエンコードしたリンク）").font(.footnote).textSelection(.enabled)
                Text("ショートカットを作成して「共有シートに表示」をオンにし、入力をURL・SafariのWebページに設定します。「入力からURLを取得」→「最初の項目を取得」→「URLエンコード」→「テキスト（上のスキーム＋エンコード結果）」→「URLを開く」の順に配置してください。")
                    .font(.footnote)
                Text("入力がない場合は終了する条件を追加してください。初回はiOSによる起動許可が表示される場合があります。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                ForEach(store.links.applicationSites.sorted(), id: \.self) { site in
                    Text(site).swipeActions { Button("ブラウザに戻す", role: .destructive) { store.resetApplicationPreference(site) } }
                }
                if store.links.applicationSites.isEmpty { Text("すべてブラウザで開きます").foregroundStyle(.secondary) }
            } header: { Text("対応アプリを優先するサイト") }
            footer: { Text("このブラウザでの開き方です。「このタブで開く」「新しいタブで開く」を選ぶと、そのサイトはブラウザ優先へ戻ります。「アプリで開く → 対応するアプリ」で成功すると再びアプリを優先します。iOS全体の設定は変更しません。") }
        }.navigationTitle("外部リンク・ショートカット")
    }
}
