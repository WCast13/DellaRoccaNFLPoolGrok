import { FieldValue, getFirestore, type WriteBatch } from "firebase-admin/firestore";

// The commissioner activity log: one document per thing that happened, written
// only from here (Admin SDK). The app reads the newest few hundred on the
// Commissioner tab. Every mutation callable and every sync or close run logs,
// so a commissioner can answer "what happened to this entry, and who did it"
// without the Firebase console.
//
// Types are dotted, prefix first, so the app can bucket them without a list:
//   pick.submitted  pick.changed
//   auth.signIn  entry.claimed
//   buyback.elected  buyback.recorded  buyback.declined  buyback.feePaid
//   buyback.confirmed  buyback.lapsed  entry.knockedOut  entry.eliminated
//   system.sync  system.syncFailed  system.weekGraded  system.gradeWeeks
//   commissioner.added  commissioner.removed

const SEASON = 2026;
export const ACTIVITY_LOG = "activityLog";

export type ActorRole = "player" | "commissioner" | "system";

export interface LogActor {
  role: ActorRole;
  uid?: string;
  email?: string;
}

export const SYSTEM_ACTOR: LogActor = { role: "system" };

export interface LogEvent {
  type: string;
  /// One line, past tense, naming the entry. What the app shows.
  summary: string;
  actor: LogActor;
  entryId?: string;
  entryLabel?: string;
  week?: number;
  team?: string;
  previousTeam?: string;
  details?: Record<string, unknown>;
}

type AuthLike = { uid: string; token: Record<string, unknown> };

/// Who made a callable request: a commissioner when the admin claim is on the
/// token, otherwise a player. Email comes from the token when Apple shared it.
export function actorFrom(auth: AuthLike): LogActor {
  const email = typeof auth.token.email === "string" && auth.token.email.length > 0
    ? auth.token.email.toLowerCase()
    : undefined;
  return { role: auth.token.admin === true ? "commissioner" : "player", uid: auth.uid, email };
}

/// Firestore rejects `undefined` values, so optional fields are dropped
/// rather than written as undefined.
function stripUndefined<T extends Record<string, unknown>>(value: T): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) {
    if (item === undefined) continue;
    out[key] = item && typeof item === "object" && !Array.isArray(item)
      ? stripUndefined(item as Record<string, unknown>)
      : item;
  }
  return out;
}

function document(event: LogEvent): Record<string, unknown> {
  return {
    season: SEASON,
    at: FieldValue.serverTimestamp(),
    ...stripUndefined(event as unknown as Record<string, unknown>),
  };
}

/// Writes one event on its own. Never throws: a failed log line must not fail
/// the pick or buyback it describes, so the error goes to the console instead.
export async function logEvent(event: LogEvent): Promise<void> {
  try {
    await getFirestore().collection(ACTIVITY_LOG).add(document(event));
  } catch (error) {
    console.error(`activityLog: could not write ${event.type}`, error);
  }
}

/// Adds the event to a batch the caller is already filling, so a close run
/// writes each entry and its log line in the same commit.
export function logEventInBatch(batch: WriteBatch, event: LogEvent): void {
  batch.set(getFirestore().collection(ACTIVITY_LOG).doc(), document(event));
}
