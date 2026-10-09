import SwiftUI

struct CommissionerContent: View {
    @Bindable var session: PlayerSession
    @State private var query = ""
    @State private var week = 4
    @State private var preview: CloseWeekReport?
    @State private var confirmClose = false
    @State private var commissionerEmail = ""
    @State private var showNoLogin = false

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

            if trimmedQuery.isEmpty {
                queueSection(
                    "No pick yet",
                    rows: missingPicks,
                    empty: session.openWeek.map { "Every alive entry has a week \($0) pick." }
                        ?? "No week is open for picks.",
                    checking: !session.privatePicksReady
                )
                queueSection(
                    "Waiting on a buyback",
                    rows: buybackEntries,
                    empty: "Nobody is waiting on a buyback."
                )
                Section {
                    if showNoLogin {
                        if noLogin.isEmpty {
                            Text("Every entry has a login.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(noLogin) { entry in
                                entryLink(entry)
                            }
                        }
                    }
                } header: {
                    Button {
                        showNoLogin.toggle()
                    } label: {
                        HStack {
                            Text("No login (\(noLogin.count))")
                            Spacer()
                            Image(systemName: showNoLogin ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Section("Matching entries") {
                    if filtered.isEmpty {
                        Text("No entry matches that name.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { entry in
                            entryLink(entry)
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

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var missingPicks: [ClaimedEntry] {
        session.roster.filter { entry in
            guard entry.status == .active, let openWeek = session.openWeek else { return false }
            return session.picks(for: entry)[openWeek] == nil
        }
    }

    private var buybackEntries: [ClaimedEntry] {
        session.roster.filter { $0.status == .pendingBuyback }
    }

    private var noLogin: [ClaimedEntry] {
        session.roster.filter { !$0.isClaimed }
    }

    @ViewBuilder
    private func queueSection(_ title: String, rows: [ClaimedEntry], empty: String, checking: Bool = false) -> some View {
        Section {
            if checking {
                ProgressView("Checking picks")
            } else if rows.isEmpty {
                Text(empty)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { entry in
                    entryLink(entry)
                }
            }
        } header: {
            Text(checking ? title : "\(title) (\(rows.count))")
        }
    }

    private func entryLink(_ entry: ClaimedEntry) -> some View {
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

    private func entrySubtitle(_ entry: ClaimedEntry) -> String {
        var parts = [entry.statusLine, entry.isClaimed ? "Has a login" : "No login"]
        if entry.status == .active, let openWeek = session.openWeek {
            if let team = session.picks(for: entry)[openWeek] {
                parts.append(NFLTeam.shortName(for: team))
            } else {
                parts.append("No pick")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusMessages: some View {
        StatusMessageText(notice: session.notice, errorMessage: session.errorMessage)
    }
}
