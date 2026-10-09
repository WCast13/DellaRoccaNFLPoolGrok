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

    private var aliveEntries: [ClaimedEntry] { session?.aliveEntries ?? [] }
    private var buybackEntries: [ClaimedEntry] { session?.buybackEntries ?? [] }
    private var eliminatedEntries: [ClaimedEntry] { session?.eliminatedEntries ?? [] }

    /// Weeks that have started. A pick is shown only when it is already public.
    /// Kept view-local (not cached on the model) because it depends on the
    /// current wall-clock time via `hasKickedOff`.
    private var visibleWeeks: [Int] {
        let started = Set((session?.games ?? []).filter(\.hasKickedOff).map(\.week))
        return started.sorted()
    }

    private func filteredEntries() -> [ClaimedEntry] {
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
        // Evaluate the kicked-off weeks and the filtered roster once per body
        // pass instead of re-deriving them for the header, each row, and the
        // empty-state overlay.
        let weeks = visibleWeeks
        let rows = filteredEntries()
        return VStack(spacing: 0) {
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
                if let latest = weeks.last {
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

            List(rows) { entry in
                PoolEntryRow(
                    entry: entry,
                    weeks: weeks,
                    isCommissioner: PoolAdmins.names.contains(entry.label),
                    logoURL: { session?.teamLogos[$0] }
                )
            }
            .listStyle(.plain)
            .overlay {
                if rows.isEmpty, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Standings") {
    PoolBoardView(session: PreviewData.player())
}

#Preview("Sign in") {
    PoolBoardView(session: PreviewData.signedOut())
}

#Preview("Loading") {
    PoolBoardView(session: PreviewData.loading())
}
#endif
