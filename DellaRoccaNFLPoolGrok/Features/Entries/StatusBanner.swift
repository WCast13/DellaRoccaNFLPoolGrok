import SwiftUI

/// The bare notice/error text lines, with no surrounding chrome, so they can
/// drop into any container (a banner, a `List`/`Form` `Section`, etc.).
struct StatusMessageText: View {
    let notice: String?
    let errorMessage: String?

    var body: some View {
        if let notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

struct StatusBanner: View {
    let notice: String?
    let errorMessage: String?

    var body: some View {
        if notice != nil || errorMessage != nil {
            VStack(alignment: .leading, spacing: 4) {
                StatusMessageText(notice: notice, errorMessage: errorMessage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

#if DEBUG
#Preview("Notice") {
    StatusBanner(notice: "Week 4 pick saved. You can change it until kickoff.", errorMessage: nil)
}

#Preview("Error") {
    StatusBanner(notice: nil, errorMessage: "That PIN is already claimed.")
}
#endif
