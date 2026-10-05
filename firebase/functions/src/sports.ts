import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";

const SEASON = 2026;
const API_SPORTS_LEAGUE = 1;
const API_SPORTS_BASE = "https://v1.american-football.api-sports.io";
const ODDS_BASE = "https://api.the-odds-api.com/v4/sports/americanfootball_nfl/odds";

const TEAM_ABBREVIATIONS: Record<string, string> = {
  "Arizona Cardinals": "ARI",
  "Atlanta Falcons": "ATL",
  "Baltimore Ravens": "BAL",
  "Buffalo Bills": "BUF",
  "Carolina Panthers": "CAR",
  "Chicago Bears": "CHI",
  "Cincinnati Bengals": "CIN",
  "Cleveland Browns": "CLE",
  "Dallas Cowboys": "DAL",
  "Denver Broncos": "DEN",
  "Detroit Lions": "DET",
  "Green Bay Packers": "GB",
  "Houston Texans": "HOU",
  "Indianapolis Colts": "IND",
  "Jacksonville Jaguars": "JAX",
  "Kansas City Chiefs": "KC",
  "Las Vegas Raiders": "LV",
  "Los Angeles Chargers": "LAC",
  "Los Angeles Rams": "LAR",
  "Miami Dolphins": "MIA",
  "Minnesota Vikings": "MIN",
  "New England Patriots": "NE",
  "New Orleans Saints": "NO",
  "New York Giants": "NYG",
  "New York Jets": "NYJ",
  "Philadelphia Eagles": "PHI",
  "Pittsburgh Steelers": "PIT",
  "San Francisco 49ers": "SF",
  "Seattle Seahawks": "SEA",
  "Tampa Bay Buccaneers": "TB",
  "Tennessee Titans": "TEN",
  "Washington Commanders": "WAS",
};

export interface SeasonSyncResult {
  teams: number;
  games: number;
  spreads: number;
  unmatchedTeams: string[];
}

interface ApiTeam {
  id?: number;
  name?: string;
  logo?: string;
}

interface ApiGame {
  game?: {
    id?: number;
    stage?: string;
    week?: string | number;
    date?: { timestamp?: number };
    status?: { short?: string };
  };
  teams?: { home?: ApiTeam; away?: ApiTeam };
  scores?: {
    home?: { total?: number | null };
    away?: { total?: number | null };
  };
}

interface OddsEvent {
  id?: string;
  home_team?: string;
  away_team?: string;
  bookmakers?: Array<{
    key?: string;
    markets?: Array<{
      key?: string;
      outcomes?: Array<{ name?: string; point?: number }>;
    }>;
  }>;
}

function abbreviation(name: string | undefined): string | null {
  if (!name) return null;
  return TEAM_ABBREVIATIONS[name] ?? null;
}

function parseWeek(value: string | number | undefined): number | null {
  const match = String(value ?? "").match(/\d+/);
  if (!match) return null;
  const week = Number(match[0]);
  return week >= 1 && week <= 18 ? week : null;
}

function resolvedStatus(short: string | undefined): string {
  const code = (short ?? "").toUpperCase();
  if (["FT", "AOT"].includes(code)) return "final";
  if (["NS", "TBD", "PST", "CANC", ""].includes(code)) return "scheduled";
  return "in_progress";
}

async function apiSports<T>(path: string, key: string): Promise<T[]> {
  const rows: T[] = [];
  for (let page = 1; page <= 20; page += 1) {
    const url = new URL(`${API_SPORTS_BASE}${path}`);
    if (page > 1) url.searchParams.set("page", String(page));
    const response = await fetch(url, { headers: { "x-apisports-key": key } });
    if (!response.ok) {
      throw new Error(`API-Sports ${path} returned ${response.status}`);
    }
    const body = await response.json() as {
      response?: T[];
      paging?: { total?: number };
      errors?: unknown;
    };
    const errors = body.errors;
    const hasErrors = Array.isArray(errors)
      ? errors.length > 0
      : !!errors && typeof errors === "object" && Object.keys(errors as object).length > 0;
    if (hasErrors) {
      throw new Error(`API-Sports ${path} rejected the request`);
    }
    rows.push(...(body.response ?? []));
    const total = body.paging?.total ?? 1;
    if (page >= total) break;
  }
  return rows;
}

function homeSpread(event: OddsEvent): number | null {
  const bookmakers = [...(event.bookmakers ?? [])].sort((left, right) => {
    if (left.key === "draftkings") return -1;
    if (right.key === "draftkings") return 1;
    return 0;
  });
  for (const book of bookmakers) {
    const market = book.markets?.find((item) => item.key === "spreads");
    const outcome = market?.outcomes?.find((item) => item.name === event.home_team);
    if (typeof outcome?.point === "number") return outcome.point;
  }
  return null;
}

export async function runSeasonSync(apiSportsKey: string, oddsApiKey: string): Promise<SeasonSyncResult> {
  const db = getFirestore();
  const unmatched = new Set<string>();
  const [teamRows, gameRows] = await Promise.all([
    apiSports<{ id?: number; name?: string; logo?: string }>(`/teams?league=${API_SPORTS_LEAGUE}&season=${SEASON}`, apiSportsKey),
    apiSports<ApiGame>(`/games?league=${API_SPORTS_LEAGUE}&season=${SEASON}`, apiSportsKey),
  ]);

  let teamsWritten = 0;
  let batch = db.batch();
  let writes = 0;
  const flush = async (force = false) => {
    if (writes === 0 || (!force && writes < 400)) return;
    await batch.commit();
    batch = db.batch();
    writes = 0;
  };

  for (const team of teamRows) {
    const abbr = abbreviation(team.name);
    if (!abbr) {
      if (team.name) unmatched.add(team.name);
      continue;
    }
    batch.set(db.collection("teams").doc(abbr), {
      abbreviation: abbr,
      name: team.name,
      apiSportsId: team.id ?? null,
      logoUrl: team.logo ?? null,
      season: SEASON,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    teamsWritten += 1;
    writes += 1;
    await flush();
  }

  let gamesWritten = 0;
  const scheduledGames = new Map<string, string>();
  for (const row of gameRows) {
    const stage = (row.game?.stage ?? "").toLowerCase();
    if (stage && !stage.includes("regular")) continue;
    const week = parseWeek(row.game?.week);
    const home = row.teams?.home;
    const away = row.teams?.away;
    const homeAbbr = abbreviation(home?.name);
    const awayAbbr = abbreviation(away?.name);
    const gameId = row.game?.id;
    const kickoff = row.game?.date?.timestamp;
    if (!week || !homeAbbr || !awayAbbr || !gameId || !kickoff) {
      if (home?.name && !homeAbbr) unmatched.add(home.name);
      if (away?.name && !awayAbbr) unmatched.add(away.name);
      continue;
    }
    const status = resolvedStatus(row.game?.status?.short);
    const homeScore = status === "final" ? row.scores?.home?.total ?? null : null;
    const awayScore = status === "final" ? row.scores?.away?.total ?? null : null;
    const docId = String(gameId);
    batch.set(db.collection("games").doc(docId), {
      season: SEASON,
      week,
      homeAbbr,
      awayAbbr,
      homeName: home?.name ?? homeAbbr,
      awayName: away?.name ?? awayAbbr,
      teams: [homeAbbr, awayAbbr],
      kickoffAt: Timestamp.fromMillis(kickoff * 1000),
      status,
      homeScore,
      awayScore,
      apiSportsId: gameId,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    if (status === "scheduled") scheduledGames.set(`${homeAbbr}|${awayAbbr}`, docId);
    gamesWritten += 1;
    writes += 1;
    await flush();
  }
  await flush(true);

  let spreads = 0;
  if (oddsApiKey) {
    const url = new URL(ODDS_BASE);
    url.searchParams.set("regions", "us");
    url.searchParams.set("markets", "spreads");
    url.searchParams.set("oddsFormat", "american");
    url.searchParams.set("apiKey", oddsApiKey);
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Odds API returned ${response.status}`);
    const events = await response.json() as OddsEvent[];
    batch = db.batch();
    writes = 0;
    for (const event of events) {
      const homeAbbr = abbreviation(event.home_team);
      const awayAbbr = abbreviation(event.away_team);
      const spread = homeSpread(event);
      if (!homeAbbr || !awayAbbr || spread === null) continue;
      const docId = scheduledGames.get(`${homeAbbr}|${awayAbbr}`);
      if (!docId) continue;
      batch.set(db.collection("games").doc(docId), {
        spreadHome: spread,
        oddsEventId: event.id ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      spreads += 1;
      writes += 1;
      await flush();
    }
    await flush(true);
    await db.collection("pool").doc(String(SEASON)).set({
      oddsSyncedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  return { teams: teamsWritten, games: gamesWritten, spreads, unmatchedTeams: [...unmatched] };
}
