import SwiftUI

/// The popup behind an entry's name on the commissioner grid: enter or correct
/// that entry's pick for the week the tab is showing.
///
/// Teams the entry can still pick come first, one tile per team on the week's
/// slate with the opponent and the game's state beneath. The teams it has
/// already used sit under those, dimmed and labelled with the week they went.
/// Commissioners may change a pick after kickoff (the server allows it for
/// admins), so a started game stays selectable and says so under the chip.
///
/// A saved pick closes the sheet; the grid cell behind it shows the new team.
/// The buyback overrides that lived on the old entry screen are here too, since
/// this is now the only place a commissioner acts on one entry.
struct CommissionerPickSheet: View {
    @Bindable var session: PlayerSession
    let entryID: String
    let week: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeam: String?
    @State private var confirmBuyback = false
    @State private var confirmDecline = false
    /// Feedback from actions taken in this sheet. Snapshotted from the session
    /// after each call so an earlier, unrelated status never shows here.
    @State private var notice: String?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 8)]
    private let chipSize: CGFloat = 56

    /// Read live from the roster so a saved pick or a recorded buyback shows
    /// here without closing the sheet.
    private var entry: ClaimedEntry? {
        session.roster.first { $0.id == entryID }
    }

    private var savedTeam: String? {
        entry.flatMap { session.picks(for: $0)[week] }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    content(entry)
                } else {
                    ContentUnavailableView("Entry unavailable", systemImage: "person.slash")
                }
            }
            .navigationTitle(entry?.label ?? "Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedTeam = savedTeam
        }
        .onChange(of: savedTeam) { oldSaved, newSaved in
            // Follow a server-side change only while no unsaved choice is pending.
            if selectedTeam == nil || selectedTeam == oldSaved {
                selectedTeam = newSaved
            }
        }
    }

    private func content(_ entry: ClaimedEntry) -> some View {
        let games = session.games(in: week)
        let used = session.usedTeams(for: entry)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(entry)
                if entry.buybackUnpaid {
                    feeSection(entry)
                }
                if entry.status == .pendingBuyback {
                    buybackSection(entry)
                }
                if entry.status == .active {
                    availableSection(entry, games: games, used: used)
                } else {
                    Text("No pick can be entered while this entry is out.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                usedSection(used)
                StatusMessageText(notice: notice, errorMessage: errorMessage)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if entry.status == .active {
                saveBar(entry, games: games, used: used)
            }
        }
        .confirmationDialog("Record a buyback for \(entry.label)?", isPresented: $confirmBuyback, titleVisibility: .visible) {
            Button("Record buyback") {
                run { await session.recordBuyback(entryID: entry.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The entry is alive again. Teams already used stay used.")
        }
        .confirmationDialog("Decline the buyback for \(entry.label)?", isPresented: $confirmDecline, titleVisibility: .visible) {
            Button("Decline buyback", role: .destructive) {
                run { await session.declineBuyback(entryID: entry.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The entry is out for the season.")
        }
    }

    // MARK: Sections

    private func header(_ entry: ClaimedEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Week \(week)")
                .font(.headline)
            Text(entry.isClaimed ? entry.statusLine : "\(entry.statusLine) · no login")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func feeSection(_ entry: ClaimedEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Owes the buyback fee")
                    .font(.subheadline.weight(.semibold))
                Text("Elected a buyback after week \(entry.eliminatedWeek.map(String.init) ?? "?"). The fee is settled outside the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Mark paid") {
                run { await session.markBuybackPaid(entryID: entry.id) }
            }
            .buttonStyle(.bordered)
            .disabled(session.isBusy)
        }
    }

    private func buybackSection(_ entry: ClaimedEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Buyback")
            Text(electionLine(entry))
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Record buyback") { confirmBuyback = true }
                    .buttonStyle(.bordered)
                Button("Decline", role: .destructive) { confirmDecline = true }
                    .buttonStyle(.bordered)
            }
            .disabled(session.isBusy)
        }
    }

    private func electionLine(_ entry: ClaimedEntry) -> String {
        switch entry.buybackElection {
        case .buyIn: return "The player elected to buy back in. Recording it here makes the entry alive now."
        case .stayOut: return "The player elected to stay out. Recording a buyback overrides that."
        case nil: return "The player has not decided yet. Recording a buyback makes the entry alive now; declining puts it out for the season."
        }
    }

    private func availableSection(_ entry: ClaimedEntry, games: [PoolGame], used: [String: Int]) -> some View {
        let choices = games.flatMap { game in
            [game.awayAbbr, game.homeAbbr].compactMap { team -> Choice? in
                let reason = EntryPickRules.unavailableReason(
                    abbreviation: team,
                    game: game,
                    usedTeams: used,
                    week: week,
                    allowKickedOff: true
                )
                return reason == nil ? Choice(team: team, game: game) : nil
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Available this week")
            if games.isEmpty {
                Text("No games scheduled for week \(week).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if choices.isEmpty {
                Text("Every team playing this week has already been used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(choices) { choice in
                        choiceTile(choice, entry: entry, used: used)
                    }
                }
            }
        }
    }

    private func usedSection(_ used: [String: Int]) -> some View {
        let past = used
            .filter { $0.value != week }
            .map { UsedTeam(team: $0.key, week: $0.value) }
            .sorted { $0.week < $1.week }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Used")
            if past.isEmpty {
                Text("No teams used yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(past) { used in
                        VStack(spacing: 3) {
                            TeamPickChip(
                                abbreviation: used.team,
                                selected: false,
                                dimmed: true,
                                logoURL: session.teamLogos[used.team],
                                size: chipSize
                            )
                            Text(used.team)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Week \(used.week)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(NFLTeam.shortName(for: used.team)), used in week \(used.week)")
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Tiles

    private struct Choice: Identifiable {
        var team: String
        var game: PoolGame
        var id: String { team }
    }

    private struct UsedTeam: Identifiable {
        var team: String
        var week: Int
        var id: String { team }
    }

    private func choiceTile(_ choice: Choice, entry: ClaimedEntry, used: [String: Int]) -> some View {
        let allowed = EntryPickRules.canSelect(
            abbreviation: choice.team,
            game: choice.game,
            entry: entry,
            usedTeams: used,
            week: week,
            allowKickedOff: true
        )
        let state = gameState(choice)
        return Button {
            selectedTeam = choice.team
        } label: {
            VStack(spacing: 3) {
                TeamPickChip(
                    abbreviation: choice.team,
                    selected: selectedTeam == choice.team,
                    dimmed: !allowed && selectedTeam != choice.team,
                    logoURL: session.teamLogos[choice.team],
                    size: chipSize
                )
                Text(choice.team)
                    .font(.caption.weight(.semibold))
                Text(opponentLabel(choice))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(state.label)
                    .font(.caption2)
                    .foregroundStyle(state.color)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .accessibilityLabel("\(NFLTeam.shortName(for: choice.team)) \(opponentLabel(choice)), \(state.label)")
        .accessibilityAddTraits(selectedTeam == choice.team ? .isSelected : [])
    }

    private func opponentLabel(_ choice: Choice) -> String {
        choice.game.homeAbbr == choice.team ? "vs \(choice.game.awayAbbr)" : "@ \(choice.game.homeAbbr)"
    }

    /// Kickoff before the game; the team's own result once it is final. A
    /// tie reads as tied here but counts as a loss when graded.
    private func gameState(_ choice: Choice) -> (label: String, color: Color) {
        let game = choice.game
        if game.isFinal, let homeScore = game.homeScore, let awayScore = game.awayScore {
            let isHome = game.homeAbbr == choice.team
            let own = isHome ? homeScore : awayScore
            let other = isHome ? awayScore : homeScore
            if own > other { return ("Won \(own)–\(other)", .green) }
            if own < other { return ("Lost \(own)–\(other)", .red) }
            return ("Tied \(own)–\(other)", .red)
        }
        if game.isFinal { return ("Final", .secondary) }
        if game.hasKickedOff { return ("In progress", .orange) }
        return (game.kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute()), .secondary)
    }

    // MARK: Saving

    private func saveBar(_ entry: ClaimedEntry, games: [PoolGame], used: [String: Int]) -> some View {
        let canSave = EntryPickRules.canSave(
            selectedTeam: selectedTeam,
            savedTeam: savedTeam,
            games: games,
            entry: entry,
            usedTeams: used,
            week: week,
            allowKickedOff: true
        )
        return VStack(spacing: 0) {
            Divider()
            Group {
                if session.isBusy {
                    ProgressView()
                } else if let savedTeam, selectedTeam == savedTeam {
                    Label("\(NFLTeam.shortName(for: savedTeam)) saved", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button {
                        // Re-check at tap time; the rules can change under an
                        // open sheet (a listener delivers, a game kicks off).
                        guard let selectedTeam, canSave else { return }
                        save(selectedTeam, entry: entry)
                    } label: {
                        Text(EntryPickRules.saveTitle(selectedTeam: selectedTeam, savedTeam: savedTeam))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
            }
            .padding()
        }
        .background(.bar)
    }

    private func save(_ team: String, entry: ClaimedEntry) {
        Task {
            await session.submitPick(
                entryID: entry.id,
                week: week,
                team: team,
                confirmation: "Saved \(NFLTeam.shortName(for: team)) for \(entry.label) in week \(week)."
            )
            if let failure = session.errorMessage {
                errorMessage = failure
                notice = nil
            } else {
                dismiss()
            }
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        Task {
            await action()
            notice = session.notice
            errorMessage = session.errorMessage
        }
    }
}

#if DEBUG
#Preview("Correct a pick") {
    CommissionerPickSheet(session: PreviewData.commissioner(), entryID: PreviewData.will.id, week: 4)
}

#Preview("Buyback open") {
    CommissionerPickSheet(session: PreviewData.commissioner(), entryID: "pat-buyer", week: 4)
}

#Preview("Out") {
    CommissionerPickSheet(session: PreviewData.commissioner(), entryID: "jordan-out", week: 4)
}

#Preview("As a sheet") {
    Text("Commissioner tab")
        .sheet(isPresented: .constant(true)) {
            CommissionerPickSheet(session: PreviewData.commissioner(), entryID: PreviewData.casa.id, week: 4)
        }
}
#endif
