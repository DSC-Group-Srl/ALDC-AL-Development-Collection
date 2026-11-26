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

Good: Within 26 character limit.

```al
table 50100 "Customer Ledger Entry"
page 50101 "Sales Invoice"
codeunit 50102 "Sales Invoice Posting"
report 50103 "Customer Statement"
```

Bad: Abbreviations, unclear names, or length violations.

```al
table 50100 "CustLE"
page 50101 "SalesInv"
table 50104 "Very Long Customer Ledger Entry"
codeunit 50102 "SIPoster"
```

- `table 50104 "Very Long Customer Ledger Entry"` — 32 chars - exceeds limit

## Rule 2: File Naming Conventions

### Intent
Establish consistent file naming patterns that clearly identify object types and facilitate organized development. Use pattern `<ObjectName>.<ObjectType>.al` and maintain consistency across all file names. Ensure file names are descriptive and match the AL object name within the files.

### Examples

Good:

```al
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

INoSeries.Interface.al
NoSeriesImpl.Codeunit.al

NoSeriesTests.Codeunit.al
SalesPostingTests.Codeunit.al
```

## Rule 3: Variable and Function Naming

### Intent
Use consistent naming conventions for variables and functions to improve code readability. Use PascalCase for variable and function names, descriptive names that clearly indicate purpose, and avoid abbreviations unless they are well-known business terms. Use consistent parameter naming in procedures.

### Examples

Good: Variables.

```al
var
  CustomerLedgerEntry: Record "Cust. Ledger Entry";
  TotalAmount: Decimal;
  DiscountPercentage: Decimal;
  IsValidTransaction: Boolean;
```

Good: Functions.

```al
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

Good: Publisher parameter names reproduced verbatim; descriptive procedure name.

```al
[EventSubscriber(ObjectType::Table, Database::"Sales Header", 'OnBeforeInsertEvent', '', false, false)]
local procedure AddDefaultValuesOnBeforeInsertSalesHeader(var Rec: Record "Sales Header"; RunTrigger: Boolean)
var
  SalesHeader: Record "Sales Header";
begin
  SalesHeader := Rec;
end;
```

- `SalesHeader: Record "Sales Header";` — descriptive alias for readability, if the body needs it

Good: Omitting a parameter the handler does not use is valid.

```al
[EventSubscriber(ObjectType::Table, Database::Customer, 'OnBeforeModifyEvent', '', false, false)]
local procedure CheckBalanceOnBeforeModifyCustomer(var Rec: Record Customer)
begin
end;
```

Bad: Renaming publisher parameters. Does not bind; the build breaks.

```al
[EventSubscriber(ObjectType::Table, Database::"Sales Header", 'OnBeforeInsertEvent', '', false, false)]
local procedure AddDefaultValuesOnBeforeInsertSalesHeader(var SalesHeader: Record "Sales Header"; RunTrigger: Boolean)
begin
end;
```

- 'SalesHeader' matches no publisher parameter

## Rule 5: Interface and Implementation Naming

### Intent
Clearly distinguish between interfaces and their implementations using consistent naming patterns. Prefix interfaces with "I" (e.g., `INoSeries`), use "Impl" suffix for implementation codeunits, and keep interface and implementation names closely related. Ensure names stay within the 26-character limit.

### Examples

Good: Within character limits.

```al
interface ICustomerService
{
    procedure GetCustomerBalance(CustomerNo: Code[20]): Decimal;
}

codeunit 50100 "Customer Service Impl" implements ICustomerService
{
    procedure GetCustomerBalance(CustomerNo: Code[20]): Decimal
    begin
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

Good: each namespace mirrors its folder (`src/Sales/Invoice/`, `src/Warehouse/Picking/`).

```al
namespace Contoso.Sales.Invoice;
namespace Contoso.Warehouse.Picking;
```

Bad: an object type instead of a feature, not PascalCase, missing the app-name root segment.

```al
namespace Contoso.Codeunits;
namespace contoso.sales;
namespace Sales.Invoice;
```
