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
#endif
