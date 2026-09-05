# Architecture

One product, one distribution channel.

```
                    ALDC-AL-Development-Collection  (this repo)
                                    │
                             claude-plugin/          the plugin, hand-maintained
                                    │
                ┌───────────────────┴───────────────────┐
                │                                       │
    scripts/sync-claude-workspace.js        GitHub Action in the marketplace repo
                │                                       │
             .claude/                          plugins/bc-dev/
      this repo dogfooding its own      dscgroup-bc-nav-agentic-dev, published
      plugin — GENERATED, never edit    to the Claude organisation
```

## Source of truth

| Concern | Lives in |
|---|---|
| Agents, skills, commands, hooks | `claude-plugin/` |
| Always-on AL rules | `claude-plugin/rules-templates/` — and its condensed `rules-floor-cheatsheet.md` |
| BCQuality source and version | `claude-plugin/tools/bcquality/bcquality.pin` |
| DSC BCQuality overrides | `claude-plugin/bcquality-custom/` (scaffolded, not yet populated) |
| Report and plan templates | `claude-plugin/docs/templates/` |
| Decision records | `.github/plans/`, `docs/decisions/` |

Nothing outside `claude-plugin/` ships. `.claude/` is generated; `docs/framework/` is
design background that predates the plugin-only layout.

## Flows

**Out — to users.** `bc-dev-upstream-drift.yml` in the marketplace repo copies
`claude-plugin/` over `plugins/bc-dev/` daily at 05:00 UTC and opens a PR. This repo is the
sole source of truth for that path, so overwriting is correct — and since the sync now
reconciles deletions, a file removed here is removed there too, with `RECONCILE_KEEP`
protecting anything the marketplace genuinely owns.

**In — from upstream.** `sync-upstream.yml` replays upstream commits touching
`claude-plugin/**` as patches, weekly. Path-filtered because this fork no longer carries
upstream's Copilot/VS Code chain; patches rather than an overlay because that directory is
co-owned and copying over it would clobber our work. A collision surfaces as a conflict and
stops the run.

**In — from BCQuality.** `bcquality-pin-bump.yml` checks weekly for a newer BCQuality
release and opens a PR bumping the pin, listing the knowledge files and review leaves that
changed. The knowledge itself is never vendored: the `SessionStart` hook keeps one shared
clone at `~/.claude/bcquality`.

## Rules

- Edit `claude-plugin/`; run `node scripts/sync-claude-workspace.js` after.
- Never edit `.claude/` — it is regenerated and a CI drift check fails on divergence.
- A rule lives in exactly one place. Where BCQuality has a knowledge file, defer to it.
- Version bumps are manual, in `claude-plugin/.claude-plugin/plugin.json` and the
  marketplace entry.

## What was removed, and why

Upstream builds a GitHub Copilot / VS Code product from root-level `agents/`, `skills/`,
`instructions/` and `prompts/`, mirrored into `packages/foundation/` for a VSIX and
published to npm, with an mkdocs site on GitHub Pages. This fork carried all of it while
using none of it, and the duplicate rule tree had drifted into contradicting the plugin's
on indentation, `TryFunction` scope and the test assert codeunit name.

Removed: those four trees, `packages/`, `collections/`, `archive/`, `tools/aldc-validate/`,
the packaging and validation scripts, `aldc.yaml`, `aldc.code-workspace`, `mkdocs.yml`, the
docs site, the npm manifests, and five already-disabled workflows.

Full reasoning: [`.github/plans/bcquality-proactive-integration.md`](.github/plans/bcquality-proactive-integration.md).
