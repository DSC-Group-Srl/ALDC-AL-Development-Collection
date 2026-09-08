---
name: skill-demo-data
description: "AL demo/sample data generation patterns for Business Central, following the same module-scoped Configure + Generate shape as Microsoft's own Contoso Demo Data tool. Use when building or extending a 'Demo Tool' page, Setup/Master/Transactional demo-data codeunits, or scenario-driven sample data for an app."
---

# Skill: Demo Data Generation (Contoso-style)

## Purpose

Give an AL app a customizable, regenerable demo dataset, structured the same way
Microsoft structures Contoso Demo Data (the Contoso Coffee apps): a config page
listing **modules**, each with a **Configure** action (map real records to
scenario roles) and a **Create Demo Data** action (generate setup, master, and
transactional records for a documented set of walkthrough scenarios).

This is the implementation skill `al-demo-architect` loads after its demo-data
plan document is approved. It is not a documentation skill — `skill-functional-docfx`
and `skill-aldoc` own written documentation; this skill owns the AL objects that
generate data.

## When to Load

- Building the AL objects for an approved `{req_name}.demo-data-plan.md`.
- Adding a new module to an existing demo-data toolkit (incremental mode).
- Any request to "generate sample data", "seed demo records", "add a Contoso-style
  demo tool" for a custom app.

## Core Shape

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
