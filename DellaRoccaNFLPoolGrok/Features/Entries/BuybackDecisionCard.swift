import SwiftUI

/// The player's own buyback decision after a knockout in weeks 1-6.
///
/// Electing in makes the entry active right away so it can pick. The buyback is
/// only confirmed by that pick: miss the deadline without one and the entry is
/// out, owing nothing. The choice stays changeable until the deadline, which is
/// the player's own pick's kickoff once they have committed to a team, and the
/// last kickoff of the week they owe a pick for before that.
struct BuybackDecisionCard: View {
    @Bindable var session: PlayerSession
    let entry: ClaimedEntry

    @State private var confirmStayOut = false

    private var pickWeek: Int? { entry.buybackPickWeek }
    private var electedIn: Bool { entry.buybackElection == .buyIn }

    /// Kickoff of the entry's own pick for the decision week if it has one,
    /// otherwise the last kickoff of that week. Mirrors the server.
    private var deadline: Date? {
        guard let pickWeek else { return nil }
        let games = session.games(in: pickWeek)
        guard !games.isEmpty else { return nil }
        if let team = session.picks(for: entry)[pickWeek],
           let own = games.first(where: { $0.homeAbbr == team || $0.awayAbbr == team }) {
            return own.kickoff
        }
        return games.map(\.kickoff).max()
    }

    private var deadlinePassed: Bool {
        guard let deadline else { return false }
        return deadline <= Date()
    }

    var body: some View {
        if let pickWeek, let eliminatedWeek = entry.eliminatedWeek {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(headline(eliminatedWeek: eliminatedWeek))
                        .font(.headline)
                    Text(explanation(pickWeek: pickWeek))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let deadline {
                        Label(
                            deadlinePassed
                                ? "The deadline has passed."
                                : "Decide by \(deadline.formatted(date: .abbreviated, time: .shortened))",
                            systemImage: deadlinePassed ? "clock.badge.xmark" : "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(deadlinePassed ? .red : .secondary)
                    }
                    if entry.buybackUnpaid {
                        Label("Buyback fee not yet paid", systemImage: "dollarsign.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !deadlinePassed {
                        buttons(pickWeek: pickWeek)
                    }
                }
                .padding(.vertical, 4)
            }
            .confirmationDialog(
                "Stay eliminated?",
                isPresented: $confirmStayOut,
                titleVisibility: .visible
            ) {
                Button("Stay eliminated", role: .destructive) {
                    Task { await session.electBuyback(entryID: entry.id, buyBackIn: false) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your week \(pickWeek) pick is withdrawn and you owe nothing. You can still change back until the deadline.")
            }
        }
    }

    @ViewBuilder
    private func buttons(pickWeek: Int) -> some View {
        if session.isBusy {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if electedIn {
            Button("I've changed my mind — stay eliminated", role: .destructive) {
                confirmStayOut = true
            }
            .font(.subheadline)
        } else {
            Button("Buy back in") {
                Task { await session.electBuyback(entryID: entry.id, buyBackIn: true) }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            if entry.buybackElection == nil {
                Button("Stay eliminated", role: .destructive) {
                    confirmStayOut = true
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func headline(eliminatedWeek: Int) -> String {
        if electedIn { return "You're back in after week \(eliminatedWeek)" }
        if entry.buybackElection == .stayOut { return "Staying eliminated after week \(eliminatedWeek)" }
        return "You lost week \(eliminatedWeek)"
    }

    private func explanation(pickWeek: Int) -> String {
        if electedIn {
            return "Make your week \(pickWeek) pick to lock the buyback in. No pick by the deadline and you're out for the season — you won't owe the fee. Teams you've already used stay used."
        }
        if entry.buybackElection == .stayOut {
            return "You're out unless you change your mind before the deadline. Buying back in means making a week \(pickWeek) pick and paying the fee."
        }
        return "A loss in weeks 1 through 6 can be bought back. Buy back in and make a week \(pickWeek) pick to stay alive — teams you've already used stay used. Do nothing and you're out for the season."
    }
}

#if DEBUG
#Preview("Undecided") {
    let session = PreviewData.pendingBuyback()
    return List {
        BuybackDecisionCard(session: session, entry: session.entries[0])
    }
}

#Preview("Elected in") {
    let session = PreviewData.boughtBackUnpaid()
    return List {
        BuybackDecisionCard(session: session, entry: session.entries[0])
    }
}
#endif
