#!/usr/bin/env python3
"""
serve.py - local launch-day editor for the MW4 JSON data.

    python3 MW4CamoTracker/Tools/editor/serve.py [--port 8765] [--no-open]

Serves index.html on http://127.0.0.1:8765 and reads/writes
Resources/{weapons,multiplayer,warzone,dmz}.json in place, so a save shows up
as an ordinary git diff. Files are written with the same formatting the repo
already uses (2-space indent, raw UTF-8, trailing newline), so saving a file
you didn't touch changes nothing.

Every save copies the previous file into Tools/editor/.backups/<timestamp>/
first (git-ignored) - a safety net for uncommitted edits.

Images dropped into the page are written under the site repo's Images/ tree
(Images/Guns/MW4/, Images/Camos/MW4/) and get their camotracker.djr.li URL;
they go live once the repo is pushed, same as the JSON.

"Publish" runs ../publish_data.py, which copies the JSON into Data/MW4/ and
regenerates the manifest the installed apps poll.

Stdlib only; binds to localhost.
"""
import argparse
import base64
import json
import re
import shutil
import subprocess
import sys
import urllib.request
import webbrowser
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = HERE.parents[1]                      # MW4CamoTracker/
ROOT = APP.parent                          # the CamoTracker site repo
RES = APP / "Resources"
BACKUPS = HERE / ".backups"
FILES = ["weapons", "multiplayer", "warzone", "dmz"]
SITE = "https://camotracker.djr.li/"
IMAGE_DIRS = {"guns": "Images/Guns/MW4", "camos": "Images/Camos/MW4"}
MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".webp": "image/webp", ".gif": "image/gif"}


def dump(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, ctype="application/json; charset=utf-8"):
        if not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    # GET ------------------------------------------------------------------

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            return self.send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        if path == "/api/data":
            return self.send(200, {n: json.loads((RES / f"{n}.json").read_text(encoding="utf-8")) for n in FILES})
        if path.startswith("/site/Images/"):
            # Local copy of a camotracker.djr.li image, so a freshly added
            # picture previews before it's pushed.
            target = (ROOT / path[len("/site/"):]).resolve()
            images = (ROOT / "Images").resolve()
            if images in target.parents and target.is_file():
                return self.send(200, target.read_bytes(), MIME.get(target.suffix.lower(), "application/octet-stream"))
            return self.send(404, {"error": "not found"})
        self.send(404, {"error": "not found"})

    # POST -----------------------------------------------------------------

    def do_POST(self):
        try:
            if self.path == "/api/save":
                return self.save(self.body())
            if self.path == "/api/publish":
                return self.publish()
            if self.path == "/api/image":
                return self.image(self.body())
            self.send(404, {"error": "not found"})
        except Exception as e:  # surface anything to the page instead of a dead socket
            self.send(500, {"error": f"{type(e).__name__}: {e}"})

    def save(self, payload):
        files = payload.get("files") or {}
        unknown = set(files) - set(FILES)
        if unknown:
            return self.send(400, {"error": f"unknown files: {sorted(unknown)}"})
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        written = []
        for name, obj in files.items():
            dest = RES / f"{name}.json"
            text = dump(obj)
            if dest.read_text(encoding="utf-8") == text:
                continue
            (BACKUPS / stamp).mkdir(parents=True, exist_ok=True)
            shutil.copy2(dest, BACKUPS / stamp / dest.name)
            tmp = dest.with_suffix(".json.tmp")
            tmp.write_text(text, encoding="utf-8")
            tmp.replace(dest)
            written.append(name)
        self.send(200, {"written": written})

    def publish(self):
        r = subprocess.run([sys.executable, str(HERE.parent / "publish_data.py")],
                           capture_output=True, text=True, cwd=ROOT)
        self.send(200 if r.returncode == 0 else 500,
                  {"ok": r.returncode == 0, "output": (r.stdout + r.stderr).strip()})

    def image(self, payload):
        kind = payload.get("kind")
        if kind not in IMAGE_DIRS:
            return self.send(400, {"error": "kind must be guns or camos"})
        name = re.sub(r"[^A-Za-z0-9._-]", "_", payload.get("filename") or "").strip("._")
        if not name:
            return self.send(400, {"error": "missing filename"})
        if payload.get("url"):
            req = urllib.request.Request(payload["url"], headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=20) as r:
                ctype = r.headers.get("Content-Type", "")
                data = r.read()
            if not ctype.startswith("image/"):
                return self.send(400, {"error": f"that URL returned {ctype or 'no content type'}, not an image"})
            ext = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp", "image/gif": ".gif"}.get(ctype.split(";")[0], ".png")
        else:
            data = base64.b64decode(payload.get("data") or "")
            ext = Path(payload.get("sourceName") or "x.png").suffix.lower() or ".png"
        if Path(name).suffix.lower() not in MIME:
            name += ext
        rel = f"{IMAGE_DIRS[kind]}/{name}"
        dest = ROOT / rel
        if dest.exists() and not payload.get("overwrite"):
            return self.send(409, {"error": "exists", "url": SITE + rel})
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        self.send(200, {"url": SITE + rel, "bytes": len(data)})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"MW4 data editor -> {url}   (Ctrl+C to stop)")
    if not args.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
