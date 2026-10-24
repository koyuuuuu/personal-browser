import Foundation

@main
struct CompatibilityRunner {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, let stage = Int(arguments[3]), (1...3).contains(stage) else {
            fatalError("Usage: compatibility-runner write|verify file.json stage")
        }
        let store = SnapshotStore(fileURL: URL(fileURLWithPath: arguments[2]))
        if arguments[1] == "write" {
            var snapshot = try store.load()
            let url = URL(string: "https://example.com/stage-\(stage)")!
            snapshot.bookmarks.append(Bookmark(title: "Saved by stage \(stage)", url: url))
            snapshot.recordVisit(url: url, title: "Visit \(stage)", isPrivate: false,
                                 at: Date(timeIntervalSince1970: Double(stage)))
            snapshot.settings.toolbarPosition = stage == 2 ? .top : .bottom
            try store.save(snapshot)
        } else if arguments[1] == "verify" {
            let snapshot = try store.load()
            guard snapshot.bookmarks.count == stage, snapshot.history.count == stage,
                  Set(snapshot.bookmarks.map(\.title)) == Set((1...stage).map { "Saved by stage \($0)" }),
                  snapshot.history.first?.title == "Visit \(stage)" else {
                fatalError("Latest bookmark/history data did not survive app-version transition")
            }
        } else { fatalError("Unknown command") }
    }
}
