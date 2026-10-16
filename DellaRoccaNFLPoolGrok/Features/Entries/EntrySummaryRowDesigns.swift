#if DEBUG
import SwiftUI

// Design explorations for the My Entries row. DEBUG-only scaffolding:
// referenced solely by the previews here, never shipped. The row in use is
// EntrySummaryRow. All three answer the same two questions at a glance — is
// this entry alive, and does it have this week's pick — and take the same
// inputs. They differ in how much of the season they show and in how many
// lines they take.

// MARK: - Design A · Logo thumbnail
//
// The week's pick as a 44pt chip on the leading edge, where a list thumbnail
// goes, with the name and one line of state beside it. A missing pick is a
// dashed red square with the week number, so the eye lands on it from across
// the room; an entry that is out shows a grey tile with a mark instead.

struct EntrySummaryRowA: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry

    var body: some View {
        let standing = WeekStanding(session: session, entry: entry)
        HStack(spacing: 12) {
            tile(standing)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(.body.weight(.semibold))
                Text(standing.line)
                    .font(.caption)
                    .foregroundStyle(standing.needsPick ? Color.red : Color.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func tile(_ standing: WeekStanding) -> some View {
        if let team = standing.team {
            TeamPickChip(
                abbreviation: team,
                selected: false,
                dimmed: false,
                logoURL: session.teamLogos[team],
                size: 44
            )
        } else if let week = standing.week {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.red, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .frame(width: 44, height: 44)
                .overlay {
                    Text("W\(week)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: entry.status == .pendingBuyback ? "arrow.uturn.backward" : "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(entry.status == .pendingBuyback ? Color.orange : Color.secondary)
                }
        }
    }
}

// MARK: - Design B · Season strip
//
// The whole season on the row: one 28pt chip per week, numbered beneath,
// ending in this week's slot, which is ringed green once the pick is saved and
// a dashed red square until then. A lost week is ringed red, bought back or
// not, and a week with no pick is a grey dash. The status line moves to the
// trailing edge of the name line, so the row is two lines of text plus the
// strip.

struct EntrySummaryRowB: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry

    private var picks: [Int: String] { session.picks(for: entry) }

    var body: some View {
        let standing = WeekStanding(session: session, entry: entry)
        let weeks = weeks(through: standing.week)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.label)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(entry.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !weeks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(weeks, id: \.self) { week in
                            VStack(spacing: 2) {
                                cell(week, openWeek: standing.week)
                                Text("\(week)")
                                    .font(.system(size: 9, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.label), \(entry.statusLine), \(standing.line)")
    }

    /// Every week from 1 through the open week, or through the last week the
    /// entry took part in once it is out.
    private func weeks(through openWeek: Int?) -> [Int] {
        let last = max(openWeek ?? 0, picks.keys.max() ?? 0, entry.eliminatedWeek ?? 0)
        return last > 0 ? Array(1...last) : []
    }

    @ViewBuilder
    private func cell(_ week: Int, openWeek: Int?) -> some View {
        if let team = picks[week] {
            TeamPickChip(
                abbreviation: team,
                selected: week == openWeek,
                dimmed: false,
                logoURL: session.teamLogos[team],
                size: 28
            )
            .overlay {
                if entry.resultLabel(for: week) != nil {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.red, lineWidth: 2)
                }
            }
        } else if week == openWeek {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.red, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                .frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 28, height: 28)
                .overlay {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
        }
    }
}

// MARK: - Design C · One line
//
// Name on the left, this week on the right, nothing else: a capsule in the
// team's colors reading "W4 · Lions" once the pick is in, a red outline
// reading "W4 · No pick" until then, and the status line in its place for an
// entry that is out or waiting on a buyback. The shortest row there is, for a
// player with several entries.

struct EntrySummaryRowC: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry

    var body: some View {
        let standing = WeekStanding(session: session, entry: entry)
        HStack(spacing: 12) {
            Text(entry.label)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing(standing)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func trailing(_ standing: WeekStanding) -> some View {
        if let week = standing.week, let team = standing.team {
            let color = NFLTeam.team(abbreviation: team)?.primaryColor
            Text("W\(week) · \(NFLTeam.shortName(for: team))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color?.foreground ?? .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color?.color ?? .gray, in: Capsule())
        } else if let week = standing.week {
            Text("W\(week) · No pick")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay {
                    Capsule().strokeBorder(Color.red, lineWidth: 1)
                }
        } else {
            Text(entry.statusLine)
                .font(.caption)
                .foregroundStyle(entry.status == .pendingBuyback ? Color.orange : Color.secondary)
        }
    }
}

// MARK: - Shared

/// This week's pick for an active entry, or nothing for one that is not
/// picking. `line` is the one sentence every design prints under the name.
@MainActor
private struct WeekStanding {
    let week: Int?
    let team: String?
    let statusLine: String

    init(session: PlayerSession, entry: ClaimedEntry) {
        if entry.status == .active, let week = session.openWeek {
            self.week = week
            team = session.picks(for: entry)[week]
        } else {
            week = nil
            team = nil
        }
        statusLine = entry.statusLine
    }

    var needsPick: Bool { week != nil && team == nil }

    var line: String {
        guard let week else { return statusLine }
        if let team { return "Week \(week) · \(NFLTeam.shortName(for: team))" }
        return "Week \(week) · No pick yet"
    }
}

// MARK: - Previews

/// Five entries that cover the states a row can be in: no pick yet, pick
/// saved, bought back twice and picked, knocked out with the buyback open, and
/// out for good.
private let rowDesignEntries: [ClaimedEntry] = [
    PreviewData.will,
    PreviewData.casa,
    PreviewData.standings.first { $0.id == "andrew-mehlbaum" } ?? PreviewData.will,
    PreviewData.standings.first { $0.id == "pat-buyer" } ?? PreviewData.will,
    PreviewData.standings.first { $0.id == "jordan-out" } ?? PreviewData.will,
]

/// Each design under the current row, in navigation links as My Entries has
/// them.
#Preview("Row designs") {
    let session = PreviewData.player()
    return NavigationStack {
        List {
            Section("Current") {
                ForEach(rowDesignEntries) { entry in
                    NavigationLink { EmptyView() } label: { EntrySummaryRow(session: session, entry: entry) }
                }
            }
            Section("Design A · Logo thumbnail") {
                ForEach(rowDesignEntries) { entry in
                    NavigationLink { EmptyView() } label: { EntrySummaryRowA(session: session, entry: entry) }
                }
            }
            Section("Design B · Season strip") {
                ForEach(rowDesignEntries) { entry in
                    NavigationLink { EmptyView() } label: { EntrySummaryRowB(session: session, entry: entry) }
                }
            }
            Section("Design C · One line") {
                ForEach(rowDesignEntries) { entry in
                    NavigationLink { EmptyView() } label: { EntrySummaryRowC(session: session, entry: entry) }
                }
            }
        }
    }
}
#endif
