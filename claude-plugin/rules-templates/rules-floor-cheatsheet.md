---
description: "Condensed always-on AL rules floor for inline injection into code-touching subagents (implement, review, planning). NOT for main-session auto-apply — this file has no `paths:` glob on purpose. The conductor reads this once per session and pastes it inline into every phase's Task instruction instead of the full 7 domain files below, which stay available as on-demand reference (read the matching al-*.md when a subagent needs the rationale/examples behind a rule)."
---

# AL Rules Floor — inline-injection cheat sheet

One line per hard rule, no rationale/examples — those live in the full files (`al-guidelines.md`, `al-code-style.md`, `al-naming-conventions.md`, `al-performance.md`, `al-error-handling.md`, `al-events.md`, `al-testing.md`). Read a full file only when a subagent needs the "why" or a worked example behind one of these lines.

**Foundational** — Event-driven only, never modify base/standard objects (extension-only). AL-Go: App project = app logic only, Test project = tests only and depends on App, never the reverse. Generate tests ONLY when explicitly requested.

**Style** — 4-space indent (Microsoft AL formatter default). PascalCase objects/variables/functions. Feature-based folders (`src/Feature/SubFeature/`), never by object type. Namespace mirrors the feature-folder path (root = app name, no object-type segments, runtime ≥13.0 only — skip below that) with a `using` for every out-of-namespace symbol. XML doc comments (`<summary>`, `<param>` for every param, `<returns>`, `<remarks>` for edge cases/callers) on every documented procedure. Small, focused procedures, no monoliths. One-of-N branching → enum-linked interface (one codeunit per value), never a growing `case`. Not-yet-built features get a stable-signature facade delegating to a stub/event — never a caller-visible "NotImplemented" name. Always `()` on method calls, even parameterless.

**Naming** — Objects ≤26 chars, PascalCase, no cryptic abbreviations. Files: `<ObjectName>.<ObjectType>.al`. Event subscriber params: descriptive, never bare `Rec`. Interfaces prefixed `I`, implementations suffixed `Impl`.

**Performance** — Filter before processing (`SetRange`/`SetFilter` first, then `SetLoadFields`, only fields actually used). Temp tables/dictionaries/lists for temp data, not repeated DB round-trips. Set-based ops (`CalcSums`, `CalcFields`) over manual accumulation loops. Batch writes — compute first, write once. Never `SetCurrentKey` unless a specific row order is a genuine requirement.

**Error handling** — `[TryFunction]` for read-only/validation risk only, never around logic that writes; writes needing rollback go in their own codeunit invoked via `Codeunit.Run()`. All user-facing/error text via `Label` (`Locked = true` for telemetry-only text), never hardcoded strings. Don't reshape business logic just to force a compile — if a referenced base symbol looks wrong, leave it flagged for correction. Custom telemetry (`Session.LogMessage`) only when explicitly requested.

**Events** — Prefer integration events over direct base-object changes. `OnBefore`/`OnAfter` pairs with an `IsHandled` pattern where a subscriber may skip default logic. Event params: pass records by `var`, descriptive names, enough context for a subscriber to act without re-querying.

**Testing** (files under `**/test/**`) — Given/When/Then naming, `Assert` calls, use standard `Library-*` codeunits for setup, never hand-roll test data creation. Test files mirror the App project's folder structure.
