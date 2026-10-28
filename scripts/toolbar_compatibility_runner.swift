import Foundation

@main
struct ToolbarCompatibilityRunner {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let command = CommandLine.arguments[2]
        let legacyFile = directory.appendingPathComponent("toolbar.json")
        let extensionFile = directory.appendingPathComponent("toolbar-extensions.json")
        let encoder = JSONEncoder()
        if command == "seed" {
            var value = ToolbarPreferences(); value.main = [.back,.newTab,.tabs]
            try encoder.encode(value).write(to: legacyFile, options: .atomic); return
        }
        var legacy = try JSONDecoder().decode(ToolbarPreferences.self, from: Data(contentsOf: legacyFile))
        if command == "verifyLegacy" {
            guard legacy.main == [.newTab,.tabs], legacy.left == [], legacy.right == [] else { fatalError("Old toolbar reader cannot use the sanitized file") }
        } else if command == "editLegacy" {
            legacy.main = [.share,.tabs]
            try encoder.encode(legacy).write(to: legacyFile, options: .atomic)
        }
        #if CURRENT_TOOLBAR
        if command == "enhance" {
            var value = ToolbarPreferences()
            value.main = [.previousViewedTab,.nextViewedTab,.newTab,.tabs]
            value.left = [.previousViewedTab]; value.right = [.nextViewedTab]
            let extended = ExtendedToolbarPreferences(value)
            try encoder.encode(extended.legacy).write(to: legacyFile, options: .atomic)
            try encoder.encode(extended).write(to: extensionFile, options: .atomic)
        } else if command == "verifyEnhanced" || command == "verifyEdited" {
            let extended = try JSONDecoder().decode(ExtendedToolbarPreferences.self, from: Data(contentsOf: extensionFile))
            let value = extended.resolve(against: legacy)
            if command == "verifyEnhanced" {
                guard value.main?.first == .previousViewedTab, value.right == [.nextViewedTab] else { fatalError("New toolbar choices lost") }
            } else {
                guard value.main == [.share,.tabs] else { fatalError("Latest old-app edits were overwritten") }
            }
        }
        #endif
    }
}
