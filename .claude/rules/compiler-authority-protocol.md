---
description: "Shared compiler-authority protocol for all ALDC subagents (planning, implement, review) and the conductor. Rides along with rules-floor-cheatsheet.md and tool-failure-protocol.md in the conductor's per-phase inline injection — no new context-injection channel needed. Purpose: stop a model from writing invalid/invented AL syntax, getting a real compiler diagnostic for it, and then rationalizing around the diagnostic (blaming the compiler, deferring the feature, commenting the code out) instead of fixing the syntax. This is distinct from tool-failure-protocol.md, which disambiguates a broken tool call from a real diagnostic — this protocol governs what happens *after* a diagnostic is already correctly classified as CODE_ISSUE."
---

# Compiler-Authority Protocol

Applies whenever the AL compiler (`al compile` / `al_build` / `al_getdiagnostics`) reports a diagnostic — an `ALxxxx` code with a file:line — for code written or edited this session.

1. **The compiler is ground truth for syntax validity.** A real `ALxxxx` diagnostic is evidence the code is wrong, not a claim to litigate. Never respond to a diagnostic by asserting the syntax is correct and the compiler is mistaken, outdated, or "doesn't support" something — that framing is backwards by default.

2. **Before rewriting the same construct a second time, verify it actually exists** — don't guess again from memory:
   - Confirm the real member/property/type/event signature with **al-mcp** `al_symbolsearch` / `al_symbolrelations` against the actual base object, or
   - Check the relevant `skill-*` reference for the documented pattern, or
   - Check `microsoft-docs` / `context7` for the current AL language/API surface.
   Ground the fix in something confirmed, not a second invented variant of the first guess.

3. **One invented-then-corrected attempt per diagnostic.** If the *same* error code recurs on the same construct after a grounded fix attempt, stop guessing — this is not a "try a third syntax variant" situation. Escalate as an open question (to the Conductor, or to the user if running standalone) with what was tried and what the symbol lookup actually showed.

4. **Never silently defer, stub, or comment out code because of a compiler error.** Dropping or deferring functionality to make a build pass is a scope change, not a coding decision — it requires explicit escalation (Unplanned Finding Triage / HITL), never a private workaround. Treat any `// TODO: re-enable/add at go-live`, `// not supported by compiler`, or similarly-motivated stub as something that must be flagged, not quietly shipped.

5. **"Compiler limitation" is only a valid conclusion when backed by a citation** — a Microsoft Learn page, a linked known-issue, or an al-mcp symbol lookup that confirms the construct genuinely isn't available in the referenced BC version/dependency. It is never the default explanation for an unresolved diagnostic, and it is never a reason to defer rather than find the correct working syntax.

**For reviewers (al-review-subagent, dredd):** treat rule 4's pattern as a MAJOR finding on sight — a defer/limitation-style comment next to disabled or stubbed code must be justified with the citation from rule 5, or reverted/fixed. Don't wave it through as a stylistic TODO.
