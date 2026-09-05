# BCQuality `/custom/` layer — DSC Group

The DSC-owned BCQuality layer. **Wired and active; the knowledge folder is deliberately
still empty.**

`skills/author/al-implementation-guidance.md` is here because BCQuality ships review skills
only — an implementation goal would otherwise reach Entry and come back `no-match`. That
file is *mechanism*: it retrieves Microsoft's corpus for a different question. DSC-specific
*rules* go in `knowledge/`, and filling that is a separate, scheduled activity.

## What this is

BCQuality ([`microsoft/BCQuality`](https://github.com/microsoft/BCQuality)) is organised in
three layers with a fixed precedence:

```
/custom/     ← DSC Group        (wins)
/community/  ← BC community
/microsoft/  ← Microsoft        (loses)
```

`/custom/` is empty upstream by design — Microsoft's `Guard custom layer` workflow
auto-closes any PR that adds content there — because it is the extension point reserved
for partners. This folder is our copy of it, versioned with the plugin instead of in a
fork of BCQuality, so it ships through the normal `claude-plugin/ → plugins/bc-dev/`
marketplace sync and needs no second repository.

The contents of `knowledge/` and `skills/` are overlaid onto `$BCQUALITY_HOME/custom/`
(default `~/.claude/bcquality/custom/`) by the BCQuality precondition hook, in both the
bash and PowerShell variants. Two details make that safe:

- The overlay survives the hook's `git fetch` + `checkout --detach`, because upstream tracks
  only `.gitkeep` under `custom/` and a checkout never removes untracked files.
- It is re-applied **synchronously on every session**, not only after a fetch, so a plugin
  upgrade lands immediately instead of waiting up to 12 hours for the next refresh.

It is a strict no-op while a folder holds nothing but `.gitkeep`, so `knowledge/` staying
empty costs nothing. When the layer is non-empty the hook says so in its `SessionStart`
message, with the file count.

## Why here and not in a fork of BCQuality

| | Fork `dsc-group-srl/BCQuality` | This folder |
|---|---|---|
| Repos to maintain | 2 | 1 |
| Upstream rebase burden | every release (~monthly) | none — we never touch `/microsoft/` |
| Distribution | separate clone + pin | rides the existing plugin sync |
| Can override a Microsoft file | yes | yes (same layer precedence) |

The fork only becomes worth it if we ever need to *modify* `/microsoft/` or `/community/`
content rather than override it. We do not today.

## What belongs here

Only rules that are **DSC-specific and not derivable** from Microsoft's layer:

- object prefix / affix registry and the AppSource ID ranges we own
- our AL-Go `App/` vs `Test/` layout and feature-folder convention
- our namespace convention
- our XLIFF / translation policy
- our permission-set conventions
- negative clarifications: patterns our codebase legitimately uses that a generic
  reviewer would otherwise flag

What does **not** belong here: anything Microsoft's layer already covers. Duplicating a
Microsoft rule here recreates exactly the two-sources-of-truth problem this whole exercise
exists to remove. When our rule and Microsoft's rule disagree, the correct action is
almost always to **drop ours**, not to override.

## File contract (enforced by BCQuality CI, mirrored here)

Every knowledge file:

- YAML frontmatter with all six required fields — `bc-version`, `domain`, `keywords`,
  `technologies`, `countries`, `application-area`
- a `## Description` section (mandatory); `## Best Practice` and `## Anti Pattern`
  optional but recommended
- **under 100 lines**, ideally under 50 — one concern per file, split if two ideas
- **no fenced code blocks** — code examples go in sibling `<slug>.good.al` /
  `<slug>.bad.al` files, referenced by filename from the article
- filed under a domain subfolder: `knowledge/<domain>/<slug>.md`

Action skills follow `skills/do.md` (Source → Relevance → Worklist → Action) and declare
`kind: action-skill` in frontmatter.

Templates: [`templates/knowledge-file.template.md`](templates/knowledge-file.template.md),
[`templates/action-skill.template.md`](templates/action-skill.template.md).

> Keep templates in `templates/`, never in `knowledge/` or `skills/`. Entry's Source step
> scans `*/skills/**/*.md` and the knowledge index scans `*/knowledge/**`; a template
> parked in either would be discovered as real content.

## Filling `knowledge/` — the remaining activity

The plumbing is done; what is left is content. When that activity is scheduled:

1. Write the first knowledge files under `knowledge/<domain>/`, using
   [`templates/knowledge-file.template.md`](templates/knowledge-file.template.md).
2. Force an index rebuild so the new articles are discoverable — delete
   `$BCQUALITY_HOME/knowledge-index.json`; Entry's Preparation step regenerates it over the
   live clone, which by then includes the overlay.
3. Confirm precedence on the first override: the `/microsoft/` file it replaces must show up
   in the review report's `suppressed[]`.
4. Remove from `claude-plugin/rules-templates/` every rule promoted to a knowledge file. A
   rule lives in exactly one place — this is the step that keeps the cleanup from undoing
   itself.

See `.github/plans/bcquality-proactive-integration.md` for the reasoning behind all of
the above.
