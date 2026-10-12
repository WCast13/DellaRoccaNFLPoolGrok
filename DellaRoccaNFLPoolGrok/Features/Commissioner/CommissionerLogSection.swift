import SwiftUI

/// The newest few log events on the commissioner tab, with a way into the
/// full log. Lives on the tab so a commissioner sees what just happened
/// without going looking.
struct CommissionerLogSection: View {
    @Bindable var session: PlayerSession

    private let shown = 6

    var body: some View {
        Section {
            if !session.activityLogLoaded {
                Text("Loading activity…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if session.activityLog.isEmpty {
                Text("Nothing logged yet. Picks, sign-ins, buybacks, and sync runs will show here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.activityLog.prefix(shown)) { event in
                    ActivityEventRow(event: event)
                }
                NavigationLink {
                    CommissionerLogView(session: session)
                } label: {
                    Text("All activity")
                }
            }
        } header: {
            Text("Activity")
        }
    }
}

#if DEBUG
#Preview("Activity section") {
    NavigationStack {
        List {
            CommissionerLogSection(session: PreviewData.commissioner())
        }
    }
}
#endif
