---
name: skill-demo-data
description: "AL demo/sample data generation for Business Central. Prefers plugging directly into Microsoft's real Contoso Demo Tool (Enum/Interface 'Contoso Demo Data Module', Page 'Contoso Demo Tool') via the Contoso Coffee Demo Dataset dependency; falls back to a bespoke module-scoped Configure + Generate page/table/enum only when that dependency isn't viable. Use when building or extending demo data for an app, a 'Demo Tool' page, Setup/Master/Transactional demo-data codeunits, or scenario-driven sample data."
---

# Skill: Demo Data Generation (Contoso-style)

## Purpose

Give an AL app a customizable, regenerable demo dataset, structured the same way
Microsoft structures Contoso Demo Data (the Contoso Coffee apps): a config page
listing **modules**, each with a **Configure** action (map real records to
scenario roles) and a **Create Demo Data** action (generate setup, master, and
transactional records for a documented set of walkthrough scenarios).

**Two ways to get this shape**: plug straight into Microsoft's own already-shipped
Contoso Demo Tool (preferred — see "Decision" below), or build a bespoke
equivalent when that isn't viable. Don't default to bespoke without checking the
decision first — that's the exact mistake this skill previously invited.

This is the implementation skill `al-demo-architect` loads after its demo-data
plan document is approved. It is not a documentation skill — `skill-functional-docfx`
and `skill-aldoc` own written documentation; this skill owns the AL objects that
generate data.

## When to Load

- Building the AL objects for an approved `{req_name}.demo-data-plan.md`.
- Adding a new module to an existing demo-data toolkit (incremental mode).
- Any request to "generate sample data", "seed demo records", "add a Contoso-style
  demo tool" for a custom app.

## Decision: plug into Microsoft's real Contoso Demo Tool, or build bespoke

**Default to the real integration below.** Microsoft already ships a working
module registry, config page, and dispatch engine — `Table`/`Page "Contoso Demo
Tool"`, `Enum`/`Interface "Contoso Demo Data Module"`, `Codeunit "Generate Contoso
Demo Data"` — in the `Contoso Coffee Demo Dataset` app (id
`5a0b41e9-7a42-4123-d521-2265186cfb31`, namespace `Microsoft.DemoTool`). For an
app that can take a dependency on it, building a second, bespoke Demo Tool
page/table/enum (Core Shape §1 below) duplicates infrastructure Microsoft already
maintains and gives the developer a UI that doesn't show up alongside every other
module they already know.

Use the **real integration** (`Real Integration` section below) when:
- The target app runs on Business Central Online / SaaS, and
- It's acceptable for the app to depend on `Contoso Coffee Demo Dataset` (it's
  available from AppSource/the marketplace in the target environments).

Fall back to the **bespoke Core Shape** (§1–§7 below) only when the real
integration isn't viable — e.g. an on-prem target where that Microsoft app can't
be guaranteed present. Record which path was taken, and why, in the demo-data
plan doc's `## Integration Approach` section before generating anything; don't
default to bespoke out of habit.

Sections 2–7 of the bespoke Core Shape below (Configure, Preview, the
Setup/Master/Transactional split, scenario docs, Job Queue, the smoke test) are
**not bespoke-only** — under the real integration they still apply, just invoked
from the interface's `RunConfigurationPage()`/`Create*Data()` methods instead of
a bespoke page's actions. Only §1 (the Demo Tool page/table itself) is skipped
when the real integration is used.

## Real Integration — plugging into Microsoft's Contoso Demo Tool

Confirmed against `Contoso Coffee Demo Dataset` (Microsoft, app id
`5a0b41e9-7a42-4123-d521-2265186cfb31`), namespace `Microsoft.DemoTool`. There is
no narrative MS Learn documentation of this AL-level contract — MS Learn only
covers the end-user Configure/Generate workflow. Ground every detail here against
the live symbols (`al_symbolsearch`) before writing AL, since ordinals and
signatures can drift across BC versions.

### The contract

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
   Build one per module for whatever Configure-time role-mapping it needs; this
   is exactly Core Shape §2's "Per-module Configure" pattern, just invoked from
   `RunConfigurationPage()` instead of a bespoke `Configure()` action.

### What to build for a new module

1. **Add the dependency** in `app.json`:
   ```json
   { "id": "5a0b41e9-7a42-4123-d521-2265186cfb31", "name": "Contoso Coffee Demo Dataset", "publisher": "Microsoft", "version": "<matching major>" }
   ```
   Download symbols (`al_downloadsymbols`), add the project to al-mcp
   (`al_addproject`), and confirm with `al_symbolsearch` (`query: "Contoso Demo
   Data Module"`, `scope: "dependencies"`) before writing any AL.

2. **Enum extension** — exactly one new value, with an ID pinned explicitly from
   the app's own `idRanges` (never let AL auto-assign it):
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

3. **Interface-implementing codeunit** — one per module, dispatching into real
   generation logic kept in separate helper codeunits (small, focused
   procedures, same as everywhere else):
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
           DemoDataMobile.CreateMasterData();
       end;

       procedure CreateTransactionalData()
       begin
           DemoDataMobile.CreateTransactionalData();
       end;

       procedure CreateHistoricalData()
       begin
           // no historical documents in this app — empty is a valid implementation
       end;

       var
           DemoDataCommon: Codeunit "DSC HR Demo Data - Common";
           DemoDataMobile: Codeunit "DSC HR Demo Data - Mobile";
   }
   ```

4. **`GetDependencies()` is a real design decision, not boilerplate.** Only list
   `"Common Module"` unless the module deliberately wants its data generated
   *after*, and layered on top of, another module's data. In particular: **do
   not** depend on `"Human Resources Module"` just because the app is
   HR-flavored — that ordinal is Microsoft's own base-BC HR demo data, with
   employee identities the app doesn't control. If the app needs a specific,
   predictable roster (specific Nos., names, an approver persona another app's
   demo data will reference by name), keep the module self-contained and
   generate its own roster in `CreateMasterData()`.

5. **Nothing else is needed.** No bespoke Demo Tool page, no bespoke
   module-registry table, no bespoke module enum, no bespoke "Preview" action —
   Microsoft's real page already provides Configure / Generate / Generate Setup
   once the enum value and interface implementation exist. (An internal
   `Preview()` helper on the module's own setup codeunit — Core Shape §3, called
   from `RunConfigurationPage()`'s setup page or from tests before
   `CreateMasterData()` actually writes — is still fine to keep for the "resolve
   and report before writing" discipline; it's just not a page action
   Microsoft's UI calls.)

### Mapping onto the bespoke Core Shape sections below

| Bespoke section | Real-integration equivalent |
|---|---|
| §1 Demo Tool page | Skip — Microsoft's `Page "Contoso Demo Tool"` already lists the module once the enum value exists. |
| §2 Per-module Configure | Still applies — build a dedicated setup table/page, invoked from `RunConfigurationPage()`. |
| §3 Preview | Keep as an internal helper if useful; not a real interface method. |
| §4 Setup/Master/Transactional split | Maps directly onto `CreateSetupData()`/`CreateMasterData()`/`CreateTransactionalData()`, plus a 4th stage, `CreateHistoricalData()`, for backdated/archived documents. |
| §5 Scenario documentation | Unchanged — keep in the demo-data plan doc. |
| §6 Job Queue integration | Unchanged. |
| §7 Smoke test | Unchanged in spirit — call the interface-implementing codeunit's methods directly, or via `Codeunit.Run(Codeunit::"Generate Contoso Demo Data", TempRec)`, rather than a bespoke table's `Generate()`. |

### Real-integration anti-patterns

- Don't build a bespoke Demo Tool page/table/enum/interface for an app that
  could take a dependency on `Contoso Coffee Demo Dataset` — check the decision
  section above first.
- Don't reuse or assume you can redirect an already-declared enum value's
  `Implementation` (e.g. `"Human Resources Module"`) — add a new value instead.
- Don't let `GetDependencies()` casually include a domain module (like Human
  Resources) whose demo data isn't under the app's control, if a downstream
  app/dataset needs to reference those records by a predictable key.
- Don't auto-assign the enum extension value's ID — pin it explicitly inside the
  app's own `idRanges`, same as any other object ID in this codebase.

## Bespoke Core Shape (fallback — real integration not viable)

### 1. The Demo Tool page

One list/worksheet page per app, one line per **module**. Each line carries at
least: module name, a status (Not Configured / Configured / Generated), and two
actions:

```al
page 50100 "<App> Demo Tool"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Administration;
    SourceTable = "<App> Demo Data Module";

    layout
    {
        area(content)
        {
            repeater(Modules)
            {
                field(Name; Rec.Name) { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(processing)
        {
            action(Configure)
            {
                ApplicationArea = All;
                Image = Setup;
                trigger OnAction()
                begin
                    Rec.Configure();
                end;
            }
            action(CreateDemoData)
            {
                ApplicationArea = All;
                Image = CreateForm;
                trigger OnAction()
                begin
                    Rec.Generate();
                end;
            }
        }
    }
}
```

`"<App> Demo Data Module"` is a table (or, for a small app, an enum-backed
temporary record) with one row per module and a `RunObject`/enum dispatch to the
module's Setup codeunit — same one-of-N branching rule as everywhere else
(`rules-floor-cheatsheet.md`: enum-linked interface, not a growing `case`, once
there are more than a couple of modules).

### 2. Per-module Configure

Configure never generates data — it only captures **which existing records** play
which scenario role (a customer, a location, an item with tracking, a starting
year, a country/region for localization). Store these as setup fields on a
per-module setup table. Populate the plan's `Developer Customization Input`
answers here first; fall back to `FindFirst`/library-style discovery only for
fields the developer left blank, and only from data that already exists in the
company — never invent master data during Configure.

### 3. Preview — resolve and report before writing any AL

Before `al-demo-architect` generates a module's codeunits, it needs to *show* the
developer what Configure would actually do — not just describe the shape in
prose. Give the setup table (or a temporary record built for this purpose) a
`Preview()` procedure that:

- Resolves every role field the developer left blank in the plan's
  `Developer Customization Input`, the same way Configure would (existing
  records only, never invented).
- Returns a structured result: role → resolved record (or "not found"), plus
  the record counts Generate is about to insert, split by Setup / Master /
  Transactional.

```al
procedure Preview(): Text
var
    PreviewText: TextBuilder;
begin
    // resolve each blank role via FindFirst-style discovery, never invent
    // append one line per role: "<Role>: <Record> (auto-selected)" or "<Role>: NOT FOUND"
    // append expected counts: "Setup: N, Master: N, Transactional: N"
    exit(PreviewText.ToText());
end;
```

`al-demo-architect` calls this, shows the result to the developer, and only
then writes the module's Generate codeunit. A role that resolves to "not
found" is never silently skipped — it blocks that module until the developer
supplies a value.

### 4. Per-module Generate — Setup / Master / Transactional split

Mirror Contoso's own layering inside the module's codeunit(s):

1. **Setup data** — number series, posting groups, templates — whatever the
   scenarios need to exist before any document can post. Idempotent: re-running
   Generate must not duplicate setup rows.
2. **Master data** — customers, vendors, items, resources, BOMs — created only if
   they don't already exist (check by a stable key, e.g. a "DEMO-" number-series
   prefix, before inserting).
3. **Transactional data** — the actual documents/journals that make the scenario
   demonstrable (a posted sales order, a firm-planned production order, a service
   contract). Batch the writes: compute the full data first, then insert — never
   accumulate via repeated single-record round trips (`al-performance.md`).

```al
codeunit 50101 "<App> Demo Data - <Module>"
{
    trigger OnRun()
    begin
        InsertSetupData();
        InsertMasterData();
        InsertTransactionalData();
    end;

    local procedure InsertSetupData()
    begin
        // idempotent — check existence before insert
    end;
    // ...
}
```

### 5. Scenario documentation

Every module ships a short list of numbered walkthrough scenarios (what a user
does once the data exists) — this is what turns "there is data" into "there is
something to demo". Keep this list in the demo-data plan doc
(`{req_name}.demo-data-plan.md`), not duplicated into code comments.

### 6. Optional: Job Queue integration

If the app has recurring processes worth demonstrating (a batch job, a
reconciliation), offer a toggle (default off, matching Contoso's own default-on-
but-configurable pattern only when genuinely useful) to create the matching Job
Queue Entry as part of Generate — never force it.

### 7. Smoke test — prove Generate actually inserts data

A module isn't done when it compiles — compiling proves the AL is valid, not
that Configure resolves correctly or that Generate's check-then-insert logic
actually works against a real company. Every module gets a minimal test
codeunit alongside its Generate codeunit, following `skill-testing`'s
Given/When/Then shape and using standard `Library-*` codeunits for setup
(never hand-rolled company/test data):

```al
codeunit 50102 "<App> Demo Data - <Module> Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure GenerateInsertsExpectedRecords()
    var
        ModuleSetup: Record "<App> Demo Data Module";
        Assert: Codeunit "Library Assert";
    begin
        // Given: an empty/clean company and a configured module (Library-driven setup)
        // When: Generate runs
        ModuleSetup.Get('<Module>');
        ModuleSetup.Generate();

        // Then: the expected setup/master/transactional records exist
        Assert.RecordCount(<MasterTable>, <ExpectedCount>);
    end;

    [Test]
    procedure GenerateIsIdempotent()
    begin
        // Given: a module already generated once
        // When: Generate runs again
        // Then: no duplicate master/setup records are created
    end;
}
```

`al-demo-architect` runs these via `al_run_tests` against a disposable sandbox
as its "plug it in" verification step — this is what actually proves the
dataset lands, not the compile step.

## Incremental Regeneration

A module already marked **Generated** must not be silently re-run and duplicated.
Generate should check the module's status first; re-running an already-generated
module either no-ops with a message or requires an explicit "Regenerate" — never
happens as a side effect of generating a *different, new* module.

## Anti-patterns

- Don't hardcode scenario role records (a specific customer/item number) — always
  route through the module's Configure setup fields.
- Don't generate transactional data before its master/setup data exists in the
  same run.
- Don't duplicate master data on re-run — always check-then-insert.
- Don't put business logic that belongs in the app itself into a demo-data
  codeunit — demo data drives the app's existing processes, it never introduces
  new ones.
- Don't generate a module's codeunits before its Preview has been shown and
  confirmed — a "not found" role resolved silently becomes a runtime error
  the developer only discovers when they click Generate themselves.
- Don't skip the smoke test "because the AL compiles" — compiling and
  successfully inserting data are different claims; only the smoke test proves
  the second one.
