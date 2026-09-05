---
name: skill-changelog
description: "AL changelog management for Business Central extensions. Use when creating or updating a versioned changelog.json for an AL app, writing release notes after a version bump, or preparing changelog entries for /aldc:al-pr-prepare."
---

# Skill: AL Changelog Management

## Purpose

Maintain a structured, versioned JSON changelog for an AL/Business Central extension: one entry per published version, each describing what changed and why, in a format that can drive an in-app "what's new" page, a release-notes site, or a customer-facing deliverable. This skill defines the JSON schema, the writing conventions, and the workflow for adding a new entry without corrupting existing history. All version numbers, object names, and tickets below are illustrative placeholders, not references to any real app or customer.

## When to Load

- After `/aldc:al-build` bumps the extension's version, before the build is published
- During `/aldc:al-pr-prepare`, to draft the release-notes section of the PR
- When `al-conductor` finishes a plan and needs to log the change for the version it produced
- On explicit user request: "aggiorna il changelog", "genera una voce di changelog", "cosa è cambiato nella versione X"
- When auditing/cleaning up an existing changelog file for consistency

## Locating the File

There is no fixed path — do not assume one. Look for an existing changelog file at the app root (same directory as `app.json`), typically named `ChangeLog.json` or `changelog.json`, using `Glob`. If none exists, ask the user for the intended filename/location before creating one. Never guess a path that hasn't been confirmed by the file system or the user.

## Schema

The file is a single JSON array, **ordered newest-first**. New entries are unshifted to the front, never appended at the end.

```json
{
  "version": "1.4.2.7",
  "title": "One-line synthesis of the release theme",
  "date": "2026-07-22T00:00:00.000Z",
  "details": [
    {
      "id": 1,
      "title": "Short heading for this specific change",
      "detail": "Long technical explanation of this change (optional)."
    }
  ]
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `version` | string | yes | `Major.Minor.Build.Revision`, must equal `app.json`'s `"version"` for that release |
| `title` | string | yes | Synthesizes the release as a whole — not a concatenation of detail titles |
| `date` | string | yes | ISO 8601 UTC datetime |
| `details` | array | no | Omit entirely for trivial releases — see Casistica C |
| `details[].id` | integer | yes (if `details` present) | Sequential starting at 1, scoped to this version entry only — never global |
| `details[].title` | string | yes (if `details` present) | Short heading for one change |
| `details[].detail` | string | no | Omit for placeholder-only entries — see Casistica D |

## Casistiche

The four shapes below are illustrated with fictitious version numbers, object names, and tickets (any resemblance to a real app is coincidental) — treat them as patterns to recognize and reproduce, not as data to look up.

### Casistica A — Full detailed release (multi-change)

Used for releases with real functional/technical impact. The top-level `title` synthesizes an overarching theme across N related changes; it is written after understanding the whole release, not derived mechanically. Each `details[]` item documents exactly one change, following the writing conventions below.

Example (illustrative): version `1.4.2.7`, title "Performance keys for aggregated FlowFields on the Sales API", with several `details[]` entries, each adding a SIFT key/SumIndexFields to a different table, unified under that one theme.

### Casistica B — Single simple change, `title` ≈ `detail`

One change only. The version's top-level `title`, the single `details[0].title`, and (when present) `details[0].detail` are near-duplicates of the same short, commit-message-style sentence. Used for small, atomic changes that don't warrant a longer narrative but are still worth logging as a discrete entry.

Example (illustrative): version `1.4.0.3`, title/detail-title/detail-text all reading "Adjust holiday accrual rounding".

### Casistica C — Minimal stub, no `details` array

Only `version`, `title`, `date` — the `details` key is absent entirely (not an empty array). Used for trivial or administrative releases (a cosmetic tweak, a process change) where a breakdown adds no value.

Example (illustrative): version `1.3.9.1`, title "Adjust report layout margins", no `details` key.

### Casistica D — `details[].title` present, `detail` omitted

A ticket/commit reference logged as a placeholder heading with no narrative — typically because the underlying work is tracked in an external system and re-describing it would just duplicate that system.

Example (illustrative): version `1.4.2.2`, a single detail titled "Ticket 10088" with no `detail` field — a build referencing an external ticket without additional text.

**Choosing a casistica**: default to A when the change has real technical substance and the user/agent can explain the "why"; use B for a single atomic change not worth elaborating; use C only when there truly is nothing to add beyond the title; use D when the authoritative description already lives in an external tracker (ticket system) and the changelog entry is only a pointer.

## Writing Conventions for `detail` Prose (Casistica A)

Follow these when authoring new detailed entries (object/field names below are illustrative placeholders):

1. **Language**: match whatever language the existing changelog already uses (Italian, English, or otherwise), technical register. Keep terminology consistent with prior entries in that file.
2. **AL object references**: cite kind + numeric ID + name, name in single quotes — e.g. `table 50100 'Contoso Sales Line'`, `page 50213 'Contoso Task FactBox'`, `codeunit 50200 'Contoso Sales Mgt.'`, `report 50233 'Contoso Update Prices'`.
3. **Field / procedure / action names**: always in single quotes — e.g. `'Item No.'`, `'GetNetUnitPrice'`, `'Suggest Lines'`.
4. **Explain the why, not just the what**: state the prior (buggy, missing, or naive) behavior versus the new one, and the concrete consequence avoided or enabled — e.g. "avoids a full table scan when...", "previously X, now Y".
5. **Cross-reference prior work** when extending or correcting an earlier fix, by version number — e.g. "extends to all validations the fix already applied in v1.3.0.12".
6. **Mention originating tickets inline** when the change comes from one (support-desk ticket numbers, work-item codes such as a Jira-style key).
7. **Fold related file changes into the same detail** (e.g. translation file updates, permission set updates) rather than spawning a separate entry — unless that ancillary work is substantial enough to stand on its own as its own `details[]` entry.
8. **Keep each `detail` self-contained** — a reader must understand the change without cross-referencing another entry, except for the deliberate cross-references in point 5.

## Versioning Convention

- Format: `Major.Minor.Build.Revision`, must mirror `app.json`'s `version` for the same release.
- **Revision** (4th segment) increments for every changelog-worthy build.
- **Build** (3rd segment) increments for a milestone or batch of related work (a new capability, a larger initiative); when it does, **Revision resets to 0**.
- **Major/Minor** stay stable through normal work; bump only on an explicit user/architect decision (e.g. a breaking change or a planned major release).
- Never decrement, skip, or reuse a version number. Before writing a new entry: read the current `app.json` `version` and the changelog's first (newest) entry, compute the next value per the rules above, and bump `app.json` to match — the two must never diverge.

## `date` Convention

- A full-precision ISO datetime (e.g. `2026-06-19T13:05:40.697Z`) indicates the entry was generated automatically at commit/publish time.
- Midnight UTC (`...T00:00:00.000Z`) indicates a manually curated or back-filled entry, typically written once the whole release is understood (usually Casistica A).
- When authoring a new entry, use the actual current commit/publish moment if it is known (e.g. from `git log`); otherwise ask the user for the intended release date. Do not fabricate a timestamp — an invented date silently corrupts the release history.

## Workflow — Adding a New Entry

1. **Locate** the changelog file (see above); read it and confirm it parses as a JSON array.
2. **Determine the version**: read `app.json`, read the changelog's first entry, and apply the versioning convention to compute the next version. Confirm the choice with the user if it's ambiguous (e.g. unclear whether this is a Build-level milestone or a plain Revision bump).
3. **Gather the change set**: use `git log`/`git diff` since the last version bump (or the plan/spec just completed) to enumerate what actually changed. Do not describe code that wasn't touched.
4. **Pick the casistica** (A/B/C/D) per the guidance above, matching the change's real significance — don't inflate a one-line fix into a Casistica A narrative, and don't collapse a multi-part release into Casistica C.
5. **Draft the entry**: top-level `title` first (synthesizing the theme), then each `details[]` item with sequential `id` starting at 1, following the writing conventions.
6. **Confirm with the user** (HITL) before writing: show the drafted entry (version, title, date, details) and the computed `app.json` version bump. This mutates a persisted history file — get an explicit go-ahead rather than writing silently.
7. **Write**: unshift the new entry at the front of the array (never append at the end, never reorder or edit prior entries except to fix a factual typo the user points out), update `app.json`'s `version` to match, and save both.

## Constraints

- Do NOT append new entries anywhere but the front of the array — the file is newest-first.
- Do NOT invent object IDs, field names, or ticket numbers — every reference in a `detail` must correspond to something actually found in the diff, the codebase, or a ticket the user gave you.
- Do NOT fabricate a `date` — use a known commit/publish timestamp or ask the user.
- Do NOT let the changelog `version` and `app.json`'s `version` diverge.
- Do NOT rewrite or reorder historical entries as part of adding a new one.
- Do NOT skip the HITL confirmation in step 6 of the workflow — the changelog is release-facing history, not scratch output.
