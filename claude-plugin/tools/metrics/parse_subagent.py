#!/usr/bin/env python3
"""Extract ALDC quality metrics from a SubagentStop payload.

Reads the hook JSON on stdin, matches the symbolic markers the ALDC agents emit, and appends
one JSONL record. Called by capture_subagent.sh; not meant to be run by hand except for
testing (`--self-test`).

PRIVACY IS THE POINT, so it is enforced here rather than trusted: the record is assembled
field by field from regex captures, never by copying any part of the message. The only
free-text that can reach the file is a BCQuality knowledge path — public Microsoft content,
shape-validated below — and an enum-checked verdict. No message body, no customer AL, no
repo paths, no full cwd.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

SCHEMA = 1

# Only our own agents. agent_type arrives as "plugin_<plugin>:<agent>" for plugin agents, so
# match on the suffix.
TRACKED = ("al-review-subagent", "al-implement-subagent", "dredd", "al-planning-subagent")

# --- markers -----------------------------------------------------------------------------
# Implementer symbolic line:  📐 instr ✓ · 📚 bcq 5/6 applied · 🧠 …
RE_IMPL = re.compile(r"📚\s*bcq\s+(\d+)\s*/\s*(\d+)\s+applied")
RE_IMPL_NONE = re.compile(r"📚\s*bcq\s*(?:·\s*)?none")
# Review accounting: 📚 6 prescribed · 5 applied · 1 deviated (0 undeclared) · 3 newly cited · 2 agent findings
RE_REV = re.compile(
    r"📚\s*(\d+)\s+prescribed\s*·\s*(\d+)\s+applied\s*·\s*(\d+)\s+deviated\s*"
    r"\((\d+)\s+undeclared\)\s*·\s*(\d+)\s+newly\s+cited\s*·\s*(\d+)\s+agent\s+findings"
)
RE_INDEP = re.compile(r"🧭\s*independence-ratio:\s*(\d+)\s*/\s*(\d+)")
RE_NOT_MOUNTED = re.compile(r"⚪\s*BCQuality\s+not\s+mounted", re.I)
RE_MOUNTED_SHA = re.compile(r"🟢\s*BCQuality[^\n]*?\b([0-9a-f]{7,40})\b")
RE_PHASE = re.compile(r"(?:Phase|Fase)\s+(\d+)\b", re.I)
RE_VERDICT = re.compile(
    r"\b(APPROVED_WITH_RECOMMENDATIONS|APPROVED|NEEDS_REVISION|FAILED|"
    r"PASS_WITH_FINDINGS|CONCERNS|PASS)\b"
)
VERDICTS = {
    "APPROVED", "APPROVED_WITH_RECOMMENDATIONS", "NEEDS_REVISION", "FAILED",
    "PASS", "PASS_WITH_FINDINGS", "CONCERNS",
}
RE_SEVERITY = re.compile(r"\*\*\[(CRITICAL|MAJOR|MINOR)\]\*\*")
# Deviations block: everything between the heading and the next heading.
RE_DEV_BLOCK = re.compile(r"###\s*Knowledge Deviations(.*?)(?:\n#{1,3}\s|\Z)", re.S)
RE_DEV_NONE = re.compile(r"^\s*[-*]?\s*none\s*$", re.I | re.M)

# A BCQuality knowledge path and nothing else. Anchored to the three layer roots so a
# customer file path can never be mistaken for one.
RE_KNOWLEDGE = re.compile(
    r"\b((?:microsoft|community|custom)/knowledge/[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*\.md)\b"
)

MAX_KNOWLEDGE = 40  # a record is a measurement, not an archive


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def short_agent(agent_type: str) -> str | None:
    """'plugin_bc-dev:al-review-subagent' -> 'al-review-subagent', if we track it."""
    tail = agent_type.split(":")[-1].strip() if agent_type else ""
    return tail if tail in TRACKED else None


def build_record(payload: dict) -> dict | None:
    agent = short_agent(str(payload.get("agent_type", "")))
    if not agent:
        return None

    msg = payload.get("last_assistant_message") or ""
    if not isinstance(msg, str) or not msg:
        return None

    rec: dict = {
        "schema": SCHEMA,
        "ts": utcnow(),
        # Truncated: enough to correlate records from one run, not enough to identify it.
        "session": str(payload.get("session_id", ""))[:8],
        # Basename only — never the full path into someone's filesystem.
        "project": os.path.basename(str(payload.get("cwd", "")).rstrip("/\\")) or "unknown",
        "agent": agent,
    }

    m = RE_PHASE.search(msg)
    if m:
        rec["phase"] = int(m.group(1))

    bcq: dict = {}
    if RE_NOT_MOUNTED.search(msg):
        bcq["mounted"] = False
    else:
        m = RE_MOUNTED_SHA.search(msg)
        if m:
            bcq["mounted"] = True
            bcq["sha"] = m.group(1)

    m = RE_REV.search(msg)
    if m:
        p, a, d, u, c, g = (int(x) for x in m.groups())
        bcq.update({"prescribed": p, "applied": a, "deviated": d,
                    "undeclared": u, "cited": c, "agent_findings": g})
        bcq.setdefault("mounted", True)
    elif (m := RE_IMPL.search(msg)):
        a, p = int(m.group(1)), int(m.group(2))
        bcq.update({"prescribed": p, "applied": a, "deviated": max(p - a, 0)})
        bcq.setdefault("mounted", True)
    elif RE_IMPL_NONE.search(msg):
        bcq.update({"prescribed": 0, "applied": 0, "deviated": 0})

    m = RE_INDEP.search(msg)
    if m:
        num, den = int(m.group(1)), int(m.group(2))
        bcq["agent_findings"] = num
        bcq["total_findings"] = den
        bcq["independence_ratio"] = round(num / den, 3) if den else None

    if bcq:
        rec["bcq"] = bcq

    sev = RE_SEVERITY.findall(msg)
    if sev:
        rec["findings"] = {
            "critical": sev.count("CRITICAL"),
            "major": sev.count("MAJOR"),
            "minor": sev.count("MINOR"),
        }

    m = RE_VERDICT.search(msg)
    if m and m.group(1) in VERDICTS:
        rec["verdict"] = m.group(1)

    # Declared deviations: count them, and keep the knowledge paths they name.
    m = RE_DEV_BLOCK.search(msg)
    if m:
        block = m.group(1)
        declared = [] if RE_DEV_NONE.search(block) else RE_KNOWLEDGE.findall(block)
        rec["deviations_declared"] = sorted(set(declared))
        if "bcq" in rec:
            rec["bcq"]["declared"] = len(set(declared))

    cited = sorted(set(RE_KNOWLEDGE.findall(msg)))
    if cited:
        rec["knowledge"] = cited[:MAX_KNOWLEDGE]
        if len(cited) > MAX_KNOWLEDGE:
            rec["knowledge_truncated"] = len(cited) - MAX_KNOWLEDGE

    # A record with no BCQuality signal and no findings measures nothing — don't store noise.
    if "bcq" not in rec and "findings" not in rec and "verdict" not in rec:
        return None
    return rec


def append_jsonl(path: str, rec: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")


def project_lane(cwd: str) -> str | None:
    """Opt-in by existence: we write there only if the directory is already present."""
    if not cwd:
        return None
    d = os.path.join(cwd, ".github", "metrics")
    return os.path.join(d, "aldc-metrics.jsonl") if os.path.isdir(d) else None


def endpoint_lane(rec: dict, log) -> None:
    """Opt-in by configuration. No secret ships in the plugin: the endpoint and token come
    from the environment, set by whoever runs the estate."""
    url = os.environ.get("ALDC_METRICS_ENDPOINT", "").strip()
    if not url:
        return
    if not url.startswith("https://"):
        log(f"endpoint lane skipped: refusing non-https endpoint {url[:40]}")
        return
    try:
        import urllib.request

        body = json.dumps(rec, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(url, data=body, method="POST")
        req.add_header("Content-Type", "application/json")
        tok = os.environ.get("ALDC_METRICS_TOKEN", "").strip()
        if tok:
            req.add_header("Authorization", f"Bearer {tok}")
        with urllib.request.urlopen(req, timeout=3) as resp:
            log(f"endpoint lane {resp.status}")
    except Exception as exc:  # never let the network fail a session
        log(f"endpoint lane failed (non-fatal): {type(exc).__name__}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=False, default="")
    ap.add_argument("--log", required=False, default="")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    def log(msg: str) -> None:
        if not args.log:
            return
        try:
            os.makedirs(os.path.dirname(args.log), exist_ok=True)
            with open(args.log, "a", encoding="utf-8") as fh:
                fh.write(f"{utcnow()} {msg}\n")
        except OSError:
            pass

    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, OSError):
        return 0
    if not isinstance(payload, dict):
        return 0

    rec = build_record(payload)
    if rec is None:
        return 0

    if args.out:
        try:
            append_jsonl(args.out, rec)
        except OSError as exc:
            log(f"plugin-data lane failed: {type(exc).__name__}")

    lane = project_lane(str(payload.get("cwd", "")))
    if lane:
        try:
            append_jsonl(lane, rec)
        except OSError as exc:
            log(f"project lane failed: {type(exc).__name__}")

    endpoint_lane(rec, log)
    return 0


def self_test() -> int:
    """Exercised by tools/metrics/test_parse.sh; keep the fixtures honest."""
    review = (
        "## Code Review: Phase 3\n\n**Status:** APPROVED_WITH_RECOMMENDATIONS\n\n"
        "**BCQuality accounting:**\n"
        "`📚 6 prescribed · 5 applied · 1 deviated (0 undeclared) · 3 newly cited · 2 agent findings`\n"
        "`🧭 independence-ratio: 2/7`\n"
        "🟢 BCQuality ad8ccde\n"
        "- **[MAJOR]** something at App/Src/Secret.Codeunit.al:42\n"
        "- **[MINOR]** other\n"
        "cites microsoft/knowledge/events/add-new-event-parameters-at-the-end.md and "
        "custom/knowledge/style/dsc-prefix.md\n"
    )
    impl = (
        "## Phase 2 Implementation Summary\n"
        "📐 instr ✓ · 📚 bcq 4/5 applied · 🧠 skill-events·EventSub\n"
        "### Knowledge Deviations\n"
        "- `microsoft/knowledge/performance/use-setloadfields-for-partial-records.md` — table has 6 fields\n"
        "### Objects Created\n- Codeunit 50100\n"
    )
    ok = True

    r = build_record({"agent_type": "plugin_bc-dev:al-review-subagent",
                      "session_id": "abcdef1234", "cwd": "/home/x/CustomerProj",
                      "last_assistant_message": review})
    checks = [
        ("review parsed", r is not None),
        ("phase", r and r.get("phase") == 3),
        ("project basename only", r and r.get("project") == "CustomerProj"),
        ("prescribed", r and r["bcq"]["prescribed"] == 6),
        ("undeclared", r and r["bcq"]["undeclared"] == 0),
        ("independence", r and r["bcq"]["independence_ratio"] == round(2 / 7, 3)),
        ("sha", r and r["bcq"]["sha"] == "ad8ccde"),
        ("verdict", r and r["verdict"] == "APPROVED_WITH_RECOMMENDATIONS"),
        ("severities", r and r["findings"] == {"critical": 0, "major": 1, "minor": 1}),
        ("knowledge captured", r and len(r["knowledge"]) == 2),
        ("NO customer path leaked", r and "Secret.Codeunit.al" not in json.dumps(r)),
        ("NO message body leaked", r and "something at" not in json.dumps(r)),
    ]

    r2 = build_record({"agent_type": "al-implement-subagent", "session_id": "s",
                       "cwd": "/p/Proj", "last_assistant_message": impl})
    checks += [
        ("impl parsed", r2 is not None),
        ("impl applied/prescribed", r2 and r2["bcq"]["applied"] == 4 and r2["bcq"]["prescribed"] == 5),
        ("impl deviated derived", r2 and r2["bcq"]["deviated"] == 1),
        ("impl declared", r2 and r2["bcq"]["declared"] == 1),
        ("impl deviation path", r2 and r2["deviations_declared"][0].endswith("use-setloadfields-for-partial-records.md")),
    ]

    checks.append(("untracked agent ignored",
                   build_record({"agent_type": "Explore", "last_assistant_message": review}) is None))
    checks.append(("noise record dropped",
                   build_record({"agent_type": "dredd", "last_assistant_message": "hello"}) is None))

    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
