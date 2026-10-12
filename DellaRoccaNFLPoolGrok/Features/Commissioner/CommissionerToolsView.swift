import SwiftUI

/// The commissioner's working tools, kept off the board: the activity log,
/// who has access, and the sync-and-grade button. Reached from the Tools
/// button in the Commissioner tab's toolbar, so the tab itself stays the
/// week header, slate, summary, and grid.
struct CommissionerToolsView: View {
    @Bindable var session: PlayerSession

    var body: some View {
        List {
            CommissionerLogSection(session: session)

            CommissionerAccessSection(session: session)

            GradeNowSection(session: session)

            if session.notice != nil || session.errorMessage != nil {
                Section {
                    StatusMessageText(notice: session.notice, errorMessage: session.errorMessage)
                }
            }
        }
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Tools") {
    NavigationStack {
        CommissionerToolsView(session: PreviewData.commissioner())
    }
}
#endif
