import SwiftUI
import Playgrounds
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


struct ContentView: View {
    private let pool = SurvivorPoolLoader.load()
    @State private var session: PlayerSession?

    var body: some View {
        TabView {
            PoolBoardView(pool: pool)
                .tabItem {
                    Label("Pool", systemImage: "list.bullet")
                }
            MyEntriesView(session: session)
                .tabItem {
                    Label("My Entries", systemImage: "person.crop.circle")
                }
            CommissionerView(session: session)
                .tabItem {
                    Label("Commissioner", systemImage: "checkmark.shield")
                }
        }
        .task {
            if session == nil {
                session = PlayerSession()
            }
        }
    }
}



#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
