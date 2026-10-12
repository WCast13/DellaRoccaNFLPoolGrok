import SwiftUI

/// The full commissioner activity log: every pick, sign-in, buyback step, and
/// sync run the backend wrote, newest first, grouped by day. A segmented
/// filter narrows to one kind, and search matches the entry, the email, or any
/// text in the summary, so "everything about Will Castellano" is one query.
struct CommissionerLogView: View {
    @Bindable var session: PlayerSession
    @State private var filter: Filter = .all
    @State private var query = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all, picks, logins, buybacks, system

        var id: Self { self }

        var title: String {
            switch self {
            case .all: return "All"
            case .picks: return "Picks"
            case .logins: return "Logins"
            case .buybacks: return "Buybacks"
            case .system: return "System"
            }
        }

        func matches(_ event: ActivityEvent) -> Bool {
            switch self {
            case .all: return true
            case .picks: return event.category == .picks
            case .logins: return event.category == .logins
            case .buybacks: return event.category == .buybacks
            case .system: return event.category == .system
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var events: [ActivityEvent] {
        let kind = session.activityLog.filter(filter.matches)
        guard !trimmedQuery.isEmpty else { return kind }
        return kind.filter { event in
            event.summary.localizedStandardContains(trimmedQuery)
                || (event.entryLabel?.localizedStandardContains(trimmedQuery) ?? false)
                || (event.actorEmail?.localizedStandardContains(trimmedQuery) ?? false)
        }
    }

    /// Newest day first; the events inside keep their newest-first order.
    private var days: [(day: Date, events: [ActivityEvent])] {
        let grouped = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.at) }
        return grouped.keys.sorted(by: >).map { day in
            (day: day, events: grouped[day] ?? [])
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if !session.activityLogLoaded {
                Section {
                    Text("Loading activity…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if events.isEmpty {
                Section {
                    Text(emptyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(days, id: \.day) { group in
                    Section {
                        ForEach(group.events) { event in
                            ActivityEventRow(event: event)
                        }
                    } header: {
                        Text(dayTitle(group.day))
                    }
                }
                if session.activityLog.count >= 300 {
                    Section {
                        Text("Showing the newest 300 events.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $query, prompt: "Entry, email, or text")
    }

    private var emptyMessage: String {
        let kind = filter == .all ? "events" : "\(filter.title.lowercased()) events"
        if trimmedQuery.isEmpty { return "No \(kind) logged yet." }
        return "No \(kind) match “\(trimmedQuery)”."
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

#if DEBUG
#Preview("Activity log") {
    NavigationStack {
        CommissionerLogView(session: PreviewData.commissioner())
    }
}

#Preview("Empty") {
    let session = PlayerSession(preview: PlayerSession.PreviewSample(
        userID: "preview-commissioner",
        accountLabel: "wcastellano13@gmail.com",
        isAdmin: true
    ))
    return NavigationStack {
        CommissionerLogView(session: session)
    }
}
#endif
