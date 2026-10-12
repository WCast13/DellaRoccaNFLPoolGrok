import SwiftUI

/// Every entry's season so far, as one aligned table: entries down, weeks 1
/// through the selected week across.
///
/// The entry column is pinned and only the weeks scroll, so a week can be read
/// straight down the board — which is the whole point of the grid, and what
/// per-row scrolling strips cannot do, since each row would scroll separately.
/// Both halves share `rowHeight` to stay in register.
struct CommissionerEntriesGrid: View {
    @Bindable var session: PlayerSession
    let entries: [ClaimedEntry]
    /// Weeks 1 through this are shown.
    let throughWeek: Int
    /// Shown in place of the grid when `entries` is empty; the caller knows
    /// whether that is a filter, a search, or an empty pool.
    var emptyMessage = "No entries yet."
    /// Tapping an entry's name. The tab opens the pick sheet for `throughWeek`.
    let onSelect: (ClaimedEntry) -> Void

    private let rowHeight: CGFloat = 38
    private let headerHeight: CGFloat = 24
    private let cellWidth: CGFloat = 46
    private let nameWidth: CGFloat = 116

    private var weeks: [Int] { Array(1...max(1, throughWeek)) }

    var body: some View {
        if entries.isEmpty {
            Text(emptyMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 0) {
                pinnedNames
                Divider()
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(weeks, id: \.self) { week in
                                Text("W\(week)")
                                    .font(.caption2.weight(week == throughWeek ? .bold : .regular))
                                    .foregroundStyle(week == throughWeek ? .primary : .secondary)
                                    .frame(width: cellWidth, height: headerHeight)
                            }
                        }
                        ForEach(entries) { entry in
                            HStack(spacing: 0) {
                                ForEach(weeks, id: \.self) { week in
                                    cell(entry, week: week)
                                        .frame(width: cellWidth, height: rowHeight)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var pinnedNames: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Entry")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: nameWidth, height: headerHeight, alignment: .leading)
            ForEach(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(statusTag(entry))
                            .font(.system(size: 9))
                            .foregroundStyle(statusColor(entry))
                    }
                    .frame(width: nameWidth, height: rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the week \(throughWeek) pick for this entry")
            }
        }
    }

    @ViewBuilder
    private func cell(_ entry: ClaimedEntry, week: Int) -> some View {
        let team = session.picks(for: entry)[week]
        let result = entry.resultLabel(for: week)
        ZStack {
            if let team {
                let palette = NFLTeam.team(abbreviation: team)
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette?.primaryColor.color ?? .gray)
                    .padding(2)
                Text(team)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette?.primaryColor.foreground ?? .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let result {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(result == "Loss" ? Color.red : Color.green, lineWidth: 2)
                    .padding(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cellLabel(entry, week: week, team: team, result: result))
    }

    private func cellLabel(_ entry: ClaimedEntry, week: Int, team: String?, result: String?) -> String {
        let name = team.map { NFLTeam.shortName(for: $0) } ?? "no pick"
        if let result { return "\(entry.label), week \(week), \(name), \(result)" }
        return "\(entry.label), week \(week), \(name)"
    }

    private func statusTag(_ entry: ClaimedEntry) -> String {
        if entry.buybackUnpaid { return "Owes fee" }
        switch entry.status {
        case .active: return entry.isClaimed ? "Alive" : "No login"
        case .pendingBuyback: return "Buyback"
        case .eliminated: return "Out"
        }
    }

    private func statusColor(_ entry: ClaimedEntry) -> Color {
        if entry.buybackUnpaid { return .orange }
        switch entry.status {
        case .active: return entry.isClaimed ? .secondary : .orange
        case .pendingBuyback: return .orange
        case .eliminated: return .red
        }
    }
}

#if DEBUG
#Preview("Entries grid") {
    let session = PreviewData.commissioner()
    return List {
        Section {
            CommissionerEntriesGrid(session: session, entries: session.roster, throughWeek: 4) { _ in }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}
#endif
