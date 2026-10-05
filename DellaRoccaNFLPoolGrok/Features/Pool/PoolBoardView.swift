import SwiftUI

struct PoolBoardView: View {
    var session: PlayerSession?

    @State private var filter: BoardFilter = .alive
    @State private var query = ""

    private enum BoardFilter: String, CaseIterable, Identifiable {
        case alive = "Alive"
        case buyback = "Buy back"
        case out = "Out"

        var id: String { rawValue }
    }

    private var standings: [ClaimedEntry] { session?.standings ?? [] }

    private var aliveEntries: [ClaimedEntry] { standings.filter { $0.status == .active } }
    private var buybackEntries: [ClaimedEntry] { standings.filter(\.canBuyBack) }
    private var eliminatedEntries: [ClaimedEntry] {
        standings.filter { $0.status == .eliminated || ($0.status == .pendingBuyback && !$0.canBuyBack) }
    }

    /// Weeks that have started. A pick is shown only when it is already public.
    private var visibleWeeks: [Int] {
        let started = Set((session?.games ?? []).filter(\.hasKickedOff).map(\.week))
        return started.sorted()
    }

    private var filteredEntries: [ClaimedEntry] {
        let base: [ClaimedEntry]
        switch filter {
        case .alive: base = aliveEntries
        case .buyback: base = buybackEntries
        case .out: base = eliminatedEntries
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { $0.label.localizedStandardContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session == nil {
                    ProgressView("Opening the pool")
                } else if session?.isSignedIn != true {
                    ContentUnavailableView(
                        "Sign in to see the pool",
                        systemImage: "person.crop.circle",
                        description: Text("The standings come from the live pool. Sign in on My Entries.")
                    )
                } else if session?.standingsLoaded != true {
                    ProgressView("Loading the pool")
                } else {
                    board
                }
            }
            .navigationTitle("Knock-out Pool")
            .searchable(text: $query, prompt: "Entry name")
        }
    }

    private var board: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $filter) {
                ForEach(BoardFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(aliveEntries.count) alive · \(buybackEntries.count) can buy back · \(eliminatedEntries.count) out")
                if let latest = visibleWeeks.last {
                    Text("Picks show after kickoff. Through week \(latest).")
                } else {
                    Text("Picks show after kickoff.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)

            List(filteredEntries) { entry in
                PoolEntryRow(
                    entry: entry,
                    weeks: visibleWeeks,
                    isCommissioner: PoolAdmins.names.contains(entry.label),
                    logoURL: { session?.teamLogos[$0] }
                )
            }
            .listStyle(.plain)
            .overlay {
                if filteredEntries.isEmpty, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

private struct PoolEntryRow: View {
    let entry: ClaimedEntry
    let weeks: [Int]
    let isCommissioner: Bool
    let logoURL: (String) -> URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.label)
                    .font(.body.weight(.semibold))
                if isCommissioner {
                    Text("Commissioner")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            Text(entry.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !weeks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(weeks, id: \.self) { week in
                            weekChip(week)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func weekChip(_ week: Int) -> some View {
        let team = entry.picks[week]
        let result = entry.resultLabel(for: week)
        return VStack(spacing: 4) {
            Text("W\(week)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let team {
                TeamPickChip(
                    abbreviation: team,
                    selected: false,
                    dimmed: result != nil,
                    logoURL: logoURL(team)
                )
                .frame(width: 76)
            } else {
                Text(result == nil ? "—" : "No pick")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 76, height: 32)
            }
            if let result {
                Text(result)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chipLabel(week: week, team: team, result: result))
    }

    private func chipLabel(week: Int, team: String?, result: String?) -> String {
        let name = team.map { NFLTeam.shortName(for: $0) } ?? "no pick"
        if let result {
            return "Week \(week) \(name), \(result)"
        }
        return "Week \(week) \(name)"
    }
}
