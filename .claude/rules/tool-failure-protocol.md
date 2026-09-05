---
description: "Shared tool/MCP-failure protocol for all ALDC subagents (planning, implement, review) and the conductor. Rides along with rules-floor-cheatsheet.md in the conductor's per-phase inline injection — no new context-injection channel needed. Purpose: stop transient tool/MCP failures (e.g. a TLS-intercepting proxy blocking al-mcp's calls to Microsoft symbol servers) from turning into unbounded retry loops, while never misclassifying a real code problem as a tool problem."
---

# Tool-Failure Protocol

Applies to any tool call — al-mcp, nab-al-tools, WebFetch, Bash, anything that can fail for reasons outside the code itself.

1. **Try once.** If it fails and a clearly-applicable alternate exists (a different tool, adjusted params — e.g. cross-check `al_build` against a bare `al_compile`, or retry `al_downloadsymbols` with `globalSourcesOnly=true`), try that alternate **once**.
2. **Then stop.** Two attempts is the ceiling. No further variations, no repeated guessing, no silent workarounds, no trial-and-error tool bursts.
3. **Classify before surfacing:**
   - **TOOL_BLOCKED** — the error text carries network/TLS/certificate/handshake/timeout/connection-reset signatures (e.g. "unable to verify the first certificate", `ECONNRESET`, "connection timed out"). This is an environment/infrastructure problem, not a code defect.
   - **CODE_ISSUE** — the failure is a compiler diagnostic with an AL file:line and an `ALxxxx` code, or a symbol genuinely not found among something the spec/code actually references.
4. **On TOOL_BLOCKED** — report it plainly as a labeled environment blocker: `TOOL_BLOCKED: <tool> — <one-line symptom> — looks like a network/proxy/TLS-interception issue, needs human attention.` Stop working that thread; do not keep retrying and do not silently fall back to inventing data or guessing a signature.
5. **On CODE_ISSUE** — handle normally; this is real work, not an infrastructure problem, and does not get the TOOL_BLOCKED escalation treatment.

**For al-implement-subagent specifically:** if a build fails with no clear cause, the project depends on a sibling project (test app on base app), or a symbol refresh doesn't seem to register, load `skill-al-mcp-workspace` before spending more turns on it — it has the concrete tool-vs-code disambiguation gotchas (stale path causing false build failures, `al_downloadsymbols` stuck on the wrong project, `al_build` vs `al_getdiagnostics` disagreeing).
