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
    if (data.status !== "active") continue;
    const picks = asPickMap(data.picks);
    const team = privateByEntry.get(doc.id) ?? picks[String(week)] ?? "";
    const label = String(data.label ?? doc.id);

    // An entry that already took its loss for this week and bought back must
    // not be graded again. Re-closing a week is normal operation: the
    // commissioner closes Sunday night with MNF unfinished (so those entries
    // land in `ungraded` and closedThroughWeek does not advance), records
    // buybacks Monday, then re-closes Tuesday to grade the MNF entries. By then
    // status is "active" again, so the check above no longer skips them, and
    // markLoss already wrote picks[week] — so the stale team was re-found,
    // re-graded a loss, and the paid buyback was nullified.
    const boughtBackThisWeek = (Array.isArray(data.buybacks) ? data.buybacks : [])
      .some((row) => Number((row as DocumentData)?.eliminatedWeek) === week);
    if (boughtBackThisWeek) {
      if (report.examples.length < 12) {
        report.examples.push(`${label}: already bought back for week ${week}`);
      }
      continue;
    }

    if (!team) {
      report.missingPicks += 1;
      if (report.examples.length < 12) report.examples.push(`${label}: no pick`);
      await markLoss(doc.ref);
      continue;
    }

    const result = outcome(team, games.get(team));
    if (result === "win") {
      report.wins += 1;
      continue;
    }
    if (result === "pending" || result === "missing") {
      report.ungraded += 1;
      if (report.examples.length < 12) report.examples.push(`${label}: ${team} is not final`);
      continue;
    }

    report.losses += 1;
    if (report.examples.length < 12) report.examples.push(`${label}: ${team} lost`);
    await markLoss(doc.ref, team, data);
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

  async function markLoss(ref: DocumentReference, team?: string, data?: DocumentData) {
    report.updated += 1;
    if (!apply) return;
    const throughBuyback = week <= BUYBACK_THROUGH_WEEK;
    const update: Record<string, unknown> = {
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
