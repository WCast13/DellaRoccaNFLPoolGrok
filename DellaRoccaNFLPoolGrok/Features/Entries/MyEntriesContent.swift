import AuthenticationServices
import SwiftUI

struct MyEntriesContent: View {
    @Bindable var session: PlayerSession
    var previewEntryID: String?
    @State private var pin = ""
    @State private var claiming = false
    @State private var selectedTeam: String?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !session.isSignedIn {
                    signedOut
                } else if session.entries.isEmpty {
                    claimForm
                } else {
                    entryList
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
                    entryEditor(entry)
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
                claimForm
                    .navigationTitle("Claim an entry")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { claiming = false }
                        }
                    }
            }
        }
    }

    private var entryList: some View {
        List {
            Section {
                ForEach(session.entries) { entry in
                    NavigationLink(value: entry.id) {
                        entrySummary(entry)
                    }
                }
            }
            Section {
                Button("Claim another entry") { claiming = true }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
        }
    }

    private func entrySummary(_ entry: ClaimedEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.label)
                .font(.body.weight(.semibold))
            Text(entry.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.status == .active, let week = session.openWeek {
                if let team = session.picks(for: entry)[week] {
                    Text("Week \(week): \(NFLTeam.shortName(for: team))")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Week \(week): No pick")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
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
            StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var claimForm: some View {
        Form {
            Section("Claim an entry") {
                if session.isSignedIn {
                    Text(session.accountLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
            if session.notice != nil || session.errorMessage != nil {
                Section {
                    StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
                }
            }
        }
    }

    private func entryEditor(_ entry: ClaimedEntry) -> some View {
        let week = session.openWeek
        let picks = session.picks(for: entry)
        return List {
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
            if entry.status == .active, let week {
                Section {
                    Text("Week \(week) locks at each game's kickoff. A team can be used once all season. The spread is only a reference.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(session.games(in: week)) { game in
                        gameRow(game, entry: entry, week: week)
                    }
                }
            } else if entry.status != .active {
                Section {
                    Text("This entry cannot make a pick until a commissioner records a buyback.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
        }
        .safeAreaInset(edge: .bottom) {
            if entry.status == .active, let week {
                saveBar(entry: entry, week: week, picks: picks)
            }
        }
        .navigationTitle(entry.label)
        .onAppear {
            selectedTeam = week.flatMap { picks[$0] }
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

    private func saveBar(entry: ClaimedEntry, week: Int, picks: [Int: String]) -> some View {
        let saved = picks[week]
        let unchanged = selectedTeam != nil && selectedTeam == saved
        return VStack(spacing: 0) {
            Divider()
            Group {
                if session.isBusy {
                    ProgressView()
                } else if unchanged, let saved {
                    Label("\(NFLTeam.shortName(for: saved)) saved", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button {
                        guard let selectedTeam else { return }
                        Task { await session.submitPick(entryID: entry.id, week: week, team: selectedTeam) }
                    } label: {
                        Text(saveTitle(saved: saved))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave(entry: entry, week: week))
                }
            }
            .padding()
        }
        .background(.bar)
    }

    private func gameRow(_ game: PoolGame, entry: ClaimedEntry, week: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                teamButton(game.awayAbbr, game: game, entry: entry, week: week)
                Text("at")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 22)
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
        let reason = unavailableReason(abbreviation, game: game, entry: entry, week: week)
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
            .accessibilityLabel(teamAccessibility(abbreviation, allowed: allowed, reason: reason))
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

    private func unavailableReason(_ abbreviation: String, game: PoolGame, entry: ClaimedEntry, week: Int) -> String? {
        if let usedWeek = session.usedTeams(for: entry)[abbreviation], usedWeek != week {
            return "Used in week \(usedWeek)"
        }
        if game.hasKickedOff {
            return "Locked"
        }
        return nil
    }

    private func canSelect(_ abbreviation: String, game: PoolGame, entry: ClaimedEntry, week: Int) -> Bool {
        guard entry.status == .active else { return false }
        guard game.homeAbbr == abbreviation || game.awayAbbr == abbreviation else { return false }
        return unavailableReason(abbreviation, game: game, entry: entry, week: week) == nil
    }

    private func canSave(entry: ClaimedEntry, week: Int) -> Bool {
        guard let selectedTeam,
              selectedTeam != session.picks(for: entry)[week],
              let game = session.games(in: week).first(where: {
                  $0.homeAbbr == selectedTeam || $0.awayAbbr == selectedTeam
              }) else {
            return false
        }
        return canSelect(selectedTeam, game: game, entry: entry, week: week)
    }

    private func saveTitle(saved: String?) -> String {
        guard let selectedTeam else { return "Save pick" }
        let name = NFLTeam.shortName(for: selectedTeam)
        if saved == nil { return "Save \(name)" }
        if selectedTeam != saved { return "Change pick to \(name)" }
        return "\(name) saved"
    }

    private func teamAccessibility(_ abbreviation: String, allowed: Bool, reason: String?) -> String {
        let name = NFLTeam.team(abbreviation: abbreviation)?.name ?? abbreviation
        if let reason { return "\(name), \(reason)" }
        return allowed ? name : "\(name), unavailable"
    }
}
