import SwiftUI
import Playgrounds

/// Formats a game's kickoff as a short local time (e.g. "1:00 PM").
private func kickoffTime(_ game: PoolGame) -> String {
    game.kickoff.formatted(date: .omitted, time: .shortened)
}

// A single tight line: away pick, a minimal time-over-spread stack in the
// middle, home pick. Smallest vertical footprint so many games fit on screen.
struct GamePickRow: View {
    @Bindable var session: PlayerSession
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    @Binding var selectedTeam: String?

    var body: some View {
        HStack(spacing: 10) {
            pickButton(game.awayAbbr)

            VStack(spacing: 2) {
                Text(kickoffTime(game))
                    .font(.caption).bold()
                if let spread = game.spreadLabel {
                    Text(spread)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            pickButton(game.homeAbbr)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func pickButton(_ abbreviation: String) -> some View {
        PickTeamButton(
            abbreviation: abbreviation,
            game: game,
            entry: entry,
            week: week,
            usedTeams: session.usedTeams(for: entry),
            logoURL: session.teamLogos[abbreviation],
            selectedTeam: $selectedTeam
        )
    }
}

#if DEBUG

#Preview("Both Open and Locked") {
    @Previewable @State var selectedTeam: String? = "NYG"
    GamePickRow(
        session: PreviewData.player(),
        game: PreviewData.games.first { $0.id == "w4-jax" } ?? PreviewData.games[0],
        entry: PreviewData.will,
        week: 4,
        selectedTeam: $selectedTeam
    )
    GamePickRow(
        session: PreviewData.player(),
        game: PreviewData.games.first { $0.id == "w4-locked" } ?? PreviewData.games[0],
        entry: PreviewData.will,
        week: 4,
        selectedTeam: $selectedTeam
    )
}

#endif

#Playground {
    let game = PreviewData.games.first!
    let kickoff = game.kickoff
}
