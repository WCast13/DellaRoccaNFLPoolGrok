import SwiftUI

struct EntryEditorView: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry
    @State private var selectedTeam: String?

    private var week: Int? { session.openWeek }
    private var picks: [Int: String] { session.picks(for: entry) }

    var body: some View {
        List {
            Section {
                Text(entry.label)
                    .font(.headline.weight(.semibold))
                if !picks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(picks.keys.sorted(), id: \.self) { pickWeek in
                                if let team = picks[pickWeek] {
                                    
                                    VStack(spacing: 4) {
                                        Text("W\(pickWeek)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        TeamPickChip(
                                            abbreviation: team,
                                            selected: false,
                                            dimmed: false,
                                            logoURL: session.teamLogos[team]
                                        )
                                        .frame(width: 50, height: 50)
                                        .background(.black.opacity(0.69))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .background(.yellow.opacity(0.3))
            if entry.status == .active, let week {
                Section {
                    ForEach(session.games(in: week)) { game in
                        NewGamePickRowTwo(
                            session: session,
                            game: game,
                            entry: entry,
                            week: week,
                            selectedTeam: $selectedTeam
                        )
                        .frame(height: 100)
                    }
                }
            } else if entry.status != .active {
                Section {
                    Text("This entry cannot make a pick until a commissioner records a buyback.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
        }
        .safeAreaInset(edge: .bottom) {
            if entry.status == .active, let week {
                EntrySaveBar(session: session, entry: entry, week: week, selectedTeam: $selectedTeam)
            }
        }
//        .navigationTitle("Week \(week ?? 0)") //TODO: Dont like this Title
        .onAppear {
            selectedTeam = week.flatMap { picks[$0] }
        }
        .onChange(of: entry.id) { _, _ in
            selectedTeam = week.flatMap { picks[$0] }
        }
        .onChange(of: week.flatMap { picks[$0] }) { _, team in
            if selectedTeam == nil {
                selectedTeam = team
            }
        }
    }
}

#if DEBUG
#Preview("Make a pick") {
    NavigationStack {
        EntryEditorView(session: PreviewData.player(), entry: PreviewData.will)
    }
}

#Preview("Saved pick") {
    NavigationStack {
        EntryEditorView(session: PreviewData.player(), entry: PreviewData.casa)
    }
}

#Preview("Needs a buyback") {
    let entry = PreviewData.standings.first { $0.id == "pat-buyer" } ?? PreviewData.will
    return NavigationStack {
        EntryEditorView(session: PreviewData.player(), entry: entry)
    }
}
#endif
