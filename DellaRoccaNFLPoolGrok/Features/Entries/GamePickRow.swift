import SwiftUI
import Playgrounds

/// Formats a game's kickoff as a short local time (e.g. "1:00 PM").
private func kickoffTime(_ game: PoolGame) -> String {
    game.kickoff.formatted(date: .omitted, time: .shortened)
}

#if DEBUG
// NOTE: Placeholder standings. `PoolGame` does not yet carry team records;
// this returns a fixed "W-L" string so the designs below have something to
// show. Replace with the real record once the model exposes it.
private func standing(for abbreviation: String) -> String {
    "2-1"
}
#endif

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

// Design explorations below are DEBUG-only scaffolding: they are referenced
// solely by the previews in this file and must not ship in release builds.

// MARK: - Design A · Records under each team
//
// Keeps the compact single-line spirit but gives each team a column with its
// standing tucked under the pick button. Center stays time-over-spread.

struct GamePickRowStandingsA: View {
    @Bindable var session: PlayerSession
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    @Binding var selectedTeam: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            teamColumn(game.awayAbbr)

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
            .padding(.top, 24)

            teamColumn(game.homeAbbr)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func teamColumn(_ abbreviation: String) -> some View {
        VStack(spacing: 4) {
            pickButton(abbreviation)
            Text(standing(for: abbreviation))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

// MARK: - Design B · Standings flanking the center
//
// Mirrors the original horizontal emphasis: each team's record sits inline
// between its pick button and the center info block, so the two standings
// bracket the kickoff/spread.

struct GamePickRowStandingsB: View {
    @Bindable var session: PlayerSession
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    @Binding var selectedTeam: String?

    var body: some View {
        HStack(spacing: 8) {
            pickButton(game.awayAbbr)

            Text(standing(for: game.awayAbbr))
                .font(.caption2)
                .foregroundStyle(.secondary)

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

            Text(standing(for: game.homeAbbr))
                .font(.caption2)
                .foregroundStyle(.secondary)

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

// MARK: - Design C · Card with standing badges
//
// Wraps the matchup in a rounded material card. Each team's standing becomes a
// pill badge beneath its pick button, with the kickoff time as a center pill
// and the spread as a trailing footnote.

struct GamePickRowStandingsC: View {
    @Bindable var session: PlayerSession
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    @Binding var selectedTeam: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                teamColumn(game.awayAbbr)

                Text(kickoffTime(game))
                    .font(.caption).bold()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                teamColumn(game.homeAbbr)
            }

            if let spread = game.spreadLabel {
                Text(spread)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func teamColumn(_ abbreviation: String) -> some View {
        VStack(spacing: 6) {
            pickButton(abbreviation)
            Text(standing(for: abbreviation))
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
        }
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

#Preview("Design A · Records under teams") {
    @Previewable @State var selectedTeam: String? = "NYG"
    GamePickRowStandingsA(
        session: PreviewData.player(),
        game: PreviewData.games.first { $0.id == "w4-jax" } ?? PreviewData.games[0],
        entry: PreviewData.will,
        week: 4,
        selectedTeam: $selectedTeam
    )
    GamePickRowStandingsA(
        session: PreviewData.player(),
        game: PreviewData.games.first { $0.id == "w4-locked" } ?? PreviewData.games[0],
        entry: PreviewData.will,
        week: 4,
        selectedTeam: $selectedTeam
    )
}

#Preview("Design B · Standings flank center") {
    @Previewable @State var selectedTeam: String? = "NYG"
    GamePickRowStandingsB(
        session: PreviewData.player(),
        game: PreviewData.games.first { $0.id == "w4-jax" } ?? PreviewData.games[0],
        entry: PreviewData.will,
        week: 4,
        selectedTeam: $selectedTeam
    )
    GamePickRowStandingsB(
        session: PreviewData.player(),
        game: PreviewData.games.first { $0.id == "w4-locked" } ?? PreviewData.games[0],
        entry: PreviewData.will,
        week: 4,
        selectedTeam: $selectedTeam
    )
}

#Preview("Design C · Card with badges") {
    @Previewable @State var selectedTeam: String? = "NYG"
    GamePickRowStandingsC(
        session: PreviewData.player(),
        game: PreviewData.games.first { $0.id == "w4-jax" } ?? PreviewData.games[0],
        entry: PreviewData.will,
        week: 4,
        selectedTeam: $selectedTeam
    )
    GamePickRowStandingsC(
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
