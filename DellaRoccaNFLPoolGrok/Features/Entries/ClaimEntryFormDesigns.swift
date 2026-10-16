#if DEBUG
import SwiftUI

// Design explorations for the claim form. DEBUG-only scaffolding: referenced
// solely by the previews here, never shipped. The form in use is
// ClaimEntryForm. All three keep its contract: a PIN of one letter and four
// digits from 1 to 9, uppercased and trimmed as it is typed, a claim button
// disabled until the PIN is well formed that shows progress while the callable
// runs, the notice or error beneath, and the field cleared on success.

// MARK: - Design A · Code boxes
//
// The PIN as five boxes, the way a verification code is entered: the first for
// the letter, four for the digits, each filling as it is typed and the next
// one outlined in the accent color. The field itself sits invisibly underneath
// and takes the keyboard; the boxes only show what is in it. The hint moves
// to the section footer and the button becomes a full-width prominent one.

struct ClaimEntryFormA: View {
    @Bindable var session: PlayerSession
    @Binding var pin: String
    @FocusState private var focused: Bool

    private let boxCount = 5

    var body: some View {
        Form {
            Section {
                ZStack {
                    TextField("PIN", text: $pin)
                        #if os(iOS) || os(visionOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .autocorrectionDisabled()
                        .focused($focused)
                        .opacity(0.02)
                        .onChange(of: pin) { _, newValue in
                            let cleaned = cleanedPin(newValue)
                            if cleaned != pin { pin = cleaned }
                        }
                    HStack(spacing: 10) {
                        ForEach(0..<boxCount, id: \.self) { index in
                            box(at: index)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            } header: {
                Text("Claim an entry")
            } footer: {
                Text(pinHint)
            }
            Section {
                Button {
                    claim($pin, with: session)
                } label: {
                    Group {
                        if session.isBusy {
                            ProgressView()
                        } else {
                            Text("Claim entry")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isBusy || !EntryPin.isValid(pin))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    StatusMessageText(notice: session.notice, errorMessage: session.errorMessage)
                    if session.isSignedIn {
                        Text("Signed in as \(session.accountLabel)")
                    }
                }
            }
        }
    }

    private func box(at index: Int) -> some View {
        let characters = Array(pin)
        let character = index < characters.count ? String(characters[index]) : ""
        let active = focused && index == characters.count
        // A faint "A" in the first box says that one is the letter.
        let placeholder = index == 0 ? "A" : ""
        return Text(character.isEmpty ? placeholder : character)
            .font(.system(.title2, design: .monospaced).weight(.semibold))
            .foregroundStyle(character.isEmpty ? Color.secondary.opacity(0.4) : Color.primary)
            .frame(width: 44, height: 52)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(active ? Color.accentColor : Color.clear, lineWidth: 2)
            }
    }
}

// MARK: - Design B · Welcome page
//
// Not a form: a centered page for the player's first minute in the app, with
// a title, one sentence about where the PIN comes from, a large centered
// field, and the button. The account they signed in with sits at the bottom
// as a footnote. Built for the empty tab; "Claim another entry" would still
// want something smaller.

struct ClaimEntryFormB: View {
    @Bindable var session: PlayerSession
    @Binding var pin: String

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(systemName: "football")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Enter your PIN")
                    .font(.title2.weight(.bold))
                Text("It's on your pool sheet: one letter and four digits from 1 to 9.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            TextField("PIN", text: $pin)
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.characters)
                #endif
                .autocorrectionDisabled()
                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                .onChange(of: pin) { _, newValue in
                    let cleaned = cleanedPin(newValue)
                    if cleaned != pin { pin = cleaned }
                }
            Button {
                claim($pin, with: session)
            } label: {
                Group {
                    if session.isBusy {
                        ProgressView()
                    } else {
                        Text("Claim entry")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.isBusy || !EntryPin.isValid(pin))
            VStack(spacing: 4) {
                StatusMessageText(notice: session.notice, errorMessage: session.errorMessage)
            }
            .multilineTextAlignment(.center)
            Spacer()
            Spacer()
            if session.isSignedIn {
                Text("Signed in as \(session.accountLabel)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }
}

// MARK: - Design C · One row
//
// The field and the button on one line, like an address bar: type the PIN,
// tap Claim. The hint and the account are the section footer, so the whole
// thing is a single list row and sits as easily under a player's existing
// entries as it does on an empty tab.

struct ClaimEntryFormC: View {
    @Bindable var session: PlayerSession
    @Binding var pin: String

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    TextField("PIN", text: $pin)
                        #if os(iOS) || os(visionOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                        .onChange(of: pin) { _, newValue in
                            let cleaned = cleanedPin(newValue)
                            if cleaned != pin { pin = cleaned }
                        }
                    Button {
                        claim($pin, with: session)
                    } label: {
                        if session.isBusy {
                            ProgressView()
                        } else {
                            Text("Claim")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isBusy || !EntryPin.isValid(pin))
                }
            } header: {
                Text("Claim an entry")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pinHint)
                    StatusMessageText(notice: session.notice, errorMessage: session.errorMessage)
                    if session.isSignedIn {
                        Text("Signed in as \(session.accountLabel)")
                    }
                }
            }
        }
    }
}

// MARK: - Shared

private let pinHint = "One letter and four digits from 1 to 9. Zero is not used."

/// Uppercase, no whitespace, five characters at most. Mirrors ClaimEntryForm.
private func cleanedPin(_ raw: String) -> String {
    String(raw.uppercased().filter { !$0.isWhitespace }.prefix(5))
}

/// The claim every design shares: submit, then clear the field when the
/// server did not complain.
@MainActor
private func claim(_ pin: Binding<String>, with session: PlayerSession) {
    Task {
        await session.claim(pin: pin.wrappedValue)
        if session.errorMessage == nil { pin.wrappedValue = "" }
    }
}

// MARK: - Previews

#Preview("Design A · Code boxes") {
    @Previewable @State var pin = "A12"
    ClaimEntryFormA(session: PreviewData.claim(), pin: $pin)
}

#Preview("Design B · Welcome page") {
    @Previewable @State var pin = ""
    ClaimEntryFormB(session: PreviewData.claim(), pin: $pin)
}

#Preview("Design C · One row") {
    @Previewable @State var pin = "A1234"
    ClaimEntryFormC(session: PreviewData.claim(), pin: $pin)
}

/// Every design on one shared PIN, the current form first. Swipe between
/// pages and type in any of them.
#Preview("Claim designs") {
    @Previewable @State var pin = "A12"
    let session = PreviewData.claim()
    return TabView {
        ClaimEntryForm(session: session, pin: $pin)
        ClaimEntryFormA(session: session, pin: $pin)
        ClaimEntryFormB(session: session, pin: $pin)
        ClaimEntryFormC(session: session, pin: $pin)
    }
    .tabViewStyle(.page)
}

/// The same pages after the server turned the PIN down.
#Preview("Claim designs · error") {
    @Previewable @State var pin = "A1234"
    let session = PreviewData.claim()
    session.errorMessage = "That PIN is already claimed."
    return TabView {
        ClaimEntryForm(session: session, pin: $pin)
        ClaimEntryFormA(session: session, pin: $pin)
        ClaimEntryFormB(session: session, pin: $pin)
        ClaimEntryFormC(session: session, pin: $pin)
    }
    .tabViewStyle(.page)
}
#endif
