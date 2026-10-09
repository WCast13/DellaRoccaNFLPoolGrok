import Foundation

enum EntryStatus: String, Codable, Hashable {
    case active
    case pendingBuyback
    case eliminated
}

enum EntryPin {
    /// One letter A–Z and four digits from 1–9. Zero is not used.
    static func isValid(_ raw: String) -> Bool {
        let pin = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard pin.count == 5 else { return false }
        let characters = Array(pin)
        guard let first = characters.first, ("A"..."Z").contains(first) else { return false }
        return characters.dropFirst().allSatisfy { ("1"..."9").contains($0) }
    }
}
