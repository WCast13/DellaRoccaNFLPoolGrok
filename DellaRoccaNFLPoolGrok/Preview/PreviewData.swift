#if DEBUG
import Foundation

enum PreviewData {
    static func signedOut() -> PlayerSession {
        PlayerSession(preview: PlayerSession.PreviewSample())
    }

    static func loading() -> PlayerSession {
        PlayerSession(preview: PlayerSession.PreviewSample(
            userID: "preview-user",
            accountLabel: "wcastellano13@gmail.com",
            standingsLoaded: false
        ))
    }

    static func claim() -> PlayerSession {
        PlayerSession(preview: PlayerSession.PreviewSample(
            userID: "preview-user",
            accountLabel: "wcastellano13@gmail.com"
        ))
    }

    static func player() -> PlayerSession {
        PlayerSession(preview: PlayerSession.PreviewSample(
            userID: "preview-user",
            accountLabel: "wcastellano13@gmail.com",
            entries: [will, casa],
            games: games,
            privatePicks: privatePicks,
            standings: standings,
            standingsLoaded: true,
            teamLogos: logos
        ))
    }

    static func commissioner() -> PlayerSession {
        PlayerSession(preview: PlayerSession.PreviewSample(
            userID: "preview-commissioner",
            accountLabel: "wcastellano13@gmail.com",
            entries: [will, casa],
            games: games,
            privatePicks: privatePicks,
            standings: standings,
            standingsLoaded: true,
            isAdmin: true,
            privatePicksReady: true,
            teamLogos: logos,
            activityLog: activity
        ))
    }

    /// Knocked out in week 3 with the decision still open.
    static func pendingBuyback() -> PlayerSession {
        PlayerSession(preview: PlayerSession.PreviewSample(
            userID: "preview-user",
            accountLabel: "wcastellano13@gmail.com",
            entries: [knockedOut],
            games: games,
            standings: standings,
            standingsLoaded: true,
            teamLogos: logos
        ))
    }

    /// Elected the buyback, owes the fee, has not yet made the week-4 pick.
    static func boughtBackUnpaid() -> PlayerSession {
        PlayerSession(preview: PlayerSession.PreviewSample(
            userID: "preview-user",
            accountLabel: "wcastellano13@gmail.com",
            entries: [electedIn],
            games: games,
            standings: standings,
            standingsLoaded: true,
            teamLogos: logos
        ))
    }

    /// A day of commissioner-log traffic, newest first, as the listener delivers it.
    static let activity: [ActivityEvent] = [
        event("pick.changed", "Casa Castellano changed week 4 from GB to DET by a commissioner", minutesAgo: 4,
              role: "commissioner", email: "wcastellano13@gmail.com", entry: "casa-castellano", label: "Casa Castellano", week: 4, team: "DET"),
        event("pick.submitted", "Will Castellano picked DET for week 4", minutesAgo: 12,
              role: "player", email: "wcastellano13@gmail.com", entry: "will-castellano", label: "Will Castellano", week: 4, team: "DET"),
        event("auth.signIn", "wcastellano13@gmail.com signed in (commissioner)", minutesAgo: 15,
              role: "commissioner", email: "wcastellano13@gmail.com"),
        event("system.sync", "Hourly sync ran: 272 games, 0 spreads, 3 picks published, graded nothing", minutesAgo: 41, role: "system"),
        event("buyback.elected", "Pat Buyer elected to buy back in after week 3", minutesAgo: 95,
              role: "player", email: "pat@example.com", entry: "pat-buyer", label: "Pat Buyer", week: 3),
        event("buyback.recorded", "Commissioner recorded a buyback for Sam Buyer after week 3", minutesAgo: 130,
              role: "commissioner", email: "wcastellano13@gmail.com", entry: "sam-buyer", label: "Sam Buyer", week: 3),
        event("buyback.feePaid", "Commissioner marked Sam Buyer's buyback fee paid", minutesAgo: 129,
              role: "commissioner", email: "wcastellano13@gmail.com", entry: "sam-buyer", label: "Sam Buyer"),
        event("system.weekGraded", "Week 3 graded: 104 wins, 2 losses, 0 no pick, 0 not final, 0 buybacks lapsed", minutesAgo: 60 * 26, role: "system", week: 3),
        event("entry.knockedOut", "Pat Buyer lost week 3 with CIN; buyback open", minutesAgo: 60 * 26,
              role: "system", entry: "pat-buyer", label: "Pat Buyer", week: 3, team: "CIN"),
        event("buyback.lapsed", "Jordan Out did not buy back after week 2; out", minutesAgo: 60 * 26 + 1,
              role: "system", entry: "jordan-out", label: "Jordan Out", week: 2),
        event("entry.claimed", "pat@example.com claimed Pat Buyer", minutesAgo: 60 * 50,
              role: "player", email: "pat@example.com", entry: "pat-buyer", label: "Pat Buyer"),
        event("system.syncFailed", "Hourly sync failed: Odds API returned 429", minutesAgo: 60 * 51, role: "system"),
        event("commissioner.added", "Commissioner added ralph@example.com as a commissioner", minutesAgo: 60 * 72,
              role: "commissioner", email: "wcastellano13@gmail.com"),
    ]

    static let knockedOut = entry(
        id: "pat-buyer",
        label: "Pat Buyer",
        status: .pendingBuyback,
        eliminatedWeek: 3,
        picks: [1: "JAX", 2: "SF", 3: "CIN"]
    )

    static let electedIn = entry(
        id: "pat-buyer",
        label: "Pat Buyer",
        status: .active,
        eliminatedWeek: 3,
        picks: [1: "JAX", 2: "SF", 3: "CIN"],
        buybackElection: .buyIn,
        buybackUnpaid: true
    )

    static let will = entry(
        id: "will-castellano",
        label: "Will Castellano",
        picks: [1: "JAX", 2: "SF"],
        isCommissioner: true
    )

    static let casa = entry(
        id: "casa-castellano",
        label: "Casa Castellano",
        picks: [1: "PHI", 2: "BUF", 3: "KC"]
    )

    static let standings: [ClaimedEntry] = [
        entry(id: "ralph-della-rocca", label: "Ralph Della Rocca", picks: [1: "PHI", 2: "BUF", 3: "KC"], isCommissioner: true),
        will,
        casa,
        entry(id: "andrew-mehlbaum", label: "Andrew Mehlbaum", picks: [1: "DAL", 2: "MIA", 3: "BAL"], buybackWeeks: [1, 2]),
        entry(id: "alex-nologin", label: "Alex No Login", picks: [1: "TB", 2: "NYJ", 3: "LAR"], isClaimed: false),
        entry(id: "chris-early", label: "Chris Early", picks: [1: "NE", 2: "LAR", 3: "GB", 4: "NYG"]),
        entry(
            id: "pat-buyer",
            label: "Pat Buyer",
            status: .pendingBuyback,
            eliminatedWeek: 3,
            picks: [1: "NE", 2: "LAR", 3: "CIN"]
        ),
        entry(
            id: "sam-buyer",
            label: "Sam Buyer",
            status: .pendingBuyback,
            eliminatedWeek: 3,
            picks: [1: "TB", 2: "NYJ", 3: "CIN"],
            isClaimed: false
        ),
        entry(
            id: "allen-morrow",
            label: "Allen Morrow",
            status: .eliminated,
            eliminatedWeek: 1,
            buybackDeclined: true,
            picks: [1: "DAL"]
        ),
        entry(
            id: "jordan-out",
            label: "Jordan Out",
            status: .eliminated,
            eliminatedWeek: 2,
            buybackDeclined: true,
            picks: [1: "TB", 2: "NYJ"]
        ),
    ]

    static let privatePicks: [String: [Int: String]] = [
        "ralph-della-rocca": [4: "DET"],
        "casa-castellano": [4: "DET"],
        "andrew-mehlbaum": [4: "GB"],
    ]

    static let games: [PoolGame] = [
        game("w1", week: 1, away: "NYJ", home: "NE", daysAgo: 21, spread: -3),
        game("w2", week: 2, away: "MIA", home: "SF", daysAgo: 14, spread: -6.5),
        game("w3", week: 3, away: "CIN", home: "PIT", daysAgo: 7, spread: -2.5),
        game("w4-locked", week: 4, away: "NYG", home: "DAL", daysAgo: 2, spread: -6.5),
        game("w4-jax", week: 4, away: "JAX", home: "PIT", daysAhead: 3, spread: -2.5),
        game("w4-gb", week: 4, away: "GB", home: "DET", daysAhead: 4, spread: -1.5),
        game("w4-kc", week: 4, away: "KC", home: "BUF", daysAhead: 5, spread: -3),
    ]

    static let logos: [String: URL] = {
        let abbreviations = ["JAX", "SF", "PHI", "BUF", "KC", "DET", "GB", "DAL", "NYG", "NE", "LAR", "CIN", "TB", "NYJ", "BAL", "MIA", "PIT"]
        return Dictionary(uniqueKeysWithValues: abbreviations.compactMap { abbr in
            URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/\(abbr.lowercased()).png").map { (abbr, $0) }
        })
    }()

    private static func entry(
        id: String,
        label: String,
        status: EntryStatus = .active,
        eliminatedWeek: Int? = nil,
        buybackDeclined: Bool = false,
        picks: [Int: String] = [:],
        buybackWeeks: [Int] = [],
        isClaimed: Bool = true,
        isCommissioner: Bool = false,
        buybackElection: BuybackElection? = nil,
        buybackUnpaid: Bool = false
    ) -> ClaimedEntry {
        ClaimedEntry(
            id: id,
            label: label,
            status: status,
            eliminatedWeek: eliminatedWeek,
            buybackDeclined: buybackDeclined,
            picks: picks,
            usedTeams: Dictionary(uniqueKeysWithValues: picks.map { ($0.value, $0.key) }),
            buybackWeeks: buybackWeeks,
            isClaimed: isClaimed,
            isCommissioner: isCommissioner,
            buybackElection: buybackElection,
            buybackUnpaid: buybackUnpaid
        )
    }

    private static func event(
        _ type: String,
        _ summary: String,
        minutesAgo: Double,
        role: String,
        email: String? = nil,
        entry: String? = nil,
        label: String? = nil,
        week: Int? = nil,
        team: String? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            id: "\(type)-\(Int(minutesAgo))",
            at: Date().addingTimeInterval(-minutesAgo * 60),
            type: type,
            summary: summary,
            actorRole: role,
            actorEmail: email,
            entryId: entry,
            entryLabel: label,
            week: week,
            team: team
        )
    }

    private static func game(
        _ id: String,
        week: Int,
        away: String,
        home: String,
        daysAgo: Double = 0,
        daysAhead: Double = 0,
        spread: Double?,
        homeScore: Int? = nil,
        awayScore: Int? = nil
    ) -> PoolGame {
        let seconds = (daysAhead - daysAgo) * 24 * 60 * 60
        let isFinal = seconds <= 0
        return PoolGame(
            id: id,
            week: week,
            homeAbbr: home,
            awayAbbr: away,
            kickoff: Date().addingTimeInterval(seconds),
            status: isFinal ? "final" : "scheduled",
            spreadHome: spread,
            // A finished fixture gets a plausible score so the commissioner
            // grid has something to render in both states.
            homeScore: homeScore ?? (isFinal ? 24 : nil),
            awayScore: awayScore ?? (isFinal ? 17 : nil)
        )
    }
}
#endif
