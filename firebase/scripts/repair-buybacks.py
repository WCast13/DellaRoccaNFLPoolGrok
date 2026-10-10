#!/usr/bin/env python3
"""
Re-derive every entry's standing from its picks and the final scores.

The pool rule, confirmed by the commissioner on 2026-10-10: a pick after a loss
the previous week means the entry bought back and is active. The grader shipped
that day required an in-app election as well, so the week-4 close lapsed 138
entries whose week-4 picks had been loaded outside the app. A further 49 were
left pending at week 1 by the week 1-3 importer although they kept picking.

For each entry, walk weeks 1..closedThroughWeek:
  - a win keeps it going; a missing pick is a loss, as the grader treats it
  - a loss followed by a pick for the next week (public or still private) or
    a recorded buyback row is a buyback: active again
  - an entry with a live in-app election for the latest closed week is left
    to the close, which resolves it
  - a loss in the latest closed week with none of those: pendingBuyback (weeks
    1-6) or eliminated, decision open
  - a loss in an earlier week with none of those: eliminated, declined
Entries whose pick cannot be scored (no final game) are left untouched.

Only status, eliminatedWeek, buybackDeclined, buybacks, and buybackCount are
written, and only where they differ. Picks, usedTeams, and the fee flag are
never touched. Dry run by default; pass --apply to write.

Auth: the OAuth token the Firebase CLI keeps in its configstore. Run any
`firebase` command first so it is fresh. The token is never printed.
"""
import argparse, collections, json, os, sys, time, urllib.request

PROJECT = "dellaroccanflpool"
SEASON = 2026
BUYBACK_THROUGH_WEEK = 6
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"


def token():
    store = os.path.expanduser("~/.config/configstore/firebase-tools.json")
    tokens = (json.load(open(store)).get("tokens") or {})
    value = tokens.get("access_token")
    if not value or tokens.get("expires_at", 0) / 1000 < time.time() + 60:
        sys.exit("Firebase CLI token missing or expired; run `firebase projects:list` and retry")
    return value


TOKEN = token()


def call(url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} from {url.split('/documents')[-1][:40]}: {e.read().decode()[:400]}")


def decode(v):
    if v is None or "nullValue" in v:
        return None
    for k in ("stringValue", "booleanValue", "timestampValue"):
        if k in v:
            return v[k]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "doubleValue" in v:
        return v["doubleValue"]
    if "mapValue" in v:
        return {k: decode(x) for k, x in (v["mapValue"].get("fields") or {}).items()}
    if "arrayValue" in v:
        return [decode(x) for x in (v["arrayValue"].get("values") or [])]
    return None


def encode(v):
    if v is None:
        return {"nullValue": None}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, list):
        return {"arrayValue": {"values": [encode(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: encode(x) for k, x in v.items()}}}
    raise TypeError(type(v))


def list_collection(name):
    docs, page_token = [], None
    while True:
        page = call(f"{BASE}/{name}?pageSize=300" + (f"&pageToken={page_token}" if page_token else ""))
        for d in page.get("documents", []):
            fields = {k: decode(v) for k, v in (d.get("fields") or {}).items()}
            fields["_name"] = d["name"]
            fields["_id"] = d["name"].split("/")[-1]
            docs.append(fields)
        page_token = page.get("nextPageToken")
        if not page_token:
            return docs


def private_picks():
    q = call(f"{BASE}:runQuery", {"structuredQuery": {"from": [{"collectionId": "privatePicks", "allDescendants": True}], "limit": 5000}})
    out = collections.defaultdict(dict)
    for r in q:
        d = r.get("document")
        if not d:
            continue
        entry_id = d["name"].split("/")[-3]
        f = {k: decode(v) for k, v in d["fields"].items()}
        week = f.get("week") or int(d["name"].split("/")[-1])
        if f.get("team"):
            out[entry_id][int(week)] = f["team"]
    return out


def results_by_week(games):
    """team -> 'win' | 'loss' per week, from final games with scores. A tie is
    a loss for both sides, as in grade.ts."""
    out = collections.defaultdict(dict)
    for g in games:
        if g.get("season") not in (None, SEASON) or g.get("status") != "final":
            continue
        hs, as_ = g.get("homeScore"), g.get("awayScore")
        if not isinstance(hs, int) or not isinstance(as_, int):
            continue
        week = int(g["week"])
        out[week][g["homeAbbr"]] = "win" if hs > as_ else "loss"
        out[week][g["awayAbbr"]] = "win" if as_ > hs else "loss"
    return out


def derive(entry, private, results, through):
    public = {int(w): t for w, t in (entry.get("picks") or {}).items() if t}
    picks = {**public, **private}
    rows_in = [r for r in (entry.get("buybacks") or []) if isinstance(r, dict)]
    existing = {}
    for r in rows_in:
        wk = r.get("eliminatedWeek")
        if isinstance(wk, int) and wk not in existing:
            existing[wk] = r
    recorded = {wk for wk, r in existing.items() if not r.get("provisional")}
    election = entry.get("buybackElection")
    if election is not None and entry.get("eliminatedWeek") == through:
        # A decision the player is still making in the app, for a week that
        # has not closed. The close resolves it; this script stays out.
        return None, f"live election ({election}) after week {through}; left to the app flow"

    status, elim, declined, rows = "active", None, False, []
    for week in range(1, through + 1):
        team = public.get(week)
        if team is None:
            lost = True
        else:
            res = results.get(week, {}).get(team)
            if res is None:
                return None, f"week {week}: no final result for {team}"
            lost = res == "loss"
        if not lost:
            continue
        next_pick = picks.get(week + 1)
        if week <= BUYBACK_THROUGH_WEEK and (next_pick or week in recorded):
            row = dict(existing.get(week) or {"eliminatedWeek": week})
            row.pop("provisional", None)
            if next_pick and row.get("boughtBackBeforeWeek") is None:
                row["boughtBackBeforeWeek"] = week + 1
            rows.append(row)
            continue
        if week <= BUYBACK_THROUGH_WEEK and week == through:
            status, elim, declined = "pendingBuyback", week, False
        else:
            status, elim, declined = "eliminated", week, True
        break
    return {"status": status, "eliminatedWeek": elim, "buybackDeclined": declined, "buybacks": rows, "buybackCount": len(rows)}, None


def differs(entry, target):
    if entry.get("status") != target["status"]:
        return True
    if entry.get("eliminatedWeek") != target["eliminatedWeek"]:
        return True
    if bool(entry.get("buybackDeclined")) != target["buybackDeclined"]:
        return True
    current = [r for r in (entry.get("buybacks") or []) if isinstance(r, dict)]
    if current != target["buybacks"]:
        return True
    return (entry.get("buybackCount") or 0) != target["buybackCount"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write the changes (default is a dry run)")
    args = ap.parse_args()

    pool = call(f"{BASE}/pool/{SEASON}")
    through = decode(pool["fields"].get("closedThroughWeek")) or 0
    print(f"closedThroughWeek = {through}")
    games = list_collection("games")
    results = results_by_week(games)
    print("scored weeks:", {w: len(t) // 2 for w, t in sorted(results.items())})
    entries = list_collection("entries")
    private = private_picks()
    print(f"{len(entries)} entries, {sum(len(v) for v in private.values())} private picks\n")

    plan, skipped = [], []
    transitions = collections.Counter()
    for e in entries:
        target, why = derive(e, private.get(e["_id"], {}), results, through)
        if target is None:
            skipped.append((e.get("label"), why))
            continue
        if not differs(e, target):
            continue
        before = f"{e.get('status')}@{e.get('eliminatedWeek')}"
        after = f"{target['status']}@{target['eliminatedWeek']}"
        transitions[(before, after)] += 1
        plan.append((e, target, before, after))

    print("TRANSITIONS (before -> after): count")
    for (b, a), n in sorted(transitions.items(), key=lambda x: -x[1]):
        print(f"  {b:22} -> {a:22} {n}")
        names = sorted(str(e.get("label")) for e, t, bb, aa in plan if bb == b and aa == a)
        if n <= 40:
            print("     ", ", ".join(names))
    if skipped:
        print("\nSKIPPED (left untouched):")
        for label, why in skipped:
            print(f"  {label}: {why}")

    after = collections.Counter(e.get("status") for e in entries)
    for e, t, _, _ in plan:
        after[e.get("status")] -= 1
        after[t["status"]] += 1
    print(f"\n{len(plan)} entries to write. Status totals after: {dict(after)}")

    if not args.apply:
        print("\nDry run. Re-run with --apply to write.")
        return

    writes = []
    for e, t, _, _ in plan:
        fields = {k: encode(v) for k, v in t.items()}
        mask = list(t.keys())
        if e.get("buybackElection") is not None and t["status"] == "active":
            mask.append("buybackElection")  # in the mask, absent from fields: deleted
        writes.append({
            "update": {"name": e["_name"], "fields": fields},
            "updateMask": {"fieldPaths": mask},
            "updateTransforms": [{"fieldPath": "updatedAt", "setToServerValue": "REQUEST_TIME"}],
        })
    done = 0
    for i in range(0, len(writes), 200):
        chunk = writes[i:i + 200]
        res = call(f"{BASE}:commit", {"writes": chunk})
        done += len(res.get("writeResults", []))
    print(f"committed {done} writes")


if __name__ == "__main__":
    main()
