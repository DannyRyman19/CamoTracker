-- Stream overlays: one row per link a player has switched on. `body` is the
-- JSON the overlay page reads (cleaned by src/overlay.js); `key_hash` is the
-- SHA-256 of the write key only that player's app holds.
CREATE TABLE IF NOT EXISTS overlays (
  id          TEXT PRIMARY KEY,
  key_hash    TEXT NOT NULL,
  body        TEXT NOT NULL,
  ip_hash     TEXT NOT NULL,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS overlays_ip_recent ON overlays (ip_hash, created_at);
CREATE INDEX IF NOT EXISTS overlays_updated ON overlays (updated_at);

-- Per-streamer QR scans. An overlay's QR code links to /go/<code>, where
-- `code` is derived from its id (src/overlay.js, scanCode). `channel` is the
-- name the streamer typed in the app, if any, so counts can be told apart.
CREATE TABLE IF NOT EXISTS scan_codes (
  code        TEXT PRIMARY KEY,
  channel     TEXT NOT NULL DEFAULT '',
  first_seen  TEXT NOT NULL,
  last_seen   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS scans (
  code  TEXT NOT NULL,
  day   TEXT NOT NULL,
  n     INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (code, day)
);
