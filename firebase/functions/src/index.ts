import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

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
      return { error: "That entry is missing.", code: "not-found" as const };
    }

    const owner = entry.get("playerId");
    if (typeof owner === "string" && owner.length > 0 && owner !== auth.uid) {
      return { error: "That entry is already on another account.", code: "already-exists" as const };
    }

    tx.set(attemptsRef, { count: 0, windowStart: FieldValue.serverTimestamp() }, { merge: true });
    tx.update(entryRef, { playerId: auth.uid, claimedAt: FieldValue.serverTimestamp() });
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
  const gameQuery = db.collection("games")
    .where("season", "==", 2026)
    .where("week", "==", week)
    .where("teams", "array-contains", team)
    .limit(1);

  await db.runTransaction(async (tx) => {
    const entry = await tx.get(entryRef);
    const games = await tx.get(gameQuery);
    if (!entry.exists) throw new HttpsError("not-found", "That entry is missing.");

    const data = entry.data() as DocumentData;
    const admin = isAdminCaller(auth);
    if (!admin && data.playerId !== auth.uid) {
      throw new HttpsError("permission-denied", "That entry is not on this account.");
    }
    if (data.status !== "active") {
      throw new HttpsError("failed-precondition", "This entry is knocked out.");
    }

    const game = games.docs[0];
    if (!game) throw new HttpsError("failed-precondition", "That team does not play this week.");
    const kickoff = game.get("kickoffAt")?.toMillis?.() ?? 0;
    if (!admin && kickoff <= Date.now()) {
      throw new HttpsError("failed-precondition", "That game has already kicked off.");
    }

    const usedTeams = asTeamMap(data.usedTeams);
    const picks = asPickMap(data.picks);
    const weekKey = String(week);
    const previous = picks[weekKey];
    if (previous && previous !== team && usedTeams[previous] === week) {
      delete usedTeams[previous];
    }
    const usedInWeek = usedTeams[team];
    if (usedInWeek !== undefined && usedInWeek !== week) {
      throw new HttpsError("already-exists", "This entry already used that team.");
    }

    usedTeams[team] = week;
    picks[weekKey] = team;
    tx.update(entryRef, {
      usedTeams,
      picks,
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
