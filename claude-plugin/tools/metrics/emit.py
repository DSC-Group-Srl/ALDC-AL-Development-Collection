#!/usr/bin/env python3
"""Emit one ALDC efficiency event from a script or an agent's Bash call.

    python emit.py AldcRun  tier=MEDIUM wps=3 waves=2 fixLoops=1 stops=3 lane=ran \
                            testsPassed=12 testsFailed=0 --numstat-base <git-ref>
    python emit.py AldcLane result=ran lockWaitS=4.2 publishS=31 runS=18 passed=12 failed=0
    python emit.py AldcRead action=blocked lines=1840 chars=90211
    python emit.py AldcHook hook=read-guard decision=deny ms=41

Live progress (al-conductor), read by the GITCloner control panel:

    python emit.py AldcRunStart req=<req> tier=MEDIUM wpsPlanned=3 waves=2 lane=ran
    python emit.py AldcWave stage=start wave=1 waves=2 wps=2
    python emit.py AldcWp   stage=start wave=1 wp=1
    python emit.py AldcWp   stage=end   wave=1 wp=1 result=done
    python emit.py AldcWave stage=end   wave=1 waves=2 verdict=APPROVED lane=ran passed=14 failed=0
    python emit.py AldcAlive agent=al-implement-subagent tool=Bash        (the alive hook)

Every event of a run carries `req` and `runId` without the conductor repeating them: they are
kept in a per-session LIVE SNAPSHOT, `~/.claude/aldc-plugin-data/live/<session>.json`, which
this script updates on each live event. The snapshot also supplies durations (`durationS` on a
`stage=end` that does not pass one) and the run's `wallMinutes` when the conductor reports 0.
The snapshot never leaves the machine; it is what a local panel reads with no latency, while
Application Insights carries the same events to the team view.

Writes the record to the plugin-data JSONL (the same file parse_subagent.py appends to, so
/al-metrics sees everything in one place) and sends it to Application Insights through
`appinsights.send_event()` — resolved the same way as every other event, including the
per-machine ALDC_METRICS_APPINSIGHTS_DISABLE kill switch.

PRIVACY: only the event names and keys allowlisted below are accepted. A numeric value
becomes a measurement; a string value is accepted only for the enum-like keys and only when
it matches a short token shape — so a path, a message or a command line can never be passed
through, even by mistake. `--numstat-base` reduces `git diff --numstat` to totals in-process;
no file name is ever kept. Identity (ident.py) adds a user hash, the e-mail's local part, a
machine hash and the session prefix.

Never fails the caller: any problem exits 0 with nothing sent.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

RUN_KEYS = {"req", "runId"}
EVENTS: dict[str, set[str]] = {
    "AldcRun": {"tier", "wpsPlanned", "wps", "waves", "fixLoops", "stops", "lane",
                "testsPassed", "testsFailed", "reviewFirstPass", "reviews", "parallelism",
                "wallMinutes", "outcome"} | RUN_KEYS,
    "AldcLane": {"result", "lockWaitS", "publishS", "runS", "passed", "failed", "errored",
                 "skipped", "staleRecovered", "wave", "envType"} | RUN_KEYS,
    "AldcRead": {"action", "lines", "chars", "threshold"},
    "AldcHook": {"hook", "decision", "ms"},
    "AldcRunStart": {"tier", "wpsPlanned", "waves", "lane"} | RUN_KEYS,
    "AldcWave": {"stage", "wave", "waves", "wps", "verdict", "lane", "passed", "failed",
                 "fixLoops", "durationS"} | RUN_KEYS,
    "AldcWp": {"stage", "wave", "wp", "result", "fixRound", "durationS"} | RUN_KEYS,
    "AldcAlive": {"agent", "tool"} | RUN_KEYS,
}
LIVE_EVENTS = {"AldcRunStart", "AldcWave", "AldcWp", "AldcRun", "AldcLane"}
STRING_KEYS = {"tier", "lane", "outcome", "result", "action", "hook", "decision", "envType",
               "stage", "verdict", "req", "runId", "agent", "tool"}
RE_TOKEN = re.compile(r"^[A-Za-z0-9_.:-]{1,40}$")
RE_NUM = re.compile(r"^-?\d+(?:\.\d+)?$")
# Keys that stay strings even when they look numeric (a req called "042").
NEVER_NUMERIC = {"req", "runId"}


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


def build(event: str, pairs: list[str], cwd: str, session: str = "") -> tuple[dict, dict] | None:
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
        if RE_NUM.match(v) and k not in NEVER_NUMERIC:
            meas[k] = float(v)
        elif k in STRING_KEYS and RE_TOKEN.match(v):
            props[k] = v
    v = plugin_version()
    if v:
        props["pluginVersion"] = v
    import ident
    import usage

    ph = usage.project_hash(cwd)
    if ph:
        props["projectHash"] = ph
    props["project"] = usage.project_name(cwd)
    props.update(ident.props(session))
    return props, meas


# --- live snapshot -------------------------------------------------------------------------

def live_dir() -> str:
    # One fixed place, whoever writes: hooks get CLAUDE_PLUGIN_DATA, an agent's Bash call does
    # not, and the panel must not have to guess which.
    return os.environ.get("ALDC_LIVE_DIR") or os.path.join(
        os.path.expanduser("~"), ".claude", "aldc-plugin-data", "live")


def _now() -> float:
    return round(time.time(), 3)


def load_live(session: str) -> dict:
    if not session:
        return {}
    try:
        with open(os.path.join(live_dir(), f"{session}.json"), encoding="utf-8") as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_live(session: str, snap: dict) -> None:
    d = live_dir()
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, f"{session}.json")
    tmp = f"{p}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(snap, fh, indent=1, sort_keys=True)
    os.replace(tmp, p)


def run_id(props: dict, req: str) -> str:
    """Stable for one requirement of one project and user — so a run resumed in a new session
    keeps its id."""
    key = f"{props.get('projectHash') or props.get('project', '')}:{req}:{props.get('userHash', '')}"
    return hashlib.sha256(key.encode()).hexdigest()[:10]


def apply_live(event: str, props: dict, meas: dict, snap: dict, cwd: str, session: str,
               now: float | None = None) -> dict:
    """Fold one event into the session snapshot and enrich the event from it (req/runId,
    durations, wallMinutes). Mutates props/meas; returns the new snapshot."""
    now = _now() if now is None else now
    if event == "AldcRunStart":
        req = props.get("req") or snap.get("req") or "run"
        rid = props.get("runId") or run_id(props, req)
        resumed = snap.get("runId") == rid and not snap.get("outcome")
        snap = snap if resumed else {"wps": {}, "waveLog": []}
        snap.update({"req": req, "runId": rid, "startedAt": snap.get("startedAt") or now,
                     "tier": props.get("tier") or snap.get("tier"),
                     "wavesPlanned": int(meas.get("waves") or snap.get("wavesPlanned") or 0),
                     "wpsPlanned": int(meas.get("wpsPlanned") or snap.get("wpsPlanned") or 0)})
        snap.pop("outcome", None)
        snap.pop("endedAt", None)
    if snap.get("runId"):
        props.setdefault("req", snap.get("req", ""))
        props.setdefault("runId", snap["runId"])

    wave = int(meas["wave"]) if "wave" in meas else snap.get("wave")
    stage = props.get("stage", "")
    if event == "AldcWave" and wave:
        if meas.get("waves"):
            snap["wavesPlanned"] = int(meas["waves"])
        if stage == "start":
            snap.update({"wave": wave, "waveStage": "running", "waveStartedAt": now})
        elif stage == "end":
            if "durationS" not in meas and snap.get("wave") == wave and snap.get("waveStartedAt"):
                meas["durationS"] = round(now - float(snap["waveStartedAt"]), 1)
            entry = {"wave": wave, "endedAt": now, "durationS": meas.get("durationS"),
                     "verdict": props.get("verdict"), "lane": props.get("lane"),
                     "passed": meas.get("passed"), "failed": meas.get("failed")}
            snap["waveLog"] = [w for w in snap.get("waveLog", []) if w.get("wave") != wave] + [entry]
            snap.update({"wave": wave, "waveStage": "done"})
    elif event == "AldcWp" and "wp" in meas:
        key = str(int(meas["wp"]))
        wp = dict(snap.get("wps", {}).get(key) or {})
        if stage == "start":
            wp.update({"wave": wave, "state": "running", "startedAt": now, "endedAt": None,
                       "fixRound": int(meas.get("fixRound") or 0)})
        elif stage == "end":
            if "durationS" not in meas and wp.get("startedAt"):
                meas["durationS"] = round(now - float(wp["startedAt"]), 1)
            wp.update({"wave": wave or wp.get("wave"), "state": props.get("result") or "done",
                       "endedAt": now, "durationS": meas.get("durationS")})
        snap.setdefault("wps", {})[key] = wp
    elif event == "AldcLane":
        snap["lane"] = {"result": props.get("result"), "at": now,
                        "passed": meas.get("passed"), "failed": meas.get("failed")}
    elif event == "AldcRun":
        if not meas.get("wallMinutes") and snap.get("startedAt"):
            meas["wallMinutes"] = round((now - float(snap["startedAt"])) / 60, 1)
        snap.update({"outcome": props.get("outcome") or "done", "endedAt": now})

    snap.update({"schema": 1, "session": session, "cwd": cwd, "project": props.get("project"),
                 "projectHash": props.get("projectHash"), "user": props.get("user"),
                 "where": props.get("where"), "updatedAt": now})
    return snap


def main(argv: list[str]) -> int:
    if not argv or argv[0] == "--self-test":
        return self_test() if argv else 0
    event, rest = argv[0], argv[1:]
    base = ""
    if "--numstat-base" in rest:
        i = rest.index("--numstat-base")
        base = rest[i + 1] if i + 1 < len(rest) else ""
        rest = rest[:i] + rest[i + 2:]
    session = ""
    if "--session" in rest:
        i = rest.index("--session")
        session = rest[i + 1] if i + 1 < len(rest) else ""
        rest = rest[:i] + rest[i + 2:]
    cwd = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        built = build(event, rest, cwd, session)
        if not built:
            return 0
        props, meas = built
        if base and RE_TOKEN.match(base):
            meas.update(numstat_totals(base, cwd))
        import ident

        full_session = ident.session_id(session)
        if full_session and event in LIVE_EVENTS | {"AldcAlive"}:
            snap = load_live(full_session)
            if event == "AldcAlive":
                # Read-only: the heartbeat carries the run's position to the team view.
                if snap.get("runId") and not snap.get("outcome"):
                    props.setdefault("req", snap.get("req", ""))
                    props.setdefault("runId", snap["runId"])
                    for k in ("wave", "wavesPlanned"):
                        if snap.get(k):
                            meas[k] = float(snap[k])
            elif event != "AldcLane" or snap.get("runId"):
                save_live(full_session, apply_live(event, props, meas, snap, cwd, full_session))
        rec = {"schema": 2, "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "event": event, "props": props, "measurements": meas}
        data = os.environ.get("CLAUDE_PLUGIN_DATA") or os.path.join(
            os.path.expanduser("~"), ".claude", "aldc-plugin-data")
        out = os.path.join(data, "metrics", "aldc-metrics.jsonl")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if event != "AldcAlive":  # heartbeats are for the live view, not the history file
            with open(out, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(rec, sort_keys=True) + "\n")
        if event == "AldcRun":
            # session_end.py joins this onto the session total: tokens per changed AL line.
            with open(os.path.join(os.path.dirname(out), "last-run.json"), "w", encoding="utf-8") as fh:
                json.dump({"ts": rec["ts"], "measurements": meas, "props": props}, fh)
        import appinsights

        appinsights.send_event(event, props, meas, ts=rec["ts"],
                               operation_id=props.get("runId") or props.get("session", ""))
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
        ("project is a name, not a path", b and "/" not in b[0]["project"] and "\\" not in b[0]["project"]),
        ("identity dimension present", b and b[0].get("where") in ("local", "cloud")),
    ]

    # Live snapshot: a two-wave run, timed with a fake clock.
    s = "sess-0001-self-test"
    snap: dict = {}

    def ev(event: str, pairs: list[str], t: float) -> tuple[dict, dict]:
        nonlocal snap
        p, m = build(event, pairs, cwd, s)
        snap = apply_live(event, p, m, snap, cwd, s, now=t)
        return p, m

    ev("AldcRunStart", ["req=U-04", "tier=MEDIUM", "wpsPlanned=2", "waves=2"], 1000)
    w1, _ = ev("AldcWave", ["stage=start", "wave=1", "waves=2", "wps=1"], 1010)
    ev("AldcWp", ["stage=start", "wave=1", "wp=1"], 1011)
    _, wpm = ev("AldcWp", ["stage=end", "wave=1", "wp=1", "result=done"], 1311)
    _, wm = ev("AldcWave", ["stage=end", "wave=1", "verdict=APPROVED", "lane=ran", "passed=14"], 1610)
    ev("AldcWave", ["stage=start", "wave=2"], 1620)
    ev("AldcLane", ["result=ran", "passed=20", "failed=0"], 1700)
    _, rm = ev("AldcRun", ["tier=MEDIUM", "wallMinutes=0", "outcome=done"], 2200)
    rid = snap.get("runId", "")
    checks += [
        ("runId derived and stable", len(rid) == 10 and rid == run_id(w1, "U-04")),
        ("req/runId copied onto later events", w1.get("req") == "U-04" and w1.get("runId") == rid),
        ("req stays a string", build("AldcRunStart", ["req=042"], cwd)[0].get("req") == "042"),
        ("wp duration from snapshot", wpm.get("durationS") == 300.0),
        ("wave duration from snapshot", wm.get("durationS") == 600.0),
        ("wave log kept", [w["wave"] for w in snap["waveLog"]] == [1]),
        ("current wave tracked", snap.get("wave") == 2 and snap.get("waveStage") == "running"),
        ("lane result tracked", snap.get("lane", {}).get("passed") == 20.0),
        ("wallMinutes 0 is replaced", rm.get("wallMinutes") == 20.0),
        ("run closed", snap.get("outcome") == "done"),
        ("new run after a finished one starts clean",
         apply_live("AldcRunStart", *build("AldcRunStart", ["req=U-05"], cwd, s), dict(snap), cwd, s,
                    now=3000).get("waveLog") == []),
    ]
    ok = True
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
