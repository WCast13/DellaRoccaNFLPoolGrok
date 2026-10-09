import { FieldValue, getFirestore, type DocumentData } from "firebase-admin/firestore";

const SEASON = 2026;
const GRADE_THROUGH_WEEK = 3;
const BUYBACK_THROUGH_WEEK = 6;

interface StoredGame {
  week: number;
  status: string;
  homeAbbr: string;
  awayAbbr: string;
  homeScore: number | null;
  awayScore: number | null;
}

export interface GradeReport {
  active: number;
  pendingBuyback: number;
  eliminated: number;
  buybacksRecorded: number;
  changed: number;
  skipped: number;
  skippedLaterEvidence: number;
  disagreements: Array<{ label: string; stored: string; graded: string }>;
}

function asPickMap(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object") return {};
  const map: Record<string, string> = {};
  for (const [week, team] of Object.entries(value as Record<string, unknown>)) {
    if (typeof team === "string" && team.length > 0) map[week] = team;
  }
  return map;
}

/// True when the entry carries evidence of play past the weeks this grader can
/// see. Weeks 1-3 alone cannot describe such an entry, so the grader must not
/// rewrite its status: an entry that won weeks 1-3 and lost week 8 would be
/// recomputed as active and put back in the pool.
function hasEvidencePastGradedWeeks(data: DocumentData): boolean {
  for (const week of Object.keys(asPickMap(data.picks))) {
    if (Number(week) > GRADE_THROUGH_WEEK) return true;
  }
  const storedEliminated = Number(data.eliminatedWeek);
  if (Number.isInteger(storedEliminated) && storedEliminated > GRADE_THROUGH_WEEK) return true;
  const storedGraded = Number(data.gradedThroughWeek);
  if (Number.isInteger(storedGraded) && storedGraded > GRADE_THROUGH_WEEK) return true;
  for (const row of Array.isArray(data.buybacks) ? data.buybacks : []) {
    const week = Number((row as DocumentData)?.eliminatedWeek);
    if (Number.isInteger(week) && week > GRADE_THROUGH_WEEK) return true;
  }
  return false;
}

function nextPickedWeek(picks: Record<string, string>, after: number): number | null {
  for (let week = after + 1; week <= GRADE_THROUGH_WEEK; week += 1) {
    if (picks[String(week)]) return week;
  }
  return null;
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

export async function gradeImportedWeeks(apply: boolean): Promise<GradeReport> {
  const db = getFirestore();
  const [gameSnap, entrySnap] = await Promise.all([
    db.collection("games").where("season", "==", SEASON).get(),
    db.collection("entries").get(),
  ]);

  const games = new Map<string, StoredGame>();
  for (const doc of gameSnap.docs) {
    const data = doc.data();
    const week = Number(data.week);
    if (week > GRADE_THROUGH_WEEK) continue;
    const game: StoredGame = {
      week,
      status: String(data.status ?? ""),
      homeAbbr: String(data.homeAbbr ?? ""),
      awayAbbr: String(data.awayAbbr ?? ""),
      homeScore: typeof data.homeScore === "number" ? data.homeScore : null,
      awayScore: typeof data.awayScore === "number" ? data.awayScore : null,
    };
    if (game.homeAbbr) games.set(`${week}|${game.homeAbbr}`, game);
    if (game.awayAbbr) games.set(`${week}|${game.awayAbbr}`, game);
  }

  const report: GradeReport = {
    active: 0,
    pendingBuyback: 0,
    eliminated: 0,
    buybacksRecorded: 0,
    changed: 0,
    skipped: 0,
    skippedLaterEvidence: 0,
    disagreements: [],
  };

  let batch = db.batch();
  let writes = 0;
  const flush = async (force = false) => {
    if (!apply || writes === 0 || (!force && writes < 400)) return;
    await batch.commit();
    batch = db.batch();
    writes = 0;
  };

  for (const doc of entrySnap.docs) {
    const data = doc.data() as DocumentData;
    // The entry query is unfiltered, so this runs over the whole pool. Leave
    // anything whose history extends past week 3 completely untouched.
    if (hasEvidencePastGradedWeeks(data)) {
      report.skippedLaterEvidence += 1;
      continue;
    }
    const picks = asPickMap(data.picks);
    let status = "active";
    let eliminatedWeek: number | null = null;
    let buybackDeclined = false;
    const buybacks: Array<{ eliminatedWeek: number; boughtBackBeforeWeek: number }> = [];
    let skip = false;

    for (let week = 1; week <= GRADE_THROUGH_WEEK; week += 1) {
      const team = picks[String(week)];
      if (!team) {
        status = "eliminated";
        buybackDeclined = true;
        if (eliminatedWeek === null) eliminatedWeek = week;
        break;
      }
      const result = outcome(team, games.get(`${week}|${team}`));
      if (result === "pending" || result === "missing") {
        skip = true;
        break;
      }
      if (result === "win") continue;
      const boughtBackBeforeWeek = nextPickedWeek(picks, week);
      if (boughtBackBeforeWeek) {
        buybacks.push({ eliminatedWeek: week, boughtBackBeforeWeek });
        continue;
      }
      eliminatedWeek = week;
      if (week < GRADE_THROUGH_WEEK) {
        status = "eliminated";
        buybackDeclined = true;
      } else if (week <= BUYBACK_THROUGH_WEEK) {
        status = "pendingBuyback";
        buybackDeclined = false;
      } else {
        status = "eliminated";
        buybackDeclined = true;
      }
      break;
    }

    if (skip) {
      report.skipped += 1;
      continue;
    }

    if (status === "active") report.active += 1;
    else if (status === "pendingBuyback") report.pendingBuyback += 1;
    else report.eliminated += 1;
    report.buybacksRecorded += buybacks.length;

    const storedStatus = String(data.status ?? "");
    if (storedStatus !== status) {
      report.changed += 1;
      if (report.disagreements.length < 30) {
        report.disagreements.push({
          label: String(data.label ?? doc.id),
          stored: storedStatus,
          graded: status,
        });
      }
    }

    if (!apply) continue;
    batch.set(doc.ref, {
      status,
      eliminatedWeek,
      buybackDeclined,
      buybacks,
      buybackCount: buybacks.length,
      gradedThroughWeek: GRADE_THROUGH_WEEK,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    writes += 1;
    await flush();
  }
  await flush(true);
  return report;
}
