import SwiftUI

/// Every game in the selected week, as a compact grid. Each tile is away over
/// home with the kickoff time beneath, swapping to the score once the game has
/// started so the commissioner can see the whole slate at a glance.
struct WeekGamesGrid: View {
    let games: [PoolGame]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        if games.isEmpty {
            Text("No games scheduled for this week.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(games) { game in
                    GameTile(game: game)
                }
            }
        }
    }
}

private struct GameTile: View {
    let game: PoolGame

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                teamCell(game.awayAbbr)
                Divider().frame(height: 18)
                teamCell(game.homeAbbr)
            }
            Divider()
            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(game.hasKickedOff ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func teamCell(_ abbreviation: String) -> some View {
        Text(abbreviation)
            .font(.caption.weight(game.winner == abbreviation ? .bold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
    }

    /// Time before kickoff, score after. A started game with no score yet says
    /// so rather than falling back to a time that has already passed.
    private var detail: String {
        if let score = game.scoreLabel { return score }
        if game.hasKickedOff { return game.isFinal ? "Final" : "In progress" }
        return game.kickoff.formatted(date: .omitted, time: .shortened)
    }

    private var accessibilityText: String {
        let away = NFLTeam.shortName(for: game.awayAbbr)
        let home = NFLTeam.shortName(for: game.homeAbbr)
        if let homeScore = game.homeScore, let awayScore = game.awayScore {
            return "\(away) \(awayScore), \(home) \(homeScore)\(game.isFinal ? ", final" : "")"
        }
        return "\(away) at \(home), \(game.kickoff.formatted(date: .abbreviated, time: .shortened))"
    }
}

#if DEBUG
#Preview("Games grid") {
    WeekGamesGrid(games: PreviewData.games)
        .padding()
}
#endif
