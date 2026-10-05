enum EntryPickRules {
    static func unavailableReason(
        abbreviation: String,
        game: PoolGame,
        usedTeams: [String: Int],
        week: Int
    ) -> String? {
        if let usedWeek = usedTeams[abbreviation], usedWeek != week {
            return "Used in week \(usedWeek)"
        }
        if game.hasKickedOff {
            return "Locked"
        }
        return nil
    }

    static func canSelect(
        abbreviation: String,
        game: PoolGame,
        entry: ClaimedEntry,
        usedTeams: [String: Int],
        week: Int
    ) -> Bool {
        guard entry.status == .active else { return false }
        guard game.homeAbbr == abbreviation || game.awayAbbr == abbreviation else { return false }
        return unavailableReason(
            abbreviation: abbreviation,
            game: game,
            usedTeams: usedTeams,
            week: week
        ) == nil
    }

    static func canSave(
        selectedTeam: String?,
        savedTeam: String?,
        games: [PoolGame],
        entry: ClaimedEntry,
        usedTeams: [String: Int],
        week: Int
    ) -> Bool {
        guard let selectedTeam,
              selectedTeam != savedTeam,
              let game = games.first(where: {
                  $0.homeAbbr == selectedTeam || $0.awayAbbr == selectedTeam
              }) else {
            return false
        }
        return canSelect(
            abbreviation: selectedTeam,
            game: game,
            entry: entry,
            usedTeams: usedTeams,
            week: week
        )
    }

    static func saveTitle(selectedTeam: String?, savedTeam: String?) -> String {
        guard let selectedTeam else { return "Save pick" }
        let name = NFLTeam.shortName(for: selectedTeam)
        if savedTeam == nil { return "Save \(name)" }
        if selectedTeam != savedTeam { return "Change pick to \(name)" }
        return "\(name) saved"
    }

    static func teamAccessibility(abbreviation: String, allowed: Bool, reason: String?) -> String {
        let name = NFLTeam.team(abbreviation: abbreviation)?.name ?? abbreviation
        if let reason { return "\(name), \(reason)" }
        return allowed ? name : "\(name), unavailable"
    }
}
