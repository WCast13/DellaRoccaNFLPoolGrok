import SwiftUI

struct CommissionerContent: View {
    @Bindable var session: PlayerSession
    @State private var query = ""
    @State private var week = 1
    @State private var didInitWeek = false
    @State private var showCloseWeek = false
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
            .toolbar {
                if session.isAdmin {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Close week \(week)…", systemImage: "flag.checkered") {
                                showCloseWeek = true
                            }
                            if let openWeek = session.openWeek, openWeek != week {
                                Button("Go to open week \(openWeek)", systemImage: "arrow.uturn.forward") {
                                    week = openWeek
                                }
                            }
                        } label: {
                            Label("Week actions", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
//            .sheet(isPresented: $showCloseWeek) {
//                CloseWeekSheet(session: session, week: week)
//            }
        }
        .onAppear {
            initializeWeek()
        }
        .onChange(of: session.openWeek) { _, _ in
            initializeWeek()
        }
    }

    /// Start on the open week, falling back to the latest scheduled week. Keeps
    /// resolving as games load in late, but never overrides a manual change.
    private func initializeWeek() {
        guard !didInitWeek else { return }
        if let openWeek = session.openWeek {
            week = openWeek
            didInitWeek = true
        } else if let maxWeek = session.games.map(\.week).max() {
            week = maxWeek
            didInitWeek = true
        }
    }

    private var roster: some View {
        List {
            Section {
                CommissionerWeekHeader(
                    week: $week,
                    scheduledWeeks: scheduledWeeks,
                    openWeek: session.openWeek
                )
                WeekGamesGrid(games: session.games(in: week))
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            // The season so far, entries down and weeks across. Honors the
            // search field so a name filters the board rather than replacing it.
            Section {
                CommissionerEntriesGrid(
                    session: session,
                    entries: filtered,
                    throughWeek: week
                )
            } header: {
                Text(trimmedQuery.isEmpty ? "Picks through week \(week)" : "Matching entries")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

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
    }

    private var scheduledWeeks: [Int] {
        Array(Set(session.games.map(\.week))).sorted()
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
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

