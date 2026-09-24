# Template — Planning Findings

Returned by `al-planning-subagent` to the Conductor, once per run. Replace placeholders,
drop sections that do not apply (in mode `worklist` usually only the worklist remains), add
no other structure. No code blocks in findings — describe and link to files.

---

```markdown
## AL Planning Findings: {Task Name}

**Mode:** {worklist | research+worklist}

### Knowledge Worklist
🟢 BCQuality {sha} · {N} prescriptions across {M} WPs
*(or `⚪ BCQuality not mounted — no worklist`, or `📚 bcq · none` when Entry returned no-match)*

#### WP-1 — {objective}
- `microsoft/knowledge/{domain}/{file}.md` — {message, verbatim} — {confidence}
#### WP-2 — {objective}
- none

### Gap Answers
*(One entry per gap the Conductor listed.)*
- **{gap}** — {verified answer}; source: {al_symbolsearch result | file:line}

### Anchors for Implementers
- `{exact/path/File.Codeunit.al}:{start}-{end}` — {procedure/trigger} — touched by WP-{n}

### Relevant Objects & Events
- Base: {type ID "Name"} · Existing extensions: {type ID "Name" → path}
- Events confirmed: {publisher object} `{EventName}` — {used by WP-n}

### Project Layout & Conventions
- App: {path, key deps} · Test: {path, deps; Library Assert present y/n}
- Prefix {x} · IDs in use {ranges} · folders {feature-based path} · test pattern {…}

### Performance Considerations
- {table/area} — {SetLoadFields / filter-early / FlowField note}

### Implementation Options *(only when a gap leaves a real choice)*
1. **{Option A}** (Recommended) — pros / cons
2. **{Option B}** — pros / cons

### Open Questions / Uncertainties
- ❓ {Question? Option A / Option B} — {why it could not be resolved}

### Blockers
- {TOOL_BLOCKED: … | missing symbol … | none}
```

---

## Rules

- Exact file paths and real object IDs, never placeholders.
- Worklist entries are copied verbatim from the BCQuality skill output — path, message,
  confidence. Never paraphrase or merge.
- Open Questions: 0-5 entries, each `Question? Option A / Option B`.
- Do NOT draft a plan; the Conductor owns the WP graph.
