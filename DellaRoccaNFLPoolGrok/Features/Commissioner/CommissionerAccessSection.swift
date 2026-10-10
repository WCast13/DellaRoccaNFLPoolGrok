import SwiftUI

/// Who can use the commissioner tools, with add and remove. Access is the
/// email on the Apple ID; the server grants the admin claim on sign-in when
/// the email is allowed and revokes it when it is not.
struct CommissionerAccessSection: View {
    @Bindable var session: PlayerSession
    @State private var newEmail = ""
    @State private var pendingRemoval: CommissionerAccess?
    @State private var confirmRemoval = false

    var body: some View {
        Section {
            if !session.commissionersLoaded {
                ProgressView("Loading")
            } else {
                ForEach(session.commissioners) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.email)
                            Text(status(row))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.builtIn {
                            Text("Built in")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        } else {
                            Button("Remove", role: .destructive) {
                                pendingRemoval = row
                                confirmRemoval = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.isBusy)
                        }
                    }
                }
            }
            TextField("Apple ID email", text: $newEmail)
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .autocorrectionDisabled()
            Button("Allow this email") {
                Task {
                    await session.addCommissionerEmail(newEmail)
                    if session.errorMessage == nil { newEmail = "" }
                }
            }
            .disabled(session.isBusy || !newEmail.contains("@"))
        } header: {
            Text("Commissioners")
        } footer: {
            Text("Access follows the email on the Apple ID. Removing someone takes effect the next time their app refreshes its sign-in, within an hour.")
        }
        .task { await session.loadCommissioners() }
        .confirmationDialog(
            "Remove \(pendingRemoval?.email ?? "this commissioner")?",
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove commissioner", role: .destructive) {
                if let row = pendingRemoval {
                    Task { await session.removeCommissionerEmail(row.email) }
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(removalMessage)
        }
    }

    private func status(_ row: CommissionerAccess) -> String {
        if !row.signedIn { return "Has not signed in yet" }
        return row.hasClaim ? "Commissioner" : "Signed in · access applies on next refresh"
    }

    private var removalMessage: String {
        let mine = pendingRemoval?.email.lowercased() == session.accountLabel.lowercased()
        return mine
            ? "This is your own account. You will lose the commissioner tools."
            : "They lose the commissioner tools the next time their app refreshes its sign-in."
    }
}

#if DEBUG
#Preview("Commissioners") {
    List {
        CommissionerAccessSection(session: PreviewData.commissioner())
    }
}
#endif
