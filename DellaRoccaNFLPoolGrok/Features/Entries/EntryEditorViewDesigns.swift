#if DEBUG
import SwiftUI

// Design explorations for the player's pick editor. DEBUG-only scaffolding:
// referenced solely by the previews here, never shipped. The editor in use is
// EntryEditorView. All three keep its contract: the open week's games with a
// team selectable only when EntryPickRules allows it, the saved pick seeded
// into the selection and dropped when the week moves on, the buyback card
// while a decision is open, and the "nothing to pick" branches. They differ in
// how the slate is laid out and where the pick's standing is shown.

// MARK: - Design A · Matchup tiles, three a row
//
// The slate as a grid of matchups rather than a list of rows: two 44pt chips
// with the kickoff under them, three games across, so a full Sunday fits on
// one screen. A used team carries its week as a corner badge and a locked one
// a padlock, which replaces the reason line without losing the reason. The
// entry name is the title and the week with the pick's standing is the
// subtitle, as on the commissioner sheet. The history strip shrinks to 36pt.

struct EntryEditorViewA: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry
    @State private var selectedTeam: String?

    private var week: Int? { session.openWeek }
    private var picks: [Int: String] { session.picks(for: entry) }

    var body: some View {
        List {
            if !picks.isEmpty {
                Section {
                    PickHistoryStrip(picks: picks, logos: session.teamLogos, chipSize: 36)
                }
            }
            if entry.status == .active, let week {
                let games = session.games(in: week)
                let locked = lockedTeam(session: session, entry: entry, week: week)
                Section {
                    ForEach(Array(stride(from: 0, to: games.count, by: 3)), id: \.self) { start in
                        let end = min(start + 3, games.count)
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(games[start..<end]) { game in
                                MatchupTile(
                                    session: session,
                                    game: game,
                                    entry: entry,
                                    week: week,
                                    lockedBy: locked,
                                    selectedTeam: $selectedTeam
                                )
                            }
                            // Pad the last row so its tiles keep the width of
                            // the rows above instead of stretching to fill.
                            ForEach(0..<(start + 3 - end), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                }
            } else {
                NothingToPickSection(session: session, entry: entry)
            }
            if entry.hasOpenBuybackDecision {
                BuybackDecisionCard(session: session, entry: entry)
            }
        }
        .navigationTitle(entry.label)
        .navigationSubtitle(pickStanding(session: session, entry: entry))
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
        }
        .safeAreaInset(edge: .bottom) {
            if entry.status == .active, let week {
                EntrySaveBar(session: session, entry: entry, week: week, selectedTeam: $selectedTeam)
            }
        }
        .modifier(PickSelectionSync(session: session, entry: entry, selectedTeam: $selectedTeam))
    }
}

/// One game as a tile: away at home, kickoff, spread.
private struct MatchupTile: View {
    @Bindable var session: PlayerSession
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    let lockedBy: String?
    @Binding var selectedTeam: String?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                chip(game.awayAbbr)
                Text("@")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                chip(game.homeAbbr)
            }
            Text(shortKickoff(game))
                .font(.caption2.weight(.semibold))
            Text(game.spreadLabel ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }

    private func chip(_ abbreviation: String) -> some View {
        let used = session.usedTeams(for: entry)
        let allowed = EntryPickRules.canSelect(
            abbreviation: abbreviation, game: game, entry: entry, usedTeams: used, week: week, lockedBy: lockedBy
        )
        let reason = EntryPickRules.unavailableReason(
            abbreviation: abbreviation, game: game, usedTeams: used, week: week, lockedBy: lockedBy
        )
        // The standing pick after kickoff is "used" this week and locked; that
        // is a padlock, not a week badge.
        let usedWeek = used[abbreviation].flatMap { $0 == week ? nil : $0 }
        return Button {
            selectedTeam = abbreviation
        } label: {
            TeamPickChip(
                abbreviation: abbreviation,
                selected: selectedTeam == abbreviation,
                dimmed: !allowed && selectedTeam != abbreviation,
                logoURL: session.teamLogos[abbreviation],
                size: 44
            )
            .overlay(alignment: .topTrailing) {
                if reason != nil {
                    ReasonBadge(usedWeek: usedWeek)
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .accessibilityLabel(
            EntryPickRules.teamAccessibility(abbreviation: abbreviation, allowed: allowed, reason: reason)
        )
    }
}

/// "W2" on a team used in week 2, a padlock on a locked one.
private struct ReasonBadge: View {
    let usedWeek: Int?

    var body: some View {
        Group {
            if let usedWeek {
                Text("W\(usedWeek)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 4)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .padding(3)
            }
        }
        .frame(minHeight: 14)
        .foregroundStyle(.white)
        .background(Color.gray, in: Capsule())
    }
}

// MARK: - Design B · Grouped by kickoff
//
// Games that kick off together share a section headed by the day and time, so
// the time leaves every row and the slate reads like the TV schedule: Thursday
// night, Sunday 1:00, Sunday 4:25, Sunday night, Monday night. Each row is the
// two teams at 52pt with the spread between them and the team's name under the
// chip; a team that cannot be picked shows the reason in place of its name.
// The history becomes one footnote line of names, the smallest it can be.

struct EntryEditorViewB: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry
    @State private var selectedTeam: String?

    private var week: Int? { session.openWeek }
    private var picks: [Int: String] { session.picks(for: entry) }

    var body: some View {
        List {
            if !picks.isEmpty {
                Section {
                    Text(usedLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if entry.status == .active, let week {
                let locked = lockedTeam(session: session, entry: entry, week: week)
                ForEach(KickoffSlot.group(session.games(in: week))) { slot in
                    Section(slot.title) {
                        ForEach(slot.games) { game in
                            SlotGameRow(
                                session: session,
                                game: game,
                                entry: entry,
                                week: week,
                                lockedBy: locked,
                                selectedTeam: $selectedTeam
                            )
                        }
                    }
                }
            } else {
                NothingToPickSection(session: session, entry: entry)
            }
            if entry.hasOpenBuybackDecision {
                BuybackDecisionCard(session: session, entry: entry)
            }
        }
        .navigationTitle(entry.label)
        .navigationSubtitle(pickStanding(session: session, entry: entry))
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
        }
        .safeAreaInset(edge: .bottom) {
            if entry.status == .active, let week {
                EntrySaveBar(session: session, entry: entry, week: week, selectedTeam: $selectedTeam)
            }
        }
        .modifier(PickSelectionSync(session: session, entry: entry, selectedTeam: $selectedTeam))
    }

    /// "Used: Jaguars W1 · 49ers W2"
    private var usedLine: String {
        let names = picks.keys.sorted().compactMap { pickWeek in
            picks[pickWeek].map { "\(NFLTeam.shortName(for: $0)) W\(pickWeek)" }
        }
        return "Used: " + names.joined(separator: " · ")
    }
}

/// Games that kick off at the same local day and time.
private struct KickoffSlot: Identifiable {
    let title: String
    var games: [PoolGame]

    var id: String { title }

    /// Groups kickoff-sorted games into runs that share a kickoff.
    static func group(_ games: [PoolGame]) -> [KickoffSlot] {
        var slots: [KickoffSlot] = []
        for game in games {
            let title = game.kickoff.formatted(.dateTime.weekday(.wide).hour().minute())
            if let last = slots.indices.last, slots[last].title == title {
                slots[last].games.append(game)
            } else {
                slots.append(KickoffSlot(title: title, games: [game]))
            }
        }
        return slots
    }
}

private struct SlotGameRow: View {
    @Bindable var session: PlayerSession
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    let lockedBy: String?
    @Binding var selectedTeam: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            team(game.awayAbbr)
            VStack(spacing: 2) {
                Text("at")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(game.spreadLabel ?? " ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            team(game.homeAbbr)
        }
        .padding(.vertical, 2)
    }

    private func team(_ abbreviation: String) -> some View {
        let used = session.usedTeams(for: entry)
        let allowed = EntryPickRules.canSelect(
            abbreviation: abbreviation, game: game, entry: entry, usedTeams: used, week: week, lockedBy: lockedBy
        )
        let reason = EntryPickRules.unavailableReason(
            abbreviation: abbreviation, game: game, usedTeams: used, week: week, lockedBy: lockedBy
        )
        return VStack(spacing: 4) {
            Button {
                selectedTeam = abbreviation
            } label: {
                TeamPickChip(
                    abbreviation: abbreviation,
                    selected: selectedTeam == abbreviation,
                    dimmed: !allowed && selectedTeam != abbreviation,
                    logoURL: session.teamLogos[abbreviation],
                    size: 52
                )
            }
            .buttonStyle(.plain)
            .disabled(!allowed)
            .accessibilityLabel(
                EntryPickRules.teamAccessibility(abbreviation: abbreviation, allowed: allowed, reason: reason)
            )
            Text(reason ?? NFLTeam.shortName(for: abbreviation))
                .font(.caption2)
                .foregroundStyle(reason == nil ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 84)
    }
}

// MARK: - Design C · Pick card over slim rows
//
// The pick's standing is the first thing on the screen: a card with the chosen
// team at 56pt, its opponent and kickoff, and the save button, or "No pick
// yet" with the first kickoff while nothing is chosen. The card follows the
// selection live, so it is also the confirmation step and the bottom bar goes
// away. Under it each game is one 40pt line: the two chips, then the kickoff
// over the spread, or over the reason a team cannot be picked, on the trailing
// side. The history sits inside the card as 28pt chips.

struct EntryEditorViewC: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry
    @State private var selectedTeam: String?

    private var week: Int? { session.openWeek }
    private var picks: [Int: String] { session.picks(for: entry) }

    var body: some View {
        List {
            if entry.status == .active, let week {
                let games = session.games(in: week)
                let locked = lockedTeam(session: session, entry: entry, week: week)
                Section {
                    PickCard(session: session, entry: entry, week: week, games: games, selectedTeam: $selectedTeam)
                }
                Section("Week \(week) games") {
                    ForEach(games) { game in
                        SlimGameRow(
                            session: session,
                            game: game,
                            entry: entry,
                            week: week,
                            lockedBy: locked,
                            selectedTeam: $selectedTeam
                        )
                    }
                }
            } else {
                if !picks.isEmpty {
                    Section {
                        PickHistoryStrip(picks: picks, logos: session.teamLogos, chipSize: 36)
                    }
                }
                NothingToPickSection(session: session, entry: entry)
            }
            if entry.hasOpenBuybackDecision {
                BuybackDecisionCard(session: session, entry: entry)
            }
        }
        .navigationTitle(entry.label)
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
        }
        .modifier(PickSelectionSync(session: session, entry: entry, selectedTeam: $selectedTeam))
    }
}

/// The chosen team, what it is up against, and the save control; the history
/// as a line of small chips beneath.
private struct PickCard: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry
    let week: Int
    let games: [PoolGame]
    @Binding var selectedTeam: String?

    private var picks: [Int: String] { session.picks(for: entry) }
    private var saved: String? { picks[week] }
    private var unchanged: Bool { selectedTeam != nil && selectedTeam == saved }

    private var game: PoolGame? {
        guard let selectedTeam else { return nil }
        return games.first { $0.homeAbbr == selectedTeam || $0.awayAbbr == selectedTeam }
    }

    private var canSave: Bool {
        EntryPickRules.canSave(
            selectedTeam: selectedTeam,
            savedTeam: saved,
            games: games,
            entry: entry,
            usedTeams: session.usedTeams(for: entry),
            week: week
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let selectedTeam {
                    TeamPickChip(
                        abbreviation: selectedTeam,
                        selected: unchanged,
                        dimmed: false,
                        logoURL: session.teamLogos[selectedTeam],
                        size: 56
                    )
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.red, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Text("W\(week)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.red)
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.headline)
                        .foregroundStyle(selectedTeam == nil ? Color.red : Color.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                saveControl
            }
            let history = picks.keys.sorted().filter { $0 != week }
            if !history.isEmpty {
                HStack(spacing: 6) {
                    ForEach(history, id: \.self) { pastWeek in
                        if let team = picks[pastWeek] {
                            WeekPickChip(week: pastWeek, team: team, logoURL: session.teamLogos[team], chipSize: 28)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var headline: String {
        guard let selectedTeam else { return "No pick yet" }
        let name = NFLTeam.shortName(for: selectedTeam)
        return unchanged ? "\(name) saved" : name
    }

    private var detail: String {
        if let selectedTeam, let game {
            let home = game.homeAbbr == selectedTeam
            let opponent = NFLTeam.shortName(for: home ? game.awayAbbr : game.homeAbbr)
            return "\(home ? "vs" : "at") \(opponent) · \(shortKickoff(game))"
        }
        if let first = games.first(where: { !$0.hasKickedOff }) {
            return "Week \(week) · first kickoff \(shortKickoff(first))"
        }
        return "Week \(week)"
    }

    @ViewBuilder
    private var saveControl: some View {
        if session.isBusy {
            ProgressView()
        } else if unchanged {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityLabel("Saved")
        } else if selectedTeam != nil {
            Button(saved == nil ? "Save" : "Change") {
                // Re-validate at tap time, as the save bar does: a game can
                // kick off between render and tap.
                guard let selectedTeam, canSave else { return }
                Task { await session.submitPick(entryID: entry.id, week: week, team: selectedTeam) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }
}

private struct SlimGameRow: View {
    @Bindable var session: PlayerSession
    let game: PoolGame
    let entry: ClaimedEntry
    let week: Int
    let lockedBy: String?
    @Binding var selectedTeam: String?

    var body: some View {
        let used = session.usedTeams(for: entry)
        let reasons = [game.awayAbbr, game.homeAbbr].compactMap { abbreviation -> String? in
            let reason = EntryPickRules.unavailableReason(
                abbreviation: abbreviation, game: game, usedTeams: used, week: week, lockedBy: lockedBy
            )
            guard reason != nil else { return nil }
            let name = NFLTeam.shortName(for: abbreviation)
            if let usedWeek = used[abbreviation], usedWeek != week { return "\(name) used W\(usedWeek)" }
            return "\(name) locked"
        }
        HStack(spacing: 8) {
            chip(game.awayAbbr, used: used)
            Text("@")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            chip(game.homeAbbr, used: used)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(shortKickoff(game))
                    .font(.caption.weight(.semibold))
                Text(reasons.isEmpty ? (game.spreadLabel ?? " ") : reasons.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    private func chip(_ abbreviation: String, used: [String: Int]) -> some View {
        let allowed = EntryPickRules.canSelect(
            abbreviation: abbreviation, game: game, entry: entry, usedTeams: used, week: week, lockedBy: lockedBy
        )
        let reason = EntryPickRules.unavailableReason(
            abbreviation: abbreviation, game: game, usedTeams: used, week: week, lockedBy: lockedBy
        )
        return Button {
            selectedTeam = abbreviation
        } label: {
            TeamPickChip(
                abbreviation: abbreviation,
                selected: selectedTeam == abbreviation,
                dimmed: !allowed && selectedTeam != abbreviation,
                logoURL: session.teamLogos[abbreviation],
                size: 40
            )
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .accessibilityLabel(
            EntryPickRules.teamAccessibility(abbreviation: abbreviation, allowed: allowed, reason: reason)
        )
    }
}

// MARK: - Shared

/// "Sun 1:00 PM"
private func shortKickoff(_ game: PoolGame) -> String {
    game.kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

/// The standing pick for `week` once its game has kicked off; from then on no
/// other team may be substituted. Mirrors GamePickRow.
@MainActor
private func lockedTeam(session: PlayerSession, entry: ClaimedEntry, week: Int) -> String? {
    guard let saved = session.picks(for: entry)[week] else { return nil }
    guard EntryPickRules.standingPickHasKickedOff(
        savedTeam: saved,
        games: session.games(in: week),
        week: week
    ) else { return nil }
    return saved
}

/// "Week 4 · Lions saved", "Week 4 · No pick yet", or the status line for an
/// entry that is not picking.
@MainActor
private func pickStanding(session: PlayerSession, entry: ClaimedEntry) -> String {
    guard entry.status == .active, let week = session.openWeek else { return entry.statusLine }
    if let saved = session.picks(for: entry)[week] {
        return "Week \(week) · \(NFLTeam.shortName(for: saved)) saved"
    }
    return "Week \(week) · No pick yet"
}

/// The weeks picked so far, oldest first, as week chips.
private struct PickHistoryStrip: View {
    let picks: [Int: String]
    let logos: [String: URL]
    var chipSize: CGFloat = 36

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(picks.keys.sorted(), id: \.self) { week in
                    if let team = picks[week] {
                        WeekPickChip(week: week, team: team, logoURL: logos[team], chipSize: chipSize)
                    }
                }
            }
        }
    }
}

/// What the editor shows when there is nothing to pick: the schedule still on
/// its way, no game left this season, or an entry that is out with nothing to
/// decide. Mirrors EntryEditorView.
private struct NothingToPickSection: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry

    var body: some View {
        if entry.status == .active {
            Section {
                if session.gamesLoaded {
                    Text("No games left to pick this season.")
                } else {
                    ProgressView("Loading this week's games")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if !entry.hasOpenBuybackDecision {
            Section {
                Text(entry.statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The selection bookkeeping every editor shares, lifted from EntryEditorView:
/// seed from the saved pick when nothing is chosen, start over when the entry
/// or the open week changes, and follow a server-side change to the saved pick
/// only while the user has not chosen something else.
private struct PickSelectionSync: ViewModifier {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry
    @Binding var selectedTeam: String?

    private var week: Int? { session.openWeek }
    private var saved: String? { week.flatMap { session.picks(for: entry)[$0] } }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if selectedTeam == nil { selectedTeam = saved }
            }
            .onChange(of: entry.id) { _, _ in
                selectedTeam = saved
            }
            .onChange(of: week) { _, newWeek in
                selectedTeam = newWeek.flatMap { session.picks(for: entry)[$0] }
            }
            .onChange(of: saved) { oldSaved, newSaved in
                if selectedTeam == nil || selectedTeam == oldSaved {
                    selectedTeam = newSaved
                }
            }
    }
}

// MARK: - Previews

/// The player fixture with a fuller week 4: four more games, two sharing a
/// Sunday-afternoon kickoff and two a late one, so the grid has rows to fill
/// and the kickoff groups have more than one game each.
private enum EditorDesignData {
    static func fullSlate() -> PlayerSession {
        let base = PreviewData.games
        let afternoon = base.first { $0.id == "w4-gb" }?.kickoff ?? Date()
        let late = afternoon.addingTimeInterval(3.5 * 60 * 60)
        let extra: [PoolGame] = [
            PoolGame(id: "w4-mia", week: 4, homeAbbr: "BAL", awayAbbr: "MIA", kickoff: afternoon, status: "scheduled", spreadHome: -3.5),
            PoolGame(id: "w4-phi", week: 4, homeAbbr: "TB", awayAbbr: "PHI", kickoff: afternoon, status: "scheduled", spreadHome: 1.5),
            PoolGame(id: "w4-cin", week: 4, homeAbbr: "LAR", awayAbbr: "CIN", kickoff: late, status: "scheduled", spreadHome: -4),
            PoolGame(id: "w4-nyj", week: 4, homeAbbr: "NE", awayAbbr: "NYJ", kickoff: late, status: "scheduled", spreadHome: -2.5),
        ]
        return PlayerSession(preview: PlayerSession.PreviewSample(
            userID: "preview-user",
            accountLabel: "wcastellano13@gmail.com",
            entries: [PreviewData.will, PreviewData.casa],
            games: base + extra,
            privatePicks: PreviewData.privatePicks,
            standings: PreviewData.standings,
            standingsLoaded: true,
            teamLogos: PreviewData.logos
        ))
    }
}

#Preview("Design A · Matchup tiles") {
    NavigationStack {
        EntryEditorViewA(session: EditorDesignData.fullSlate(), entry: PreviewData.will)
    }
}

#Preview("Design B · Grouped by kickoff") {
    NavigationStack {
        EntryEditorViewB(session: EditorDesignData.fullSlate(), entry: PreviewData.will)
    }
}

#Preview("Design C · Pick card") {
    NavigationStack {
        EntryEditorViewC(session: EditorDesignData.fullSlate(), entry: PreviewData.will)
    }
}

/// Every design with a saved pick, the current editor first. Swipe between
/// pages; the selection is per page.
#Preview("Editor designs · saved pick") {
    let session = EditorDesignData.fullSlate()
    return TabView {
        NavigationStack { EntryEditorView(session: session, entry: PreviewData.casa) }
        NavigationStack { EntryEditorViewA(session: session, entry: PreviewData.casa) }
        NavigationStack { EntryEditorViewB(session: session, entry: PreviewData.casa) }
        NavigationStack { EntryEditorViewC(session: session, entry: PreviewData.casa) }
    }
    .tabViewStyle(.page)
}

/// Every design with the buyback decision open, the current editor first.
#Preview("Editor designs · buyback open") {
    let session = PreviewData.pendingBuyback()
    let entry = session.entries[0]
    return TabView {
        NavigationStack { EntryEditorView(session: session, entry: entry) }
        NavigationStack { EntryEditorViewA(session: session, entry: entry) }
        NavigationStack { EntryEditorViewB(session: session, entry: entry) }
        NavigationStack { EntryEditorViewC(session: session, entry: entry) }
    }
    .tabViewStyle(.page)
}
#endif
