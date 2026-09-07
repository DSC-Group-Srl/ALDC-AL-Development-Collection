#!/usr/bin/env python3
"""Send an ALDC metrics event to Azure Application Insights.

WHY DIRECT HTTP AND NOT AN SDK. This runs inside Claude Code hooks on a developer's machine.
Requiring `pip install azure-monitor-opentelemetry` on every workstation to record a handful
of numbers is not a trade anyone would take, and a hook that fails because a package is
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
one row per phase (or per heartbeat), sliceable by project, agent and verdict.

TWO EVENT NAMES ship from this module:

    AldcPhase       one per TDD phase — see `send()`, built from a parse_subagent.py record.
    AldcHeartbeat   one per machine, on SessionStart, carrying only the plugin version — see
                    heartbeat.py. Answers "what is actually deployed", which does not wait
                    for anyone to run a review.

Both go through `send_event()`, the generic primitive.

CONFIGURATION resolves in this order — see `resolve_connection_string()`:
  1. `ALDC_METRICS_APPINSIGHTS_DISABLE` set → nothing is sent, full stop.
  2. an explicit `connection_string` argument.
  3. the standard Azure environment variable, `APPLICATIONINSIGHTS_CONNECTION_STRING` —
     lets a machine, a CI run, or a developer point at a different resource (or, set to
     empty, silence it) without touching the plugin.
  4. `appinsights.connection`, shipped beside this file. This is what makes it install
     itself: once DSC pastes the estate's connection string into that file and commits it,
     every machine that gets the plugin update reports with zero per-machine setup — the
     same pattern as `tools/bcquality/bcquality.pin`, for a write key instead of a
     knowledge-base pin. Empty by default, so a fresh checkout sends nothing.

PRIVACY is inherited, not re-decided here: `send()` forwards the record `parse_subagent.py`
already built, which by construction holds only counts, an enum verdict, and public
BCQuality knowledge paths. `heartbeat.py` builds its own minimal properties (version,
project basename, OS) with the same discipline.
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
PHASE_EVENT_NAME = "AldcPhase"
SDK_TAG = "aldc-plugin:1"
TIMEOUT_S = 3

# Application Insights caps a property value at 8192 chars and a key at 150. Our values are
# short by construction; the cap is here so a future field cannot silently truncate a whole
# envelope server-side.
MAX_PROP_LEN = 8192

_CONNECTION_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "appinsights.connection")


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


def read_shipped_connection_string(path: str = _CONNECTION_FILE) -> str:
    """The plugin-shipped default — see `appinsights.connection`. First non-comment,
    non-blank line, with an optional `connectionString=` prefix stripped. Absent file or any
    read error is silently "no default", never an exception."""
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.split("#", 1)[0].strip()
                if not line:
                    continue
                if line.lower().startswith("connectionstring="):
                    line = line.split("=", 1)[1].strip()
                return line
    except OSError:
        pass
    return ""


def _is_truthy(v: str) -> bool:
    return v.strip().lower() in ("1", "true", "yes", "on")


def resolve_connection_string(explicit: str = "") -> str:
    """Priority: a per-machine disable switch beats everything; then an explicit argument;
    then the standard environment variable; then the connection string shipped with the
    plugin. See the module docstring for why each rung exists."""
    if _is_truthy(os.environ.get("ALDC_METRICS_APPINSIGHTS_DISABLE", "")):
        return ""
    if explicit:
        return explicit
    env = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING", "").strip()
    if env:
        return env
    return read_shipped_connection_string()


def _props(rec: dict) -> dict[str, str]:
    """String dimensions for an AldcPhase event — what you group by in KQL."""
    bcq = rec.get("bcq") or {}
    out = {
        "agent": str(rec.get("agent", "")),
        "project": str(rec.get("project", "")),
        "session": str(rec.get("session", "")),
        "schema": str(rec.get("schema", "")),
        "bcqMounted": str(bool(bcq.get("mounted", False))).lower(),
    }
    if rec.get("pluginVersion"):
        out["pluginVersion"] = str(rec["pluginVersion"])
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
    return {k: v for k, v in out.items() if v not in ("", "None")}


def _measurements(rec: dict) -> dict[str, float]:
    """Numeric measures for an AldcPhase event — what you aggregate in KQL."""
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


def build_envelope(event_name: str, properties: dict, measurements: dict, ikey: str,
                    role: str = "aldc-plugin", ts: str = "", operation_id: str = "") -> dict:
    """The generic envelope, shared by AldcPhase and AldcHeartbeat. Property values are
    stringified and length-capped here, once, so every caller gets the same discipline."""
    ts = ts or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    props = {str(k): str(v)[:MAX_PROP_LEN] for k, v in properties.items() if v not in ("", None)}
    return {
        "ver": 1,
        "name": ENVELOPE_NAME,
        "time": ts,
        "iKey": ikey,
        "tags": {
            "ai.cloud.role": role,
            "ai.cloud.roleInstance": str(properties.get("project", "unknown")),
            # Correlates related events (every phase of one session, or a heartbeat) together.
            "ai.operation.id": str(operation_id or uuid.uuid4().hex[:8]),
            "ai.internal.sdkVersion": SDK_TAG,
        },
        "data": {
            "baseType": BASE_TYPE,
            "baseData": {
                "ver": 2,
                "name": event_name,
                "properties": props,
                "measurements": {k: float(v) for k, v in measurements.items()
                                 if isinstance(v, (int, float))},
            },
        },
    }


def send_event(event_name: str, properties: dict, measurements: dict, *,
               connection_string: str = "", ts: str = "", operation_id: str = "",
               role: str = "", log=lambda _m: None) -> bool:
    """POST one custom event. Returns True only on a 2xx. Never raises.

    This is the generic primitive both `send()` (AldcPhase) and heartbeat.py (AldcHeartbeat)
    call. `connection_string`, when given, is still passed through `resolve_connection_string`
    so the disable switch always wins even when a caller supplies one explicitly.
    """
    cs = resolve_connection_string(connection_string)
    parsed = parse_connection_string(cs)
    if not parsed:
        if cs:
            log("appinsights: connection string present but unusable (no InstrumentationKey, "
                "or a non-https IngestionEndpoint)")
        return False
    ikey, endpoint = parsed
    role = role or os.environ.get("ALDC_METRICS_CLOUD_ROLE", "aldc-plugin")

    envelope = build_envelope(event_name, properties, measurements, ikey, role,
                               ts=ts, operation_id=operation_id)
    body = json.dumps([envelope], ensure_ascii=False).encode("utf-8")

    try:
        payload = gzip.compress(body)
        req = urllib.request.Request(f"{endpoint}/v2/track", data=payload, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("Content-Encoding", "gzip")
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            # 200 all accepted, 206 partial. Anything else is worth a log line but never an
            # exception: telemetry must not be able to disturb a development session.
            if resp.status in (200, 206):
                log(f"appinsights: {event_name} {resp.status}")
                return True
            log(f"appinsights: {event_name} unexpected status {resp.status}")
            return False
    except urllib.error.HTTPError as exc:
        # 400 invalid, 402 quota, 429 throttled, 5xx server — all documented; none retried
        # here on purpose. A hook is not the place for a retry queue, and (for AldcPhase) the
        # JSONL lanes already hold the record, so nothing real is lost.
        log(f"appinsights: {event_name} HTTP {exc.code}")
        return False
    except (urllib.error.URLError, socket.timeout, OSError) as exc:
        log(f"appinsights: {event_name} unreachable ({type(exc).__name__})")
        return False


def send(rec: dict, connection_string: str = "", log=lambda _m: None) -> bool:
    """Send one AldcPhase event, built from a parse_subagent.py record."""
    return send_event(PHASE_EVENT_NAME, _props(rec), _measurements(rec),
                       connection_string=connection_string,
                       ts=rec.get("ts"), operation_id=rec.get("session"), log=log)


def self_test() -> int:
    """Validates the envelope against the field names read from Microsoft's generated model,
    proves the privacy guarantee survives the transformation into an envelope, and exercises
    connection-string resolution including the shipped-file default and the disable switch."""
    ok = True
    rec = {
        "schema": 1, "ts": "2026-09-05T12:00:00Z", "session": "abcdef12",
        "project": "CustomerProj", "agent": "al-review-subagent", "phase": 3,
        "verdict": "APPROVED", "pluginVersion": "5.2",
        "bcq": {"mounted": True, "sha": "ad8ccde", "prescribed": 6, "applied": 5,
                "deviated": 1, "undeclared": 0, "cited": 3, "agent_findings": 2,
                "total_findings": 9, "independence_ratio": 0.222},
        "findings": {"critical": 0, "major": 1, "minor": 4},
        "knowledge": ["microsoft/knowledge/events/a.md", "custom/knowledge/style/b.md"],
        "deviations_declared": ["microsoft/knowledge/performance/c.md"],
    }
    env = build_envelope(PHASE_EVENT_NAME, _props(rec), _measurements(rec),
                          "00000000-0000-0000-0000-000000000000",
                          ts=rec["ts"], operation_id=rec["session"])
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
        ("dimension: pluginVersion", bd["properties"]["pluginVersion"] == "5.2"),
        ("measure: independenceRatio", bd["measurements"]["independenceRatio"] == 0.222),
        ("measure: findingsMajor", bd["measurements"]["findingsMajor"] == 1.0),
        ("knowledge joined, not exploded", bd["properties"]["knowledge"].count("|") == 1),
        ("operation id correlates the session", env["tags"]["ai.operation.id"] == "abcdef12"),
        ("no free text leaked", "last_assistant_message" not in blob and "Codeunit" not in blob),
    ]

    # A distinct event name with its own shape — proves send_event is genuinely generic, not
    # AldcPhase with a relabeled name.
    hb_env = build_envelope("AldcHeartbeat", {"pluginVersion": "5.2", "project": "proj",
                                               "upgraded": "true", "previousVersion": "5.1"},
                             {}, "IKEY", operation_id="deadbeef")
    hb_bd = hb_env["data"]["baseData"]
    checks += [
        ("heartbeat event name", hb_bd["name"] == "AldcHeartbeat"),
        ("heartbeat has no measurements", hb_bd["measurements"] == {}),
        ("heartbeat carries the version", hb_bd["properties"]["pluginVersion"] == "5.2"),
        ("heartbeat carries upgrade flag", hb_bd["properties"]["upgraded"] == "true"),
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
        ("unset env, no shipped file sends nothing", send({}, "", lambda _m: None) is False),
    ]

    # --- resolve_connection_string: the priority order, isolated from the real environment
    # and the real shipped file so this doesn't depend on what happens to be configured.
    import tempfile

    env_backup = {k: os.environ.get(k) for k in
                  ("APPLICATIONINSIGHTS_CONNECTION_STRING", "ALDC_METRICS_APPINSIGHTS_DISABLE")}
    for k in env_backup:
        os.environ.pop(k, None)
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".connection", delete=False) as tf:
            tf.write("# comment\n\nconnectionString=InstrumentationKey=shipped-key\n")
            shipped_path = tf.name

        checks += [
            ("no config anywhere -> empty", resolve_connection_string() == ""),
            ("shipped file read (comment/blank lines skipped)",
             read_shipped_connection_string(shipped_path) == "InstrumentationKey=shipped-key"),
            ("missing shipped file -> empty",
             read_shipped_connection_string("/no/such/file") == ""),
        ]

        os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"] = "InstrumentationKey=env-key"
        checks.append(("env var wins over nothing", resolve_connection_string() == "InstrumentationKey=env-key"))

        checks.append(("explicit arg wins over env var",
                       resolve_connection_string("InstrumentationKey=explicit-key")
                       == "InstrumentationKey=explicit-key"))

        os.environ["ALDC_METRICS_APPINSIGHTS_DISABLE"] = "1"
        checks.append(("disable switch beats an explicit arg",
                       resolve_connection_string("InstrumentationKey=explicit-key") == ""))
    finally:
        os.unlink(shipped_path)
        for k, v in env_backup.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    for name, passed in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and bool(passed)
    return 0 if ok else 1


if __name__ == "__main__":
    import sys

    if "--self-test" in sys.argv:
        sys.exit(self_test())
    if "--print-envelope" in sys.argv:
        rec_in = json.load(sys.stdin)
        env_out = build_envelope(PHASE_EVENT_NAME, _props(rec_in), _measurements(rec_in),
                                  "IKEY-PLACEHOLDER", ts=rec_in.get("ts"),
                                  operation_id=rec_in.get("session"))
        print(json.dumps(env_out, indent=2))
        sys.exit(0)
    # Default: read one AldcPhase record on stdin and send it.
    sys.exit(0 if send(json.load(sys.stdin), log=lambda m: print(m)) else 1)
