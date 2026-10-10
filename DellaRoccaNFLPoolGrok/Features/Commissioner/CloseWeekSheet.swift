import SwiftUI

/// Preview and close a week in one place. Previews on appear, then shows the
/// counts it would apply next to the button that applies them — so the numbers
/// the commissioner agrees to are the numbers on screen.
struct CloseWeekSheet: View {
    @Bindable var session: PlayerSession
    let week: Int
    @Environment(\.dismiss) private var dismiss

    @State private var report: CloseWeekReport?
    @State private var confirmClose = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A missing pick becomes a loss once every game has kicked off. Through week 6 that entry can still buy back. After week 6 the loss is final.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if session.isBusy && report == nil {
                    Section { ProgressView("Checking week \(week)") }
                } else if let report, report.week == week {
                    Section("What this will do") {
                        counts(report)
                        ForEach(report.examples, id: \.self) { example in
                            Text(example)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if report.applied {
                        Section {
                            Label("Week \(week) is closed.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Section {
                            Button("Close week \(week)", role: .destructive) {
                                confirmClose = true
                            }
                            .disabled(session.isBusy)
                            if report.ungraded > 0 {
                                Text("\(report.ungraded) picked games are not final yet. Those entries stay ungraded and the week can be closed again later to finish them.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if session.errorMessage != nil || session.notice != nil {
                    Section { StatusMessageText(notice: session.notice, errorMessage: session.errorMessage) }
                }
            }
            .navigationTitle("Close week \(week)")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(report?.applied == true ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Re-check") {
                        Task { report = await session.closeWeek(week: week, apply: false) }
                    }
                    .disabled(session.isBusy)
                }
            }
        }
        .task {
            if report == nil {
                report = await session.closeWeek(week: week, apply: false)
            }
        }
        .confirmationDialog("Close week \(week)?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Close week \(week)", role: .destructive) {
                Task { report = await session.closeWeek(week: week, apply: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private func counts(_ report: CloseWeekReport) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            countRow("Wins", report.wins)
            countRow("Losses", report.losses)
            countRow("No pick", report.missingPicks)
            countRow("Not final", report.ungraded)
            countRow("Buybacks lapsed", report.lapsedBuybacks)
        }
        .font(.subheadline)
    }

    private func countRow(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text("\(value)")
                .monospacedDigit()
                .fontWeight(.semibold)
                .gridColumnAlignment(.trailing)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    /// Repeats the numbers in the confirmation, since these are the entries the
    /// tap actually knocks out.
    private var confirmationMessage: String {
        guard let report, report.week == week else {
            return "Alive entries with no pick, or with a final loss, are knocked out."
        }
        let knockedOut = report.losses + report.missingPicks
        var lines = ["\(knockedOut) entries are knocked out: \(report.losses) lost, \(report.missingPicks) had no pick."]
        if report.lapsedBuybacks > 0 {
            lines.append("\(report.lapsedBuybacks) never completed a buyback and are out for the season, owing nothing.")
        }
        lines.append("A loss through week 6 can still be bought back.")
        return lines.joined(separator: " ")
    }
}

#if DEBUG
#Preview("Close week") {
    CloseWeekSheet(session: PreviewData.commissioner(), week: 3)
}
#endif
