"""
load_to_sqlite.py — Phase 1, script 2 of 2
===========================================

WHAT THIS DOES
    Reads every raw JSON page in data/raw/, flattens each adverse event
    report into one row of a table, and writes that table into a SQLite
    database at data/processed/orthowatch.db.

HOW TO RUN (from the project root, venv activated)
    python ingest/load_to_sqlite.py

DESIGN DECISIONS, EXPLAINED
    * The table is called raw_events because it is a faithful flattening —
      NO cleaning happens here. Duplicates, weird dates, and inconsistent
      device names all flow through untouched; fixing them visibly is
      Phase 2's whole job.
    * A MAUDE report is a nested document (a report can list several
      devices and several narrative texts). Tables are flat. Our
      flattening rule: one row per REPORT, taking the first listed
      device (plus a count of how many there were) and joining all
      narrative texts into one field. Simplifications like this are
      normal in analytics — the skill is stating them out loud.
    * Every row carries source_file, so any value in the database can be
      traced back to the exact raw API response it came from.
    * The table is rebuilt from scratch every run (if_exists="replace").
      Re-running the pipeline should always give the same result from
      the same raw files — that's reproducibility.
"""

import glob
import json
import pathlib
import sqlite3

import pandas as pd

RAW_DIR = pathlib.Path("data/raw")
DB_PATH = pathlib.Path("data/processed/orthowatch.db")


def join_clean(items, sep=";"):
    """Join a list into one string, skipping None and empty entries.

    Why this exists: MAUDE lists can contain nulls INSIDE them, e.g.
    product_problems = ["Fracture", "Wear", None]. Plain ";".join()
    crashes on the None (that was v1's bug — a real report triggered
    it). Filtering before joining is the defensive habit: never assume
    list items are clean just because the list exists.
    """
    return sep.join(str(x) for x in (items or []) if x)


def flatten_report(report: dict, source_file: str) -> dict:
    """Turn one nested MAUDE report into one flat row (a plain dict).

    .get() returns None when a field is missing instead of crashing —
    essential here, because MAUDE reports omit fields all the time.
    """
    # -- device block: a LIST of devices; we keep the first and count them
    devices = report.get("device") or []
    first_device = devices[0] if devices else {}

    # -- narrative block: a list of text entries; join them into one string
    texts = report.get("mdr_text") or []
    narrative = " || ".join(
        t.get("text", "") for t in texts if t.get("text")
    )

    # -- product_problems: a list of short problem labels, joined with ';'
    problems = report.get("product_problems") or []

    return {
        # identifiers
        "report_number": report.get("report_number"),
        "mdr_report_key": report.get("mdr_report_key"),
        # dates arrive as strings like "20230415" — we parse them in R
        # during Phase 2, deliberately keeping this loader dumb & faithful
        "date_received": report.get("date_received"),
        "date_of_event": report.get("date_of_event"),
        # what happened (Malfunction / Injury / Death / Other)
        "event_type": report.get("event_type"),
        # who reported (manufacturer, user facility, voluntary, ...)
        "source_type": join_clean(report.get("source_type")),
        # first listed device
        "brand_name": first_device.get("brand_name"),
        "generic_name": first_device.get("generic_name"),
        "manufacturer_name": first_device.get("manufacturer_d_name"),
        "model_number": first_device.get("model_number"),
        "n_devices_on_report": len(devices),
        # problem labels and free text (join_clean skips null entries —
        # the exact line that crashed v1 on a real report)
        "product_problems": join_clean(problems),
        "narrative": narrative,
        # provenance: which raw file this row came from
        "source_file": source_file,
    }


def main() -> None:
    files = sorted(glob.glob(str(RAW_DIR / "maude_*.json")))
    if not files:
        raise SystemExit(
            "No raw files found in data/raw/ — run fetch_maude.py first."
        )

    rows = []
    for path in files:
        with open(path, encoding="utf-8") as f:
            page = json.load(f)
        fname = pathlib.Path(path).name
        for report in page.get("results", []):
            rows.append(flatten_report(report, fname))
        print(f"read {fname}: {len(page.get('results', []))} reports")

    df = pd.DataFrame(rows)

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    df.to_sql("raw_events", con, if_exists="replace", index=False)
    con.close()

    # ── sanity summary: read this every time you load ────────────────
    print("\n──── load summary ────")
    print(f"rows written to raw_events : {len(df):,}")
    print(f"unique report_number values: {df['report_number'].nunique():,}")
    print(f"date_received range        : "
          f"{df['date_received'].min()} → {df['date_received'].max()}")
    print(f"event_type counts:\n{df['event_type'].value_counts(dropna=False)}")
    print(f"\nDatabase written to {DB_PATH}")
    if len(df) != df["report_number"].nunique():
        print("\nNote: duplicate report numbers detected. Expected! Some "
              "reports match more than one device query, and MAUDE itself "
              "contains follow-up reports. Phase 2 handles this visibly.")


if __name__ == "__main__":
    main()
