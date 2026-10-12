import AuthenticationServices
import SwiftUI

/// The whole app while signed out: ContentView shows this instead of the
/// tabs until Firebase reports a user. Apple and Google up top, then email or
/// phone underneath a segmented switch. Every path lands in the same place,
/// My Entries with the PIN form, once sign-in completes.
struct LoginView: View {
    @Bindable var session: PlayerSession
    @Environment(\.colorScheme) private var colorScheme

    private enum Method: String, CaseIterable, Identifiable {
        case email, phone

        var id: Self { self }

        var title: String {
            switch self {
            case .email: return "Email"
            case .phone: return "Phone"
            }
        }
    }

    private enum Field: Hashable {
        case email, password, phone, code
    }

    @State private var method: Method = .email
    @State private var email = ""
    @State private var password = ""
    @State private var creatingAccount = false
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                SignInWithAppleButton(.signIn) { request in
                    session.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await session.completeAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 48)
                .disabled(session.isAuthenticating)

                Button {
                    Task { await session.signInWithGoogle() }
                } label: {
                    Text("Continue with Google")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.bordered)
                .disabled(session.isAuthenticating)

                HStack(spacing: 10) {
                    Rectangle().fill(.quaternary).frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle().fill(.quaternary).frame(height: 1)
                }

                Picker("Sign-in method", selection: $method) {
                    ForEach(Method.allCases) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch method {
                case .email: emailForm
                case .phone: phoneForm
                }

                StatusBanner(notice: session.notice, errorMessage: session.errorMessage)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("Then enter the PIN the commissioners gave you. One account can hold more than one entry.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .padding(.top, 24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .overlay {
            if session.isAuthenticating {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onChange(of: method) { _, _ in
            focus = nil
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "football.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("BHF Survivor Pool")
                .font(.title2.weight(.bold))
            Text("Sign in to claim your entries and make picks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: Email

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }
            SecureField(creatingAccount ? "Choose a password (6+ characters)" : "Password", text: $password)
                .textContentType(creatingAccount ? .newPassword : .password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(submitEmail)
            Button(action: submitEmail) {
                Text(creatingAccount ? "Create account" : "Sign in")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.isAuthenticating)
            HStack {
                Button(creatingAccount ? "Have an account? Sign in" : "New here? Create an account") {
                    creatingAccount.toggle()
                }
                Spacer()
                if !creatingAccount {
                    Button("Forgot password?") {
                        Task { await session.sendPasswordReset(email: email) }
                    }
                }
            }
            .font(.footnote)
            .disabled(session.isAuthenticating)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func submitEmail() {
        focus = nil
        Task {
            if creatingAccount {
                await session.createAccount(email: email, password: password)
            } else {
                await session.signIn(email: email, password: password)
            }
        }
    }

    // MARK: Phone

    @ViewBuilder
    private var phoneForm: some View {
        VStack(spacing: 12) {
            if codeSent {
                Text("Enter the code we texted to \(PlayerSession.e164(phone) ?? phone).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("6-digit code", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .code)
                Button {
                    focus = nil
                    Task { await session.confirmPhoneCode(code) }
                } label: {
                    Text("Verify")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.isAuthenticating)
                HStack {
                    Button("Use a different number") {
                        codeSent = false
                        code = ""
                        focus = .phone
                    }
                    Spacer()
                    Button("Send it again") {
                        Task { codeSent = await session.startPhoneSignIn(phoneNumber: phone) }
                    }
                }
                .font(.footnote)
                .disabled(session.isAuthenticating)
            } else {
                TextField("Phone number", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused($focus, equals: .phone)
                Button {
                    focus = nil
                    Task {
                        codeSent = await session.startPhoneSignIn(phoneNumber: phone)
                        if codeSent { focus = .code }
                    }
                } label: {
                    Text("Text me a code")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.isAuthenticating)
                Text("US numbers can skip the +1. Standard messaging rates may apply.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

#if DEBUG
#Preview("Login") {
    LoginView(session: PreviewData.signedOut())
}

#Preview("Login · error") {
    let session = PlayerSession(preview: PlayerSession.PreviewSample(
        errorMessage: "The password is invalid or the user does not have a password."
    ))
    return LoginView(session: session)
}
#endif
