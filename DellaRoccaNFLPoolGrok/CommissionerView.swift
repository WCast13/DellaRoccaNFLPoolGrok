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

private struct CommissionerContent: View {
    @Bindable var session: PlayerSession
    @State private var query = ""
    @State private var week = 4
    @State private var preview: CloseWeekReport?
    @State private var confirmClose = false
    @State private var commissionerEmail = ""

    private var filtered: [ClaimedEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return session.roster }
        return session.roster.filter { $0.label.localizedStandardContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !session.isSignedIn {
                    message("Sign in with Apple on My Entries. Commissioner tools appear on Ralph's and Will's accounts.")
                } else if !session.isAdmin {
                    message("\(session.accountLabel) is not a commissioner yet. A commissioner can add this Apple account's email.")
                } else {
                    roster
                }
            }
            .navigationTitle("Commissioner")
            .searchable(text: $query, prompt: "Entry name")
        }
        .onAppear {
            if let openWeek = session.openWeek {
                week = openWeek
            }
        }
    }

    private var roster: some View {
        List {
            Section("Close a week") {
                Stepper("Week \(week)", value: $week, in: 1...18)
                    .onChange(of: week) { _, _ in preview = nil }
                Text("A missing pick becomes a loss once every game has kicked off. Through week 6 that entry can still buy back. After week 6 the loss is final.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Preview week \(week)") {
                    Task { preview = await session.closeWeek(week: week, apply: false) }
                }
                .disabled(session.isBusy)
                if let preview, preview.week == week {
                    Text("\(preview.wins) wins · \(preview.losses) losses · \(preview.missingPicks) missing · \(preview.ungraded) not final")
                        .font(.subheadline)
                    ForEach(preview.examples, id: \.self) { example in
                        Text(example)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !preview.applied {
                        Button("Close week \(week)", role: .destructive) {
                            confirmClose = true
                        }
                        .disabled(session.isBusy)
                    }
                }
            }

            Section("Entries") {
                ForEach(filtered) { entry in
                    NavigationLink {
                        CommissionerEntryView(session: session, entryID: entry.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.label)
                                .font(.body.weight(.semibold))
                            Text(entrySubtitle(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Add a commissioner") {
                TextField("Apple ID email", text: $commissionerEmail)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .autocorrectionDisabled()
                Button("Allow this email") {
                    Task {
                        await session.addCommissionerEmail(commissionerEmail)
                        if session.errorMessage == nil { commissionerEmail = "" }
                    }
                }
                .disabled(session.isBusy || !commissionerEmail.contains("@"))
            }

            if session.notice != nil || session.errorMessage != nil {
                Section {
                    statusMessages
                }
            }
        }
        .confirmationDialog("Close week \(week)?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Close week \(week)", role: .destructive) {
                Task { preview = await session.closeWeek(week: week, apply: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Alive entries with no pick, or with a final loss, are knocked out. This can be bought back through week 6.")
        }
    }

    private func entrySubtitle(_ entry: ClaimedEntry) -> String {
        let login = entry.isClaimed ? "Has a login" : "No login"
        return "\(entry.statusLine) · \(login)"
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let notice = session.notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let errorMessage = session.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

private struct CommissionerEntryView: View {
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
                                        TeamPickChip(abbreviation: team, selected: false, dimmed: false)
                                            .frame(width: 64)
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
            HStack(spacing: 8) {
                teamButton(game.awayAbbr, game: game, entry: entry)
                Text("at")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        return Button {
            selectedTeam = abbreviation
        } label: {
            TeamPickChip(
                abbreviation: abbreviation,
                selected: selectedTeam == abbreviation,
                dimmed: !allowed && selectedTeam != abbreviation
            )
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
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
              let game = session.games(in: week).first(where: {
                  $0.homeAbbr == selectedTeam || $0.awayAbbr == selectedTeam
              }) else {
            return false
        }
        return canSelect(selectedTeam, game: game, entry: entry)
    }

    private func saveTitle(entry: ClaimedEntry, picks: [Int: String]) -> String {
        let current = picks[week]
        if let selectedTeam, selectedTeam != current {
            return current == nil ? "Save \(selectedTeam)" : "Change pick to \(selectedTeam)"
        }
        return "Save pick"
    }
}
