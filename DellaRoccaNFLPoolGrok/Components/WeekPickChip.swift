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
    /// Edge length of the team chip, and the width of the whole column.
    var chipSize: CGFloat = 50
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
                    logoURL: logoURL,
                    size: chipSize
                )
            } else if showsEmptyPlaceholder {
                // Height floor keeps a pickless week as tall as a chip week, so
                // row heights don't vary down the pool board.
                Text(result == nil ? "—" : "No pick")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: chipSize)
            }
            if let result {
                Text(result)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        // Every cell is exactly one chip wide, whatever it contains. This is the
        // alignment contract that lets a week be read straight down the board:
        // without it a "—" cell (~12pt) and a "No pick" cell (~50pt) put the
        // same week at different offsets on different rows.
        .frame(width: chipSize)
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
        WeekPickChip(week: 1, team: "GB", logoURL: PreviewData.logos["GB"])
        WeekPickChip(week: 2, team: "DAL", result: "Loss", logoURL: PreviewData.logos["DAL"])
        WeekPickChip(week: 3, team: nil, showsEmptyPlaceholder: true)
        WeekPickChip(week: 4, team: nil, result: "Loss", showsEmptyPlaceholder: true)
    }
    .padding()
}
#endif
