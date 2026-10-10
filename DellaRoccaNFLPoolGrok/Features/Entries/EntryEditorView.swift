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
                                    WeekPickChip(
                                        week: pickWeek,
                                        team: team,
                                        logoURL: session.teamLogos[team],
                                        chipSize: 50
                                    )
                                }
                            }
                        }
                    }
                }
            }
            if entry.status == .active, let week {
                Section {
                    ForEach(session.games(in: week)) { game in
                        GamePickRow(
                            session: session,
                            game: game,
                            entry: entry,
                            week: week,
                            selectedTeam: $selectedTeam
                        )
                        .frame(height: 100)
                    }
                }
            } else if entry.status != .active, !entry.hasOpenBuybackDecision {
                Section {
                    Text(entry.statusLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // The player's own call after a loss in weeks 1-6. Shown alongside
            // the pick section once they elect in, since they then owe a pick
            // for the decision week and can still change their mind.
            if entry.hasOpenBuybackDecision {
                BuybackDecisionCard(session: session, entry: entry)
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
        .onChange(of: week) { _, newWeek in
            // The open week advances on its own when the last game of the
            // previous week kicks off, so a selection made for the old week
            // must not carry over — the save bar would submit it for the new
            // week and burn that team for the season. Unconditional, unlike the
            // hook below: a changed week invalidates any selection made for the
            // week before it.
            selectedTeam = newWeek.flatMap { picks[$0] }
        }
        .onChange(of: week.flatMap { picks[$0] }) { oldSaved, newSaved in
            // Re-sync to a server-side pick change (e.g. a commissioner
            // correction) only when the user hasn't made an unsaved selection —
            // i.e. they're still showing the previously-saved pick.
            if selectedTeam == nil || selectedTeam == oldSaved {
                selectedTeam = newSaved
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
