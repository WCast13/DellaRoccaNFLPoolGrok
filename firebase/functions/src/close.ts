import { FieldValue, getFirestore, type DocumentData, type DocumentReference } from "firebase-admin/firestore";
import { publishLockedPicks } from "./picks";

const SEASON = 2026;
const BUYBACK_THROUGH_WEEK = 6;

export interface CloseWeekReport {
  week: number;
  missingPicks: number;
  losses: number;
  wins: number;
  ungraded: number;
  updated: number;
  lapsedBuybacks: number;
  applied: boolean;
  examples: string[];
}

function asPickMap(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object") return {};
  const map: Record<string, string> = {};
  for (const [week, team] of Object.entries(value as Record<string, unknown>)) {
    if (typeof team === "string" && team.length > 0) map[week] = team;
  }
  return map;
}

function asTeamMap(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object") return {};
  const map: Record<string, number> = {};
  for (const [team, week] of Object.entries(value as Record<string, unknown>)) {
    if (typeof week === "number") map[team] = week;
  }
  return map;
}

interface StoredGame {
  status: string;
  homeAbbr: string;
  awayAbbr: string;
  homeScore: number | null;
  awayScore: number | null;
  kickoff: number;
}

function outcome(team: string, game: StoredGame | undefined): "win" | "loss" | "pending" | "missing" {
  if (!game) return "missing";
  if (game.status !== "final") return "pending";
  const teamIsHome = game.homeAbbr === team;
  const teamIsAway = game.awayAbbr === team;
  if (!teamIsHome && !teamIsAway) return "missing";
  if (game.homeScore === null || game.awayScore === null) return "pending";
  const teamScore = teamIsHome ? game.homeScore : game.awayScore;
  const opponentScore = teamIsHome ? game.awayScore : game.homeScore;
  return teamScore > opponentScore ? "win" : "loss";
}

/// Grades every week whose games have all kicked off and that the pool has not
/// yet closed through, in order. This is what the hourly sync calls; there is
/// no manual close-week step.
///
/// Idempotent: closePoolWeek skips entries already graded, and a week with a
/// game still pending is re-run each hour until it is final. Weeks grade
/// strictly in order and stop at the first that still has a game to play —
/// closedThroughWeek is a single high-water mark, so grading week 6 ahead of
/// a postponed week-5 game would mark 5 as done and never return to it.
export async function gradeClosedWeeks(now = Date.now()): Promise<CloseWeekReport[]> {
  const db = getFirestore();
  const pool = await db.collection("pool").doc(String(SEASON)).get();
  const closedThrough = Number(pool.get("closedThroughWeek"));
  const firstOpen = (Number.isInteger(closedThrough) ? closedThrough : 0) + 1;

  const games = await db.collection("games").where("season", "==", SEASON).get();
  const lastKickoffByWeek = new Map<number, number>();
  for (const doc of games.docs) {
    const week = Number(doc.get("week"));
    const kickoff = doc.get("kickoffAt")?.toMillis?.() ?? 0;
    if (!Number.isInteger(week) || kickoff <= 0) continue;
    lastKickoffByWeek.set(week, Math.max(lastKickoffByWeek.get(week) ?? 0, kickoff));
  }

  const reports: CloseWeekReport[] = [];
  for (let week = firstOpen; week <= 18; week += 1) {
    const lastKickoff = lastKickoffByWeek.get(week);
    if (lastKickoff === undefined || lastKickoff > now) break;
    try {
      reports.push(await closePoolWeek(week, true, now));
    } catch (error) {
      // Leave the rest for the next run rather than failing the whole sync.
      console.error(`gradeClosedWeeks: week ${week} failed`, error);
      break;
    }
  }
  return reports;
}

export async function closePoolWeek(week: number, apply: boolean, now = Date.now()): Promise<CloseWeekReport> {
  const db = getFirestore();
  if (apply) await publishLockedPicks(now);

  const gameSnap = await db.collection("games").where("season", "==", SEASON).get();
  const games = new Map<string, StoredGame>();
  const weekGames: StoredGame[] = [];
  for (const doc of gameSnap.docs) {
    const data = doc.data();
    if (Number(data.week) !== week) continue;
    const game: StoredGame = {
      status: String(data.status ?? ""),
      homeAbbr: String(data.homeAbbr ?? ""),
      awayAbbr: String(data.awayAbbr ?? ""),
      homeScore: typeof data.homeScore === "number" ? data.homeScore : null,
      awayScore: typeof data.awayScore === "number" ? data.awayScore : null,
      kickoff: doc.get("kickoffAt")?.toMillis?.() ?? 0,
    };
    weekGames.push(game);
    if (game.homeAbbr) games.set(game.homeAbbr, game);
    if (game.awayAbbr) games.set(game.awayAbbr, game);
  }
  if (weekGames.length === 0) {
    throw new Error(`Week ${week} has no games.`);
  }
  const stillOpen = weekGames.filter((game) => game.kickoff > now);
  if (stillOpen.length > 0) {
    throw new Error(`Week ${week} still has a game that has not kicked off.`);
  }

  const [entries, privatePicks] = await Promise.all([
    db.collection("entries").get(),
    db.collectionGroup("privatePicks").get(),
  ]);
  const privateByEntry = new Map<string, string>();
  for (const doc of privatePicks.docs) {
    const pickedWeek = Number(doc.get("week") ?? doc.id);
    const team = String(doc.get("team") ?? "");
    const entryId = doc.ref.parent.parent?.id;
    if (pickedWeek === week && team && entryId) privateByEntry.set(entryId, team);
  }

  const report: CloseWeekReport = {
    week,
    missingPicks: 0,
    losses: 0,
    wins: 0,
    ungraded: 0,
    updated: 0,
    lapsedBuybacks: 0,
    applied: apply,
    examples: [],
  };

  let batch = db.batch();
  let writes = 0;
  const flush = async (force = false) => {
    if (!apply || writes === 0 || (!force && writes < 400)) return;
    await batch.commit();
    batch = db.batch();
    writes = 0;
  };

  for (const doc of entries.docs) {
    const data = doc.data() as DocumentData;
    const picks = asPickMap(data.picks);
    const team = privateByEntry.get(doc.id) ?? picks[String(week)] ?? "";
    const label = String(data.label ?? doc.id);
    const buybackRows = Array.isArray(data.buybacks) ? data.buybacks : [];
    const rowForWeek = (target: number) =>
      buybackRows.find(
        (row) => Number((row as DocumentData)?.eliminatedWeek) === target
      ) as DocumentData | undefined;

    // A buyback elected after a loss in week N is confirmed by a pick for week
    // N+1, so closing week N+1 is where it resolves. Picked: the buyback stands
    // and the pick grades normally below. Not picked: the entry never completed
    // the buyback and is simply out — NOT a loss, which at week N+1 <= 6 would
    // otherwise hand it a second buyback.
    const eliminatedWeek = Number(data.eliminatedWeek);
    const decisionWeek = Number.isInteger(eliminatedWeek) ? eliminatedWeek + 1 : 0;
    let confirmFields: DocumentData | null = null;
    if (decisionWeek === week && data.buybackDeclined !== true) {
      const existing = rowForWeek(eliminatedWeek);
      // A confirmed row means an earlier close already resolved this decision.
      // Without the check, a re-close would see the cleared election and lapse
      // an entry that had legitimately bought back and picked.
      const alreadyResolved = existing !== undefined && existing.provisional !== true;
      if (!alreadyResolved) {
        if (data.buybackElection === "in" && team) {
          // Held, not written: merged into this entry's single write below so
          // the same document is never written twice in one batch.
          confirmFields = confirmedBuybackFields(buybackRows, eliminatedWeek);
        } else {
          if (report.examples.length < 12) {
            report.examples.push(
              data.buybackElection === "in"
                ? `${label}: bought back but made no week ${week} pick`
                : `${label}: did not buy back after week ${eliminatedWeek}`
            );
          }
          await resolveLapsedBuyback(doc.ref, buybackRows, eliminatedWeek);
          continue;
        }
      }
    }

    if (data.status !== "active") continue;

    // An entry that already took its loss for THIS week and bought back must
    // not be graded again. Re-closing a week is normal operation: the
    // commissioner closes Sunday night with MNF unfinished (so those entries
    // land in `ungraded` and closedThroughWeek does not advance), records
    // buybacks Monday, then re-closes Tuesday to grade the MNF entries. By then
    // status is "active" again, so the check above no longer skips them, and
    // markLoss already wrote picks[week] — so the stale team was re-found,
    // re-graded a loss, and the paid buyback was nullified.
    if (rowForWeek(week) !== undefined) {
      if (report.examples.length < 12) {
        report.examples.push(`${label}: already bought back for week ${week}`);
      }
      continue;
    }

    if (!team) {
      report.missingPicks += 1;
      if (report.examples.length < 12) report.examples.push(`${label}: no pick`);
      await markLoss(doc.ref, undefined, undefined, confirmFields);
      continue;
    }

    const result = outcome(team, games.get(team));
    if (result === "win") {
      report.wins += 1;
      await applyFields(doc.ref, confirmFields);
      continue;
    }
    if (result === "pending" || result === "missing") {
      report.ungraded += 1;
      if (report.examples.length < 12) report.examples.push(`${label}: ${team} is not final`);
      await applyFields(doc.ref, confirmFields);
      continue;
    }

    report.losses += 1;
    if (report.examples.length < 12) report.examples.push(`${label}: ${team} lost`);
    await markLoss(doc.ref, team, data, confirmFields);
  }
  await flush(true);

  if (apply && report.ungraded === 0) {
    // Monotonic: the stepper permits any week, so a plain assignment moved the
    // marker backwards when an earlier week was re-closed later in the season.
    const poolRef = db.collection("pool").doc(String(SEASON));
    const stored = Number((await poolRef.get()).get("closedThroughWeek"));
    await poolRef.set({
      closedThroughWeek: Number.isInteger(stored) ? Math.max(stored, week) : week,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  return report;

  /// Elected a buyback but never made the pick it was conditional on, or never
  /// elected at all: out for the season, and nothing owed, since the entry
  /// never actually played.
  async function resolveLapsedBuyback(
    ref: DocumentReference,
    rows: unknown[],
    eliminatedWeek: number
  ) {
    report.lapsedBuybacks += 1;
    report.updated += 1;
    if (!apply) return;
    const buybacks = rows.filter(
      (row) =>
        !(Number((row as DocumentData)?.eliminatedWeek) === eliminatedWeek
          && (row as DocumentData)?.provisional === true)
    );
    batch.set(ref, {
      status: "eliminated",
      buybackDeclined: true,
      buybackElection: FieldValue.delete(),
      buybackUnpaid: false,
      buybacks,
      buybackCount: buybacks.length,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    writes += 1;
    await flush();
  }

  /// Fields that confirm an elected buyback: drops the provisional marker so a
  /// later close cannot withdraw it, and clears the election so the next
  /// knockout starts clean. buybackUnpaid is left alone for collection.
  function confirmedBuybackFields(rows: unknown[], eliminatedWeek: number): DocumentData {
    const buybacks = rows.map((row) => {
      const typed = row as DocumentData;
      if (Number(typed?.eliminatedWeek) === eliminatedWeek && typed?.provisional === true) {
        const confirmed: DocumentData = { ...typed, confirmedAt: new Date().toISOString() };
        delete confirmed.provisional;
        return confirmed;
      }
      return row;
    });
    return {
      buybackElection: FieldValue.delete(),
      buybacks,
      buybackCount: buybacks.length,
    };
  }

  async function applyFields(ref: DocumentReference, fields: DocumentData | null) {
    if (!apply || !fields) return;
    batch.set(ref, { ...fields, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    writes += 1;
    await flush();
  }

  async function markLoss(
    ref: DocumentReference,
    team?: string,
    data?: DocumentData,
    confirmFields: DocumentData | null = null
  ) {
    report.updated += 1;
    if (!apply) return;
    const throughBuyback = week <= BUYBACK_THROUGH_WEEK;
    const update: Record<string, unknown> = {
      // Merged in so a confirmed buyback and the new knockout it precedes are
      // one write. A new loss also clears any election left over.
      ...(confirmFields ?? {}),
      buybackElection: FieldValue.delete(),
      status: throughBuyback ? "pendingBuyback" : "eliminated",
      eliminatedWeek: week,
      buybackDeclined: !throughBuyback,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (team && data) {
      const picks = asPickMap(data.picks);
      const usedTeams = asTeamMap(data.usedTeams);
      picks[String(week)] = team;
      usedTeams[team] = week;
      update.picks = picks;
      update.usedTeams = usedTeams;
    }
    batch.set(ref, update, { merge: true });
    writes += 1;
    if (team) {
      batch.delete(ref.collection("privatePicks").doc(String(week)));
      writes += 1;
    }
    await flush();
  }
}
