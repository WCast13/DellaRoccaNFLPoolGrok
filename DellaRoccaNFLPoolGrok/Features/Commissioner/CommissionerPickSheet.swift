import SwiftUI

/// The popup behind an entry's name on the commissioner grid: enter or correct
/// that entry's pick for the week the tab is showing.
///
/// It is deliberately spare. The entry's name is the title, one subtitle line
/// carries the week and the pick's standing ("Week 4 · Lions saved"), and the
/// body is the week's teams as a grid of logo chips (`CommissionerPickTeamGrid`)
/// and nothing else. Tapping a team hands the save to `session.enqueuePick`
/// and closes the sheet at once, so the next entry can be opened while the
/// callable runs; the grid cell behind shows the new team immediately, and
/// `PickSaveQueueBar` on the tab reports the saves in flight and any that
/// fail. Commissioners may change a pick after kickoff, and the sheet does not
/// ask first; the server allows it for admins.
///
/// The buyback overrides and the fee live here too, one row each, since this
/// is the only place a commissioner acts on one entry.
struct CommissionerPickSheet: View {
    @Bindable var session: PlayerSession
    let entryID: String
    let week: Int

    @Environment(\.dismiss) private var dismiss
    /// Feedback from the buyback and fee actions taken in this sheet.
    /// Snapshotted from the session after each call so an earlier, unrelated
    /// status never shows here.
    @State private var notice: String?
    @State private var errorMessage: String?

    /// Read live from the roster so a recorded buyback shows here without
    /// closing the sheet.
    private var entry: ClaimedEntry? {
        session.roster.first { $0.id == entryID }
    }

    /// What stands for the week, including a pick still in the queue.
    private var savedTeam: String? {
        entry.flatMap { session.picks(for: $0)[week] }
    }

    /// This entry's save for the week still waiting, in flight, or failed.
    private var pendingSave: PendingPickSave? {
        session.pendingPickSave(entryID: entryID, week: week)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    content(entry)
                        .navigationSubtitle(subtitle(entry))
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
    }

    private func content(_ entry: ClaimedEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if entry.buybackUnpaid {
                    feeRow(entry)
                }
                if entry.status == .pendingBuyback {
                    buybackRow(entry)
                }
                CommissionerPickTeamGrid(slate: slate(entry))
                StatusMessageText(notice: notice, errorMessage: errorMessage ?? pendingSave?.failure)
            }
            .padding()
        }
    }

    private func slate(_ entry: ClaimedEntry) -> CommissionerPickSlate {
        CommissionerPickSlate(
            week: week,
            entry: entry,
            games: session.games(in: week),
            used: session.usedTeams(for: entry),
            savedTeam: savedTeam,
            pendingTeam: pendingSave.flatMap { $0.isFailed ? nil : $0.team },
            logos: session.teamLogos
        ) { choice in
            pick(choice)
        }
    }

    // MARK: Chrome

    /// One line for the navigation bar: the week, anything unusual about the
    /// entry, and what stands for the week.
    private func subtitle(_ entry: ClaimedEntry) -> String {
        var parts = ["Week \(week)"]
        if entry.status != .active {
            parts.append(entry.statusLine)
        } else {
            if !entry.isClaimed {
                parts.append("No login")
            }
            if let pendingSave, !pendingSave.isFailed {
                parts.append("Saving \(NFLTeam.shortName(for: pendingSave.team))…")
            } else if let savedTeam {
                parts.append("\(NFLTeam.shortName(for: savedTeam)) saved")
            } else {
                parts.append("No pick yet")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func feeRow(_ entry: ClaimedEntry) -> some View {
        HStack {
            Text("Owes the buyback fee")
                .font(.footnote.weight(.semibold))
            Spacer()
            Button("Mark paid") {
                run { await session.markBuybackPaid(entryID: entry.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(session.isBusy)
        }
    }

    /// The state, the player's election when there is one, and the two
    /// choices. Both act at once; the result shows in the row and the subtitle.
    private func buybackRow(_ entry: ClaimedEntry) -> some View {
        HStack {
            Text(buybackLine(entry))
                .font(.footnote.weight(.semibold))
            Spacer()
            Button("Record") {
                run { await session.recordBuyback(entryID: entry.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Decline", role: .destructive) {
                run { await session.declineBuyback(entryID: entry.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .disabled(session.isBusy)
    }

    private func buybackLine(_ entry: ClaimedEntry) -> String {
        switch entry.buybackElection {
        case .buyIn: return "Buyback open · elected in"
        case .stayOut: return "Buyback open · elected out"
        case nil: return "Buyback open"
        }
    }

    // MARK: Saving

    /// A tap on a team: queues the save and closes. The rules are re-checked
    /// here rather than trusted from the chip, since they can change under an
    /// open sheet (a listener delivers, a game kicks off), and the entry is
    /// re-read from the roster for the same reason.
    private func pick(_ choice: CommissionerPickChoice) {
        guard let entry else { return }
        guard EntryPickRules.canSave(
            selectedTeam: choice.team,
            savedTeam: savedTeam,
            games: session.games(in: week),
            entry: entry,
            usedTeams: session.usedTeams(for: entry),
            week: week,
            allowKickedOff: true
        ) else { return }
        save(choice.team, entry: entry)
    }

    /// Hands the pick to the session's queue and closes. The grid cell behind
    /// the sheet shows the team at once; the tab's queue bar reports the rest.
    private func save(_ team: String, entry: ClaimedEntry) {
        session.enqueuePick(entryID: entry.id, entryLabel: entry.label, week: week, team: team)
        dismiss()
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

#Preview("Saved pick") {
    CommissionerPickSheet(session: PreviewData.commissioner(), entryID: PreviewData.casa.id, week: 4)
}

#Preview("After kickoff") {
    CommissionerPickSheet(session: PreviewData.commissioner(), entryID: "chris-early", week: 4)
}

#Preview("Buyback open") {
    CommissionerPickSheet(session: PreviewData.commissioner(), entryID: "pat-buyer", week: 4)
}

#Preview("Out") {
    CommissionerPickSheet(session: PreviewData.commissioner(), entryID: "jordan-out", week: 4)
}

#Preview("Save failed") {
    CommissionerPickSheet(session: PreviewData.commissionerSaving(), entryID: PreviewData.will.id, week: 4)
}

#Preview("As a sheet") {
    Text("Commissioner tab")
        .sheet(isPresented: .constant(true)) {
            CommissionerPickSheet(session: PreviewData.commissioner(), entryID: PreviewData.casa.id, week: 4)
        }
}
#endif
