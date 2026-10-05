import SwiftUI

struct CommissionerView: View {
    var session: PlayerSession?

    var body: some View {
        if let session {
            CommissionerContent(session: session)
        } else {
            ProgressView("Opening the pool")
        }
    }
}

#if DEBUG
#Preview("Queues") {
    CommissionerView(session: PreviewData.commissioner())
}

#Preview("Sign in") {
    CommissionerView(session: PreviewData.signedOut())
}

#Preview("Not a commissioner") {
    CommissionerView(session: PreviewData.player())
}
#endif
