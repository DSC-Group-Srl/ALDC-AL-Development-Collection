#!/usr/bin/env python3
"""Efficiency counters from a Claude Code transcript (JSONL): tokens, turns, wall-clock,
tool calls, reads, builds, skill loads, subagent spawns.

Used by parse_subagent.py (one subagent's own transcript, on SubagentStop) and by
session_end.py (the main session's transcript, on SessionEnd). Semantic metrics — BCQuality
accounting, verdicts — stay in parse_subagent.py; this module only counts.

SAME PRIVACY RULE AS THE REST OF tools/metrics: the output is numbers plus allowlisted
identifiers (tool names, our own agent and skill names, model ids). No path, no argument
value, no message text ever leaves this module. Every string that reaches the result passes
through one of the `_allow_*` filters below.

Transcript shape (read from real transcripts, not guessed): one JSON object per line;
assistant lines carry `message.model`, `message.usage` and `message.content[]` blocks, and a
single API request is streamed as several lines sharing one `requestId` with the same usage
repeated — so usage is de-duplicated per requestId, keeping the largest output count.
Tool results arrive as user lines whose `message.content[]` holds `tool_result` blocks.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from datetime import datetime

# Our MCP servers: the verb is worth keeping (al_compile vs al_symbolsearch is the whole
# point of measuring). Anything else collapses to its server-less bucket.
_MCP_SERVERS = ("al-mcp", "nab-al-tools", "context7", "microsoft-docs", "ms-learn")
_BUILTIN = {
    "Read", "Write", "Edit", "Glob", "Grep", "Bash", "PowerShell", "Task", "Agent", "Skill",
    "WebFetch", "WebSearch", "TodoWrite", "AskUserQuestion", "NotebookEdit", "LSP",
    "ToolSearch", "SendMessage",
}
_RE_SKILL = re.compile(r"^(?:bc-dev:)?(skill-[a-z0-9-]{2,60})$")
_RE_OWN_AGENT = re.compile(
    r"^(?:bc-dev:|plugin_bc-dev:)?(al-[a-z0-9-]{2,60}|dredd)$"
)
_RE_MODEL = re.compile(r"^(claude-[a-z0-9.-]{2,60})")
_RE_BUILD_CMD = re.compile(r"(?:^|[;&|]\s*)al(?:\.exe)?\s+(?:workspace\s+)?compile\b")
_RE_LANE_CMD = re.compile(r"(?:^|[;&|]\s*)al(?:\.exe)?\s+(publishapp|runtests)\b")
_BUILD_VERBS = {"al_compile", "al_build"}


def _allow_tool(name: str) -> str:
    if name in _BUILTIN:
        return name
    if name.startswith("mcp__"):
        parts = name.split("__")
        server, verb = (parts[1] if len(parts) > 1 else ""), (parts[-1] if len(parts) > 2 else "")
        for s in _MCP_SERVERS:
            if server.endswith(s) and re.fullmatch(r"[a-z0-9_-]{2,60}", verb or ""):
                return f"{s}:{verb}"
        return "mcp:other"
    return "other"


def _allow_skill(name: str) -> str | None:
    m = _RE_SKILL.match(name or "")
    return m.group(1) if m else None


def allow_agent(name: str) -> str:
    """Our own agents by name; any other subagent type becomes 'other'."""
    tail = (name or "").split(":")[-1].strip()
    return tail if _RE_OWN_AGENT.match(tail) else ("other" if tail else "")


def _ts(s: str) -> datetime | None:
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def _result_len(block: dict) -> int:
    c = block.get("content")
    if isinstance(c, str):
        return len(c)
    if isinstance(c, list):
        return sum(len(x.get("text", "")) for x in c if isinstance(x, dict))
    return 0


def summarize(path: str, max_lines: int = 200_000) -> dict | None:
    """Counters for one transcript file, or None if it is missing or unreadable."""
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        return None

    usage_by_req: dict[str, dict] = {}
    models: Counter = Counter()
    tools: Counter = Counter()
    skills: Counter = Counter()
    spawns: Counter = Counter()
    read_ids: dict[str, str] = {}  # tool_use id -> "whole" | "ranged"
    reads = {"whole": 0, "ranged": 0, "wholeChars": 0, "rangedChars": 0, "bcquality": 0}
    builds = lane_cmds = human_turns = asks = 0
    first = last = first_tool = None

    with fh:
        for i, line in enumerate(fh):
            if i >= max_lines:
                break
            try:
                d = json.loads(line)
            except ValueError:
                continue
            t = _ts(d.get("timestamp"))
            if t:
                first = first or t
                last = t
            msg = d.get("message") if isinstance(d.get("message"), dict) else {}
            content = msg.get("content")
            if d.get("type") == "assistant":
                m = _RE_MODEL.match(str(msg.get("model", "")))
                if m:
                    models[m.group(1)] += 1
                u = msg.get("usage")
                if isinstance(u, dict):
                    key = str(d.get("requestId") or d.get("uuid") or i)
                    prev = usage_by_req.get(key)
                    if not prev or u.get("output_tokens", 0) >= prev.get("output_tokens", 0):
                        usage_by_req[key] = u
                for b in content if isinstance(content, list) else []:
                    if not isinstance(b, dict) or b.get("type") != "tool_use":
                        continue
                    first_tool = first_tool or t
                    name = str(b.get("name", ""))
                    inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                    tools[_allow_tool(name)] += 1
                    if name == "Read":
                        kind = "ranged" if ("offset" in inp or "limit" in inp) else "whole"
                        reads[kind] += 1
                        read_ids[str(b.get("id"))] = kind
                        if "bcquality" in str(inp.get("file_path", "")).replace("\\", "/").lower():
                            reads["bcquality"] += 1
                    elif name == "Skill":
                        s = _allow_skill(str(inp.get("skill", "")))
                        if s:
                            skills[s] += 1
                    elif name in ("Task", "Agent"):
                        a = allow_agent(str(inp.get("subagent_type", "")))
                        if a:
                            spawns[a] += 1
                    elif name == "AskUserQuestion":
                        asks += 1
                    elif name in ("Bash", "PowerShell"):
                        cmd = str(inp.get("command", ""))
                        if _RE_BUILD_CMD.search(cmd):
                            builds += 1
                        if _RE_LANE_CMD.search(cmd):
                            lane_cmds += 1
                    elif _allow_tool(name).split(":")[-1] in _BUILD_VERBS:
                        builds += 1
            elif d.get("type") == "user":
                if isinstance(content, str) and content.strip():
                    human_turns += 1
                for b in content if isinstance(content, list) else []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_result":
                        kind = read_ids.pop(str(b.get("tool_use_id")), None)
                        if kind:
                            reads[f"{kind}Chars"] += _result_len(b)
                    elif b.get("type") == "text" and b.get("text", "").strip():
                        human_turns += 1

    if not usage_by_req and not tools:
        return None
    tok = Counter()
    for u in usage_by_req.values():
        for k_in, k_out in (("input_tokens", "input"), ("output_tokens", "output"),
                            ("cache_read_input_tokens", "cacheRead"),
                            ("cache_creation_input_tokens", "cacheCreation")):
            v = u.get(k_in)
            if isinstance(v, (int, float)):
                tok[k_out] += int(v)
    tok["total"] = tok["input"] + tok["output"] + tok["cacheRead"] + tok["cacheCreation"]

    out = {
        "tokens": dict(tok),
        "turns": len(usage_by_req),
        "wallSeconds": round((last - first).total_seconds(), 1) if first and last else None,
        "firstToolSeconds": round((first_tool - first).total_seconds(), 1)
        if first and first_tool else None,
        "tools": dict(tools),
        "reads": reads,
        "builds": builds,
        "laneCommands": lane_cmds,
        "skills": dict(skills),
        "spawns": dict(spawns),
        "asks": asks,
        "humanTurns": human_turns,
    }
    if models:
        out["model"] = models.most_common(1)[0][0]
    return out


def first_timestamp(path: str) -> str:
    """ISO timestamp of the first timestamped line of a transcript, '' if unknown."""
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    t = json.loads(line).get("timestamp")
                except ValueError:
                    continue
                if t:
                    return str(t)
    except OSError:
        pass
    return ""


def flatten(u: dict, prefix: str = "") -> dict[str, float]:
    """Numeric leaves as App Insights measurements: tokens.output -> tokensOutput."""
    out: dict[str, float] = {}
    for k, v in (u or {}).items():
        k = re.sub(r"[^A-Za-z0-9]+", "_", str(k)).strip("_")
        key = f"{prefix}{k[:1].upper()}{k[1:]}" if prefix else k
        if isinstance(v, dict):
            out.update(flatten(v, key))
        elif isinstance(v, (int, float)) and not isinstance(v, bool):
            out[key] = float(v)
    return out


def project_hash(cwd: str) -> str:
    """Salted hash of the AL app id found at/under cwd — groups records by project without
    revealing which customer it is. Empty when no app.json is found."""
    import hashlib
    import os

    cands = [os.path.join(cwd, "app.json"), os.path.join(cwd, "app", "app.json")]
    try:
        cands += [os.path.join(cwd, d, "app.json") for d in sorted(os.listdir(cwd))]
    except OSError:
        pass
    for c in cands:
        try:
            with open(c, encoding="utf-8-sig") as fh:
                app_id = str(json.load(fh).get("id", ""))
        except (OSError, ValueError, AttributeError):
            continue
        if app_id:
            return hashlib.sha256(("aldc-metrics-v1:" + app_id.lower()).encode()).hexdigest()[:12]
    return ""


def self_test() -> int:
    import os
    import tempfile

    lines = [
        {"type": "user", "timestamp": "2026-09-24T10:00:00Z", "message": {"content": "do it"}},
        {"type": "assistant", "requestId": "r1", "timestamp": "2026-09-24T10:00:05Z",
         "message": {"model": "claude-sonnet-5", "usage": {"input_tokens": 10, "output_tokens": 1,
                     "cache_read_input_tokens": 100, "cache_creation_input_tokens": 50},
                     "content": [{"type": "tool_use", "id": "t1", "name": "Read",
                                  "input": {"file_path": "C:/Customer/Secret.Codeunit.al"}}]}},
        {"type": "assistant", "requestId": "r1", "timestamp": "2026-09-24T10:00:06Z",
         "message": {"model": "claude-sonnet-5", "usage": {"input_tokens": 10, "output_tokens": 40,
                     "cache_read_input_tokens": 100, "cache_creation_input_tokens": 50},
                     "content": [{"type": "tool_use", "id": "t2", "name": "Read",
                                  "input": {"file_path": "x", "offset": 5, "limit": 10}}]}},
        {"type": "user", "timestamp": "2026-09-24T10:00:07Z", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "t1", "content": "A" * 300},
            {"type": "tool_result", "tool_use_id": "t2", "content": [{"type": "text", "text": "B" * 20}]}]}},
        {"type": "assistant", "requestId": "r2", "timestamp": "2026-09-24T10:01:00Z",
         "message": {"model": "claude-sonnet-5", "usage": {"input_tokens": 5, "output_tokens": 7},
                     "content": [
                         {"type": "tool_use", "id": "t3", "name": "mcp__plugin_bc-dev_al-mcp__al_compile", "input": {}},
                         {"type": "tool_use", "id": "t4", "name": "Bash", "input": {"command": "cd x && al compile -project:app"}},
                         {"type": "tool_use", "id": "t5", "name": "Skill", "input": {"skill": "bc-dev:skill-events"}},
                         {"type": "tool_use", "id": "t6", "name": "Skill", "input": {"skill": "customer-secret-skill"}},
                         {"type": "tool_use", "id": "t7", "name": "Task", "input": {"subagent_type": "bc-dev:al-file-reader"}},
                         {"type": "tool_use", "id": "t8", "name": "mcp__evil__steal", "input": {}},
                     ]}},
    ]
    fd, p = tempfile.mkstemp(suffix=".jsonl")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        for ln in lines:
            fh.write(json.dumps(ln) + "\n")
    s = summarize(p)
    os.unlink(p)
    blob = json.dumps(s)
    checks = [
        ("parsed", s is not None),
        ("usage deduped per requestId", s and s["tokens"]["output"] == 47),
        ("cache tokens", s and s["tokens"]["cacheRead"] == 100 and s["tokens"]["cacheCreation"] == 50),
        ("total", s and s["tokens"]["total"] == 15 + 47 + 100 + 50),
        ("turns", s and s["turns"] == 2),
        ("wall-clock", s and s["wallSeconds"] == 60.0),
        ("reads split", s and s["reads"]["whole"] == 1 and s["reads"]["ranged"] == 1),
        ("read chars", s and s["reads"]["wholeChars"] == 300 and s["reads"]["rangedChars"] == 20),
        ("builds (mcp + cli)", s and s["builds"] == 2),
        ("mcp verb kept", s and s["tools"].get("al-mcp:al_compile") == 1),
        ("unknown mcp collapsed", s and s["tools"].get("mcp:other") == 1),
        ("own skill kept", s and s["skills"] == {"skill-events": 1}),
        ("own agent spawn", s and s["spawns"] == {"al-file-reader": 1}),
        ("model", s and s["model"] == "claude-sonnet-5"),
        ("human turn", s and s["humanTurns"] == 1),
        ("NO path leaked", "Secret" not in blob and "Customer" not in blob),
        ("NO foreign skill leaked", "customer-secret-skill" not in blob),
        ("NO command leaked", "-project:app" not in blob),
        ("flatten", flatten({"tokens": {"output": 3}})["tokensOutput"] == 3.0),
    ]
    ok = True
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    import sys

    sys.exit(self_test() if "--self-test" in sys.argv else 0)
