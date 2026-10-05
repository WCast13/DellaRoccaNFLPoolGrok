import SwiftUI

struct CommissionerEntryView: View {
    @Bindable var session: PlayerSession
    let entryID: String
    @State private var week = 4
    @State private var selectedTeam: String?
    @State private var confirmBuyback = false
    @State private var confirmDecline = false

    private var entry: ClaimedEntry? {
        session.roster.first { $0.id == entryID }
    }

    var body: some View {
        Group {
            if let entry {
                editor(entry)
            } else {
                ContentUnavailableView("Entry unavailable", systemImage: "person.slash")
            }
        }
        .navigationTitle(entry?.label ?? "Entry")
        .onAppear {
            if let openWeek = session.openWeek { week = openWeek }
            session.watchCommissionerEntry(entryID)
            if let entry, let openWeek = session.openWeek {
                selectedTeam = session.picks(for: entry)[openWeek]
            }
        }
    }

    private func editor(_ entry: ClaimedEntry) -> some View {
        let picks = session.picks(for: entry)
        return List {
            Section {
                Text(entry.statusLine)
                Text(entry.isClaimed ? "Claimed on a player account" : "No login. A commissioner enters this entry's picks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !picks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(picks.keys.sorted(), id: \.self) { pickWeek in
                                if let team = picks[pickWeek] {
                                    VStack(spacing: 4) {
                                        Text("W\(pickWeek)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        TeamPickChip(
                                            abbreviation: team,
                                            selected: false,
                                            dimmed: false,
                                            logoURL: session.teamLogos[team]
                                        )
                                        .frame(width: 76)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if entry.status == .pendingBuyback {
                Section("Buyback") {
                    Button("Record buyback") { confirmBuyback = true }
                        .disabled(session.isBusy)
                    Button("Decline buyback", role: .destructive) { confirmDecline = true }
                        .disabled(session.isBusy)
                }
            }

            Section("Week \(week)") {
                Stepper("Week \(week)", value: $week, in: 1...18)
                    .onChange(of: week) { _, newWeek in
                        selectedTeam = picks[newWeek]
                    }
                Text("You can correct a pick after kickoff. The player can change it only before kickoff, and only on an entry they claimed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if entry.status != .active {
                    Text("Record a buyback before entering a new pick. This entry is not alive.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(session.games(in: week)) { game in
                    gameRow(game, entry: entry)
                }
                Button(saveTitle(entry: entry, picks: picks)) {
                    guard let selectedTeam else { return }
                    Task {
                        await session.submitPick(
                            entryID: entry.id,
                            week: week,
                            team: selectedTeam,
                            confirmation: "Saved \(selectedTeam) for \(entry.label) in week \(week)."
                        )
                    }
                }
                .disabled(session.isBusy || !canSave(entry: entry))
            }

            if session.notice != nil || session.errorMessage != nil {
                Section {
                    if let notice = session.notice {
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let errorMessage = session.errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
        }
        .confirmationDialog("Record a buyback for \(entry.label)?", isPresented: $confirmBuyback, titleVisibility: .visible) {
            Button("Record buyback") {
                Task { await session.recordBuyback(entryID: entry.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The entry is alive again. Teams already used stay used.")
        }
        .confirmationDialog("Decline the buyback for \(entry.label)?", isPresented: $confirmDecline, titleVisibility: .visible) {
            Button("Decline buyback", role: .destructive) {
                Task { await session.declineBuyback(entryID: entry.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The entry is out for the season.")
        }
    }

    private func gameRow(_ game: PoolGame, entry: ClaimedEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                teamButton(game.awayAbbr, game: game, entry: entry)
                Text("at")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 22)
                teamButton(game.homeAbbr, game: game, entry: entry)
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

    private func teamButton(_ abbreviation: String, game: PoolGame, entry: ClaimedEntry) -> some View {
        let allowed = canSelect(abbreviation, game: game, entry: entry)
        let reason = unavailableReason(abbreviation, entry: entry)
        return VStack(spacing: 4) {
            Button {
                selectedTeam = abbreviation
            } label: {
                TeamPickChip(
                    abbreviation: abbreviation,
                    selected: selectedTeam == abbreviation,
                    dimmed: !allowed && selectedTeam != abbreviation,
                    logoURL: session.teamLogos[abbreviation]
                )
            }
            .buttonStyle(.plain)
            .disabled(!allowed)
            if let reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func unavailableReason(_ abbreviation: String, entry: ClaimedEntry) -> String? {
        if let usedWeek = session.usedTeams(for: entry)[abbreviation], usedWeek != week {
            return "Used in week \(usedWeek)"
        }
        return nil
    }

    private func canSelect(_ abbreviation: String, game: PoolGame, entry: ClaimedEntry) -> Bool {
        guard entry.status == .active else { return false }
        guard game.homeAbbr == abbreviation || game.awayAbbr == abbreviation else { return false }
        if let usedWeek = session.usedTeams(for: entry)[abbreviation], usedWeek != week {
            return false
        }
        return true
    }

    private func canSave(entry: ClaimedEntry) -> Bool {
        guard entry.status == .active, let selectedTeam,
              selectedTeam != session.picks(for: entry)[week],
              let game = session.games(in: week).first(where: {
                  $0.homeAbbr == selectedTeam || $0.awayAbbr == selectedTeam
              }) else {
            return false
        }
        return canSelect(selectedTeam, game: game, entry: entry)
    }

    private func saveTitle(entry: ClaimedEntry, picks: [Int: String]) -> String {
        let current = picks[week]
        guard let selectedTeam else { return "Save pick" }
        let name = NFLTeam.shortName(for: selectedTeam)
        if selectedTeam != current {
            return current == nil ? "Save \(name)" : "Change pick to \(name)"
        }
        return "\(name) saved"
    }
}

#if DEBUG
#Preview("Correct a pick") {
    NavigationStack {
        CommissionerEntryView(session: PreviewData.commissioner(), entryID: PreviewData.will.id)
    }
}

#Preview("Buyback") {
    NavigationStack {
        CommissionerEntryView(session: PreviewData.commissioner(), entryID: "pat-buyer")
    }
}
#endif
