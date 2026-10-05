import SwiftUI

struct EntrySaveBar: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry
    let week: Int
    @Binding var selectedTeam: String?

    private var saved: String? { session.picks(for: entry)[week] }
    private var unchanged: Bool { selectedTeam != nil && selectedTeam == saved }

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
                        guard let selectedTeam else { return }
                        Task { await session.submitPick(entryID: entry.id, week: week, team: selectedTeam) }
                    } label: {
                        Text(EntryPickRules.saveTitle(selectedTeam: selectedTeam, savedTeam: saved))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!EntryPickRules.canSave(
                        selectedTeam: selectedTeam,
                        savedTeam: saved,
                        games: session.games(in: week),
                        entry: entry,
                        usedTeams: session.usedTeams(for: entry),
                        week: week
                    ))
                }
            }
            .padding()
        }
        .background(.bar)
    }
}
