import Foundation

enum PoolAdmins {
    static let names = ["Ralph Della Rocca", "Will Castellano"]
}

enum EntryStatus: String, Codable, Hashable {
    case active
    case pendingBuyback
    case eliminated
}

struct Buyback: Codable, Hashable {
    var eliminatedWeek: Int
    var boughtBackBeforeWeek: Int
}

struct PoolPick: Codable, Hashable, Identifiable {
    var week: Int
    var team: String
    var nickname: String

    var id: Int { week }
}

struct PoolEntry: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var section: String
    var status: EntryStatus
    var eliminatedWeek: Int?
    var buybackDeclined: Bool
    var buybacks: [Buyback]
    var picks: [PoolPick]

    var canBuyBack: Bool {
        status == .pendingBuyback
            && !buybackDeclined
            && (eliminatedWeek ?? 7) <= 6
    }

    func pick(for week: Int) -> PoolPick? {
        picks.first { $0.week == week }
    }
}

struct SurvivorPool: Codable {
    var season: Int
    var name: String
    var buybackThroughWeek: Int
    var adminNames: [String]
    var entries: [PoolEntry]

    var aliveEntries: [PoolEntry] { entries.filter { $0.status == .active } }
    var buybackEntries: [PoolEntry] { entries.filter(\.canBuyBack) }
    var eliminatedEntries: [PoolEntry] {
        entries.filter { $0.status == .eliminated || ($0.status == .pendingBuyback && !$0.canBuyBack) }
    }

    static let empty = SurvivorPool(
        season: 2026,
        name: "BH Knock-out Pool 2026",
        buybackThroughWeek: 6,
        adminNames: PoolAdmins.names,
        entries: []
    )
}

enum SurvivorPoolLoader {
    static func load() -> SurvivorPool {
        guard let url = Bundle.main.url(forResource: "Week3Pool", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let pool = try? JSONDecoder().decode(SurvivorPool.self, from: data) else {
            return .empty
        }
        return pool
    }
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
