import SwiftUI

struct EntrySummaryRow: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.label)
                .font(.body.weight(.semibold))
            Text(entry.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.status == .active, let week = session.openWeek {
                if let team = session.picks(for: entry)[week] {
                    Text("Week \(week): \(NFLTeam.shortName(for: team))")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Week \(week): No pick")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
#Preview("Entry rows") {
    let buyback = PreviewData.standings.first { $0.id == "pat-buyer" } ?? PreviewData.will
    return List {
        EntrySummaryRow(session: PreviewData.player(), entry: PreviewData.will)
        EntrySummaryRow(session: PreviewData.player(), entry: PreviewData.casa)
        EntrySummaryRow(session: PreviewData.player(), entry: buyback)
    }
}
#endif
