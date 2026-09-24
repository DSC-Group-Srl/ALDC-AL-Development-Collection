---
paths:
  - "**/*.al"
description: "Performance optimization guidelines and best practices for AL development"
---

# AL Performance Optimization Rules

These rules focus on writing performant AL code that scales well and provides optimal user experience in Business Central environments.

## AL Performance Guidelines Summary

- Always analyze performance impact when adding new features
- Optimize queries by filtering data as early as possible
- Avoid unnecessary loops; use set-based operations when possible
- Use SetLoadFields to minimize data retrieval
- Use temporary tables, dictionaries, or lists for temporary data storage
- Avoid `SetCurrentKey` unless a specific row ordering is actually required

## Rule 1: Early Data Filtering and Query Optimization

### Intent

Optimize queries by filtering data as early as possible to reduce data transfer and processing overhead. Apply filters before processing records, use appropriate table keys and sorting, minimize the amount of data retrieved from the database, and use SetRange and SetFilter methods effectively.

### Examples

```al
// Good example - Early filtering
procedure GetNumberOfCustomersByCity(CityFilter: Text): Integer
var
  Customer: Record Customer;
begin
  Customer.SetRange(City, CityFilter);
  Customer.SetRange(Blocked, Customer.Blocked::" ");
  if Customer.FindSet() then
    repeat
      // Process only filtered customers
    until Customer.Next() = 0;

  exit(Customer.Count);
end;
```

```al
// Bad example (avoid processing all records)
procedure GetNumberOfCustomersByCity(CityFilter: Text): Integer
var
  Customer: Record Customer;
  Count: Integer;
begin
  if Customer.FindSet() then
    repeat
      // Processing all customers then filtering
      if (Customer.City = CityFilter) and (Customer.Blocked = Customer.Blocked::" ") then
        Count += 1;
    until Customer.Next() = 0;

  exit(Count);
end;
```

## Rule 2: Use SetLoadFields for Optimal Data Retrieval

### Intent

Use `SetLoadFields` to minimise data retrieval by loading only the normal fields the code actually reads. Call it immediately before the `Get`/`FindSet`/`FindFirst` it governs. Do **not** list primary-key fields, `SystemId`, system audit fields, or fields you filter on — the platform includes all of those automatically.

**Statement order is a readability preference, not a defect.** `SetLoadFields` placed ahead of `SetRange`/`SetFilter` materialises exactly the same columns as the reverse order. Put it after the filters so a reader can see which read it governs — but never report the other order as a performance problem.

Skip `SetLoadFields` entirely when:

- the loop body performs a documented **full-load** operation on the same record variable — `Insert`, `Delete`, `Rename`, `TransferFields`, or a copy into a temporary table. Those force a just-in-time load of the missing fields, which costs more than reading the full row up front. (`Modify` is **not** in that list: a `Modify` touching only loaded fields is safe on a partial record.)
- the table has few fields (under ten), the code reads most of them (above 60 %), the loop runs ten or fewer iterations, or the table is a singleton setup table or a temporary table.

`SetLoadFields` only narrows `FieldClass = Normal`; it does not affect FlowFields or FlowFilters. For report dataitems use `AddLoadFields` in `OnPreDataItem` instead.

> Governing knowledge: `microsoft/knowledge/performance/use-setloadfields-for-partial-records.md` and `skip-setloadfields-on-write-and-transferfields.md` (BCQuality).

### Examples

```al
// Good example - immediately before the read it governs; filtered field not listed
Item.SetRange("Third Party Item Exists", false);
Item.SetLoadFields("Item Category Code");
Item.FindFirst();
```

```al
// Also correct - same projection, just less readable. Not a finding.
Item.SetLoadFields("Item Category Code");
Item.SetRange("Third Party Item Exists", false);
Item.FindFirst();
```

```al
// Bad example - partial record feeding a full-load operation
Item.SetLoadFields("Item Category Code");
if Item.FindSet() then
  repeat
    TempItem := Item;      // copy into a temporary table forces a JIT load of every field
    TempItem.Insert();
  until Item.Next() = 0;
```

## Rule 3: Use Temporary Tables, Dictionaries, and Lists for Performance

### Intent

Leverage temporary tables, dictionaries, and lists to improve performance in read-heavy scenarios and complex data processing. Use temporary tables for structured record data, dictionaries for key-value pairs, and lists for simple collections that are only temporarily needed.

### Examples

```al
// Good example - Using temporary tables for structured data
procedure ProcessSalesData(var TempSalesLine: Record "Sales Line" temporary)
var
  SalesLine: Record "Sales Line";
begin
  // Load data into temporary table once
  if SalesLine.FindSet() then
    repeat
      TempSalesLine := SalesLine;
      TempSalesLine.Insert();
    until SalesLine.Next() = 0;

  // Process temporary data multiple times without database hits
  ProcessDiscounts(TempSalesLine);
  CalculateTotals(TempSalesLine);
  ValidateInventory(TempSalesLine);
end;
```

```al
// Good example - Using dictionaries for key-value temporary data
procedure CacheCustomerData()
var
  Customer: Record Customer;
  CustomerCache: Dictionary of [Code[20], Text];
begin
  if Customer.FindSet() then
    repeat
      CustomerCache.Add(Customer."No.", Customer.Name);
    until Customer.Next() = 0;

  // Use cached data for lookups
  ProcessOrdersWithCache(CustomerCache);
end;
```

```al
// Good example - Using lists for simple collections
procedure GetBlockedCustomers(): List of [Code[20]]
var
  Customer: Record Customer;
  BlockedCustomers: List of [Code[20]];
begin
  Customer.SetRange(Blocked, Customer.Blocked::All);
  if Customer.FindSet() then
    repeat
      BlockedCustomers.Add(Customer."No.");
    until Customer.Next() = 0;

  exit(BlockedCustomers);
end;
```

## Rule 4: Avoid Unnecessary Loops - Use Set-Based Operations

### Intent

Minimize looping operations and favor set-based approaches when possible to improve performance. Use built-in aggregation methods (CalcSums, CalcFields), leverage SQL-based operations through AL, avoid nested loops when possible, and use batch operations for multiple record updates.

### Examples

```al
// Good example - Set-based operation
procedure GetTotalSalesAmount(CustomerNo: Code[20]): Decimal
var
  CustLedgerEntry: Record "Cust. Ledger Entry";
begin
  CustLedgerEntry.SetRange("Customer No.", CustomerNo);
  CustLedgerEntry.CalcSums(Amount);
  exit(CustLedgerEntry.Amount);
end;
```

```al
// Bad example (avoid manual loops for aggregation)
procedure GetTotalSalesAmount(CustomerNo: Code[20]): Decimal
var
  CustLedgerEntry: Record "Cust. Ledger Entry";
  TotalAmount: Decimal;
begin
  CustLedgerEntry.SetRange("Customer No.", CustomerNo);
  if CustLedgerEntry.FindSet() then
    repeat
      TotalAmount += CustLedgerEntry.Amount;
    until CustLedgerEntry.Next() = 0;

  exit(TotalAmount);
end;
```

## Rule 5: Performance Impact Analysis

### Intent

Always analyze and consider performance impact when adding new features or modifying existing code. While the AL compiler does not have direct access to performance profilers, you should implement performance-optimal code patterns from the start and consider scalability implications of code changes.

### Examples

```al
// Good example - Performance-conscious implementation
procedure UpdatePricesForItems(var Item: Record Item)
var
  ItemCount: Integer;
begin
  // Check data volume before processing
  ItemCount := Item.Count();

  if ItemCount > 1000 then begin
    // Use batch processing for large datasets
    UpdatePricesInBatches(Item);
  end else begin
    // Direct processing for smaller datasets
    UpdatePricesDirectly(Item);
  end;
end;
```

```al
// Good example - Batched modifications to minimize database writes
procedure UpdateCustomerStatistics(CustomerNo: Code[20])
var
  Customer: Record Customer;
  TotalBalance: Decimal;
  LastPaymentDate: Date;
begin
  // Calculate all values first
  CalculateCustomerTotals(CustomerNo, TotalBalance, LastPaymentDate);

  // Single database write with all changes
  Customer.SetLoadFields("Balance (LCY)", "Last Payment Date");
  if Customer.Get(CustomerNo) then begin
    Customer."Balance (LCY)" := TotalBalance;
    Customer."Last Payment Date" := LastPaymentDate;
    Customer.Modify(true);
  end;
end;
```

## Rule 6: Avoid SetCurrentKey Unless a Specific Ordering Is Required

### Intent

Do not call `SetCurrentKey` just out of habit or to "make sure" a lookup is fast. `SetCurrentKey` forces the SQL Server query optimizer to use that one specific index, overriding its own cost-based plan selection — a plan that, without the hint, is free to pick whichever index best fits the filters actually applied (`SetRange`/`SetFilter`). Only call `SetCurrentKey` when the code genuinely depends on iterating rows in a specific order (e.g. a report that must print in date order, or logic relying on `FindSet` traversal order). For plain filtered lookups (`Get`, `FindFirst`, `FindSet` without an order dependency, `CalcSums`), leave the key alone and let the optimizer choose.

### Examples

```al
// Good example - no ordering dependency, let the optimizer pick the index
procedure GetOpenLines(DocumentNo: Code[20])
var
  SalesLine: Record "Sales Line";
begin
  SalesLine.SetRange("Document No.", DocumentNo);
  SalesLine.SetRange(Open, true);
  if SalesLine.FindSet() then
    repeat
      // order doesn't matter here
    until SalesLine.Next() = 0;
end;
```

```al
// Good example - ordering is a real requirement, SetCurrentKey is justified
procedure PrintLinesByDate(DocumentNo: Code[20])
var
  SalesLine: Record "Sales Line";
begin
  SalesLine.SetCurrentKey("Document No.", "Shipment Date"); // report must print in shipment-date order
  SalesLine.SetRange("Document No.", DocumentNo);
  if SalesLine.FindSet() then
    repeat
      // printed in the required date order
    until SalesLine.Next() = 0;
end;
```

```al
// Bad example (avoid pinning a key when no ordering is needed)
procedure GetOpenLines(DocumentNo: Code[20])
var
  SalesLine: Record "Sales Line";
begin
  SalesLine.SetCurrentKey("Document No."); // forces this index; optimizer can no longer choose a better one
  SalesLine.SetRange("Document No.", DocumentNo);
  SalesLine.SetRange(Open, true);
  if SalesLine.FindSet() then
    repeat
      // order is irrelevant to this logic
    until SalesLine.Next() = 0;
end;
```
