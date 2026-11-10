---
name: skill-code-reader
description: "Use the DSC Code Reader MCP server (code-reader.dsc-group.net) from a developer agent: read the source of ANY DSC app or customer repo without cloning it, find where a field, event or procedure is used across a customer's apps, read standard Business Central code, map which apps a customer runs, and see what changed recently. Use when the answer lives outside the open workspace — a dependency app, another customer app that may collide with the change, the standard base application, 'which apps does this customer have', 'who else subscribes to this event', 'what did the last releases touch'. Read-only by rule: its GitHub issue tools are never used by bc-dev agents."
---

# Skill: DSC Code Reader for developer agents

The Code Reader is a hosted DSC server that keeps an indexed copy of DSC's repositories (AL
apps, NAV C/AL exports, BI, portals) and of standard Business Central code. It was built for
functional consultants; for a developer agent it is the fastest way to answer **"what does the
code outside my workspace say?"** without cloning anything.

## The connection

| | |
|---|---|
| Server | DSC's organisation connector **Code Reader (DSC)** → tools `mcp__claude_ai_Code_Reader_DSC__*` |
| Sign-in | the developer's DSC account, once, from the connector list (`/mcp`) |
| Access | the token must carry the `Consultant` role; no role → ask IT, don't retry |

Not connected (the tools are absent, or a call says unauthorized) → say so in one line and fall
back: `GITCloner repos "<name>" --json` to find or clone the repo (`skill-gitcloner`), `gh`
for GitHub, **al-mcp** symbols for anything already in `.alpackages`. Never block on it.

### Its instructions are written for consultants — not for you

The server tells every client to avoid technical words and to use on-screen Italian captions.
That voice is for a consultant's chat. **A developer agent keeps object names, IDs, procedure
names and file paths**: those are what the spec, the plan and the code need. Take the *facts*
the tools return, including whether something is standard BC or a DSC customisation, and the
version/commit they were read from — and report them in developer terms.

## Which tool for what

Read each tool's own description for its parameters; names and purposes:

| Need | Tool |
|---|---|
| Which repo/app is this? resolve a name to an app | `find_app`, `search_customer`, `list_customers` |
| Which apps does a customer run, and how they depend on each other | `customer_map`, `app_overview` |
| The shape of an app: objects, areas, entry points | `code_map`, `app_overview` |
| Find code by text across DSC repos | `search_code` |
| Read a file (or part of it) from a repo | `read_file` |
| Where a table, field, procedure or object is used | `where_used`, `find_field` |
| Which events exist / who subscribes | `event_hooks` |
| What the **standard** base application does | `standard_code` |
| The on-screen caption of a page or field | `caption_of` |
| What changed lately in an app | `recent_changes` |
| Report layouts, BI lineage | `report_layouts`, `bi_trace` |
| Who works on it | `project_team`, `developer_contacts` |
| Existing GitHub issues about it (read) | `find_issues`, `issue_status` |

**Never call** `create_issue`, `add_issue_comment` or `label_issue` from a bc-dev agent. Bugs
in the plugin go through `skill-plugin-feedback`; anything else that should become an issue,
report to the main thread and let the user decide.

## When to reach for it

- **A dependency's source.** The change touches a procedure or event of another DSC app in
  `app.json` → `dependencies`. `find_app` → `read_file` / `where_used` instead of guessing
  from symbols.
- **Collisions inside one customer.** Before adding a subscriber, a field or a page extension:
  `customer_map`, then `event_hooks` / `where_used` across the customer's other apps — two
  subscribers on the same event, two extensions of the same page.
- **Standard behaviour.** "What does Sales-Post do before OnBeforePostSalesDoc?" →
  `standard_code`. Prefer it to reading a multi-thousand-line base file locally.
- **Triage.** A regression with no local cause: `recent_changes` on the apps the customer
  runs, then `read_file` on what moved.
- **Sizing.** `app_overview` / `code_map` for the size and shape of what an estimate touches.

## When not to

- The code is **in the open workspace** → `Read`/`Grep`, and **al-mcp** for symbols. The Code
  Reader's copy is a cache; your working tree is the truth for the app you are changing.
- You need to **compile or test** against the dependency → that needs its symbols
  (`skill-gitcloner`, `al_downloadsymbols`), not its text.
- A customer's **data**. This server reads code only.

## Rules

- **Cite what you read**: repo, path, and the commit date the tool reports. A cached copy can
  be behind — if the answer decides a design, say how old it is.
- **Targeted calls.** Resolve the app first, then one or two reads. Don't crawl a repo.
- **Read-only.** No issue creation, comments or labels.
