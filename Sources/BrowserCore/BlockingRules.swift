import Foundation

public enum BlockingStrength: String, Codable, CaseIterable, Sendable { case standard, strong }

public struct BlockingPreferences: Codable, Equatable, Sendable {
    public var strength: BlockingStrength = .standard
    public var cosmetic = true
    public var automaticUpdates = true
    public init() {}
}

public struct BlockingRuleFile: Codable, Equatable, Sendable {
    public var name: String
    public var sha256: String
    public var size: Int
    public var count: Int
    public var kind: String
    public func validate(_ data: Data) throws {
        guard data.count == size,
              let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], rules.count == count,
              rules.allSatisfy({ rule in
                  guard let trigger = rule["trigger"] as? [String: Any], trigger["url-filter"] is String,
                        let action = rule["action"] as? [String: Any], let type = action["type"] as? String else { return false }
                  return ["block", "block-cookies", "ignore-previous-rules", "css-display-none"].contains(type)
                      && (type != "css-display-none" || action["selector"] is String)
              }) else { throw BlockingDataError.invalid }
    }
}

public enum BlockingDataError: Error { case invalid }

public struct BlockingManifest: Codable, Sendable {
    public var schema: Int
    public var revision: String
    public var generatedAt: String
    public var profiles: [String: [BlockingRuleFile]]
    public var sourceArchive: String
    public func validated() throws -> Self {
        guard schema == 1, revision.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              sourceArchive == "filter-sources-" + revision + ".zip" else { throw BlockingDataError.invalid }
        var files: [String: BlockingRuleFile] = [:]
        for mode in BlockingStrength.allCases {
            guard let profile = profiles[mode.rawValue], !profile.isEmpty, profile.count <= 16,
                  profile.contains(where: { $0.kind == "network" }) else { throw BlockingDataError.invalid }
            for file in profile {
                guard ["network", "cosmetic"].contains(file.kind),
                      file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                      file.name == file.kind + "-" + file.sha256 + ".json",
                      file.size > 0, file.size <= 12 * 1024 * 1024, file.count > 0, file.count <= 50000 else { throw BlockingDataError.invalid }
                if let existing = files[file.name], existing != file { throw BlockingDataError.invalid }
                files[file.name] = file
            }
            guard profile.reduce(0, { $0 + $1.size }) <= 40 * 1024 * 1024 else { throw BlockingDataError.invalid }
        }
        return self
    }
    public func files(for preferences: BlockingPreferences) -> [BlockingRuleFile] {
        (profiles[preferences.strength.rawValue] ?? []).filter { preferences.cosmetic || $0.kind != "cosmetic" }
    }
}
