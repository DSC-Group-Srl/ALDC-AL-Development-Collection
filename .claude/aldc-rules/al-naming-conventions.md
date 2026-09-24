---
paths:
  - "**/*.al"
description: "Comprehensive naming conventions for AL files, objects, variables, and functions"
---

# Naming Conventions Rules

Consistent naming conventions improve code readability, maintainability, and help AI assistants understand code structure and intent.

## Rule 1: Object Naming Conventions

### Intent
Use consistent naming patterns for all AL objects to improve discoverability and maintain professional standards. Use PascalCase for object names (tables, pages, reports, codeunits) and meaningful, descriptive names that clearly indicate the object's purpose. Object names must not exceed 30 characters total, with a maximum of 26 characters for the name itself to reserve space for prefixes/affixes (3 characters + 1 space).

### Examples

```al
// Good examples (within 26 character limit)
table 50100 "Customer Ledger Entry"     // 20 chars
page 50101 "Sales Invoice"              // 13 chars
codeunit 50102 "Sales Invoice Posting"  // 21 chars
report 50103 "Customer Statement"       // 18 chars
```

```al
// Bad examples (avoid abbreviations, unclear names, or length violations)
table 50100 "CustLE"                           // Too abbreviated
page 50101 "SalesInv"                          // Too abbreviated
table 50104 "Very Long Customer Ledger Entry" // 32 chars - exceeds limit
codeunit 50102 "SIPoster"                      // Unclear abbreviation
```

## Rule 2: File Naming Conventions

### Intent
Establish consistent file naming patterns that clearly identify object types and facilitate organized development. Use pattern `<ObjectName>.<ObjectType>.al` and maintain consistency across all file names. Ensure file names are descriptive and match the AL object name within the files.

### Examples

```al
// Good examples
NoSeries.Page.al
NoSeries.Table.al
NoSeriesErrorsImpl.Codeunit.al
NoSeriesSetup.Codeunit.al
CustomerCard.Page.al
SalesHeader.Table.al
PostSalesInvoice.Codeunit.al
ItemLedgerEntry.Report.al
InventorySetup.PageExt.al
SalesHeader.TableExt.al

// For implementations and interfaces
INoSeries.Interface.al
NoSeriesImpl.Codeunit.al

// For test files
NoSeriesTests.Codeunit.al
SalesPostingTests.Codeunit.al
```

## Rule 3: Variable and Function Naming

### Intent
Use consistent naming conventions for variables and functions to improve code readability. Use PascalCase for variable and function names, descriptive names that clearly indicate purpose, and avoid abbreviations unless they are well-known business terms. Use consistent parameter naming in procedures.

### Examples

```al
// Good examples - Variables
var
  CustomerLedgerEntry: Record "Cust. Ledger Entry";
  TotalAmount: Decimal;
  DiscountPercentage: Decimal;
  IsValidTransaction: Boolean;
```

```al
// Good examples - Functions
procedure CalculateCustomerBalance(CustomerNo: Code[20]): Decimal
procedure ValidateSalesDocument(var SalesHeader: Record "Sales Header")
procedure UpdateInventoryQuantity(ItemNo: Code[20]; Quantity: Decimal)
```

## Rule 4: Parameter Naming in Event Subscribers

### Intent

**Subscriber parameter names are not a style choice — copy them verbatim from the publisher.** AL binds each subscriber parameter to the publisher parameter *of the same name*, so a renamed parameter does not bind. Descriptive-naming rules that apply to locals do **not** apply here: `Rec`, `xRec`, `Sender`, `RunTrigger` and the publisher's own parameter names are reproduced exactly. Microsoft's own documented example keeps `var Rec: Record Customer` in a page-trigger subscriber.

A subscriber **may** declare fewer parameters than the publisher, omitting any it does not use from any position, and may list the ones it keeps in a different order. That is valid AL, not a signature mismatch.

Where the useful half of "descriptive naming" still applies: the **procedure name**, which follows Microsoft's `[Action][Event]` convention. When the body reads badly with a bare `Rec`, introduce a descriptive local alias inside the procedure — never rename the parameter.

> Governing knowledge: `microsoft/knowledge/style/event-subscriber-param-names-match-publisher.md` (BCQuality). Related compiler diagnostics: `AL0419` (subscriber missing a parameter), `AL0284` (parameter type mismatch), `AL0288` (`var` only where the publisher is `var`).

### Examples

```al
// Good example - publisher parameter names reproduced verbatim; descriptive procedure name
[EventSubscriber(ObjectType::Table, Database::"Sales Header", 'OnBeforeInsertEvent', '', false, false)]
local procedure AddDefaultValuesOnBeforeInsertSalesHeader(var Rec: Record "Sales Header"; RunTrigger: Boolean)
var
  SalesHeader: Record "Sales Header";   // descriptive alias for readability, if the body needs it
begin
  SalesHeader := Rec;
  // Event handling logic
end;

// Good example - omitting a parameter the handler does not use is valid
[EventSubscriber(ObjectType::Table, Database::Customer, 'OnBeforeModifyEvent', '', false, false)]
local procedure CheckBalanceOnBeforeModifyCustomer(var Rec: Record Customer)
begin
  // xRec and RunTrigger omitted on purpose - the handler does not need them
end;
```

```al
// Bad example - renaming publisher parameters. Does not bind; the build breaks.
[EventSubscriber(ObjectType::Table, Database::"Sales Header", 'OnBeforeInsertEvent', '', false, false)]
local procedure AddDefaultValuesOnBeforeInsertSalesHeader(var SalesHeader: Record "Sales Header"; RunTrigger: Boolean)
begin
  // 'SalesHeader' matches no publisher parameter
end;
```

## Rule 5: Interface and Implementation Naming

### Intent
Clearly distinguish between interfaces and their implementations using consistent naming patterns. Prefix interfaces with "I" (e.g., `INoSeries`), use "Impl" suffix for implementation codeunits, and keep interface and implementation names closely related. Ensure names stay within the 26-character limit.

### Examples

```al
// Good examples (within character limits)
// Interface file: ICustomerService.Interface.al
interface ICustomerService
{
    procedure GetCustomerBalance(CustomerNo: Code[20]): Decimal;
}

// Implementation file: CustomerServiceImpl.Codeunit.al
codeunit 50100 "Customer Service Impl" implements ICustomerService
{
    procedure GetCustomerBalance(CustomerNo: Code[20]): Decimal
    begin
        // Implementation logic
    end;
}
```

## Rule 6: Namespace Naming

### Intent
Namespaces (AL runtime ≥ 13.0 / BC 24+) name **features**, mirroring the feature-folder structure. This rule fixes the *naming* shape; for the folder-mirroring requirement, the `using` handling and the runtime gate see **al-code-style.md Rule 5**.

- **Root segment = the app name** (`app.json` → `name`), PascalCase, no spaces.
- **Each following segment = a feature/subfeature**, PascalCase, mirroring the folder path: `[AppName].[Feature].[SubFeature]`.
- **Never** a segment that names an object type (`.Table`, `.Pages`, `.Report`, `.Codeunits`).
- Keep segments descriptive and aligned with the folder names, so the folder path and the namespace path stay speculative mirrors of each other.

### Examples

```al
// Good examples
namespace Contoso.Sales.Invoice;      // src/Sales/Invoice/
namespace Contoso.Warehouse.Picking;  // src/Warehouse/Picking/
```

```al
// Bad examples
namespace Contoso.Codeunits;          // object type, not a feature
namespace contoso.sales;              // not PascalCase
namespace Sales.Invoice;              // missing app-name root segment
```
