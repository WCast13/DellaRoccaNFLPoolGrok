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
#Preview("Commissioner") {
    CommissionerView(session: PreviewData.commissioner())
}

/// The week header, slate and entries grid with nothing to act on, so the
/// layout can be judged without queue noise.
#Preview("Quiet week") {
    CommissionerView(session: PreviewData.commissionerQuietWeek())
}

#Preview("Sign in") {
    CommissionerView(session: PreviewData.signedOut())
}

#Preview("Not a commissioner") {
    CommissionerView(session: PreviewData.player())
}
#endif
