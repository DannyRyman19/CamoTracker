#!/usr/bin/env python3
"""
notices.py - the in-app notice cards (Data/CT/notices.json): list them, check
the file, switch one on or off.

    python3 MW4CamoTracker/Tools/notices.py                     # list and check
    python3 MW4CamoTracker/Tools/notices.py on android-testers
    python3 MW4CamoTracker/Tools/notices.py off android-testers

The words, link and dates are edited in the file by hand; run this afterwards
to check them. Nothing is live until the file is committed and pushed to
master (and jsDelivr keeps its copy for up to 12 hours unless purged: the
script prints the link). The app reads the file in Sources/Notices.swift.
"""
import datetime, json, pathlib, re, sys

FILE = pathlib.Path(__file__).resolve().parents[2] / "Data/CT/notices.json"
PURGE = "https://purge.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/CT/notices.json"
LANGUAGES = ["en", "fr", "es", "de", "nl", "it", "pt"]
TEXTS = ["title", "body", "button", "shareText"]
KNOWN = {"id", "enabled", "title", "body", "button", "url", "action", "shareText", "icon", "from", "until"}


def problems_of(notice, seen):
    """(errors, warnings) for one notice, by the rules the app applies."""
    errors, warnings = [], []
    if not isinstance(notice, dict):
        return ["not an object: the app skips it"], []
    ident = notice.get("id")
    if not isinstance(ident, str) or not ident:
        errors.append('needs an "id" (text)')
    elif ident in seen:
        errors.append(f'"id" {ident!r} is used twice: closing one closes both')
    if "enabled" in notice and not isinstance(notice["enabled"], bool):
        errors.append('"enabled" must be true or false')
    for key in TEXTS:
        text = notice.get(key)
        if text is None:
            if key == "title":
                errors.append('needs a "title"')
            continue
        if not isinstance(text, dict) or not all(isinstance(v, str) for v in text.values()):
            errors.append(f'"{key}" must be an object of language: text')
        elif not text.get("en"):
            errors.append(f'"{key}" needs English ("en"): it is what a missing language falls back to')
        else:
            missing = [lang for lang in LANGUAGES if not text.get(lang)]
            if missing:
                warnings.append(f'"{key}" has no {", ".join(missing)} (English is shown)')
    url = notice.get("url")
    if url is not None and not (isinstance(url, str) and re.match(r"^https://[^\s/]+", url)):
        errors.append('"url" must be an https:// link: the app shows no button for anything else')
    if notice.get("action") not in (None, "share", "open"):
        errors.append('"action" is "share" or "open"')
    if url and notice.get("action") != "share" and not notice.get("button"):
        warnings.append('a link to open needs "button" words, or no button is shown')
    if not url and (notice.get("button") or notice.get("action") or notice.get("shareText")):
        warnings.append('"button", "action" and "shareText" do nothing without a "url"')
    for key in ("from", "until"):
        day = notice.get(key)
        if day is None:
            continue
        try:
            if not isinstance(day, str) or len(day) != 10:
                raise ValueError
            datetime.date.fromisoformat(day)
        except ValueError:
            errors.append(f'"{key}" must be a day like 2026-12-31: the app hides the notice otherwise')
    if isinstance(notice.get("from"), str) and isinstance(notice.get("until"), str) and notice["from"] > notice["until"]:
        errors.append('"from" is after "until": it would never show')
    unknown = sorted(set(notice) - KNOWN)
    if unknown:
        warnings.append(f"the app ignores {', '.join(unknown)}")
    return errors, warnings


def state(notice, today):
    if notice.get("enabled") is False:
        return "off"
    if notice.get("from") and today < notice["from"]:
        return f"on, starts {notice['from']}"
    if notice.get("until") and today > notice["until"]:
        return f"on, but ended {notice['until']}"
    return "on" + (f" until {notice['until']}" if notice.get("until") else "")


def main(argv):
    if len(argv) not in (0, 2) or (argv and argv[0] not in ("on", "off")):
        raise SystemExit(__doc__.strip())
    try:
        data = json.loads(FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise SystemExit(f"{FILE.name} is not valid JSON: {error}")
    notices = data.get("notices") if isinstance(data, dict) else None
    if not isinstance(notices, list):
        raise SystemExit(f'{FILE.name} must be {{"notices": [...]}}')

    if argv:
        wanted = [n for n in notices if isinstance(n, dict) and n.get("id") == argv[1]]
        if not wanted:
            ids = ", ".join(str(n.get("id")) for n in notices if isinstance(n, dict))
            raise SystemExit(f"no notice {argv[1]!r} (there is: {ids or 'none'})")
        for notice in wanted:
            notice["enabled"] = argv[0] == "on"

    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    failed, seen, first_live = False, set(), None
    for notice in notices:
        errors, warnings = problems_of(notice, seen)
        ident = notice.get("id") if isinstance(notice, dict) else None
        if isinstance(ident, str):
            seen.add(ident)
        label = state(notice, today) if isinstance(notice, dict) and not errors else "broken"
        title = (notice.get("title") or {}).get("en", "") if isinstance(notice, dict) and isinstance(notice.get("title"), dict) else ""
        print(f"{ident or '?':24} {label:22} {title}")
        for line in errors:
            print(f"  error: {line}", file=sys.stderr)
        for line in warnings:
            print(f"  warning: {line}")
        failed = failed or bool(errors)
        if not errors and label.startswith("on") and "starts" not in label and "ended" not in label and first_live is None:
            first_live = ident
    if failed:
        raise SystemExit("not saved: fix the errors above" if argv else 1)
    print(f"shown now: {first_live or 'nothing'}" + (" (the first one that is on; the next shows once a player closes it)" if first_live else ""))

    if argv:
        FILE.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"saved. Commit Data/CT/notices.json and push to master to make it live, then open {PURGE} to skip jsDelivr's cache.")


if __name__ == "__main__":
    main(sys.argv[1:])
