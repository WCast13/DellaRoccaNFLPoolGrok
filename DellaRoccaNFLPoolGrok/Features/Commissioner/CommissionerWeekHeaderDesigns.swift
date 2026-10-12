#if DEBUG
import SwiftUI

// Design explorations for the commissioner week header. DEBUG-only
// scaffolding: referenced solely by the previews here and in
// CommissionerWeekSummaryDesigns, never shipped. The header in use is
// CommissionerWeekHeader; each design below pairs with the summary design of
// the same letter.

// MARK: - Design A · Pill stepper with a status line
//
// The arrows and the week share one capsule, so the control reads as a single
// stepper rather than three loose pieces. A caption under the week says what
// the week is doing: open for picks, closed, upcoming, or unscheduled.

struct CommissionerWeekHeaderA: View {
    @Binding var week: Int
    let scheduledWeeks: [Int]
    let openWeek: Int?

    private let range = 1...18

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: "Previous week", to: week - 1)
            Menu {
                Picker("Jump to week", selection: $week) {
                    ForEach(Array(range), id: \.self) { candidate in
                        Text(menuLabel(for: candidate)).tag(candidate)
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    Text("Week \(week)")
                        .font(.headline)
                        .monospacedDigit()
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(week == openWeek ? Color.green : Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .tint(.primary)
            .accessibilityLabel("Week \(week), \(statusLine). Jump to another week")
            arrow("chevron.right", label: "Next week", to: week + 1)
        }
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var statusLine: String {
        if !scheduledWeeks.contains(week) { return "No games" }
        guard let openWeek else { return "Scheduled" }
        if week == openWeek { return "Open for picks" }
        return week < openWeek ? "Closed" : "Upcoming"
    }

    private func arrow(_ systemImage: String, label: String, to target: Int) -> some View {
        Button {
            week = target
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!range.contains(target))
        .accessibilityLabel(label)
    }

    private func menuLabel(for candidate: Int) -> String {
        if candidate == openWeek { return "Week \(candidate) — open for picks" }
        if !scheduledWeeks.contains(candidate) { return "Week \(candidate) — no games" }
        return "Week \(candidate)"
    }
}

// MARK: - Design B · Big week number with the slate's dates
//
// The week number is the headline, with the span of the week's kickoffs under
// it, so the commissioner can tell at a glance which weekend they are looking
// at. Stepping and jumping move to round buttons on the trailing edge.

struct CommissionerWeekHeaderB: View {
    @Binding var week: Int
    let scheduledWeeks: [Int]
    let openWeek: Int?
    /// Kickoffs of the selected week's games, for the date range under the
    /// number. Empty shows the week's state instead.
    var kickoffs: [Date] = []

    private let range = 1...18

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("WEEK")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text("\(week)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(week == openWeek ? Color.green : Color.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                roundButton("chevron.left", label: "Previous week", to: week - 1)
                roundButton("chevron.right", label: "Next week", to: week + 1)
                Menu {
                    Picker("Jump to week", selection: $week) {
                        ForEach(Array(range), id: \.self) { candidate in
                            Text(menuLabel(for: candidate)).tag(candidate)
                        }
                    }
                } label: {
                    Image(systemName: "calendar")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.quaternary.opacity(0.6), in: Circle())
                }
                .tint(.primary)
                .accessibilityLabel("Jump to a week")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        if let first = kickoffs.min(), let last = kickoffs.max() {
            let span = first.formatted(.dateTime.month(.abbreviated).day())
                + " – " + last.formatted(.dateTime.month(.abbreviated).day())
            return week == openWeek ? "Open for picks · \(span)" : span
        }
        if !scheduledWeeks.contains(week) { return "No games scheduled" }
        return week == openWeek ? "Open for picks" : " "
    }

    private func roundButton(_ systemImage: String, label: String, to target: Int) -> some View {
        Button {
            withAnimation(.snappy) { week = target }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.quaternary.opacity(0.6), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!range.contains(target))
        .accessibilityLabel(label)
    }

    private func menuLabel(for candidate: Int) -> String {
        if candidate == openWeek { return "Week \(candidate) — open for picks" }
        if !scheduledWeeks.contains(candidate) { return "Week \(candidate) — no games" }
        return "Week \(candidate)"
    }
}

// MARK: - Design C · Scrolling week rail
//
// Every week is a chip on one horizontal rail, so jumping is a tap rather than
// a menu and the season's shape is visible: the selected week is filled, the
// open week carries a green dot, and weeks with no games are dimmed. The rail
// keeps the selected week centred as it changes.

struct CommissionerWeekHeaderC: View {
    @Binding var week: Int
    let scheduledWeeks: [Int]
    let openWeek: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(1...18, id: \.self) { candidate in
                        chip(candidate)
                            .id(candidate)
                    }
                }
                .padding(2)
            }
            .onAppear {
                proxy.scrollTo(week, anchor: .center)
            }
            .onChange(of: week) { _, newWeek in
                withAnimation(.snappy) { proxy.scrollTo(newWeek, anchor: .center) }
            }
        }
    }

    private func chip(_ candidate: Int) -> some View {
        let selected = candidate == week
        let scheduled = scheduledWeeks.contains(candidate)
        return Button {
            week = candidate
        } label: {
            VStack(spacing: 3) {
                Text("\(candidate)")
                    .font(.subheadline.weight(selected ? .bold : .medium))
                    .monospacedDigit()
                Circle()
                    .fill(candidate == openWeek ? Color.green : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 40, height: 40)
            .foregroundStyle(selected ? Color.white : (scheduled ? Color.primary : Color.secondary.opacity(0.5)))
            .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if !selected {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: candidate))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func accessibilityLabel(for candidate: Int) -> String {
        if candidate == openWeek { return "Week \(candidate), open for picks" }
        if !scheduledWeeks.contains(candidate) { return "Week \(candidate), no games" }
        return "Week \(candidate)"
    }
}

#Preview("Header designs") {
    @Previewable @State var week = 4
    let session = PreviewData.commissioner()
    let scheduled = Array(Set(session.games.map(\.week))).sorted()
    return List {
        Section("Current") {
            CommissionerWeekHeader(week: $week, scheduledWeeks: scheduled, openWeek: session.openWeek)
        }
        Section("Design A · Pill stepper") {
            CommissionerWeekHeaderA(week: $week, scheduledWeeks: scheduled, openWeek: session.openWeek)
        }
        Section("Design B · Big number") {
            CommissionerWeekHeaderB(
                week: $week,
                scheduledWeeks: scheduled,
                openWeek: session.openWeek,
                kickoffs: session.games(in: week).map(\.kickoff)
            )
        }
        Section("Design C · Week rail") {
            CommissionerWeekHeaderC(week: $week, scheduledWeeks: scheduled, openWeek: session.openWeek)
        }
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
}
#endif
