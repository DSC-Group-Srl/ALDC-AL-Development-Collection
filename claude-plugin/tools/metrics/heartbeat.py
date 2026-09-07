#!/usr/bin/env python3
"""Send one AldcHeartbeat event: the bc-dev version installed on this machine, and whether
this run is an upgrade from a previously-seen version.

Called by heartbeat.sh on SessionStart, which does the throttling and upgrade detection
(reading and writing the stamp files) and passes the result in as arguments. This script only
shapes and sends the event — kept separate from parse_subagent.py because a heartbeat is not
a phase result: no BCQuality accounting, no review, sometimes no AL project even open. It
exists purely to answer "what version of bc-dev is actually running out there", which does
not wait for anyone to run a TDD phase — everyone updates the plugin before everyone runs a
review, so this is the only way to see rollout across the estate as it happens.

Same privacy discipline as parse_subagent.py: the properties below are the whole payload,
built field by field, never copied from anything free-text. Version string, a project
basename, and the OS family.
"""

from __future__ import annotations

import argparse
import os
import platform
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appinsights  # noqa: E402

EVENT_NAME = "AldcHeartbeat"


def build_properties(version: str, previous_version: str, cwd: str) -> dict[str, str]:
    props = {
        "pluginVersion": version,
        "project": os.path.basename(cwd.rstrip("/\\")) or "unknown",
        "os": (platform.system() or "unknown").lower(),
        "upgraded": str(bool(previous_version) and previous_version != version).lower(),
    }
    if previous_version:
        props["previousVersion"] = previous_version
    return props


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True, help="current bc-dev version")
    ap.add_argument("--previous-version", default="", help="version last seen on this machine, if any")
    ap.add_argument("--cwd", default=os.getcwd())
    args = ap.parse_args()

    if not args.version:
        return 0  # nothing worth reporting

    props = build_properties(args.version, args.previous_version, args.cwd)
    # Fire-and-forget: heartbeat.sh already decided this attempt is due, and a failed send
    # here (no connection string configured, network unreachable) is not an error condition
    # for the hook — there is nothing local to fall back to for a heartbeat, unlike a phase
    # record, which always has its JSONL lanes regardless of this outcome.
    appinsights.send_event(EVENT_NAME, props, {}, operation_id=uuid.uuid4().hex[:8],
                            log=lambda _m: None)
    return 0


def self_test() -> int:
    ok = True
    checks = [
        ("fresh install (no previous version)",
         build_properties("5.2", "", "/home/x/CustomerProj") ==
         {"pluginVersion": "5.2", "project": "CustomerProj", "os": platform.system().lower(),
          "upgraded": "false"}),
        ("same version, no upgrade flagged",
         build_properties("5.2", "5.2", "/p/Proj")["upgraded"] == "false"),
        ("version changed -> upgraded true",
         build_properties("5.2", "5.1", "/p/Proj")["upgraded"] == "true"),
        ("previousVersion carried only on an upgrade",
         "previousVersion" not in build_properties("5.2", "", "/p/Proj")),
        ("previousVersion present when it changed",
         build_properties("5.2", "5.1", "/p/Proj")["previousVersion"] == "5.1"),
        ("project is a basename, not a path",
         "/" not in build_properties("5.2", "", "/deep/path/CustomerProj")["project"]),
        ("appinsights.send_event reachable", hasattr(appinsights, "send_event")),
    ]
    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(main())
