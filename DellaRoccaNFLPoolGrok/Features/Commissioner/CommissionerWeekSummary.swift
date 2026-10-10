import SwiftUI

/// The selected week across the whole pool: how many entries are in play, how
/// their picks are going, and how those picks spread over the teams.
///
/// Outcomes follow the server's grading rule in `grade.ts`: a tie is a loss, a
/// final game the feed has not scored is still pending, and a result already
/// graded onto the entry (its eliminating week, a bought-back week) wins over
/// the scoreboard. The numbers are a live read of the same data the grader
/// will use, not the graded record itself.
struct WeekSummary: Equatable {
    enum Outcome: Equatable {
        case won, lost, waiting, noPick
    }

    struct TeamCount: Identifiable, Equatable {
        var team: String
        var count: Int
        /// The team's own result once its game is final; `.waiting` before.
        var outcome: Outcome
        var id: String { team }
    }

    /// Entries that were alive going into this week.
    var active = 0
    var won = 0
    var lost = 0
    var waiting = 0
    var noPick = 0
    /// Every team picked this week, most-picked first.
    var teams: [TeamCount] = []

    static func make(
        entries: [ClaimedEntry],
        week: Int,
        games: [PoolGame],
        picks: (ClaimedEntry) -> [Int: String]
    ) -> WeekSummary {
        var summary = WeekSummary()
        var counts: [String: Int] = [:]
        for entry in entries {
            let entryPicks = picks(entry)
            guard isActive(entry, week: week, picks: entryPicks) else { continue }
            summary.active += 1
            let team = entryPicks[week]
            switch outcome(entry: entry, team: team, week: week, games: games) {
            case .won: summary.won += 1
            case .lost: summary.lost += 1
            case .waiting: summary.waiting += 1
            case .noPick: summary.noPick += 1
            }
            if let team {
                counts[team, default: 0] += 1
            }
        }
        summary.teams = counts
            .map { TeamCount(team: $0.key, count: $0.value, outcome: teamOutcome($0.key, games: games)) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.team < rhs.team
            }
        return summary
    }

    /// An entry was in play for `week` if it is alive now, was knocked out in
    /// that week or later, or has a pick on record for it. An entry out since
    /// an earlier week never had a pick to make.
    static func isActive(_ entry: ClaimedEntry, week: Int, picks: [Int: String]) -> Bool {
        if entry.status == .active { return true }
        if let eliminatedWeek = entry.eliminatedWeek, eliminatedWeek >= week { return true }
        return picks[week] != nil
    }

    static func outcome(entry: ClaimedEntry, team: String?, week: Int, games: [PoolGame]) -> Outcome {
        // A graded loss stands whatever the scoreboard says — it also covers a
        // week the entry lost by making no pick at all.
        if entry.resultLabel(for: week) != nil { return .lost }
        guard let team else { return .noPick }
        return teamOutcome(team, games: games)
    }

    /// Mirrors `outcome()` in grade.ts: a tie is a loss; a final without a
    /// score, or a team with no game this week, is still pending.
    static func teamOutcome(_ team: String, games: [PoolGame]) -> Outcome {
        guard let game = games.first(where: { $0.homeAbbr == team || $0.awayAbbr == team }),
              game.isFinal,
              let homeScore = game.homeScore,
              let awayScore = game.awayScore else {
            return .waiting
        }
        let isHome = game.homeAbbr == team
        let own = isHome ? homeScore : awayScore
        let other = isHome ? awayScore : homeScore
        return own > other ? .won : .lost
    }
}

/// Sits between the week's slate and the entries grid on the commissioner tab.
struct CommissionerWeekSummary: View {
    let summary: WeekSummary
    let week: Int

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                stat(summary.active, "active")
                stat(summary.won, "won", tint: summary.won > 0 ? .green : nil)
                stat(summary.lost, "lost", tint: summary.lost > 0 ? .red : nil)
                stat(summary.waiting, "waiting")
                stat(summary.noPick, "no pick", tint: summary.noPick > 0 ? .orange : nil)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statsAccessibility)

            if summary.teams.isEmpty {
                Text("No picks in for week \(week) yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(summary.teams) { team in
                        TeamCountTile(team: team)
                    }
                }
            }
        }
    }

    private func stat(_ value: Int, _ label: String, tint: Color? = nil) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var statsAccessibility: String {
        "Week \(week): \(summary.active) active, \(summary.won) won, \(summary.lost) lost, \(summary.waiting) waiting, \(summary.noPick) with no pick"
    }
}

/// One picked team and how many entries are on it, in the team's color with
/// a green or red ring once its game is decided.
private struct TeamCountTile: View {
    let team: WeekSummary.TeamCount

    var body: some View {
        let palette = NFLTeam.team(abbreviation: team.team)
        let background = palette?.primaryColor.color ?? .gray
        let foreground = palette?.primaryColor.foreground ?? .white
        HStack(spacing: 5) {
            Text(team.team)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(team.count)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(foreground.opacity(0.2), in: Capsule())
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(background, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if let ring {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(ring, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var ring: Color? {
        switch team.outcome {
        case .won: return .green
        case .lost: return .red
        case .waiting, .noPick: return nil
        }
    }

    private var accessibilityText: String {
        let name = NFLTeam.shortName(for: team.team)
        let entries = team.count == 1 ? "1 entry" : "\(team.count) entries"
        switch team.outcome {
        case .won: return "\(name), \(entries), won"
        case .lost: return "\(name), \(entries), lost"
        case .waiting, .noPick: return "\(name), \(entries)"
        }
    }
}

#if DEBUG
#Preview("Open week") {
    let session = PreviewData.commissioner()
    let summary = WeekSummary.make(
        entries: session.roster,
        week: 4,
        games: session.games(in: 4),
        picks: session.picks(for:)
    )
    return List {
        Section("Week 4 summary") {
            CommissionerWeekSummary(summary: summary, week: 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}

#Preview("Finished week") {
    let session = PreviewData.commissioner()
    let summary = WeekSummary.make(
        entries: session.roster,
        week: 3,
        games: session.games(in: 3),
        picks: session.picks(for:)
    )
    return List {
        Section("Week 3 summary") {
            CommissionerWeekSummary(summary: summary, week: 3)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}
#endif
