import Foundation

public enum PasswordVaultError: Error, LocalizedError {
    case invalidSite, invalidRecord, tooLarge, invalidImport, locked, authentication, unavailable, corrupted, backupPassword
    public var errorDescription: String? {
        switch self {
        case .invalidSite: "HTTPまたはHTTPSの正しいWebサイトURLを指定してください。"
        case .invalidRecord: "入力内容を確認してください。パスワードは空にできません。"
        case .tooLarge: "保管庫または選択ファイルの上限を超えています。"
        case .invalidImport: "対応するパスワードCSV・Safari ZIP・暗号化バックアップではありません。"
        case .locked: "保管庫がロックされています。もう一度解除してください。"
        case .authentication: "認証が完了しませんでした。"
        case .unavailable: "端末のパスコードを設定してから保管庫を利用してください。"
        case .corrupted: "保管庫を読み出せません。データを消去せず、署名アカウントや暗号化バックアップを確認してください。"
        case .backupPassword: "バックアップのパスフレーズが違うか、ファイルを読み出せません。"
        }
    }
}

public struct PasswordOrigin: Codable, Hashable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int
    public init(_ url: URL) throws {
        guard WebURLPolicy.allows(url), let host = url.host?.lowercased(),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw PasswordVaultError.invalidSite }
        let scheme = url.scheme!.lowercased(), port = parts.port ?? (scheme == "https" ? 443 : 80)
        guard (1...65535).contains(port), !host.isEmpty, host.utf8.count <= 255,
              !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }),
              host.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\?#@%")) == nil else { throw PasswordVaultError.invalidSite }
        var origin = URLComponents(); origin.scheme = scheme; origin.host = host; origin.port = port
        guard origin.url != nil else { throw PasswordVaultError.invalidSite }
        self.scheme = scheme; self.host = host; self.port = port
    }
    public init(_ text: String) throws {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 8192, let url = URL(string: value) else { throw PasswordVaultError.invalidSite }
        try self.init(url)
    }
    private enum CodingKeys: String, CodingKey { case scheme, host, port }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let scheme = try box.decode(String.self, forKey: .scheme), host = try box.decode(String.self, forKey: .host), port = try box.decode(Int.self, forKey: .port)
        guard ["https","http"].contains(scheme), !host.isEmpty, host.utf8.count <= 255,
              !host.contains(where: { $0.isWhitespace || $0.isNewline }), (1...65535).contains(port) else { throw PasswordVaultError.invalidSite }
        var parts = URLComponents(); parts.scheme = scheme; parts.host = host; parts.port = port
        guard let url = parts.url else { throw PasswordVaultError.invalidSite }
        let checked = try Self(url)
        guard checked.host == host, checked.scheme == scheme, checked.port == port else { throw PasswordVaultError.invalidSite }
        self = checked
    }
    public var url: URL {
        var parts = URLComponents(); parts.scheme = scheme; parts.host = host
        if port != (scheme == "https" ? 443 : 80) { parts.port = port }
        return parts.url!
    }
    public var display: String { url.absoluteString }
    public static func mayFill(saved: Self, top: Self, frame: Self, trusted: Bool) -> Bool {
        saved.scheme == "https" && trusted && saved == top && top == frame
    }
}

public struct PasswordRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var site: PasswordOrigin
    public var title: String
    public var username: String
    public var password: String
    public var notes: String
    public init(id: UUID = UUID(), site: PasswordOrigin, title: String = "", username: String, password: String, notes: String = "") {
        self.id = id; self.site = site; self.title = title; self.username = username; self.password = password; self.notes = notes
    }
    public func validated() throws -> Self {
        guard try PasswordOrigin(site.url) == site, !password.isEmpty,
              password.utf8.count <= 16384, username.utf8.count <= 4096,
              title.utf8.count <= 1024, notes.utf8.count <= 16384 else { throw PasswordVaultError.invalidRecord }
        return self
    }
    public var accountKey: String { site.display + "\u{0}" + Data(username.utf8).base64EncodedString() }
}

public struct PasswordVaultPayload: Codable, Sendable {
    public var schema = 1
    public var records: [PasswordRecord]
    public init(records: [PasswordRecord] = []) { self.records = records }
    public func validated() throws -> Self {
        guard schema == 1, records.count <= 5000, Set(records.map(\.id)).count == records.count,
              Set(records.map(\.accountKey)).count == records.count else { throw PasswordVaultError.corrupted }
        for record in records { _ = try record.validated() }
        return self
    }
}

public struct PasswordImportResult: Sendable {
    public var records: [PasswordRecord] = []
    public var skipped = 0
    public var duplicates = 0
    public var conflicts = 0
    public var ignoredCodes = 0
    public init() {}
    public static func merged(_ incoming: [PasswordRecord], into existing: [PasswordRecord], replace: Bool) throws -> Self {
        _ = try PasswordVaultPayload(records: existing).validated()
        guard incoming.count <= 5000 else { throw PasswordVaultError.tooLarge }
        var result = Self(); result.records = existing
        var positions = Dictionary(uniqueKeysWithValues: existing.enumerated().map { ($0.element.accountKey, $0.offset) })
        for value in incoming {
            let value = try value.validated()
            if let index = positions[value.accountKey] {
                if result.records[index].password.utf8.elementsEqual(value.password.utf8) && result.records[index].notes.utf8.elementsEqual(value.notes.utf8) { result.duplicates += 1 }
                else {
                    result.conflicts += 1
                    if replace { var update = value; update.id = result.records[index].id; result.records[index] = update }
                }
            } else {
                guard result.records.count < 5000 else { throw PasswordVaultError.tooLarge }
                var copy = value; copy.id = UUID(); positions[copy.accountKey] = result.records.count; result.records.append(copy)
            }
        }
        return result
    }
}

public enum PasswordCSV {
    public static let maximumBytes = 8 * 1024 * 1024
    /// Strict RFC4180 with bounded columns/rows; malformed quoting must not
    /// silently alter a password, and a small CSV cannot allocate millions of fields.
    private static func boundedRows(_ text: String) throws -> [[String]] {
        let chars = Array(text.unicodeScalars)
        var rows: [[String]] = [], row: [String] = [], field = "", i = 0
        var quoted = false, closed = false
        func addField() throws {
            guard row.count < 64, field.utf8.count <= 32768 else { throw PasswordVaultError.tooLarge }
            row.append(field); field = ""; closed = false
        }
        func addRow() throws {
            try addField()
            if row.contains(where: { !$0.isEmpty }) {
                guard rows.count < 5001 else { throw PasswordVaultError.tooLarge }
                rows.append(row)
            }
            row = []
        }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i+1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.unicodeScalars.append(c) }
            } else if c == "," { try addField() }
            else if c == "\n" || c == "\r" {
                try addRow()
                if c == "\r", i + 1 < chars.count, chars[i+1] == "\n" { i += 1 }
            } else if c == "\"", field.isEmpty, !closed { quoted = true }
            else {
                guard !closed, c != "\"" else { throw PasswordVaultError.invalidImport }
                field.unicodeScalars.append(c)
            }
            // A single field cannot grow to the whole archive size.
            if i % 4096 == 0, field.utf8.count > 32768 { throw PasswordVaultError.tooLarge }
            i += 1
        }
        guard !quoted else { throw PasswordVaultError.invalidImport }
        try addRow()
        return rows
    }
    public static func parse(_ data: Data) throws -> PasswordImportResult {
        guard data.count <= maximumBytes else { throw PasswordVaultError.tooLarge }
        // Do not guess encodings or normalize/truncate secrets.
        let text: String?
        if data.starts(with: [0xff,0xfe]) || data.starts(with: [0xfe,0xff]) {
            let encoding: String.Encoding = data.starts(with: [0xff,0xfe]) ? .utf16LittleEndian : .utf16BigEndian
            let bytes = Data(data.dropFirst(2))
            guard let decoded = String(data: bytes, encoding: encoding), decoded.data(using: encoding) == bytes else { throw PasswordVaultError.invalidImport }
            text = decoded
        } else { text = String(data: data, encoding: .utf8) }
        guard var text else { throw PasswordVaultError.invalidImport }
        if text.first == "\u{feff}" { text.removeFirst() }
        let rows = try boundedRows(text)
        guard let headers = rows.first?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }), rows.count <= 5001 else { throw PasswordVaultError.invalidImport }
        func column(_ choices: [String]) -> Int? { headers.firstIndex { choices.contains($0) } }
        guard let address = column(["url","website","origin","ウェブサイト","urlのアドレス"]),
              let user = column(["username","user name","login_username","ユーザ名","ユーザー名"]),
              let secret = column(["password","login_password","パスワード"]) else { throw PasswordVaultError.invalidImport }
        guard Set(headers).count == headers.count else { throw PasswordVaultError.invalidImport }
        let title = column(["name","title","タイトル"]), notes = column(["note","notes","メモ"])
        let otp = column(["otpauth","otp","totp","otpsecret"])
        var result = PasswordImportResult()
        for row in rows.dropFirst() {
            func value(_ index: Int?) -> String { guard let index, row.indices.contains(index) else { return "" }; return row[index] }
            if !value(otp).isEmpty { result.ignoredCodes += 1 }
            do {
                let site = try PasswordOrigin(value(address))
                let entry = try PasswordRecord(site: site, title: value(title), username: value(user), password: value(secret), notes: value(notes)).validated()
                result.records.append(entry)
            } catch { result.skipped += 1 }
        }
        guard !result.records.isEmpty else { throw PasswordVaultError.invalidImport }
        return result
    }
}
