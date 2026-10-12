import SwiftUI

/// One team on the week's slate, as the commissioner pick sheet sees it.
struct CommissionerPickChoice: Identifiable, Hashable {
    let team: String
    let game: PoolGame
    /// The week this entry already used the team, when it did. Such a team
    /// cannot be picked again; the grid dims it.
    let usedWeek: Int?

    var id: String { team }
    var isHome: Bool { game.homeAbbr == team }
    var opponent: String { isHome ? game.awayAbbr : game.homeAbbr }
    /// "vs DAL" at home, "@ DAL" away.
    var opponentLabel: String { isHome ? "vs \(opponent)" : "@ \(opponent)" }
    /// "Lions", matching the names on the pool sheet.
    var shortName: String { NFLTeam.shortName(for: team) }
}

/// Everything the pick sheet's team grid needs to draw the week's teams and
/// report a tap, computed once by `CommissionerPickSheet` from the live
/// session.
///
/// The grid is pure drawing. It rings the highlighted team, dims the used
/// ones, shows a spinner on the one being saved, and calls `onPick` when a
/// team is tapped; the sheet owns the rule check, the save, the after-kickoff
/// confirmation, and the dismissal.
struct CommissionerPickSlate {
    let week: Int
    let entry: ClaimedEntry
    /// The week's games in kickoff order.
    let games: [PoolGame]
    /// Every team on the slate in slate order: away then home, game by game.
    let choices: [CommissionerPickChoice]
    /// The pick standing for this week, public or private.
    let savedTeam: String?
    /// The team just tapped, while its save is in flight.
    let pendingTeam: String?
    let logos: [String: URL]
    /// A tap on a team. The sheet re-checks the rules and saves.
    let onPick: (CommissionerPickChoice) -> Void

    private let used: [String: Int]

    init(
        week: Int,
        entry: ClaimedEntry,
        games: [PoolGame],
        used: [String: Int],
        savedTeam: String?,
        pendingTeam: String?,
        logos: [String: URL],
        onPick: @escaping (CommissionerPickChoice) -> Void
    ) {
        self.week = week
        self.entry = entry
        self.games = games
        self.used = used
        self.savedTeam = savedTeam
        self.pendingTeam = pendingTeam
        self.logos = logos
        self.onPick = onPick
        choices = games.flatMap { game in
            [game.awayAbbr, game.homeAbbr].map { team in
                let usedWeek = used[team]
                return CommissionerPickChoice(
                    team: team,
                    game: game,
                    usedWeek: usedWeek == week ? nil : usedWeek
                )
            }
        }
    }

    /// Only an alive entry can be given a pick.
    var canPick: Bool { entry.status == .active }

    /// The team to ring: the one being saved, else the one saved.
    var highlightedTeam: String? { pendingTeam ?? savedTeam }

    func isHighlighted(_ team: String) -> Bool { highlightedTeam == team }
    func isPending(_ team: String) -> Bool { pendingTeam == team }
    func isSaved(_ team: String) -> Bool { savedTeam == team }

    /// Whether a tap on this team would do anything: the entry is alive and
    /// the team is not used elsewhere. A save already in flight does not block
    /// a new tap; the queue lets the later choice supersede it. Mirrors
    /// `EntryPickRules.canSelect` with the commissioner's after-kickoff
    /// allowance; the sheet checks `canSave` again at tap time.
    func canSelect(_ choice: CommissionerPickChoice) -> Bool {
        EntryPickRules.canSelect(
            abbreviation: choice.team,
            game: choice.game,
            entry: entry,
            usedTeams: used,
            week: week,
            allowKickedOff: true
        )
    }

    /// A used team, or any team of an entry that is out, draws faded, unless
    /// it is the one ringed.
    func isDimmed(_ choice: CommissionerPickChoice) -> Bool {
        (choice.usedWeek != nil || !canPick) && !isHighlighted(choice.team)
    }

    /// Kickoff before the game; the team's own result once it is final. A
    /// tie reads as tied here but counts as a loss when graded. Spoken only;
    /// the grid shows none of it.
    func state(of choice: CommissionerPickChoice) -> String {
        let game = choice.game
        if game.isFinal, let homeScore = game.homeScore, let awayScore = game.awayScore {
            let own = choice.isHome ? homeScore : awayScore
            let other = choice.isHome ? awayScore : homeScore
            if own > other { return "Won \(own)–\(other)" }
            if own < other { return "Lost \(own)–\(other)" }
            return "Tied \(own)–\(other)"
        }
        if game.isFinal { return "Final" }
        if game.hasKickedOff { return "In progress" }
        return game.kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    func accessibilityLabel(_ choice: CommissionerPickChoice) -> String {
        if let usedWeek = choice.usedWeek {
            return "\(choice.shortName), used in week \(usedWeek)"
        }
        return "\(choice.shortName) \(choice.opponentLabel), \(state(of: choice))"
    }

    /// What a tap does, for VoiceOver. Empty when a tap does nothing.
    func accessibilityHint(_ choice: CommissionerPickChoice) -> String {
        guard canSelect(choice), !isSaved(choice.team) else { return "" }
        return "Saves this pick for week \(week)"
    }
}

#if DEBUG
extension CommissionerPickSlate {
    /// The slate the sheet would build from the commissioner fixtures, for
    /// previewing the grid on its own, including states only a tap produces,
    /// such as a save in flight.
    static func preview(
        entryID: String = PreviewData.will.id,
        week: Int = 4,
        pendingTeam: String? = nil
    ) -> CommissionerPickSlate {
        let session = PreviewData.commissioner()
        let entry = session.roster.first { $0.id == entryID } ?? PreviewData.will
        return CommissionerPickSlate(
            week: week,
            entry: entry,
            games: session.games(in: week),
            used: session.usedTeams(for: entry),
            savedTeam: session.picks(for: entry)[week],
            pendingTeam: pendingTeam,
            logos: session.teamLogos
        ) { _ in }
    }
}
#endif
