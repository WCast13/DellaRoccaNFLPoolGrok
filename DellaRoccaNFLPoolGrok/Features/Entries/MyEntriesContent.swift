import SwiftUI

struct MyEntriesContent: View {
    @Bindable var session: PlayerSession
    var previewEntryID: String?
    @State private var pin = ""
    @State private var claiming = false
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !session.entriesLoaded {
                    // The first render has a user and an empty list, so the
                    // count alone would flash the claim form at a returning
                    // player until Firestore delivers.
                    ProgressView("Loading your entries")
                } else if session.entries.isEmpty {
                    ClaimEntryForm(session: session, pin: $pin)
                } else {
                    MyEntriesList(session: session, claiming: $claiming)
                }
            }
            .navigationTitle("My Entries")
            .toolbar {
                if session.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Sign Out", action: session.signOut)
                    }
                }
            }
            .navigationDestination(for: String.self) { entryID in
                if let entry = session.entries.first(where: { $0.id == entryID }) {
                    EntryEditorView(session: session, entry: entry)
                } else {
                    ContentUnavailableView("Entry unavailable", systemImage: "person.slash")
                }
            }
        }
        .onAppear {
            if let previewEntryID, path.isEmpty {
                path = [previewEntryID]
            }
        }
        .sheet(isPresented: $claiming) {
            NavigationStack {
                ClaimEntryForm(session: session, pin: $pin)
                    .navigationTitle("Claim an entry")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { claiming = false }
                        }
                    }
            }
        }
    }
}

#if DEBUG
#Preview("Loading") {
    MyEntriesContent(session: PreviewData.loading())
}

#Preview("Claim") {
    MyEntriesContent(session: PreviewData.claim())
}

#Preview("Entries") {
    MyEntriesContent(session: PreviewData.player())
}
#endif
