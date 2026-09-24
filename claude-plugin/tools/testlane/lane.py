#!/usr/bin/env python3
"""ALDC test lane — one shared BC test environment, used by one run at a time.

Most DSC jobs have exactly one environment that can run unit tests. Parallel work packages,
a second Claude session, or a colleague's agent on the same machine must not publish over
each other's apps mid-run, so every publish+test sequence goes through this lane:

    lane.py configs  <project-dir>                     list usable launch.json configurations
    lane.py prepare  <project-dir> <config-name>       write a single-config scratch project
    lane.py acquire  <env-key> [--wait 900]            take the lock (blocks up to --wait s)
    lane.py release  <env-key>                         give it back (idempotent)
    lane.py status   <env-key>                         who holds it, since when
    lane.py publish  <scratch-dir> <app-file>          al publishapp, classified result
    lane.py run      <scratch-dir> <codeunit-id>...    al runtests per codeunit, parsed totals

WHY A SCRATCH PROJECT: the AL CLI (18.x) lower-cases every option it receives, so
`--environmentType Sandbox` never binds; `--project <dir>` is the only reliable way to
target an environment, and it reads the FIRST configuration in that dir's
.vscode/launch.json. `prepare` writes a scratch dir holding only the chosen configuration.

THE LOCK is a directory (mkdir is atomic on every filesystem we run on — same pattern as
tools/bcquality/precondition_hook.sh) under ~/.claude/aldc-testlane/, keyed by a hash of the
environment identity (server+instance or environmentName, plus tenant), so two projects
pointing at the same environment share one lock. A holder that died is recovered after
--stale seconds (default 1800). Two developers on DIFFERENT machines are not covered.

Every command prints one JSON object on stdout and exits 0 unless the arguments are wrong,
so agents parse results instead of scraping logs. Timings are emitted as AldcLane metrics.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

LOCK_ROOT = os.path.join(os.path.expanduser("~"), ".claude", "aldc-testlane")
HERE = os.path.dirname(os.path.abspath(__file__))


def out(obj: dict) -> int:
    print(json.dumps(obj, ensure_ascii=False))
    return 0


def _strip_jsonc(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"(^|[^:\"])//[^\n]*", r"\1", text)
    return re.sub(r",(\s*[}\]])", r"\1", text)


def load_configs(project: str) -> list[dict]:
    p = os.path.join(project, ".vscode", "launch.json")
    try:
        with open(p, encoding="utf-8-sig") as fh:
            data = json.loads(_strip_jsonc(fh.read()))
    except (OSError, ValueError):
        return []
    return [c for c in data.get("configurations", []) if c.get("type") == "al"]


def env_type(c: dict) -> str:
    t = str(c.get("environmentType", "")).strip()
    if t:
        return t
    return "OnPrem" if c.get("server") else "Sandbox"


def env_key(c: dict) -> str:
    ident = "|".join(str(c.get(k, "")).lower() for k in
                     ("server", "serverInstance", "environmentName", "tenant"))
    return hashlib.sha256(ident.encode()).hexdigest()[:16]


def describe(c: dict) -> dict:
    t = env_type(c)
    where = (c.get("environmentName") or "") if t != "OnPrem" else \
        f"{c.get('server', '')}{c.get('serverInstance', '')}"
    return {"name": c.get("name", ""), "envType": t, "where": where, "envKey": env_key(c),
            "auth": c.get("authentication", "AAD" if t != "OnPrem" else "")}


def app_target(project: str) -> str:
    try:
        with open(os.path.join(project, "app.json"), encoding="utf-8-sig") as fh:
            return str(json.load(fh).get("target", "Cloud"))
    except (OSError, ValueError):
        return ""


def cmd_configs(project: str) -> int:
    cfgs = [describe(c) for c in load_configs(project)]
    target = app_target(project)
    for d in cfgs:
        # An OnPrem/Internal-targeted test app is rejected by a SaaS sandbox at publish time
        # ("destinazione di compilazione superiore a quella consentita") — flag it up front.
        d["compatible"] = not (target in ("OnPrem", "Internal") and d["envType"] != "OnPrem")
        if d["compatible"] and d["envType"] == "OnPrem":
            # A Docker config in launch.json says nothing about whether the container exists.
            d["reachable"] = reachable(next((c.get("server", "") for c in load_configs(project)
                                             if c.get("name") == d["name"]), ""))
    usable = [d["name"] for d in cfgs if d["compatible"] and d.get("reachable", True)]
    res = {"project": os.path.basename(os.path.abspath(project)), "appTarget": target,
           "configurations": cfgs, "usable": usable}
    dev = find_devenv(project)
    if dev:
        # AL-Go ships .AL-Go/localDevEnv.ps1 (Docker) and cloudDevEnv.ps1 (SaaS sandbox) in every
        # template repo. Always report them; `suggest` tells the caller to offer one now.
        dev["recommended"] = "local" if target in ("OnPrem", "Internal") or not dev.get("cloud") else \
            ("local" if dev.get("local") else "cloud")
        dev["suggest"] = not usable
        res["devEnv"] = dev
        if dev["suggest"]:
            emit_metric(["result=devenv-suggested"])
    return out(res)


def reachable(server: str, timeout: float = 4) -> bool:
    """Any HTTP answer (even 401/404) means a server is listening; only no answer is False."""
    if not server.startswith(("http://", "https://")) or os.environ.get("ALDC_LANE_NO_PROBE"):
        return True
    import urllib.error
    import urllib.request
    try:
        urllib.request.urlopen(server, timeout=timeout)
        return True
    except urllib.error.HTTPError:
        return True
    except Exception:
        return False


def find_devenv(project: str) -> dict | None:
    """Walk up from the project to the repo root looking for AL-Go's dev-env scripts."""
    d = os.path.abspath(project)
    for _ in range(5):
        algo = os.path.join(d, ".AL-Go")
        if os.path.isdir(algo):
            found = {k: os.path.join(algo, f) for k, f in
                     (("local", "localDevEnv.ps1"), ("cloud", "cloudDevEnv.ps1"))
                     if os.path.isfile(os.path.join(algo, f))}
            return found or None
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return None


def cmd_prepare(project: str, name: str) -> int:
    cfg = next((c for c in load_configs(project) if c.get("name") == name), None)
    if not cfg:
        return out({"ok": False, "error": "configuration not found", "name": name})
    scratch = os.path.join(tempfile.gettempdir(), f"aldc-lane-{env_key(cfg)}")
    os.makedirs(os.path.join(scratch, ".vscode"), exist_ok=True)
    with open(os.path.join(scratch, ".vscode", "launch.json"), "w", encoding="utf-8") as fh:
        json.dump({"version": "0.2.0", "configurations": [cfg]}, fh, indent=2)
    shutil.copyfile(os.path.join(project, "app.json"), os.path.join(scratch, "app.json"))
    return out({"ok": True, "scratch": scratch, **describe(cfg)})


def _lock_dir(key: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{8,64}", key):
        raise SystemExit(out({"ok": False, "error": "bad env key"}) or 2)
    return os.path.join(LOCK_ROOT, f"{key}.lock")


def _owner() -> dict:
    return {"pid": os.getpid(), "session": os.environ.get("CLAUDE_SESSION_ID", "")[:8],
            "host": os.environ.get("COMPUTERNAME") or os.environ.get("HOSTNAME", ""),
            "since": time.time()}


def cmd_acquire(key: str, wait: float, stale: float) -> int:
    d = _lock_dir(key)
    os.makedirs(LOCK_ROOT, exist_ok=True)
    t0 = time.time()
    recovered = 0
    while True:
        try:
            os.mkdir(d)
            with open(os.path.join(d, "owner.json"), "w", encoding="utf-8") as fh:
                json.dump(_owner(), fh)
            waited = round(time.time() - t0, 1)
            emit_metric(["result=acquired", f"lockWaitS={waited}", f"staleRecovered={recovered}"])
            return out({"ok": True, "acquired": True, "waitedS": waited, "staleRecovered": recovered})
        except FileExistsError:
            age = _age(d)
            if age is not None and age > stale:
                shutil.rmtree(d, ignore_errors=True)
                recovered += 1
                continue
            if time.time() - t0 >= wait:
                emit_metric(["result=lock-timeout", f"lockWaitS={round(time.time() - t0, 1)}"])
                return out({"ok": False, "acquired": False, "waitedS": round(time.time() - t0, 1),
                            "holder": _read_owner(d)})
            time.sleep(5)


def _age(d: str) -> float | None:
    o = _read_owner(d)
    if o and isinstance(o.get("since"), (int, float)):
        return time.time() - o["since"]
    try:
        return time.time() - os.path.getmtime(d)
    except OSError:
        return None


def _read_owner(d: str) -> dict:
    try:
        with open(os.path.join(d, "owner.json"), encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def cmd_release(key: str) -> int:
    d = _lock_dir(key)
    existed = os.path.isdir(d)
    shutil.rmtree(d, ignore_errors=True)
    return out({"ok": True, "released": existed})


def cmd_status(key: str) -> int:
    d = _lock_dir(key)
    if not os.path.isdir(d):
        return out({"ok": True, "locked": False})
    return out({"ok": True, "locked": True, "holder": _read_owner(d), "ageS": round(_age(d) or 0)})


def _al(args: list[str], timeout: int) -> tuple[int, str]:
    exe = shutil.which("al") or shutil.which("al.exe")
    if not exe:
        return 127, "al CLI not found on PATH"
    try:
        p = subprocess.run([exe, *args], capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL, encoding="utf-8", errors="replace")
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "timeout"


def _classify_publish(code: int, text: str) -> str:
    if code == 0 and "failed" not in text.lower():
        return "published"
    t = text.lower()
    if "duplicate package id" in t:
        return "already-current"      # this exact build is already there — fine
    if "destinazione di compilazione" in t or "target" in t and "allowed" in t:
        return "target-not-allowed"    # OnPrem/Internal app on a SaaS sandbox
    if any(s in t for s in ("certificate", "econnreset", "timed out", "timeout", "unable to connect",
                            "handshake", "name or service not known")):
        return "tool-blocked"
    if "aadsts" in t or "interactive" in t and "login" in t:
        return "auth-required"
    return "failed"


def cmd_publish(scratch: str, app: str) -> int:
    t0 = time.time()
    code, text = _al(["publishapp", app, "--project", scratch], timeout=900)
    res = _classify_publish(code, text)
    emit_metric([f"result=publish-{res}", f"publishS={round(time.time() - t0, 1)}"])
    reason = next((ln.split("Reason:", 1)[1].strip() for ln in text.splitlines()
                   if "Reason:" in ln and not ln.lstrip().startswith("[")), "")[:400]
    return out({"ok": res in ("published", "already-current"), "result": res,
                "seconds": round(time.time() - t0, 1), "reason": reason})


RE_TOTALS = re.compile(r"Test run completed:\s*(\d+)\s+passed,\s*(\d+)\s+failed,\s*(\d+)\s+skipped", re.I)
RE_LINE = re.compile(r"^\s*(PASS|FAIL|SKIP|ERROR)\s+(\S.*?)\s*\((\d+)ms\)", re.M)


def cmd_run(scratch: str, codeunits: list[str]) -> int:
    t0 = time.time()
    results = []
    tot = {"passed": 0, "failed": 0, "skipped": 0}
    for cu in codeunits:
        if not cu.isdigit():
            continue
        code, text = _al(["runtests", cu, "--project", scratch], timeout=1800)
        m = RE_TOTALS.search(text)
        entry = {"codeunit": int(cu), "exit": code}
        if m:
            p, f, s = (int(x) for x in m.groups())
            entry.update(passed=p, failed=f, skipped=s)
            tot["passed"] += p
            tot["failed"] += f
            tot["skipped"] += s
        else:
            entry["error"] = "no result line" if code != 124 else "timeout"
        if "not found" in text.lower() and "codeunit" in text.lower():
            entry["notFound"] = True
        entry["failures"] = [ln[1] for ln in RE_LINE.findall(text) if ln[0] in ("FAIL", "ERROR")][:20]
        results.append(entry)
    # A codeunit the server does not know ran nothing — that is a failed lane run (usually the
    # test app was not published, or was rejected), never a silent pass.
    ran = tot["passed"] + tot["failed"]
    emit_metric(["result=ran" if ran else "result=nothing-ran", f"runS={round(time.time() - t0, 1)}",
                 f"passed={tot['passed']}", f"failed={tot['failed']}", f"skipped={tot['skipped']}"])
    return out({"ok": tot["failed"] == 0 and ran > 0
                and all("error" not in r and not r.get("notFound") for r in results),
                "seconds": round(time.time() - t0, 1), **tot, "codeunits": results})


def emit_metric(pairs: list[str]) -> None:
    if os.environ.get("ALDC_LANE_NO_METRICS"):
        return
    try:
        subprocess.run([sys.executable, os.path.join(HERE, "..", "metrics", "emit.py"),
                        "AldcLane", *pairs], timeout=15, capture_output=True)
    except (OSError, subprocess.SubprocessError):
        pass


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    cmd, a = argv[0], argv[1:]

    def opt(name: str, default: float) -> float:
        if name in a:
            i = a.index(name)
            v = float(a[i + 1])
            del a[i:i + 2]
            return v
        return default

    if cmd == "configs" and a:
        return cmd_configs(a[0])
    if cmd == "prepare" and len(a) >= 2:
        return cmd_prepare(a[0], " ".join(a[1:]))
    if cmd == "acquire" and a:
        wait, stale = opt("--wait", 900), opt("--stale", 1800)
        return cmd_acquire(a[0], wait, stale)
    if cmd == "release" and a:
        return cmd_release(a[0])
    if cmd == "status" and a:
        return cmd_status(a[0])
    if cmd == "publish" and len(a) >= 2:
        return cmd_publish(a[0], a[1])
    if cmd == "run" and len(a) >= 2:
        return cmd_run(a[0], a[1:])
    if cmd == "metric":
        emit_metric(a)
        return 0
    if cmd == "--self-test":
        return self_test()
    print(__doc__)
    return 2


def self_test() -> int:
    global LOCK_ROOT
    import io
    import contextlib

    LOCK_ROOT = tempfile.mkdtemp()
    os.environ["ALDC_LANE_NO_METRICS"] = "1"
    os.environ["ALDC_LANE_NO_PROBE"] = "1"
    proj = tempfile.mkdtemp()
    os.makedirs(os.path.join(proj, ".vscode"))
    with open(os.path.join(proj, ".vscode", "launch.json"), "w", encoding="utf-8") as fh:
        fh.write('{ // comment\n "configurations": [\n'
                 ' {"name": "Docker", "type": "al", "environmentType": "OnPrem", "server": "http://x", "serverInstance": "BC"},\n'
                 ' {"name": "Sbx", "type": "al", "environmentType": "Sandbox", "environmentName": "Dev", "tenant": "t"},\n'
                 ' ]}')
    with open(os.path.join(proj, "app.json"), "w", encoding="utf-8") as fh:
        json.dump({"id": "x", "target": "OnPrem"}, fh)

    def run(*args: str) -> dict:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            main(list(args))
        return json.loads(buf.getvalue())

    os.makedirs(os.path.join(proj, ".AL-Go"))
    open(os.path.join(proj, ".AL-Go", "localDevEnv.ps1"), "w").close()
    c = run("configs", proj)
    key = c["configurations"][1]["envKey"]
    p = run("prepare", proj, "Sbx")
    with open(os.path.join(p["scratch"], ".vscode", "launch.json"), encoding="utf-8") as fh:
        only = json.load(fh)["configurations"]
    a1 = run("acquire", key, "--wait", "0")
    a2 = run("acquire", key, "--wait", "0")
    st = run("status", key)
    # simulate a dead holder
    with open(os.path.join(LOCK_ROOT, f"{key}.lock", "owner.json"), "w", encoding="utf-8") as fh:
        json.dump({"since": time.time() - 99999}, fh)
    a3 = run("acquire", key, "--wait", "0", "--stale", "60")
    r = run("release", key)
    r2 = run("release", key)
    checks = [
        ("jsonc launch.json parsed", len(c["configurations"]) == 2),
        ("OnPrem target flags sandbox incompatible", c["usable"] == ["Docker"]),
        ("AL-Go dev-env script reported, local recommended for OnPrem target",
         c.get("devEnv", {}).get("recommended") == "local" and c["devEnv"]["suggest"] is False),
        ("prepare writes exactly one config", len(only) == 1 and only[0]["name"] == "Sbx"),
        ("first acquire wins", a1["acquired"] is True),
        ("second acquire refused", a2["acquired"] is False),
        ("status shows holder", st["locked"] is True),
        ("stale holder recovered", a3["acquired"] is True and a3["staleRecovered"] == 1),
        ("release", r["released"] is True and r2["released"] is False),
        ("dup package id = already-current", _classify_publish(1, "A duplicate package ID is detected") == "already-current"),
        ("sandbox target rejection classified", _classify_publish(1, "destinazione di compilazione superiore") == "target-not-allowed"),
        ("tls = tool-blocked", _classify_publish(1, "unable to verify the first certificate") == "tool-blocked"),
        ("totals regex", RE_TOTALS.search("Test run completed: 3 passed, 1 failed, 0 skipped.") is not None),
    ]
    ok = True
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    shutil.rmtree(LOCK_ROOT, ignore_errors=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
