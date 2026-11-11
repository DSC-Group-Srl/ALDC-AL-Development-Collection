---
name: skill-app-id-range
description: "Claim the object ID range of a DSC AppSource app from DSC's own Business Central (the Product Ranges register, API pages 75114/75115 on the `businesscentral` MCP connection), and write it into app.json `idRanges`. Use when a new AppSource app or its test app needs object IDs, when an existing AppSource app has run out of IDs, when the user asks which range an app owns or which ranges are free, or says 'claim a range', 'gamma prodotti', 'range liberi', 'object IDs for the new app'. Not for per-tenant (PTE) apps: those use the customer's 50000-99999 range."
---

# Skill: claim an AppSource object ID range

DSC's AppSource object IDs come from one Microsoft-assigned block, and DSC keeps the register of
who owns which part of it in its own Business Central (**Product Ranges**). Picking a range by
hand from another app's `app.json` is how two apps end up with the same IDs. This skill reads
the register and claims a range from it.

It is the **one write** bc-dev makes on DSC's Business Central. Everything else on that
connection is read-only (`skill-bc-issue`).

## When it applies

| Situation | What to do |
|---|---|
| New AppSource app of a DSC product (`dyna-*`) | claim a range (§2) |
| Its test app (`app-test/`) | a separate claim with `testApp: true` |
| An AppSource app has no free ID left in its `idRanges` | claim an additional range for the same app |
| "Which range does this app own?", "what is free?" | read only (§1) |
| Per-tenant app for a customer (IDs 50000-99999) | **not here** — the customer's own range, no claim |

## The connection

The same one as `skill-bc-issue`: server `businesscentral`, tools
`mcp__plugin_bc-dev_businesscentral__*`, DSC tenant, `Production`, company `DSC GROUP SRL`,
the developer's own sign-in (`/mcp` → `businesscentral` → authenticate).

Only the **main thread** claims. A subagent that needs IDs says so in its result and the main
thread claims them.

Not connected, or the developer's account lacks the permission → don't guess a range. Tell the
user to claim it on the **Product Ranges** page in Business Central and give you the result.

## 1. Read the register (always first)

```text
List_ProductRanges_PAG75114
  filter: contains(tolower(appName),'<app name, lower-case>')
  select: id,productName,appName,appPrefix,rangeStart,rangeEnd,objectsAssigned,free,
          publishedOnAppSource,testApp
  orderby: rangeStart asc   top: 50
```

| Field | Meaning |
|---|---|
| `productName` | the product (`Dyna HR`, `Dyna ARX`) — one product, several apps |
| `appName`, `appPrefix` | the app that owns the row and its object-name prefix (`DSC TS`) |
| `rangeStart`, `rangeEnd` | the IDs of the row, inclusive |
| `objectsAssigned` | the **size** of the row (`rangeEnd - rangeStart + 1`), not how many IDs the code uses |
| `free` | the row is available. Recognise a free row by this flag, never by its name |
| `publishedOnAppSource`, `testApp` | the app is live on AppSource / is a test app |

Three checks before claiming anything:

1. **Does the app already own a range?** Compare the rows with `app.json` → `idRanges`. A row
   that is not in `app.json` yet is a range already claimed and never used: use it, don't
   claim another.
2. **Is it really full?** Count the IDs the code uses
   (`grep -rhoE '^(table|page|codeunit|report|query|xmlport|enum|permissionset|tableextension|pageextension|enumextension|interface) [0-9]+'`
   gives the object numbers; fields of table extensions and enum-extension values use IDs
   too). Room left in the range → no claim.
3. **What is free?** `filter: free eq true`. Nothing free, or nothing large enough → stop and
   tell the user; the register has to be extended by a person.

Use the product and app names **exactly as they already appear** in the register for that
product. **The register does not validate the product name** (verified 2026-11-11: a claim
for a product that did not exist was accepted), so a different spelling silently creates a
second product.

## 2. Claim

One call creates the claim and assigns the IDs **immediately**:

```text
Create_ProductRangeClaim_PAG75115
  productName: "Dyna HR"            required — as it appears in the register
  appName:     "Dyna TimeSheet"     the app (extension) name from app.json
  appPrefix:   "DSC TS"             the object-name prefix
  idsNeeded:   50                   required, > 0
  testApp:     false
  freeRangeStart: 0                 0 = the first free range large enough;
                                    or the rangeStart of the free row to take from
```

The answer carries the result: `claimedRangeStart` and `claimedRangeEnd`.

How it goes:

1. **Say what you are about to claim**, in one line, before the call: product, app, prefix,
   how many IDs, test app or not. The number of IDs comes from the spec or the user (objects
   planned plus room to grow); when nobody said, ask — don't pick one. Existing rows of
   similar apps are the yardstick (a small connector 10-20, a full product app 50-150).
2. **The call asks the user for permission, every time** — the guard (`tools/bc-guard/`) turns
   it into a confirmation prompt, also in auto mode. That prompt is the approval; don't add a
   second question on top.
3. **Never retry a call that returned a result.** The claim is not idempotent: a second call
   claims a second range. An error means nothing was claimed; read the message, fix the
   input, and only then call again. A timeout or an unreadable answer → **read the register
   first** (§1) to see whether the range was assigned.
4. **Write the range where it belongs**: `app.json` → `idRanges`
   (`{"from": <claimedRangeStart>, "to": <claimedRangeEnd>}`), added to the existing entries
   when the app already had a range. For a test app, the test project's `app.json`.
5. **Report it** in one line: `Claimed 18165635-18165684 for Dyna TimeSheet (Dyna HR)`.

## Rules

- **One claim per need, confirmed by the user.** Never claim "to be safe", never for an app
  that does not exist yet as a repo or a spec.
- **Releasing a range is not yours.** `MarkAsFree` is denied by the guard. A range claimed by
  mistake: tell the user its `rangeStart`-`rangeEnd`, and a person frees it on the Product
  Ranges page. Freeing only sets `free` on that row: it keeps its product, app and prefix and
  is not merged back into the neighbouring free row, so a mistaken claim leaves a small
  free row behind.
- **Never change another app's row**, and never take IDs from a row that is not `free`.
- **PTE apps never claim** — 50000-99999 belongs to the customer's tenant.
- Action names carry a page number that can change with the app version: when one is
  missing, find it again with `bc_actions_search` (keyword `product range`).
- A new AppSource app also needs licensing: `skill-dyna-license`.
