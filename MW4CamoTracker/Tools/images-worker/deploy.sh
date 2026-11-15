#!/bin/zsh
# Publishes the repo's tracked images (png, webp, jpg, svg under Images/) to
# camo-track.app/Images/ as Workers Static Assets. Only files git tracks go
# out, so nothing stray in Images/ gets published. Hard links, so no copy.
set -eu
cd "$(dirname "$0")"
ROOT=$(git rev-parse --show-toplevel)
rm -rf public && mkdir -p public
python3 - "$ROOT" <<'PY'
import os, subprocess, sys
root = sys.argv[1]
files = subprocess.run(["git", "-C", root, "ls-files", "Images"], capture_output=True, text=True, check=True).stdout.splitlines()
n = 0
for f in files:
    if os.path.splitext(f)[1].lower() not in (".png", ".webp", ".jpg", ".jpeg", ".svg"): continue
    src = os.path.join(root, f)
    if not os.path.exists(src): continue
    dst = os.path.join("public", f)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    os.link(src, dst); n += 1
print(f"{n} images staged")
PY
# A week in the app's and browsers' caches, then a quiet revalidation.
cat > public/_headers <<'H'
/Images/*
  Cache-Control: public, max-age=604800, stale-while-revalidate=86400
  Access-Control-Allow-Origin: *
H
npx --yes wrangler@4 deploy
