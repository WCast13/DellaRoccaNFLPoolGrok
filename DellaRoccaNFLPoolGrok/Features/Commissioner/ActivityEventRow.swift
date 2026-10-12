import SwiftUI

/// One line of the commissioner activity log: a glyph for the kind of event,
/// the summary the backend wrote, and who did it with how long ago.
struct ActivityEventRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary)
                    .font(.subheadline)
                Text("\(event.actorLine) · \(event.at.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Outcome first, then category: a failure or a knockout reads as such
    /// whatever bucket it sits in.
    private var symbol: String {
        switch event.type {
        case "system.syncFailed": return "exclamationmark.triangle.fill"
        case "buyback.lapsed", "entry.eliminated", "buyback.declined": return "xmark.circle"
        case "buyback.confirmed", "buyback.recorded", "buyback.feePaid": return "checkmark.circle"
        case "entry.knockedOut": return "flag.fill"
        default:
            switch event.category {
            case .picks: return "square.and.pencil"
            case .logins: return "person.crop.circle"
            case .buybacks: return "arrow.uturn.backward.circle"
            case .system: return "gearshape"
            }
        }
    }

    private var tint: Color {
        switch event.type {
        case "system.syncFailed", "buyback.lapsed", "entry.eliminated", "buyback.declined": return .red
        case "buyback.confirmed", "buyback.recorded", "buyback.feePaid": return .green
        case "entry.knockedOut": return .orange
        default:
            switch event.category {
            case .picks: return .accentColor
            case .buybacks: return .orange
            case .logins, .system: return .secondary
            }
        }
    }
}

#if DEBUG
#Preview("Rows") {
    List {
        ForEach(PreviewData.activity) { event in
            ActivityEventRow(event: event)
        }
    }
}
#endif
