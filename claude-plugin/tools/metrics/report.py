#!/usr/bin/env python3
"""Aggregate the ALDC quality metrics JSONL into a report.

Arithmetic belongs in code, not in a model's head: `/bc-dev:al-metrics` runs this and renders
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
                key = (rec.get("ts"), rec.get("session"), rec.get("agent"), rec.get("phase"),
                       rec.get("event"))
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


# --- efficiency ---------------------------------------------------------------------------
# Tokens, time, cost. Fed by the `usage` block on subagent records (parse_subagent.py) and the
# event records written by session_end.py (AldcSession) and emit.py (AldcRun/AldcLane/AldcRead).

def load_prices() -> list[tuple[str, dict]]:
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        with open(os.path.join(here, "prices.json"), encoding="utf-8") as fh:
            raw = json.load(fh)
    except (OSError, ValueError):
        return []
    rows = [(k, v) for k, v in raw.items() if not k.startswith("_") and isinstance(v, dict)]
    return sorted(rows, key=lambda kv: -len(kv[0]))  # longest prefix first


def cost_usd(tokens: dict, model: str, prices: list[tuple[str, dict]]) -> float | None:
    p = next((v for k, v in prices if model and model.startswith(k)), None)
    if not p or not tokens:
        return None
    return (tokens.get("input", 0) * p["input"] + tokens.get("output", 0) * p["output"]
            + tokens.get("cacheCreation", 0) * p["cacheWrite"]
            + tokens.get("cacheRead", 0) * p["cacheRead"]) / 1_000_000


def _avg(xs: list[float]) -> float | None:
    xs = [x for x in xs if isinstance(x, (int, float))]
    return sum(xs) / len(xs) if xs else None


def _fmt(x: float | None, unit: str = "", dec: int = 0) -> str:
    if x is None:
        return "n/a"
    if unit == "tok":
        return f"{x / 1000:.0f}k" if x >= 1000 else f"{x:.0f}"
    return f"{x:.{dec}f}{unit}"


def efficiency(recs: list[dict]) -> dict:
    prices = load_prices()
    per_agent: dict[str, list[dict]] = {}
    for r in recs:
        if r.get("usage") and r.get("agent"):
            per_agent.setdefault(r["agent"], []).append(r["usage"])
    agents = {}
    for a, us in sorted(per_agent.items()):
        costs = [cost_usd(u.get("tokens", {}), u.get("model", ""), prices) for u in us]
        whole = sum(u.get("reads", {}).get("whole", 0) for u in us)
        ranged = sum(u.get("reads", {}).get("ranged", 0) for u in us)
        agents[a] = {
            "runs": len(us),
            "avgTokens": _avg([u.get("tokens", {}).get("total") for u in us]),
            "avgOutput": _avg([u.get("tokens", {}).get("output") for u in us]),
            "avgWallS": _avg([u.get("wallSeconds") for u in us]),
            "avgTurns": _avg([u.get("turns") for u in us]),
            "avgBuilds": _avg([u.get("builds") for u in us]),
            "wholeReadShare": round(whole / (whole + ranged), 2) if whole + ranged else None,
            "avgCostUsd": _avg([c for c in costs if c is not None]),
        }

    def events(name: str) -> list[dict]:
        return [r for r in recs if r.get("event") == name]

    sessions = events("AldcSession")
    by_version: dict[str, list[float]] = {}
    for s in sessions:
        v = s.get("props", {}).get("pluginVersion", "?")
        by_version.setdefault(v, []).append(s.get("measurements", {}).get("tokensTotal", 0))
    runs, lanes, reads = events("AldcRun"), events("AldcLane"), events("AldcRead")
    m = lambda rs, k: _avg([r.get("measurements", {}).get(k) for r in rs])  # noqa: E731
    return {
        "agents": agents,
        "sessions": {
            "count": len(sessions),
            "avgTokens": m(sessions, "tokensTotal"),
            "avgWallMin": (m(sessions, "wallSeconds") or 0) / 60 if sessions else None,
            "avgTokensPerAlLine": m(sessions, "tokensPerAlLine"),
            "byVersion": {v: _avg(xs) for v, xs in sorted(by_version.items())},
        },
        "runs": {"count": len(runs), "avgWps": m(runs, "wps"), "avgWaves": m(runs, "waves"),
                 "avgFixLoops": m(runs, "fixLoops"), "avgStops": m(runs, "stops"),
                 "avgParallelism": m(runs, "parallelism"),
                 "laneSkipped": sum(1 for r in runs if r.get("props", {}).get("lane") == "skipped")},
        "lane": {"count": len(lanes), "avgLockWaitS": m(lanes, "lockWaitS"),
                 "avgPublishS": m(lanes, "publishS"), "avgRunS": m(lanes, "runS"),
                 "failed": sum(int(r.get("measurements", {}).get("failed", 0)) for r in lanes)},
        "reads": {"blocked": sum(1 for r in reads if r.get("props", {}).get("action") == "blocked"),
                  "charsAvoided": sum(r.get("measurements", {}).get("chars", 0) for r in reads
                                      if r.get("props", {}).get("action") == "blocked")},
    }


def print_efficiency(e: dict) -> None:
    print()
    print("EFFICIENCY")
    print("-" * 78)
    if e["agents"]:
        print(f"{'agent':<30}{'runs':>5}{'avg tok':>9}{'avg out':>9}{'avg s':>7}"
              f"{'turns':>6}{'builds':>7}{'whole%':>7}{'avg $':>8}")
        for a, s in e["agents"].items():
            wr = s["wholeReadShare"]
            print(f"{a:<30}{s['runs']:>5}{_fmt(s['avgTokens'], 'tok'):>9}"
                  f"{_fmt(s['avgOutput'], 'tok'):>9}{_fmt(s['avgWallS']):>7}"
                  f"{_fmt(s['avgTurns']):>6}{_fmt(s['avgBuilds'], '', 1):>7}"
                  f"{(f'{wr:.0%}' if wr is not None else 'n/a'):>7}"
                  f"{_fmt(s['avgCostUsd'], '', 2):>8}")
    else:
        print("no per-agent usage recorded yet (needs bc-dev >= 8.0)")
    s = e["sessions"]
    if s["count"]:
        print(f"sessions {s['count']} · avg {_fmt(s['avgTokens'], 'tok')} tokens · "
              f"avg {_fmt(s['avgWallMin'], ' min', 1)} · tokens per changed AL line "
              f"{_fmt(s['avgTokensPerAlLine'])}")
        if len(s["byVersion"]) > 1:
            print("avg session tokens by version: " + " · ".join(
                f"{v} {_fmt(t, 'tok')}" for v, t in s["byVersion"].items()))
    r = e["runs"]
    if r["count"]:
        print(f"conductor runs {r['count']} · avg WPs {_fmt(r['avgWps'], '', 1)} · waves "
              f"{_fmt(r['avgWaves'], '', 1)} · fix loops {_fmt(r['avgFixLoops'], '', 1)} · "
              f"human stops {_fmt(r['avgStops'], '', 1)} · parallelism "
              f"{_fmt(r['avgParallelism'], 'x', 1)} · lane skipped {r['laneSkipped']}")
    ln = e["lane"]
    if ln["count"]:
        print(f"test lane {ln['count']} runs · lock wait {_fmt(ln['avgLockWaitS'], 's', 1)} · "
              f"publish {_fmt(ln['avgPublishS'], 's')} · run {_fmt(ln['avgRunS'], 's')} · "
              f"failed tests {ln['failed']}")
    rd = e["reads"]
    if rd["blocked"]:
        print(f"read-guard blocked {rd['blocked']} whole-file reads "
              f"(~{_fmt(rd['charsAvoided'] / 4, 'tok')} tokens avoided, est. 4 chars/token)")


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

    agg["efficiency"] = efficiency(recs)
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

    print_efficiency(agg["efficiency"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
