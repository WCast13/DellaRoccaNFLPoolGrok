import SwiftUI

/// The pick sheet's team surface: every team on the week's slate as a logo
/// chip with its abbreviation beneath, six to a row in slate order (away then
/// home, game by game, so neighbours are opponents). A used team is dimmed in
/// place, the saved one is ringed, and the one being saved spins. Tapping a
/// chip saves it; there is nothing else to read.
struct CommissionerPickTeamGrid: View {
    let slate: CommissionerPickSlate

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
    private let chipSize: CGFloat = 48

    var body: some View {
        if slate.games.isEmpty {
            Text("No games scheduled for week \(slate.week).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(slate.choices) { choice in
                    chip(choice)
                }
            }
        }
    }

    private func chip(_ choice: CommissionerPickChoice) -> some View {
        let highlighted = slate.isHighlighted(choice.team)
        return Button {
            slate.onPick(choice)
        } label: {
            VStack(spacing: 3) {
                TeamPickChip(
                    abbreviation: choice.team,
                    selected: highlighted,
                    dimmed: slate.isDimmed(choice),
                    logoURL: slate.logos[choice.team],
                    size: chipSize
                )
                .savingOverlay(slate.isPending(choice.team))
                Text(choice.team)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(choice.usedWeek == nil ? .primary : .tertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!slate.canSelect(choice))
        .accessibilityLabel(slate.accessibilityLabel(choice))
        .accessibilityHint(slate.accessibilityHint(choice))
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}

private extension View {
    /// A spinner over a team chip while its save is in flight.
    func savingOverlay(_ saving: Bool) -> some View {
        overlay {
            if saving {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.black.opacity(0.35))
                    ProgressView()
                        .tint(.white)
                }
            }
        }
    }
}

#if DEBUG
#Preview("No pick yet") {
    ScrollView {
        CommissionerPickTeamGrid(slate: .preview())
            .padding()
    }
}

#Preview("Saved pick") {
    ScrollView {
        CommissionerPickTeamGrid(slate: .preview(entryID: PreviewData.casa.id))
            .padding()
    }
}

#Preview("Saving") {
    ScrollView {
        CommissionerPickTeamGrid(slate: .preview(pendingTeam: "GB"))
            .padding()
    }
}
#endif
