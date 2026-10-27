#!/usr/bin/env python3
"""Emit one ALDC efficiency event from a script or an agent's Bash call.

    python emit.py AldcRun  tier=MEDIUM wps=3 waves=2 fixLoops=1 stops=3 lane=ran \
                            testsPassed=12 testsFailed=0 --numstat-base <git-ref>
    python emit.py AldcLane result=ran lockWaitS=4.2 publishS=31 runS=18 passed=12 failed=0
    python emit.py AldcRead action=blocked lines=1840 chars=90211
    python emit.py AldcHook hook=read-guard decision=deny ms=41
    python emit.py AldcHook hook=freshdesk-guard decision=ask tool=createTicketNote calls=2

Live progress (al-conductor), read by the GITCloner control panel:

    python emit.py AldcRunStart req=<req> tier=MEDIUM wpsPlanned=3 waves=2 lane=ran
    python emit.py AldcWave stage=start wave=1 waves=2 wps=2
    python emit.py AldcWp   stage=start wave=1 wp=1
    python emit.py AldcWp   stage=end   wave=1 wp=1 result=done
    python emit.py AldcWave stage=end   wave=1 waves=2 verdict=APPROVED lane=ran passed=14 failed=0
    python emit.py AldcAlive agent=al-implement-subagent tool=Bash        (the alive hook)
    python emit.py AldcGate  gate=fixloop                 (right before a mid-run stop-and-ask)

Ex-ante scope, once per run, right after AldcRunStart (counts parsed from the plan, not
counted by the model):

    python emit.py AldcEstimate --plan <path-to-plan.md> [estP50Min=<n> estP80Min=<n>
                                estSource=<stima-sviluppo|manual|none> issueNo=<no> model=<id>]

Every event of a run carries `req` and `runId` without the conductor repeating them: they are
kept in a per-session LIVE SNAPSHOT, `~/.claude/aldc-plugin-data/live/<session>.json`, which
this script updates on each live event. The snapshot also supplies durations (`durationS` on a
`stage=end` that does not pass one) and the run's MEASURED duration: `wallMinutes` is always
computed from the snapshot (a value the conductor passes is kept as `reportedMinutes`), and
`activeSeconds` sums the gaps between the run's events: inside an open wave or WP in full (up
to OPEN_CAP_S — a compile or a lane run sends no event), between steps capped at IDLE_CAP_S,
so a session left open overnight does not count as work. An `AldcGate` marks a human ask: the
gap after it goes to `humanWaitSeconds` instead.

Resumes: `runId` is stable per project:req:user, so a run resumed in a new session keeps it.
The ATTEMPT REGISTRY (`runs.json`, beside the live directory) counts the sessions a run took
(`attempt` on every run event), sums active time across them (`activeSecondsTotal` on
AldcRun) and drops a second AldcRun for an attempt that already has an outcome. A req started
again after its run finished `done` is a REWORK: its own runId and `rework=<n>`.
The snapshot never leaves the machine; it is what a local panel reads with no latency, while
Application Insights carries the same events to the team view.

Writes the record to the plugin-data JSONL (the same file parse_subagent.py appends to, so
/al-metrics sees everything in one place) and sends it to Application Insights through
`appinsights.send_event()` — resolved the same way as every other event, including the
per-machine ALDC_METRICS_APPINSIGHTS_DISABLE kill switch.

PRIVACY: only the event names and keys allowlisted below are accepted. A numeric value
becomes a measurement; a string value is accepted only for the enum-like keys and only when
it matches a short token shape — so a path, a message or a command line can never be passed
through, even by mistake. `--numstat-base` reduces `git diff --numstat` to totals in-process,
and the object kind of each changed .al file to a count per kind; no file name is ever kept.
`--plan` reduces the plan to fixed, allowlisted counts the same way.
`ALDC_METRICS_EXCLUDE=1` marks every event `exclude=true` (dry runs, demos, self-tests).
Identity (ident.py) adds a user hash, the e-mail's local part, a machine hash and the session
prefix.

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

SCHEMA = 3  # 3: measured wallMinutes + reportedMinutes, activeSeconds, attempt, AldcEstimate,
#             objDone_* per kind, alAddedTest/alAddedProd, `schema` and `exclude` dimensions
IDLE_CAP_S = 600.0    # a gap between steps longer than this is idle, not work
OPEN_CAP_S = 7200.0   # a gap inside an open wave/WP counts in full, up to this

RUN_KEYS = {"req", "runId"}
EVENTS: dict[str, set[str]] = {
    # wallMinutes is still accepted from the conductor (older agent prompts pass it), but it
    # is kept as reportedMinutes; the wallMinutes that is sent is always measured.
    "AldcRun": {"tier", "wpsPlanned", "wps", "waves", "fixLoops", "stops", "lane",
                "testsPassed", "testsFailed", "reviewFirstPass", "reviews", "parallelism",
                "wallMinutes", "outcome"} | RUN_KEYS,
    # Everything else on AldcEstimate is parsed from --plan, never taken from the caller.
    "AldcEstimate": {"tier", "model", "estP50Min", "estP80Min", "estSource", "issueNo"} | RUN_KEYS,
    "AldcGate": {"gate"} | RUN_KEYS,
    "AldcLane": {"result", "lockWaitS", "publishS", "runS", "passed", "failed", "errored",
                 "skipped", "staleRecovered", "wave", "envType"} | RUN_KEYS,
    "AldcRead": {"action", "lines", "chars", "threshold"},
    # tool/calls: freshdesk-guard reports the allowlisted Freshdesk tool name (or "other") and
    # the session's call count - never a ticket id, text or tool_input.
    "AldcHook": {"hook", "decision", "ms", "tool", "calls"},
    "AldcRunStart": {"tier", "wpsPlanned", "waves", "lane"} | RUN_KEYS,
    "AldcWave": {"stage", "wave", "waves", "wps", "verdict", "lane", "passed", "failed",
                 "fixLoops", "durationS"} | RUN_KEYS,
    "AldcWp": {"stage", "wave", "wp", "result", "fixRound", "durationS"} | RUN_KEYS,
    "AldcAlive": {"agent", "tool"} | RUN_KEYS,
}
LIVE_EVENTS = {"AldcRunStart", "AldcWave", "AldcWp", "AldcRun", "AldcLane", "AldcEstimate",
               "AldcGate"}
# Events that advance a live run's active-time clock (AldcAlive included: it is the only
# signal while subagents work between two conductor events).
TICK_EVENTS = LIVE_EVENTS | {"AldcAlive"}
STRING_KEYS = {"tier", "lane", "outcome", "result", "action", "hook", "decision", "envType",
               "stage", "verdict", "req", "runId", "agent", "tool", "model", "estSource",
               "issueNo", "gate"}
# String keys whose value must also come from a closed set.
ENUM_VALUES = {"estSource": {"stima-sviluppo", "manual", "none"},
               "gate": {"fixloop", "conflict", "stall", "blocked", "contradiction", "other"}}
RE_TOKEN = re.compile(r"^[A-Za-z0-9_.:-]{1,40}$")
RE_NUM = re.compile(r"^-?\d+(?:\.\d+)?$")
# Keys that stay strings even when they look numeric (a req called "042", an Issue "1234").
NEVER_NUMERIC = {"req", "runId", "issueNo"}

# AL object kinds, shared by the ex-ante plan table (obj_<kind>_new|ext on AldcEstimate) and the
# ex-post diff (objDone_<kind>_new|ext on AldcRun). A fixed set, so the keys are allowlisted by
# construction; anything else is "other".
OBJ_KINDS = ("table", "tableextension", "page", "pageextension", "codeunit", "report",
             "reportextension", "query", "xmlport", "enum", "enumextension", "interface",
             "permissionset", "apipage", "testcodeunit", "other")
OBJ_ALIASES = {"tableext": "tableextension", "pageext": "pageextension",
               "reportext": "reportextension", "enumext": "enumextension", "api": "apipage",
               "apipages": "apipage", "test": "testcodeunit", "testcodeunits": "testcodeunit",
               "permissions": "permissionset"}
COMPLEXITY_WEIGHT = {"S": 1, "M": 2, "L": 4}


def plugin_version() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        with open(os.path.join(here, "..", "..", ".claude-plugin", "plugin.json"), encoding="utf-8") as fh:
            return str(json.load(fh).get("version", ""))
    except (OSError, ValueError):
        return ""


def _git(args: list[str], cwd: str, timeout: int = 20) -> str | None:
    """stdout of a git command, or None when it fails (bad ref, not a repo, no git)."""
    try:
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


def norm_kind(s: str) -> str:
    """'Table extension' / 'API page' / 'tables' -> an OBJ_KINDS member, '' if not a kind."""
    k = re.sub(r"[\s_-]+", "", (s or "").strip().strip("`*").lower())
    if not k or not k.isalpha():
        return ""
    k = OBJ_ALIASES.get(k, k)
    if k not in OBJ_KINDS and k.endswith("s") and k[:-1] in OBJ_KINDS:
        k = k[:-1]
    return k if k in OBJ_KINDS else "other"


RE_AL_KEYWORD = re.compile(r"^([A-Za-z]+)\b")
RE_API_PAGE = re.compile(r"^\s*PageType\s*=\s*API\s*;", re.I | re.M)
RE_TEST_CU = re.compile(r"^\s*Subtype\s*=\s*Test\s*;", re.I | re.M)


def al_object_kind(text: str) -> str:
    """The object kind of one .al file: the keyword on its first line that is not a comment,
    a pragma/region, an attribute, a namespace or a using. Read locally; only the kind leaves."""
    text = text.lstrip("﻿")
    kw, in_block = "", False
    for raw in text.splitlines():
        line = raw.strip()
        if in_block:
            if "*/" not in line:
                continue
            in_block, line = False, line.split("*/", 1)[1].strip()
        if line.startswith("/*"):
            if "*/" not in line:
                in_block = True
                continue
            line = line.split("*/", 1)[1].strip()
        low = line.lower()
        if (not line or line.startswith(("//", "#", "[")) or low.startswith(("namespace ", "using "))):
            continue
        m = RE_AL_KEYWORD.match(line)
        kw = m.group(1).lower() if m else ""
        break
    if kw == "page" and RE_API_PAGE.search(text):
        return "apipage"
    if kw == "codeunit" and RE_TEST_CU.search(text):
        return "testcodeunit"
    return kw if kw in OBJ_KINDS else "other"


RE_TEST_DEP = re.compile(r"library assert|test runner|tests?-?test ?libraries|library variable storage",
                         re.I)


def _is_test_project(top: str, rel: str, cache: dict[str, bool]) -> bool:
    """True when the nearest app.json above `rel` is a test app: its name says test, or it
    depends on Microsoft's test libraries."""
    d = os.path.dirname(os.path.join(top, rel))
    top_n = os.path.normcase(os.path.abspath(top))
    seen = []
    while True:
        if d in cache:
            res = cache[d]
            break
        seen.append(d)
        aj = os.path.join(d, "app.json")
        if os.path.isfile(aj):
            try:
                with open(aj, encoding="utf-8-sig") as fh:
                    j = json.load(fh)
                deps = " ".join(str(x.get("name", "")) for x in (j.get("dependencies") or [])
                                if isinstance(x, dict))
                res = bool(re.search(r"test", str(j.get("name", "")), re.I) or RE_TEST_DEP.search(deps))
            except (OSError, ValueError, AttributeError):
                res = False
            break
        parent = os.path.dirname(d)
        if parent == d or os.path.normcase(os.path.abspath(d)) == top_n:
            res = bool(re.search(r"(^|[\\/])[^\\/]*test[^\\/]*([\\/]|$)", rel, re.I))
            break
        d = parent
    for s in seen:
        cache[s] = res
    return res


def _numstat_path(p: str) -> str:
    """The new-side path of a numstat entry: `a => b` and `dir/{a => b}/f` resolve to b."""
    if " => " not in p:
        return p
    m = re.match(r"^(.*)\{(.*) => (.*)\}(.*)$", p)
    if m:
        return re.sub(r"/{2,}", "/", m.group(1) + m.group(3) + m.group(4))
    return p.split(" => ", 1)[1]


def numstat_totals(base: str, cwd: str) -> dict[str, float]:
    """Added/removed line totals vs `base`, split AL vs everything else, AL added split test vs
    prod app, and one count per object kind for .al files added (`_new`) or changed (`_ext`).
    A moved or renamed file is changed, not new (a restructure otherwise reads as all-new
    objects plus thousands of removed lines). Deleted files only count toward alRemoved.
    Totals only — no path is returned."""
    top = (_git(["rev-parse", "--show-toplevel"], cwd) or "").strip() or cwd
    out = _git(["diff", "--numstat", "-M", base], top)
    if out is None:
        return {}
    t = {"alAdded": 0, "alRemoved": 0, "otherAdded": 0, "otherRemoved": 0, "filesChanged": 0,
         "alAddedTest": 0, "alAddedProd": 0}
    t.update({f"objDone_{k}_{s}": 0 for k in OBJ_KINDS for s in ("new", "ext")})
    cache: dict[str, bool] = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 3 or not parts[0].isdigit() or not parts[1].isdigit():
            continue
        path = _numstat_path(parts[2])
        kind = "al" if path.lower().endswith(".al") else "other"
        t[f"{kind}Added"] += int(parts[0])
        t[f"{kind}Removed"] += int(parts[1])
        t["filesChanged"] += 1
        if kind == "al":
            t["alAddedTest" if _is_test_project(top, path, cache) else "alAddedProd"] += int(parts[0])
    for line in (_git(["diff", "--name-status", "-M", base], top) or "").splitlines():
        parts = line.split("\t")
        st = parts[0][:1]
        if len(parts) < 2 or st not in ("A", "M", "R", "C"):
            continue
        path = parts[-1]  # R/C lines carry old and new path; the new one is last
        if not path.lower().endswith(".al"):
            continue
        try:
            with open(os.path.join(top, path), encoding="utf-8", errors="replace") as fh:
                k = al_object_kind(fh.read(65536))
        except OSError:
            continue
        t[f"objDone_{k}_{'new' if st in ('A', 'C') else 'ext'}"] += 1
    return {k: float(v) for k, v in t.items()}


# --- ex-ante scope: the plan file -----------------------------------------------------------

def _md_tables(lines: list[str]) -> list[tuple[list[str], list[list[str]]]]:
    """Every markdown table as (header cells, body rows); the separator row is dropped."""
    tables, i = [], 0
    while i < len(lines):
        if not lines[i].lstrip().startswith("|"):
            i += 1
            continue
        block = []
        while i < len(lines) and lines[i].lstrip().startswith("|"):
            block.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
            i += 1
        body = [r for r in block[1:] if not all(re.fullmatch(r":?-{2,}:?", c or "-") for c in r)]
        tables.append((block[0], body))
    return tables


def _section(text: str, title_re: str) -> str:
    """The body of the first markdown heading matching title_re, up to the next heading of
    the same or a higher level."""
    m = re.search(rf"^(#{{1,4}})\s*(?:\d+\.\s*)?{title_re}[^\n]*\n", text, re.I | re.M)
    if not m:
        return ""
    rest = text[m.end():]
    n = re.search(rf"^#{{1,{len(m.group(1))}}}\s", rest, re.M)
    return rest[:n.start()] if n else rest


def _open_questions(plan_text: str, plan_path: str) -> int:
    """Unresolved open questions: the spec beside the plan (rows of its Open Questions table
    still `Open`) when there is one, else the plan's own list (items with no answer yet)."""
    d = os.path.dirname(os.path.abspath(plan_path))
    try:
        specs = sorted(f for f in os.listdir(d) if f.lower().endswith(".spec.md"))
    except OSError:
        specs = []
    for f in specs:
        try:
            with open(os.path.join(d, f), encoding="utf-8", errors="replace") as fh:
                sec = _section(fh.read(400_000), r"open questions")
        except OSError:
            continue
        n = 0
        for header, rows in _md_tables(sec.splitlines()):
            hl = [h.lower() for h in header]
            if "status" not in hl:
                continue
            si = hl.index("status")
            n += sum(1 for r in rows if len(r) > si and r[si].lower() in ("open", "aperta", "aperto")
                     and not any(c.startswith("{") for c in r))
        return n
    sec = _section(plan_text, r"open questions")
    n = 0
    for line in sec.splitlines():
        m = re.match(r"^\s*\d+\.\s*(.+)$", line)
        if not m or m.group(1).startswith("{"):
            continue
        ans = m.group(1).split("→", 1)[1].strip() if "→" in m.group(1) else ""
        if not ans or ans.startswith("{"):
            n += 1
    return n


RE_BASE = re.compile(r"\*\*Base:\*\*\s*`?\s*([0-9a-fA-F]{7,40})\b")


def plan_base(req: str, cwd: str) -> str:
    """The `**Base:**` commit of this requirement's plan, for an AldcRun the caller sent without
    --numstat-base. Looks where the conductor writes it and where the closing step archives it."""
    if not req or not RE_TOKEN.match(req) or ".." in req:
        return ""
    import glob

    top = (_git(["rev-parse", "--show-toplevel"], cwd) or "").strip() or cwd
    for root in dict.fromkeys((cwd, top)):
        for pat in ("requirements/*", "*/requirements/*", ".github/plans"):
            for path in sorted(glob.glob(os.path.join(root, pat, req, f"{req}.plan.md"))):
                try:
                    with open(path, encoding="utf-8", errors="replace") as fh:
                        m = RE_BASE.search(fh.read(400_000))
                except OSError:
                    continue
                if m:
                    return m.group(1)
    return ""


RE_INTEGRATION = re.compile(r"\b(integration|integrazione|httpclient|http|web ?services?|soap|odata|"
                            r"rest api|webhook)\b", re.I)


def parse_plan(path: str, cwd: str) -> tuple[dict[str, float], dict[str, str]]:
    """Fixed, allowlisted counts from a conductor plan: the Planned objects table, the WP table
    and the header. Never raises; parseOk=0 when the plan or one of its tables is missing."""
    meas: dict[str, float] = {f"obj_{k}_{s}": 0.0 for k in OBJ_KINDS for s in ("new", "ext")}
    meas.update({"objTotal": 0.0, "objWeighted": 0.0, "testCodeunitsPlanned": 0.0,
                 "wpsPlanned": 0.0, "wavesPlanned": 0.0, "openQuestions": 0.0,
                 "hasIntegration": 0.0, "hasEvents": 0.0, "hasApi": 0.0, "parseOk": 0.0})
    props: dict[str, str] = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read(400_000)
    except (OSError, TypeError):
        return meas, props
    m = re.search(r"\*\*Tier:\*\*\s*\{?\s*(LOW|MEDIUM|HIGH)\b", text, re.I)
    if m:
        props["tier"] = m.group(1).upper()
    m = RE_BASE.search(text)
    base = m.group(1) if m else ""

    ok_obj = ok_wp = False
    domains, wp_tests, waves = "", 0, set()
    for header, rows in _md_tables(text.splitlines()):
        hl = [h.lower() for h in header]
        if any("object type" in h for h in hl) and "count" in hl:
            ti = next(i for i, h in enumerate(hl) if "object type" in h)
            ci = hl.index("count")
            ni = next((i for i, h in enumerate(hl) if "new" in h), -1)
            xi = next((i for i, h in enumerate(hl) if "complex" in h), -1)
            for r in rows:
                if len(r) <= max(ti, ci) or not re.fullmatch(r"\d{1,4}", r[ci]):
                    continue
                kind = norm_kind(r[ti])
                if not kind:
                    continue
                ne = "ext" if 0 <= ni < len(r) and r[ni].lower().startswith("ext") else "new"
                cnt = int(r[ci])
                cx = r[xi].strip().upper()[:1] if 0 <= xi < len(r) else ""
                meas[f"obj_{kind}_{ne}"] += cnt
                meas["objTotal"] += cnt
                meas["objWeighted"] += cnt * COMPLEXITY_WEIGHT.get(cx, 2)
            ok_obj = True
        elif hl and hl[0] == "wp":
            wi = hl.index("wave") if "wave" in hl else -1
            di = hl.index("domains") if "domains" in hl else -1
            tci = next((i for i, h in enumerate(hl) if h.startswith("test codeunit")), -1)
            for r in rows:
                if not re.match(r"^WP-?\d+", r[0], re.I):
                    continue
                meas["wpsPlanned"] += 1
                if 0 <= wi < len(r) and r[wi].isdigit():
                    waves.add(int(r[wi]))
                if 0 <= di < len(r):
                    domains += " " + r[di].lower()
                if 0 <= tci < len(r):
                    wp_tests += len(re.findall(r"\b\d{4,}\b", r[tci]))
            ok_wp = True
    meas["wavesPlanned"] = float(len(waves))
    planned_tests = meas["obj_testcodeunit_new"] + meas["obj_testcodeunit_ext"]
    meas["testCodeunitsPlanned"] = planned_tests if planned_tests else float(wp_tests)
    meas["hasEvents"] = 1.0 if re.search(r"\bevents?\b", domains) else 0.0
    meas["hasApi"] = 1.0 if re.search(r"\bapi\b", domains) or meas["obj_apipage_new"] + meas["obj_apipage_ext"] else 0.0
    intro = text.split("\n## ", 1)[0]  # title + the 1–2 sentence summary
    meas["hasIntegration"] = 1.0 if RE_INTEGRATION.search(domains + " " + intro) else 0.0
    meas["openQuestions"] = float(_open_questions(text, path))
    tree = _git(["ls-tree", "-r", "--name-only", base or "HEAD"], cwd)
    if tree is not None:
        meas["appObjectCount"] = float(sum(1 for f in tree.splitlines() if f.lower().endswith(".al")))
    meas["parseOk"] = 1.0 if ok_obj and ok_wp else 0.0
    return meas, props


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
        elif k in STRING_KEYS and RE_TOKEN.match(v) and v in ENUM_VALUES.get(k, {v}):
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


def idle_cap() -> float:
    try:
        v = float(os.environ.get("ALDC_METRICS_IDLE_CAP_S", "") or IDLE_CAP_S)
    except ValueError:
        return IDLE_CAP_S
    return v if v > 0 else IDLE_CAP_S


def open_cap() -> float:
    try:
        v = float(os.environ.get("ALDC_METRICS_OPEN_CAP_S", "") or OPEN_CAP_S)
    except ValueError:
        return OPEN_CAP_S
    return v if v > 0 else OPEN_CAP_S


def _step_open(snap: dict) -> bool:
    """A wave or a WP is in flight: the conductor is waiting on work (a compile, the test lane,
    a subagent's long tool call), not idle, even when no event arrives for a while."""
    return snap.get("waveStage") == "running" or any(
        isinstance(w, dict) and w.get("state") == "running" for w in (snap.get("wps") or {}).values())


def _tick(snap: dict, event: str, now: float) -> None:
    """Advance the run's clocks: the gap since the previous run event is active time, unless an
    AldcGate opened it — then it is human wait. Between steps the gap is capped at
    IDLE_CAP_S, so an idle session does not count; inside an open wave or WP it counts in full
    up to OPEN_CAP_S (a sanity bound for a session abandoned mid-wave)."""
    last = snap.get("lastEventAt")
    if last is not None:
        gap = max(0.0, now - float(last))
        if snap.get("gateAt") is not None:
            snap["humanWaitS"] = round(float(snap.get("humanWaitS") or 0) + gap, 1)
            snap.pop("gateAt", None)
        else:
            cap = open_cap() if _step_open(snap) else idle_cap()
            snap["activeS"] = round(float(snap.get("activeS") or 0) + min(gap, cap), 1)
    snap["lastEventAt"] = now
    if event == "AldcGate":
        snap["gateAt"] = now


def apply_live(event: str, props: dict, meas: dict, snap: dict, cwd: str, session: str,
               now: float | None = None) -> dict:
    """Fold one event into the session snapshot and enrich the event from it (req/runId,
    durations, measured wallMinutes, activeSeconds). Mutates props/meas; returns the new
    snapshot."""
    now = _now() if now is None else now
    fresh = False
    if event == "AldcRunStart":
        req = props.get("req") or snap.get("req") or "run"
        rid = props.get("runId") or run_id(props, req)
        resumed = snap.get("runId") == rid and not snap.get("outcome")
        if not resumed:
            snap, fresh = {"wps": {}, "waveLog": []}, True
        snap.update({"req": req, "runId": rid,
                     "startedAt": now if snap.get("startedAt") is None else snap["startedAt"],
                     "tier": props.get("tier") or snap.get("tier"),
                     "wavesPlanned": int(meas.get("waves") or snap.get("wavesPlanned") or 0),
                     "wpsPlanned": int(meas.get("wpsPlanned") or snap.get("wpsPlanned") or 0)})
        snap.pop("outcome", None)
        snap.pop("endedAt", None)
    elif event in ("AldcRun", "AldcEstimate") and props.get("req") and props["req"] != snap.get("req"):
        # A session that never saw this run's AldcRunStart: still key the event to its run.
        # No startedAt, so no wallMinutes — but the run's attempts and dedupe still apply.
        snap = {"wps": {}, "waveLog": [], "req": props["req"],
                "runId": props.get("runId") or run_id(props, props["req"])}
    if snap.get("runId"):
        props.setdefault("req", snap.get("req", ""))
        props.setdefault("runId", snap["runId"])

    if fresh:
        snap.update({"activeS": 0.0, "humanWaitS": 0.0, "lastEventAt": now})
    elif snap.get("runId") and not snap.get("outcome") and event in TICK_EVENTS:
        _tick(snap, event, now)
    if event == "AldcAlive":
        # The heartbeat carries the run's position to the team view and keeps its clock
        # running; it changes nothing else (its cwd may be a worktree, not the project).
        for k in ("wave", "wavesPlanned"):
            if snap.get(k):
                meas[k] = float(snap[k])
        snap["updatedAt"] = now
        return snap

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
        # Durations are measured, never reported: a value the conductor passes is a guess
        # (round numbers that disagreed with the measured span by 2x), kept for comparison.
        reported = meas.pop("wallMinutes", None)
        if reported:
            meas["reportedMinutes"] = reported
        if snap.get("startedAt") is not None:
            meas["wallMinutes"] = round((now - float(snap["startedAt"])) / 60, 1)
        meas["activeSeconds"] = float(round(float(snap.get("activeS") or 0)))
        meas["humanWaitSeconds"] = float(round(float(snap.get("humanWaitS") or 0)))
        # Σ wave durations of this attempt: activeSeconds below it means the clock missed work.
        meas["waveSeconds"] = float(round(sum(float(w.get("durationS") or 0)
                                              for w in snap.get("waveLog") or [])))
        snap.update({"outcome": props.get("outcome") or "done", "endedAt": now})

    snap.update({"schema": 1, "session": session, "cwd": cwd, "project": props.get("project"),
                 "projectHash": props.get("projectHash"), "user": props.get("user"),
                 "where": props.get("where"), "updatedAt": now})
    return snap


# --- attempt registry ------------------------------------------------------------------------
# runs.json: runId -> {attempts, firstStartedAt, activeSecondsTotal, lastOutcome, estimatedAt,
# att: {"<n>": {activeS, waitS, outcome}}}. Beside the live directory, not under
# CLAUDE_PLUGIN_DATA: the conductor's Bash calls do not get that variable, the hooks do, and
# both must read the same file.

REGISTRY_KEEP_S = 180 * 86400


def runs_path() -> str:
    return os.environ.get("ALDC_RUNS_FILE") or os.path.join(os.path.dirname(live_dir()), "runs.json")


def load_runs() -> dict:
    try:
        with open(runs_path(), encoding="utf-8") as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_runs(reg: dict, now: float | None = None) -> None:
    now = _now() if now is None else now
    keep = {k: v for k, v in reg.items()
            if isinstance(v, dict) and now - float(v.get("updatedAt") or now) < REGISTRY_KEEP_S}
    p = runs_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = f"{p}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(keep, fh, indent=1, sort_keys=True)
    os.replace(tmp, p)


def resolve_rework(event: str, props: dict, snap: dict, reg: dict, now: float | None = None) -> None:
    """A req whose run already finished `done` and is started again (a follow-up fix weeks
    later) is a REWORK, not another attempt: it gets its own runId (hash of `<req>#r<n>`) and
    `rework=<n>`, so its time never inflates the original task against the original estimate.
    A rework that is still open is resumed like any run. Sets props["runId"]; no-op otherwise."""
    now = _now() if now is None else now
    req = props.get("req")
    if event not in ("AldcRunStart", "AldcRun", "AldcEstimate") or not req or props.get("runId"):
        return
    if snap.get("req") == req and snap.get("runId") and (event != "AldcRunStart" or not snap.get("outcome")):
        return  # this session's own run (or a report for it): the snapshot already keys it
    base = run_id(props, req)
    e = reg.get(base) or {}
    if e.get("lastOutcome") != "done":
        return  # open or stopped: a resume, i.e. the next attempt of the same run
    cur = e.get("reworkRunId")
    if cur and (reg.get(cur) or {}).get("lastOutcome") != "done":
        props["runId"] = cur
    elif event == "AldcRunStart":
        n = int(e.get("reworks") or 0) + 1
        cur = run_id(props, f"{req}#r{n}")
        e.update({"reworks": n, "reworkRunId": cur, "updatedAt": now})
        reg[cur] = {"attempts": 0, "att": {}, "rework": n, "reworkOf": base, "updatedAt": now}
        props["runId"] = cur
    # else: a late AldcRun/AldcEstimate for the finished run itself — the dedupe decides


def apply_attempts(event: str, props: dict, meas: dict, snap: dict, reg: dict,
                   now: float | None = None) -> bool:
    """Fold one run event into the attempt registry: number the attempt, carry `attempt` on the
    event, keep this attempt's active time so a later session can sum it. Returns False when
    the event is a duplicate to drop: an AldcRun for an attempt that already has an outcome, or
    a second AldcEstimate for the run."""
    now = _now() if now is None else now
    rid = snap.get("runId")
    if not rid or props.get("runId") != rid:
        return True
    e = reg.setdefault(rid, {"attempts": 0, "att": {}})
    e.setdefault("att", {})
    e.setdefault("firstStartedAt", now if snap.get("startedAt") is None else snap["startedAt"])
    if "attempt" not in snap:
        latest = e["att"].get(str(e.get("attempts", 0))) or {}
        # A new session's AldcRunStart is a new attempt (the plan's resume path). A session
        # that reports without one continues the latest attempt, unless that one is closed.
        if event == "AldcRunStart" or not e.get("attempts") or latest.get("outcome"):
            e["attempts"] = int(e.get("attempts") or 0) + 1
        snap["attempt"] = int(e["attempts"])
    a = str(snap["attempt"])
    meas["attempt"] = float(snap["attempt"])
    if e.get("rework"):
        meas["rework"] = float(e["rework"])
    cur = e["att"].setdefault(a, {})
    cur["activeS"] = float(snap.get("activeS") or 0)
    cur["waitS"] = float(snap.get("humanWaitS") or 0)
    e["activeSecondsTotal"] = float(round(sum(float(x.get("activeS") or 0) for x in e["att"].values())))
    e["updatedAt"] = now
    if event == "AldcEstimate":
        if e.get("estimatedAt"):
            return False
        e["estimatedAt"] = now
    elif event == "AldcRun":
        if cur.get("outcome"):
            return False
        cur["outcome"] = e["lastOutcome"] = props.get("outcome") or "done"
        meas["attempts"] = float(e["attempts"])
        meas["activeSecondsTotal"] = e["activeSecondsTotal"]
        meas["wallMinutesTotal"] = round((now - float(e["firstStartedAt"])) / 60, 1)
    return True


class _Lock:
    """Best-effort cross-process lock around the snapshot + registry read-modify-write: the
    alive hook now writes the snapshot too, in the background, alongside the conductor. Waits at
    most ~2 s, breaks a lock older than 15 s, and on any failure proceeds unlocked — a lost
    increment is acceptable, a blocked session is not."""

    def __init__(self, path: str):
        self.path, self.held = path, False

    def __enter__(self):
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
        except OSError:
            return self
        for _ in range(40):
            try:
                os.close(os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
                self.held = True
                return self
            except FileExistsError:
                try:
                    if time.time() - os.path.getmtime(self.path) > 15:
                        os.remove(self.path)
                        continue
                except OSError:
                    pass
                time.sleep(0.05)
            except OSError:
                return self
        return self

    def __exit__(self, *_):
        if self.held:
            try:
                os.remove(self.path)
            except OSError:
                pass
        return False


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
    plan = ""
    if "--plan" in rest:
        i = rest.index("--plan")
        plan = rest[i + 1] if i + 1 < len(rest) else ""
        rest = rest[:i] + rest[i + 2:]
    cwd = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    data = os.environ.get("CLAUDE_PLUGIN_DATA") or os.path.join(
        os.path.expanduser("~"), ".claude", "aldc-plugin-data")
    out = os.path.join(data, "metrics", "aldc-metrics.jsonl")
    try:
        built = build(event, rest, cwd, session)
        if not built:
            return 0
        props, meas = built
        if event == "AldcRun" and not base:
            # The model drops the flag now and then; the plan always carries the commit.
            base = plan_base(props.get("req", ""), cwd)
        if base and RE_TOKEN.match(base):
            meas.update(numstat_totals(base, cwd))
        if event == "AldcEstimate":
            pm, pp = parse_plan(plan, cwd)
            meas.update(pm)
            for k, v in pp.items():
                props.setdefault(k, v)
            props.setdefault("estSource", "none")
        import ident

        full_session = ident.session_id(session)
        keep = True
        if full_session and event in TICK_EVENTS:
            with _Lock(os.path.join(live_dir(), ".lock")):
                snap = load_live(full_session)
                live = bool(snap.get("runId")) and not snap.get("outcome")
                # Alive and a gate only matter inside a live run; a lane run outside a
                # conductor run (al-developer) has no run to join.
                if (event not in ("AldcAlive", "AldcGate") or live) and (event != "AldcLane" or snap.get("runId")):
                    reg = load_runs()
                    resolve_rework(event, props, snap, reg)
                    snap = apply_live(event, props, meas, snap, cwd, full_session)
                    keep = apply_attempts(event, props, meas, snap, reg)
                    if keep:
                        save_runs(reg)
                        save_live(full_session, snap)
        if not keep:
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(os.path.join(os.path.dirname(out), "capture.log"), "a", encoding="utf-8") as fh:
                fh.write(f"{datetime.now(timezone.utc):%Y-%m-%dT%H:%M:%SZ} emit: dropped duplicate "
                         f"{event} runId={props.get('runId')} attempt={int(meas.get('attempt', 0))}\n")
            return 0
        props["schema"] = str(SCHEMA)
        rec = {"schema": SCHEMA, "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "event": event, "props": props, "measurements": meas}
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
    fd = build("AldcHook", ["hook=freshdesk-guard", "decision=ask", "tool=createTicketNote",
                            "calls=2", "ticket=48213", "body=Dear customer", "tool_input={}"], cwd)
    fd_bad = build("AldcHook", ["hook=freshdesk-guard", "decision=deny",
                                "tool=Ticket 48213: the invoice is wrong"], cwd)
    checks += [
        ("freshdesk hook: tool token + call count kept",
         fd and fd[0].get("tool") == "createTicketNote" and fd[0].get("decision") == "ask"
         and fd[1].get("calls") == 2.0),
        ("freshdesk hook: ticket id / text / tool_input never kept",
         fd and not ({"ticket", "body", "tool_input"} & (set(fd[0]) | set(fd[1])))
         and "48213" not in json.dumps(fd)),
        ("freshdesk hook: free-text tool value rejected", fd_bad and "tool" not in fd_bad[0]),
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
        ("activeSeconds sums the run's event gaps", rm.get("activeSeconds") == 1200.0),
    ]
    checks += _self_test_duration(cwd) + _self_test_attempts(cwd) + _self_test_estimate(cwd)
    checks += _self_test_numstat() + _self_test_privacy(cwd)
    ok = True
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


def _run(events: list[tuple[str, list[str], float]], cwd: str, session: str, snap: dict,
         reg: dict) -> tuple[dict, list[tuple[dict, dict, bool]]]:
    """Feed events through build -> apply_live -> apply_attempts, as main() does."""
    out = []
    for event, pairs, t in events:
        p, m = build(event, pairs, cwd, session)
        resolve_rework(event, p, snap, reg, now=t)
        snap = apply_live(event, p, m, snap, cwd, session, now=t)
        out.append((p, m, apply_attempts(event, p, m, snap, reg, now=t)))
    return snap, out


def _self_test_duration(cwd: str) -> list[tuple[str, bool]]:
    s = "sess-0002-self-test"
    snap, ev = _run([("AldcRunStart", ["req=D-01"], 0), ("AldcWave", ["stage=start", "wave=1"], 100),
                     ("AldcAlive", ["agent=al-implement-subagent"], 220),
                     # a 30-min compile / lane run inside the open wave: all of it is work
                     ("AldcWp", ["stage=end", "wave=1", "wp=1"], 2020),
                     ("AldcWave", ["stage=end", "wave=1"], 2100),
                     # an evening away between waves: 4900 s of nothing, IDLE_CAP_S at most
                     ("AldcWave", ["stage=start", "wave=2"], 7000),
                     ("AldcGate", ["gate=fixloop"], 7060),
                     # the human answers 3000 s later: wait, not work
                     ("AldcWp", ["stage=start", "wave=2", "wp=2", "fixRound=1"], 10060),
                     ("AldcWp", ["stage=end", "wave=2", "wp=2"], 10300),
                     ("AldcWave", ["stage=end", "wave=2"], 10340),
                     ("AldcRun", ["wallMinutes=240", "outcome=done"], 10400)], cwd, s, {}, {})
    rm = ev[-1][1]
    # A session abandoned mid-wave: the open-step gap is still bounded by OPEN_CAP_S.
    _, ab = _run([("AldcRunStart", ["req=D-03"], 0), ("AldcWave", ["stage=start", "wave=1"], 10),
                  ("AldcRun", ["outcome=stopped"], 10 + 86400)], cwd, s, {}, {})
    return [
        ("duration measured although the conductor sent one", rm.get("wallMinutes") == round(10400 / 60, 1)),
        ("the conductor's value is kept as reportedMinutes", rm.get("reportedMinutes") == 240.0),
        ("a gap inside an open wave counts in full", ev[3][1].get("attempt") == 1.0 and rm.get("activeSeconds")
         == 100 + 120 + 1800 + 80 + 600 + 60 + 240 + 40 + 60),
        ("the gap after a gate is human wait", rm.get("humanWaitSeconds") == 3000.0),
        ("waveSeconds sums the wave durations", rm.get("waveSeconds") == 2000 + 3340),
        ("an abandoned open wave is capped at OPEN_CAP_S", ab[-1][1].get("activeSeconds") == 10 + OPEN_CAP_S),
        ("alive advances the clock", ev[2][2] and ev[2][1].get("attempt") == 1.0),
        ("no wallMinutes without a start", "wallMinutes" not in _run(
            [("AldcRun", ["req=D-02", "wallMinutes=60"], 10)], cwd, s, {}, {})[1][0][1]),
    ]


def _self_test_attempts(cwd: str) -> list[tuple[str, bool]]:
    reg: dict = {}
    a, b = "sess-0003-attempt-a", "sess-0004-attempt-b"
    # Session A: starts the run, works 900 s, dies without an AldcRun.
    sa, eva = _run([("AldcRunStart", ["req=R-01", "tier=LOW"], 0), ("AldcWave", ["stage=start", "wave=1"], 300),
                    ("AldcWp", ["stage=end", "wave=1", "wp=1"], 900)], cwd, a, {}, reg)
    # Session B, next day: the same req resumes; works 400 s and finishes.
    sb, evb = _run([("AldcRunStart", ["req=R-01", "tier=LOW"], 90000), ("AldcWave", ["stage=start", "wave=2"], 90200),
                    ("AldcRun", ["outcome=done"], 90400)], cwd, b, {}, reg)
    rid = sa.get("runId")
    run_p, run_m, kept = evb[-1]
    # The same AldcRun again (the 28 Sep duplicate): dropped.
    _, dup = _run([("AldcRun", ["outcome=done"], 90500)], cwd, b, dict(sb), reg)
    # A resume inside the same session is the same attempt.
    _, same = _run([("AldcRunStart", ["req=R-02"], 0), ("AldcRunStart", ["req=R-02"], 50)], cwd, a, {}, reg)
    return [
        ("same runId across sessions", rid and sb.get("runId") == rid),
        ("attempt 1 then 2", eva[0][1].get("attempt") == 1.0 and evb[0][1].get("attempt") == 2.0),
        ("attempt on every run event", all(m.get("attempt") == 2.0 for _, m, _ in evb)),
        ("AldcRun carries attempts and the summed active time",
         kept and run_m.get("attempts") == 2.0 and run_m.get("activeSecondsTotal") == 1300.0
         and run_m.get("activeSeconds") == 400.0),
        ("wallMinutesTotal spans the attempts", run_m.get("wallMinutesTotal") == round(90400 / 60, 1)),
        ("registry records the outcome", reg[rid]["lastOutcome"] == "done" and reg[rid]["attempts"] == 2),
        ("duplicate AldcRun dropped", dup[0][2] is False),
        ("resume in the same session keeps the attempt", [m.get("attempt") for _, m, _ in same] == [1.0, 1.0]),
    ] + _self_test_rework(cwd, reg, rid)


def _self_test_rework(cwd: str, reg: dict, base: str) -> list[tuple[str, bool]]:
    """R-01 finished `done` above. Weeks later the same req is started again: a rework."""
    c, d, f = "sess-0006-rework-c", "sess-0007-rework-d", "sess-0008-rework-f"
    sc, evc = _run([("AldcRunStart", ["req=R-01"], 2_000_000), ("AldcEstimate", [], 2_000_010),
                    ("AldcWave", ["stage=start", "wave=1"], 2_000_100)], cwd, c, {}, reg)
    rw = sc.get("runId")
    # resumed in another session, then finished
    sd, evd = _run([("AldcRunStart", ["req=R-01"], 2_100_000),
                    ("AldcRun", ["req=R-01", "outcome=done"], 2_100_300)], cwd, d, {}, reg)
    # and started once more after that: a second rework
    sf, _ = _run([("AldcRunStart", ["req=R-01"], 3_000_000)], cwd, f, {}, reg)
    run_m = evd[-1][1]
    return [
        ("a finished req started again gets its own runId", rw and rw != base and evc[0][0].get("runId") == rw),
        ("rework flagged on its events", all(m.get("rework") == 1.0 for _, m, _ in evc)),
        ("rework has its own estimate", evc[1][2] is True),
        ("rework starts at attempt 1", evc[0][1].get("attempt") == 1.0),
        ("an open rework resumes as its next attempt", sd.get("runId") == rw and run_m.get("attempt") == 2.0),
        ("rework time never touches the original task",
         reg[base]["activeSecondsTotal"] == 1300.0 and run_m.get("activeSecondsTotal") == 100.0 + 300.0),
        ("a rework after a finished rework is the next one",
         sf.get("runId") not in (base, rw) and reg[sf["runId"]].get("rework") == 2),
        ("the original run keeps no rework flag", "rework" not in reg[base]),
    ]


def _self_test_estimate(cwd: str) -> list[tuple[str, bool]]:
    import shutil
    import tempfile

    here = os.path.dirname(os.path.abspath(__file__))
    plan = os.path.join(here, "fixtures", "sample.plan.md")
    m, p = parse_plan(plan, cwd)
    d = tempfile.mkdtemp()
    try:
        shutil.copy(plan, d)  # no spec beside it: the plan's own open questions count
        m2, _ = parse_plan(os.path.join(d, "sample.plan.md"), cwd)
    finally:
        shutil.rmtree(d, ignore_errors=True)
    bad, _ = parse_plan(os.path.join(here, "fixtures", "no-such.plan.md"), cwd)
    reg: dict = {}
    s = "sess-0005-estimate"
    _, ev = _run([("AldcRunStart", ["req=E-01"], 0),
                  ("AldcEstimate", ["estP50Min=90", "estP80Min=150", "estSource=stima-sviluppo",
                                    "issueNo=1234", "model=claude-sonnet-5-5"], 10),
                  ("AldcEstimate", [], 20)], cwd, s, {}, reg)
    ep, em, ekept = ev[1]
    return [
        ("plan parsed", m["parseOk"] == 1.0 and p.get("tier") == "MEDIUM"),
        ("objects by kind", m["obj_table_new"] == 1 and m["obj_tableextension_new"] == 1
         and m["obj_codeunit_new"] == 1 and m["obj_codeunit_ext"] == 1 and m["obj_apipage_new"] == 1
         and m["obj_other_new"] == 1),
        ("objTotal / objWeighted", m["objTotal"] == 10 and m["objWeighted"] == 2 + 1 + 1 + 4 + 2 + 2 + 6 + 1),
        ("WPs, waves and planned tests", m["wpsPlanned"] == 3 and m["wavesPlanned"] == 2
         and m["testCodeunitsPlanned"] == 3),
        ("open questions from the spec", m["openQuestions"] == 2),
        ("open questions from the plan without a spec", m2["openQuestions"] == 1),
        ("flags", m["hasEvents"] == 1 and m["hasApi"] == 1 and m["hasIntegration"] == 1),
        ("unreadable plan -> parseOk 0, not an error", bad["parseOk"] == 0.0 and bad["objTotal"] == 0),
        ("estimate passes through the external estimate", em.get("estP80Min") == 150.0
         and ep.get("estSource") == "stima-sviluppo" and ep.get("issueNo") == "1234"),
        ("estimate keyed to the run", ekept and ep.get("runId") and em.get("attempt") == 1.0),
        ("second estimate for the run dropped", ev[2][2] is False),
    ]


def _self_test_numstat() -> list[tuple[str, bool]]:
    import shutil
    import tempfile

    d = tempfile.mkdtemp()
    g = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]

    def w(rel: str, text: str) -> None:
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)

    try:
        if _git(["init", "-q"], d) is None:
            return [("object-kind classification (git unavailable, skipped)", True)]
        w("app/app.json", json.dumps({"name": "Credit"}))
        w("test/app.json", json.dumps({"name": "Credit QA", "dependencies": [{"name": "Library Assert"}]}))
        w("app/src/Old.Table.al", 'table 50100 "Old"\n{\n}\n')
        w("app/src/Gone.Codeunit.al", 'codeunit 50199 "Gone"\n{\n}\n')
        moved = 'enum 50150 "Moved"\n{\n    value(0; A) { }\n    value(1; B) { }\n    value(2; C) { }\n'
        w("app/src/Moved.Enum.al", moved + "}\n")
        _git([*g, "add", "-A"], d)
        _git([*g, "commit", "-q", "-m", "base"], d)
        base = (_git(["rev-parse", "HEAD"], d) or "").strip()
        w("app/src/Old.Table.al", 'table 50100 "Old"\n{\n    // field added\n}\n')
        os.remove(os.path.join(d, "app/src/Gone.Codeunit.al"))
        os.remove(os.path.join(d, "app/src/Moved.Enum.al"))
        w("app/src/Enums/Moved.Enum.al", moved + "    value(3; D) { }\n}\n")
        w("app/src/Ext.TableExt.al", '// header\n/* block\n   comment */\nnamespace Dsc.Credit;\n\n'
          'tableextension 50101 "Cust" extends Customer\n{\n}\n')
        w("app/src/Api.Page.al", 'page 50120 "Credit API"\n{\n    PageType = API;\n}\n')
        w("test/src/T.Codeunit.al", 'codeunit 50200 "T"\n{\n    Subtype = Test;\n}\n')
        w("app/src/Readme.md", "x\n")
        _git([*g, "add", "-A"], d)
        _git([*g, "commit", "-q", "-m", "run"], d)
        t = numstat_totals(base, d)
        w("app/requirements/archived/req-x/req-x.plan.md", f"# Plan\n\n**Base:** `{base[:12]}`\n")
        found = plan_base("req-x", d)
        traversal = plan_base("../req-x", d)
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return [
        ("new kinds classified", t.get("objDone_tableextension_new") == 1 and t.get("objDone_apipage_new") == 1
         and t.get("objDone_testcodeunit_new") == 1),
        ("changed object is _ext", t.get("objDone_table_ext") == 1 and t.get("objDone_table_new") == 0),
        ("deleted file only in alRemoved", t.get("objDone_codeunit_new") == 0 and t.get("objDone_codeunit_ext") == 0
         and t.get("alRemoved") == 3),
        ("AL added split test vs prod", t.get("alAddedTest") == 4 and t.get("alAddedProd") == 1 + 8 + 4 + 1),
        ("existing totals unchanged", t.get("otherAdded") == 1 and t.get("filesChanged") == 7),
        ("moved file is _ext, not _new", t.get("objDone_enum_ext") == 1 and t.get("objDone_enum_new") == 0),
        ("run base read from the archived plan", found == base[:12]),
        ("plan lookup refuses a path-shaped req", traversal == ""),
        ("no path in the totals", not any("/" in k or ".al" in k.lower() for k in t)),
    ]


def _self_test_privacy(cwd: str) -> list[tuple[str, bool]]:
    """Every string key added in schema 3, fed a path-like or free-text value: dropped."""
    bad = ["C:/Users/mario/Customer/secret.al", "..\\secret", "/home/x/y", "a b c"]
    out = []
    for event, key in (("AldcEstimate", "estSource"), ("AldcEstimate", "issueNo"),
                       ("AldcEstimate", "model"), ("AldcEstimate", "tier"), ("AldcGate", "gate")):
        leaked = [v for v in bad if key in build(event, [f"{key}={v}"], cwd)[0]]
        out.append((f"path-like {key} dropped", not leaked))
    out += [
        ("estSource outside its enum dropped", "estSource" not in build("AldcEstimate", ["estSource=guess"], cwd)[0]),
        ("caller cannot pass parsed plan counts", "obj_table_new" not in build("AldcEstimate", ["obj_table_new=9"], cwd)[1]),
        ("caller cannot pass active time", "activeSeconds" not in build("AldcRun", ["activeSeconds=9"], cwd)[1]),
        ("issueNo stays a string", build("AldcEstimate", ["issueNo=0042"], cwd)[0].get("issueNo") == "0042"),
    ]
    return out


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
