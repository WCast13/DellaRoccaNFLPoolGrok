import SwiftUI

struct PoolEntryRow: View {
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
//                .frame(width: 76)
            } else {
                Text(result == nil ? "—" : "No pick")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
//                    .frame(width: 76, height: 32)
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

#if DEBUG
#Preview("Entry row") {
    let entry = PreviewData.standings.first { $0.id == "andrew-mehlbaum" } ?? PreviewData.will
    return PoolEntryRow(
        entry: entry,
        weeks: [1, 2, 3, 4],
        isCommissioner: true,
        logoURL: { PreviewData.logos[$0] }
    )
    .padding()
}
#endif
