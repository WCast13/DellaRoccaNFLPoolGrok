#if DEBUG
import SwiftUI

// Design explorations for the commissioner entries grid. DEBUG-only
// scaffolding: referenced solely by the previews here, never shipped. The grid
// in use is CommissionerEntriesGrid. All three keep its contract: a pinned
// entry column, weeks that scroll together so a week reads straight down, and
// a tap on the name that opens the pick sheet. Each takes the same inputs.

// MARK: - Design A · Logo matrix
//
// Logos instead of colored abbreviations, so a week reads by crest rather than
// by three letters. Results move from a ring around the cell to a small badge
// on its corner: a red cross for a loss, a green check for a win once the game
// is final, a green return arrow for a bought-back week. Rows alternate
// backgrounds, the selected week's column is tinted, and the status tag under
// the name becomes a colored dot beside it, which lets the row sit at 44pt.

struct CommissionerEntriesGridA: View {
    @Bindable var session: PlayerSession
    let entries: [ClaimedEntry]
    let throughWeek: Int
    var emptyMessage = "No entries yet."
    let onSelect: (ClaimedEntry) -> Void

    private let rowHeight: CGFloat = 44
    private let headerHeight: CGFloat = 22
    private let cellWidth: CGFloat = 46
    private let nameWidth: CGFloat = 112

    private var weeks: [Int] { Array(1...max(1, throughWeek)) }

    var body: some View {
        if entries.isEmpty {
            Text(emptyMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            let gamesByWeek = Dictionary(grouping: session.games, by: \.week)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Entry")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: nameWidth, height: headerHeight, alignment: .leading)
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor(entry))
                                    .frame(width: 7, height: 7)
                                Text(entry.label)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(width: nameWidth, height: rowHeight, alignment: .leading)
                            .background(stripe(index))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(entry.label), \(statusTag(entry))")
                        .accessibilityHint("Opens the week \(throughWeek) pick for this entry")
                    }
                }
                Divider()
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(weeks, id: \.self) { week in
                                Text("W\(week)")
                                    .font(.caption2.weight(week == throughWeek ? .bold : .regular))
                                    .foregroundStyle(week == throughWeek ? .primary : .secondary)
                                    .frame(width: cellWidth, height: headerHeight)
                            }
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            let picks = session.picks(for: entry)
                            HStack(spacing: 0) {
                                ForEach(weeks, id: \.self) { week in
                                    cell(entry, week: week, team: picks[week], games: gamesByWeek[week] ?? [])
                                        .frame(width: cellWidth, height: rowHeight)
                                }
                            }
                            .background(stripe(index))
                        }
                    }
                }
            }
        }
    }

    private func stripe(_ index: Int) -> Color {
        index.isMultiple(of: 2) ? Color.clear : Color(.secondarySystemBackground)
    }

    @ViewBuilder
    private func cell(_ entry: ClaimedEntry, week: Int, team: String?, games: [PoolGame]) -> some View {
        let result = entry.resultLabel(for: week)
        let badge = badge(entry, week: week, team: team, result: result, games: games)
        ZStack {
            if week == throughWeek {
                Color.accentColor.opacity(0.08)
            }
            if let team {
                TeamPickChip(
                    abbreviation: team,
                    selected: false,
                    dimmed: result != nil,
                    logoURL: session.teamLogos[team],
                    size: 32
                )
            } else {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                Image(systemName: badge.symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(badge.color, in: Circle())
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1))
                    .offset(x: -3, y: -3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cellLabel(entry, week: week, team: team, result: result, badge: badge))
    }

    private func badge(_ entry: ClaimedEntry, week: Int, team: String?, result: String?, games: [PoolGame]) -> (symbol: String, color: Color)? {
        if result == "Bought back" { return ("arrow.uturn.backward", .green) }
        if result == "Loss" { return ("xmark", .red) }
        guard let team else { return nil }
        switch WeekSummary.teamOutcome(team, games: games) {
        case .won: return ("checkmark", .green)
        case .lost: return ("xmark", .red)
        case .waiting, .noPick: return nil
        }
    }

    private func cellLabel(_ entry: ClaimedEntry, week: Int, team: String?, result: String?, badge: (symbol: String, color: Color)?) -> String {
        let name = team.map { NFLTeam.shortName(for: $0) } ?? "no pick"
        if let result { return "\(entry.label), week \(week), \(name), \(result)" }
        if let badge { return "\(entry.label), week \(week), \(name), \(badge.symbol == "checkmark" ? "won" : "lost")" }
        return "\(entry.label), week \(week), \(name)"
    }
}

// MARK: - Design B · Dense matrix
//
// Built for a 380-entry pool: 26pt rows and 34pt cells put roughly twice as
// many entries on screen as the current grid. The status moves into the color
// of the name, the week headers drop to bare numbers, and a result is a thin
// ring. The selected week's column is tinted so the eye lands on it.

struct CommissionerEntriesGridB: View {
    @Bindable var session: PlayerSession
    let entries: [ClaimedEntry]
    let throughWeek: Int
    var emptyMessage = "No entries yet."
    let onSelect: (ClaimedEntry) -> Void

    private let rowHeight: CGFloat = 26
    private let headerHeight: CGFloat = 18
    private let cellWidth: CGFloat = 34
    private let nameWidth: CGFloat = 96

    private var weeks: [Int] { Array(1...max(1, throughWeek)) }

    var body: some View {
        if entries.isEmpty {
            Text(emptyMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Entry")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: nameWidth, height: headerHeight, alignment: .leading)
                    ForEach(entries) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            Text(entry.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(nameColor(entry))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: nameWidth, height: rowHeight, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(entry.label), \(statusTag(entry))")
                        .accessibilityHint("Opens the week \(throughWeek) pick for this entry")
                    }
                }
                Divider()
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(weeks, id: \.self) { week in
                                Text("\(week)")
                                    .font(.system(size: 9, weight: week == throughWeek ? .bold : .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(week == throughWeek ? .primary : .secondary)
                                    .frame(width: cellWidth, height: headerHeight)
                            }
                        }
                        ForEach(entries) { entry in
                            let picks = session.picks(for: entry)
                            HStack(spacing: 0) {
                                ForEach(weeks, id: \.self) { week in
                                    cell(entry, week: week, team: picks[week])
                                        .frame(width: cellWidth, height: rowHeight)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func nameColor(_ entry: ClaimedEntry) -> Color {
        switch entry.status {
        case .active: return entry.buybackUnpaid ? .orange : .primary
        case .pendingBuyback: return .orange
        case .eliminated: return .red
        }
    }

    @ViewBuilder
    private func cell(_ entry: ClaimedEntry, week: Int, team: String?) -> some View {
        let result = entry.resultLabel(for: week)
        ZStack {
            if week == throughWeek {
                Color.accentColor.opacity(0.08)
            }
            if let team {
                let palette = NFLTeam.team(abbreviation: team)
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette?.primaryColor.color ?? .gray)
                    .padding(2)
                Text(team)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette?.primaryColor.foreground ?? .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let result {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(result == "Loss" ? Color.red : Color.green, lineWidth: 1.5)
                    .padding(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            let name = team.map { NFLTeam.shortName(for: $0) } ?? "no pick"
            return result.map { "\(entry.label), week \(week), \(name), \($0)" } ?? "\(entry.label), week \(week), \(name)"
        }())
    }
}

// MARK: - Design C · Selected-week focus
//
// The selected week is what the commissioner is working on, so it gets the
// big cell, pinned beside the name with a result mark: a green check or red
// cross once the game is final, a clock while it is being played, and an
// orange alert for an alive entry with no pick yet. Earlier weeks shrink to a
// trail of small tiles that scrolls on the right, still aligned down the board.

struct CommissionerEntriesGridC: View {
    @Bindable var session: PlayerSession
    let entries: [ClaimedEntry]
    let throughWeek: Int
    var emptyMessage = "No entries yet."
    let onSelect: (ClaimedEntry) -> Void

    private let rowHeight: CGFloat = 46
    private let headerHeight: CGFloat = 22
    private let nameWidth: CGFloat = 104
    private let pickWidth: CGFloat = 50
    private let markWidth: CGFloat = 22
    private let trailWidth: CGFloat = 30

    private var history: [Int] { Array(1..<max(1, throughWeek)) }

    var body: some View {
        if entries.isEmpty {
            Text(emptyMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            let currentGames = session.games(in: throughWeek)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Entry")
                            .frame(width: nameWidth, alignment: .leading)
                        Text("W\(throughWeek)")
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .frame(width: pickWidth)
                        Color.clear
                            .frame(width: markWidth)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: headerHeight)
                    ForEach(entries) { entry in
                        let team = session.picks(for: entry)[throughWeek]
                        HStack(spacing: 0) {
                            Button {
                                onSelect(entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.label)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text(statusTag(entry))
                                        .font(.system(size: 9))
                                        .foregroundStyle(statusColor(entry))
                                }
                                .frame(width: nameWidth, height: rowHeight, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the week \(throughWeek) pick for this entry")
                            currentCell(entry, team: team)
                                .frame(width: pickWidth, height: rowHeight)
                            let mark = mark(entry, team: team, games: currentGames)
                            Group {
                                if let mark {
                                    Image(systemName: mark.symbol)
                                        .font(.caption)
                                        .foregroundStyle(mark.color)
                                        .accessibilityLabel(mark.label)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: markWidth, height: rowHeight)
                        }
                    }
                }
                Divider()
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(history, id: \.self) { week in
                                Text("\(week)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .frame(width: trailWidth, height: headerHeight)
                            }
                        }
                        ForEach(entries) { entry in
                            let picks = session.picks(for: entry)
                            HStack(spacing: 0) {
                                ForEach(history, id: \.self) { week in
                                    trailCell(entry, week: week, team: picks[week])
                                        .frame(width: trailWidth, height: rowHeight)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func currentCell(_ entry: ClaimedEntry, team: String?) -> some View {
        let result = entry.resultLabel(for: throughWeek)
        ZStack {
            Color.accentColor.opacity(0.08)
            if let team {
                TeamPickChip(
                    abbreviation: team,
                    selected: false,
                    dimmed: result != nil,
                    logoURL: session.teamLogos[team],
                    size: 36
                )
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Week \(throughWeek), \(team.map { NFLTeam.shortName(for: $0) } ?? "no pick")")
    }

    private func mark(_ entry: ClaimedEntry, team: String?, games: [PoolGame]) -> (symbol: String, color: Color, label: String)? {
        if entry.resultLabel(for: throughWeek) == "Loss" { return ("xmark.circle.fill", .red, "lost") }
        guard let team else {
            return entry.status == .active ? ("exclamationmark.circle", .orange, "no pick yet") : nil
        }
        switch WeekSummary.teamOutcome(team, games: games) {
        case .won: return ("checkmark.circle.fill", .green, "won")
        case .lost: return ("xmark.circle.fill", .red, "lost")
        case .waiting, .noPick:
            let kickedOff = games.first { $0.homeAbbr == team || $0.awayAbbr == team }?.hasKickedOff ?? false
            return kickedOff ? ("clock", .secondary, "in progress") : nil
        }
    }

    @ViewBuilder
    private func trailCell(_ entry: ClaimedEntry, week: Int, team: String?) -> some View {
        let result = entry.resultLabel(for: week)
        ZStack {
            if let team {
                let palette = NFLTeam.team(abbreviation: team)
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette?.primaryColor.color ?? .gray)
                    .frame(width: 26, height: 20)
                Text(team)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(palette?.primaryColor.foreground ?? .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let result {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(result == "Loss" ? Color.red : Color.green, lineWidth: 1.5)
                    .frame(width: 26, height: 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            let name = team.map { NFLTeam.shortName(for: $0) } ?? "no pick"
            return result.map { "Week \(week), \(name), \($0)" } ?? "Week \(week), \(name)"
        }())
    }
}

// MARK: - Shared

private func statusTag(_ entry: ClaimedEntry) -> String {
    if entry.buybackUnpaid { return "Owes fee" }
    switch entry.status {
    case .active: return entry.isClaimed ? "Alive" : "No login"
    case .pendingBuyback: return "Buyback"
    case .eliminated: return "Out"
    }
}

private func statusColor(_ entry: ClaimedEntry) -> Color {
    if entry.buybackUnpaid { return .orange }
    switch entry.status {
    case .active: return entry.isClaimed ? .green : .orange
    case .pendingBuyback: return .orange
    case .eliminated: return .red
    }
}

// MARK: - Previews

#Preview("Grid designs") {
    let session = PreviewData.commissioner()
    return List {
        Section("Current") {
            CommissionerEntriesGrid(session: session, entries: session.roster, throughWeek: 4) { _ in }
        }
        Section("Design A · Logo matrix") {
            CommissionerEntriesGridA(session: session, entries: session.roster, throughWeek: 4) { _ in }
        }
        Section("Design B · Dense matrix") {
            CommissionerEntriesGridB(session: session, entries: session.roster, throughWeek: 4) { _ in }
        }
        Section("Design C · Selected-week focus") {
            CommissionerEntriesGridC(session: session, entries: session.roster, throughWeek: 4) { _ in }
        }
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
}

#Preview("Design A · Logo matrix") {
    let session = PreviewData.commissioner()
    return List {
        Section {
            CommissionerEntriesGridA(session: session, entries: session.roster, throughWeek: 4) { _ in }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}

#Preview("Design B · Dense matrix") {
    let session = PreviewData.commissioner()
    return List {
        Section {
            CommissionerEntriesGridB(session: session, entries: session.roster, throughWeek: 4) { _ in }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}

#Preview("Design C · Selected-week focus") {
    @Previewable @State var week = 4
    let session = PreviewData.commissioner()
    return List {
        Section {
            CommissionerWeekHeader(
                week: $week,
                scheduledWeeks: Array(Set(session.games.map(\.week))).sorted(),
                openWeek: session.openWeek
            )
            CommissionerEntriesGridC(session: session, entries: session.roster, throughWeek: week) { _ in }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}
#endif
