#!/usr/bin/env python3
"""Print compact QA summaries from the three sweep reports."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QA = ROOT / "out" / "qa"


def summarize(name: str, path: Path) -> None:
    if not path.exists():
        print(f"{name}: missing {path}")
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    results = data.get("results", [])
    empty = sum(1 for r in results if r.get("empty_record"))
    failed = [r for r in results if not r.get("ok")]
    print(f"{name}: {len(results)} indices, {empty} empty records, "
          f"{len(failed)} failures")
    for r in failed[:20]:
        print(f"  {r['index']:04X} {r.get('label', '')}: "
              f"{r.get('failures', [])[:3]}")


def main() -> int:
    summarize("history/shop", QA / "report.json")
    summarize("field", QA / "field_report.json")
    summarize("pages", QA / "pages_report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
