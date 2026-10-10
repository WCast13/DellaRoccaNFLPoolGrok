import SwiftUI

/// Runs the hourly sync-and-grade job on demand and shows what it did. Same
/// backend path as the schedule, so the result is exactly what the next tick
/// would have produced — for testing a grading run without waiting the hour.
struct GradeNowSection: View {
    @Bindable var session: PlayerSession
    @State private var summary: SeasonSyncSummary?

    var body: some View {
        Section {
            Button {
                Task { summary = await session.runSeasonSync() }
            } label: {
                Label("Sync scores and grade now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(session.isBusy)
            Text("Runs the hourly job immediately: refreshes scores, publishes locked picks, then grades every week whose games have all kicked off. Safe to repeat — a week already graded is skipped.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if session.isBusy {
                ProgressView("Running")
            } else if let summary {
                Text("\(summary.games) games synced · \(summary.publishedPicks) picks published")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if summary.graded.isEmpty {
                    Text("No week was ready to grade.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(summary.graded) { week in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Week \(week.week): \(week.wins) wins · \(week.losses) losses · \(week.missingPicks) no pick · \(week.ungraded) not final · \(week.lapsedBuybacks) buybacks lapsed")
                            .font(.subheadline)
                        ForEach(week.examples, id: \.self) { example in
                            Text(example)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Grade now")
        }
    }
}

#if DEBUG
#Preview("Grade now") {
    List {
        GradeNowSection(session: PreviewData.commissioner())
    }
}
#endif
