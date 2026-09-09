---
name: skill-demo-data
description: "AL demo/sample data generation for Business Central. Lives in its own sibling AL project, app-demo/ (created on demand, dependent on the base app + its own dependencies + Microsoft's Contoso Coffee Demo Dataset). Always plugs into Microsoft's real Contoso Demo Tool (Enum/Interface 'Contoso Demo Data Module', Page 'Contoso Demo Tool') — no bespoke Demo Tool page/table/enum is ever built. Use when building or extending demo data for an app, a 'Demo Tool' integration, Setup/Master/Transactional demo-data codeunits, or scenario-driven sample data."
---

# Skill: Demo Data Generation (Contoso-style)

## Purpose

Give an AL app a customizable, regenerable demo dataset, structured the same way
Microsoft structures Contoso Demo Data (the Contoso Coffee apps): a config page
listing **modules**, each with a **Configure** action (map real records to
scenario roles) and a **Create Demo Data** action (generate setup, master, and
transactional records for a documented set of walkthrough scenarios).

**There is exactly one way to get this shape: plug into Microsoft's own
already-shipped Contoso Demo Tool.** A bespoke equivalent (a second Demo Tool
page/table/enum) is never the right answer for this plugin — it duplicates
infrastructure Microsoft maintains and gives the developer a UI that doesn't
show up alongside every other module they already know. If the target
environment genuinely cannot take the dependency, that is a blocker to
escalate to the developer (see `al-demo-architect`'s Constraints), not a
license to build a bespoke copy.

This is the implementation skill `al-developer` loads when `al-demo-architect`
hands it an approved demo-data plan (or a data-content brief for an already-built
harness). It is not a documentation skill — `skill-functional-docfx` and
`skill-aldoc` own written documentation; this skill owns the AL objects that
generate data.

## When to Load

- Building the AL harness (dependency, enum extension value, interface-implementing
  codeunit, per-module Configure setup table/page) for an approved
  `{req_name}.demo-data-plan.md`.
- Writing the actual data-generation content (Setup/Master/Transactional record
  inserts) into a harness per `al-demo-architect`'s data-content brief.
- Adding a new module to an existing demo-data toolkit (incremental mode).
- Any request to "generate sample data", "seed demo records", "add a Contoso-style
  demo tool" for a custom app.

## The contract — Microsoft's Contoso Demo Tool

Confirmed against `Contoso Coffee Demo Dataset` (Microsoft, app id
`5a0b41e9-7a42-4123-d521-2265186cfb31`), namespace `Microsoft.DemoTool`. There is
no narrative MS Learn documentation of this AL-level contract — MS Learn only
covers the end-user Configure/Generate workflow. Ground every detail here against
the live symbols (`al_symbolsearch`) before writing AL, since ordinals and
signatures can drift across BC versions.

1. **`Enum "Contoso Demo Data Module"`** (extensible, namespace `Microsoft.DemoTool`)
   — one value per module. Already-taken ordinals — do not reuse, do not assume
   you can redirect their implementation: `Common Module`=0, `Manufacturing
   Module`=1, `Warehouse Module`=2, `Service Module`=3, `Fixed Asset Module`=4,
   `Human Resources Module`=5 (Microsoft's own base-BC HR demo data — unrelated
   to and not reusable by an HR-flavored custom app), `Job Module`=6,
   `Foundation`=10, `Finance`=11, `CRM`=12, `Bank`=13, `Inventory`=14,
   `Purchase`=15, `Sales`=16, `EService`=17, `Analytics`=18. Each value's
   declaration binds an implementation (`Implementation = "Contoso Demo Data
   Module" = <SomeCodeunit>;`), fixed by whoever declares it — you can only
   **add a new value**, never override an existing one's binding.

2. **`Interface "Contoso Demo Data Module"`** (namespace `Microsoft.DemoTool`) —
   every module codeunit implements:
   ```al
   procedure RunConfigurationPage()
   procedure GetDependencies(): List of [Enum "Contoso Demo Data Module"]
   procedure CreateSetupData()
   procedure CreateMasterData()
   procedure CreateTransactionalData()
   procedure CreateHistoricalData()
   ```
   An empty body is a valid implementation for any stage the app has nothing to
   contribute to.

3. **`Table "Contoso Demo Data Module"`** and **`Page "Contoso Demo Tool"`** are
   Microsoft's real, already-shipped module registry and UI — **do not build your
   own equivalents**. `Codeunit "Contoso Demo Tool".RefreshModules()` /
   `GetRefreshedModules()` walks the enum's values itself and inserts/refreshes a
   row per value automatically; adding a new enum value is enough for it to
   appear on Microsoft's real page with no further wiring.

4. **`Codeunit "Generate Contoso Demo Data".Run(var Record: Record "Contoso Demo
   Data Module"): Boolean`** resolves each row's enum value to its bound
   interface implementation and calls the `Create*Data` methods in
   `GetDependencies()`-resolved order.

5. **Per-module setup tables are separate, small, module-owned tables** (e.g.
   `"Manufacturing Demo Data Setup"`, `"Whse Demo Data Setup"`, the generic
   `"Contoso Coffee Demo Data Setup"`) — not fields on the shared registry table.
   Build one per module for whatever Configure-time role-mapping it needs.

## The demo dataset lives in its own app: `app-demo/`

The demo-data objects are never added to the base app, and never folded into
the test app. They live in a **separate AL project**, sibling to `app/` (and
`app-test/`/`app-performance/` if present) — same convention as any other
multi-project workspace in this plugin (`skill-al-mcp-workspace`). This project
does not exist in a fresh template repo; `al-developer` creates it the first
time `al-demo-architect` requests a Pass 1 harness for an app that doesn't have
one yet (bootstrap mode). Incremental-mode runs reuse the existing `app-demo/`.

**`app-demo/app.json` dependencies** — resolved by `al-demo-architect` during
planning and carried in the harness brief, built by `al-developer`:

1. `Contoso Coffee Demo Dataset` (Microsoft, id
   `5a0b41e9-7a42-4123-d521-2265186cfb31`) — the real integration contract.
2. **The base app itself** — `app-demo` demonstrates it, so it depends on it
   directly (id/name/publisher/version copied from the base app's own
   `app.json`).
3. **Every one of the base app's own `dependencies`, copied in too** — not
   inferred as transitive. If the base app depends on other apps (a shared
   foundation library, another DSC extension it extends), `app-demo`'s demo
   data may need to construct or reference records from those apps directly
   (a posting group defined in a dependency, a table the base app only
   extends). Declaring them explicitly in `app-demo/app.json` is what makes
   their symbols resolvable when writing Pass 2 content — don't wait to
   discover the need mid-Pass-2; copy the full dependency list at Pass 1.

`app-demo`'s own `idRanges` are separate from the base app's — request a
fresh, non-overlapping range the same way any new AL project would (ask the
developer if the plan doesn't already carry one). Every enum/object ID pinned
below is pinned from **`app-demo`'s** `idRanges`, never the base app's.

Register the new project the same way any sibling project is added to a
multi-project workspace (`commands/al-initialize.md`'s pattern): if a root
`<name>.code-workspace` file exists, add `app-demo` to it (`Bash: al workspace
create <name>.code-workspace app app-test app-demo` regenerates it, or edit
the existing manifest by hand); either way call **al-mcp** `al_addproject` on
`app-demo`'s canonical path so it's visible for live symbol lookups this
session. Load `skill-al-mcp-workspace` for the build/symbol-sync mechanics
now that there are 3+ sibling projects.

## Two implementation passes (matches al-demo-architect's brief handoffs)

`al-developer` receives two distinct requests from `al-demo-architect` for the
same module, never one undifferentiated "build the demo data" ask:

### Pass 1 — the harness (structure, no data content yet)

Given the approved plan's module list and role definitions, create `app-demo/`
if it doesn't exist yet (see above), then build and compile clean:

1. **`app-demo/app.json`** with the three dependency groups above (Contoso
   Coffee Demo Dataset, the base app, the base app's own dependencies).
   Download symbols (`al_downloadsymbols`) for all of them, add the project to
   al-mcp (`al_addproject`), and confirm with `al_symbolsearch` (`query:
   "Contoso Demo Data Module"`, `scope: "dependencies"`) before writing any AL.
   If the symbols don't resolve or the dependency can't be added for this
   target, stop and report it back as a blocker — never substitute a bespoke
   page/table/enum to route around it.

2. **Enum extension** — exactly one new value, with an ID pinned explicitly from
   `app-demo`'s own `idRanges` (never let AL auto-assign it):
   ```al
   enumextension 18141160 "Dyna HR Demo Data Module" extends "Contoso Demo Data Module"
   {
       value(18141160; "Dyna HR Module")
       {
           Caption = 'Dyna HR';
           Implementation = "Contoso Demo Data Module" = "Dyna HR Demo Data Module";
       }
   }
   ```

3. **Interface-implementing codeunit** — one per module, with **empty stage
   bodies wired to helper codeunits** (small, focused procedures, same as
   everywhere else) but no record-insert logic yet — that's Pass 2:
   ```al
   codeunit 18141164 "Dyna HR Demo Data Module" implements "Contoso Demo Data Module"
   {
       procedure RunConfigurationPage()
       begin
           Page.RunModal(Page::"DSC HR Demo Data Cfg. Common");
       end;

       procedure GetDependencies(): List of [Enum "Contoso Demo Data Module"]
       var
           Dependencies: List of [Enum "Contoso Demo Data Module"];
       begin
           Dependencies.Add(Enum::"Contoso Demo Data Module"::"Common Module");
           exit(Dependencies);
       end;

       procedure CreateSetupData()
       begin
           DemoDataCommon.CreateSetupData();
       end;

       procedure CreateMasterData()
       begin
           DemoDataCommon.CreateMasterData();
       end;

       procedure CreateTransactionalData()
       begin
           DemoDataCommon.CreateTransactionalData();
       end;

       procedure CreateHistoricalData()
       begin
           // no historical documents in this app — empty is a valid implementation
       end;

       var
           DemoDataCommon: Codeunit "DSC HR Demo Data - Common";
   }
   ```
   `GetDependencies()` is a real design decision, not boilerplate — carry
   whatever the approved plan recorded. Only list `"Common Module"` unless the
   plan deliberately wants this module's data generated *after*, and layered on
   top of, another module's data. In particular: **do not** depend on
   `"Human Resources Module"` just because the app is HR-flavored — that
   ordinal is Microsoft's own base-BC HR demo data, with employee identities the
   app doesn't control. If the plan calls for a specific, predictable roster,
   keep the module self-contained and generate its own roster in
   `CreateMasterData()`.

4. **Per-module Configure setup table/page** — one per module, with one field
   per role the plan defined (a customer, a location, an item with tracking, a
   starting year, a country/region). This is what `RunConfigurationPage()` opens.
   Configure never generates data — it only captures **which existing records**
   play which scenario role; leave the fields empty at this pass, Pass 2 resolves
   and populates them.

5. **The module's smoke test codeunit** (empty `[Test]` stubs — Pass 2 fills in
   the assertions once the data content exists), following `skill-testing`'s
   Given/When/Then shape and standard `Library-*` codeunits for setup.

6. **Nothing else** — no bespoke Demo Tool page, no bespoke module-registry
   table, no bespoke module enum. Microsoft's real page already provides
   Configure / Generate / Generate Setup once the enum value and interface
   implementation exist.

Report back: compiled clean, the harness's file list, and any role field or
`GetDependencies()` question the plan left ambiguous.

### Pass 2 — the generated data (content, into the harness Pass 1 built)

`al-demo-architect` hands back a **data-content brief**: for every Configure
role, the resolved record (developer-specified or auto-selected from existing
company data — never invented) or an explicit "not found, ask the developer"
flag; and for every scenario, the concrete setup/master/transactional records to
insert. Given that brief, fill in the harness Pass 1 built:

1. **Configure setup table defaults** — wire the resolved role → record mapping
   from the brief into the setup table (as the Configure page's default/last-used
   values, or inserted directly if the plan says to skip manual Configure).
2. **`CreateSetupData()`** — number series, posting groups, templates — whatever
   the scenarios need to exist before any document can post. Idempotent:
   re-running must not duplicate setup rows.
3. **`CreateMasterData()`** — customers, vendors, items, resources, BOMs —
   created only if they don't already exist (check by a stable key, e.g. a
   "DEMO-" number-series prefix, before inserting).
4. **`CreateTransactionalData()`** — the actual documents/journals that make the
   scenario demonstrable (a posted sales order, a firm-planned production order,
   a service contract). Batch the writes: compute the full data first, then
   insert — never accumulate via repeated single-record round trips
   (`al-performance.md`).
5. **`CreateHistoricalData()`** — backdated/archived documents, if the brief
   calls for any; empty body otherwise.
6. **The smoke test's assertions** — record counts and idempotency (a second
   `Generate` run must not duplicate master/setup records).

A brief's role that resolves to "not found" is never silently skipped or
invented around — flag it back to `al-demo-architect`/the developer and leave
that role's insert logic pending until a value is supplied.

## Scenario documentation

Every module ships a short list of numbered walkthrough scenarios (what a user
does once the data exists) — this is what turns "there is data" into "there is
something to demo". Keep this list in the demo-data plan doc
(`{req_name}.demo-data-plan.md`), not duplicated into code comments; it belongs
to `al-demo-architect`'s planning output, not to the harness's AL.

## Optional: Job Queue integration

If the app has recurring processes worth demonstrating (a batch job, a
reconciliation), offer a toggle (default off) to create the matching Job Queue
Entry as part of Generate — never force it. This is Pass 2 content, not harness
structure.

## Incremental Regeneration

A module already marked **Generated** must not be silently re-run and
duplicated. `CreateSetupData()`/`CreateMasterData()` should check existing state
first; re-running an already-generated module either no-ops or requires the
developer to explicitly re-trigger it — never happens as a side effect of
generating a *different, new* module.

## Anti-patterns

- **Never build a bespoke Demo Tool page/table/enum/interface**, for any target
  — if the real dependency isn't viable, that's an escalation, not a fallback to
  build around.
- Don't reuse or assume you can redirect an already-declared enum value's
  `Implementation` (e.g. `"Human Resources Module"`) — add a new value instead.
- Don't let `GetDependencies()` casually include a domain module (like Human
  Resources) whose demo data isn't under the app's control, if a downstream
  app/dataset needs to reference those records by a predictable key.
- Don't auto-assign the enum extension value's ID — pin it explicitly inside
  `app-demo`'s own `idRanges`, same as any other object ID in this codebase.
- Don't add demo-data objects to the base app or the test app — they belong
  exclusively in the separate `app-demo` project, dependent on the base app,
  never the other way around.
- Don't guess at `app-demo`'s dependency list — copy the base app's own
  `dependencies` entries verbatim rather than adding them only when a missing
  symbol surfaces mid-Pass-2.
- Don't hardcode scenario role records (a specific customer/item number) in Pass
  1 — those only ever arrive via Pass 2's data-content brief.
- Don't write Pass 2 content before Pass 1 has compiled clean — the harness is
  the contract Pass 2's inserts target.
- Don't generate transactional data before its master/setup data exists in the
  same run.
- Don't duplicate master data on re-run — always check-then-insert.
- Don't put business logic that belongs in the app itself into a demo-data
  codeunit — demo data drives the app's existing processes, it never introduces
  new ones.
- Don't skip the smoke test "because the AL compiles" — compiling and
  successfully inserting data are different claims; only the smoke test proves
  the second one.
