#!/usr/bin/env python3
"""Aggregate the ALDC quality metrics JSONL into a report.

Arithmetic belongs in code, not in a model's head: `/aldc:al-metrics` runs this and renders
what it prints. Reads the plugin-data lane by default, plus the project lane when present,
de-duplicating records that landed in both.

Each metric carries the reading that makes it actionable. A number without a threshold is
decoration, and the whole point of these four is to catch the review drifting from a
measurement into an agreement with the implementer.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone

# Piping this into `head` or `less` is the normal way to read it; without restoring the
# default SIGPIPE handling, python turns that into a traceback on stderr.
try:
    import signal

    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (ImportError, AttributeError, ValueError):  # not POSIX, or not the main thread
    pass


def load(paths: list[str]) -> list[dict]:
    seen: set[tuple] = set()
    out: list[dict] = []
    for p in paths:
        if not p or not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                # Same event written to two lanes: identical ts+session+agent+phase.
                key = (rec.get("ts"), rec.get("session"), rec.get("agent"), rec.get("phase"))
                if key in seen:
                    continue
                seen.add(key)
                out.append(rec)
    return sorted(out, key=lambda r: r.get("ts", ""))


def since_filter(recs: list[dict], days: int | None) -> list[dict]:
    if not days:
        return recs
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return [r for r in recs if r.get("ts", "") >= cutoff]


def pct(n: int, d: int) -> str:
    return f"{100 * n / d:.0f}%" if d else "n/a"


def main() -> int:
    ap = argparse.ArgumentParser(description="Aggregate ALDC quality metrics.")
    ap.add_argument("--data-dir", default=os.environ.get("CLAUDE_PLUGIN_DATA", ""))
    ap.add_argument("--project-dir", default=os.getcwd())
    ap.add_argument("--days", type=int, default=0, help="only records from the last N days")
    ap.add_argument("--project", default="", help="only this project (basename)")
    ap.add_argument("--json", action="store_true", help="emit the aggregate as JSON")
    args = ap.parse_args()

    paths = []
    if args.data_dir:
        paths.append(os.path.join(args.data_dir, "metrics", "aldc-metrics.jsonl"))
    paths.append(os.path.join(args.project_dir, ".github", "metrics", "aldc-metrics.jsonl"))

    recs = since_filter(load(paths), args.days)
    if args.project:
        recs = [r for r in recs if r.get("project") == args.project]

    if not recs:
        print("No metrics recorded yet.")
        print()
        print("Records are written by the SubagentStop hook when a review, implement or audit")
        print("subagent finishes. If you have run phases and still see nothing, check")
        print(f"  {os.path.join(args.data_dir or '<CLAUDE_PLUGIN_DATA>', 'metrics', 'capture.log')}")
        print("— the most common cause is no python interpreter on PATH.")
        return 0

    reviews = [r for r in recs if r.get("agent") == "al-review-subagent"]
    impls = [r for r in recs if r.get("agent") == "al-implement-subagent"]

    def s(rs: list[dict], key: str) -> int:
        return sum(int(r.get("bcq", {}).get(key, 0) or 0) for r in rs)

    prescribed = s(reviews, "prescribed") or s(impls, "prescribed")
    applied = s(reviews, "applied") or s(impls, "applied")
    deviated = s(reviews, "deviated") or s(impls, "deviated")
    undeclared = s(reviews, "undeclared")
    cited = s(reviews, "cited")
    agent_f = s(reviews, "agent_findings")
    total_f = s(reviews, "total_findings")

    agg = {
        "records": len(recs),
        "reviews": len(reviews),
        "implementations": len(impls),
        "projects": sorted({r.get("project", "?") for r in recs}),
        "window_days": args.days or None,
        "independence_ratio": round(agent_f / total_f, 3) if total_f else None,
        "deviation_rate": round(deviated / prescribed, 3) if prescribed else None,
        "undeclared_deviations": undeclared,
        "prescribed": prescribed,
        "applied": applied,
        "cited": cited,
        "agent_findings": agent_f,
        "total_findings": total_f,
        "not_mounted_runs": sum(1 for r in recs if r.get("bcq", {}).get("mounted") is False),
    }

    if args.json:
        print(json.dumps(agg, indent=2, sort_keys=True))
        return 0

    window = f"last {args.days}d" if args.days else "all time"
    print(f"ALDC quality metrics — {window} · {len(recs)} records "
          f"({len(reviews)} reviews, {len(impls)} implementations) "
          f"· projects: {', '.join(agg['projects'])}")
    print()

    print("METRIC                   VALUE      READING")
    print("-" * 78)

    ir = agg["independence_ratio"]
    if ir is None:
        reading = "no review has reported an independence-ratio yet"
    elif ir >= 0.15:
        reading = "healthy — the review is still finding things the corpus does not know"
    elif ir > 0:
        reading = "LOW — the anti-correlation valve is weakening; check agent findings are being run"
    else:
        reading = "ZERO — the review has stopped measuring and is only agreeing. Investigate."
    print(f"{'independence-ratio':<24} {str(ir if ir is not None else 'n/a'):<10} {reading}")

    dr = agg["deviation_rate"]
    if dr is None:
        reading = "nothing prescribed yet"
    elif dr <= 0.15:
        reading = "normal"
    else:
        reading = "HIGH — a prescribed rule may be wrong for us; consider a /custom/ override"
    print(f"{'deviation rate':<24} {str(dr if dr is not None else 'n/a'):<10} {reading}")

    u = agg["undeclared_deviations"]
    reading = "good" if u == 0 else "MUST BE ZERO — the implementer is not reading the worklist"
    print(f"{'undeclared deviations':<24} {u:<10} {reading}")

    if prescribed:
        overlap = pct(cited, prescribed)
        reading = ("the prescriptive pass is scoped too narrowly — review keeps finding what it missed"
                   if cited > prescribed * 0.5 else "the prescriptive pass is covering its ground")
        print(f"{'cited vs prescribed':<24} {overlap:<10} {reading}")

    print()
    print(f"BCQuality prescribed {prescribed} · applied {applied} · deviated {deviated} "
          f"· newly cited by review {cited} · agent findings {agent_f}")
    if agg["not_mounted_runs"]:
        print(f"⚠ {agg['not_mounted_runs']} run(s) had BCQuality not mounted — those contribute no "
              "prescriptions and skew every ratio above. Check the SessionStart hook.")

    verdicts = Counter(r["verdict"] for r in recs if r.get("verdict"))
    if verdicts:
        print("Verdicts: " + " · ".join(f"{k} {v}" for k, v in verdicts.most_common()))

    dev_paths = Counter(p for r in recs for p in r.get("deviations_declared", []))
    if dev_paths:
        print()
        print("Most-deviated knowledge (candidates for a /custom/ override):")
        for path, n in dev_paths.most_common(5):
            print(f"  {n:>3}×  {path}")

    hot = Counter(p for r in recs for p in r.get("knowledge", []))
    if hot:
        print()
        print("Most-cited knowledge:")
        for path, n in hot.most_common(5):
            print(f"  {n:>3}×  {path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
