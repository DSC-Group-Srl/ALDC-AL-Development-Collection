---
name: skill-mcp
description: Design new Business Central AL API pages/queries and bound actions, or review existing ones, so they work well as tool surfaces for the Business Central MCP server, Copilot Studio agents, and other AI/agentic OData consumers. Use this whenever a user is creating an API page (`PageType = API`), an API query object, or a `[ServiceEnabled]` bound action in AL; adapting an existing API surface for AI agents; choosing between an API page and an API query; naming/captioning/tooltip-ing fields and entities that an LLM will read as a tool description; or auditing an extension's API pages for "MCP readiness" or "agent readiness" — even if the user never says "MCP" and just asks to "expose this table as an API," "let Copilot call this," or "review my API page."
---

# Business Central MCP API Design

Reference and review checklist for making AL API pages, API queries, and bound actions good tool surfaces for the Business Central MCP server (and, by extension, any OData/Copilot Studio/Power Platform consumer — the same design choices help all of them). Use it both to design a new API page/query from scratch and to review an existing one for gaps.

Companion reading, not restated here: general AL conventions the user's own repo may already have for error handling, naming, or the BC Agent SDK (a different, unrelated consumption path — see §1.4). This skill is only about API pages/queries as MCP tool surfaces.

## 1. Mental model: what actually becomes a tool

### 1.1 Architecture

The [Model Context Protocol](https://modelcontextprotocol.io) is an open standard for how AI clients discover and call tools. Business Central ships a hosted MCP server at a single fixed endpoint, `https://mcp.businesscentral.dynamics.com`. Any MCP-compliant client (VS Code + Copilot, Copilot Studio, Claude, ChatGPT, MCP Inspector, custom agents) connects to it and selects the target environment via HTTP headers (`TenantId`, `EnvironmentName`, `Company`, optional `ConfigurationName`) — not via URL path segments. Non-ASCII `Company`/`ConfigurationName` values must be Base64-encoded.

Authentication is OAuth 2.0 Authorization Code + PKCE (OAuth 2.1 on the enhanced server, see §1.4) against Microsoft Entra ID. **Every call runs under the connecting user's own BC identity and permissions.** There is no separate "agent user" concept at the MCP layer — normal BC permission sets are the only access-control lever available; there's nothing MCP-specific to configure per user beyond the object-level config in §1.2.

[MCP overview](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/ai/mcp-overview) · [MCP authorization spec](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)

### 1.2 What becomes a tool, and how it's configured

- **By default, every published API page is exposed read-only.** No admin action needed for an agent to list/read data through any API page already marked `Published` as a web service.
- **Write access (create/modify/delete/bound actions) is opt-in per object**, configured on the **MCP Server Configurations** page (`page=8351`), which requires the **MCP - ADMIN** permission set. Each configuration turns on a master **Unblock Edit Tools** switch, then sets `Allow Read`/`Allow Create`/`Allow Modify`/`Allow Delete`/`Allow Bound Actions` independently per API page object. If `Unblock Edit Tools` is off, all of those collapse to read-only regardless of the individual flags.
- Only **top-level API pages** can be added as tools — `ListPart`/`CardPart` API page subtypes aren't supported.
- **Dynamic Tool Mode**: off = every allowed operation on every configured page becomes a *named* static tool an agent maker explicitly adds in Copilot Studio (`List<Page>_PAG<ID>`, `Create<Page>_PAG<ID>`, `ListUpdate<Page>_PAG<ID>`, `Delete<Page>_PAG<ID>`, `<action>_PAG<ID>`). On = tools aren't statically listed; the agent calls three system tools at runtime instead — `bc_actions_search`, `bc_actions_describe`, `bc_actions_invoke` — to discover and invoke whatever the configuration allows. Turn this on whenever the number of exposed tools could exceed a host's static limit — **Copilot Studio currently caps at 70 tools**, and anything past the first 70 in a static configuration is silently unavailable.
- **Discover Additional Objects** (only meaningful with Dynamic Tool Mode on) grants read-only access to *any* API page in the environment, even ones never explicitly added to the configuration.
- The **enhanced MCP server** (GA April 2026) adds static pre-runtime validation of tool configurations (catches missing parent API pages, broken object references before an agent ever calls them), a Purview-backed audit trail of MCP configuration changes, OAuth 2.1, and embedded-resource support for passing large datasets to code-execution tools.

[Configure Business Central MCP Server](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/ai/configure-mcp-server) · [Connect to BC MCP Server in VS Code](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/ai/use-mcp-server-in-vscode) · [Enhanced MCP server release plan](https://learn.microsoft.com/dynamics365/release-plan/2026wave1/smb/dynamics365-business-central/create-agentic-experiences-enhanced-mcp-server)

### 1.3 The one fact that should drive every other decision in this skill

**There is no BC-specific "AI description" field, anywhere.** The MCP server derives everything the LLM sees about a tool from metadata that already exists on the API page/query object: `Caption`/`EntityCaption`/`EntitySetCaption`, field captions and tooltips, `EntityName`/`EntitySetName`, and — for bound actions — the procedure name plus its XML doc comment. There's no dedicated override field distinct from the normal localized caption metadata exposed at `.../entityDefinitions`.

Practical consequence: **caption and tooltip quality is the entire tool-description budget.** A page with a cryptic caption is a cryptic tool no matter how clean the underlying AL is — Microsoft's own guidance for agent makers stuck with a bad caption is to fall back to a hand-editable Power Platform connector instead, precisely because the MCP path has no override mechanism. Every checklist item below ultimately serves this one fact.

[Developing a custom API — localization](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/devenv-develop-custom-api#general-tips-for-custom-apis)

### 1.4 MCP vs. a coded/first-party agent framework

If the codebase also has a BC coded-agent setup (an `IAgentFactory`/`IAgentMetadata` style integration, sometimes called the BC Agent SDK or Copilot Capability framework), don't conflate the two — they're complementary, not alternatives:

| | MCP server | Coded agent framework |
|---|---|---|
| Consumer | External MCP host (VS Code, Copilot Studio, Claude, ChatGPT) | A BC-hosted agent running inside BC as its own first-class user |
| Identity | The connecting human's own permissions | A dedicated agent user with its own profile/permission set |
| Surface | Existing API pages/queries, exposed automatically | The BC UI itself via the logical UI API |
| Audit | Native — calls run as the real user | Agent is its own user; audit needs deliberate design (§5) |

This skill covers the **MCP path only**: making API pages/queries good tool surfaces. The AL-side work still benefits the other path too (clear captions, safe bound actions, actionable errors help any caller), but the configuration and identity mechanics differ.

## 2. Checklist for API pages (`PageType = API`)

Work through this whenever creating or reviewing an API page meant to be agent-callable. Every unchecked item is a real tool-quality gap, not a style nitpick — explain *why* when flagging one, not just that it's missing.

- [ ] `PageType = API`; `APIPublisher`/`APIGroup`/`APIVersion` set (`APIVersion` follows `vX.Y`, e.g. `v1.0`).
- [ ] **`Caption` is a human-readable phrase**, not the object identifier repeated — `Caption = 'Service Contracts API'`, never `Caption = 'ctsoSvcContractsAPI'`. This *is* the tool's one-line description to an LLM; treat it as prompt content, not internal plumbing.
- [ ] `EntityName`/`EntitySetName`/`APIPublisher`/`APIGroup` are camelCase, alphanumeric only. Don't repeat the extension's internal object prefix inside the entity name — the publisher/group already namespaces it; repeating it adds noise an agent has to parse through for zero semantic gain (`ctsoServiceContractAPI` should just be `serviceContractAPI` once `APIPublisher`/`APIGroup` already say who owns it).
- [ ] `EntitySetName` is the **plural** of `EntityName` for anything that returns a collection (`serviceContractAPI` → `serviceContractsAPI`). Keep both singular only for genuine setup/singleton entities (one row per company). A list-returning entity whose set name equals its entity name reads to an agent as "list of one" — it won't reliably infer that filtering/paging still applies.
- [ ] `ODataKeyFields = SystemId` — always, unless integrating with a system that requires composite natural keys (rare; document why). A single GUID key is what lets generic MCP/Power Automate/Power Apps tooling address a specific record without app-specific knowledge.
- [ ] Every exposed field has an unambiguous camelCase alias, distinct from every other field's meaning on the page.
- [ ] **Field-level `ToolTip` wherever the field name alone is ambiguous** — status/type enums surfaced as raw integers, business-specific abbreviations, fields whose unit or currency isn't obvious from the name. This is, empirically, the single most commonly skipped item and the highest-leverage one to add: an agent choosing which field to filter or write has only the field name to go on if there's no tooltip. Since BC 2024 release wave 1, `ToolTip` can be declared once on the **table field** and every page referencing it inherits it automatically — for an API surface with several pages over the same table, that's one place to fix instead of many.
  - Follow the same authoring convention BC uses everywhere else: field tooltips start with *"Specifies..."*, action tooltips start with an imperative verb ("Release", "Calculate"), and both stay under ~200 characters.
- [ ] Enum fields projected as `Integer` for API stability get a tooltip enumerating the mapping (`0=Open,1=Released,...`) or, better, a paired human-readable text field so an agent doesn't have to guess enum ordinals.
- [ ] Prefer first-level fields over `ODataEDMType` complex fields — deprecated in API v2.0 in favor of first-level properties or navigation properties (page parts), both for performance and because nested complex JSON is harder for an OData/MCP client to reason about than flat properties.
- [ ] `InsertAllowed`/`ModifyAllowed`/`DeleteAllowed` reflect the entity's actual lifecycle, not a copy-pasted default. Reference/master data should usually be `false`/`false`/`false`, changed only via bound actions; transactional data the calling app owns is typically `true`/`true`/`true`. A page whose name implies read-only derived data (statistics, computed totals) but whose CRUD flags are all `true` is a real bug waiting to be found by an MCP admin flipping on write access — audit these explicitly, don't assume they were set deliberately.
- [ ] `OnOpenPage` sets `Rec.ReadIsolation := IsolationLevel::ReadCommitted` on read-heavy pages so MCP list/read calls don't take unnecessary locks.
- [ ] No database writes in `OnInit`/`OnOpenPage`/`OnFindRecord`/`OnNextRecord`/`OnAfterGetRecord`/`OnAfterGetCurrRecord` — list reads may run against a read-only replica; side effects there silently fail or degrade performance.
- [ ] `Permissions` declared explicitly on any API page that touches more than its own source table (child tables read/written by triggers or bound actions) — see §5.
- [ ] Filtering/paging: expose the fields an agent will realistically filter on (`$filter`) with real table keys behind them, so paging stays fast under the platform's default 20,000-row server-driven page size. Don't design a page that requires paging through the entire set to find one row by a non-indexed field.

## 3. API page vs. API query — which to build

Prefer an **API query** over an API page when the scenario is:

- **Pure read**, no create/update/delete, and no need for webhooks — queries can't be written to.
- **A join across tables** an agent would otherwise reconstruct client-side via multiple round trips and `$expand` — e.g. "order lines joined to their header's customer and salesperson" today might require calling the header API, the line API, and cross-referencing; a single query flattening that join is fewer tool calls *and* a smaller, clearer schema for the model to reason about.
- **Aggregation-shaped** — sums/counts/grouping an agent would ask for in natural language ("total sales per customer this quarter") map directly onto query `Method = Sum/Count` + grouping, instead of asking the agent to page through raw rows and sum client-side (slow, and burns context window on rows it doesn't need).
- Set `DataAccessIntent = ReadOnly` on API queries used purely as readers, so the platform can route to a read replica.

Trade-off: queries can't be extended and can't carry bound actions, so anything needing a write path or a lifecycle action (release/approve/reopen) has to stay an API page regardless of how read-heavy the rest of its surface is.

**Anti-pattern to flag on sight**: an unbound codeunit action published via `[ServiceEnabled]` that returns a hand-built JSON string (`Text` return type) instead of a typed entity. This is common in codebases that grew a REST-like action for a specific client (a mobile app that "knows the shape out-of-band") before API queries existed as an option. It's close to opaque to an MCP tool caller: the tool's declared return type is `Text`, so the agent gets no field-level schema for what's inside that string and can't `$select`/`$filter` it at all. See `references/examples.md` for a concrete before/after.

## 4. Designing bound actions for agentic tool-calling

### 4.1 XML doc comments are mandatory, not optional

Every `[ServiceEnabled]` procedure needs a `///` doc comment with `<summary>`, one `<param>` per parameter, and `<returns>` if non-void. The bar for `<summary>` content: state (1) what the action does, (2) what business-state transition it causes — so an agent understands whether this is idempotent or not — and (3) any side effect that isn't obvious from the name.

Why this matters more here than for a human developer reading IntelliSense: a human can go read the codeunit body if the doc comment is thin. **An LLM tool-caller only ever sees the tool name, parameter names/types, and whatever description surfaces through object metadata — there is no fallback to "go read the source."** A thin or missing doc comment produces a tool the agent either refuses to call (safe, but useless) or calls wrong (unsafe).

See `references/examples.md` for a full before/after of a bound action's doc comment.

### 4.2 Parameter design

- Prefer a small number of explicit, named, primitive-typed parameters (`Code[20]`, `Text`, `Integer`, `Boolean`, `Date`) over a single JSON blob parameter — every named parameter is visible to the tool caller; a blob parameter hides its internal shape from the agent entirely (same failure mode as the JSON-string anti-pattern in §3).
- Avoid `Variant`-typed or overly generic parameters. Prefer strongly-typed overloads so the compiler — and the agent, reading the parameter type — knows exactly what's valid, rather than a variant the callee inspects at runtime.
- If the app already has a convention for stamping "who, inside a shared integration credential, actually triggered this" (see §5), keep that parameter on every new mutating action and document it identically each time.

### 4.3 Idempotency and side-effect transparency

- State-transition actions (release, approve, reject, reopen) are **not** idempotent and must say so in the summary — calling one twice on an already-transitioned record should error clearly, not silently no-op or double-transition. An agent retrying a failed call needs to know whether retrying is safe.
- Read-then-decide actions (compute a value, generate a report) are safe to call repeatedly; say that too ("Read-only; does not modify the record") so an agent doesn't unnecessarily hesitate or wrap the call in confirmation logic.
- Every mutating action should return a result code reflecting what actually happened (created/updated/deleted), and the `<returns>` doc should describe what the *returned key* means, not just repeat the AL return type.

### 4.4 The obsolete-overload versioning pattern

When a `[ServiceEnabled]` bound action's signature needs to change in a way that would break existing consumers, don't modify the existing procedure signature in place:

1. Add a **new** overload with the new signature, placed **before** the old one in source order.
2. Mark the **old** overload `[Obsolete('<reason>', '<version>')]`, keep its body empty or a no-op, and keep `[ServiceEnabled]` on it so its OData action metadata doesn't disappear out from under still-connected old clients during the deprecation window.
3. Keep both `[ServiceEnabled]` — but validate after any AL compiler/runtime upgrade that the intended (new) overload is still the one the OData endpoint answers to; multiple `[ServiceEnabled]` overloads of the same action name is a source-order-sensitive area of the platform, not a documented multi-overload publishing guarantee.

Full before/after code in `references/examples.md`. Apply the same shape for any MCP-motivated signature change (e.g. adding a required confirmation parameter to a destructive action) — never mutate an already-published action's signature or documented behavior in a way old clients silently start hitting differently.

## 5. Permissions and audit for agent-driven access

- **Least privilege at the object level**: declare `Permissions` on every API page/codeunit exposed for MCP use, scoped to exactly the `tabledata` it needs (`R`/`RIMD` as appropriate):
  ```al
  Permissions =
      tabledata "CTSO Service Contract" = R,
      tabledata "CTSO Service Contract Line" = R;
  ```
  This matters more for MCP than for a purely internal integration because the MCP admin's per-object `Allow Create`/`Allow Modify`/`Allow Delete`/`Allow Bound Actions` flags (§1.2) are a coarse on/off switch at the page level. The AL-level `Permissions` property is the finer-grained backstop that keeps a page's bound actions from silently reaching into tables the page's own declared scope doesn't cover.
- Use `[InherentPermissions]` on narrow internal helper procedures only when a specific, small, same-extension operation genuinely needs elevated access it shouldn't require of the calling user's full permission set — not as a blanket workaround for missing `Permissions` declarations.
- **The audit gap agentic access exposes**: every MCP (and generic OData) call authenticates as the connecting user's own BC identity, so standard system audit fields (`SystemCreatedBy`, `SystemModifiedBy`) populate correctly per call — *when the caller is a real end user calling on their own behalf.* The gap appears when a single shared service principal calls the API on behalf of many end users (a mobile app, a portal, an RPA bot) — standard BC audit fields can't distinguish "the integration called this" from "which end user, inside the integration, triggered it." If that shape exists in the app already, extend its existing "acting user" stamp field into any new mutating bound action, stamping it *before* the state change:
  ```al
  Rec.Validate("Acting User No.", pActingUserNo);
  Rec.Release();
  Rec.Modify(false);
  ```
  Don't invent this pattern for actions the MCP server itself will call directly (a human or agent authenticating as themselves, no shared credential in between) — there, `SystemModifiedBy` already resolves to the real person, and adding an extra stamp parameter is cargo-culting a fix for a problem that doesn't exist in that call path.

## 6. Rollout and versioning discipline

- **Respect the existing `APIVersion`/obsolete-overload strategy** — anything that alters the observable behavior of an already-published entity or action (renaming `EntitySetName`, tightening/loosening CRUD flags, changing a bound action's parameter list) is a breaking change to every existing consumer, not just to hypothetical future MCP consumers. Two safe paths:
  1. **Additive, same version**: adding `Permissions`, adding field-level `ToolTip`s, adding/improving XML doc comments, fixing a `Caption` string — none of these change the wire contract and can ship in the current API version without bumping it.
  2. **Breaking, new version**: renaming `EntityName`/`EntitySetName`, changing CRUD flags, or changing a bound action's parameter list needs either a new `APIVersion` with the old version left running unchanged, or the obsolete-overload pattern applied within the same version. Never silently change these on a live version.
- **Sequence by leverage, not file order**: tooltips and `Permissions` are zero-risk additive changes — do a whole app in one pass. `Caption` fixes are additive but user-visible in the `.../entityDefinitions` metadata external tooling may already cache — coordinate with any downstream integration owners before a bulk rename. CRUD-flag corrections need a product decision first, then a versioned rollout.
- Once API pages are cleaned up, validate them against an actual **MCP Server Configuration** in a sandbox (`page=8351`) before assuming they're agent-ready — confirm bound actions appear under `Allow Bound Actions` as expected, and confirm `Dynamic Tool Mode`/`Discover Additional Objects` behave as intended for the app's total tool count relative to the 70-tool Copilot Studio cap.

## 7. How to use this checklist in practice

**Reviewing an existing API page**: go through §2 (and §4 for any bound actions) item by item, quoting the specific property/line that fails each check and explaining *why* it matters for an agent caller specifically — not just "this is missing" but "an agent choosing which field to filter has only the field name to go on here." Group findings by risk: caption/tooltip/naming gaps are zero-risk to fix; CRUD-flag or Permissions gaps need a decision from whoever owns the data.

**Designing a new API page or query from scratch**: decide page vs. query first (§3), then build the page/query straight from the §2/§4 checklists rather than retrofitting them after — it's much cheaper to get `EntitySetName` pluralization and `ODataKeyFields` right on the first pass than to do a breaking rename later.

See `references/examples.md` for full, runnable-shape AL code for every good/bad pattern referenced above — naming, tooltips, the obsolete-overload pattern, `ErrorInfo` vs. bare `Error`, and the JSON-blob anti-pattern.

## References

- `references/examples.md` — worked before/after AL code for every pattern in this skill
- [MCP overview](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/ai/mcp-overview)
- [Configure Business Central MCP Server](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/ai/configure-mcp-server)
- [Create agents in Copilot Studio that connect to Business Central](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/ai/create-agent-in-copilot-studio)
- [API page type](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/devenv-api-pagetype)
- [Developing a custom API](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/devenv-develop-custom-api)
- [API query type](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/devenv-api-querytype)
- [Web service performance](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/webservices/web-service-performance)
- [Documenting your code with XML comments](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/devenv-xml-comments)
- [Permissions property](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/properties/devenv-permissions-property)
- [ErrorInfo data type](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/methods-auto/errorinfo/errorinfo-data-type) · [Actionable errors](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/devenv-actionable-errors)