import SwiftUI

/// Week navigation for the commissioner tab: arrows to step a week at a time,
/// and a menu to jump anywhere in the season.
struct CommissionerWeekHeader: View {
    @Binding var week: Int
    /// Weeks the schedule actually has games for, used to label the jump menu.
    let scheduledWeeks: [Int]
    /// The week currently open for picks, flagged in the menu so a commissioner
    /// can find their way back to it.
    let openWeek: Int?

    private let range = 1...18

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                stepButton(
                    systemImage: "chevron.left",
                    label: "Previous week",
                    to: week - 1
                )
                Spacer()
                Menu {
                    Picker("Jump to week", selection: $week) {
                        ForEach(Array(range), id: \.self) { candidate in
                            Text(menuLabel(for: candidate)).tag(candidate)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Week \(week)")
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Week \(week). Jump to another week")
                Spacer()
                stepButton(
                    systemImage: "chevron.right",
                    label: "Next week",
                    to: week + 1
                )
            }
            Divider()
        }
    }

    private func stepButton(systemImage: String, label: String, to target: Int) -> some View {
        Button {
            week = target
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 32)
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

#if DEBUG
#Preview("Week header") {
    @Previewable @State var week = 3
    return CommissionerWeekHeader(week: $week, scheduledWeeks: [1, 2, 3, 4], openWeek: 4)
        .padding()
}
#endif
