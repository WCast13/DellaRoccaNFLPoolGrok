import SwiftUI

struct PickTeamButton: View {
    let abbreviation: String
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    let usedTeams: [String: Int]
    let logoURL: URL?
    @Binding var selectedTeam: String?

    private var allowed: Bool {
        EntryPickRules.canSelect(
            abbreviation: abbreviation,
            game: game,
            entry: entry,
            usedTeams: usedTeams,
            week: week
        )
    }

    private var reason: String? {
        EntryPickRules.unavailableReason(
            abbreviation: abbreviation,
            game: game,
            usedTeams: usedTeams,
            week: week
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            Button {
                selectedTeam = abbreviation
            } label: {
                TeamPickChip(
                    abbreviation: abbreviation,
                    selected: selectedTeam == abbreviation,
                    dimmed: !allowed && selectedTeam != abbreviation,
                    logoURL: logoURL
                )
                .frame(width: 75, height: 75)
            }
            .buttonStyle(.plain)
            .disabled(!allowed)
            .accessibilityLabel(
                EntryPickRules.teamAccessibility(abbreviation: abbreviation, allowed: allowed, reason: reason)
            )
        }
//        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Team choices") {
    @Previewable @State var selectedTeam: String? = "GB"
    let open = PreviewData.games.first { $0.id == "w4-gb" } ?? PreviewData.games[0]
    let usedGame = PreviewData.games.first { $0.id == "w4-jax" } ?? PreviewData.games[0]
    let locked = PreviewData.games.first { $0.id == "w4-locked" } ?? PreviewData.games[0]
    let usedTeams = PreviewData.player().usedTeams(for: PreviewData.will)
    return HStack(spacing: 8) {
        PickTeamButton(
            abbreviation: "PIT",
            game: usedGame,
            entry: PreviewData.will,
            week: 4,
            usedTeams: usedTeams,
            logoURL: PreviewData.logos["PIT"],
            selectedTeam: $selectedTeam
        )
        PickTeamButton(
            abbreviation: "GB",
            game: open,
            entry: PreviewData.will,
            week: 4,
            usedTeams: usedTeams,
            logoURL: PreviewData.logos["GB"],
            selectedTeam: $selectedTeam
        )
        PickTeamButton(
            abbreviation: "JAX",
            game: usedGame,
            entry: PreviewData.will,
            week: 4,
            usedTeams: usedTeams,
            logoURL: PreviewData.logos["JAX"],
            selectedTeam: $selectedTeam
        )
        PickTeamButton(
            abbreviation: "NYG",
            game: locked,
            entry: PreviewData.will,
            week: 4,
            usedTeams: usedTeams,
            logoURL: PreviewData.logos["NYG"],
            selectedTeam: $selectedTeam
        )
    }
    .padding()
}
#endif
