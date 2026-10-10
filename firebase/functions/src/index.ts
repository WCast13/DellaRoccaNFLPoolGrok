import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, type DocumentData } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { closePoolWeek } from "./close";
import { gradeImportedWeeks } from "./grade";
import { publishLockedPicks } from "./picks";
import { runSeasonSync } from "./sports";

const BOOTSTRAP_COMMISSIONER_EMAILS = ["wcastellano13@gmail.com"];

const apiSportsKey = defineSecret("APISPORTS_KEY");
const oddsApiKey = defineSecret("ODDS_API_KEY");

setGlobalOptions({ region: "us-east4" });
initializeApp();

const db = getFirestore();

const PIN_PATTERN = /^[A-Z][1-9]{4}$/;
const BUYBACK_THROUGH_WEEK = 6;
const MAX_PIN_ATTEMPTS_PER_HOUR = 8;

type AuthToken = { uid: string; token: Record<string, unknown> };

function requireUser(auth: { uid: string; token: Record<string, unknown> } | undefined): AuthToken {
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return auth;
}

function requireAdmin(auth: AuthToken) {
  if (auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Only a commissioner can do that.");
  }
}

function asTeamMap(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object") return {};
  const map: Record<string, number> = {};
  for (const [team, week] of Object.entries(value as Record<string, unknown>)) {
    if (typeof week === "number") map[team] = week;
  }
  return map;
}

function asPickMap(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object") return {};
  const map: Record<string, string> = {};
  for (const [week, team] of Object.entries(value as Record<string, unknown>)) {
    if (typeof team === "string") map[week] = team;
  }
  return map;
}

export const claimEntry = onCall(async (request) => {
  const auth = requireUser(request.auth);
  const pin = String(request.data?.pin ?? "").trim().toUpperCase();
  if (!PIN_PATTERN.test(pin)) {
    throw new HttpsError("invalid-argument", "A PIN is one letter followed by four digits from 1 to 9.");
  }

  const attemptsRef = db.collection("claimAttempts").doc(auth.uid);
  const pinRef = db.collection("entryPins").doc(pin);

  const allowed = await commissionerEmails();
  const callerEmail = String(auth.token.email ?? "").trim().toLowerCase();
  const callerIsCommissioner = callerEmail.length > 0 && allowed.has(callerEmail);

  const claim = await db.runTransaction(async (tx) => {
    const attempts = await tx.get(attemptsRef);
    const pinDoc = await tx.get(pinRef);
    const windowStart = attempts.get("windowStart")?.toMillis?.() ?? 0;
    const now = Date.now();
    const windowIsFresh = now - windowStart > 60 * 60 * 1000;
    const used = windowIsFresh ? 0 : Number(attempts.get("count") ?? 0);
    if (used >= MAX_PIN_ATTEMPTS_PER_HOUR) {
      return { error: "Too many PIN attempts. Try again in an hour.", code: "resource-exhausted" as const };
    }

    const nextWindowStart = windowIsFresh
      ? FieldValue.serverTimestamp()
      : attempts.get("windowStart") ?? FieldValue.serverTimestamp();

    if (!pinDoc.exists) {
      tx.set(attemptsRef, { count: used + 1, windowStart: nextWindowStart }, { merge: true });
      return { error: "That PIN does not match an entry.", code: "not-found" as const };
    }

    const entryId = String(pinDoc.get("entryId"));
    const entryRef = db.collection("entries").doc(entryId);
    const entry = await tx.get(entryRef);
    if (!entry.exists) {
      tx.set(attemptsRef, { count: used + 1, windowStart: nextWindowStart }, { merge: true });
      return { error: "That entry is missing.", code: "not-found" as const };
    }

    const owner = entry.get("playerId");
    const alreadyOwned = typeof owner === "string" && owner.length > 0;
    if (alreadyOwned && owner !== auth.uid) {
      // Counts against the hourly limit. Returning without incrementing made
      // probing which PINs are taken free, and the taken/not-taken split leaks
      // the valid PIN space.
      tx.set(attemptsRef, { count: used + 1, windowStart: nextWindowStart }, { merge: true });
      return { error: "That entry is already on another account.", code: "already-exists" as const };
    }

    // Reset only when this call actually transfers an unowned entry. Re-claiming
    // a PIN the caller already owns falls through to success, so resetting on
    // any success let eight guesses plus one self-claim repeat without bound
    // against a 26 * 9^4 = 170,586 PIN space.
    if (!alreadyOwned) {
      tx.set(attemptsRef, { count: 0, windowStart: FieldValue.serverTimestamp() }, { merge: true });
    }
    tx.update(entryRef, {
      playerId: auth.uid,
      claimedAt: FieldValue.serverTimestamp(),
      isCommissioner: callerIsCommissioner,
    });
    return { entryId, label: String(entry.get("label") ?? "") };
  });

  if ("error" in claim && claim.error) {
    throw new HttpsError(claim.code, claim.error);
  }
  return claim;
});

export const submitPick = onCall(async (request) => {
  const auth = requireUser(request.auth);
  const entryId = String(request.data?.entryId ?? "");
  const week = Number(request.data?.week);
  const team = String(request.data?.team ?? "").trim().toUpperCase();
  if (!entryId || !Number.isInteger(week) || week < 1 || week > 18 || !/^[A-Z]{2,3}$/.test(team)) {
    throw new HttpsError("invalid-argument", "Choose an entry, a week, and a team.");
  }

  const entryRef = db.collection("entries").doc(entryId);
  const privateRef = entryRef.collection("privatePicks").doc(String(week));
  const gameQuery = db.collection("games")
    .where("season", "==", 2026)
    .where("week", "==", week)
    .where("teams", "array-contains", team)
    .limit(1);

  await db.runTransaction(async (tx) => {
    const entry = await tx.get(entryRef);
    const games = await tx.get(gameQuery);
    const privatePicks = await tx.get(entryRef.collection("privatePicks"));
    if (!entry.exists) throw new HttpsError("not-found", "That entry is missing.");

    const data = entry.data() as DocumentData;
    const admin = isAdminCaller(auth);
    if (!admin && data.playerId !== auth.uid) {
      throw new HttpsError("permission-denied", "That entry is not on this account.");
    }
    if (data.status !== "active") {
      throw new HttpsError("failed-precondition", "This entry is knocked out.");
    }

    const now = Date.now();
    const weekKey = String(week);
    const game = games.docs[0];
    if (!game) throw new HttpsError("failed-precondition", "That team does not play this week.");
    const kickoff = game.get("kickoffAt")?.toMillis?.() ?? 0;
    const locked = kickoff <= now;
    if (!admin && locked) {
      throw new HttpsError("failed-precondition", "That game has already kicked off.");
    }

    const taken = asTeamMap(data.usedTeams);
    for (const pickDoc of privatePicks.docs) {
      const pickedWeek = Number(pickDoc.id);
      const pickedTeam = String(pickDoc.get("team") ?? "");
      if (pickedTeam && Number.isInteger(pickedWeek)) taken[pickedTeam] = pickedWeek;
    }
    let previous = "";
    for (const [abbr, usedWeek] of Object.entries(taken)) {
      if (usedWeek === week) previous = abbr;
    }
    if (previous && previous !== team) delete taken[previous];
    const usedInWeek = taken[team];
    if (usedInWeek !== undefined && usedInWeek !== week) {
      throw new HttpsError("already-exists", "This entry already used that team.");
    }

    // The week is locked by the pick ALREADY STANDING for it, not only by the
    // incoming team's game. Once the standing team has kicked off its result is
    // determined, so the pick cannot be swapped for a team that plays later in
    // the week. Checking only the incoming kickoff let an entry pick a
    // Sunday-early team, lose, then switch to a Monday-night team before
    // closeWeek ran — and survive the week it had already lost.
    if (!admin && previous && previous !== team) {
      let previousLocked: boolean;
      if (asPickMap(data.picks)[weekKey] === previous) {
        // Published already, and publishLockedPicks only publishes at kickoff.
        previousLocked = true;
      } else {
        const previousGames = await tx.get(db.collection("games")
          .where("season", "==", 2026)
          .where("week", "==", week)
          .where("teams", "array-contains", previous)
          .limit(1));
        const previousKickoff = previousGames.docs[0]?.get("kickoffAt")?.toMillis?.();
        // Fail closed: a standing pick whose kickoff cannot be established is
        // treated as locked rather than silently swappable.
        previousLocked = previousKickoff === undefined || previousKickoff <= now;
      }
      if (previousLocked) {
        throw new HttpsError(
          "failed-precondition",
          `Your week ${week} pick has already kicked off and cannot be changed.`
        );
      }
    }

    if (locked) {
      const picks = asPickMap(data.picks);
      const usedTeams = asTeamMap(data.usedTeams);
      const publicPrevious = picks[weekKey];
      if (publicPrevious && publicPrevious !== team && usedTeams[publicPrevious] === week) {
        delete usedTeams[publicPrevious];
      }
      picks[weekKey] = team;
      usedTeams[team] = week;
      tx.update(entryRef, {
        usedTeams,
        picks,
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.delete(privateRef);
      return;
    }

    // An admin may change a pick whose game already kicked off to a team that
    // has not, so this branch can be reached with a published pick standing for
    // the week. Withdraw it: the public reconciliation used to live only in the
    // `locked` branch above, so picks[week] kept the superseded team and
    // usedTeams kept it burned for the rest of the season. publishLockedPicks
    // is additive and never removes a stale usedTeams row, so the entry ended
    // up with two teams mapped to one week.
    const picks = asPickMap(data.picks);
    const usedTeams = asTeamMap(data.usedTeams);
    const publicPrevious = picks[weekKey];
    if (publicPrevious && publicPrevious !== team) {
      delete picks[weekKey];
      if (usedTeams[publicPrevious] === week) delete usedTeams[publicPrevious];
      tx.update(entryRef, {
        picks,
        usedTeams,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    // Future picks stay off the public entry until kickoff.
    tx.set(privateRef, {
      team,
      week,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { entryId, week, team };
});

function isAdminCaller(auth: AuthToken) {
  return auth.token.admin === true;
}

export const recordBuyback = onCall(async (request) => {
  const auth = requireUser(request.auth);
  requireAdmin(auth);
  const entryId = String(request.data?.entryId ?? "");
  if (!entryId) throw new HttpsError("invalid-argument", "Choose an entry.");

  const entryRef = db.collection("entries").doc(entryId);
  await db.runTransaction(async (tx) => {
    const entry = await tx.get(entryRef);
    if (!entry.exists) throw new HttpsError("not-found", "That entry is missing.");
    const data = entry.data() as DocumentData;
    const eliminatedWeek = Number(data.eliminatedWeek);
    if (data.status !== "pendingBuyback" || data.buybackDeclined === true) {
      throw new HttpsError("failed-precondition", "This entry is not waiting on a buyback.");
    }
    if (!Number.isInteger(eliminatedWeek) || eliminatedWeek > BUYBACK_THROUGH_WEEK) {
      throw new HttpsError("failed-precondition", "Buybacks are only available through week 6.");
    }

    const buybacks = Array.isArray(data.buybacks) ? data.buybacks : [];
    buybacks.push({
      eliminatedWeek,
      recordedAt: new Date().toISOString(),
    });
    tx.update(entryRef, {
      status: "active",
      eliminatedWeek: null,
      buybackDeclined: false,
      buybackCount: Number(data.buybackCount ?? 0) + 1,
      buybacks,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { entryId };
});

const ODDS_REFRESH_MS = 12 * 60 * 60 * 1000;

async function syncSeasonFromSecrets(includeOdds: boolean) {
  const publishedPicks = await publishLockedPicks();
  const result = await runSeasonSync(apiSportsKey.value(), includeOdds ? oddsApiKey.value() : "");
  return { ...result, publishedPicks };
}

export const syncSeason = onCall({ secrets: [apiSportsKey, oddsApiKey] }, async (request) => {
  const auth = requireUser(request.auth);
  requireAdmin(auth);
  return syncSeasonFromSecrets(true);
});

export const syncSeasonScheduled = onSchedule({
  schedule: "every 60 minutes",
  secrets: [apiSportsKey, oddsApiKey],
}, async () => {
  const pool = await db.collection("pool").doc("2026").get();
  const lastOdds = pool.get("oddsSyncedAt")?.toMillis?.() ?? 0;
  const includeOdds = Date.now() - lastOdds > ODDS_REFRESH_MS;
  await syncSeasonFromSecrets(includeOdds);
});

export const gradeWeeks = onCall(async (request) => {
  const auth = requireUser(request.auth);
  requireAdmin(auth);
  // Defaulted to true, which meant a bare call rewrote terminal status and
  // buyback history for the whole pool. Require the caller to say so.
  const apply = request.data?.apply === true;
  return gradeImportedWeeks(apply);
});

// Reflect a user's commissioner status onto every entry they own, so the Pool
// board can show the badge from server data instead of a client name list.
// This is display only; authorization remains the Auth `admin` claim.
async function setEntriesCommissionerFlag(uid: string, isCommissioner: boolean): Promise<void> {
  if (!uid) return;
  const entries = await db.collection("entries").where("playerId", "==", uid).get();
  if (entries.empty) return;
  const batch = db.batch();
  let changed = 0;
  for (const doc of entries.docs) {
    if (doc.get("isCommissioner") !== isCommissioner) {
      batch.update(doc.ref, { isCommissioner });
      changed += 1;
    }
  }
  if (changed > 0) await batch.commit();
}

async function commissionerEmails(): Promise<Set<string>> {
  const allowed = new Set(BOOTSTRAP_COMMISSIONER_EMAILS.map((email) => email.toLowerCase()));
  const pool = await db.collection("pool").doc("2026").get();
  const extra = pool.get("commissionerEmails");
  if (Array.isArray(extra)) {
    for (const email of extra) {
      if (typeof email === "string" && email.includes("@")) allowed.add(email.trim().toLowerCase());
    }
  }
  return allowed;
}

export const syncCommissionerClaim = onCall(async (request) => {
  const auth = requireUser(request.auth);
  const email = String(auth.token.email ?? "").trim().toLowerCase();
  const allowed = await commissionerEmails();
  if (!email || !allowed.has(email)) {
    return { admin: auth.token.admin === true };
  }
  if (auth.token.admin !== true) {
    const user = await getAuth().getUser(auth.uid);
    await getAuth().setCustomUserClaims(auth.uid, { ...(user.customClaims ?? {}), admin: true });
  }
  await setEntriesCommissionerFlag(auth.uid, true);
  return { admin: true };
});

export const addCommissionerEmail = onCall(async (request) => {
  const auth = requireUser(request.auth);
  requireAdmin(auth);
  const email = String(request.data?.email ?? "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Enter an email address.");
  }
  const ref = db.collection("pool").doc("2026");
  await db.runTransaction(async (tx) => {
    const pool = await tx.get(ref);
    const current = Array.isArray(pool.get("commissionerEmails")) ? pool.get("commissionerEmails") : [];
    const emails = current.filter((item: unknown): item is string => typeof item === "string");
    if (!emails.includes(email)) emails.push(email);
    tx.set(ref, { commissionerEmails: emails }, { merge: true });
  });
  // If this person has already signed in and claimed entries, flag them now.
  // Otherwise syncCommissionerClaim handles it the next time they sign in.
  try {
    const user = await getAuth().getUserByEmail(email);
    await setEntriesCommissionerFlag(user.uid, true);
  } catch {
    // No account for that email yet; nothing to flag.
  }
  return { email };
});

export const closeWeek = onCall({ timeoutSeconds: 120 }, async (request) => {
  const auth = requireUser(request.auth);
  requireAdmin(auth);
  const week = Number(request.data?.week);
  if (!Number.isInteger(week) || week < 1 || week > 18) {
    throw new HttpsError("invalid-argument", "Choose a week.");
  }
  try {
    return await closePoolWeek(week, request.data?.apply === true);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not close that week.";
    throw new HttpsError("failed-precondition", message);
  }
});

export const declineBuyback = onCall(async (request) => {
  const auth = requireUser(request.auth);
  requireAdmin(auth);
  const entryId = String(request.data?.entryId ?? "");
  if (!entryId) throw new HttpsError("invalid-argument", "Choose an entry.");

  const entryRef = db.collection("entries").doc(entryId);
  await db.runTransaction(async (tx) => {
    const entry = await tx.get(entryRef);
    if (!entry.exists) throw new HttpsError("not-found", "That entry is missing.");
    if (entry.get("status") !== "pendingBuyback") {
      throw new HttpsError("failed-precondition", "This entry is not waiting on a buyback.");
    }
    tx.update(entryRef, {
      status: "eliminated",
      buybackDeclined: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { entryId };
});
