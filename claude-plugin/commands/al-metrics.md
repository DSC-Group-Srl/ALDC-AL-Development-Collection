---
description: >
  Report the ALDC quality metrics collected from review, implementation and audit phases —
  independence-ratio, deviation rate, undeclared deviations, and prescribed-vs-cited. Use
  when you want to know whether the BCQuality-guided flow is actually working, which
  prescribed rules keep being deviated from, or whether the review has drifted into merely
  agreeing with the implementer.
allowed-tools: Bash, Read
argument-hint: "optional: --days 30 · --project <name> · --json"
---

# ALDC Quality Metrics

Aggregate and interpret the metrics the `SubagentStop` hook has been collecting.

## What is being measured, and why these four

The BCQuality-guided flow puts the same knowledge on both sides of the work: the implementer
writes against a prescribed worklist, the reviewer checks it. That removes a real problem —
the two used to follow contradicting rule sets — but it introduces one, and these metrics
exist to catch it.

| Metric | What it catches |
|---|---|
| **independence-ratio** | agent findings / total findings. The review drawing on the same corpus as the implementer stops being an independent measurement and becomes a consistency check. This ratio is the only number that shows it happening. Trending to zero means the review is agreeing, not measuring. |
| **deviation rate** | deviated / prescribed. Normal at a low level. Persistently high means a prescribed rule does not fit how we build — promote it to a `/custom/` override rather than deviating from it every phase. |
| **undeclared deviations** | Must be zero. Non-zero means the implementer is not reading the worklist, which makes every other number here meaningless. |
| **cited vs prescribed** | How much the review still finds on its own in domains that were prescribed. High means the prescriptive pass is scoped too narrowly. |

## Run it

```bash
"${CLAUDE_PLUGIN_ROOT}/tools/metrics/report.sh" $ARGUMENTS
```

Pass `--days 30` to window the report, `--project <name>` to narrow to one project, `--json`
for the raw aggregate.

## Then interpret

Render what the script prints, and add the judgement it cannot make:

1. **Read the `READING` column first.** Each metric carries its own threshold; the script
   flags the ones that are out of range. Do not restate a healthy metric at length.
2. **When `undeclared deviations > 0`, that is the headline** regardless of what the other
   numbers say. Nothing else can be trusted until it is zero. Look at which phases produced
   them and say so.
3. **When the independence-ratio is low or zero**, check the obvious mechanical cause before
   concluding anything about quality: the review agent is supposed to run its agent-findings
   pass on every diff larger than ~2 files / 30 lines. A zero ratio across many phases is far
   more likely to be that pass being skipped than a genuinely defect-free codebase.
4. **Turn the most-deviated list into an action.** An article deviated three or more times is
   a `/custom/` override candidate: say which, and why the deviation reasons suggest the rule
   does not fit us.
5. **Note thin data honestly.** Under about five reviews these ratios are noise. Say so
   rather than reading a trend into four data points.

## Where the data lives

- `$CLAUDE_PLUGIN_DATA/metrics/aldc-metrics.jsonl` — always written, survives plugin updates.
- `<project>/.github/metrics/aldc-metrics.jsonl` — only when that directory exists. Create it
  to version metrics with the project.
- **Azure Application Insights** — when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set, each
  record is also sent as an `AldcPhase` custom event. That is the estate-wide view: this
  command reports the local machine, KQL reports everyone. If the user is asking about trends
  across projects or over months, point them at `tools/metrics/azure/queries.kql` and the
  workbook rather than trying to answer from one machine's JSONL.
- `$ALDC_METRICS_ENDPOINT` — a plain webhook, when set. Off by default; no credential ships
  in the plugin.

Records hold counts, verdicts and BCQuality knowledge paths. **No message bodies, no customer
AL, no repo paths** — enforced in the parser, not merely intended, because these files travel.

If nothing has been collected, the script says where to look; the usual cause is no python
interpreter on `PATH`, which the capture hook records in `metrics/capture.log` rather than
failing the session.
