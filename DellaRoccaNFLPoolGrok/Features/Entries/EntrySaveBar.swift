import SwiftUI

struct EntrySaveBar: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry
    let week: Int
    @Binding var selectedTeam: String?

    private var saved: String? { session.picks(for: entry)[week] }
    private var unchanged: Bool { selectedTeam != nil && selectedTeam == saved }

    private var canSave: Bool {
        EntryPickRules.canSave(
            selectedTeam: selectedTeam,
            savedTeam: saved,
            games: session.games(in: week),
            entry: entry,
            usedTeams: session.usedTeams(for: entry),
            week: week
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if session.isBusy {
                    ProgressView()
                } else if unchanged, let saved {
                    Label("\(NFLTeam.shortName(for: saved)) saved", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button {
                        // Re-validate at tap time: a game can kick off between
                        // render and tap, so don't rely on `.disabled` alone.
                        guard let selectedTeam, canSave else { return }
                        Task { await session.submitPick(entryID: entry.id, week: week, team: selectedTeam) }
                    } label: {
                        Text(EntryPickRules.saveTitle(selectedTeam: selectedTeam, savedTeam: saved))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
            }
            .padding()
        }
        .background(.bar)
    }
}

#if DEBUG
#Preview("No team yet") {
    @Previewable @State var selectedTeam: String? = nil
    EntrySaveBar(session: PreviewData.player(), entry: PreviewData.will, week: 4, selectedTeam: $selectedTeam)
}

#Preview("Ready to save") {
    @Previewable @State var selectedTeam: String? = "GB"
    EntrySaveBar(session: PreviewData.player(), entry: PreviewData.will, week: 4, selectedTeam: $selectedTeam)
}

#Preview("Saved") {
    @Previewable @State var selectedTeam: String? = "DET"
    EntrySaveBar(session: PreviewData.player(), entry: PreviewData.casa, week: 4, selectedTeam: $selectedTeam)
}
#endif
