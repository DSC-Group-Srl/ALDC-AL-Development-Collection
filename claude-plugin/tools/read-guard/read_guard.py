#!/usr/bin/env python3
"""PreToolUse read-guard: steer whole-file reads of large source files to targeted reads.

Modeled on Spotify's "shunt" plugin (bulk reads of big files routed to a cheap model): in an
AL workspace, a `Read` with no offset/limit of a source file longer than ALDC_READ_MIN_LINES
(default 350) is denied with a message pointing at `al-file-reader` (Haiku: returns exact
line ranges) or a ranged Read.

Up to bc-dev 8.x the same full Read repeated once was allowed, on the belief that Claude Code's
Edit tool needs one FULL Read of the file. It does not: Edit (and Write over an existing file)
only needs the file to have been Read at all — a 5-line ranged Read is enough, also for an
edit outside those lines (verified 2026-11). The belief was written into the denial and into
the agent contract, so agents answered every denial by repeating the read: telemetry showed
thousands of whole-file reads and five al-file-reader calls. Now the first TWO full reads of a
file are denied and the denial says what Edit really needs; a third identical attempt within
30 minutes is let through, as the escape for the rare case that truly needs the whole file.

Also catches whole-file `cat`/`type`/`Get-Content` of a large file through Bash/PowerShell.

Never guards: al-file-reader itself, files under the plugin root or any `.claude/` folder,
requirement documents (`requirements/`), markdown, non-AL workspaces, small files.
Kill switch: ALDC_READ_GUARD_DISABLE=1. Every decision that matters is counted as an
AldcRead/AldcHook metric (counts only — never a path).

Fails open: any error means "allow".
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
GUARDED_EXT = {".al", ".xlf", ".xml", ".json", ".cs", ".ts", ".tsx", ".js", ".ps1", ".py",
               ".sql", ".txt", ".log", ".razor", ".yml", ".yaml"}
REPEAT_WINDOW_S = 1800
RE_SHELL_DUMP = re.compile(
    r"^\s*(?:cat|type|Get-Content|gc)\s+(?:-Raw\s+)?([\"']?)([^|;&<>\"'`]+?)\1\s*$", re.I)


def threshold() -> int:
    try:
        return max(50, int(os.environ.get("ALDC_READ_MIN_LINES", "350")))
    except ValueError:
        return 350


def is_al_workspace(cwd: str) -> bool:
    if not cwd:
        return False
    if os.path.isfile(os.path.join(cwd, "app.json")):
        return True
    try:
        for d in os.listdir(cwd):
            if os.path.isfile(os.path.join(cwd, d, "app.json")):
                return True
    except OSError:
        pass
    return False


def exempt(path: str) -> bool:
    p = path.replace("\\", "/").lower()
    root = os.environ.get("CLAUDE_PLUGIN_ROOT", "").replace("\\", "/").lower().rstrip("/")
    if root and p.startswith(root + "/"):
        return True
    if "/.claude/" in p or p.startswith(".claude/") or "/requirements/" in p:
        return True
    ext = os.path.splitext(p)[1]
    return ext not in GUARDED_EXT


def count_lines(path: str, cap: int) -> tuple[int, int]:
    n = size = 0
    with open(path, "rb") as fh:
        while True:
            b = fh.read(1 << 16)
            if not b:
                break
            size += len(b)
            n += b.count(b"\n")
            if n > cap * 50:  # enough to decide; don't scan a 100 MB log
                break
    return n, size


def state_file(session: str) -> str:
    data = os.environ.get("CLAUDE_PLUGIN_DATA") or os.path.join(
        os.path.expanduser("~"), ".claude", "aldc-plugin-data")
    d = os.path.join(data, "read-guard")
    os.makedirs(d, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9_-]", "", session)[:40] or "nosession"
    return os.path.join(d, f"{safe}.json")


DENIALS_BEFORE_ALLOW = 2


def attempt_no(session: str, path: str) -> int:
    """How many full reads of this file the session has now asked for (this one included),
    within the window. State: {key: [first_seen, count]}; an old bare timestamp counts as 1."""
    key = hashlib.sha256(os.path.abspath(path).lower().encode()).hexdigest()[:20]
    f = state_file(session)
    try:
        with open(f, encoding="utf-8") as fh:
            st = json.load(fh)
    except (OSError, ValueError):
        st = {}
    now = time.time()
    clean = {}
    for k, v in (st.items() if isinstance(st, dict) else []):
        first, count = (v[0], v[1]) if isinstance(v, list) and len(v) == 2 else (v, 1)
        if isinstance(first, (int, float)) and now - first < REPEAT_WINDOW_S:
            clean[k] = [first, int(count)]
    first, count = clean.get(key, [now, 0])
    clean[key] = [first, count + 1]
    try:
        with open(f, "w", encoding="utf-8") as fh:
            json.dump(clean, fh)
    except OSError:
        pass
    return count + 1


def metric(event: str, pairs: list[str]) -> None:
    if os.environ.get("ALDC_READ_GUARD_NO_METRICS"):
        return
    try:
        sys.path.insert(0, os.path.join(HERE, "..", "metrics"))
        import emit  # noqa: WPS433

        emit.main([event, *pairs])
    except Exception:
        pass


def decide(payload: dict) -> dict | None:
    """Return a hookSpecificOutput deny object, or None to allow."""
    if os.environ.get("ALDC_READ_GUARD_DISABLE", "").strip().lower() in ("1", "true", "yes", "on"):
        return None
    agent = str(payload.get("agent_type", ""))
    if agent.split(":")[-1] == "al-file-reader":
        return None
    tool = str(payload.get("tool_name", ""))
    inp = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
    cwd = str(payload.get("cwd", "")) or os.getcwd()

    if tool == "Read":
        if "offset" in inp or "limit" in inp or inp.get("pages"):
            return None
        path = str(inp.get("file_path", ""))
    elif tool in ("Bash", "PowerShell"):
        m = RE_SHELL_DUMP.match(str(inp.get("command", "")))
        if not m:
            return None
        path = m.group(2).strip()
        if not os.path.isabs(path):
            path = os.path.join(cwd, path)
    else:
        return None

    if not path or exempt(path) or not is_al_workspace(cwd) or not os.path.isfile(path):
        return None
    limit = threshold()
    lines, size = count_lines(path, limit)
    if lines <= limit:
        return None
    session = str(payload.get("session_id", ""))
    if tool == "Read" and attempt_no(session, path) > DENIALS_BEFORE_ALLOW:
        metric("AldcRead", ["action=allowed-repeat", f"lines={lines}", f"chars={size}"])
        return None
    metric("AldcRead", ["action=blocked", f"lines={lines}", f"chars={size}", f"threshold={limit}"])
    name = os.path.basename(path)
    reason = (
        f"read-guard: {name} has {lines} lines (> {limit}). Don't load it whole. Either "
        f"(1) ask the al-file-reader agent via Task (question + this path) for the exact line "
        f"ranges you need, then Read with offset/limit; or (2) Read with offset/limit directly "
        f"if you already know where to look (Grep for `procedure `/`trigger `/`field(` first). "
f"To EDIT this file you do NOT need a full read: Edit only requires that the file was "
        f"Read at all, and a ranged Read of the lines you will change is enough - read those "
        f"lines with offset/limit, then Edit. Repeating this full Read is denied again; only "
        f"a third identical attempt is let through, for the rare case that needs every line."
    )
    if tool != "Read":
        reason = (f"read-guard: {name} has {lines} lines - don't dump it through the shell. "
                  f"Use Read with offset/limit, Grep, or the al-file-reader agent.")
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        res = decide(payload) if isinstance(payload, dict) else None
    except Exception:
        return 0
    if res:
        print(json.dumps(res))
    return 0


def self_test() -> int:
    import shutil
    import tempfile

    os.environ["ALDC_READ_GUARD_NO_METRICS"] = "1"
    os.environ["CLAUDE_PLUGIN_DATA"] = tempfile.mkdtemp()
    ws = tempfile.mkdtemp()
    os.makedirs(os.path.join(ws, "app", "src"))
    with open(os.path.join(ws, "app", "app.json"), "w") as fh:
        fh.write("{}")
    big = os.path.join(ws, "app", "src", "Big.Codeunit.al")
    small = os.path.join(ws, "app", "src", "Small.Codeunit.al")
    with open(big, "w") as fh:
        fh.write("x\n" * 1000)
    with open(small, "w") as fh:
        fh.write("x\n" * 10)
    other = tempfile.mkdtemp()
    with open(os.path.join(other, "Big.cs"), "w") as fh:
        fh.write("x\n" * 1000)

    def rd(path, **kw):
        return decide({"tool_name": "Read", "tool_input": {"file_path": path, **kw},
                       "cwd": ws, "session_id": "s1", **({"agent_type": kw.pop("agent")} if "agent" in kw else {})})

    first = rd(big)
    second = rd(big)
    third = rd(big)
    checks = [
        ("large whole read denied", first is not None and first["hookSpecificOutput"]["permissionDecision"] == "deny"),
        ("denial names the reader", first and "al-file-reader" in first["hookSpecificOutput"]["permissionDecisionReason"]),
        ("denial says a ranged read is enough to Edit",
         first and "ranged Read of the lines you will change is enough" in first["hookSpecificOutput"]["permissionDecisionReason"]),
        ("repeat is denied too (Edit never needed a full read)", second is not None),
        ("third identical attempt is the escape", third is None),
        ("ranged read allowed", rd(big, offset=10, limit=50) is None),
        ("small file allowed", rd(small) is None),
        ("file-reader exempt", decide({"tool_name": "Read", "tool_input": {"file_path": big}, "cwd": ws,
                                       "session_id": "s2", "agent_type": "bc-dev:al-file-reader"}) is None),
        ("non-AL workspace allowed", decide({"tool_name": "Read", "tool_input": {"file_path": os.path.join(other, "Big.cs")},
                                             "cwd": other, "session_id": "s3"}) is None),
        ("shell cat denied", decide({"tool_name": "Bash", "tool_input": {"command": f'cat "{big}"'},
                                     "cwd": ws, "session_id": "s4"}) is not None),
        ("shell head allowed", decide({"tool_name": "Bash", "tool_input": {"command": f'head -50 "{big}"'},
                                       "cwd": ws, "session_id": "s4"}) is None),
    ]
    os.environ["ALDC_READ_GUARD_DISABLE"] = "1"
    checks.append(("kill switch", decide({"tool_name": "Read", "tool_input": {"file_path": big}, "cwd": ws,
                                          "session_id": "s5"}) is None))
    del os.environ["ALDC_READ_GUARD_DISABLE"]
    ok = True
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    shutil.rmtree(ws, ignore_errors=True)
    shutil.rmtree(other, ignore_errors=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else main())
