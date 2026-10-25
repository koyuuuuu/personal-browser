import Foundation

@main
struct FavoritesCompatibilityRunner {
    static func main() throws {
        let args = CommandLine.arguments, file = URL(fileURLWithPath: CommandLine.arguments[2])
        let stage = Int(args[3])!
        var library = FileManager.default.fileExists(atPath: file.path) ? try JSONDecoder().decode(LibraryExtras.self, from: Data(contentsOf: file)).validated() : LibraryExtras()
        if args[1] == "write" {
            library.favorites.insert(Bookmark(title: "Latest \(stage)", url: URL(string: "https://example.com/\(stage)")!), at: 0)
            if stage == 2 { library.favorites[1].title = "Edited on 0.5" }
            try JSONEncoder().encode(library).write(to: file, options: .atomic)
        } else {
            let expected = stage == 1 ? ["Latest 1"] : (stage == 2 ? ["Latest 2", "Edited on 0.5"] : ["Latest 3", "Latest 2", "Edited on 0.5"])
            guard library.favorites.map(\.title) == expected, library.schemaVersion == 1 else { fatalError("Latest favorites/order lost across app rollback") }
        }
    }
}
