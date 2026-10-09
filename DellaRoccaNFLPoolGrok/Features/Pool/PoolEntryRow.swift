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
                            WeekPickChip(
                                week: week,
                                team: entry.picks[week],
                                result: entry.resultLabel(for: week),
                                logoURL: entry.picks[week].flatMap(logoURL),
                                showsEmptyPlaceholder: true
                            )
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
