#!/usr/bin/env python3
"""Emit one ALDC efficiency event from a script or an agent's Bash call.

    python emit.py AldcRun  tier=MEDIUM wps=3 waves=2 fixLoops=1 stops=3 lane=ran \
                            testsPassed=12 testsFailed=0 --numstat-base <git-ref>
    python emit.py AldcLane result=ran lockWaitS=4.2 publishS=31 runS=18 passed=12 failed=0
    python emit.py AldcRead action=blocked lines=1840 chars=90211
    python emit.py AldcHook hook=read-guard decision=deny ms=41

Writes the record to the plugin-data JSONL (the same file parse_subagent.py appends to, so
/al-metrics sees everything in one place) and sends it to Application Insights through
`appinsights.send_event()` — resolved the same way as every other event, including the
per-machine ALDC_METRICS_APPINSIGHTS_DISABLE kill switch.

PRIVACY: only the event names and keys allowlisted below are accepted. A numeric value
becomes a measurement; a string value is accepted only for the enum-like keys and only when
it matches a short token shape — so a path, a message or a command line can never be passed
through, even by mistake. `--numstat-base` reduces `git diff --numstat` to totals in-process;
no file name is ever kept.

Never fails the caller: any problem exits 0 with nothing sent.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

EVENTS: dict[str, set[str]] = {
    "AldcRun": {"tier", "wpsPlanned", "wps", "waves", "fixLoops", "stops", "lane",
                "testsPassed", "testsFailed", "reviewFirstPass", "reviews", "parallelism",
                "wallMinutes", "outcome"},
    "AldcLane": {"result", "lockWaitS", "publishS", "runS", "passed", "failed", "errored",
                 "skipped", "staleRecovered", "wave", "envType"},
    "AldcRead": {"action", "lines", "chars", "threshold"},
    "AldcHook": {"hook", "decision", "ms"},
}
STRING_KEYS = {"tier", "lane", "outcome", "result", "action", "hook", "decision", "envType"}
RE_TOKEN = re.compile(r"^[A-Za-z0-9_.:-]{1,40}$")
RE_NUM = re.compile(r"^-?\d+(?:\.\d+)?$")


def plugin_version() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        with open(os.path.join(here, "..", "..", ".claude-plugin", "plugin.json"), encoding="utf-8") as fh:
            return str(json.load(fh).get("version", ""))
    except (OSError, ValueError):
        return ""


def numstat_totals(base: str, cwd: str) -> dict[str, float]:
    """Added/removed line totals vs `base`, split AL vs everything else. Totals only."""
    try:
        out = subprocess.run(["git", "diff", "--numstat", base], cwd=cwd, capture_output=True,
                             text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    t = {"alAdded": 0, "alRemoved": 0, "otherAdded": 0, "otherRemoved": 0, "filesChanged": 0}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 3 or not parts[0].isdigit() or not parts[1].isdigit():
            continue
        kind = "al" if parts[2].lower().endswith(".al") else "other"
        t[f"{kind}Added"] += int(parts[0])
        t[f"{kind}Removed"] += int(parts[1])
        t["filesChanged"] += 1
    return {k: float(v) for k, v in t.items()}


def build(event: str, pairs: list[str], cwd: str) -> tuple[dict, dict] | None:
    allowed = EVENTS.get(event)
    if allowed is None:
        return None
    props: dict[str, str] = {}
    meas: dict[str, float] = {}
    for p in pairs:
        if "=" not in p:
            continue
        k, v = p.split("=", 1)
        if k not in allowed:
            continue
        if RE_NUM.match(v):
            meas[k] = float(v)
        elif k in STRING_KEYS and RE_TOKEN.match(v):
            props[k] = v
    v = plugin_version()
    if v:
        props["pluginVersion"] = v
    import usage

    ph = usage.project_hash(cwd)
    if ph:
        props["projectHash"] = ph
    props["project"] = os.path.basename(cwd.rstrip("/\\")) or "unknown"
    return props, meas


def main(argv: list[str]) -> int:
    if not argv or argv[0] == "--self-test":
        return self_test() if argv else 0
    event, rest = argv[0], argv[1:]
    base = ""
    if "--numstat-base" in rest:
        i = rest.index("--numstat-base")
        base = rest[i + 1] if i + 1 < len(rest) else ""
        rest = rest[:i] + rest[i + 2:]
    cwd = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        built = build(event, rest, cwd)
        if not built:
            return 0
        props, meas = built
        if base and RE_TOKEN.match(base):
            meas.update(numstat_totals(base, cwd))
        rec = {"schema": 2, "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "event": event, "props": props, "measurements": meas}
        data = os.environ.get("CLAUDE_PLUGIN_DATA") or os.path.join(
            os.path.expanduser("~"), ".claude", "aldc-plugin-data")
        out = os.path.join(data, "metrics", "aldc-metrics.jsonl")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, sort_keys=True) + "\n")
        if event == "AldcRun":
            # session_end.py joins this onto the session total: tokens per changed AL line.
            with open(os.path.join(os.path.dirname(out), "last-run.json"), "w", encoding="utf-8") as fh:
                json.dump({"ts": rec["ts"], "measurements": meas, "props": props}, fh)
        import appinsights

        appinsights.send_event(event, props, meas, ts=rec["ts"])
    except Exception:  # telemetry must never disturb the caller
        pass
    return 0


def self_test() -> int:
    cwd = os.getcwd()
    b = build("AldcRun", ["tier=MEDIUM", "wps=3", "lane=ran", "outcome=C:/Customer/secret.al",
                          "evil=1", "stops=2.5"], cwd)
    lane = build("AldcLane", ["result=ran", "publishS=31.5", "envType=Sandbox"], cwd)
    checks = [
        ("known event built", b is not None),
        ("string enum kept", b and b[0].get("tier") == "MEDIUM" and b[0].get("lane") == "ran"),
        ("numbers are measurements", b and b[1] == {"wps": 3.0, "stops": 2.5}),
        ("path-shaped value rejected", b and "outcome" not in b[0]),
        ("unknown key rejected", b and "evil" not in b[1]),
        ("unknown event rejected", build("Evil", ["x=1"], cwd) is None),
        ("lane event", lane and lane[1]["publishS"] == 31.5 and lane[0]["envType"] == "Sandbox"),
        ("numstat of a bad ref is empty, not an error", numstat_totals("no-such-ref-xyz", cwd) in ({}, {
            "alAdded": 0.0, "alRemoved": 0.0, "otherAdded": 0.0, "otherRemoved": 0.0, "filesChanged": 0.0})),
    ]
    ok = True
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
