#if DEBUG
import SwiftUI
#endif

enum EntryPickRules {
    /// `allowKickedOff` lifts the post-kickoff "Locked" restriction, used by
    /// commissioner tools that may correct a pick after a game has started.
    static func unavailableReason(
        abbreviation: String,
        game: PoolGame,
        usedTeams: [String: Int],
        week: Int,
        allowKickedOff: Bool = false,
        lockedBy: String? = nil
    ) -> String? {
        if let usedWeek = usedTeams[abbreviation], usedWeek != week {
            return "Used in week \(usedWeek)"
        }
        if !allowKickedOff, let lockedBy, abbreviation != lockedBy {
            return "Week locked"
        }
        if !allowKickedOff, game.hasKickedOff {
            return "Locked"
        }
        return nil
    }

    /// True once the team already standing for `week` has kicked off: the week's
    /// result is determined, so no other team may be substituted. An unverifiable
    /// standing pick fails closed, matching the server.
    static func standingPickHasKickedOff(
        savedTeam: String,
        games: [PoolGame],
        week: Int
    ) -> Bool {
        guard let game = games.first(where: {
            $0.week == week && ($0.homeAbbr == savedTeam || $0.awayAbbr == savedTeam)
        }) else {
            return true
        }
        return game.hasKickedOff
    }

    static func canSelect(
        abbreviation: String,
        game: PoolGame,
        entry: ClaimedEntry,
        usedTeams: [String: Int],
        week: Int,
        allowKickedOff: Bool = false,
        lockedBy: String? = nil
    ) -> Bool {
        guard entry.status == .active else { return false }
        guard game.homeAbbr == abbreviation || game.awayAbbr == abbreviation else { return false }
        return unavailableReason(
            abbreviation: abbreviation,
            game: game,
            usedTeams: usedTeams,
            week: week,
            allowKickedOff: allowKickedOff,
            lockedBy: lockedBy
        ) == nil
    }

    static func canSave(
        selectedTeam: String?,
        savedTeam: String?,
        games: [PoolGame],
        entry: ClaimedEntry,
        usedTeams: [String: Int],
        week: Int,
        allowKickedOff: Bool = false
    ) -> Bool {
        guard let selectedTeam,
              selectedTeam != savedTeam,
              let game = games.first(where: {
                  $0.homeAbbr == selectedTeam || $0.awayAbbr == selectedTeam
              }) else {
            return false
        }
        // Computed here rather than taken as a parameter: this is the gate on
        // submission, and a caller that forgot to pass it would reopen the hole.
        if !allowKickedOff, let savedTeam,
           standingPickHasKickedOff(savedTeam: savedTeam, games: games, week: week) {
            return false
        }
        return canSelect(
            abbreviation: selectedTeam,
            game: game,
            entry: entry,
            usedTeams: usedTeams,
            week: week,
            allowKickedOff: allowKickedOff
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

#if DEBUG
#Preview("Pick rules") {
    let session = PreviewData.player()
    let used = session.usedTeams(for: PreviewData.will)
    let open = PreviewData.games.first { $0.id == "w4-gb" } ?? PreviewData.games[0]
    let usedGame = PreviewData.games.first { $0.id == "w4-jax" } ?? PreviewData.games[0]
    let locked = PreviewData.games.first { $0.id == "w4-locked" } ?? PreviewData.games[0]
    return List {
        LabeledContent(
            "Packers",
            value: EntryPickRules.unavailableReason(abbreviation: "GB", game: open, usedTeams: used, week: 4) ?? "Available"
        )
        LabeledContent(
            "Jaguars",
            value: EntryPickRules.unavailableReason(abbreviation: "JAX", game: usedGame, usedTeams: used, week: 4) ?? "Available"
        )
        LabeledContent(
            "Giants",
            value: EntryPickRules.unavailableReason(abbreviation: "NYG", game: locked, usedTeams: used, week: 4) ?? "Available"
        )
        LabeledContent("Save", value: EntryPickRules.saveTitle(selectedTeam: "GB", savedTeam: nil))
        LabeledContent("Saved", value: EntryPickRules.saveTitle(selectedTeam: "DET", savedTeam: "DET"))
    }
}
#endif
