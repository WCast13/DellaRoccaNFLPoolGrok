import SwiftUI

struct PoolBoardView: View {
    let pool: SurvivorPool

    @State private var filter: BoardFilter = .alive
    @State private var query = ""

    private enum BoardFilter: String, CaseIterable, Identifiable {
        case alive = "Alive"
        case buyback = "Buy back"
        case out = "Out"

        var id: String { rawValue }
    }

    private var filteredEntries: [PoolEntry] {
        let base: [PoolEntry]
        switch filter {
        case .alive: base = pool.aliveEntries
        case .buyback: base = pool.buybackEntries
        case .out: base = pool.eliminatedEntries
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { $0.label.localizedStandardContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: $filter) {
                    ForEach(BoardFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Text("\(pool.aliveEntries.count) alive · \(pool.buybackEntries.count) can buy back · \(pool.eliminatedEntries.count) out")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                List(filteredEntries) { entry in
                    PoolEntryRow(entry: entry, isCommissioner: pool.adminNames.contains(entry.label))
                }
                .listStyle(.plain)
                .overlay {
                    if filteredEntries.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .navigationTitle("Knock-out Pool")
            .searchable(text: $query, prompt: "Entry name")
        }
    }
}

private struct PoolEntryRow: View {
    let entry: PoolEntry
    let isCommissioner: Bool

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

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { week in
                    if let pick = entry.pick(for: week) {
                        PickChip(pick: pick)
                    } else {
                        Text("W\(week) —")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        switch entry.status {
        case .active:
            return "Alive"
        case .pendingBuyback:
            if let week = entry.eliminatedWeek {
                return "Lost week \(week) · can buy back"
            }
            return "Can buy back"
        case .eliminated:
            if let week = entry.eliminatedWeek {
                return "Out · no buyback after week \(week)"
            }
            return "Out"
        }
    }
}

private struct PickChip: View {
    let pick: PoolPick

    var body: some View {
        let team = NFLTeam.team(abbreviation: pick.team)
        Text(pick.nickname)
            .font(.caption.weight(.semibold))
            .foregroundStyle(team?.primaryColor.foreground ?? .white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(team?.primaryColor.color ?? .gray, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Week \(pick.week) \(pick.nickname)")
    }
}
