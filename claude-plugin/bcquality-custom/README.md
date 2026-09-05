# BCQuality `/custom/` layer — DSC Group

Scaffolding for the DSC-owned BCQuality layer. **Prepared, deliberately not populated.**
Filling it is a separate, scheduled activity — see *Activation checklist* at the bottom.

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

At activation time the contents of `knowledge/` and `skills/` are overlaid onto
`$BCQUALITY_HOME/custom/` (default `~/.claude/bcquality/custom/`) by the BCQuality
precondition hook. The overlay survives the hook's `git fetch` + `checkout --detach`
because only `.gitkeep` is tracked in the upstream `custom/` tree, so untracked files
dropped there are never removed by the checkout.

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

## Activation checklist (future activity)

1. Write the first knowledge files under `knowledge/<domain>/`.
2. Wire the overlay in `claude-plugin/tools/bcquality/precondition_hook.sh` (+ `.ps1`):
   after a successful fetch/checkout, copy `$CLAUDE_PLUGIN_ROOT/bcquality-custom/knowledge`
   and `.../skills` into `$home/custom/`. Make it a strict no-op when both folders hold
   only `.gitkeep`.
3. Force an index rebuild so the new articles are discoverable — delete
   `$home/knowledge-index.json`; Entry's Preparation step regenerates it.
4. Confirm precedence: an overriding `/custom/` file must appear in the review report's
   `suppressed[]` against the `/microsoft/` file it replaces.
5. Remove from `claude-plugin/rules-templates/` every rule that has been promoted to a
   knowledge file. A rule must live in exactly one place.

See `.github/plans/bcquality-proactive-integration.md` for the reasoning behind all of
the above.
