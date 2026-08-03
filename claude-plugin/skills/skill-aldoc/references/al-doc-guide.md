# AL Documentation with aldoc + docfx

> **Version**: 1.0  
> Reference guide for generating technical documentation from AL source code using `aldoc` and `docfx`.
>
> **Core rule**: `/// <summary>` must be used **only before** objects, procedures, and enum values. For **table fields**, documentation belongs in the `ToolTip` and `Description` properties.

---

## How the documentation pipeline works

```
.al sources  →  [AL Compiler]  →  .app
                                      ↓
                                 aldoc build    → reference/*.md + toc.yml
                                      ↓
                                 docfx build    → _site/ (HTML)
```

**Key point:** `aldoc` reads XML comments from the metadata inside the compiled `.app` file, **not** directly from the `.al` sources. Every change to comments requires:

1. Recompile the extension in VS Code (`Ctrl+Shift+B`)
2. Run `aldoc build`
3. Run `docfx build`

---

## When to use `/// <summary>` vs `ToolTip`/`Description`

| AL element | Correct tool | Readable by aldoc? |
|------------|-------------|-------------------|
| Object (`table`, `codeunit`, `page`, etc.) | `/// <summary>` **before** the object declaration | Yes |
| Public codeunit procedure | `/// <summary>` + `<param>` + `<returns>` + `<remarks>` **before** `procedure` | Yes |
| Integration Event | `/// <summary>` + `<param>` + `<remarks>` **before** `[IntegrationEvent]` | Yes |
| Table field (`field`) | `ToolTip = '...';` + `Description = '...';` **inside** the `field()` block | Yes |
| Enum value (`value`) | `/// <summary>` **before** the `value(...)` line, value on a single line | Yes |

---

## Code examples

### Table field — correct format

```al
// CORRECT: ToolTip and Description as properties
field(1; "MyCode"; Code[10])
{
    Caption = 'Code';
    ToolTip = 'Primary key identifying the record. Referenced in headers to associate documents with this configuration.';
    Description = 'Primary key identifying the record. Referenced in headers to associate documents with this configuration.';
    NotBlank = true;
    DataClassification = CustomerContent;
}

// WRONG: /// <summary> inside the field body — ignored by aldoc
field(1; "MyCode"; Code[10])
{
    /// <summary>Primary key identifying the record.</summary>
    Caption = 'Code';
}
```

**Rule**: `ToolTip` and `Description` must contain the same text. Single quotes in AL text must be escaped by doubling them (`'` → `''`).

### Enum with documented values

```al
// CORRECT: /// <summary> BEFORE value(), value on single line
/// <summary>Sales-side — shipments or returns to customers.</summary>
value(1; Customer) { Caption = 'Customer'; }

// WRONG: /// <summary> inside the value block
value(1; Customer)
{
    /// <summary>Sales-side.</summary>
    Caption = 'Customer';
}
```

### Table (complete example)

```al
/// <summary>
/// Central configuration table for the extension. Each record defines a type
/// with its posting rules, number series, and inventory behaviour.
/// Referenced in document headers to drive the posting engine.
/// </summary>
table 50000 "My Setup Table"
{
    Caption = 'My Setup';
    fields
    {
        field(1; "Code"; Code[10])
        {
            Caption = 'Code';
            NotBlank = true;
            DataClassification = CustomerContent;
            ToolTip = 'Primary key identifying the setup type. Referenced in document headers to associate each document with the correct configuration.';
            Description = 'Primary key identifying the setup type. Referenced in document headers to associate each document with the correct configuration.';
        }
        field(10; "Description"; Text[50])
        {
            Caption = 'Description';
            DataClassification = CustomerContent;
            ToolTip = 'Human-readable label for the setup type, displayed in lookups and list pages.';
            Description = 'Human-readable label for the setup type, displayed in lookups and list pages.';
        }
    }
}
```

### TableExtension — single field

```al
/// <summary>
/// Extends Sales Header with fields required for custom document management.
/// </summary>
tableextension 50000 "My Sales Header Ext" extends "Sales Header"
{
    fields
    {
        field(50000; "My Custom Code"; Code[10])
        {
            Caption = 'Custom Code';
            DataClassification = CustomerContent;
            ToolTip = 'Code of the type assigned to this sales header. Determines the posting rules for the document.';
            Description = 'Code of the type assigned to this sales header. Determines the posting rules for the document.';
        }
    }
}
```

### Codeunit — full public procedure

```al
/// <summary>
/// Posts a document from a Sales Header.
/// Main entry point of the posting engine: validates the document,
/// determines the posted document number, verifies setup,
/// optionally creates item ledger entries, and transfers to the posted BC document.
/// </summary>
/// <param name="SalesHeader">The Sales Header to post. Modified in place (Posting No. is set).</param>
/// <remarks>
/// Raises OnBeforePost (allows cancellation via IsHandled) and OnAfterPost.
/// If Write Item Ledger Entry is enabled in setup, calls CreateItemLedgerEntry;
/// otherwise calls TransferReservations.
/// After posting, if the document is fully shipped, triggers archiving and/or
/// deletion based on setup flags.
/// </remarks>
procedure PostDocument(var SalesHeader: Record "Sales Header")
```

### Integration Event

```al
/// <summary>
/// Integration event raised before PostDocument executes.
/// Subscribe to this event to override the default posting logic.
/// </summary>
/// <param name="IsHandled">Set to true to skip the default implementation.</param>
/// <param name="SalesHeader">The Sales Header being posted.</param>
/// <remarks>
/// When IsHandled is set to true, all remaining logic in PostDocument is skipped.
/// Use this event to implement custom posting behaviour for specific document types.
/// </remarks>
[IntegrationEvent(false, false)]
local procedure OnBeforePostDocument(var IsHandled: Boolean; var SalesHeader: Record "Sales Header")
begin
end;
```

### Enum with documented values

```al
/// <summary>
/// Extensible enum identifying whether a setup record applies to customer (sales)
/// or vendor (purchase) flows, controlling the available document types and posting paths.
/// </summary>
enum 50000 "My Source Type"
{
    Extensible = true;

    /// <summary>Not set. The source type has not been selected yet.</summary>
    value(0; " ") { Caption = ''; }
    /// <summary>Sales-side — shipments or returns to customers.</summary>
    value(1; Customer) { Caption = 'Customer'; }
    /// <summary>Purchase-side — receipts or returns from vendors.</summary>
    value(2; Vendor) { Caption = 'Vendor'; }
}
```

---

## Generating the documentation

### First-time initialisation

Run `aldoc init` only when setting up the `docs\` folder for the first time, or after upgrading the AL extension to a new major version. Under normal circumstances, skip `init` and go straight to Step 2.

```powershell
$aldoc = "C:\Users\<username>\.vscode\extensions\ms-dynamics-smb.al-<version>\bin\win32\aldoc.exe"
$app   = "C:\<repo>\app\<Publisher>_<Name>_<version>.app"
$docs  = "C:\<repo>\docs\developer\en-US"

& $aldoc init -o $docs -T $app
```

**Warning:** `init` overwrites `template\`, `docfx.json`, `index.md`, and `toc.yml`. Reapply brand customisations afterwards.

### Step 1 — Identify the latest `.app` file

```powershell
Get-ChildItem "C:\<repo>\app\*.app" | Sort-Object Name
```

### Step 2 — Run `aldoc build`

```powershell
$aldoc = "C:\Users\<username>\.vscode\extensions\ms-dynamics-smb.al-<version>\bin\win32\aldoc.exe"
$app   = "C:\<repo>\app\<Publisher>_<Name>_<version>.app"
$docs  = "C:\<repo>\docs\developer\en-US"
$pkgs  = "C:\<repo>\app\.alpackages"

& $aldoc build -s $app -o $docs -c $pkgs
```

### Step 3 — Run `docfx build`

```powershell
docfx build "$docs\docfx.json"
```

### Step 4 — Preview locally

```powershell
docfx serve "$docs\_site" -p 8080
```

Open http://localhost:8080

---

## Rules by object type

### Tables / TableExtensions
- Object: `/// <summary>` before `table` / `tableextension`
- Fields: `ToolTip` + `Description` (same text) inside `field()` block, after `Caption`
- Public procedures: `/// <summary>` + `<param>` + `<returns>`
- Field triggers: no documentation

### Codeunits
- Object: `/// <summary>` before `codeunit`
- Public procedures: `/// <summary>` + `<param>` + `<returns>` + `<remarks>`
- Local procedures: do not document
- Integration Events: `/// <summary>` + `<param>` + `<remarks>`

### Enums / EnumExtensions
- Object: `/// <summary>` before `enum` / `enumextension`
- Values: `/// <summary>` before the `value(...)` line; value block on a single line

### Pages / PageExtensions
- Object: `/// <summary>` before `page` / `pageextension`
- Public procedures: `/// <summary>` + `<param>` + `<returns>`
- Page triggers: do not document

### Reports
- Object: `/// <summary>` before `report`
- Public procedures (`InitializeRequest`, setters, getters): `/// <summary>` + `<param>` + `<returns>`

### PermissionSets
- Object: `/// <summary>` before `permissionset`
