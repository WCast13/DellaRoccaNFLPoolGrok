import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation
import Security

struct PoolGame: Identifiable, Hashable, Sendable {
    var id: String
    var week: Int
    var homeAbbr: String
    var awayAbbr: String
    var kickoff: Date
    var status: String
    var spreadHome: Double?

    var hasKickedOff: Bool { kickoff <= Date() }

    var spreadLabel: String? {
        guard let spreadHome else { return nil }
        let rounded = (spreadHome * 2).rounded() / 2
        let text = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%+.0f", rounded)
            : String(format: "%+.1f", rounded)
        return "\(homeAbbr) \(text)"
    }
}

struct CloseWeekReport: Hashable, Sendable {
    var week: Int
    var missingPicks: Int
    var losses: Int
    var wins: Int
    var ungraded: Int
    var updated: Int
    var applied: Bool
    var examples: [String]
}

struct ClaimedEntry: Identifiable, Hashable, Sendable {
    var id: String
    var label: String
    var status: EntryStatus
    var eliminatedWeek: Int?
    var buybackDeclined: Bool
    var picks: [Int: String]
    var usedTeams: [String: Int]
    var buybackWeeks: [Int]
    var isClaimed: Bool

    var canBuyBack: Bool {
        status == .pendingBuyback
            && !buybackDeclined
            && (eliminatedWeek ?? 7) <= 6
    }

    /// Bought-back weeks and the week that currently has this entry out.
    func resultLabel(for week: Int) -> String? {
        if buybackWeeks.contains(week) { return "Bought back" }
        if status != .active, eliminatedWeek == week { return "Loss" }
        return nil
    }

    var statusLine: String {
        switch status {
        case .active:
            return "Alive"
        case .pendingBuyback:
            if let eliminatedWeek {
                return "Lost week \(eliminatedWeek) · can buy back"
            }
            return "Can buy back"
        case .eliminated:
            if buybackDeclined, let eliminatedWeek {
                return "Out · no buyback after week \(eliminatedWeek)"
            }
            return "Out"
        }
    }
}

@Observable
final class PlayerSession {
    var userID: String?
    var accountLabel = ""
    var entries: [ClaimedEntry] = []
    var games: [PoolGame] = []
    var privatePicks: [String: [Int: String]] = [:]
    var errorMessage: String?
    var notice: String?
    var isBusy = false
    var isAdmin = false
    var standings: [ClaimedEntry] = []
    var standingsLoaded = false
    var teamLogos: [String: URL] = [:]
    var privatePicksReady = false

    var roster: [ClaimedEntry] { isAdmin ? standings : [] }

    private func functionsClient() -> Functions {
        Functions.functions(region: "us-east4")
    }
    private let isPreview: Bool
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var entryListener: ListenerRegistration?
    private var gameListener: ListenerRegistration?
    private var standingsListener: ListenerRegistration?
    private var teamListener: ListenerRegistration?
    private var allPrivatePicksListener: ListenerRegistration?
    private var commissionerPickListener: ListenerRegistration?
    private var privateListeners: [ListenerRegistration] = []
    private var currentNonce: String?

    init() {
        isPreview = false
        let current = Auth.auth().currentUser
        userID = current?.uid
        accountLabel = Self.accountLabel(for: current)
        authHandle = Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor in
                self.userID = user?.uid
                self.accountLabel = Self.accountLabel(for: user)
                self.watchPool()
            }
        }
    }

#if DEBUG
    struct PreviewSample {
        var userID: String?
        var accountLabel = ""
        var entries: [ClaimedEntry] = []
        var games: [PoolGame] = []
        var privatePicks: [String: [Int: String]] = [:]
        var standings: [ClaimedEntry] = []
        var standingsLoaded = false
        var isAdmin = false
        var privatePicksReady = false
        var teamLogos: [String: URL] = [:]
        var notice: String?
        var errorMessage: String?
    }

    init(preview sample: PreviewSample) {
        isPreview = true
        userID = sample.userID
        accountLabel = sample.accountLabel
        entries = sample.entries
        games = sample.games
        privatePicks = sample.privatePicks
        standings = sample.standings
        standingsLoaded = sample.standingsLoaded
        isAdmin = sample.isAdmin
        privatePicksReady = sample.privatePicksReady
        teamLogos = sample.teamLogos
        notice = sample.notice
        errorMessage = sample.errorMessage
    }
#endif

    var isSignedIn: Bool { userID != nil }

    func picks(for entry: ClaimedEntry) -> [Int: String] {
        var combined = entry.picks
        for (week, team) in privatePicks[entry.id] ?? [:] {
            combined[week] = team
        }
        return combined
    }

    func usedTeams(for entry: ClaimedEntry) -> [String: Int] {
        var used = entry.usedTeams
        for (week, team) in privatePicks[entry.id] ?? [:] {
            used[team] = week
        }
        return used
    }

    var openWeek: Int? {
        games.filter { !$0.hasKickedOff }.map(\.week).min()
    }

    func games(in week: Int) -> [PoolGame] {
        games.filter { $0.week == week }.sorted { $0.kickoff < $1.kickoff }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            let code = (error as NSError).code
            if code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            await signIn(with: authorization)
        }
    }

    func claim(pin: String) async {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if isPreview {
            guard EntryPin.isValid(trimmed) else {
                errorMessage = "A PIN is one letter followed by four digits from 1 to 9."
                return
            }
            notice = "Claimed a sample entry."
            errorMessage = nil
            return
        }
        guard EntryPin.isValid(trimmed) else {
            errorMessage = "A PIN is one letter followed by four digits from 1 to 9."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await functionsClient().httpsCallable("claimEntry").call(["pin": trimmed])
            let label = (result.data as? [String: Any])?["label"] as? String
            notice = label.map { "Claimed \($0)." } ?? "Entry claimed."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            notice = nil
        }
    }

    func submitPick(entryID: String, week: Int, team: String, confirmation: String? = nil) async {
        if isPreview {
            privatePicks[entryID, default: [:]][week] = team
            notice = confirmation ?? "Week \(week) pick saved. You can change it until kickoff."
            errorMessage = nil
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await functionsClient().httpsCallable("submitPick").call([
                "entryId": entryID,
                "week": week,
                "team": team,
            ])
            notice = confirmation ?? "Week \(week) pick saved. You can change it until kickoff."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            notice = nil
        }
    }

    func signOut() {
        if isPreview {
            userID = nil
            accountLabel = ""
            isAdmin = false
            entries = []
            notice = nil
            errorMessage = nil
            return
        }
        do {
            try Auth.auth().signOut()
            notice = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signIn(with authorization: ASAuthorization) async {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else {
            errorMessage = "Apple did not return a sign-in token."
            return
        }
        do {
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: token,
                rawNonce: nonce,
                fullName: credential.fullName
            )
            _ = try await Auth.auth().signIn(with: firebaseCredential)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func watchPool() {
        entryListener?.remove()
        gameListener?.remove()
        clearPrivateListeners()
        entryListener = nil
        gameListener = nil
        guard userID != nil else {
            entries = []
            games = []
            privatePicks = [:]
            standings = []
            standingsLoaded = false
            teamLogos = [:]
            privatePicksReady = false
            isAdmin = false
            standingsListener?.remove()
            standingsListener = nil
            teamListener?.remove()
            teamListener = nil
            allPrivatePicksListener?.remove()
            allPrivatePicksListener = nil
            commissionerPickListener?.remove()
            commissionerPickListener = nil
            return
        }

        let uid = userID ?? ""
        entryListener = Firestore.firestore().collection("entries")
            .whereField("playerId", isEqualTo: uid)
            .addSnapshotListener { snapshot, error in
                let parsed = snapshot?.documents.compactMap(ClaimedEntry.init(document:)) ?? []
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    self.entries = parsed.sorted {
                        $0.label.localizedStandardCompare($1.label) == .orderedAscending
                    }
                    self.watchPrivatePicks()
                }
            }

        gameListener = Firestore.firestore().collection("games")
            .whereField("season", isEqualTo: 2026)
            .addSnapshotListener { snapshot, error in
                let parsed = snapshot?.documents.compactMap(PoolGame.init(document:)) ?? []
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    self.games = parsed
                }
            }
        standingsListener?.remove()
        standingsListener = Firestore.firestore().collection("entries")
            .addSnapshotListener { snapshot, error in
                let parsed = snapshot?.documents.compactMap(ClaimedEntry.init(document:)) ?? []
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    self.standings = parsed.sorted {
                        $0.label.localizedStandardCompare($1.label) == .orderedAscending
                    }
                    self.standingsLoaded = true
                }
            }

        teamListener?.remove()
        teamListener = Firestore.firestore().collection("teams")
            .addSnapshotListener { snapshot, error in
                var logos: [String: URL] = [:]
                for document in snapshot?.documents ?? [] {
                    if let raw = document.data()["logoUrl"] as? String, let url = URL(string: raw) {
                        logos[document.documentID] = url
                    }
                }
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    self.teamLogos = logos
                }
            }
        Task { await refreshAccess() }
    }

    func refreshAccess() async {
        guard let user = Auth.auth().currentUser else {
            isAdmin = false
            watchPrivatePicks()
            watchAllPrivatePicks()
            return
        }
        do {
            let result = try await functionsClient().httpsCallable("syncCommissionerClaim").call([:])
            let granted = (result.data as? [String: Any])?["admin"] as? Bool == true
            if granted {
                _ = try await user.getIDTokenResult(forcingRefresh: true)
            }
            let token = try await user.getIDTokenResult()
            isAdmin = granted || token.claims["admin"] as? Bool == true
        } catch {
            let token = try? await user.getIDTokenResult()
            isAdmin = token?.claims["admin"] as? Bool == true
        }
        watchPrivatePicks()
        watchAllPrivatePicks()
    }

    func watchCommissionerEntry(_ entryID: String?) {
        guard !isPreview else { return }
        commissionerPickListener?.remove()
        commissionerPickListener = nil
        guard isAdmin, let entryID else { return }
        commissionerPickListener = Firestore.firestore()
            .collection("entries")
            .document(entryID)
            .collection("privatePicks")
            .addSnapshotListener { snapshot, error in
                var weekPicks: [Int: String] = [:]
                for document in snapshot?.documents ?? [] {
                    let data = document.data()
                    let week = data["week"] as? Int ?? Int(document.documentID)
                    if let week, let team = data["team"] as? String {
                        weekPicks[week] = team
                    }
                }
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    self.privatePicks[entryID] = weekPicks
                }
            }
    }

    func recordBuyback(entryID: String) async {
        await callCommissioner("recordBuyback", ["entryId": entryID], success: "Buyback recorded. Used teams stay used.")
    }

    func declineBuyback(entryID: String) async {
        await callCommissioner("declineBuyback", ["entryId": entryID], success: "Buyback declined. This entry is out.")
    }

    func closeWeek(week: Int, apply: Bool) async -> CloseWeekReport? {
        if isPreview {
            let report = CloseWeekReport(
                week: week,
                missingPicks: 2,
                losses: 1,
                wins: 4,
                ungraded: apply ? 0 : 1,
                updated: apply ? 3 : 0,
                applied: apply,
                examples: ["Will Castellano has no pick.", "Pat Buyer lost with Bengals."]
            )
            notice = apply
                ? "Week \(week) closed. \(report.updated) entries updated."
                : "Week \(week) preview: \(report.missingPicks) missing picks, \(report.losses) losses, \(report.wins) wins."
            errorMessage = nil
            return report
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await functionsClient().httpsCallable("closeWeek").call([
                "week": week,
                "apply": apply,
            ])
            let data = result.data as? [String: Any] ?? [:]
            let report = CloseWeekReport(
                week: integer(data["week"]) ?? week,
                missingPicks: integer(data["missingPicks"]) ?? 0,
                losses: integer(data["losses"]) ?? 0,
                wins: integer(data["wins"]) ?? 0,
                ungraded: integer(data["ungraded"]) ?? 0,
                updated: integer(data["updated"]) ?? 0,
                applied: data["applied"] as? Bool ?? apply,
                examples: data["examples"] as? [String] ?? []
            )
            notice = apply
                ? "Week \(week) closed. \(report.updated) entries updated."
                : "Week \(week) preview: \(report.missingPicks) missing picks, \(report.losses) losses, \(report.wins) wins."
            errorMessage = nil
            return report
        } catch {
            errorMessage = error.localizedDescription
            notice = nil
            return nil
        }
    }

    func addCommissionerEmail(_ email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        await callCommissioner("addCommissionerEmail", ["email": trimmed], success: "\(trimmed) can become a commissioner after signing in.")
    }

    private func callCommissioner(_ name: String, _ data: [String: Any], success: String) async {
        if isPreview {
            notice = success
            errorMessage = nil
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await functionsClient().httpsCallable(name).call(data)
            notice = success
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            notice = nil
        }
    }

    private func watchAllPrivatePicks() {
        allPrivatePicksListener?.remove()
        allPrivatePicksListener = nil
        guard isAdmin else {
            privatePicksReady = false
            return
        }
        privatePicksReady = false
        allPrivatePicksListener = Firestore.firestore().collectionGroup("privatePicks")
            .addSnapshotListener { snapshot, error in
                var picksByEntry: [String: [Int: String]] = [:]
                for document in snapshot?.documents ?? [] {
                    guard let entryID = document.reference.parent.parent?.documentID else { continue }
                    let data = document.data()
                    let week = data["week"] as? Int ?? Int(document.documentID)
                    guard let week, let team = data["team"] as? String else { continue }
                    picksByEntry[entryID, default: [:]][week] = team
                }
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    self.privatePicks = picksByEntry
                    self.privatePicksReady = true
                }
            }
    }

    private func watchPrivatePicks() {
        clearPrivateListeners()
        guard !isAdmin else { return }
        let entryIDs = Set(entries.map(\.id))
        privatePicks = privatePicks.filter { entryIDs.contains($0.key) }
        for entry in entries {
            let registration = Firestore.firestore()
                .collection("entries")
                .document(entry.id)
                .collection("privatePicks")
                .addSnapshotListener { snapshot, error in
                    var weekPicks: [Int: String] = [:]
                    for document in snapshot?.documents ?? [] {
                        let data = document.data()
                        let week = data["week"] as? Int ?? Int(document.documentID)
                        let team = data["team"] as? String
                        if let week, let team { weekPicks[week] = team }
                    }
                    let failure = error?.localizedDescription
                    let entryID = entry.id
                    Task { @MainActor in
                        if let failure { self.errorMessage = failure }
                        self.privatePicks[entryID] = weekPicks
                    }
                }
            privateListeners.append(registration)
        }
    }

    private func clearPrivateListeners() {
        privateListeners.forEach { $0.remove() }
        privateListeners.removeAll()
    }

    private static func accountLabel(for user: User?) -> String {
        if let email = user?.email, !email.isEmpty { return email }
        return user == nil ? "" : "Signed in with Apple"
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private extension ClaimedEntry {
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        guard let label = data["label"] as? String else { return nil }
        self.id = document.documentID
        self.label = label
        self.status = EntryStatus(rawValue: data["status"] as? String ?? "") ?? .eliminated
        self.eliminatedWeek = integer(data["eliminatedWeek"])
        self.buybackDeclined = data["buybackDeclined"] as? Bool ?? false
        self.picks = Self.weekTeams(data["picks"])
        self.usedTeams = Self.teamWeeks(data["usedTeams"])
        self.buybackWeeks = Self.buybackWeeks(data["buybacks"])
        let owner = data["playerId"] as? String
        self.isClaimed = owner?.isEmpty == false
    }

    static func buybackWeeks(_ value: Any?) -> [Int] {
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { row in
            let map: [String: Any]?
            if let typed = row as? [String: Any] {
                map = typed
            } else if let object = row as? NSDictionary {
                map = object as? [String: Any]
            } else {
                map = nil
            }
            return integer(map?["eliminatedWeek"])
        }
    }

    static func weekTeams(_ value: Any?) -> [Int: String] {
        guard let raw = value as? [String: Any] else { return [:] }
        var picks: [Int: String] = [:]
        for (week, team) in raw {
            guard let week = Int(week), let team = team as? String else { continue }
            picks[week] = team
        }
        return picks
    }

    static func teamWeeks(_ value: Any?) -> [String: Int] {
        guard let raw = value as? [String: Any] else { return [:] }
        var used: [String: Int] = [:]
        for (team, week) in raw {
            if let week = integer(week) { used[team] = week }
        }
        return used
    }
}

private func integer(_ value: Any?) -> Int? {
    switch value {
    case let number as Int:
        return number
    case let number as Int64:
        return Int(number)
    case let number as NSNumber:
        return number.intValue
    default:
        return nil
    }
}

private extension PoolGame {
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        guard let week = integer(data["week"]),
              let home = data["homeAbbr"] as? String,
              let away = data["awayAbbr"] as? String,
              let kickoff = data["kickoffAt"] as? Timestamp else {
            return nil
        }
        self.id = document.documentID
        self.week = week
        self.homeAbbr = home
        self.awayAbbr = away
        self.kickoff = kickoff.dateValue()
        self.status = data["status"] as? String ?? "scheduled"
        if let spread = data["spreadHome"] as? NSNumber {
            self.spreadHome = spread.doubleValue
        } else if let spread = data["spreadHome"] as? Double {
            self.spreadHome = spread
        }
    }
}
