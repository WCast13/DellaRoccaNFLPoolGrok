import SwiftUI

/// One week's pick in the horizontal history strip: a "W<week>" label above the
/// team chip, with an optional result label beneath. Shared by the pick editor,
/// the commissioner entry screen, and the pool board row.
struct WeekPickChip: View {
    let week: Int
    let team: String?
    /// Result such as "Loss" / "Bought back"; also dims the chip when present.
    var result: String? = nil
    var logoURL: URL? = nil
    /// Explicit chip sizing. `nil` leaves the dimension unconstrained.
    var chipWidth: CGFloat? = nil
    var chipHeight: CGFloat? = nil
    /// When there is no pick, show a placeholder ("—" / "No pick") instead of
    /// nothing. Used on the pool board; off in the editors (which only ever
    /// render weeks that already have a pick).
    var showsEmptyPlaceholder: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text("W\(week)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let team {
                TeamPickChip(
                    abbreviation: team,
                    selected: false,
                    dimmed: result != nil,
                    logoURL: logoURL
                )
                .frame(width: chipWidth, height: chipHeight)
            } else if showsEmptyPlaceholder {
                Text(result == nil ? "—" : "No pick")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let result {
                Text(result)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let name = team.map { NFLTeam.shortName(for: $0) } ?? "no pick"
        if let result { return "Week \(week) \(name), \(result)" }
        return "Week \(week) \(name)"
    }
}

#if DEBUG
#Preview("Week chips") {
    HStack(spacing: 8) {
        WeekPickChip(week: 1, team: "GB", logoURL: PreviewData.logos["GB"], chipWidth: 50, chipHeight: 50)
        WeekPickChip(week: 2, team: "DAL", result: "Loss", logoURL: PreviewData.logos["DAL"], chipWidth: 50, chipHeight: 50)
        WeekPickChip(week: 3, team: nil, showsEmptyPlaceholder: true)
    }
    .padding()
}
#endif
