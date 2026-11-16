---
description: >
  Capture and review the tutorial screenshots of the current Business Central app's functional
  guide (guides/functional/<language>/) from its Page Scripting recordings, with bc-tutorial-kit.
  Use when a recording arrives after the al-conductor plan closed, when the final gate said
  "waiting for recording" or "sign-in needed", after a Global app's release on the product
  sandbox, or when asked to "aggiornare gli screenshot del tutorial".
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Skill
argument-hint: "[page.md | capture-id] [language]"
---

# Capture tutorial screenshots

**Inputs**: parse from `$ARGUMENTS`: optional `{Target}` (a page in
`guides/functional/<language>/`, e.g. `code-processo.md`, or one marker id such as
`code-processo-03`; default: every marker without an image) and optional `{Language}` (default
`it-IT`). Do not ask for an optional input.

Load **`bc-dev:skill-functional-docfx`** and follow its **Phase 7** only: this command captures
and reviews, it does not rewrite the pages. Speak Italian to the developer.

1. `validate guides/functional --lang {Language} --json`. Errors in the markers you are about to
   capture (wrong `after`, unknown caption) → fix the marker first; anything else → report it,
   don't fix it here.
2. List the markers to capture with their recording. A recording still missing → say who it was
   assigned to (the plan or spec's Documentation section) and skip that marker.
3. Check `guides/functional/capture.json` (Global → product sandbox; PTE → test environment).
   Shared test environment → take the test-lane lock (`bc-dev:skill-test-lane`). Ask the
   developer to confirm the published version, and warn before a sign-in window opens.
4. `capture`, in the background; release the lock afterwards, always.
5. 🔒 Review: show every pending screenshot (absolute paths) and every warning; then
   `review --approve` / `--reject` exactly as the developer answers.
6. `validate` again, then commit `guides/functional/**` (and any new `app-pagescripting/*.yml`)
   on the current branch. Never a new branch for screenshots alone.

Finish with: screenshots approved and rejected, markers still waiting (and for what), warnings
left open, and whether the change is committed.
