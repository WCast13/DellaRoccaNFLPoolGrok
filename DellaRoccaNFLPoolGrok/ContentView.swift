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

    var body: some View {
        TabView {
            PoolBoardView(pool: pool)
                .tabItem {
                    Label("Pool", systemImage: "list.bullet")
                }
            TeamListView()
                .tabItem {
                    Label("Teams", systemImage: "paintpalette")
                }
        }
    }
}



private struct TeamListView: View {
    var body: some View {
        NavigationStack {
            List(NFLTeam.all) { team in
                TeamColorsRow(team: team)
            }
            .navigationTitle("NFL Teams")
        }
    }
}

private struct TeamColorsRow: View {
    let team: NFLTeam

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(team.abbreviation)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(team.primaryColor.foreground)
                    .frame(width: 48, height: 28)
                    .background(team.primaryColor.color, in: RoundedRectangle(cornerRadius: 6))

                Text(team.name)
                    .font(.body.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(team.colors) { teamColor in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(teamColor.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                            }
                        Text(teamColor.name)
                            .font(.subheadline)
                        Text(teamColor.hex)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
