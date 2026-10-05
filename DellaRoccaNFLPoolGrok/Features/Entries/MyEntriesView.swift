import SwiftUI

struct MyEntriesView: View {
    var session: PlayerSession?
    var previewEntryID: String?

    var body: some View {
        if let session {
            MyEntriesContent(session: session, previewEntryID: previewEntryID)
        } else {
            ProgressView("Opening the pool")
        }
    }
}

#if DEBUG
#Preview("Sign in") {
    MyEntriesView(session: PreviewData.signedOut())
}

#Preview("Claim a PIN") {
    MyEntriesView(session: PreviewData.claim())
}

#Preview("My entries") {
    MyEntriesView(session: PreviewData.player())
}

#Preview("Make a pick") {
    MyEntriesView(session: PreviewData.player(), previewEntryID: PreviewData.will.id)
}

#Preview("Saved pick") {
    MyEntriesView(session: PreviewData.player(), previewEntryID: PreviewData.casa.id)
}
#endif
