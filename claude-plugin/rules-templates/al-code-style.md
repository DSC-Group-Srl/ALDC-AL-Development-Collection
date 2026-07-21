---
paths:
  - "**/*.al"
description: "AL Code structure, formatting, and folder organization guidelines for AL development"
---

# AL Code Style & Formatting Rules

These rules ensure consistent code structure and organization across AL projects, making code more maintainable and AI-assistant friendly.

## Style guidelines for AL code
- Always use PascalCase for variable and function names.
- Use PascalCase for object names (e.g., tables, pages, reports).
- Maintain a consistent indentation style (4 spaces, matching the official Microsoft AL formatter default so `Format Document` does not fight your code).

## Commonly used methods and patterns
- Temporary tables for performance optimization
- Use of events for extensibility

## Rule 1: Consistent Indentation and Formatting

### Intent
Maintain consistent code formatting to improve readability and enable better AI understanding of code structure. Use 4-space indentation consistently throughout your project — this matches the Microsoft AL Language extension formatter default, so a developer running `Format Document` will not reflow your code. Maintain consistent formatting within functions and procedures.

### Examples

```al
// Good example
procedure CalculateDiscount(Amount: Decimal; DiscountPct: Decimal): Decimal
begin
    if DiscountPct > 0 then
        exit(Amount * DiscountPct / 100);

    exit(0);
end;
```

## Rule 2: Feature-Based Folder Organization

### Intent
Organize code by business features rather than object types to improve maintainability and logical grouping. Use feature-based organization with `src/feature/subfeature/` structure and place shared components in `Common` or `Shared` folders.

### Examples

```
// Good example - Feature-based organization
src/
├── NoSeries/
│   ├── NoSeries.Table.al
│   ├── NoSeries.Page.al
│   └── NoSeriesSetup.Codeunit.al
├── Sales/
│   ├── Invoice/
│   │   ├── SalesInvoice.Page.al
│   │   └── SalesInvoicePosting.Codeunit.al
│   └── Order/
│       └── SalesOrder.Page.al
└── Common/
    ├── Helpers/
    │   └── DateHelper.Codeunit.al
    └── Interfaces/
        └── IPostable.Interface.al
```

```
// Bad example (avoid object-type segregation)
src/
├── Tables/
│   ├── NoSeries.Table.al
│   └── SalesHeader.Table.al
├── Pages/
│   ├── NoSeries.Page.al
│   └── SalesInvoice.Page.al
└── Codeunits/
    ├── NoSeriesSetup.Codeunit.al
    └── SalesInvoicePosting.Codeunit.al
```

## Rule 3: Code Documentation and Comments

### Intent
Provide clear documentation for procedures using XML documentation comments — global and local alike, including event publishers. Code should be self-documenting through clear naming, but every documented procedure still needs full, structured XML doc comments for API clarity. A doc comment must always include, alongside `<summary>`:
- `<param name="...">` for **every** parameter (including `var` parameters and event parameters like `IsHandled`)
- `<returns>` whenever the procedure has a return value
- `<remarks>` for anything beyond the core summary — callers, edge cases, scope limitations, "not yet implemented" notes, etc. Keep this prose out of `<summary>` so the summary stays a one-line statement of what the procedure does.

### Examples

```al
// Good example - XML documentation for global functions
codeunit 50100 "Base64 Convert"
{
    /// <summary>
    /// Converts the value of the input string to its equivalent string representation that is encoded with base-64 digits.
    /// </summary>
    /// <param name="String">The string to convert.</param>
    /// <returns>The string representation, in base-64, of the input string.</returns>
    procedure ToBase64(String: Text): Text
    begin
        exit(Base64ConvertImpl.ToBase64(String));
    end;

    /// <summary>
    /// Validates discount percentage against business rules.
    /// </summary>
    /// <param name="DiscountPct">The discount percentage to validate.</param>
    /// <remarks>Called by PostDocument before any ledger entries are created; a failed validation stops posting entirely.</remarks>
    procedure ValidateDiscountPercentage(DiscountPct: Decimal)
    begin
        if DiscountPct > 50 then
            Error('Discount cannot exceed 50% due to company policy');

        if DiscountPct < 0 then
            Error('Discount percentage cannot be negative');
    end;
}
```

```al
// Bad example (avoid summary-only prose that hides params/returns/callers instead of tagging them)
/// <summary>
/// Converts the value of the input string to its equivalent string representation that is encoded
/// with base-64 digits. String is the string to convert. Returns the base-64 representation.
/// </summary>
procedure ToBase64(String: Text): Text
begin
    exit(Base64ConvertImpl.ToBase64(String));
end;
```

```al
// Bad example (avoid inline comments for obvious operations)
procedure ValidateDiscountPercentage(DiscountPct: Decimal)
begin
    // Check if discount is greater than 50
    if DiscountPct > 50 then
        Error('Discount cannot exceed 50%');

    // Check if discount is less than 0
    if DiscountPct < 0 then
        Error('Discount percentage cannot be negative');
end;
```

## Rule 4: Modular and Reusable Code Structure

### Intent
Keep code modular and reusable to enhance maintainability and reduce duplication. Write small, focused procedures that do one thing well and use interfaces and patterns where appropriate.

### Examples

```al
// Good example - Modular approach
procedure PostDocument(var DocumentHeader: Record "Sales Header")
begin
    ValidateDocument(DocumentHeader);
    CalculateTotals(DocumentHeader);
    CreateLedgerEntries(DocumentHeader);
    UpdateStatus(DocumentHeader);
end;

local procedure ValidateDocument(var DocumentHeader: Record "Sales Header")
begin
    if DocumentHeader."No." = '' then
        Error('Document number cannot be empty');
end;

local procedure CalculateTotals(var DocumentHeader: Record "Sales Header")
begin
    DocumentHeader.CalcFields(Amount);
end;
```

```al
// Bad example (avoid monolithic procedures)
procedure PostDocument(var DocumentHeader: Record "Sales Header")
begin
    // All validation, calculation, and posting logic in one procedure
    // ... 200+ lines of mixed concerns
end;
```

## Rule 5: Namespaces Mirror the Feature-Folder Structure

### Intent
From AL **runtime 13.0** (Business Central 2024 wave 1 / BC 24) onward, every AL object supports a `namespace` declaration. The namespace is the **code-level counterpart of the feature-folder organization in Rule 2**: it must mirror the folder path, and — like the folders — it names **features, never object types**. Declare a `namespace` in **every** AL file, and add every `using` directive needed to bring referenced symbols into scope.

**Platform gate:** namespaces require runtime ≥ 13.0. On a project targeting an earlier runtime (check `app.json` → `runtime`), skip this rule — do **not** emit `namespace`/`using`.

### Structure
- **Root segment = the app name** (`app.json` → `name`, PascalCase, no spaces), then one segment per folder level, mirroring `src/Feature/SubFeature/`:
  `namespace [AppName].[Feature].[SubFeature];`
- The folder path and the namespace path are **speculative mirrors** of each other — a file in `src/Sales/Invoice/` declares `namespace [AppName].Sales.Invoice;`.
- **No object-type segments** — never `.Tables`, `.Pages`, `.Codeunits`. Segments name features, exactly like the folders (Rule 2).
- **`using` is mandatory** for every symbol referenced from outside the current namespace — base-app namespaces (e.g. `Microsoft.Sales.Document`, `System.Utilities`) and your own other feature namespaces. A missing `using` leaves the symbol out of scope and breaks the build.

### Examples

```al
// Good example - File: src/Sales/Invoice/SalesInvoicePosting.Codeunit.al
namespace Contoso.Sales.Invoice;

using Microsoft.Sales.Document;
using Microsoft.Foundation.NoSeries;
using Contoso.Sales.Setup;

codeunit 50100 "Sales Invoice Posting"
{
    procedure Post(var SalesHeader: Record "Sales Header")
    begin
        // ...
    end;
}
```

```al
// Bad example - namespace mirrors the object type instead of the feature (avoid)
namespace Contoso.Codeunits;          // object-type segment, not a feature

// Bad example - missing using for a referenced base object (breaks symbol scope)
namespace Contoso.Sales.Invoice;
// (no `using Microsoft.Sales.Document;`) -> Record "Sales Header" cannot be resolved
codeunit 50100 "Sales Invoice Posting"
{
    procedure Post(var SalesHeader: Record "Sales Header") begin end;
}
```

## Rule 6: Enum-Linked Interfaces Replace Case-Statement Dispatch

### Intent
When a procedure branches on an enum value to decide which of several distinct behaviors to run (one branch per action/type/mode), do not write a `case` statement that inlines each behavior. Instead, declare an `interface` with one procedure (e.g. `Execute`), have the enum `implements` that interface, and bind each enum value to its own implementing codeunit via that value's `Implementation` property. Adding a new value is then adding a new codeunit and one `Implementation` line — never touching the dispatch site or any other value's code. This app already establishes the pattern for period calculation (`"DSC NOT Default Period"` enum + interface + one codeunit per period type in `Source/Period/`); reuse it for any new one-of-N dispatch rather than reinventing a `case` statement.

Resolve the concrete implementation by assigning the enum value to an interface-typed variable (`IMyAction := MyEnumValue;`), then call its procedure — do not hand-roll a lookup.

### Examples

```al
// Good example - enum-linked interface, one codeunit per action
interface "Contoso Order Action"
{
    procedure Execute(var Order: Record "Sales Header")
}

enum 50100 "Contoso Order Action" implements "Contoso Order Action"
{
    Extensible = true;

    value(0; Confirm)
    {
        Implementation = "Contoso Order Action" = "Contoso Order Action Confirm";
    }
    value(1; Cancel)
    {
        Implementation = "Contoso Order Action" = "Contoso Order Action Cancel";
    }
}

codeunit 50101 "Contoso Order Action Confirm" implements "Contoso Order Action"
{
    procedure Execute(var Order: Record "Sales Header")
    begin
        // Confirm-specific logic only
    end;
}

// Dispatch site never changes when a new action is added:
procedure RunAction(var Order: Record "Sales Header"; Action: Enum "Contoso Order Action")
var
    OrderAction: Interface "Contoso Order Action";
begin
    OrderAction := Action;
    OrderAction.Execute(Order);
end;
```

```al
// Bad example (avoid a case statement that inlines every action's logic)
local procedure RunAction(var Order: Record "Sales Header"; Action: Enum "Contoso Order Action")
begin
    case Action of
        Action::Confirm:
            begin
                // Confirm-specific logic inlined here
            end;
        Action::Cancel:
            begin
                // Cancel-specific logic inlined here
            end;
        // Every new action means a new branch here, growing one shared procedure forever.
    end;
end;
```

## Rule 7: Facades for Not-Yet-Built Features, Never "NotImplemented" Stubs

### Intent
When a feature (or one branch of a multi-action dispatch, see Rule 6) is not built yet, do not expose that fact in the public surface — no procedure named `RaiseXNotImplemented`, no caller-visible flag for "this one isn't real yet." Callers of a facade must see the exact same shape (procedure name, parameters, return value) whether the real feature exists or not, so that shipping the real implementation later never requires touching any caller. Build the facade with its final, permanent public signature, and have it delegate internally to a stub (an event with no subscriber yet, or a clear error) as an implementation detail. When the real feature ships, only the facade's body changes — swap the stub call for the real delegation — the signature and every call site stay untouched.

This composes directly with Rule 6: in an enum-linked interface dispatch, the not-yet-built action's implementing codeunit *is* the facade — its `Execute` procedure has the same signature as every other action's, and only its body currently raises a "not implemented" error/event instead of doing the real work.

### Examples

```al
// Good example - facade with a stable public surface, stub hidden inside
codeunit 50102 "Contoso Draft Action" implements "Contoso Order Action"
{
    // Same Execute signature every other action implements -- callers can't tell this one is a stub.
    procedure Execute(var Order: Record "Sales Header")
    begin
        CreateDraft(Order);
    end;

    local procedure CreateDraft(var Order: Record "Sales Header")
    var
        IsHandled: Boolean;
        NotAvailableErr: Label 'Draft creation is not available yet.';
    begin
        OnCreateDraft(Order, IsHandled);
        if IsHandled then
            exit;

        Error(NotAvailableErr);
    end;

    [IntegrationEvent(false, false)]
    procedure OnCreateDraft(var Order: Record "Sales Header"; var IsHandled: Boolean)
    begin
    end;
}
```

```al
// Bad example (avoid naming/branding the public surface around "not implemented")
codeunit 50102 "Contoso Draft Action" implements "Contoso Order Action"
{
    procedure Execute(var Order: Record "Sales Header")
    begin
        RaiseDraftNotImplemented(Order); // caller-visible name announces the gap instead of hiding it
    end;

    procedure RaiseDraftNotImplemented(var Order: Record "Sales Header")
    begin
        Error('Draft creation is not available yet.');
    end;
    // When the real feature ships, every caller of RaiseDraftNotImplemented must be found and changed.
}
```
