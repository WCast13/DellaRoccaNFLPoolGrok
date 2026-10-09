import SwiftUI
import FirebaseCore

@main
struct MyApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private enum AppTab: Hashable {
    case pool
    case entries
    case commissioner
}

struct ContentView: View {
    @State private var session: PlayerSession?
    @State private var tab: AppTab = .pool
    @State private var appliedSignedInTab = false

    fileprivate init(previewSession: PlayerSession? = nil, previewTab: AppTab? = nil) {
        _session = State(initialValue: previewSession)
        if let previewTab {
            _tab = State(initialValue: previewTab)
            _appliedSignedInTab = State(initialValue: true)
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            PoolBoardView(session: session)
                .tabItem {
                    Label("Pool", systemImage: "list.bullet")
                }
                .tag(AppTab.pool)
            MyEntriesView(session: session)
                .tabItem {
                    Label("My Entries", systemImage: "person.crop.circle")
                }
                .tag(AppTab.entries)
            if session?.isAdmin == true {
                CommissionerView(session: session)
                    .tabItem {
                        Label("Commissioner", systemImage: "checkmark.shield")
                    }
                    .tag(AppTab.commissioner)
            }
        }
        .task {
            if session == nil {
                session = PlayerSession()
            }
        }
        .onChange(of: session?.isSignedIn) { _, signedIn in
            guard signedIn == true, !appliedSignedInTab else { return }
            appliedSignedInTab = true
            tab = .entries
        }
        .onChange(of: session?.isAdmin) { _, isAdmin in
            // The Commissioner tab only exists while isAdmin is true. If access
            // is revoked (e.g. sign-out) while it's selected, the bound
            // selection would point at a missing tag; fall back to Pool.
            if isAdmin != true, tab == .commissioner {
                tab = .pool
            }
        }
        .onAppear(perform: openEntriesIfSignedIn)
    }

    private func openEntriesIfSignedIn() {
        guard session?.isSignedIn == true, !appliedSignedInTab else { return }
        appliedSignedInTab = true
        tab = .entries
    }
}

#if DEBUG
#Preview("Signed out") {
    ContentView(previewSession: PreviewData.signedOut())
}

#Preview("Player") {
    ContentView(previewSession: PreviewData.player(), previewTab: .entries)
}

#Preview("Commissioner") {
    ContentView(previewSession: PreviewData.commissioner(), previewTab: .commissioner)
}
#endif
