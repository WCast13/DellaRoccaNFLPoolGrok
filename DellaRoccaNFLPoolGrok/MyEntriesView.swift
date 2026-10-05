import AuthenticationServices
import FirebaseCore
import SwiftUI

struct MyEntriesView: View {
    @State private var session: PlayerSession?

    var body: some View {
        Group {
            if let session {
                MyEntriesContent(session: session)
            } else {
                ProgressView("Opening the pool")
            }
        }
        .task {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            if session == nil {
                session = PlayerSession()
            }
        }
    }
}

private struct MyEntriesContent: View {
    @Bindable var session: PlayerSession
    @State private var pin = ""
    @State private var selectedEntryID: String?
    @State private var selectedTeam: String?

    private var selectedEntry: ClaimedEntry? {
        let id = selectedEntryID ?? session.entries.first?.id
        return session.entries.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !session.isSignedIn {
                    signedOut
                } else if session.entries.isEmpty {
                    claimForm
                } else if let entry = selectedEntry {
                    entryEditor(entry)
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
        }
        .onChange(of: session.entries.map(\.id)) { _, ids in
            if selectedEntryID == nil || !ids.contains(selectedEntryID ?? "") {
                selectedEntryID = ids.first
            }
        }
    }

    private var signedOut: some View {
        VStack(spacing: 20) {
            Text("Sign in with Apple, then enter the PIN the commissioners gave you. One account can hold more than one entry.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            SignInWithAppleButton(.signIn) { request in
                session.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await session.completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .frame(maxWidth: 375)
            statusMessages
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var claimForm: some View {
        Form {
            Section("Claim an entry") {
                Text(session.accountLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("PIN", text: $pin)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                    .autocorrectionDisabled()
                    .font(.title3.monospaced())
                    .onChange(of: pin) { _, newValue in
                        let filtered = String(newValue.uppercased().filter { !$0.isWhitespace }.prefix(5))
                        if filtered != pin { pin = filtered }
                    }
                Text("One letter and four digits from 1 to 9. Zero is not used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await session.claim(pin: pin)
                        if session.errorMessage == nil { pin = "" }
                    }
                } label: {
                    if session.isBusy {
                        ProgressView()
                    } else {
                        Text("Claim entry")
                    }
                }
                .disabled(session.isBusy || !EntryPin.isValid(pin))
            }
            messageSection
        }
    }

    private func entryEditor(_ entry: ClaimedEntry) -> some View {
        let week = session.openWeek
        let picks = session.picks(for: entry)
        return List {
            if session.entries.count > 1 {
                Picker("Entry", selection: Binding(
                    get: { entry.id },
                    set: { selectedEntryID = $0; selectedTeam = nil }
                )) {
                    ForEach(session.entries) { item in
                        Text(item.label).tag(item.id)
                    }
                }
            }
            Section {
                Text(entry.label)
                    .font(.title3.weight(.semibold))
                Text(entry.statusLine)
                    .font(.subheadline)
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
            if entry.status == .active, let week {
                Section {
                    Text("Week \(week) locks at each game's kickoff. A team can be used once all season. The spread is only a reference.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(session.games(in: week)) { game in
                        gameRow(game, entry: entry, week: week)
                    }
                }
                Section {
                    Button {
                        guard let selectedTeam else { return }
                        Task { await session.submitPick(entryID: entry.id, week: week, team: selectedTeam) }
                    } label: {
                        if session.isBusy {
                            ProgressView()
                        } else {
                            Text(saveTitle(entry: entry, week: week))
                        }
                    }
                    .disabled(session.isBusy || !canSave(entry: entry, week: week))
                }
            } else if entry.status != .active {
                Section {
                    Text("This entry cannot make a pick until a commissioner records a buyback.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            messageSection
        }
        .onAppear {
            if let week, selectedTeam == nil {
                selectedTeam = picks[week]
            }
        }
        .onChange(of: entry.id) { _, _ in
            selectedTeam = week.flatMap { picks[$0] }
        }
        .onChange(of: week.flatMap { picks[$0] }) { _, team in
            if selectedTeam == nil {
                selectedTeam = team
            }
        }
    }

    private func gameRow(_ game: PoolGame, entry: ClaimedEntry, week: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                teamButton(game.awayAbbr, game: game, entry: entry, week: week)
                Text("at")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                teamButton(game.homeAbbr, game: game, entry: entry, week: week)
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

    private func teamButton(_ abbreviation: String, game: PoolGame, entry: ClaimedEntry, week: Int) -> some View {
        let allowed = canSelect(abbreviation, game: game, entry: entry, week: week)
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
        .accessibilityLabel(teamAccessibility(abbreviation, allowed: allowed))
    }

    private func canSelect(_ abbreviation: String, game: PoolGame, entry: ClaimedEntry, week: Int) -> Bool {
        guard entry.status == .active, !game.hasKickedOff else { return false }
        guard game.homeAbbr == abbreviation || game.awayAbbr == abbreviation else { return false }
        if let usedWeek = session.usedTeams(for: entry)[abbreviation], usedWeek != week {
            return false
        }
        return true
    }

    private func canSave(entry: ClaimedEntry, week: Int) -> Bool {
        guard let selectedTeam,
              let game = session.games(in: week).first(where: {
                  $0.homeAbbr == selectedTeam || $0.awayAbbr == selectedTeam
              }) else {
            return false
        }
        return canSelect(selectedTeam, game: game, entry: entry, week: week)
    }

    private func saveTitle(entry: ClaimedEntry, week: Int) -> String {
        let current = session.picks(for: entry)[week]
        if let selectedTeam, selectedTeam != current {
            return current == nil ? "Save \(selectedTeam)" : "Change pick to \(selectedTeam)"
        }
        return "Save pick"
    }

    private func teamAccessibility(_ abbreviation: String, allowed: Bool) -> String {
        let name = NFLTeam.team(abbreviation: abbreviation)?.name ?? abbreviation
        return allowed ? name : "\(name), unavailable"
    }

    @ViewBuilder
    private var messageSection: some View {
        if session.notice != nil || session.errorMessage != nil {
            Section {
                statusMessages
            }
        }
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

private struct TeamPickChip: View {
    let abbreviation: String
    let selected: Bool
    let dimmed: Bool

    var body: some View {
        let team = NFLTeam.team(abbreviation: abbreviation)
        Text(abbreviation)
            .font(.caption.weight(.bold))
            .foregroundStyle(team?.primaryColor.foreground ?? .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(team?.primaryColor.color ?? .gray, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary, lineWidth: 2)
                }
            }
            .opacity(dimmed ? 0.4 : 1)
    }
}
