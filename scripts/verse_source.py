"""Vers des Tages von YouVersion für den Board-Server (nur stdlib).

Reihenfolge:
  1. Offizielle YouVersion Platform API (nur mit YOUVERSION_APP_KEY)
  2. Öffentliche YouVersion-App-API nodejs.bible.com (ohne Key, inoffiziell)
  3. Kein Treffer -> None, das Board zeigt dann board/verses.js
Erfolgreiche Abrufe landen pro Datum in ~/.local/share/pi-screen/verse-cache.json.
"""
import datetime
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

try:
    from zoneinfo import ZoneInfo
    TZ = ZoneInfo("Europe/Berlin")
except Exception:  # tzdata fehlt
    TZ = None

CACHE_FILE = Path.home() / ".local" / "share" / "pi-screen" / "verse-cache.json"
UA = "Pi-Screen-Board/1.0 (ICF Heilbronn; +https://github.com/Rasvan-Teofil/Pi-Canva-Viewer)"
TIMEOUT = 6
RETRY_AFTER = 900  # Sekunden Pause nach einem Fehlschlag

DEFAULT_VERSION = 73  # Hoffnung für alle
_fail = {"key": None, "at": 0.0}


def today():
    return datetime.datetime.now(TZ).date() if TZ else datetime.date.today()


def _get(url, headers=None):
    h = {"User-Agent": UA, "Accept": "application/json"}
    h.update(headers or {})
    with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _clean(text):
    text = re.sub(r"<[^>]+>", " ", text or "")
    return re.sub(r"\s+", " ", text).strip()


def _de_ref(human):
    """'Jesaja 43:18' -> 'Jesaja 43,18'"""
    return re.sub(r"(\d+):(\d+)", r"\1,\2", human or "").strip()


def _join_ref(first_human, usfms):
    """Mehrere USFM-Verse zu einer Stelle: 'Jesaja 43,18–19' bzw. 'Johannes 14,31–15,2'."""
    ref = _de_ref(first_human)
    if len(usfms) < 2:
        return ref
    a, b = usfms[0].split("."), usfms[-1].split(".")
    if len(a) < 3 or len(b) < 3:
        return ref
    return ref + "–" + (b[2] if a[1] == b[1] else "%s,%s" % (b[1], b[2]))


def _official(day, version, key, abbr):
    h = {"X-YVP-App-Key": key}
    base = "https://api.youversion.com/v1"
    votd = _get("%s/verse-of-the-days/%d" % (base, day.timetuple().tm_yday), h)
    pid = votd.get("passage_id") or ""
    usfms = [p for p in pid.split("+") if p]
    texts, refs = [], []
    for p in usfms:
        # einzelne Verse oder Bereiche innerhalb eines Kapitels sind erlaubt
        data = _get("%s/bibles/%s/passages/%s?format=text" % (base, version, urllib.parse.quote(p)), h)
        texts.append(_clean(data.get("content")))
        refs.append(_de_ref(data.get("reference")))
    text = " ".join(t for t in texts if t)
    if not text:
        raise ValueError("leerer Text")
    return {"text": text, "reference": " + ".join(r for r in refs if r), "version": abbr,
            "usfm": usfms, "source": "youversion-platform"}


def _legacy(day, version, abbr):
    data = _get("https://nodejs.bible.com/api/moments/votd/3.1?language_tag=de")
    yday = day.timetuple().tm_yday
    entry = next((e for e in data.get("votd", []) if e.get("day") == yday), None)
    if not entry or not entry.get("usfm"):
        raise ValueError("kein Eintrag für Tag %d" % yday)
    usfms = entry["usfm"]
    texts, first_human = [], ""
    for u in usfms:
        v = _get("https://nodejs.bible.com/api/bible/verse/3.1?id=%s&reference=%s"
                 % (urllib.parse.quote(str(version)), urllib.parse.quote(u)))
        if v.get("errors") or not v.get("content"):
            raise ValueError("%s nicht in Version %s" % (u, version))
        texts.append(_clean(v["content"]))
        first_human = first_human or (v.get("reference") or {}).get("human", "")
    if not abbr:
        try:
            abbr = _get("https://nodejs.bible.com/api/bible/version/3.1?id=%s"
                        % urllib.parse.quote(str(version))).get("local_abbreviation", "")
        except Exception:
            abbr = ""
    return {"text": " ".join(texts), "reference": _join_ref(first_human, usfms), "version": abbr,
            "usfm": usfms, "source": "youversion"}


def _load_cache():
    try:
        return json.loads(CACHE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_cache(cache):
    try:
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        keep = dict(sorted(cache.items())[-14:])  # nur die letzten 14 Einträge
        tmp = CACHE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(keep, ensure_ascii=False, indent=1), encoding="utf-8")
        tmp.replace(CACHE_FILE)
    except OSError as exc:
        sys.stderr.write("board-server: Vers-Cache nicht schreibbar: %s\n" % exc)


def verse_of_the_day(env, day=None):
    """Liefert {text, reference, version, source, date} oder None (-> lokaler Fallback)."""
    if env.get("VERSE_SOURCE", "youversion").strip().lower() != "youversion":
        return None
    day = day or today()
    version = env.get("YOUVERSION_VERSION", "").strip() or str(DEFAULT_VERSION)
    abbr = env.get("YOUVERSION_VERSION_LABEL", "").strip() or ("HFA" if version == "73" else "")
    key = env.get("YOUVERSION_APP_KEY", "").strip()
    ckey = "%s|%s" % (day.isoformat(), version)

    cache = _load_cache()
    if ckey in cache:
        return cache[ckey]
    if _fail["key"] == ckey and time.time() - _fail["at"] < RETRY_AFTER:
        return None

    result = None
    attempts = ([("platform", lambda: _official(day, version, key, abbr))] if key else []) + \
               [("nodejs.bible.com", lambda: _legacy(day, version, abbr))]
    for name, fn in attempts:
        try:
            result = fn()
            break
        except Exception as exc:  # offline, Format geändert, Version fehlt …
            sys.stderr.write("board-server: Vers via %s fehlgeschlagen: %s\n" % (name, exc))
    if not result:
        _fail.update(key=ckey, at=time.time())
        return None
    result["date"] = day.isoformat()
    cache[ckey] = result
    _save_cache(cache)
    return result


if __name__ == "__main__":  # Test: python3 scripts/verse_source.py [YYYY-MM-DD] [VERSION]
    d = datetime.date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else None
    e = {"YOUVERSION_VERSION": sys.argv[2]} if len(sys.argv) > 2 else {}
    print(json.dumps(verse_of_the_day(e, d), ensure_ascii=False, indent=1))
