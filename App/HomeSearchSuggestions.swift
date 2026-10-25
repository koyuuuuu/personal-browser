import SwiftUI

@MainActor
struct HomeSearchSuggestions: View {
    let query: String
    let engine: SearchEngine
    let select: (String) -> Void
    @State private var choices: [String] = []
    @State private var loading = false
    private var requestID: String { engine.rawValue + ":" + query }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(engine.label + "の検索候補").font(.headline).padding()
                ForEach(choices, id: \.self) { value in
                    Button { select(value) } label: {
                        HStack { Image(systemName: "magnifyingglass"); Text(value).multilineTextAlignment(.leading); Spacer() }
                            .padding().frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("searchCandidate-" + value)
                    Divider()
                }
                if loading { ProgressView().padding() }
                else if choices.isEmpty { Text("検索語を入力してください。候補がなくてもそのまま検索できます。")
                    .font(.footnote).foregroundStyle(.secondary).padding() }
            }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding()
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("homeSearchSuggestions")
        .task(id: requestID) {
            choices = []; loading = false
            guard let url = SearchSuggestions.endpoint(query, engine: engine) else { return }
            loading = true
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-suggestion-fixture") {
                    choices = [query + " one", query + " two"]; loading = false; return
                }
                #endif
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
                configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 5
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(from: url)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { loading = false; return }
                choices = try SearchSuggestions.parse(data, engine: engine); loading = false
            } catch { if !Task.isCancelled { choices = []; loading = false } }
        }
    }
}
