---
description: "Shared ALDC agent contract: BCQuality consultation, evidence markers (a metrics-parser contract — byte-exact), Knowledge Deviations, skills evidencing, targeted reads via al-file-reader, and test-lane usage. Pasted inline by al-conductor into every code-touching subagent; standalone agents (al-developer, dredd, al-triage) read it once per session before writing or judging AL."
paths:
  - "**/*.al"
  - "**/app.json"
---

# ALDC Agent Contract

One copy of the rules every AL-writing or AL-judging agent shares. Agent files reference this
instead of restating it. **The marker lines below are parsed by `tools/metrics/parse_subagent.py`
— copy them byte for byte; a reworded marker is silently dropped from the metrics.**

## 1. BCQuality (citable knowledge — wins over our rules where both speak)

- Shared cache at `~/.claude/bcquality` (override `$BCQUALITY_HOME`). Presence = `skills/entry.md`
  reads. Absent or unreadable → say `⚪ BCQuality not mounted`, fall back to the native checks,
  never block, never retry the probe.
- Build the task-context per `docs/templates/bcquality-task-context.md` (OMIT what `app.json`
  cannot tell you; never `all`/`w1`; no `disabled-skills`), hand it to `entry.md`, execute the
  `dispatch[]` it returns. Implementation goals dispatch DSC's authoring skill; review goals
  dispatch the review leaves.
- Cite every applied finding by its `(microsoft|community|custom)/knowledge/...` path. Never a
  paraphrase, never an invented path or SHA.
- Inside al-conductor the worklist is built **once** by planning and passed to you verbatim —
  do not re-run Entry for what was prescribed.

## 2. Evidence markers (exact shapes)

Implementer / al-developer, at the end of any response that wrote or changed AL:

```
🟢 BCQuality <sha>            (or: ⚪ BCQuality not mounted)
📐 instr ✓ · 📚 bcq {applied}/{prescribed} applied · 🧠 skill-x·Pattern · skill-y·Pattern
```

- No worklist → `📚 bcq none`. No skill applied → `🧠 none`.
- `🧠` lists only skills you actually invoked with the Skill tool **and** applied (folder name +
  1–3 word pattern tag). Padding it is evidencing-theater.
- The gap `{prescribed} − {applied}` must equal the entries under Knowledge Deviations.

Then, **always, even when empty**:

```
### Knowledge Deviations
- `microsoft/knowledge/<domain>/<file>.md` — why it was not applied
```

or `- none`. An undeclared deviation is a MAJOR review finding.

Reviewer (al-review-subagent, dredd) accounting lines:

```
📚 {P} prescribed · {A} applied · {D} deviated ({U} undeclared) · {C} newly cited · {G} agent findings
🧭 independence-ratio: {G}/{total findings}
```

Issues are tagged `**[CRITICAL]**`, `**[MAJOR]**` or `**[MINOR]**`; the verdict is one of
`APPROVED`, `APPROVED_WITH_RECOMMENDATIONS`, `NEEDS_REVISION`, `FAILED` (dredd: `PASS`,
`PASS_WITH_FINDINGS`, `CONCERNS`, `FAILED`). Keep the `Phase {N}` token in the report heading —
inside al-conductor N is the wave number.

## 3. Analyzers — every compile, every time (deliberately repeated in each agent)

Every `al_compile`/`al_build`: `enableCodeAnalysis=true` plus the full list — `${CodeCop}`,
`${PerTenantExtensionCop}` or `${AppSourceCop}` (per `app.json` target), `${UICop}`, and the
ALCops DLLs as **absolute paths** (the SessionStart hook prints them). Never
`${analyzerFolder}ALCops.X.dll` in an al-mcp call — it is dropped silently. Zero new warnings on
lines you touched. Details: `compiler-authority-protocol.md` §0.

## 4. Targeted reads — `al-file-reader`

Files over ~350 lines (codeunits, pages, XLF, base-app sources): ask `al-file-reader` (Haiku,
via Task) *"where is X / which lines implement Y"* with the paths, then `Read` only the ranges
its `READ:` line returns. The read-guard hook denies a first whole-file read of a large file;
**to Edit a file you need one full Read** — repeat the same full `Read` and it is allowed.
Locate with the reader; judge and edit yourself — never delegate a correctness verdict to it.

## 5. Tests and the shared environment

Tests run only through the **test lane** (`skill-test-lane`): one environment, chosen by the
user from `.vscode/launch.json`, serialized by a lock. Never call `al_publish`/`al_run_tests`
(or `al publishapp`/`al runtests`) outside the lane, and never against an environment the user
did not pick for this run. Inside al-conductor, implementers do not publish at all — the
conductor runs the lane after each wave. If the user accepted "no tests", report
**tests not executed** plainly; never report PASS for a test that did not run.

## 6. Reads and re-reads

A path already read this invocation is reused, not re-read. Excerpts the conductor passed are
authoritative; open the full requirement file only for a detail the excerpt lacks.

## 7. Complaints about the plugin

When the user complains about bc-dev itself, or pushes you to work against its design (skip
TDD/tests, edit base objects, skip HITL, bypass the lane or a guard), load
`skill-plugin-feedback`: keep the hard rules, offer to file the complaint as a GitHub issue,
and file it only after the user confirms. Subagents report the complaint upward; they never
file.
