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
function hasEvidencePastGradedWeeks(data: DocumentData, picks: Record<string, string>): boolean {
  for (const week of Object.keys(picks)) {
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

/// Weeks whose stored buyback row is real — recorded by a commissioner or
/// confirmed by a pick — as opposed to a provisional row from an election the
/// player has not yet followed with a pick.
function recordedBuybackWeeks(data: DocumentData): Set<number> {
  const weeks = new Set<number>();
  for (const row of Array.isArray(data.buybacks) ? data.buybacks : []) {
    const record = row as DocumentData;
    const week = Number(record?.eliminatedWeek);
    if (Number.isInteger(week) && record?.provisional !== true) weeks.add(week);
  }
  return weeks;
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
  const [gameSnap, entrySnap, privateSnap] = await Promise.all([
    db.collection("games").where("season", "==", SEASON).get(),
    db.collection("entries").get(),
    // A pick whose game has not kicked off lives only here. Reading the public
    // map alone graded every such entry as having made no pick.
    db.collectionGroup("privatePicks").get(),
  ]);

  const games = new Map<string, StoredGame>();
  const weeksWithGames = new Set<number>();
  const weeksStillPlaying = new Set<number>();
  for (const doc of gameSnap.docs) {
    const data = doc.data();
    const week = Number(data.week);
    if (!Number.isInteger(week) || week > GRADE_THROUGH_WEEK) continue;
    const game: StoredGame = {
      week,
      status: String(data.status ?? ""),
      homeAbbr: String(data.homeAbbr ?? ""),
      awayAbbr: String(data.awayAbbr ?? ""),
      homeScore: typeof data.homeScore === "number" ? data.homeScore : null,
      awayScore: typeof data.awayScore === "number" ? data.awayScore : null,
    };
    weeksWithGames.add(week);
    if (game.status !== "final") weeksStillPlaying.add(week);
    if (game.homeAbbr) games.set(`${week}|${game.homeAbbr}`, game);
    if (game.awayAbbr) games.set(`${week}|${game.awayAbbr}`, game);
  }

  // The latest week this grader may treat as closed: it and every week before
  // it have all their games final. A loss there leaves the buyback decision
  // open. A loss in an earlier week with no pick for the week after it has
  // lapsed — the same resolution closePoolWeek applies when week N+1 closes.
  let closedThrough = 0;
  while (
    closedThrough < GRADE_THROUGH_WEEK
    && weeksWithGames.has(closedThrough + 1)
    && !weeksStillPlaying.has(closedThrough + 1)
  ) {
    closedThrough += 1;
  }

  const privateByEntry = new Map<string, Record<string, string>>();
  for (const doc of privateSnap.docs) {
    const week = Number(doc.get("week") ?? doc.id);
    const team = String(doc.get("team") ?? "");
    const entryId = doc.ref.parent.parent?.id;
    if (!entryId || !team || !Number.isInteger(week)) continue;
    const map = privateByEntry.get(entryId) ?? {};
    map[String(week)] = team;
    privateByEntry.set(entryId, map);
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
    const picks = { ...asPickMap(data.picks), ...(privateByEntry.get(doc.id) ?? {}) };
    // The entry query is unfiltered, so this runs over the whole pool. Leave
    // anything whose history extends past week 3 completely untouched.
    if (hasEvidencePastGradedWeeks(data, picks)) {
      report.skippedLaterEvidence += 1;
      continue;
    }

    const storedStatus = String(data.status ?? "");
    const storedEliminatedWeek = Number(data.eliminatedWeek);
    // A decision the player is still making in the app, for a week that has
    // not closed. The close resolves it; this grader stays out.
    if (data.buybackElection != null && storedEliminatedWeek === closedThrough) {
      report.skipped += 1;
      continue;
    }
    const recorded = recordedBuybackWeeks(data);

    let status = "active";
    let eliminatedWeek: number | null = null;
    let buybackDeclined = false;
    const buybacks: Array<{ eliminatedWeek: number; boughtBackBeforeWeek: number }> = [];
    let skip = false;

    for (let week = 1; week <= GRADE_THROUGH_WEEK; week += 1) {
      const team = picks[String(week)];
      let lost: boolean;
      if (!team) {
        // A missing pick is a loss once the week has closed — the same loss a
        // beaten team takes, with the same buyback — never a declined buyback
        // on its own. Before the week closes nothing can be said about it.
        if (week > closedThrough) {
          skip = true;
          break;
        }
        lost = true;
      } else {
        const result = outcome(team, games.get(`${week}|${team}`));
        if (result === "pending" || result === "missing") {
          skip = true;
          break;
        }
        lost = result === "loss";
      }
      if (!lost) continue;

      const boughtBackBeforeWeek = nextPickedWeek(picks, week);
      if (boughtBackBeforeWeek) {
        buybacks.push({ eliminatedWeek: week, boughtBackBeforeWeek });
        continue;
      }
      // recordBuyback puts the entry back in before it has picked again; that
      // row is the record that the player paid, and must not read as a knockout.
      if (recorded.has(week)) continue;

      eliminatedWeek = week;
      // declineBuyback, or the lapse at the week N+1 close, already settled
      // this knockout. Re-opening the decision would undo that.
      const settled = storedStatus === "eliminated"
        && data.buybackDeclined === true
        && storedEliminatedWeek === week;
      if (week === closedThrough && week <= BUYBACK_THROUGH_WEEK && !settled) {
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
    // Union with what is already stored rather than replacing it. `buybacks`
    // above is a fresh array built only from weeks 1-3 inference, so writing it
    // directly erased rows written by recordBuyback — the only record that a
    // player actually paid, and unrecoverable once gone. Stored rows win on a
    // week collision because they carry recordedAt.
    const storedBuybacks = Array.isArray(data.buybacks) ? data.buybacks : [];
    const storedWeeks = new Set(
      storedBuybacks
        .map((row) => Number((row as DocumentData)?.eliminatedWeek))
        .filter((week) => Number.isInteger(week))
    );
    const mergedBuybacks = [
      ...storedBuybacks,
      ...buybacks.filter((row) => !storedWeeks.has(row.eliminatedWeek)),
    ];
    batch.set(doc.ref, {
      status,
      eliminatedWeek,
      buybackDeclined,
      buybacks: mergedBuybacks,
      buybackCount: mergedBuybacks.length,
      gradedThroughWeek: GRADE_THROUGH_WEEK,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    writes += 1;
    await flush();
  }
  await flush(true);
  return report;
}
