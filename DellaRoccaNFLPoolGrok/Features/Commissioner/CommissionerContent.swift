import SwiftUI

/// Which half of the roster the entries grid shows. Eliminated means the
/// entry's status says so; everyone else is active, including a knocked-out
/// entry whose buyback is still open (its row tag says "Buyback").
enum CommissionerEntryFilter: String, CaseIterable, Identifiable {
    case active
    case eliminated

    var id: Self { self }

    var title: String {
        switch self {
        case .active: return "Active"
        case .eliminated: return "Eliminated"
        }
    }

    func matches(_ entry: ClaimedEntry) -> Bool {
        switch self {
        case .active: return entry.status != .eliminated
        case .eliminated: return entry.status == .eliminated
        }
    }
}

struct CommissionerContent: View {
    @Bindable var session: PlayerSession
    @State private var query = ""
    @State private var week = 1
    @State private var didInitWeek = false
    @State private var filter: CommissionerEntryFilter = .active
    /// The entry whose name was tapped; drives the pick sheet.
    @State private var editing: ClaimedEntry?

    /// The grid's rows: the chosen segment, narrowed by the search field.
    private var filtered: [ClaimedEntry] {
        let segment = session.roster.filter(filter.matches)
        guard !trimmedQuery.isEmpty else { return segment }
        return segment.filter { $0.label.localizedStandardContains(trimmedQuery) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !session.isSignedIn {
                    message("Sign in with Apple on My Entries. Commissioner tools appear on accounts a commissioner has allowed.")
                } else if !session.isAdmin {
                    message("\(session.accountLabel) is not a commissioner yet. A commissioner can add this Apple account's email.")
                } else {
                    roster
                }
            }
            .navigationTitle("Commissioner")
            .searchable(text: $query, prompt: "Entry name")
        }
        .onAppear {
            initializeWeek()
        }
        .onChange(of: session.openWeek) { _, _ in
            initializeWeek()
        }
        .sheet(item: $editing) { entry in
            CommissionerPickSheet(session: session, entryID: entry.id, week: week)
        }
    }

    /// Start on the open week, falling back to the latest scheduled week. Keeps
    /// resolving as games load in late, but never overrides a manual change.
    private func initializeWeek() {
        guard !didInitWeek else { return }
        if let openWeek = session.openWeek {
            week = openWeek
            didInitWeek = true
        } else if let maxWeek = session.games.map(\.week).max() {
            week = maxWeek
            didInitWeek = true
        }
    }

    private var roster: some View {
        List {
            Section {
                CommissionerWeekHeader(
                    week: $week,
                    scheduledWeeks: scheduledWeeks,
                    openWeek: session.openWeek
                )
                WeekGamesGrid(games: session.games(in: week))
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            // The week over the whole roster, whatever the grid below is
            // filtered to: who is in play, how the picks are going, and how
            // they spread over the teams.
            Section {
                CommissionerWeekSummary(summary: weekSummary, week: week)
            } header: {
                Text("Week \(week) summary")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            // The season so far, entries down and weeks across. The segment
            // splits out the eliminated entries; the search field narrows
            // within the chosen segment rather than replacing the board.
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(CommissionerEntryFilter.allCases) { candidate in
                        Text("\(candidate.title) (\(count(for: candidate)))").tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                CommissionerEntriesGrid(
                    session: session,
                    entries: filtered,
                    throughWeek: week,
                    emptyMessage: emptyMessage
                ) { entry in
                    editing = entry
                }
            } header: {
                Text(trimmedQuery.isEmpty ? "Picks through week \(week)" : "Matching entries")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            GradeNowSection(session: session)

            CommissionerAccessSection(session: session)

            if session.notice != nil || session.errorMessage != nil {
                Section {
                    statusMessages
                }
            }
        }
    }

    private var weekSummary: WeekSummary {
        WeekSummary.make(
            entries: session.roster,
            week: week,
            games: session.games(in: week),
            picks: session.picks(for:)
        )
    }

    private func count(for candidate: CommissionerEntryFilter) -> Int {
        session.roster.filter(candidate.matches).count
    }

    private var emptyMessage: String {
        let noun = filter == .active ? "active" : "eliminated"
        if trimmedQuery.isEmpty {
            return session.roster.isEmpty ? "No entries yet." : "No \(noun) entries."
        }
        return "No \(noun) entries match “\(trimmedQuery)”."
    }

    private var scheduledWeeks: [Int] {
        Array(Set(session.games.map(\.week))).sorted()
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusMessages: some View {
        StatusMessageText(notice: session.notice, errorMessage: session.errorMessage)
    }
}
