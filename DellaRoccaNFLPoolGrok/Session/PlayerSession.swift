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
    /// Filled once the backend sees a score. Nil before kickoff, and for a game
    /// the feed has not scored yet.
    var homeScore: Int?
    var awayScore: Int?

    var hasKickedOff: Bool { kickoff <= Date() }

    var isFinal: Bool { status == "final" }

    /// "20 – 17" in away–home order, matching how the teams are laid out.
    var scoreLabel: String? {
        guard let homeScore, let awayScore else { return nil }
        return "\(awayScore) – \(homeScore)"
    }

    /// The abbreviation that won, once the game is final. Nil for a tie, an
    /// unfinished game, or a final game the feed has not scored.
    var winner: String? {
        guard isFinal, let homeScore, let awayScore, homeScore != awayScore else { return nil }
        return homeScore > awayScore ? homeAbbr : awayAbbr
    }

    var spreadLabel: String? {
        guard let spreadHome else { return nil }
        let rounded = (spreadHome * 2).rounded() / 2
        let text = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%+.0f", rounded)
            : String(format: "%+.1f", rounded)
        return "\(homeAbbr) \(text)"
    }
}

/// The player's reversible choice after a knockout in weeks 1-6. Written by the
/// `electBuyback` callable; cleared by the backend once the decision resolves.
enum BuybackElection: String, Hashable, Sendable {
    case buyIn = "in"
    case stayOut = "out"
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
    /// Whether this entry's owner is a commissioner. Server-provided; drives
    /// the board badge. Never an authorization check — that is the admin claim.
    var isCommissioner: Bool = false
    /// The player's buyback choice, while it is still changeable.
    var buybackElection: BuybackElection? = nil
    /// The player elected a buyback and the fee has not been collected.
    var buybackUnpaid: Bool = false

    /// Last week (inclusive) in which a knocked-out entry may still buy back.
    static let lastBuybackWeek = 6

    var canBuyBack: Bool {
        guard status == .pendingBuyback, !buybackDeclined else { return false }
        // An unknown elimination week is treated as eligible, matching
        // `statusLine` and the commissioner buyback section so all three
        // surfaces agree. The backend re-validates before applying a buyback.
        guard let eliminatedWeek else { return true }
        return eliminatedWeek <= Self.lastBuybackWeek
    }

    /// The week this entry must pick for to complete a buyback. A buyback is
    /// confirmed by that pick, not by electing alone.
    var buybackPickWeek: Int? {
        guard !buybackDeclined, let eliminatedWeek, eliminatedWeek <= Self.lastBuybackWeek else {
            return nil
        }
        return eliminatedWeek + 1
    }

    /// The player still has a buyback decision open, or can still change it.
    var hasOpenBuybackDecision: Bool {
        guard buybackPickWeek != nil else { return false }
        if status == .pendingBuyback { return true }
        return status == .active && buybackElection == .buyIn
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
@MainActor
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
    var standings: [ClaimedEntry] = [] {
        didSet { recomputeStandingBuckets() }
    }
    var standingsLoaded = false
    var teamLogos: [String: URL] = [:]
    var privatePicksReady = false

    /// Standings partitioned by board status. Cached and recomputed only when
    /// `standings` changes so SwiftUI bodies (e.g. the searchable pool board)
    /// don't re-filter the whole roster on every keystroke.
    private(set) var aliveEntries: [ClaimedEntry] = []
    private(set) var buybackEntries: [ClaimedEntry] = []
    private(set) var eliminatedEntries: [ClaimedEntry] = []

    var roster: [ClaimedEntry] { isAdmin ? standings : [] }

    private func recomputeStandingBuckets() {
        aliveEntries = standings.filter { $0.status == .active }
        buybackEntries = standings.filter(\.canBuyBack)
        eliminatedEntries = standings.filter {
            $0.status == .eliminated || ($0.status == .pendingBuyback && !$0.canBuyBack)
        }
    }

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
    private var subscribedPrivatePickIDs: Set<String> = []
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
            // Optimistically reflect the saved pick locally so the save bar
            // settles immediately; the privatePicks listener reconciles it.
            privatePicks[entryID, default: [:]][week] = team
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
                // Keep the last-known-good entries on an error delivery (nil snapshot);
                // only surface the error rather than wiping the list to empty.
                let parsed = snapshot?.documents.compactMap(ClaimedEntry.init(document:))
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    guard let parsed else { return }
                    self.entries = parsed.sorted {
                        $0.label.localizedStandardCompare($1.label) == .orderedAscending
                    }
                    self.watchPrivatePicks()
                }
            }

        gameListener = Firestore.firestore().collection("games")
            .whereField("season", isEqualTo: 2026)
            .addSnapshotListener { snapshot, error in
                let parsed = snapshot?.documents.compactMap(PoolGame.init(document:))
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    guard let parsed else { return }
                    self.games = parsed
                }
            }
        standingsListener?.remove()
        standingsListener = Firestore.firestore().collection("entries")
            .addSnapshotListener { snapshot, error in
                let parsed = snapshot?.documents.compactMap(ClaimedEntry.init(document:))
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    guard let parsed else { return }
                    self.standings = parsed.sorted {
                        $0.label.localizedStandardCompare($1.label) == .orderedAscending
                    }
                    self.standingsLoaded = true
                }
            }

        teamListener?.remove()
        teamListener = Firestore.firestore().collection("teams")
            .addSnapshotListener { snapshot, error in
                let logos: [String: URL]? = snapshot.map { snap in
                    var result: [String: URL] = [:]
                    for document in snap.documents {
                        if let raw = document.data()["logoUrl"] as? String, let url = URL(string: raw) {
                            result[document.documentID] = url
                        }
                    }
                    return result
                }
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    guard let logos else { return }
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
        var resolvedAdmin = false
        var claimLagged = false
        do {
            let result = try await functionsClient().httpsCallable("syncCommissionerClaim").call([:])
            let granted = (result.data as? [String: Any])?["admin"] as? Bool == true
            // Base admin status on the claim actually present in the token the
            // Firestore SDK will use — not on the function's return. A fresh grant
            // can lag the token by a moment, so when the server says we're admin
            // but the claim hasn't landed yet, force-refresh and retry briefly.
            // A genuinely lagging claim denies the collectionGroup listener, so the
            // retry below is still worth having — but it was never the cause of the
            // "Missing or insufficient permissions" seen here. firestore.rules only
            // declared privatePicks under a concrete /entries/{entryId} parent, which
            // cannot authorize a collection-group query at all; the recursive-wildcard
            // rule is what fixes that.
            var token = try await user.getIDTokenResult(forcingRefresh: granted)
            if granted {
                var attempts = 0
                while token.claims["admin"] as? Bool != true && attempts < 3 {
                    // Swallow cancellation here rather than throwing into the catch
                    // below, which would resolve a cancelled refresh to "not admin".
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    token = try await user.getIDTokenResult(forcingRefresh: true)
                    attempts += 1
                }
            }
            resolvedAdmin = token.claims["admin"] as? Bool == true
            // The server granted the claim but it never reached the token. Nothing
            // calls refreshAccess() again until the next auth-state change, so say
            // so instead of leaving a real commissioner silently demoted.
            claimLagged = granted && !resolvedAdmin
        } catch {
            let token = try? await user.getIDTokenResult()
            resolvedAdmin = token?.claims["admin"] as? Bool == true
        }
        // A cancelled refresh means the caller went away mid-retry, not that the
        // claim is absent. Leave isAdmin and the listeners as they stand.
        if Task.isCancelled { return }
        // The awaits above can span a sign-out or an account switch. Don't let a
        // stale user decide admin status for whoever is signed in now, and don't
        // re-attach listeners that watchPool() has already torn down.
        guard Auth.auth().currentUser?.uid == user.uid else { return }
        isAdmin = resolvedAdmin
        if claimLagged {
            errorMessage = "Commissioner access is still syncing. Sign out and back in if the Commissioner tab does not appear."
            notice = nil
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
                let weekPicks: [Int: String]? = snapshot.map { snap in
                    var result: [Int: String] = [:]
                    for document in snap.documents {
                        let data = document.data()
                        let week = data["week"] as? Int ?? Int(document.documentID)
                        if let week, let team = data["team"] as? String {
                            result[week] = team
                        }
                    }
                    return result
                }
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    guard let weekPicks else { return }
                    self.privatePicks[entryID] = weekPicks
                }
            }
    }

    func recordBuyback(entryID: String) async {
        await callCommissioner("recordBuyback", ["entryId": entryID], success: "Buyback recorded. Used teams stay used.")
    }

    /// The player's own buyback decision. Electing in makes the entry active so
    /// it can pick; the buyback is only confirmed when that pick exists at the
    /// deadline. Reversible until then.
    func electBuyback(entryID: String, buyBackIn: Bool) async {
        let success = buyBackIn
            ? "You're back in. Make your pick to lock it in."
            : "You're staying out. You can change this until the deadline."
        if isPreview {
            if let index = entries.firstIndex(where: { $0.id == entryID }) {
                entries[index].buybackElection = buyBackIn ? .buyIn : .stayOut
                entries[index].status = buyBackIn ? .active : .pendingBuyback
                entries[index].buybackUnpaid = buyBackIn
            }
            notice = success
            errorMessage = nil
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await functionsClient().httpsCallable("electBuyback").call([
                "entryId": entryID,
                "buyBackIn": buyBackIn,
            ])
            notice = success
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            notice = nil
        }
    }

    func markBuybackPaid(entryID: String) async {
        await callCommissioner("markBuybackPaid", ["entryId": entryID], success: "Buyback marked paid.")
    }

    func declineBuyback(entryID: String) async {
        await callCommissioner("declineBuyback", ["entryId": entryID], success: "Buyback declined. This entry is out.")
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
                let picksByEntry: [String: [Int: String]]? = snapshot.map { snap in
                    var result: [String: [Int: String]] = [:]
                    for document in snap.documents {
                        guard let entryID = document.reference.parent.parent?.documentID else { continue }
                        let data = document.data()
                        let week = data["week"] as? Int ?? Int(document.documentID)
                        guard let week, let team = data["team"] as? String else { continue }
                        result[entryID, default: [:]][week] = team
                    }
                    return result
                }
                let failure = error?.localizedDescription
                Task { @MainActor in
                    if let failure { self.errorMessage = failure }
                    guard let picksByEntry else { return }
                    self.privatePicks = picksByEntry
                    self.privatePicksReady = true
                }
            }
    }

    private func watchPrivatePicks() {
        guard !isAdmin else {
            clearPrivateListeners()
            return
        }
        let entryIDs = Set(entries.map(\.id))
        // The entries listener calls this on every snapshot delivery. Skip the
        // full teardown/rebuild of per-entry listeners when the set of entries
        // hasn't actually changed, which also avoids a removed listener's
        // already-queued async write racing the fresh one.
        if entryIDs == subscribedPrivatePickIDs { return }
        clearPrivateListeners()
        subscribedPrivatePickIDs = entryIDs
        privatePicks = privatePicks.filter { entryIDs.contains($0.key) }
        for entry in entries {
            let entryID = entry.id
            let registration = Firestore.firestore()
                .collection("entries")
                .document(entryID)
                .collection("privatePicks")
                .addSnapshotListener { snapshot, error in
                    let weekPicks: [Int: String]? = snapshot.map { snap in
                        var result: [Int: String] = [:]
                        for document in snap.documents {
                            let data = document.data()
                            let week = data["week"] as? Int ?? Int(document.documentID)
                            let team = data["team"] as? String
                            if let week, let team { result[week] = team }
                        }
                        return result
                    }
                    let failure = error?.localizedDescription
                    Task { @MainActor in
                        if let failure { self.errorMessage = failure }
                        guard let weekPicks else { return }
                        self.privatePicks[entryID] = weekPicks
                    }
                }
            privateListeners.append(registration)
        }
    }

    private func clearPrivateListeners() {
        privateListeners.forEach { $0.remove() }
        privateListeners.removeAll()
        subscribedPrivatePickIDs = []
    }

    private static func accountLabel(for user: User?) -> String {
        if let email = user?.email, !email.isEmpty { return email }
        return user == nil ? "" : "Signed in with Apple"
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
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
    // Firestore snapshot callbacks run off the main actor; parsing must be
    // callable there, so the decoders and their helpers are nonisolated.
    nonisolated init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        guard let label = data["label"] as? String else {
            print("[PlayerSession] Dropped entry \(document.documentID): missing 'label'")
            return nil
        }
        self.id = document.documentID
        self.label = label
        // Fail safe: a missing/unrecognized status defaults to alive rather
        // than silently knocking the entry out. The backend is authoritative.
        self.status = EntryStatus(rawValue: data["status"] as? String ?? "") ?? .active
        self.eliminatedWeek = integer(data["eliminatedWeek"])
        self.buybackDeclined = data["buybackDeclined"] as? Bool ?? false
        self.picks = Self.weekTeams(data["picks"])
        self.usedTeams = Self.teamWeeks(data["usedTeams"])
        self.buybackWeeks = Self.buybackWeeks(data["buybacks"])
        let owner = data["playerId"] as? String
        self.isClaimed = owner?.isEmpty == false
        self.isCommissioner = data["isCommissioner"] as? Bool ?? false
        self.buybackElection = BuybackElection(rawValue: data["buybackElection"] as? String ?? "")
        self.buybackUnpaid = data["buybackUnpaid"] as? Bool ?? false
    }

    nonisolated static func buybackWeeks(_ value: Any?) -> [Int] {
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

    nonisolated static func weekTeams(_ value: Any?) -> [Int: String] {
        guard let raw = value as? [String: Any] else { return [:] }
        var picks: [Int: String] = [:]
        for (week, team) in raw {
            guard let week = Int(week), let team = team as? String else { continue }
            picks[week] = team
        }
        return picks
    }

    nonisolated static func teamWeeks(_ value: Any?) -> [String: Int] {
        guard let raw = value as? [String: Any] else { return [:] }
        var used: [String: Int] = [:]
        for (team, week) in raw {
            if let week = integer(week) { used[team] = week }
        }
        return used
    }
}

private nonisolated func integer(_ value: Any?) -> Int? {
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
    nonisolated init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        guard let week = integer(data["week"]),
              let home = data["homeAbbr"] as? String,
              let away = data["awayAbbr"] as? String,
              let kickoff = data["kickoffAt"] as? Timestamp else {
            print("[PlayerSession] Dropped game \(document.documentID): missing or invalid week/homeAbbr/awayAbbr/kickoffAt")
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
        self.homeScore = integer(data["homeScore"])
        self.awayScore = integer(data["awayScore"])
    }
}
