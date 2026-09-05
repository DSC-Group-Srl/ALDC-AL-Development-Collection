# ALDC metrics on Azure Application Insights

Enterprise aggregation for the four quality metrics. One Application Insights resource
receives one custom event per TDD phase from every developer machine, and KQL does the rest.

> **What is in this folder is everything that belongs in a repo.** The `az deployment` and
> the distribution of the connection string are yours to run — they need a subscription and
> credentials this repo does not and must not have.

## Why an event and not a metric

Every record lands in `customEvents` as `AldcPhase`, with numbers in `customMeasurements`
and dimensions in `customDimensions`. That means one row per phase, sliceable by project,
agent and verdict, and re-aggregatable after the fact — you can ask a question in six months
that nobody thought of today. Pre-aggregated `customMetrics` would have thrown the dimensions
away at write time, and these numbers are only interesting *sliced*: an independence-ratio
averaged across the whole company hides the one project where the review stopped measuring.

## How it gets there

```
al-review-subagent finishes
        │
        ▼  SubagentStop hook (last_assistant_message)
  parse_subagent.py ──▶ JSONL, always, in $CLAUDE_PLUGIN_DATA
        │
        └─▶ appinsights.py ──▶ POST gzip {IngestionEndpoint}/v2/track ──▶ customEvents
             (only when APPLICATIONINSIGHTS_CONNECTION_STRING is set)
```

No SDK: the ingestion contract is public and `appinsights.py` speaks it with `urllib` and
`gzip` from the standard library. Requiring `pip install azure-monitor-opentelemetry` on
every workstation to record four numbers is not a trade worth making, and a hook that fails
because a package is missing is worse than no telemetry.

The envelope shape was read out of Microsoft's own generated model in
`azure-monitor-opentelemetry-exporter`, not guessed — see the module docstring. Send failures
are logged and dropped: the local JSONL lanes already hold every record, so nothing is lost
and a hook is not the place for a retry queue.

## 1. Deploy

```bash
az group create -n rg-aldc-metrics -l westeurope
az deployment group create -g rg-aldc-metrics -f main.bicep -p environment=prod
```

[`main.bicep`](main.bicep) creates a Log Analytics workspace and a workspace-based
Application Insights component. Two settings worth knowing about:

- **`dailyQuotaGb` (default 1)** — a hard ingestion cap, so a runaway loop cannot produce a
  bill. A phase record is well under 1 KB; realistic volume for a consultancy is a few MB a
  month, so the cap will never be reached in normal use and exists purely as a stop.
- **`SamplingPercentage: 100`** — never sample. The point is counting every phase, and at
  this volume sampling would only add error.

## 2. Distribute the connection string

```bash
az monitor app-insights component show \
  -g rg-aldc-metrics -a appi-aldc-metrics-prod --query connectionString -o tsv
```

Set it as `APPLICATIONINSIGHTS_CONNECTION_STRING` — the standard Azure variable, so a machine
or pipeline that already has it configured needs nothing else:

| Where | How |
|---|---|
| Developer machine (Windows) | `setx APPLICATIONINSIGHTS_CONNECTION_STRING "InstrumentationKey=...;IngestionEndpoint=..."` |
| Developer machine (macOS/Linux) | export it from `~/.zshrc` / `~/.bashrc` |
| GitHub Actions | a repository or organisation secret, exported as an `env:` on the job |
| Azure DevOps | a variable group linked to Key Vault |

Optionally set `ALDC_METRICS_CLOUD_ROLE` to separate estates (defaults to `aldc-plugin`); it
lands in `ai.cloud.role`.

**On treating it as a secret.** An App Insights connection string is a *write* key: someone
who has it can send you junk telemetry, but cannot read anything. So it is configuration
rather than a credential — but it still does not belong in a committed file, which is why the
plugin ships no default and reads it only from the environment.

## 3. Confirm it arrives

Run one TDD phase, then, after a minute or two:

```kql
customEvents | where name == "AldcPhase" | order by timestamp desc | take 5
```

Nothing showing up? In order of likelihood:

1. **The variable is not visible to the hook.** It is read by the process Claude Code spawns,
   so a variable exported only in an already-open shell will not reach it. Restart the client.
2. **Ingestion latency.** Under five minutes is normal.
3. **Look at the log.** `$CLAUDE_PLUGIN_DATA/metrics/capture.log` records every send with its
   status: `appinsights: 200`, an `HTTP 4xx`, or `unreachable`. A `400` means a malformed
   envelope, `402` means the daily cap is hit, `429` means throttling.
4. **No python on `PATH`.** The capture hook needs one and says so in the same log.

The local JSONL lanes keep working regardless, so `/aldc:al-metrics` still reports while the
Azure lane is being sorted out.

## 4. Query and visualise

[`queries.kql`](queries.kql) has eight ready blocks: the four headline metrics, the
verdict mix, most-cited and most-deviated knowledge, plus two health checks (runs where
BCQuality was not mounted, and which pin the estate is actually on).

[`workbook.json`](workbook.json) is an importable Azure Workbook with the four metrics as
tiles, the independence-ratio trend against its 0.15 floor, the most-deviated articles, and a
per-project health table. Import it from the Application Insights resource →
**Workbooks** → **New** → **</>** (Advanced Editor) → paste → **Apply** → **Save**.

## What is stored

Counts, an enum verdict, and BCQuality knowledge paths — public Microsoft content. **Never a
message body, never customer AL, never a path inside a customer repo, never a full cwd.**
`project` is a directory basename and `session` is eight characters. That is enforced in
`parse_subagent.py` and covered by assertions in its self-test, because this data leaves the
developer's machine.

If a project name is itself sensitive — a client name in a folder — the honest fix is to set
`ALDC_METRICS_CLOUD_ROLE` per estate and stop sending the project dimension, not to rely on
obscurity. Say so and it takes ten minutes to add.

## Cost

At a few hundred phases a month this is a rounding error: Log Analytics bills by ingested GB
with 5 GB/month free on pay-as-you-go, and these records total a few MB. The `dailyQuotaGb`
cap and the 90-day default retention are there so it stays that way without anyone watching.
