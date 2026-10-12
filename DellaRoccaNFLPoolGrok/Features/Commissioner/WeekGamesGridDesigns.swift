#if DEBUG
import SwiftUI

// Design explorations for the week slate. DEBUG-only scaffolding: referenced
// solely by the previews here, never shipped. The slate in use is
// WeekGamesGrid. All three take the same games it takes; A also takes the
// logo lookup the session provides.

// MARK: - Design A · Logo tiles
//
// Wider tiles with both crests, so a game reads by logo rather than by two
// abbreviations. The winner's chip gets the green ring and the loser dims,
// matching how the pick editor marks a selection. Score sits under each crest
// once there is one; the middle column carries the state and the spread.

struct WeekGamesGridA: View {
    let games: [PoolGame]
    var logoURL: (String) -> URL? = { _ in nil }

    private let columns = [GridItem(.adaptive(minimum: 156), spacing: 8)]

    var body: some View {
        if games.isEmpty {
            emptySlate
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(games) { game in
                    LogoTile(game: game, logoURL: logoURL)
                }
            }
        }
    }
}

private struct LogoTile: View {
    let game: PoolGame
    let logoURL: (String) -> URL?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                team(game.awayAbbr, score: game.awayScore)
                VStack(spacing: 3) {
                    Text(middleLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isLive ? Color.orange : Color.secondary)
                    if let spread = game.spreadLabel {
                        Text(spread)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(minWidth: 44)
                .padding(.top, 12)
                team(game.homeAbbr, score: game.homeScore)
            }
            Text(game.kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(game))
    }

    private var isLive: Bool { game.hasKickedOff && !game.isFinal }

    private var middleLabel: String {
        if game.isFinal { return "Final" }
        if game.hasKickedOff { return "Live" }
        return "at"
    }

    private func team(_ abbreviation: String, score: Int?) -> some View {
        let won = game.winner == abbreviation
        let lost = game.winner != nil && !won
        return VStack(spacing: 3) {
            TeamPickChip(
                abbreviation: abbreviation,
                selected: won,
                dimmed: lost,
                logoURL: logoURL(abbreviation),
                size: 36
            )
            HStack(spacing: 3) {
                Text(abbreviation)
                    .font(.caption2.weight(won ? .bold : .regular))
                if let score {
                    Text("\(score)")
                        .font(.caption2.weight(won ? .bold : .regular))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(lost ? Color.secondary : Color.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Design B · Schedule by day
//
// The slate as a schedule: one row per game, grouped under the day it is
// played, kickoff or score on the trailing edge. Twice the height of the tile
// grid for a full week, in exchange for a layout that reads top to bottom in
// kickoff order and shows the day, which the tiles never do.

struct WeekGamesListB: View {
    let games: [PoolGame]

    private var days: [(day: Date, games: [PoolGame])] {
        let grouped = Dictionary(grouping: games) { Calendar.current.startOfDay(for: $0.kickoff) }
        return grouped.keys.sorted().map { day in
            (day: day, games: grouped[day]!.sorted { $0.kickoff < $1.kickoff })
        }
    }

    var body: some View {
        if games.isEmpty {
            emptySlate
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(days, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        ForEach(group.games) { game in
                            row(game)
                            if game.id != group.games.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ game: PoolGame) -> some View {
        HStack(spacing: 8) {
            badge(game.awayAbbr, game: game)
            Text("@")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            badge(game.homeAbbr, game: game)
            if let spread = game.spreadLabel {
                Text(spread)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing(game)
        }
        .frame(height: 34)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(game))
    }

    private func badge(_ abbreviation: String, game: PoolGame) -> some View {
        let won = game.winner == abbreviation
        let lost = game.winner != nil && !won
        let palette = NFLTeam.team(abbreviation: abbreviation)
        return Text(abbreviation)
            .font(.caption.weight(.bold))
            .foregroundStyle(palette?.primaryColor.foreground ?? .white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 42, height: 22)
            .background(palette?.primaryColor.color ?? .gray, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                if won {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.green, lineWidth: 2)
                }
            }
            .opacity(lost ? 0.45 : 1)
    }

    @ViewBuilder
    private func trailing(_ game: PoolGame) -> some View {
        if let score = game.scoreLabel {
            HStack(spacing: 5) {
                Text(score)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(game.isFinal ? "Final" : "Live")
                    .font(.caption2)
                    .foregroundStyle(game.isFinal ? Color.secondary : Color.orange)
            }
        } else if game.hasKickedOff {
            Text(game.isFinal ? "Final" : "In progress")
                .font(.caption)
                .foregroundStyle(game.isFinal ? Color.secondary : Color.orange)
        } else {
            Text(game.kickoff.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Design C · Scoreboard strip
//
// A single row of scoreboard cards that scrolls sideways, so the slate takes
// a fixed 90pt however many games the week has and the entries grid moves up
// the screen. Each card stacks away over home with the score beside, state in
// the corner, a sliver of team color as the only ornament. A caption under
// the strip sums up the week and names the next kickoff.

struct WeekGamesStripC: View {
    let games: [PoolGame]

    var body: some View {
        if games.isEmpty {
            emptySlate
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(games) { game in
                            ScoreCard(game: game)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var caption: String {
        let finals = games.filter(\.isFinal).count
        let live = games.filter { $0.hasKickedOff && !$0.isFinal }.count
        var parts = [games.count == 1 ? "1 game" : "\(games.count) games"]
        if finals > 0 { parts.append("\(finals) final") }
        if live > 0 { parts.append("\(live) live") }
        if let next = games.filter({ !$0.hasKickedOff }).map(\.kickoff).min() {
            parts.append("next kickoff \(next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ScoreCard: View {
    let game: PoolGame

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stateLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(game.hasKickedOff && !game.isFinal ? Color.orange : Color.secondary)
                Spacer()
                if let spread = game.spreadLabel {
                    Text(spread)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            teamRow(game.awayAbbr, score: game.awayScore)
            teamRow(game.homeAbbr, score: game.homeScore)
        }
        .padding(8)
        .frame(width: 128)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(game))
    }

    private var stateLabel: String {
        if game.isFinal { return "Final" }
        if game.hasKickedOff { return "Live" }
        return game.kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func teamRow(_ abbreviation: String, score: Int?) -> some View {
        let won = game.winner == abbreviation
        let lost = game.winner != nil && !won
        let palette = NFLTeam.team(abbreviation: abbreviation)
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(palette?.primaryColor.color ?? .gray)
                .frame(width: 4, height: 14)
            Text(abbreviation)
                .font(.caption.weight(won ? .bold : .medium))
            Spacer(minLength: 0)
            if let score {
                Text("\(score)")
                    .font(.caption.weight(won ? .bold : .regular))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(lost ? Color.secondary : Color.primary)
    }
}

// MARK: - Shared

private var emptySlate: some View {
    Text("No games scheduled for this week.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

private func accessibilityText(_ game: PoolGame) -> String {
    let away = NFLTeam.shortName(for: game.awayAbbr)
    let home = NFLTeam.shortName(for: game.homeAbbr)
    if let homeScore = game.homeScore, let awayScore = game.awayScore {
        return "\(away) \(awayScore), \(home) \(homeScore)\(game.isFinal ? ", final" : "")"
    }
    return "\(away) at \(home), \(game.kickoff.formatted(date: .abbreviated, time: .shortened))"
}

// MARK: - Previews

#Preview("Slate designs") {
    let session = PreviewData.commissioner()
    let games = session.games(in: 4)
    return List {
        Section("Current") {
            WeekGamesGrid(games: games)
        }
        Section("Design A · Logo tiles") {
            WeekGamesGridA(games: games) { session.teamLogos[$0] }
        }
        Section("Design B · Schedule by day") {
            WeekGamesListB(games: games)
        }
        Section("Design C · Scoreboard strip") {
            WeekGamesStripC(games: games)
        }
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
}

#Preview("Slate designs · all preview games") {
    let session = PreviewData.commissioner()
    return List {
        Section("Design A · Logo tiles") {
            WeekGamesGridA(games: session.games) { session.teamLogos[$0] }
        }
        Section("Design B · Schedule by day") {
            WeekGamesListB(games: session.games)
        }
        Section("Design C · Scoreboard strip") {
            WeekGamesStripC(games: session.games)
        }
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
}

#Preview("Empty week") {
    List {
        Section("Design A") { WeekGamesGridA(games: []) }
        Section("Design B") { WeekGamesListB(games: []) }
        Section("Design C") { WeekGamesStripC(games: []) }
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
}
#endif
