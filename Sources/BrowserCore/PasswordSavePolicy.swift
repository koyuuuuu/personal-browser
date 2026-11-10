import Foundation

/// A proposal never mutates the vault. The native user must accept it first.
public enum PasswordSavePolicy {
    public enum Proposal: Equatable {
        case insert(PasswordRecord), update(PasswordRecord), unchanged, chooseAccount
    }
    public static func proposal(_ candidate: PasswordRecord, records: [PasswordRecord], passwordChange: Bool,
                                accountID: UUID? = nil) throws -> Proposal {
        let candidate = try candidate.validated()
        let matches = records.filter { $0.site == candidate.site }
        var value = candidate
        if passwordChange && candidate.username.isEmpty && !matches.isEmpty {
            let chosen = accountID.flatMap { id in matches.first { $0.id == id } }
            guard let account = chosen ?? (matches.count == 1 ? matches.first : nil) else { return .chooseAccount }
            value.username = account.username
        }
        if let existing = matches.first(where: { $0.accountKey == value.accountKey }) {
            guard !existing.password.utf8.elementsEqual(value.password.utf8) else { return .unchanged }
            var updated = existing; updated.password = value.password
            return .update(updated) // Preserve identity, notes and title.
        }
        return .insert(value)
    }
}
