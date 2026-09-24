#!/usr/bin/env python3
"""SessionEnd: one AldcSession event with the whole session's efficiency — the main
transcript plus every subagent transcript beside it (<stem>/subagents/agent-*.jsonl).

This is the number that answers "how much did that feature cost": subagent records
(parse_subagent.py) show where the tokens went, this shows the total, including the
orchestrating conversation itself, which no SubagentStop ever sees.

Only runs its sums when the session touched an AL project (an app.json at or under cwd) —
a Blazor or NAV session is not ours to measure. Same privacy rule as usage.py: counts and
allowlisted identifiers only. Never fails the session.
"""

from __future__ import annotations

import glob
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import usage  # noqa: E402


def aggregate(transcript: str) -> dict | None:
    main = usage.summarize(transcript) if transcript else None
    if not main:
        return None
    subs_dir = os.path.join(os.path.splitext(transcript)[0], "subagents")
    tok = Counter(main["tokens"])
    main_tok = dict(main["tokens"])
    by_agent: Counter = Counter()
    n_sub = 0
    for p in glob.glob(os.path.join(subs_dir, "agent-*.jsonl")):
        s = usage.summarize(p)
        if not s:
            continue
        n_sub += 1
        tok.update(s["tokens"])
        agent = "other"
        try:
            with open(p[:-len(".jsonl")] + ".meta.json", encoding="utf-8") as fh:
                agent = usage.allow_agent(str(json.load(fh).get("agentType", ""))) or "other"
        except (OSError, ValueError):
            pass
        by_agent[agent] += s["tokens"].get("total", 0)
    return {
        "tokens": dict(tok),
        "mainTokens": main_tok,
        "subagents": n_sub,
        "tokensByAgent": dict(by_agent),
        "wallSeconds": main.get("wallSeconds"),
        "humanTurns": main.get("humanTurns"),
        "asks": main.get("asks"),
        "spawns": main.get("spawns"),
        "model": main.get("model", ""),
    }


def _join_last_run(payload: dict, props: dict, meas: dict) -> None:
    """If a conductor run finished during this session (emit.py AldcRun wrote last-run.json),
    attach its changed-line totals and the headline KPI: tokens per changed AL line."""
    data = os.environ.get("CLAUDE_PLUGIN_DATA") or os.path.join(
        os.path.expanduser("~"), ".claude", "aldc-plugin-data")
    p = os.path.join(data, "metrics", "last-run.json")
    try:
        with open(p, encoding="utf-8") as fh:
            run = json.load(fh)
        start = usage.first_timestamp(str(payload.get("transcript_path", "")))
        if not start or str(run.get("ts", "")) < start[:19]:
            return
        m = run.get("measurements", {})
        al = float(m.get("alAdded", 0)) + float(m.get("alRemoved", 0))
        for k in ("alAdded", "alRemoved", "wps", "waves", "fixLoops", "stops"):
            if k in m:
                meas[f"run{k[:1].upper()}{k[1:]}"] = float(m[k])
        if al and meas.get("tokensTotal"):
            meas["tokensPerAlLine"] = round(meas["tokensTotal"] / al, 1)
        if run.get("props", {}).get("tier"):
            props["tier"] = run["props"]["tier"]
        os.remove(p)
    except (OSError, ValueError, TypeError):
        pass


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, OSError):
        return 0
    if not isinstance(payload, dict):
        return 0
    cwd = str(payload.get("cwd", ""))
    ph = usage.project_hash(cwd)
    if not ph:
        return 0
    try:
        agg = aggregate(str(payload.get("transcript_path", "")))
        if not agg:
            return 0
        props = {"projectHash": ph, "project": os.path.basename(cwd.rstrip("/\\")) or "unknown",
                 "session": str(payload.get("session_id", ""))[:8], "model": agg.pop("model")}
        reason = str(payload.get("reason", ""))
        if reason.isidentifier() and len(reason) <= 30:
            props["reason"] = reason
        here = os.path.dirname(os.path.abspath(__file__))
        try:
            with open(os.path.join(here, "..", "..", ".claude-plugin", "plugin.json"), encoding="utf-8") as fh:
                props["pluginVersion"] = str(json.load(fh).get("version", ""))
        except (OSError, ValueError):
            pass
        meas = usage.flatten(agg)
        _join_last_run(payload, props, meas)
        rec = {"schema": 2, "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "event": "AldcSession", "props": props, "measurements": meas}
        data = os.environ.get("CLAUDE_PLUGIN_DATA") or os.path.join(
            os.path.expanduser("~"), ".claude", "aldc-plugin-data")
        out = os.path.join(data, "metrics", "aldc-metrics.jsonl")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, sort_keys=True) + "\n")
        import appinsights

        appinsights.send_event("AldcSession", props, meas, ts=rec["ts"],
                               operation_id=props["session"])
    except Exception:
        pass
    return 0


def self_test() -> int:
    import tempfile

    d = tempfile.mkdtemp()
    main_t = os.path.join(d, "sess.jsonl")
    line = {"type": "assistant", "requestId": "r", "timestamp": "2026-01-01T00:00:00Z",
            "message": {"model": "claude-opus-5-5", "usage": {"input_tokens": 1, "output_tokens": 2}}}
    with open(main_t, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(line) + "\n")
    os.makedirs(os.path.join(d, "sess", "subagents"))
    sub = os.path.join(d, "sess", "subagents", "agent-x")
    with open(sub + ".jsonl", "w", encoding="utf-8") as fh:
        line["message"]["usage"] = {"input_tokens": 10, "output_tokens": 20}
        fh.write(json.dumps(line) + "\n")
    with open(sub + ".meta.json", "w", encoding="utf-8") as fh:
        json.dump({"agentType": "bc-dev:al-implement-subagent"}, fh)
    a = aggregate(main_t)
    checks = [
        ("aggregated", a is not None),
        ("total includes subagents", a and a["tokens"]["total"] == 33),
        ("main tokens separate", a and a["mainTokens"]["total"] == 3),
        ("by agent", a and a["tokensByAgent"] == {"al-implement-subagent": 30}),
        ("no project -> no event", usage.project_hash(d) == ""),
    ]
    ok = True
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else main())
