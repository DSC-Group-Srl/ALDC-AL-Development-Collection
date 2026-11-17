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
    issueNo      the DSC Business Central Issue (its entryNo, digits only) this session's work
                 is linked to, once `emit.py AldcIssue issueNo=<n>` has set it. Kept in
                 `<live dir>/<session>.issue`; every later event of the session carries it, so
                 tokens, time and outcome join to the Issue's estimated and actual hours.

The e-mail is ALDC_USER_EMAIL when set; otherwise the first address on the company domain
(ALDC_COMPANY_EMAIL_DOMAIN, default dsc-group.net) among the signed-in Claude account
(~/.claude.json oauthAccount.emailAddress) and `git config user.email` (repo, then global);
otherwise the company address this machine resolved before; otherwise whatever was found. A
personal address therefore never wins over the company one (see email()). Nothing else about
the account is read, and the full address never leaves this machine.

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
RE_ISSUE = re.compile(r"^[1-9][0-9]{0,9}$")  # an Issue entryNo: a positive integer, nothing else

_email_cache: list[str] = []


def _truthy(v: str) -> bool:
    return (v or "").strip().lower() in ("1", "true", "yes", "on")


def company_domain() -> str:
    """The company e-mail domain (same variable as tools/issue/whoami.sh)."""
    return (os.environ.get("ALDC_COMPANY_EMAIL_DOMAIN", "") or "dsc-group.net").strip().lower()


def _identity_file() -> str:
    return os.path.join(os.path.expanduser("~"), ".claude", "aldc-plugin-data", "identity.json")


def _claude_email() -> str:
    for base in dict.fromkeys((os.environ.get("CLAUDE_CONFIG_DIR", ""), os.path.expanduser("~"))):
        if not base:
            continue
        try:
            with open(os.path.join(base, ".claude.json"), encoding="utf-8") as fh:
                return str(((json.load(fh) or {}).get("oauthAccount") or {}).get("emailAddress") or "")
        except (OSError, ValueError, AttributeError):
            continue
    return ""


def _git_email(*scope: str) -> str:
    try:
        return subprocess.run(["git", "config", *scope, "user.email"], capture_output=True,
                              text=True, timeout=3).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def _remembered() -> str:
    try:
        with open(_identity_file(), encoding="utf-8") as fh:
            return str((json.load(fh) or {}).get("email") or "")
    except (OSError, ValueError, AttributeError):
        return ""


def _remember(e: str) -> None:
    if _remembered() == e:
        return
    try:
        os.makedirs(os.path.dirname(_identity_file()), exist_ok=True)
        with open(_identity_file(), "w", encoding="utf-8") as fh:
            json.dump({"email": e}, fh)
    except OSError:
        pass


def _norm(e: str) -> str:
    e = (e or "").strip().strip('"').lower()
    return e if "@" in e and " " not in e else ""


def email() -> str:
    """One person, one identity. The same developer used to show up twice (a personal address
    in git or the Claude login on one machine, the company one on another), splitting their
    runs in every per-user view. So:
      1. ALDC_USER_EMAIL, when set, wins outright;
      2. else the first address on the company domain among the Claude login, the repo's and
         the global git e-mail;
      3. else the company address this machine resolved before (~/.claude/aldc-plugin-data/
         identity.json, written by step 2 — it stays on this machine);
      4. else the first address found at all."""
    if _email_cache:
        return _email_cache[0]
    e = _norm(os.environ.get("ALDC_USER_EMAIL", ""))
    if not e:
        dom = "@" + company_domain()
        found = [x for x in (_norm(_claude_email()), _norm(_git_email()), _norm(_git_email("--global"))) if x]
        e = next((x for x in found if x.endswith(dom)), "")
        if e:
            _remember(e)
        else:
            r = _norm(_remembered())
            e = r if r.endswith(dom) else (found[0] if found else "")
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


def _live_dir() -> str:
    # Same place as emit.live_dir(); repeated here because emit imports this module.
    return os.environ.get("ALDC_LIVE_DIR") or os.path.join(
        os.path.expanduser("~"), ".claude", "aldc-plugin-data", "live")


def issue_no(session: str = "") -> str:
    """The BC Issue linked to this session, or "" — never anything but digits."""
    s = session_id(session)
    if not s:
        return ""
    try:
        with open(os.path.join(_live_dir(), f"{s}.issue"), encoding="utf-8") as fh:
            v = fh.read(32).strip()
    except OSError:
        return ""
    return v if RE_ISSUE.match(v) else ""


def issue_state(session: str = "") -> str:
    """What the session's user answered about its Issue: "linked" (a number), "none" (the user
    said there is no Issue for this work) or "" (nobody has answered yet)."""
    if issue_no(session):
        return "linked"
    s = session_id(session)
    if not s:
        return ""
    try:
        with open(os.path.join(_live_dir(), f"{s}.issue"), encoding="utf-8") as fh:
            return "none" if fh.read(32).strip().lower() == "none" else ""
    except OSError:
        return ""


def set_issue(session: str, no: str) -> bool:
    """Link the session to Issue `no` (digits), record the user's "none" (no Issue for this
    work), or clear the link with "0". False when the session id or the number is not usable;
    never raises."""
    s = session_id(session)
    if not s:
        return False
    p = os.path.join(_live_dir(), f"{s}.issue")
    try:
        if no == "0":
            if os.path.isfile(p):
                os.remove(p)
            return True
        no = "none" if (no or "").strip().lower() == "none" else no
        if no != "none" and not RE_ISSUE.match(no or ""):
            return False
        os.makedirs(_live_dir(), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(no)
        return True
    except OSError:
        return False


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
    i = issue_no(session)
    if i:
        out["issueNo"] = i
    if excluded():
        out["exclude"] = "true"
    return out


def excluded() -> bool:
    """ALDC_METRICS_EXCLUDE=1: a dry run, demo or self-test — still recorded, but every
    event says `exclude=true` so the estimation and team queries leave it out."""
    return _truthy(os.environ.get("ALDC_METRICS_EXCLUDE", ""))


def self_test() -> int:
    import tempfile

    env_keys = ("ALDC_USER_EMAIL", "ALDC_METRICS_ANONYMOUS", "CLAUDE_CODE_REMOTE",
                "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_BRIDGE_SESSION_ID", "ALDC_METRICS_EXCLUDE",
                "ALDC_LIVE_DIR")
    backup = {k: os.environ.get(k) for k in env_keys}
    try:
        for k in env_keys:
            os.environ.pop(k, None)
        os.environ["ALDC_USER_EMAIL"] = "Mario.Rossi@Example.com"
        os.environ["CLAUDE_CODE_SESSION_ID"] = "20a903ef-52d2-48d7-b681-990ce2056020"
        os.environ["ALDC_LIVE_DIR"] = tempfile.mkdtemp(prefix="aldc-ident-")
        _email_cache.clear()
        p = props()
        bad_set = [set_issue("", v) for v in ("12a", "-4", "1 2", "../x", "", "00")]
        linked_ok = set_issue("", "4821")
        linked = props()
        other = props("ffffffff-0000-4000-8000-000000000000")
        with open(os.path.join(_live_dir(), "20a903ef-52d2-48d7-b681-990ce2056020.issue"), "w") as fh:
            fh.write("Customer X: invoice wrong")
        tampered = props()
        set_issue("", "77")
        cleared_ok = set_issue("", "0")
        cleared = props()
        os.environ["ALDC_METRICS_ANONYMOUS"] = "1"
        os.environ["CLAUDE_CODE_REMOTE"] = "true"
        os.environ["CLAUDE_CODE_BRIDGE_SESSION_ID"] = "session_014FJYLCSBFaxWgN2eaq4eCB"
        anon = props()
        os.environ["ALDC_METRICS_EXCLUDE"] = "1"
        excl = props()
        # "none" is an answer, distinct from no answer; it never becomes an issueNo.
        none_ok = set_issue("", "none")
        none_state, none_props = issue_state(), props()
        set_issue("", "0")
        unanswered = issue_state()
        # Identity: the company address wins over a personal one, whichever source has it.
        os.environ.pop("ALDC_USER_EMAIL", None)
        home = tempfile.mkdtemp(prefix="aldc-home-")
        g = globals()
        saved = (g["_claude_email"], g["_git_email"], g["_identity_file"])
        try:
            g["_identity_file"] = lambda: os.path.join(home, "identity.json")
            g["_claude_email"] = lambda: "Mario.Rossi@gmail.com"
            g["_git_email"] = lambda *a: "" if a else "mario.rossi@dsc-group.net"
            _email_cache.clear()
            prefers_company = email()
            g["_git_email"] = lambda *a: ""
            _email_cache.clear()
            remembered = email()
            g["_identity_file"] = lambda: os.path.join(home, "nothing-here.json")
            _email_cache.clear()
            personal_only = email()
        finally:
            g["_claude_email"], g["_git_email"], g["_identity_file"] = saved
            _email_cache.clear()
        checks = [
            ("issue none: recorded as an answer", none_ok and none_state == "none"),
            ("issue none: never sent as issueNo", "issueNo" not in none_props),
            ("issue state: empty when nobody answered", unanswered == ""),
            ("identity: company address beats a personal one", prefers_company == "mario.rossi@dsc-group.net"),
            ("identity: the machine remembers its company address", remembered == "mario.rossi@dsc-group.net"),
            ("identity: a personal address is used only when nothing else exists", personal_only == "mario.rossi@gmail.com"),
            ("not excluded by default", "exclude" not in p),
            ("no issue until one is linked", "issueNo" not in p),
            ("issue link: only a positive integer is accepted", not any(bad_set) and linked_ok),
            ("issue link: carried by the session's events", linked.get("issueNo") == "4821"),
            ("issue link: another session does not see it", "issueNo" not in other),
            ("issue link: a tampered file is ignored", "issueNo" not in tampered),
            ("issue link: 0 clears it", cleared_ok and "issueNo" not in cleared),
            ("ALDC_METRICS_EXCLUDE marks the event", excl.get("exclude") == "true"),
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
