---
description: >
  Prune and recreate the project CLAUDE.md: keep only what a fresh session needs and cannot
  derive, move decisions to app/requirements/memory.md, drop the rest, and show the result
  before writing. Use when CLAUDE.md is long, stale, contradicts the plugin, or the
  SessionStart hook suggests a refresh; also to create a first CLAUDE.md.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, AskUserQuestion
argument-hint: "[--check]"
---

# Prune and recreate CLAUDE.md

The project `CLAUDE.md` loads into **every** session and every subagent. Each line costs tokens
on every turn, and each stale line steers agents wrong. It is not a diary, a backlog or a
decision log. This command rebuilds it from what is true today.

`--check` → do steps 1–3 and report the classification only; write nothing.

## 1. Read

- `CLAUDE.md` (and `CLAUDE.local.md` if present — report it, never edit it: it is personal).
- `app.json` of every project (`find . -maxdepth 2 -name app.json`): name, publisher, idRanges,
  prefix if visible from object names, dependencies, runtime/application.
- `.github/AL-Go-Settings.json` `type` (PTE / AppSource App), `.code-workspace`, the folder
  layout (`app/`, `app-test/`, `app-performance/`, `app-demo/`).
- `app/requirements/memory.md` (the decision log), and `git log --format='%h %ad %s' --date=short -- CLAUDE.md | head -20`.

## 2. Classify every line or block of the current CLAUDE.md

| Class | What | Goes to |
|---|---|---|
| **Keep** | Project facts a fresh session cannot derive and needs: customer/product purpose in 1–3 lines, object prefix, idRanges per project, non-obvious build/symbol quirks, external systems and their contacts *by role*, test environment name, conventions this repo follows that differ from the bc-dev rules. | new CLAUDE.md |
| **Move** | Decisions with a rationale ("we chose X because Y"). | `app/requirements/memory.md`, dated, one entry each |
| **Drop: derivable** | Object lists, file trees, field lists, anything `app.json`, the code or `git log` already says. | nowhere |
| **Drop: plugin duplicate** | Restated bc-dev rules, agent routing, coding standards, AL-Go flow, TDD/HITL principles. The plugin injects these itself; a copy only drifts. | nowhere |
| **Drop: contradicts the plugin** | Notes overriding plugin behaviour — e.g. AL-Go release inputs (GoLive, directCommit, useGhTokenWorkflow: fixed in `bc-dev:skill-al-go-workflows` and enforced by a guard), "skip tests", "push without asking", branch policies (read from the repo's `branch-protection-enabled` property). | nowhere — list them to the user separately, they may reveal a plugin gap worth `bc-dev:skill-plugin-feedback` |
| **Drop: stale** | Session diaries, "current focus", TODOs, done items, paths or objects that no longer exist (check with `Glob`/`Grep`), finished requirements. | nowhere (open TODOs the user still wants → their tracker, ask) |

When a line is ambiguous, keep it and mark it for the question in step 4 — never guess-delete a
fact you cannot verify.

## 3. Draft the new file

Target: **under 80 lines**. Structure (omit empty sections):

```markdown
# {App name} — Claude Code instructions
<!-- aldc-refreshed: {YYYY-MM-DD} -->

{1–3 lines: what the app does, for whom (PTE for customer X / AppSource product Y).}

## Project facts
- Prefix: `{XXX}` · idRanges: app {a..b}, test {c..d}
- Layout: app/, app-test/ … (only if it differs from the AL-Go template)
- Dependencies worth knowing: {only non-obvious ones and why}

## Conventions that differ from bc-dev
- …

## Gotchas
- {symptom → cause → what to do}, one line each

Decisions: `app/requirements/memory.md`. Requirements: `app/requirements/`.
```

The stamp line is what the SessionStart hook reads to know when the file was last pruned —
always write it with today's date.

## 4. Confirm, then write

1. Show the user: the line count before → after, and per class a short list of what goes
   (group, max 5 items per class; "+N more" if longer). List **contradicts the plugin** items
   explicitly.
2. Ask with `AskUserQuestion` (one call): write it as shown (recommended) / show the full new
   file first / cancel. Add one question per genuinely ambiguous line (max 3).
3. On yes: append the **Move** entries to `app/requirements/memory.md` (create it with
   `# Decisions` if absent), write `CLAUDE.md`, and commit both on the current branch:
   `docs: prune CLAUDE.md`. Do not push (pushing is its own question).

## Rules for this command and for every session

- Never append session notes, progress, TODOs or decisions to `CLAUDE.md`. Decisions go to
  `app/requirements/memory.md`; requirement documents to `app/requirements/`.
- Never record plugin overrides in `CLAUDE.md` or memory. If the plugin is wrong for this
  project, that is a plugin issue (`bc-dev:skill-plugin-feedback`).
