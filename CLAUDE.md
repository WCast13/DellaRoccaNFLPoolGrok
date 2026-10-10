# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An iOS/SwiftUI NFL survivor pool app for a private pool. One entry picks one NFL team per week and may never reuse a team; after a wrong pick in weeks 1–6 the player can buy back in, confirmed by making the next week's pick. Season is hardcoded to **2026**, weeks 1–18.

Two codebases in one repo: the SwiftUI client (`DellaRoccaNFLPoolGrok/`) and the Firebase backend (`firebase/`).

## Read MODEL.md first

`MODEL.md` is the authoritative cheat sheet for the data model — every Firestore collection, field, type, and relationship, plus the full callable-function table and the status-transition rules. Any task touching entries, picks, buybacks, grading, or week-closing should start there. Do not re-derive the schema by reading Firestore code, and keep `MODEL.md` current when the shape changes.

`UX-CHECKLIST.md` is a living list of UX work; checked items are shipped. Update it when you complete or add an item.

## Commands

Build the app (quote the path — the repo lives in iCloud Drive, so it contains spaces and `~`):

```bash
xcodebuild -project DellaRoccaNFLPoolGrok.xcodeproj \
  -scheme DellaRoccaNFLPoolGrok \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Backend:

```bash
npm --prefix firebase/functions install
npm --prefix firebase/functions run build     # tsc — the only check that exists
cd firebase && firebase deploy --only functions
cd firebase && firebase deploy --only firestore:rules
```

**There is no test target and no linter.** Correctness is verified by building and by the `#Preview` blocks (see below). Don't claim tests pass; there are none to run.

### Build gotcha

`IPHONEOS_DEPLOYMENT_TARGET` is **27.0** while the installed Xcode (26.3) supports up to 26.2.99. The build **succeeds** but emits `the range of supported deployment target versions is 12.0 to 26.2.99`. That warning is expected and pre-existing — not something you introduced.

## Architecture

### `PlayerSession` is the whole app

`Session/PlayerSession.swift` (~680 lines) is the single `@Observable` object holding all state, all Firestore listeners, and every Cloud Functions call. There is no separate view-model, repository, or service layer. Views read it directly.

Views receive it as **optional** — `var session: PlayerSession?` — because `ContentView` constructs it in `.task`, after first render. Every view must handle `nil` as "not ready yet". Follow this pattern in new views rather than forcing unwraps.

### Reads and writes go different ways

This asymmetry is the most important thing to understand:

- **Reads**: direct Firestore `addSnapshotListener` calls, live. Set up in `watchPool()`.
- **Writes**: always `httpsCallable` to Cloud Functions in region **`us-east4`** (`functionsClient()`). The client never writes Firestore directly.

Adding a mutation means adding a callable in `firebase/functions/src/index.ts` and a wrapper method on `PlayerSession` — not a Firestore write.

### Preview mode is a parallel implementation

`PlayerSession` has an `isPreview` flag and a `#if DEBUG init(preview:)` taking a `PreviewSample`. **Every mutating method branches on `isPreview` and fakes the mutation locally** instead of calling Firebase — see `claim`, `submitPick`, `signOut`, `electBuyback`, `callCommissioner`.

If you add a session method that touches Firebase, you must add an `if isPreview { ... }` branch or every `#Preview` using it will hang or crash. Fixtures live in `Preview/PreviewData.swift` (`signedOut()`, `loading()`, `claim()`, `player()`, `commissioner()`). Previews are the de facto test suite here — add them for new views, and keep the existing ones compiling.

### Pick visibility: private before kickoff, public after

A pick lives in `entries/{id}/privatePicks/{week}` until its game kicks off, then the backend copies it onto `entries/{id}.picks` + `.usedTeams` and deletes the private doc (`publishLockedPicks`).

So the client holds two sources and must merge them. **Always use the accessors** `session.picks(for: entry)` and `session.usedTeams(for: entry)`, which overlay `privatePicks[entry.id]` on top of the public `entry.picks` / `entry.usedTeams`. Reading the raw fields silently drops the current week's unlocked pick.

### Player vs admin listener topology

`refreshAccess()` resolves admin status by calling `syncCommissionerClaim`, force-refreshing the ID token when granted, then reading the `admin` custom claim. Admin status then selects which private-pick listeners attach:

- **Player**: `watchPrivatePicks()` — one listener per owned entry.
- **Admin**: `watchAllPrivatePicks()` — a single `collectionGroup("privatePicks")` listener across all entries, gated by `privatePicksReady`.
- **Admin viewing one entry**: `watchCommissionerEntry(_:)`.

These are mutually exclusive (`watchPrivatePicks` early-returns when `isAdmin`). Changing one usually means changing the others, and listeners must be removed before reassignment — `watchPool()` tears everything down on sign-out.

Admin status also drives UI: the Commissioner tab only exists when `session?.isAdmin == true`.

### Status and notices

All mutations funnel success into `session.notice` and failure into `session.errorMessage`; `StatusBanner` renders them. Set one and clear the other — the existing methods always do both.

### Pick rules exist on both sides

`Features/Entries/EntryPickRules.swift` decides what the UI allows (greys out a team, explains "Used in week 2" / "Locked", titles the save button). The server re-validates independently in `firebase/functions/src/`. **These must be changed together** — the client copy is an affordance, not the enforcement point, and divergence shows up as a button that submits and then fails.

### Team colors come from the asset catalog

`Models/NFLTeam.swift` holds the hardcoded 32-team catalog with official palettes. `TeamColor.assetName` resolves to the namespaced color set `NFL Team Colors/<team>/<color name>`, so a new or renamed color needs a matching asset or it renders wrong. The initializer has a `precondition` requiring 6 hex digits. `TeamColor.foreground` auto-picks black or white text by relative luminance — use it rather than hardcoding a text color on a team-colored surface. Most teams have three colors; Raiders, Steelers, and 49ers have two.

## Conventions

- Firestore decoding lives in `private extension` initializers taking `DocumentSnapshot` (`ClaimedEntry.init(document:)`, `PoolGame.init(document:)`), returning `nil` on malformed docs so bad rows are skipped rather than crashing. A document with no `label` is intentionally dropped.
- Numbers from Firestore arrive as `Int`, `Int64`, or `NSNumber` depending on path — the file-private `integer(_:)` helper normalizes them. Use it instead of a direct cast.
- Snapshot callbacks are not on the main actor. Parse inside the callback, then hop with `Task { @MainActor in ... }` to assign to observable state. Keep this pattern; assigning directly from the callback is a data race.
- Views are small and single-purpose (`Features/<Area>/<Thing>View.swift` or a row/bar/banner component). Prefer a new small file over growing an existing view.
- The Pool board's commissioner badge reads the server-written `entries.isCommissioner` field (display only). It is **not** an access check — authorization is the Firebase `admin` custom claim. The field is maintained by `claimEntry`, `syncCommissionerClaim`, `addCommissionerEmail`, and `removeCommissionerEmail`.

## Secrets and sensitive files

- `private/` is gitignored and holds real entry PINs (`week3-entries-with-pins.json`). Never print its contents, commit it, or paste it into anything outward-facing.
- Backend API keys are Firebase secrets (`APISPORTS_KEY`, `ODDS_API_KEY`) via `defineSecret`, not files.
- `GoogleService-Info.plist` is committed, which is normal for Firebase iOS clients — security is enforced by `firebase/firestore.rules` plus the callables, not by hiding it.
