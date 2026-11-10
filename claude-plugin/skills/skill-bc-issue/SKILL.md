---
name: skill-bc-issue
description: "Link a piece of bc-dev work to its Issue in DSC's own Business Central (Customer > Project > Task > Issue) through the read-only `businesscentral` MCP connection, and read the estimate and booked hours already recorded on it. Use at the start of any activity (spec, conductor run, LOW change, triage of a ticket) to find and record the Issue, when a spec or a conductor run needs the Issue's estimate, and whenever the user gives an Issue number or reference (issueListRef, 'IL 1234', 'la issue di ...'). The link makes telemetry, estimates and DSC's prediction model join on the Issue."
---

# Skill: link the work to its Business Central Issue

DSC plans and bills every activity as an **Issue** in its own Business Central. bc-dev measures
what the same activity costs an agent (tokens, minutes, fix loops). The two only meet if the
session knows **which Issue it is working on**. This skill is how it finds out, records it, and
reads the Issue's numbers back.

Everything here is **read-only**. The connection is DSC's production company.

## The connection

| | |
|---|---|
| Server | `businesscentral` in the plugin's `.mcp.json` → tools `mcp__plugin_bc-dev_businesscentral__*` |
| Target | DSC tenant, environment `Production`, company `DSC GROUP SRL`, configuration `OPERATIONS` |
| Sign-in | the developer's own DSC account: `/mcp` → `businesscentral` → authenticate (once) |
| Tools | `bc_actions_search` → `bc_actions_describe` → `bc_actions_invoke` |
| Guard | `tools/bc-guard/`: only `List_*` actions run; every write is denied |

It is the same Business Central the `dsc-timesheet` plugin uses, on a separate connection, so
the two never get in each other's way. If the tools are **not connected** (not signed in, a
customer's machine, offline): say so in one line, ask the user for the Issue number instead,
and carry on. Never block work on it.

Subagents get these tools only where their definition lists them (`al-triage`). Everywhere else the **main thread** resolves the Issue and passes the number in
the brief.

## Data model

```
Customer (customerCode)
  └─ Project   List_Projects_PAG75102  (projectID)
      └─ Task  List_Tasks_PAG75103     (taskCode)   the billable job
          └─ Issue  List_Issues_PAG75105 (entryNo)  the activity — the thing to link
```

Issue fields that matter here:

| Field | Meaning |
|---|---|
| `entryNo` | **the key** — the integer you link and report |
| `issueListRef` | the human reference people quote |
| `ilDescription`, `notes` | what the activity is |
| `customerCode` / `customerName`, `projectID`, `taskCode` | where it sits |
| `status` | `Pending`, `Not Started`, `Started`, `Completed`, `Suspended`, `Exceeded`, `Approving` |
| `requestType`, `managementType` | `Development`/`Maintenance`/…, `Time Material`/`Quoted`/… |
| `estimatedHours` | technical estimate (human hours) |
| `plannedHours` | hours communicated to the customer |
| `totalHoursTSLine`, `totalHoursUsed` | actual hours from timesheets |
| `ticketRef` | Freshdesk ticket, when the Issue came from one |
| `employeeID` | last assignee |
| `issueChildrenCount`, `issueParentEntryNo` | hierarchy — link the **leaf** |

Action names can change with the app version: when one is missing, rediscover it with
`bc_actions_search` (keyword `issue, task, project`) instead of guessing.

OData limits: `eq ne lt le gt ge and or`, `contains/startswith/endswith/tolower`; `or` only on
one field; no `not`. Dates unquoted (`insertDate ge 2026-10-01`). **Default page size is 10** —
pass `top`. Always pass `select`: an Issue has 91 fields.

## 1. Find the Issue: derive it, propose it, let the user confirm

Don't open with "which Issue is it?". Work it out first, then put a concrete proposal in front
of the user. Three inputs, all cheap:

**a. What you were told.** A number or reference from the user, a `**BC Issue:**` line in the
spec, or a Freshdesk ticket (`ticketRef eq '<ticket number>'`) settles it: verify it exists
(query below) and go to "propose".

**b. Whose repository this is.** `gh api repos/{owner}/{repo}/properties/values` gives
`customer` (`MARTESANA SRL`, or `DSC GROUP` for DSC's own products) and, for a product,
`product` (`Dyna ARX`). In Business Central the customer is matched on `customerName`
(`contains`, lower-case, without the legal form: `martesana`, `dsc group`); a product's Issues
sit in the project named after it (`projectID` `DYNA-ARX` for `Dyna ARX`).

**c. Who is working.** The Issues assigned to the developer:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/tools/issue/whoami.sh"     # -> the developer's company e-mail
```

It takes the address from the GitHub account `gh` is signed in with, falling back to
`git config user.email` and the Claude account (GitHub usually hides the address). Then:

```text
List_Employees_QRY75105
  filter: tolower(companyEMail) eq '<e-mail>'     select: no,companyEMail      -> no = employeeID
```

No e-mail, or no employee with it → skip the employee filter and search by customer only.

**The candidates** — open, leaf Issues of that customer assigned to that employee:

```text
List_Issues_PAG75105
  filter: employeeID eq '<ID>' and contains(tolower(customerName),'<customer>')
          and status ne 'Completed' and status ne 'Suspended' and status ne 'Exceeded'
          and issueChildrenCount eq 0
  select: entryNo,issueListRef,ilDescription,customerName,projectID,taskCode,status,
          estimatedHours,lastModifyDate,lastSprintNo
  orderby: lastModifyDate desc   top: 30
```

For a product repo add `and contains(tolower(projectID),'<product slug>')`. Nothing comes back
→ drop `employeeID` (the Issue may be assigned to someone else) and add a word from the request:
`and contains(tolower(ilDescription),'<word>')`.

**Rank them** against what the work is — the user's request, the spec title, the branch name:
words shared with `ilDescription`, the same project/task as the spec, `Started` before
`Pending`, in the current sprint, most recently modified.

**Propose, then ask** — always with `AskUserQuestion`, one question:

> *"Is this the Business Central Issue for this work?"*

| Option | When |
|---|---|
| **`<issueListRef>` — `<ilDescription>`** (your best match, first, marked recommended) | you have a candidate |
| up to two more candidates, same shape | others are plausible |
| **No Issue for this work** | always offered |
| *(the free-text answer)* | "another one": the user types the number or reference |

Put customer, project and status in each option's description. No candidate at all → say so in
the question and offer only "No Issue for this work" plus the free text. A typed number or
reference is verified before it is recorded:

```text
List_Issues_PAG75105
  filter: entryNo eq 4821            (or: issueListRef eq 'DSC21-612')
  select: entryNo,issueListRef,ilDescription,customerName,projectID,taskCode,status,
          estimatedHours,plannedHours,totalHoursTSLine,issueChildrenCount
```

Rules for the proposal:

- **Never link without the user's yes**, however obvious the match — the number ends up on
  timesheets and in the estimation data.
- **"No Issue" is a normal answer** (plugin work, experiments, a quick fix nobody planned).
  Never create an Issue.
- **An Issue without an estimate is normal too.** Many have `estimatedHours` 0 and nothing in
  the notes. Link it all the same; §3 only applies when there is something to read.
- A `Completed` Issue, or a parent with children: say so and ask whether the work really
  belongs there.
- The `businesscentral` connection is not signed in → you cannot derive anything: ask for the
  number directly, with the same "No Issue" option.

**Before a conductor run this always happens.** A guard (`tools/issue/run_guard.sh`) denies
launching `al-conductor` until the spec header or the brief says `BC Issue: <number>` or
`BC Issue: none`.

## 2. Record the link

**The spec header is the source of truth.** Once `**BC Issue:** <entryNo>` is in the spec of
the branch, the scripts do the rest on their own: the session-start hook links every new
session on that branch, and the conductor's run events read the same line. You record the link
by hand only the first time, or for work that has no spec.

Three places, all cheap:

1. **Telemetry** — when you have just resolved the Issue in this session (a session the hook
   already linked says so at start: don't emit again):

   ```bash
   python "${CLAUDE_PLUGIN_ROOT}/tools/metrics/emit.py" AldcIssue issueNo=<entryNo> source=<spec|user|freshdesk|history|branch>
   ```

   From then on every event of the session (conductor run, each subagent phase, the session
   total) carries `issueNo`. `issueNo=0` clears it. Only the number travels — never the
   description, customer or hours.
2. **The spec** — the header line `**BC Issue:** <entryNo> (<issueListRef>)`, on its own
   line, number first. Next to it, when the Issue carries the estimator's agent wall-clock:
   `**Agent estimate:** P50 <n> min · P80 <n> min (stima-sviluppo)`. Keep both shapes exact —
   a script reads them.
3. **Your reply** — one line: `Linked to Issue <issueListRef> (<entryNo>): <short description>`.

"No Issue" is recorded too: write `**BC Issue:** none` in the spec, and do not emit.

## 3. Read the estimate on the Issue — when there is one

Often there is none: the Issue was opened without an estimate, or the work never went through
the estimator. Then there is nothing to read — write "not estimated" in the spec, leave the
`**Agent estimate:**` line out, and carry on. The link alone is what matters.

bc-dev does **not** estimate. Estimating a development is the consultant's flow in the
`bc-cons` plugin (`/bc-cons:stima-sviluppo`): it has the calibrated engine and writes its
result on the Issue. A developer session reads that result back:

| On the Issue | What it is |
|---|---|
| `estimatedHours` | technical estimate, **human** hours |
| `plannedHours` | hours agreed with the customer (commercial — quote, don't change) |
| `notes` | where the estimator puts the **agent effort**: iterations, wall-clock, confidence |
| `totalHoursTSLine` | hours booked so far |

Use them like this:

- **Spec** — quote `estimatedHours` (and the booked hours, if any) in the effort section, with
  the Issue reference. Don't invent a number when the field is empty: write "not estimated"
  and suggest `/bc-cons:stima-sviluppo`.
- **Conductor run** — when `notes` carry an agent wall-clock estimate in minutes (P50 / P80),
  put them in the spec so `al-conductor` passes `estP50Min` / `estP80Min`
  `estSource=stima-sviluppo` to `AldcEstimate`. That pair, plus `issueNo`, is what lets DSC
  compare the estimate with what the run measured.
- **Someone asks "how long will this take?"** in a developer session → answer from the Issue
  if it has an estimate; otherwise point to `/bc-cons:stima-sviluppo` rather than improvising.

Hours in BC are **human** hours. Agent effort (tokens, wall-clock) is a different unit — keep
them in separate lines, never add them.

## Rules

- **Read-only.** No `Create_`, `Modify_`, `Delete_` or bound action, ever — the guard denies
  them, and working around it is not an option. What should be written, a person writes in BC.
- **Timesheet lines are not yours.** That is the `dsc-timesheet` plugin.
- **Few calls.** One or two queries find an Issue. Don't page through the list.
- **Nothing customer-specific leaves the session.** Issue descriptions, customer names and
  hours stay in the conversation and the spec; telemetry gets the number only.
- **Files and notes of an Issue** (Teams channel, SharePoint folder, Markdown notes) are not
  exposed by the API yet — DSC-Group-Srl/dscgroup-base#74. Until then ask the user for the
  document.
