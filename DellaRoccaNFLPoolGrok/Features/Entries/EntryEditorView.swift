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
                    .font(.title3.weight(.semibold))
                Text(entry.statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !picks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
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
                                        .frame(width: 76)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if entry.status == .active, let week {
                Section {
                    Text("Week \(week) locks at each game's kickoff. A team can be used once all season. The spread is only a reference.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(session.games(in: week)) { game in
                        GamePickRow(
                            session: session,
                            game: game,
                            entry: entry,
                            week: week,
                            selectedTeam: $selectedTeam
                        )
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
        .navigationTitle(entry.label)
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
