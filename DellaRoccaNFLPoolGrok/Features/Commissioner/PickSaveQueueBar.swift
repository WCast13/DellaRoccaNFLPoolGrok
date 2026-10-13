import SwiftUI

/// The strip along the bottom of the Commissioner tab while picks tapped in
/// the sheet are still on their way to the server: one line for the saves in
/// flight, and a row for each failed save with Retry and Dismiss. Gone when
/// the queue is empty.
struct PickSaveQueueBar: View {
    let items: [PendingPickSave]
    let onRetry: (UUID) -> Void
    let onDismiss: (UUID) -> Void

    private var active: [PendingPickSave] { items.filter { !$0.isFailed } }
    private var failed: [PendingPickSave] { items.filter(\.isFailed) }

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 0) {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if !active.isEmpty {
                        savingLine
                    }
                    ForEach(failed) { item in
                        failedRow(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private var savingLine: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(savingText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var savingText: String {
        if active.count == 1, let item = active.first {
            return "Saving \(NFLTeam.shortName(for: item.team)) for \(item.entryLabel)…"
        }
        return "Saving \(active.count) picks…"
    }

    private func failedRow(_ item: PendingPickSave) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Week \(item.week) · \(NFLTeam.shortName(for: item.team)) for \(item.entryLabel) not saved")
                    .font(.footnote.weight(.semibold))
                if let failure = item.failure {
                    Text(failure)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button("Retry") { onRetry(item.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Dismiss") { onDismiss(item.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

#if DEBUG
#Preview("Saving one") {
    PickSaveQueueBar(
        items: [PreviewData.savingPick],
        onRetry: { _ in },
        onDismiss: { _ in }
    )
}

#Preview("Saving several") {
    PickSaveQueueBar(
        items: [
            PreviewData.savingPick,
            PendingPickSave(id: UUID(), entryID: "casa-castellano", entryLabel: "Casa Castellano", week: 4, team: "KC", state: .queued),
            PendingPickSave(id: UUID(), entryID: "chris-early", entryLabel: "Chris Early", week: 4, team: "BUF", state: .queued),
        ],
        onRetry: { _ in },
        onDismiss: { _ in }
    )
}

#Preview("Failed") {
    PickSaveQueueBar(
        items: [PreviewData.failedPick],
        onRetry: { _ in },
        onDismiss: { _ in }
    )
}

#Preview("Mixed") {
    PickSaveQueueBar(
        items: [PreviewData.savingPick, PreviewData.failedPick],
        onRetry: { _ in },
        onDismiss: { _ in }
    )
}
#endif
