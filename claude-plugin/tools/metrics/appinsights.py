#!/usr/bin/env python3
"""Send an ALDC metrics record to Azure Application Insights as a custom event.

WHY DIRECT HTTP AND NOT AN SDK. This runs inside a `SubagentStop` hook on a developer's
machine. Requiring `pip install azure-monitor-opentelemetry` on every workstation to record
four numbers is not a trade anyone would take, and a hook that fails because a package is
missing is worse than no telemetry. The ingestion contract is public — Microsoft's own FAQ
says so — so this speaks it directly with `urllib` and `gzip`, both stdlib.

THE ENVELOPE IS NOT GUESSED. Field names and the event shape were read out of Microsoft's
own generated model in `azure-monitor-opentelemetry-exporter`
(`_generated/exporter/models/_models.py`):

    TelemetryItem      ver, name, time (rfc3339), sampleRate, seq, iKey, tags, data
    MonitorBase        baseType, baseData
    TelemetryEventData ver, name, properties (str->str), measurements (str->float)

with `name = "Microsoft.ApplicationInsights.Event"` and `baseType = "EventData"`, and the
path `/track` appended to the connection string's `IngestionEndpoint`. Those land in the
`customEvents` table, with `properties` queryable as `customDimensions` and `measurements`
as `customMeasurements` — which is the whole reason to use an event rather than a metric:
one row per phase, sliceable by project, agent and verdict.

CONFIGURATION is the standard Azure variable, so a machine or a pipeline that already has
it set needs nothing else:

    APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=...;IngestionEndpoint=https://<region>.in.applicationinsights.azure.com/

Nothing ships in the plugin. No connection string, no key, no default endpoint.

PRIVACY is inherited, not re-decided: this sends the record `parse_subagent.py` already
built, which by construction holds only counts, an enum verdict, and public BCQuality
knowledge paths.
"""

from __future__ import annotations

import gzip
import json
import os
import socket
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone

ENVELOPE_NAME = "Microsoft.ApplicationInsights.Event"
BASE_TYPE = "EventData"
EVENT_NAME = "AldcPhase"
SDK_TAG = "aldc-plugin:1"
TIMEOUT_S = 3

# Application Insights caps a property value at 8192 chars and a key at 150. Our values are
# short by construction; the cap is here so a future field cannot silently truncate a whole
# envelope server-side.
MAX_PROP_LEN = 8192


def parse_connection_string(cs: str) -> tuple[str, str] | None:
    """-> (instrumentation_key, ingestion_endpoint) or None if unusable.

    Per the connection-string schema: semicolon-separated key=value, `InstrumentationKey`
    required, `IngestionEndpoint` optional (the global endpoint is the documented fallback
    when only a key is given).
    """
    if not cs:
        return None
    parts: dict[str, str] = {}
    for chunk in cs.split(";"):
        if "=" not in chunk:
            continue
        k, _, v = chunk.partition("=")
        parts[k.strip().lower()] = v.strip()
    ikey = parts.get("instrumentationkey", "")
    if not ikey:
        return None
    endpoint = parts.get("ingestionendpoint", "").rstrip("/")
    if not endpoint:
        # Documented behaviour when the connection string carries only a key.
        endpoint = "https://dc.services.visualstudio.com"
    if not endpoint.startswith("https://"):
        return None
    return ikey, endpoint


def _props(rec: dict) -> dict[str, str]:
    """String dimensions — what you group by in KQL."""
    bcq = rec.get("bcq") or {}
    out = {
        "agent": str(rec.get("agent", "")),
        "project": str(rec.get("project", "")),
        "session": str(rec.get("session", "")),
        "schema": str(rec.get("schema", "")),
        "bcqMounted": str(bool(bcq.get("mounted", False))).lower(),
    }
    if rec.get("verdict"):
        out["verdict"] = str(rec["verdict"])
    if rec.get("phase") is not None:
        out["phase"] = str(rec["phase"])
    if bcq.get("sha"):
        out["bcqSha"] = str(bcq["sha"])
    # Knowledge paths as one delimited string: a dimension per path would explode
    # cardinality, and KQL splits it back with `split(customDimensions.knowledge, "|")`.
    if rec.get("knowledge"):
        out["knowledge"] = "|".join(rec["knowledge"])
    if rec.get("deviations_declared"):
        out["deviationsDeclared"] = "|".join(rec["deviations_declared"])
    return {k: v[:MAX_PROP_LEN] for k, v in out.items() if v not in ("", "None")}


def _measurements(rec: dict) -> dict[str, float]:
    """Numeric measures — what you aggregate in KQL."""
    bcq = rec.get("bcq") or {}
    f = rec.get("findings") or {}
    src = {
        "prescribed": bcq.get("prescribed"),
        "applied": bcq.get("applied"),
        "deviated": bcq.get("deviated"),
        "undeclared": bcq.get("undeclared"),
        "declared": bcq.get("declared"),
        "cited": bcq.get("cited"),
        "agentFindings": bcq.get("agent_findings"),
        "totalFindings": bcq.get("total_findings"),
        "independenceRatio": bcq.get("independence_ratio"),
        "findingsCritical": f.get("critical"),
        "findingsMajor": f.get("major"),
        "findingsMinor": f.get("minor"),
    }
    return {k: float(v) for k, v in src.items() if isinstance(v, (int, float))}


def build_envelope(rec: dict, ikey: str, role: str = "aldc-plugin") -> dict:
    ts = rec.get("ts") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "ver": 1,
        "name": ENVELOPE_NAME,
        "time": ts,
        "iKey": ikey,
        "tags": {
            "ai.cloud.role": role,
            "ai.cloud.roleInstance": str(rec.get("project", "unknown")),
            # Correlates every phase of one Claude Code session into a single operation.
            "ai.operation.id": str(rec.get("session") or uuid.uuid4().hex[:8]),
            "ai.internal.sdkVersion": SDK_TAG,
        },
        "data": {
            "baseType": BASE_TYPE,
            "baseData": {
                "ver": 2,
                "name": EVENT_NAME,
                "properties": _props(rec),
                "measurements": _measurements(rec),
            },
        },
    }


def send(rec: dict, connection_string: str = "", log=lambda _m: None) -> bool:
    """POST one record. Returns True only on a 2xx. Never raises."""
    cs = connection_string or os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING", "")
    parsed = parse_connection_string(cs)
    if not parsed:
        if cs:
            log("appinsights: connection string present but unusable (no InstrumentationKey, "
                "or a non-https IngestionEndpoint)")
        return False
    ikey, endpoint = parsed

    role = os.environ.get("ALDC_METRICS_CLOUD_ROLE", "aldc-plugin")
    body = json.dumps([build_envelope(rec, ikey, role)], ensure_ascii=False).encode("utf-8")

    try:
        payload = gzip.compress(body)
        req = urllib.request.Request(f"{endpoint}/v2/track", data=payload, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("Content-Encoding", "gzip")
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            # 200 all accepted, 206 partial. Anything else is worth a log line but never an
            # exception: telemetry must not be able to disturb a development session.
            if resp.status in (200, 206):
                log(f"appinsights: {resp.status}")
                return True
            log(f"appinsights: unexpected status {resp.status}")
            return False
    except urllib.error.HTTPError as exc:
        # 400 invalid, 402 quota, 429 throttled, 5xx server — all documented; none retried
        # here on purpose. A hook is not the place for a retry queue, and the JSONL lanes
        # already hold the record, so nothing is lost.
        log(f"appinsights: HTTP {exc.code} (record kept in the local lanes)")
        return False
    except (urllib.error.URLError, socket.timeout, OSError) as exc:
        log(f"appinsights: unreachable ({type(exc).__name__}) - record kept locally")
        return False


def self_test() -> int:
    """Validates the envelope against the field names read from Microsoft's generated model,
    and proves the privacy guarantee survives the transformation into an envelope."""
    ok = True
    rec = {
        "schema": 1, "ts": "2026-09-05T12:00:00Z", "session": "abcdef12",
        "project": "CustomerProj", "agent": "al-review-subagent", "phase": 3,
        "verdict": "APPROVED",
        "bcq": {"mounted": True, "sha": "ad8ccde", "prescribed": 6, "applied": 5,
                "deviated": 1, "undeclared": 0, "cited": 3, "agent_findings": 2,
                "total_findings": 9, "independence_ratio": 0.222},
        "findings": {"critical": 0, "major": 1, "minor": 4},
        "knowledge": ["microsoft/knowledge/events/a.md", "custom/knowledge/style/b.md"],
        "deviations_declared": ["microsoft/knowledge/performance/c.md"],
    }
    env = build_envelope(rec, "00000000-0000-0000-0000-000000000000")
    bd = env["data"]["baseData"]
    blob = json.dumps(env)

    checks = [
        ("envelope name", env["name"] == "Microsoft.ApplicationInsights.Event"),
        ("iKey field present", "iKey" in env),
        ("time is rfc3339", env["time"].endswith("Z")),
        ("baseType", env["data"]["baseType"] == "EventData"),
        ("baseData.ver", bd["ver"] == 2),
        ("event name", bd["name"] == "AldcPhase"),
        ("properties all str", all(isinstance(v, str) for v in bd["properties"].values())),
        ("measurements all float", all(isinstance(v, float) for v in bd["measurements"].values())),
        ("dimension: verdict", bd["properties"]["verdict"] == "APPROVED"),
        ("dimension: phase as string", bd["properties"]["phase"] == "3"),
        ("measure: independenceRatio", bd["measurements"]["independenceRatio"] == 0.222),
        ("measure: findingsMajor", bd["measurements"]["findingsMajor"] == 1.0),
        ("knowledge joined, not exploded", bd["properties"]["knowledge"].count("|") == 1),
        ("operation id correlates the session", env["tags"]["ai.operation.id"] == "abcdef12"),
        ("no free text leaked", "last_assistant_message" not in blob and "Codeunit" not in blob),
    ]

    cs = ("InstrumentationKey=11111111-2222-3333-4444-555555555555;"
          "IngestionEndpoint=https://westeurope-1.in.applicationinsights.azure.com/;"
          "LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/")
    parsed = parse_connection_string(cs)
    checks += [
        ("connection string parsed", parsed is not None),
        ("ikey extracted", parsed and parsed[0] == "11111111-2222-3333-4444-555555555555"),
        ("endpoint extracted without trailing slash",
         parsed and parsed[1] == "https://westeurope-1.in.applicationinsights.azure.com"),
        ("key-only falls back to the global endpoint",
         parse_connection_string("InstrumentationKey=abc") ==
         ("abc", "https://dc.services.visualstudio.com")),
        ("no key -> unusable", parse_connection_string("IngestionEndpoint=https://x/") is None),
        ("http endpoint -> unusable",
         parse_connection_string("InstrumentationKey=a;IngestionEndpoint=http://x/") is None),
        ("empty -> unusable", parse_connection_string("") is None),
        ("unset env sends nothing", send({}, "", lambda _m: None) is False),
    ]

    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    import sys

    if "--self-test" in sys.argv:
        sys.exit(self_test())
    if "--print-envelope" in sys.argv:
        print(json.dumps(build_envelope(json.load(sys.stdin), "IKEY-PLACEHOLDER"), indent=2))
        sys.exit(0)
    # Default: read one record on stdin and send it.
    sys.exit(0 if send(json.load(sys.stdin), log=lambda m: print(m)) else 1)
