import { FieldValue, getFirestore } from "firebase-admin/firestore";

const SEASON = 2026;

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

/** Copy private picks onto the public entry once that game has kicked off. */
export async function publishLockedPicks(now = Date.now()): Promise<number> {
  const db = getFirestore();
  const games = await db.collection("games").where("season", "==", SEASON).get();
  const kickoffByTeamWeek = new Map<string, number>();
  for (const doc of games.docs) {
    const week = Number(doc.get("week"));
    const kickoff = doc.get("kickoffAt")?.toMillis?.() ?? 0;
    if (!Number.isInteger(week) || kickoff <= 0) continue;
    for (const team of [doc.get("homeAbbr"), doc.get("awayAbbr")]) {
      if (typeof team === "string" && team.length > 0) {
        kickoffByTeamWeek.set(`${week}|${team}`, kickoff);
      }
    }
  }

  const pending = await db.collectionGroup("privatePicks").get();
  let published = 0;
  for (const pickDoc of pending.docs) {
    const week = Number(pickDoc.get("week") ?? pickDoc.id);
    const team = String(pickDoc.get("team") ?? "");
    const kickoff = kickoffByTeamWeek.get(`${week}|${team}`) ?? 0;
    if (!team || kickoff <= 0 || kickoff > now) continue;
    const entryRef = pickDoc.ref.parent.parent;
    if (!entryRef) continue;

    const wrote = await db.runTransaction(async (tx) => {
      const entry = await tx.get(entryRef);
      const fresh = await tx.get(pickDoc.ref);
      if (!entry.exists || !fresh.exists) return false;
      const currentTeam = String(fresh.get("team") ?? "");
      const currentWeek = Number(fresh.get("week") ?? fresh.ref.id);
      if (currentTeam !== team || currentWeek !== week) return false;
      const picks = asPickMap(entry.get("picks"));
      const usedTeams = asTeamMap(entry.get("usedTeams"));
      const usedWeek = usedTeams[currentTeam];
      if (usedWeek !== undefined && usedWeek !== currentWeek) return false;
      picks[String(currentWeek)] = currentTeam;
      usedTeams[currentTeam] = currentWeek;
      tx.update(entryRef, {
        picks,
        usedTeams,
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.delete(fresh.ref);
      return true;
    });
    if (wrote) published += 1;
  }
  return published;
}
