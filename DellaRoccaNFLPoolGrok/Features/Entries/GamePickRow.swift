import SwiftUI
import Playgrounds

struct GamePickRow: View {
    @Bindable var session: PlayerSession
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    @Binding var selectedTeam: String?
    
   

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                PickTeamButton(
                    abbreviation: game.awayAbbr,
                    game: game,
                    entry: entry,
                    week: week,
                    usedTeams: session.usedTeams(for: entry),
                    logoURL: session.teamLogos[game.awayAbbr],
                    selectedTeam: $selectedTeam
                )
                Text("at")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 22)
                PickTeamButton(
                    abbreviation: game.homeAbbr,
                    game: game,
                    entry: entry,
                    week: week,
                    usedTeams: session.usedTeams(for: entry),
                    logoURL: session.teamLogos[game.homeAbbr],
                    selectedTeam: $selectedTeam
                )
            }
            HStack {
                Text(game.kickoff.formatted(date: .abbreviated, time: .shortened))
                if let spread = game.spreadLabel {
                    Text(spread)
                }
                Spacer()
                if game.hasKickedOff {
                    Text("Kicked off")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct NewGamePickRowTwo: View {
    @Bindable var session: PlayerSession
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    @Binding var selectedTeam: String?
    
    var body: some View {
        VStack {
            HStack {
                
                
                PickTeamButton(
                    abbreviation: game.awayAbbr,
                    game: game,
                    entry: entry,
                    week: week,
                    usedTeams: session.usedTeams(for: entry),
                    logoURL: session.teamLogos[game.awayAbbr],
                    selectedTeam: $selectedTeam
                )
//                .frame(maxWidth: 100)
                .padding(.vertical, 6)
                
               
                
                
                Text("1-1")
                    .font(.caption)
                
                Spacer()
                
                Text("13:00")
                    .font(.caption)
                    .bold()
                
                Spacer()

                
                Text("1-1")
                    .font(.caption)
                
                
                
                PickTeamButton(
                    abbreviation: game.homeAbbr,
                    game: game,
                    entry: entry,
                    week: week,
                    usedTeams: session.usedTeams(for: entry),
                    logoURL: session.teamLogos[game.homeAbbr],
                    selectedTeam: $selectedTeam
                )
//                .frame(maxWidth: 100)
                
                
                
            }
            
            Text (game.spreadLabel ?? "")
            .font(.caption)
        }
//        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.2))
    }
}

#if DEBUG

#Preview("Both Open and Locked") {
    @Previewable @State var selectedTeam: String? = "NYG"
    NewGamePickRowTwo(
        session: PreviewData.player(),
        game: PreviewData.games.first { $0.id == "w4-jax" } ?? PreviewData.games[0],
        entry: PreviewData.will,
        week: 4,
        selectedTeam: $selectedTeam
    )
    
    NewGamePickRowTwo(
        session: PreviewData.player(),
        game: PreviewData.games.first { $0.id == "w4-locked" } ?? PreviewData.games[0],
        entry: PreviewData.will,
        week: 4,
        selectedTeam: $selectedTeam
    )
}



//#Preview("Still open") {
//    @Previewable @State var selectedTeam: String? = "nil"
//    GamePickRow(
//        session: PreviewData.player(),
//        game: PreviewData.games.first { $0.id == "w4-jax" } ?? PreviewData.games[0],
//        entry: PreviewData.will,
//        week: 4,
//        selectedTeam: $selectedTeam
//    )
//    .padding()
//}

//#Preview("Kicked off") {
//    @Previewable @State var selectedTeam: String? = "NYG"
//    GamePickRow(
//        session: PreviewData.player(),
//        game: PreviewData.games.first { $0.id == "w4-locked" } ?? PreviewData.games[0],
//        entry: PreviewData.will,
//        week: 4,
//        selectedTeam: $selectedTeam
//    )
//    .padding()
//}
#endif

#Playground {
    let game = PreviewData.games.first!
    let kickoff = game.kickoff
}
