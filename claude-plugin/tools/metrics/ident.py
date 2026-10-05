#!/usr/bin/env python3
"""Who and where an ALDC event comes from — the dimensions the GITCloner control panel needs
to tell "my sessions" from the team's, and this machine from another one or from the cloud.

    userHash     sha256("aldc-user-v1:" + lower(email))[:16] — the join key. GITCloner hashes
                 the Claude / gh / git e-mails of whoever runs it the same way to find "mine".
    user         the e-mail's local part (`mario.rossi`), so the team view can say who.
                 ALDC_METRICS_ANONYMOUS=1 drops it and keeps only the hash.
    machineHash  sha256("aldc-machine-v1:" + lower(hostname))[:12]
    where        "cloud" in a Claude Code cloud session (CLAUDE_CODE_REMOTE=true), else "local"
    session      the first 8 chars of the Claude Code session id — the same prefix
                 `claude agents` shows, so a local panel can join events to its sessions.

The e-mail is read from, in order: ALDC_USER_EMAIL, the signed-in Claude account
(~/.claude.json oauthAccount.emailAddress), `git config user.email`. Nothing else about the
account is read, and the full address never leaves this module.

Never raises: every lookup degrades to "unknown"/absent.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import socket
import subprocess

RE_LOCAL = re.compile(r"^[A-Za-z0-9._+-]{1,64}$")
RE_SESSION = re.compile(r"^[A-Za-z0-9_-]{8,80}$")

_email_cache: list[str] = []


def _truthy(v: str) -> bool:
    return (v or "").strip().lower() in ("1", "true", "yes", "on")


def email() -> str:
    if _email_cache:
        return _email_cache[0]
    e = os.environ.get("ALDC_USER_EMAIL", "").strip()
    if not e:
        try:
            with open(os.path.join(os.path.expanduser("~"), ".claude.json"), encoding="utf-8") as fh:
                e = str(((json.load(fh) or {}).get("oauthAccount") or {}).get("emailAddress") or "")
        except (OSError, ValueError, AttributeError):
            e = ""
    if not e:
        try:
            e = subprocess.run(["git", "config", "user.email"], capture_output=True, text=True,
                               timeout=3).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            e = ""
    e = e.lower() if "@" in e else ""
    _email_cache.append(e)
    return e


def user_hash(e: str) -> str:
    return hashlib.sha256(("aldc-user-v1:" + e.strip().lower()).encode()).hexdigest()[:16] if e else ""


def machine_hash() -> str:
    try:
        h = socket.gethostname()
    except OSError:
        h = ""
    return hashlib.sha256(("aldc-machine-v1:" + h.lower()).encode()).hexdigest()[:12] if h else ""


def is_cloud() -> bool:
    return _truthy(os.environ.get("CLAUDE_CODE_REMOTE", ""))


def session_id(explicit: str = "") -> str:
    """Full session id: the hook payload's, else the one Claude Code puts in the Bash env."""
    s = explicit or os.environ.get("CLAUDE_CODE_SESSION_ID", "") or os.environ.get(
        "CLAUDE_CODE_REMOTE_SESSION_ID", "")
    return s if RE_SESSION.match(s or "") else ""


def props(session: str = "") -> dict[str, str]:
    """The identity dimensions for one event. Empty values are dropped."""
    out: dict[str, str] = {"where": "cloud" if is_cloud() else "local"}
    e = email()
    if e:
        out["userHash"] = user_hash(e)
        local = e.split("@", 1)[0]
        if not _truthy(os.environ.get("ALDC_METRICS_ANONYMOUS", "")) and RE_LOCAL.match(local):
            out["user"] = local
    m = machine_hash()
    if m:
        out["machineHash"] = m
    s = session_id(session)
    if s:
        out["session"] = s[:8]
    b = os.environ.get("CLAUDE_CODE_BRIDGE_SESSION_ID", "")
    if re.match(r"^session_[A-Za-z0-9]{8,64}$", b):
        out["bridgeSession"] = b  # claude.ai/code/<id> — lets the panel open the session
    return out


def self_test() -> int:
    env_keys = ("ALDC_USER_EMAIL", "ALDC_METRICS_ANONYMOUS", "CLAUDE_CODE_REMOTE",
                "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_BRIDGE_SESSION_ID")
    backup = {k: os.environ.get(k) for k in env_keys}
    try:
        for k in env_keys:
            os.environ.pop(k, None)
        os.environ["ALDC_USER_EMAIL"] = "Mario.Rossi@Example.com"
        os.environ["CLAUDE_CODE_SESSION_ID"] = "20a903ef-52d2-48d7-b681-990ce2056020"
        _email_cache.clear()
        p = props()
        os.environ["ALDC_METRICS_ANONYMOUS"] = "1"
        os.environ["CLAUDE_CODE_REMOTE"] = "true"
        os.environ["CLAUDE_CODE_BRIDGE_SESSION_ID"] = "session_014FJYLCSBFaxWgN2eaq4eCB"
        anon = props()
        checks = [
            ("hash is case-insensitive", p.get("userHash") == user_hash("mario.rossi@example.com")),
            ("hash length", len(p.get("userHash", "")) == 16),
            ("local part only", p.get("user") == "mario.rossi"),
            ("full e-mail never present", "example.com" not in json.dumps(p).lower()),
            ("session is the 8-char prefix", p.get("session") == "20a903ef"),
            ("local by default", p.get("where") == "local"),
            ("anonymous drops the name", "user" not in anon and anon.get("userHash")),
            ("cloud detected", anon.get("where") == "cloud"),
            ("bridge session kept", anon.get("bridgeSession") == "session_014FJYLCSBFaxWgN2eaq4eCB"),
            ("junk session id rejected", session_id("../../etc") == ""),
            ("known vector", user_hash("a@b.c") == hashlib.sha256(b"aldc-user-v1:a@b.c").hexdigest()[:16]),
        ]
    finally:
        _email_cache.clear()
        for k, v in backup.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    ok = True
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    import sys

    sys.exit(self_test() if "--self-test" in sys.argv else 0)
