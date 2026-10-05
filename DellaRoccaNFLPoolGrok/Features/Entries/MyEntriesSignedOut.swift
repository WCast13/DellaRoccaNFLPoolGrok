import AuthenticationServices
import SwiftUI

struct MyEntriesSignedOut: View {
    @Bindable var session: PlayerSession

    var body: some View {
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
}
