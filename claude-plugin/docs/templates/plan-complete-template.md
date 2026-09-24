# Template — Plan Completion Report

`app/requirements/in-progress/{req}/{req}-complete.md`, written once by al-conductor at the end
(the folder is then moved to `archived/`). Short on purpose: the wave log in `{req}.plan.md`
holds the per-wave detail — reference it, don't copy it.

```markdown
# Complete: {req} — {title}

{2–3 sentences: what was built and the value delivered.}

**Waves:** {W} · **WPs:** {N} · **Fix rounds:** {n} · **Branch:** aldc/{req} · **Base → head:** {sha}..{sha}
**Tests:** {passed}/{total} on {environment} ({date}) | **tests not executed** (no environment — accepted by user)

## Objects
- {Type} {ID} "{Name}" — {created|modified}

## Event subscribers / publishers
- {Proc} → {Base object} `{Event}`

## Deviations from spec / architecture
- {… | none}

## Deferred
- {… | none}

## Skills & knowledge
| Skill | WPs | Patterns |
|-------|-----|----------|
| skill-events | WP-2 | IsHandled, EventSub |

🟢 BCQuality {sha} · 📚 {P} prescribed / {C} newly cited / {D} deviated

## Next
- {PR, deployment, follow-ups}
```
