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
            }
            .buttonStyle(.plain)
            .disabled(!allowed)
            .accessibilityLabel(
                EntryPickRules.teamAccessibility(abbreviation: abbreviation, allowed: allowed, reason: reason)
            )
            if let reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
