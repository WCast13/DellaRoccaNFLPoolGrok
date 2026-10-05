import SwiftUI

struct ClaimEntryForm: View {
    @Bindable var session: PlayerSession
    @Binding var pin: String

    var body: some View {
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
}

#if DEBUG
#Preview("Empty PIN") {
    @Previewable @State var pin = ""
    ClaimEntryForm(session: PreviewData.claim(), pin: $pin)
}

#Preview("PIN entered") {
    @Previewable @State var pin = "A1234"
    ClaimEntryForm(session: PreviewData.claim(), pin: $pin)
}
#endif
