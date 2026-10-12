#if DEBUG
import SwiftUI

// Design explorations for the commissioner week summary. DEBUG-only
// scaffolding: referenced solely by the previews here, never shipped. The
// summary in use is CommissionerWeekSummary; each design below pairs with the
// header design of the same letter in CommissionerWeekHeaderDesigns. All take
// the same WeekSummary the shipping view takes.

// MARK: - Design A · Capsule strip and logo chips
//
// Everything on two scrolling rows, for the least vertical space: the five
// counts as tinted capsules, then one logo chip per picked team with its count
// in a badge. The outcome ring sits on the chip, as it does on the grid.

struct CommissionerWeekSummaryA: View {
    let summary: WeekSummary
    let week: Int
    var logoURL: (String) -> URL? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    capsule(summary.active, "active", .accentColor)
                    capsule(summary.won, "won", .green)
                    capsule(summary.lost, "lost", .red)
                    capsule(summary.waiting, "waiting", .gray)
                    capsule(summary.noPick, "no pick", .orange)
                }
                .padding(.horizontal, 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statsAccessibility)

            if summary.teams.isEmpty {
                Text("No picks in for week \(week) yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(summary.teams) { team in
                            logoChip(team)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 6)
                }
            }
        }
    }

    private func capsule(_ value: Int, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(value > 0 ? tint : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((value > 0 ? tint : Color.secondary).opacity(0.12), in: Capsule())
    }

    private func logoChip(_ team: WeekSummary.TeamCount) -> some View {
        VStack(spacing: 3) {
            TeamPickChip(
                abbreviation: team.team,
                selected: false,
                dimmed: false,
                logoURL: logoURL(team.team),
                size: 44
            )
            .overlay {
                if let ring = ringColor(team.outcome) {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(ring, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                Text("\(team.count)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.background, in: Capsule())
                    .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 1))
                    .offset(x: 6, y: -6)
            }
            Text(team.team)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(teamAccessibility(team))
    }

    private var statsAccessibility: String {
        "Week \(week): \(summary.active) active, \(summary.won) won, \(summary.lost) lost, \(summary.waiting) waiting, \(summary.noPick) with no pick"
    }
}

// MARK: - Design B · Stacked bar and ranked team bars
//
// A dashboard read: the active count as the headline, a proportional bar of
// how those entries are doing, then the most-picked teams as bars in their own
// colors so the concentration of the pool on one team is obvious.

struct CommissionerWeekSummaryB: View {
    let summary: WeekSummary
    let week: Int

    private let shownTeams = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.active)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(summary.active == 1 ? "entry active" : "entries active")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            OutcomeBar(summary: summary)
            HStack(spacing: 12) {
                legend(summary.won, "won", .green)
                legend(summary.lost, "lost", .red)
                legend(summary.waiting, "waiting", .gray)
                legend(summary.noPick, "no pick", .orange)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(summary.won) won, \(summary.lost) lost, \(summary.waiting) waiting, \(summary.noPick) with no pick")

            if summary.teams.isEmpty {
                Text("No picks in for week \(week) yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                teamBars
            }
        }
    }

    private func legend(_ value: Int, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text("\(value) \(label)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var teamBars: some View {
        let shown = Array(summary.teams.prefix(shownTeams))
        let maxCount = CGFloat(max(shown.first?.count ?? 1, 1))
        return VStack(spacing: 6) {
            ForEach(shown) { team in
                HStack(spacing: 8) {
                    Text(team.team)
                        .font(.caption.weight(.semibold))
                        .frame(width: 36, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(NFLTeam.team(abbreviation: team.team)?.primaryColor.color ?? .gray)
                            .frame(width: max(8, geo.size.width * CGFloat(team.count) / maxCount))
                    }
                    .frame(height: 14)
                    Text("\(team.count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .frame(width: 22, alignment: .trailing)
                    outcomeMark(team.outcome)
                        .frame(width: 16)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(teamAccessibility(team))
            }
            if summary.teams.count > shown.count {
                Text("+\(summary.teams.count - shown.count) more teams")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func outcomeMark(_ outcome: WeekSummary.Outcome) -> some View {
        switch outcome {
        case .won:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .lost:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .waiting, .noPick:
            Color.clear
        }
    }
}

/// Won, lost, waiting, and no-pick as proportions of the active entries.
private struct OutcomeBar: View {
    let summary: WeekSummary

    var body: some View {
        GeometryReader { geo in
            let total = CGFloat(max(summary.active, 1))
            HStack(spacing: 2) {
                segment(summary.won, .green, width: geo.size.width, total: total)
                segment(summary.lost, .red, width: geo.size.width, total: total)
                segment(summary.waiting, .gray, width: geo.size.width, total: total)
                segment(summary.noPick, .orange, width: geo.size.width, total: total)
            }
        }
        .frame(height: 10)
        .background(Color(.systemGray5), in: Capsule())
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segment(_ count: Int, _ color: Color, width: CGFloat, total: CGFloat) -> some View {
        if count > 0 {
            Rectangle()
                .fill(color)
                .frame(width: max(3, width * CGFloat(count) / total))
        }
    }
}

// MARK: - Design C · Donut with legend and a capsule rail
//
// The active count sits inside a ring split by outcome, with the legend beside
// it, so the week's health is one glance. Teams run along a single rail of
// colored capsules beneath, ringed green or red once their game is decided.

struct CommissionerWeekSummaryC: View {
    let summary: WeekSummary
    let week: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                OutcomeDonut(summary: summary)
                VStack(alignment: .leading, spacing: 6) {
                    legendRow(summary.won, "Won", .green)
                    legendRow(summary.lost, "Lost", .red)
                    legendRow(summary.waiting, "Waiting on a result", .gray)
                    legendRow(summary.noPick, "No pick", .orange)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Week \(week): \(summary.active) active, \(summary.won) won, \(summary.lost) lost, \(summary.waiting) waiting, \(summary.noPick) with no pick")

            if summary.teams.isEmpty {
                Text("No picks in for week \(week) yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(summary.teams) { team in
                            teamCapsule(team)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func legendRow(_ value: Int, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func teamCapsule(_ team: WeekSummary.TeamCount) -> some View {
        let palette = NFLTeam.team(abbreviation: team.team)
        let background = palette?.primaryColor.color ?? .gray
        let foreground = palette?.primaryColor.foreground ?? .white
        return HStack(spacing: 5) {
            Text(team.team)
                .font(.caption.weight(.semibold))
            Text("\(team.count)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .background(foreground.opacity(0.2), in: Capsule())
        }
        .foregroundStyle(foreground)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
        .overlay {
            if let ring = ringColor(team.outcome) {
                Capsule().strokeBorder(ring, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(teamAccessibility(team))
    }
}

/// A ring split by outcome, the active count in the middle.
private struct OutcomeDonut: View {
    let summary: WeekSummary

    private struct Segment: Identifiable {
        var id: Int
        var start: CGFloat
        var end: CGFloat
        var color: Color
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 11)
            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(summary.active)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
    }

    private var segments: [Segment] {
        let total = CGFloat(max(summary.active, 1))
        let parts: [(Int, Color)] = [
            (summary.won, .green), (summary.lost, .red), (summary.waiting, .gray), (summary.noPick, .orange),
        ]
        var start: CGFloat = 0
        var out: [Segment] = []
        for (index, part) in parts.enumerated() where part.0 > 0 {
            let end = start + CGFloat(part.0) / total
            out.append(Segment(id: index, start: start, end: end, color: part.1))
            start = end
        }
        return out
    }
}

// MARK: - Shared

private func ringColor(_ outcome: WeekSummary.Outcome) -> Color? {
    switch outcome {
    case .won: return .green
    case .lost: return .red
    case .waiting, .noPick: return nil
    }
}

private func teamAccessibility(_ team: WeekSummary.TeamCount) -> String {
    let name = NFLTeam.shortName(for: team.team)
    let entries = team.count == 1 ? "1 entry" : "\(team.count) entries"
    switch team.outcome {
    case .won: return "\(name), \(entries), won"
    case .lost: return "\(name), \(entries), lost"
    case .waiting, .noPick: return "\(name), \(entries)"
    }
}

// MARK: - Previews

#Preview("Summary designs · open week") {
    let session = PreviewData.commissioner()
    let summary = WeekSummary.make(entries: session.roster, week: 4, games: session.games(in: 4), picks: session.picks(for:))
    return List {
        Section("Current") {
            CommissionerWeekSummary(summary: summary, week: 4)
        }
        Section("Design A · Capsules and logos") {
            CommissionerWeekSummaryA(summary: summary, week: 4) { session.teamLogos[$0] }
        }
        Section("Design B · Bars") {
            CommissionerWeekSummaryB(summary: summary, week: 4)
        }
        Section("Design C · Donut") {
            CommissionerWeekSummaryC(summary: summary, week: 4)
        }
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
}

#Preview("Summary designs · finished week") {
    let session = PreviewData.commissioner()
    let summary = WeekSummary.make(entries: session.roster, week: 3, games: session.games(in: 3), picks: session.picks(for:))
    return List {
        Section("Current") {
            CommissionerWeekSummary(summary: summary, week: 3)
        }
        Section("Design A · Capsules and logos") {
            CommissionerWeekSummaryA(summary: summary, week: 3) { session.teamLogos[$0] }
        }
        Section("Design B · Bars") {
            CommissionerWeekSummaryB(summary: summary, week: 3)
        }
        Section("Design C · Donut") {
            CommissionerWeekSummaryC(summary: summary, week: 3)
        }
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
}

/// Each header with its matching summary, stacked as they would sit at the top
/// of the tab, with the current pair first. Step the week to see every design
/// follow.
#Preview("Design pairs in the tab") {
    @Previewable @State var week = 4
    let session = PreviewData.commissioner()
    let scheduled = Array(Set(session.games.map(\.week))).sorted()
    let summary = WeekSummary.make(entries: session.roster, week: week, games: session.games(in: week), picks: session.picks(for:))
    return List {
        Section("Current") {
            CommissionerWeekHeader(week: $week, scheduledWeeks: scheduled, openWeek: session.openWeek)
            CommissionerWeekSummary(summary: summary, week: week)
        }
        Section("Design A") {
            CommissionerWeekHeaderA(week: $week, scheduledWeeks: scheduled, openWeek: session.openWeek)
            CommissionerWeekSummaryA(summary: summary, week: week) { session.teamLogos[$0] }
        }
        Section("Design B") {
            CommissionerWeekHeaderB(
                week: $week,
                scheduledWeeks: scheduled,
                openWeek: session.openWeek,
                kickoffs: session.games(in: week).map(\.kickoff)
            )
            CommissionerWeekSummaryB(summary: summary, week: week)
        }
        Section("Design C") {
            CommissionerWeekHeaderC(week: $week, scheduledWeeks: scheduled, openWeek: session.openWeek)
            CommissionerWeekSummaryC(summary: summary, week: week)
        }
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
}
#endif
