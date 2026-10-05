import SwiftUI

struct MyEntriesList: View {
    @Bindable var session: PlayerSession
    @Binding var claiming: Bool

    var body: some View {
        List {
            Section {
                ForEach(session.entries) { entry in
                    NavigationLink(value: entry.id) {
                        EntrySummaryRow(session: session, entry: entry)
                    }
                }
            }
            Section {
                Button("Claim another entry") { claiming = true }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
        }
    }
}
