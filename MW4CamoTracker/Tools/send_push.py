#!/usr/bin/env python3
"""
send_push.py - send the announcement in a game's published manifest as a real
push to every phone registered with camo-track.app/api/push (the
camo-track-push Worker, Backend/push).

    python3 MW4CamoTracker/Tools/send_push.py                 # MW4
    python3 MW4CamoTracker/Tools/send_push.py --game bo7
    python3 MW4CamoTracker/Tools/send_push.py --count         # how many phones
    python3 MW4CamoTracker/Tools/send_push.py --no-wait       # don't wait for jsDelivr

Run it after publish_data.py --title/--body and the push to master. It first
waits until jsDelivr serves that manifest (a phone that refreshes on the push
must get the new data, not the cached old one), then sends a page of 40 phones
at a time until all have had it. Each phone gets the text in its language.
The admin token is MW4CamoTracker/Backend/push/.admin-token (git ignores it).
"""
import argparse, json, pathlib, sys, time, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOKEN_FILE = ROOT / "MW4CamoTracker/Backend/push/.admin-token"
API = "https://camo-track.app/api/push"
CDN = "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/"
PURGE = "https://purge.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/"


def call(method, path, token, body=None):
    req = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                 headers={"authorization": f"Bearer {token}", "content-type": "application/json",
                                          "user-agent": "camo-track-publish"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def manifest_path(game):
    games = json.load(open(ROOT / "MW4CamoTracker/Resources/games.json"))
    entry = next((g for g in games if g["id"] == game), None)
    if not entry:
        raise SystemExit(f"--game: no game {game!r}")
    return entry["path"].rstrip("/") + "/manifest.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default="mw4")
    ap.add_argument("--count", action="store_true", help="just say how many phones are registered")
    ap.add_argument("--no-wait", action="store_true", help="send without waiting for jsDelivr")
    args = ap.parse_args()
    token = TOKEN_FILE.read_text().strip()
    if args.count:
        print(call("GET", "/count", token))
        return

    rel = manifest_path(args.game)
    note = json.load(open(ROOT / rel)).get("notification") or {}
    if note.get("silent") or not note.get("id") or not (note.get("title") or note.get("body")):
        raise SystemExit(f"{rel} has no announcement to push (publish with --title/--body first)")
    print(f"announcement {note['id']}: {note.get('title', {}).get('en', '')}")

    if not args.no_wait:
        tried_purge = False
        for i in range(60):
            try:
                with urllib.request.urlopen(f"{CDN}{rel}?t={int(time.time())}", timeout=30) as r:
                    live = json.load(r).get("notification") or {}
            except Exception as e:
                live = {}
                print(f"jsDelivr: {e}")
            if live.get("id") == note["id"]:
                print("jsDelivr has it")
                break
            if not tried_purge:
                urllib.request.urlopen(PURGE + rel, timeout=30).read()
                tried_purge = True
            print("waiting for jsDelivr…")
            time.sleep(30)
        else:
            raise SystemExit("jsDelivr still serves the old manifest after 30 minutes: is it pushed to master? (--no-wait to send anyway)")

    totals = {"sent": 0, "failed": 0, "removed": 0}
    cursor = None
    while True:
        r = call("POST", "/send", token, {"id": note["id"], "title": note.get("title") or {}, "body": note.get("body") or {}, "link": note.get("link"), "cursor": cursor})
        for k in totals:
            totals[k] += r.get(k, 0)
        cursor = r.get("cursor")
        if not cursor:
            break
    print(f"pushed: {totals['sent']} sent, {totals['failed']} failed, {totals['removed']} dead tokens removed")


if __name__ == "__main__":
    main()
