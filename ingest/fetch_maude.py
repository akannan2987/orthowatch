"""
fetch_maude.py — Phase 1, script 1 of 2  (v2)
==============================================

WHAT THIS DOES
    Downloads orthopedic device adverse event reports from the FDA's free
    openFDA API and saves the *untouched* JSON responses into data/raw/.
    Also writes data/raw/fetch_log.csv — our traceability record.

HOW TO RUN (from the project root, venv activated)
    export OPENFDA_API_KEY="your-key-here"   # see 'API KEY' note below
    python ingest/fetch_maude.py --probe     # show counts, download nothing
    python ingest/fetch_maude.py             # actually download

CHANGES IN v2 (and the story behind them — see docs, Phase 1 FAQ)
    1. Hip/knee searches switched from exact-phrase to AND-style:
       FDA generic names are comma-inverted ("PROSTHESIS, HIP, ..."),
       so the phrase "hip prosthesis" matched almost nothing. The probe
       step caught this: 45 hip reports in a year was implausible.
    2. Requests now send a User-Agent header identifying this project,
       support an API key, and retry with backoff. api.fda.gov sits
       behind bot-detection (Akamai) that can 403 anonymous script
       traffic; identifying yourself and authenticating is the fix —
       and the professional norm when calling public APIs.

API KEY (free, 2 minutes)
    Get one at https://open.fda.gov/apis/authentication/ then, in your
    terminal, BEFORE running this script:
        export OPENFDA_API_KEY="paste-your-key"
    The key lives in an environment variable, never in code and never
    in Git — secrets in a public repo are a classic security mistake.
    (To make it permanent, add that export line to your ~/.zshrc.)
"""

import argparse
import re
import csv
import datetime as dt
import json
import os
import pathlib
import sys
import time

import requests

# ─────────────────────────────────────────────────────────────────────
# CONFIGURATION — the only part you should ever need to edit
# ─────────────────────────────────────────────────────────────────────

BASE_URL = "https://api.fda.gov/device/event.json"
RAW_DIR = pathlib.Path("data/raw")

# Identify this client politely. Edge security treats anonymous traffic
# with suspicion; a descriptive User-Agent with a contact point is API
# etiquette (and often the difference between 200 and 403).
HEADERS = {
    "User-Agent": "orthowatch/0.2 (open-source project; "
                  "github.com/akannan2987/orthowatch)"
}

# Device family -> openFDA search expression.
#   field:(a AND b) means the field contains both words, in any order —
#   which is what FDA's comma-inverted names ("PROSTHESIS, HIP,
#   SEMI-CONSTRAINED...") require. Exact phrases "..." are order-
#   sensitive and silently miss them (v1's bug, caught by the probe).
QUERIES = {
    "hip_prosthesis":  'device.generic_name:(hip AND prosthesis)',
    "knee_prosthesis": 'device.generic_name:(knee AND prosthesis)',
    "bone_plate":      'device.generic_name:(bone AND plate)',
    "spinal_fixation": 'device.generic_name:(spinal AND fixation)',
}

# Years of reports to pull (range excludes the end: 2020..2024).
YEARS = range(2020, 2025)

# Records per request (1000 = the API maximum).
PAGE_SIZE = 1000

# openFDA's skip/limit paging cannot go past this many results per query.
SKIP_CEILING = 25_000

# Pause between requests. With a key we're allowed 240/minute; running at
# ~1/second is gentle and still fast enough.
SLEEP_SECONDS = 1.0

# Retry policy: these statuses are treated as transient (edge blocks,
# rate limits, server hiccups) and retried with growing waits.
RETRY_STATUSES = {403, 429, 500, 502, 503, 504}
MAX_ATTEMPTS = 4          # waits between attempts: 5s, 15s, 45s

# The key is read from the environment — see 'API KEY' in the header.
API_KEY = os.environ.get("OPENFDA_API_KEY", "")

# The QUERY DICTIONARY: the openFDA device/event fields this project
# accepts in an extra --search clause. openFDA only understands ITS
# field names — anything else silently matches nothing or errors — so
# we validate against this whitelist BEFORE any network call. Each
# entry: field -> (what it means, an example clause).
SEARCHABLE_FIELDS = {
    "device.generic_name":        ("device type as FDA names it",
                                   'device.generic_name:(shoulder AND prosthesis)'),
    "device.brand_name":          ("product/brand name",
                                   'device.brand_name:ATTUNE'),
    "device.manufacturer_d_name": ("manufacturer name",
                                   'device.manufacturer_d_name:ZIMMER'),
    "device.model_number":        ("model number",
                                   'device.model_number:12345'),
    "event_type":                 ("Injury / Malfunction / Death / Other",
                                   'event_type:Malfunction'),
    "product_problems":           ("coded problem term",
                                   'product_problems:"Corroded"'),
    "mdr_text.text":              ("words in the narrative text",
                                   'mdr_text.text:(cobalt AND revision)'),
}


def validate_search_clause(clause: str) -> str:
    """Return '' if the clause is acceptable, else the reason it isn't.

    Accepts one or more field:value terms joined by AND/OR, each field
    from SEARCHABLE_FIELDS. This is validation-before-network: a typo
    fails HERE, in milliseconds, with a reason — not after a silent
    zero-match download.
    """
    if not clause.strip():
        return ""
    fields = re.findall(r"([A-Za-z_][A-Za-z0-9_.]*)\s*:", clause)
    if not fields:
        return ("no field:value term found - write e.g. "
                "product_problems:\"Corroded\"")
    bad = [f for f in fields if f not in SEARCHABLE_FIELDS]
    if bad:
        return ("unknown field(s): " + ", ".join(sorted(set(bad))) +
                " - searchable fields: " +
                ", ".join(SEARCHABLE_FIELDS))
    return 

# ─────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────


def page_filename(slug: str, tag: str, year: int, page: int) -> str:
    """THE one place page-file names are made - the writer and the
    dry-run both call this, so what the dry-run promises is what the
    writer does. (Born of an incident: a filename claim printed
    beside the writer drifted from it, and a scoped fetch silently
    overwrote a full page file.)"""
    return f"maude_{slug}{tag}_{year}_p{page:03d}.json"


def build_search(device_query: str, year: int, extra: str = "") -> str:
    """Combine a device expression with a one-year date window, plus an
    optional extra clause (validated against SEARCHABLE_FIELDS).

    date_received uses YYYYMMDD strings; [a TO b] is openFDA's
    inclusive range syntax.
    """
    s = f"({device_query}) AND date_received:[{year}0101 TO {year}1231]"
    if extra.strip():
        s += f" AND ({extra.strip()})"
    return s


def call_api(search: str, limit: int, skip: int) -> requests.Response:
    """One API request, with polite headers and retry-with-backoff.

    Backoff means: if the server says "not now" (403/429/5xx), wait,
    then try again with a longer wait each time — like knocking again
    later instead of hammering the door. 404 is NOT retried: openFDA
    uses it to mean "zero matches", which is an answer, not an error.
    """
    params = {
        "search": search,
        "limit": limit,
        "skip": skip,
        "sort": "date_received:asc",   # fixed order = deterministic paging
    }
    if API_KEY:
        params["api_key"] = API_KEY

    for attempt in range(1, MAX_ATTEMPTS + 1):
        resp = requests.get(BASE_URL, params=params,
                            headers=HEADERS, timeout=60)
        if resp.status_code not in RETRY_STATUSES:
            return resp                       # success, or a real error
        if attempt == MAX_ATTEMPTS:
            return resp                       # give up; caller raises
        wait = 5 * (3 ** (attempt - 1))       # 5, 15, 45 seconds
        print(f"  … got HTTP {resp.status_code}; "
              f"retrying in {wait}s (attempt {attempt}/{MAX_ATTEMPTS - 1})")
        time.sleep(wait)
    return resp  # unreachable, but keeps type-checkers happy


def get_total(search: str) -> int:
    """How many reports match, without downloading them (limit=1;
    the response's meta block carries the total)."""
    resp = call_api(search, limit=1, skip=0)
    if resp.status_code == 404:
        return 0
    resp.raise_for_status()
    return resp.json()["meta"]["results"]["total"]


# ─────────────────────────────────────────────────────────────────────
# MAIN LOGIC
# ─────────────────────────────────────────────────────────────────────


def probe(queries=None, years=None, extra: str = "") -> None:
    queries = queries or QUERIES
    years = years or YEARS
    print(f"{'slice':<28} {'reports available':>18}")
    print("-" * 46)
    grand_total = 0
    for slug, device_query in queries.items():
        for year in years:
            total = get_total(build_search(device_query, year, extra))
            grand_total += total
            print(f"{slug + ' ' + str(year):<28} {total:>18,}")
            time.sleep(0.3)
    print("-" * 46)
    print(f"{'TOTAL':<28} {grand_total:>18,}")
    est_requests = grand_total // PAGE_SIZE + len(queries) * len(years)
    print(f"\nEstimated download requests: ~{est_requests} "
          f"(daily allowance: 120,000 (with key))")


def fetch_all(queries=None, years=None, extra: str = "", tag: str = "") -> None:
    queries = queries or QUERIES
    years = years or YEARS
    """Download every slice, page by page, and log everything."""
    if not API_KEY:
        print("NOTE: no OPENFDA_API_KEY set. Anonymous traffic is more "
              "likely to hit bot-detection 403s and is capped at 1,000 "
              "requests/day. A free key takes two minutes — see the "
              "header of this script.\n")

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    log_path = RAW_DIR / "fetch_log.csv"

    log_exists = log_path.exists()
    with open(log_path, "a", newline="", encoding="utf-8") as log_file:
        log = csv.writer(log_file)
        if not log_exists:
            log.writerow(["fetched_at_utc", "slice", "search",
                          "total_available", "records_fetched",
                          "pages_saved", "status"])

        for slug, device_query in queries.items():
            for year in years:
                search = build_search(device_query, year, extra)
                total = get_total(search)
                time.sleep(SLEEP_SECONDS)

                if total == 0:
                    print(f"[{slug} {year}] no reports — skipping")
                    log.writerow([dt.datetime.now(dt.timezone.utc).isoformat(),
                                  f"{slug}_{year}", search, 0, 0, 0, "empty"])
                    continue

                status = "complete"
                if total > SKIP_CEILING + PAGE_SIZE:
                    print(f"[{slug} {year}] {total:,} reports exceeds the "
                          f"paging ceiling — fetching the first "
                          f"{SKIP_CEILING + PAGE_SIZE:,} only")
                    status = "truncated_at_ceiling"

                fetched = 0
                pages = 0
                skip = 0
                while skip <= min(total - 1, SKIP_CEILING):
                    resp = call_api(search, limit=PAGE_SIZE, skip=skip)
                    resp.raise_for_status()
                    results = resp.json().get("results", [])
                    if not results:
                        break

                    out = RAW_DIR / page_filename(slug, tag, year, pages)
                    # Self-check: an extra-search fetch must write
                    # ONLY tagged names. If this ever fails, something
                    # upstream broke - refuse loudly, clobber nothing.
                    if bool(extra.strip()) != ("_q_" in out.name):
                        raise RuntimeError(
                            "filename tag self-check failed for " + out.name)
                    with open(out, "w", encoding="utf-8") as f:
                        json.dump(resp.json(), f)

                    fetched += len(results)
                    pages += 1
                    skip += PAGE_SIZE
                    print(f"[{slug} {year}] page {pages:>3} saved "
                          f"({fetched:,}/{total:,} reports)", end="\r")
                    time.sleep(SLEEP_SECONDS)

                print()
                log.writerow([dt.datetime.now(dt.timezone.utc).isoformat(),
                              f"{slug}_{year}", search, total,
                              fetched, pages, status])

    print(f"\nDone. Raw files in {RAW_DIR}/ — log written to {log_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fetch MAUDE orthopedic reports")
    parser.add_argument("--probe", action="store_true",
                        help="show counts only; download nothing")
    parser.add_argument("--families", default="",
                        help="comma-separated subset of: " + ",".join(QUERIES))
    parser.add_argument("--year-from", type=int, default=None,
                        help="first year (default: config block)")
    parser.add_argument("--year-to", type=int, default=None,
                        help="last year, inclusive (default: config block)")
    parser.add_argument("--search", default="",
                        help="extra clause ANDed onto every query, e.g. "
                             "product_problems:\"Corroded\" - fields must be "
                             "in the query dictionary (SEARCHABLE_FIELDS)")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the search expressions and file names "
                             "this scope would use; no network at all")
    args = parser.parse_args()

    # Validation-before-network: every scope problem fails here, with a
    # reason, before a single request is made.
    queries = QUERIES
    if args.families:
        wanted = [f.strip() for f in args.families.split(",") if f.strip()]
        bad = [f for f in wanted if f not in QUERIES]
        if bad:
            sys.exit("unknown family: " + ", ".join(bad) +
                     " - known: " + ", ".join(QUERIES))
        queries = {k: QUERIES[k] for k in wanted}
    years = YEARS
    y0 = args.year_from if args.year_from is not None else min(YEARS)
    y1 = args.year_to if args.year_to is not None else max(YEARS)
    if not (2010 <= y0 <= y1 <= 2026):
        sys.exit(f"year range {y0}-{y1} invalid (2010-2026, from <= to)")
    years = range(y0, y1 + 1)
    err = validate_search_clause(args.search)
    if err:
        sys.exit("bad --search: " + err)
    tag = "_q" if args.search.strip() else ""

    if args.dry_run:
        print("dry run - the scope resolves to:")
        for slug, q in queries.items():
            for year in years:
                print(" ", build_search(q, year, args.search))
        print("first file would be named:",
              page_filename(sorted(queries)[0], tag, min(years), 0))
        sys.exit(0)

    try:
        probe(queries, years, args.search) if args.probe \
            else fetch_all(queries, years, args.search, tag)
    except KeyboardInterrupt:
        sys.exit("\ninterrupted - partial pages are safe to keep or delete")
