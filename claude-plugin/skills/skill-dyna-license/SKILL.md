---
name: skill-dyna-license
description: Protect a DSC AppSource app with Dyna License (DSC's own licensing app, id 38500a92-e0fb-42f9-9d38-8ee835194b98) and register it as a product on the Dyna License admin portal (https://dynalicenseadmin.azurewebsites.net). Covers the app.json and AL-Go dependency, the license wrapper codeunit (version reporting on install/upgrade/configure, CheckActive / CheckValue / Use gates), where to put the gates, Level vs Package license types, the test app's Dyna License Test Library, and filling the portal's Add Product and Add License forms with Claude in Chrome (or guiding the user through them). Use when a new or still unprotected AppSource app needs licensing, when the user mentions Dyna License, DSC LIC, license check, license level (Essential/Premium/Gold), package/quantity licensing, or adding a product or license on the Dyna License portal.
---

# Dyna License for an AppSource app

Dyna License is DSC's licensing app. Every DSC AppSource product depends on it. It downloads,
per tenant, the products and licenses from the Dyna License service, caches them in its own
Isolated Storage, and answers "does this app have an active license (at this level / with this
quantity left)?" for an **app id**. The match is `Product.BCAppId` on the portal = the consuming
app's `app.json` `id`.

Two halves, both required:

1. **Code**: the app depends on Dyna License and calls it (§1 to §5).
2. **Portal**: a product with that app id exists on the admin portal, and a customer has a
   license for it (§6 to §8). Without the product, every check fails with *"No product found with
   the specified Application Id"*.

Sources, for when this skill is not enough: `DSC-Group-Srl/dyna-license` (AL, GitHub; usually
`D:\repos\DSC GROUP\Business Central\dyna-license`) and `dyna-license-admin` (portal, service, DB;
Azure DevOps project *Dyna License*). Reference consumers: `dyna-arx`
(`app/Source/Security/Codeunit/DSCARXDynaLicenseMngt.Codeunit.al`) and `dyna-expense-notes`
(also uses the Test Library).

## 0. Is the app eligible and unprotected?

- **AppSource only.** `idRanges` outside 50000-99999 and `.AL-Go/settings.json` has
  `deliverToAppSource`. A PTE does not use Dyna License: stop and tell the user.
- **Already protected?** `grep -l 38500a92-e0fb-42f9-9d38-8ee835194b98 */app.json`. If it is a
  dependency, look for the existing wrapper codeunit (`grep -rl '"DSC LIC Dyna License Mngt"'`)
  and extend it rather than adding a second one.
- Ask the user for two decisions before writing code: the **license type** (§3) and **which
  features are gated, at which level** (§4). They are commercial decisions, not technical ones.

## 1. Dependencies

`app/app.json`:

```json
{
  "id": "38500a92-e0fb-42f9-9d38-8ee835194b98",
  "name": "Dyna License",
  "publisher": "DSC Group Srl",
  "version": "<latest released version>"
}
```

Take the version from `gh release list -R DSC-Group-Srl/dyna-license --limit 1` (for example
`28.2.0` → `"28.2.0.0"`), not from `dyna-license/app/app.json` on `main`, which can be ahead of
what customers have installed. The minimum version is a promise to every customer tenant, so do
not raise it without a reason.

`app-test/app.json` (§5):

```json
{
  "id": "3d4fc733-9399-4f5e-831a-a31fe207e02b",
  "name": "Dyna License Test Library",
  "publisher": "DSC Group Srl",
  "version": "<version in dyna-license/app-test-library/app.json>"
}
```

`.AL-Go/settings.json`, so CI finds both (Apps and TestApps of the latest `main` build):

```json
"appDependencyProbingPaths": [
  { "repo": "DSC-Group-Srl/dyna-license", "release_status": "latestBuild",
    "branch": "main", "AuthTokenSecret": "GhTokenWorkflow" }
]
```

`GhTokenWorkflow` must exist as a repo/org secret (`bc-dev:skill-al-go-workflows`).

**Symbols locally.** Dyna License is on AppSource: `GITCloner al-symbols … --country it --json`
(`bc-dev:skill-gitcloner`) or al-mcp `al_downloadsymbols` with `globalSourcesOnly=true`. The Test
Library is **not** on AppSource: take its `.app` from the latest `dyna-license` CICD run artifacts
(`dyna-license-main-TestApps-<version>`, via `gh run download -R DSC-Group-Srl/dyna-license`) into
`app-test/.alpackages`.

## 2. The wrapper codeunit

One codeunit per app, in `app/Source/Security/Codeunit/`, with the app's affix and an id from its
own range. Every other object calls this, never Dyna License directly: the license logic stays in
one place, and `NavApp.GetCurrentModuleInfo` returns **this** app's id because it runs inside this
app. Never hard-code the app id.

```al
namespace <AppNamespace>.Security;

using DynaLicense;
using DynaLicense.Configuration;
using DynaLicense.License;
using DynaLicense.VersionMngt;
using System.Environment;
using System.Upgrade;

/// <summary>
/// Connects <App Name> to Dyna License: reports the installed version to the license service and
/// is the single place where the app checks its license.
/// </summary>
codeunit <id> "<AFFIX> Dyna License Mngt"
{
    Access = Internal;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Extension Triggers", OnInstallAppPerDatabase, '', false, false)]
    local procedure OnInstall()
    begin
        SendVersionIfConfigured();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Upgrade Triggers", OnValidateUpgradePerDatabase, '', false, false)]
    local procedure OnUpgrade()
    begin
        SendVersionIfConfigured();
    end;

    [EventSubscriber(ObjectType::Page, Page::"DSC LIC Dyna License Setup", Configured, '', false, false)]
    local procedure OnDynaLicenseConfigured()
    var
        VersionMngt: Codeunit "DSC LIC Version Mngt";
        ModuleInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(ModuleInfo);
        if VersionMngt.SendAppDataToDynaVersion(ModuleInfo.Id(), ModuleInfo.AppVersion()) then;
    end;

    /// <summary>Fails with the Dyna License message when the app has no active license.</summary>
    /// <remarks>TryFunction: use the return value for a silent check, ignore it for a hard stop.</remarks>
    [TryFunction]
    procedure CheckActive()
    var
        DynaLicenseMngt: Codeunit "DSC LIC Dyna License Mngt";
        ModuleInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(ModuleInfo);
        DynaLicenseMngt.CheckActive(ModuleInfo.Id());
    end;

    /// <summary>Fails unless an active license is at least the given level (Level-type products).</summary>
    [TryFunction]
    procedure CheckLevel(Level: Enum "DSC LIC License Level")
    var
        DynaLicenseMngt: Codeunit "DSC LIC Dyna License Mngt";
        ModuleInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(ModuleInfo);
        DynaLicenseMngt.CheckValue(ModuleInfo.Id(), Level.AsInteger());
    end;

    local procedure SendVersionIfConfigured()
    var
        DynaLicenseMngt: Codeunit "DSC LIC Dyna License Mngt";
        VersionMngt: Codeunit "DSC LIC Version Mngt";
        ModuleInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(ModuleInfo);
        if DynaLicenseMngt.IsDynaLicenseConfigured() then
            if VersionMngt.SendAppDataToDynaVersion(ModuleInfo.Id(), ModuleInfo.AppVersion()) then;
    end;
}
```

The version calls are wrapped in `if … then;` on purpose: an offline service must never make an
install or upgrade fail. Version reporting feeds the portal's *Installed Version* column and the
version matrix.

For a Package product add the quantity procedures from §3 instead of, or next to, `CheckLevel`.

## 3. License type: Level or Package

The type is set **on the portal product** (§6), not in code. The code must call the procedures
that match it.

| Type | Use when | The license carries | Calls |
|------|----------|--------------------|-------|
| **Level** (default; all DSC products but two) | Subscription per tenant, optionally with tiers | Start date, due date, level `Essential` (0) < `Premium` (1) < `Gold` (2) | `CheckActive(AppId)`; `CheckValue(AppId, Level.AsInteger())` passes when any active license is **at least** that level |
| **Package** (Dyna Translator, Dyna HR WebApp) | Pay per use: documents, translations, calls | Purchased packages; cumulative quantity and used quantity | `CheckValue(AppId, Qty)` before the work, `Use(AppId, Qty)` after it succeeds |

Package details that bite:

- `CheckValue` on a Package product passes when **remaining > Value**, strictly. To check that
  *N* units can be consumed, pass `N - 1`. `CheckActive` is `CheckValue(…, 0)`: at least one unit
  left.
- `Use` adds to the used quantity of the active package and writes to the database. Call it once,
  after the operation succeeded, and check its return value.
- A Package license without an active package fails with *"No Active Package found"*: on the
  portal, a package must be added to the license (§8).

## 4. Where to put the gates

- **Gate the paid entry points**, not every trigger: the setup/main page `OnOpenPage`, the action
  that starts the paid process, the job queue codeunit's `OnRun`, the API page's
  `OnOpenPage`/`OnFindRecord`. Hard stop: `DynaLicenseMngt.CheckActive();` (return value
  ignored, so the error reaches the user with Dyna License's own message).
- **Event subscribers on standard BC flows** (posting, release, document events): silent check,
  `if not DynaLicenseMngt.CheckActive() then exit;`. An expired licence must switch the add-on
  off, never block the customer's standard posting.
- **Tiers**: `DynaLicenseMngt.CheckLevel(Enum::"DSC LIC License Level"::Premium);` on the
  Premium/Gold features only. Essential features keep `CheckActive`.
- The checks are cheap: they read Dyna License's cache, refreshed by a Job Queue Entry it
  schedules at login. There is no HTTP call per check.
- The error texts belong to Dyna License (*"No Active License found for %1. Please contact your
  provider."*, where %1 is the portal product **Name**). Do not wrap them in your own Label.
- Users: Dyna License ships the assignable permission set `DSC LIC MainPerm`. The current
  consumers do not include it in theirs. If a non-SUPER user hits a permission error on a
  `DSC LIC` object, add `IncludedPermissionSets = "DSC LIC MainPerm";` to the app's permission
  set (`bc-dev:skill-permissions`).

## 5. Tests

A fresh container has no Dyna License setup, so every gated path fails. The **Dyna License Test
Library** seeds an offline setup plus an active **Gold** license for an app id, idempotently, and
refuses to run in a SaaS production environment. It never modifies an existing setup.

```al
var
    LicenseTestLibrary: Codeunit "DSC LIC Test Library";
    AppIdTxt: Label '<app/app.json id>', Locked = true;

local procedure EnsureLicense()
var
    AppId: Guid;
begin
    Evaluate(AppId, AppIdTxt);
    LicenseTestLibrary.EnableLicenseForTesting(AppId);
end;
```

Call it from the test library's `Initialize()` (`bc-dev:skill-testing`). If the app depends on
another licensed DSC app that gates the code under test, enable that app id too
(`dyna-expense-notes` enables itself and Dyna HR).

Limits: the library only **enables**. There is no API to make the license inactive or a lower
level, so the "no license" paths cannot be unit-tested through it. A Package product reused from
an existing setup still needs its own package data. Run the tests through the test lane
(`bc-dev:skill-test-lane`).

## 6. The portal: add the product

Portal: **https://dynalicenseadmin.azurewebsites.net**. Sign-in is Entra ID; anyone in the DSC
Group tenant can open it. Pages (left menu): **Home** (charts), **Customers** (`/customers`),
**Potential Customers** (`/potentialcustomers`: tenants that registered themselves from BC but
have no DSC customer number or notification mail yet), **Products** (`/products`).

**Products** grid: columns Id, Name, BC App (check/cross), License Type. Each row has History
(installed versions and changelog), Edit (pencil) and **Delete** (red bin). The green **+** at the
top right opens **Add Product**:

| Field | What to enter |
|-------|---------------|
| **Id** | Read-only, a new GUID generated by the portal. This is the *product* id, **not** the app id. Leave it. |
| **Name** | Product display name, at most 50 characters, as customers should see it: Dyna License puts it in the license messages and the expiry notifications. Follow the existing names (`Dyna Arx`, `Dyna Expense Notes`), usually `app.json` `name`. |
| **Business Central App** (switch) | **On.** Off is for non-BC products (Dyna HR WebApp), and BC ignores products with it off. |
| **Business Central App Id** | Appears when the switch is on, required. `app/app.json` `id`, **lowercase, no braces** (`e6509112-a196-487c-9840-b33c52fd7cc9`). Dyna License compares it as text with the lowercased app id; the portal does not normalise it. |
| **License Type** | `Level` or `Package` (§3). It drives the BC check and the license forms in §8. |
| **Azure DevOps Enabled** (switch) | **Off** for GitHub repos. On, it asks Project, Repository, Branch, Root Path, and the History dialog reads `changelog.json` from that Azure DevOps folder. Older products (`Dyna Arx` → `BC-UniversalCode` / `dyna-arx-20` / `main` / `/DynaARX 20/`) still use it. GitHub repos cannot. |

**SAVE** → snackbar *"Product inserted!"* and the row appears. *"Cannot insert the product!"*
means the database rejected it: check the length of the name.

Before adding, check the grid for the same product **name**. The grid does not show the BC App Id:
open **Edit** on a suspect row to read it, then **CANCEL**. With two products on the same app id,
BC silently uses the one whose product Id sorts first.

## 7. Filling the portal with Claude in Chrome

When the `mcp__claude-in-chrome__*` tools exist (they can be deferred: load
`tabs_context_mcp, tabs_create_mcp, navigate, computer, find, read_page, get_page_text,
browser_batch, tabs_close_mcp` in **one** ToolSearch call), fill the form for the user. Otherwise
give them the table in §6 with the values already filled in.

1. Collect the values first: Name, App Id (read it from `app.json`, lowercase it), License Type.
2. `tabs_context_mcp` (createIfEmpty), `navigate` to `https://dynalicenseadmin.azurewebsites.net/products`,
   screenshot. **If you land on `login.microsoftonline.com`, stop** and ask the user to sign in
   in that window: never type credentials.
3. `get_page_text`: check the name is not in the list (§6).
4. Click the green **+** (top right of the grid). Locate fields with `find` / `read_page`
   (`filter: interactive`), not with fixed coordinates: the dialog moves down when the BC App Id
   field appears. The textboxes are labelled `Name` and `Business Central App Id`. The switches
   have no accessible name, so use `find` ("Business Central App switch"). License Type is a
   MudSelect showing `Level`: click it, then pick `Level` or `Package` from the list.
5. Type the Name, turn the **Business Central App** switch on, type the App Id, set the License
   Type, leave **Azure DevOps Enabled** off.
6. Screenshot the filled dialog, show the user the four values, and **ask for a yes in chat
   before clicking SAVE**. Saving writes to the production licensing database every customer
   tenant reads.
7. After the yes, click **SAVE**, confirm the *"Product inserted!"* snackbar and the new row.
   Close the tab.

Never click **Delete** (on products, customers or licenses), **Deactivate License** or **Edit
License Level** unless the user asks for that specific action. **CANCEL** closes a dialog without
saving.

## 8. A license to try it, and what the customer does

A product without licenses only makes BC say *"No Active License found"*. To check the whole chain
on a sandbox:

1. **The tenant registers itself.** In the BC sandbox, with the app and Dyna License installed,
   open **Dyna License Setup** (search *Dyna License Setup*). On SaaS it creates the customer by
   tenant automatically, and the **Configured** event fires the wrapper's version report. On
   OnPrem it asks a **Customer Id** created on the portal first (Customers → **+**).
2. **Portal → Customers** (switch *Show potential customers* on, if the tenant is new) → row
   icons: **licenses** (first icon, `/licenses/{customerId}`), installed products (second, with
   *Installed Version* from the version report), Edit, Delete.
3. **Licenses - <customer>** page → **+** → **Add License**: Id (read-only), **Product**
   (autocomplete on the name), **Start Date**, **End Date**, and for Level products **License
   Level** (`Essential` / `Premium` / `Gold`). Same rule as §7: values to the user, a yes, then
   **SAVE**.
4. Expanding a license row shows the **License Key**, **Generate Activation Key** (offline/OnPrem
   tenants paste that key in BC → *Activate New Offline License*), start and due date, level, and
   the actions Edit License Level / Deactivate License / Delete License. For a **Package** product
   the row shows **Add Package** (Purchase Date, Purchase Quantity; Cumulative Quantity is
   calculated), and the license has no active package until one is added.
5. **Back in BC**: Dyna License Setup → **Synch Manually**, then exercise a gated feature.

Licenses renew automatically during the reminder period (the service sends the reminders and
BC shows an expiry notification). The portal has no separate trial type: a trial is a normal
license with a short end date.

## 9. Checklist

- [ ] `app.json` dependency on Dyna License (latest released version)
- [ ] `.AL-Go/settings.json` probing path on `DSC-Group-Srl/dyna-license`
- [ ] Wrapper codeunit: install / upgrade / Configured version report, `CheckActive`, plus
      `CheckLevel` (Level) or quantity checks + `Use` (Package)
- [ ] Gates on the paid entry points; silent exits in subscribers on standard flows
- [ ] Test app depends on the Test Library and calls `EnableLicenseForTesting` in `Initialize()`
- [ ] Compiles with every analyzer on; tests green through the test lane
- [ ] Portal product: BC App on, App Id lowercase from `app.json`, License Type, DevOps off
- [ ] A sandbox license and one manual check of a gated feature
