---
name: skill-translate
description: "AL translation and localization for Business Central. Use when working with XLF files, NAB tools, or implementing multi-language support in extensions."
---

# Skill: AL Translation Management

## Purpose

Manage multilingual translations for AL extensions using XLF files: initialize the NAB MCP server against the app, create and refresh language files, batch-translate in a bounded self-loop, apply the Business Central glossary with a longest-match strategy, preserve every technical element (placeholders, backslash sequences, XML tags, `maxLength`), and run a state-based review workflow.

This skill mirrors the official **NAB-XLF-Translator** agent shipped with the NAB AL Tools extension (`jwikman/nab-al-tools`, `extension/assets/agents/NAB-XLF-Translator.agent.md` and its `instructions/*.instructions.md`). Where the official agent targets VS Code Copilot, this skill targets the Claude Code harness and the **nab-al-tools MCP server** wired into `.mcp.json`.

## When to Load

- A new target language needs to be added to an AL extension
- Untranslated texts need to be translated after code changes
- Translation quality review is needed (placeholder validation, character limits, `needs-review` state)
- Regional language variations must be managed (es-ES vs es-MX)
- Incremental translation is required after refreshing XLF files

## Tool Namespace

Every tool in this skill is a real MCP tool call against the **nab-al-tools** server (`.mcp.json`, package `@nabsolutions/nab-al-tools-mcp@next`) — not a VS Code command, a Copilot chat variable, or a hypothetical action. In agent prose, call them as **nab-al-tools** `toolName` (harness-qualified name `mcp__plugin_bc-dev_nab-al-tools__toolName`). All file paths are **absolute paths on disk**, not AL object names. Confirm the tool is reachable as `mcp__plugin_bc-dev_nab-al-tools__*` before relying on it; if absent, tell the user the MCP server isn't configured rather than fabricating output.

---

## Step 0 (MANDATORY): Settings precondition — disable `[NAB: *]` tags

**Do this before `initialize`, and always before any `refreshXlf`.**

By default NAB AL Tools writes review markers as **`[NAB: *]` tokens inside the target element** — `[NAB: NOT TRANSLATED]`, `[NAB: SUGGESTION]`, `[NAB: REVIEW]`. The entire MCP state-based workflow used by this skill (`targetState`, `getTranslatedTextsByState`, `getTextsToTranslate`) depends on **XLIFF target-state attributes** instead. If the tokens are left enabled, `refreshXlf` pollutes the target text with `[NAB: ...]` strings and the state filters stop working correctly.

**Required setting:**

| Key | Type | Default | Set to |
|---|---|---|---|
| `NAB.UseTargetStates` | boolean | `false` | **`true`** |

> `NAB.UseExternalTranslationTool` is the deprecated old name for the same setting — if a project still has it, migrate it to `NAB.UseTargetStates`.

**Recommended companions** (defaults are already correct — just verify):

| Key | Default | Notes |
|---|---|---|
| `NAB.ReplaceSelfClosingXlfTags` | `true` | keep `true` — normalizes `<tag/>` → `</tag>` |
| `NAB.DetectInvalidTargets` | `true` | keep `true` — catches placeholder mismatches on refresh |
| `NAB.ClearTargetWhenSourceHasChanged` | `false` | only has any effect when `NAB.UseTargetStates` is `true`; enable if you want changed sources re-flagged |
| `NAB.SetExactMatchToState` | (unset) | optional; with target states on, sets the state applied to exact matches during refresh |

### Where the setting lives — extension vs. MCP

The setting **key and file are the same** for both (`NAB.*` in a settings JSON) — what differs is **how the server discovers it**.

- **VS Code extension:** reads the live workspace configuration — `.vscode/settings.json` and the `settings` object of the open `.code-workspace`. Nothing extra to do beyond setting the key.
- **nab-al-tools MCP server (this skill):** has no live VS Code. It loads settings only when `initialize` is given a `workspaceFilePath`, via NAB's `CliSettingsLoader`, which reads (lowest→highest precedence): built-in defaults → the `.code-workspace` `settings` object → `.vscode/settings.json` (folder-level, wins). **If `initialize` is called without `workspaceFilePath`, only built-in defaults apply → `NAB.UseTargetStates` is `false` → `[NAB: *]` tokens get injected on the next `refreshXlf`.**

**Therefore, for the MCP path you must do BOTH:**

1. Ensure `NAB.UseTargetStates: true` is written to one of:
   - `.vscode/settings.json` in the app folder (folder-level, highest precedence), **or**
   - the `"settings": { }` object inside the repo's `*.code-workspace` file.

   ```jsonc
   // .vscode/settings.json
   {
     "NAB.UseTargetStates": true,
     "NAB.ReplaceSelfClosingXlfTags": true,
     "NAB.DetectInvalidTargets": true
   }
   ```

2. Pass that `.code-workspace` path as `workspaceFilePath` to **nab-al-tools** `initialize` (see Step 1) so the server actually loads it.

If neither a `.vscode/settings.json` nor a `.code-workspace` exists, create the `.vscode/settings.json` (HITL: tell the user you're adding it and why), and still pass a `workspaceFilePath` that includes the app folder.

**Verify** after the first `refreshXlf`: open the language `.xlf` and confirm new untranslated units carry `state="needs-translation"` (or similar) and **no `[NAB:` substring appears in any `<target>`**. If you see `[NAB: NOT TRANSLATED]`, the setting did not load — fix it and re-refresh.

---

## Workflow

The official agent runs exactly **one** workflow per request — **Translation**, **Review**, or **Glossary Management**. Declare which one is active before starting, and if the user switches, re-establish context from Step 1.

### Step 1: Initialize the server (once per session)

`initialize` **must be called before any other nab-al-tools tool.** It locates the generated `.g.xlf`, loads `app.json`, and loads settings.

```
nab-al-tools: initialize
  appFolderPath: "D:/repos/MyApp/app"          // absolute path to the folder containing app.json
  workspaceFilePath: "D:/repos/MyApp/MyApp.code-workspace"   // MANDATORY when the app is in a workspace — carries NAB.* settings
```

Locating `workspaceFilePath`: look for `*.code-workspace` in the app folder, its parents, and the git repo root; verify the app folder is actually one of the workspace's `folders`.

**Prerequisite:** the `.g.xlf` must exist and be current. Regenerate it first with `Bash: al compile` (the AL compiler writes `Translations/<App>.g.xlf` when `"features": ["TranslationFile"]` is set in `app.json`). Never edit `.g.xlf` by hand.

### Step 2: App discovery (if the app is ambiguous)

Before translating, be sure which app you're translating:

- If the current context is inside an AL app (an `app.json` at the folder root), use that app's `Translations/` folder.
- Otherwise, search the workspace folders for every `app.json`, keep only those with `"TranslationFile"` in the `features` array, and present the qualifying apps for the user to choose.
- `al compile` / `initialize` operate on **one** app — the correct app context is essential.

### Step 3: Create or refresh language files

**New language:**

```
nab-al-tools: createLanguageXlf
  targetLanguageCode: "sv-SE"
  matchBaseAppTranslation: true    // pre-populate from Microsoft base app translations (needs internet)
```

One file per locale: `MyApp.sv-SE.xlf`, `MyApp.da-DK.xlf`, … Never copy an existing `.xlf` to make a new language — always `createLanguageXlf`.

**Existing languages — refresh before translating** (and again at the very end):

```
nab-al-tools: refreshXlf
  filePath: "D:/repos/MyApp/app/Translations/MyApp.sv-SE.xlf"
```

`refreshXlf` syncs the target file with the current `.g.xlf`: adds new units, preserves existing translations and their states, sorts to match `.g.xlf`. Its result reports the untranslated count and review status — read that instead of a separate `getTextsToTranslate` call for scoping. Repeat per language `.xlf`.

> Re-confirm Step 0: if `NAB.UseTargetStates` is not loaded, this call injects `[NAB: *]` tokens.

### Step 4: Mandatory context loading (once per language, before translating)

Load these and **retain both for the whole session — do not re-fetch each batch:**

1. **Target language** — extract from the filename: `<basename>.<lang>.xlf` → e.g. `MyApp.da-DK.xlf` → `da-DK`.
2. **Local glossary** — check for `Translations/glossary.tsv` (TSV: first column `en-US`, optional last column `Description`, language codes in between; first line is ISO-code headers). Local terms override the built-in glossary.
3. **Glossary terms:**

   ```
   nab-al-tools: getGlossaryTerms
     targetLanguageCode: "da-DK"
     sourceLanguageCode: "en-US"                       // optional, default en-US
     localGlossaryPath: "D:/repos/MyApp/app/Translations/glossary.tsv"   // optional
   ```

   `getGlossaryTerms` covers only built-in glossary locales (enum): `en-US`, `en-GB`, `en-AU`, `en-CA`, `en-NZ`, `cs-CZ`, `da-DK`, `de-DE`, `de-AT`, `de-CH`, `es-ES_tradnl`, `es-MX`, `fi-FI`, `fr-FR`, `fr-BE`, `fr-CA`, `fr-CH`, `is-IS`, `it-IT`, `it-CH`, `nb-NO`, `nl-NL`, `nl-BE`, `sv-SE`. Note **`es-ES_tradnl`**, not `es-ES`. For any other locale, rely on the translated-texts map plus a local glossary.

4. **Translation memory (existing translations):**

   ```
   nab-al-tools: getTranslatedTextsMap
     filePath: "D:/repos/MyApp/app/Translations/MyApp.da-DK.xlf"
     offset: 0
     limit: 0            // 0 = all; groups source → [targetTexts]
   ```

   Returns each `sourceText` with the array of `targetTexts` already used for it — the reference for staying consistent when a term was translated differently in different contexts.

### Step 5: Translate — bounded self-loop

Translate in a continuous loop, **no pauses or permission requests between batches** once the user has confirmed scope:

```
iteration = 0
LOOP:
  1. nab-al-tools: getTextsToTranslate   filePath: "<lang.xlf>"   offset: 0   limit: 100
  2. IF returnedCount == 0  → EXIT (language complete)
  3. Translate every returned text (see rules below)
  4. Validate every translation against the pre-save checklist
  5. nab-al-tools: saveTranslatedTexts   filePath: "<lang.xlf>"   translations: [ {id, targetText, targetState: "translated"}, ... ]
  6. iteration += 1
  7. IF iteration >= 4  → EXIT with warning (report moreTextsRemain: true)
  8. GOTO 1
```

- **Batch size: `limit: 100`.** One `saveTranslatedTexts` call per fetch — translate the whole batch, save once; never split a fetched batch into sub-saves.
- **`offset: 0` always.** After a save the untranslated set changes, so re-fetch from the start — this guarantees no skips.
- **Max 4 iterations** (~400 texts). If still incomplete, stop and return a summary; the caller re-invokes for the remainder (each re-invocation re-loads glossary + map).
- **Progress log** per batch: `Batch N: saved X translations, Y remain, continuing…`
- `targetState: "translated"` for normal machine/agent translations. Use `needs-review-translation` only for items you genuinely can't resolve (e.g. `maxLength` impossible) and want a human to see.

Each `getTextsToTranslate` entry gives you: `id`, `source`, `sourceLanguage`, `context` (e.g. `Table Customer - Field Name - Property Caption`), `maxLength` (if set in AL), and `comments` (placeholder notes). Use `context` to disambiguate meaning.

### Step 6: Review workflow (state-based)

```
// Count / fetch items awaiting review
nab-al-tools: getTranslatedTextsByState
  filePath: "<lang.xlf>"
  offset: 0
  limit: 0
  translationStateFilter: "needs-review"        // enum: needs-review | translated | final | signed-off
```

> Asymmetry to remember: the **filter** value is `needs-review`, but the **`targetState`** you write back via `saveTranslatedTexts` is `needs-review-translation` (enum: `needs-review-translation | translated | final | signed-off`).

- Items in a review state **must be shown to the user for approval** — never silently promote them to `translated`.
- `getTranslatedTextsByState` returns `alternativeTranslations` when multiple targets exist — these are the suggestions behind `[NAB: SUGGESTION]`.
- After review, write back with `saveTranslatedTexts` and the appropriate `targetState`: accepted/edited → `translated`; leave finalized items at `final` / `signed-off`; still unsure → `needs-review-translation`.
- Batch review in small groups (≈10, up to 100).

Use `getTextsByKeyword` to check how a term is used or already translated across the app:

```
nab-al-tools: getTextsByKeyword
  filePath: "<lang.xlf>"
  offset: 0
  limit: 0
  keyword: "Customer|Vendor|Invoice"
  isRegex: true
  caseSensitive: false
  searchInTarget: true      // false = search source (includes untranslated); true = search target only
```

### Glossary Management workflow

A separate workflow (declare it as the active one) for building, reviewing, and extending the project `glossary.tsv`. The glossary is the single source of terminology truth that the Translation workflow consumes via `getGlossaryTerms` + `localGlossaryPath`.

**File format** — `glossary.tsv`, tab-separated, UTF-8:

| Column 1 | Columns 2…N | Final column |
|---|---|---|
| `en-US` — source terms, **unique, case-sensitive** | one per target locale (`da-DK`, `sv-SE`, `de-DE`, …), alphabetical by code recommended; empty cells allowed | `Description` — optional but recommended, ≥20 chars, form `[Purpose]. [Differentiation].` (≈50–150 chars) |

- First line is the header row of ISO codes; `en-US` first, `Description` last if present.
- Delimiter is **tab only** — no tabs inside any cell, no stray HTML/XML.
- Location: `Translations/glossary.tsv` in the app (or the repo's shared `resources/glossary.tsv`). Confirm the location with the user.

```
en-US	da-DK	sv-SE	Description
Bank Account	Bankkonto	Bankkonto	Master record in Cash Management. Not the G/L account.
Posting Date	Bogføringsdato	Bokföringsdatum	Date the entry affects the ledgers.
```

**Create:**
1. Ask the user for the target locales (default `en-US` + at least one target). Check for XLF files; offer `createLanguageXlf` if none exist.
2. Confirm the file location.
3. Build the header: `en-US` → locale columns (alphabetical) → `Description`.
4. Seed 20–50 core terms via extraction (below) or built-in BC vocabulary.
5. Validate before saving (see checks below).

**Term extraction / scoring** — pull candidates from the XLF, not free-association:
1. `refreshXlf`, then `getTranslatedTextsMap` (`offset: 0`, `limit: 0`) and/or `getTranslatedTextsByState` for existing targets.
2. Rank candidates:
   - **High** — technical terms, AL object names, multi-word phrases (2–4 words)
   - **Medium** — terms occurring 3+ times, capitalized domain vocabulary (finance, inventory, manufacturing)
   - **Exclude** — generic UI words (`OK`, `Cancel`), strings <3 chars, sentences >100 chars, placeholders, date/number format strings
3. Review the top ≈50–100 with the user interactively — show term, frequency, the object/property contexts it appears in, grouped by category; accept/decline per term.
4. Write a `Description` for each accepted term.

**Add a language to an existing glossary:**
1. Parse and structurally validate the current file.
2. Get the new `xx-XX` code from the user; verify format and that it isn't already a column.
3. Insert the new column after `en-US`, before `Description` (alphabetical preferred); add empty cells to every data row; keep every existing cell unchanged.
4. Optionally populate from XLF extraction.
5. Validate: equal column count on every row, existing data untouched, UTF-8 preserved.

**Review an existing glossary** — report coverage % (filled target cells), empty-cell count, a consistency score, and description completeness. Checks:
- *Structural:* one tab delimiter between columns, consistent column count, valid header, valid locale codes, UTF-8.
- *Data quality:* no duplicate or empty `en-US` terms, translation completeness, description length/quality.
- *Terminology:* capitalization consistent within a locale, sane term length, alignment with Microsoft BC standard terms (cross-check with `getGlossaryTerms` for the built-in set and `getTextsByKeyword` for how the term is actually translated in the app).
- Offer automatic fixes for structural issues; offer suggestions (not silent edits) for data-quality issues.

**Pre-translation validation** — before the Translation workflow relies on the glossary: file exists / readable / UTF-8 / tab-separated; header valid (`en-US` first, `Description` last, no duplicate/invalid codes); rows have consistent column count, no duplicate/empty `en-US`, descriptions ≥20 chars where the column exists; no tabs or unintended markup in cells. Result is **PASS** (ready), **WARNING** (use but address), or **FAIL** (blocks use).

**Loading precedence at translation time:** local `glossary.tsv` first, then the NAB built-in glossary — local entries win on duplicate `en-US`. Application is exact-match, longest-phrase-first, term-boundary-aware (no partial-word hits), case-sensitive preferred with case-insensitive fallback.

> The glossary tools do **not** re-write existing XLF targets. Enforcing a corrected term across already-translated units is a Review-workflow action: find them with `getTextsByKeyword` (`searchInTarget: true`), then `saveTranslatedTexts` the fixes with the right `targetState`.

### Step 7: Finalize

1. `refreshXlf` once more per language.
2. Confirm `getTextsToTranslate` (`limit: 0`) returns nothing.
3. Collect the review status from each `refreshXlf` result; if any items need review, offer the Review workflow.
4. `Bash: al compile` to verify the `.xlf` still integrates.
5. Test the UI in the target language.

---

## Translation Rules

### Style (Business Central conventions)

- **Formal, neutral, professional** — no colloquialisms. Audience: business users, accountants, administrators.
- **Localize, don't transliterate** — adapt to the target market's business practice and UI conventions; the result should read as if originally written in the target language.
- **Consistency** — the same term is translated identically everywhere (use the glossary and the translated-texts map).
- **Brevity** for UI elements.
- Match **Microsoft's official base-app terminology** for standard BC terms.

### Glossary — longest-match strategy

- Sort glossary entries by source length **descending**; apply the longest matching phrase first when terms overlap.
- Match case exactly; use the glossary target **verbatim**.
- When the glossary offers multiple targets, pick by `context`.
- Local glossary entries always beat built-in ones.

### Technical preservation (from `xlf-translation-technical-rules`)

| Element | Rule |
|---|---|
| **Placeholders** `%1 %2 %3` | keep every one, unchanged; keep order unless target grammar strictly requires reordering |
| **Backslash sequences** `\` `\\` | preserve exact count and position; **never** turn `\\` into a real line break; don't add/remove backslashes |
| **XML / inline tags** `<g id="1">…</g>` | keep markup byte-identical; translate only the text between tags |
| **`maxLength`** | count characters in the target **as you write it** — never estimate; if it doesn't fit, shorten and recount; if genuinely impossible, flag `needs-review-translation` and tell the user |
| **Punctuation & whitespace** | preserve leading/trailing spaces, non-breaking spaces, `! ? : ; .`, dashes `— – …`, quotes, symbols `© ® ™ € $` |
| **Capitalization** | follow target-language convention but keep source intent (ALL CAPS stays emphatic) |
| **Progress placeholders** `#1#####…` | keep the exact hash pattern |
| **Unicode** | keep characters exactly |

### JSON backslash escaping

Tool I/O is JSON, so backslashes are doubled. `\\` in tool output = **one** real backslash in the XLF. When you pass `targetText` to `saveTranslatedTexts`, a source with two real backslashes (`Line1\\Line2`) must be sent as four (`Line1\\\\Line2`) so JSON parsing yields two. Decode the JSON layer first; never count backslashes in raw tool output.

### Pre-save checklist (run on every translation before `saveTranslatedTexts`)

1. Backslash sequences preserved exactly (count + position)
2. All `%1`, `%2`, … present and unchanged
3. XML/inline tags identical to source
4. Within `maxLength` — character count explicitly verified
5. Punctuation / whitespace intact
6. `targetText` ≠ `sourceText` unless that's a deliberate choice (proper noun, universal abbreviation) — if unsure, ask the user

---

## Regional Variations (es-ES vs es-MX)

```
1. createLanguageXlf  targetLanguageCode: "es-ES"   matchBaseAppTranslation: true
2. createLanguageXlf  targetLanguageCode: "es-MX"   matchBaseAppTranslation: true
3. getTranslatedTextsMap  filePath: "…/MyApp.es-ES.xlf"  offset: 0  limit: 0   // base as reference
4. Translate es-MX, adjusting only regional terms ("ordenador" → "computadora"); shared terms ("factura") stay.
```

---

## Common Language Codes

| Code | Language | Code | Language |
|---|---|---|---|
| `es-ES` | Spanish (Spain) | `fr-FR` | French (France) |
| `es-MX` | Spanish (Mexico) | `fr-CA` | French (Canada) |
| `de-DE` | German | `pt-BR` | Portuguese (Brazil) |
| `it-IT` | Italian | `nl-NL` | Dutch |
| `da-DK` | Danish | `sv-SE` | Swedish |
| `nb-NO` | Norwegian | `fi-FI` | Finnish |
| `pl-PL` | Polish | `cs-CZ` | Czech |
| `ja-JP` | Japanese | `zh-CN` | Chinese (Simplified) |

> The **glossary** enum uses `es-ES_tradnl` (not `es-ES`); XLF **file** locale codes use `es-ES`.

---

## Constraints

- This skill covers **XLF translation management, batch translation, and state-based quality review** via the **nab-al-tools** MCP server.
- Always call `initialize` first; always pass `workspaceFilePath` when a workspace file exists.
- **`NAB.UseTargetStates: true` must be loaded before any `refreshXlf`** — otherwise `[NAB: *]` tokens are written into targets.
- Do **not** edit `.g.xlf` or `.xlf` files by hand, and do **not** copy an `.xlf` to create a new language — use `createLanguageXlf` / `refreshXlf` / `saveTranslatedTexts` only.
- Do **not** remove or reorder placeholders (`%1`, `%2`) or alter backslash / tag / whitespace structure.
- Do **not** exceed `maxLength`.
- Do **not** translate without loading glossary + translated-texts map first (consistency).
- **Forbidden anti-patterns:** Python/Node automation scripts over XLF, external TMS tools (Crowdin, Lokalise), generic file read/write or string replacement on `.xlf`, bulk translation outside NAB AL Tools.
- Translation testing in the UI → `skill-testing` | Page captions and tooltips → `skill-pages`

## References

- [NAB-XLF-Translator agent + instruction files](https://github.com/jwikman/nab-al-tools/tree/main/extension/assets) — the official source this skill mirrors (`agents/NAB-XLF-Translator.agent.md`, `instructions/xlf-translation-technical-rules.instructions.md`, `instructions/translation-workflow.instructions.md`, `instructions/review-translation-workflow.instructions.md`, `instructions/glossary-management.instructions.md`)
- [NAB AL Tools MCP Server](https://github.com/jwikman/nab-al-tools/blob/main/extension/MCP_SERVER.md) — the tool provider wired into `.mcp.json` as `nab-al-tools` (`npx -y @nabsolutions/nab-al-tools-mcp@next`)
- [NAB AL Tools settings reference](https://github.com/jwikman/nab-al-tools#settings) — `NAB.UseTargetStates` and companions
- [Working with Translation Files](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-work-with-translation-files)
- [MaxLength Property](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/properties/devenv-maxlength-property)
- [XLIFF 1.2 Standard](http://docs.oasis-open.org/xliff/v1.2/os/xliff-core.html)
