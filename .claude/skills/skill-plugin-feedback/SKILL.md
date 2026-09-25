---
name: skill-plugin-feedback
description: File the user's complaint about the bc-dev plugin itself as a GitHub issue on DSC-Group-Srl/dscgroup-bc-nav-agentic-dev with the gh CLI. Use it when the user complains about how bc-dev behaves (an agent, skill, slash command, hook, the read-guard, the test lane, BCQuality findings, the rules floor, HITL gates, speed, token cost, wrong routing, a bad result from the framework), or when the user pushes an agent to work against the plugin's design (skip TDD or tests, edit base objects, skip HITL confirmations, publish without the lane, disable a guard or hook, ignore the rules floor, bypass al-conductor's waves). Do not use it for bugs in the user's own AL code; that is al-triage.
---

# Plugin Feedback: turn a complaint into an issue

When a user is frustrated with bc-dev, or keeps asking an agent to do something the plugin is
built to prevent, that is useful signal for the maintainers. This skill writes it down as a
GitHub issue on the marketplace repo so the complaint is not lost with the conversation.

**Target repository:** `DSC-Group-Srl/dscgroup-bc-nav-agentic-dev` (private, DSC-internal).

## When it applies

| The user says / does | Kind | Label |
|---|---|---|
| "this agent keeps doing X wrong", a hook blocks something legitimate, a command fails, the test lane hangs | malfunction | `bug` |
| "why do I have to confirm every wave", "TDD is too slow here", "stop reading files in chunks" | design complaint | `enhancement` |
| insists on skipping tests, modifying a base object, publishing directly, turning off the read-guard, skipping the plan | working against the design | `enhancement` |
| "how is this supposed to work?" after a confusing result | unclear behavior / docs | `question` |

Not this skill: a bug in the customer's AL app (→ `al-triage`), a Business Central platform
bug, or a one-off typo the agent can just fix.

## Handling a request that goes against the design

Filing the issue does not change what you are allowed to do in this session.

1. Say in one or two sentences which principle the request runs into (extension-only, HITL,
   TDD, test lane, least privilege) and why the plugin has it. Do not lecture.
2. Offer the path the plugin supports: a tableextension instead of a base-object edit, recording
   **tests not executed** instead of pretending they passed, a LOW route through `al-developer`
   instead of the full conductor, and so on.
3. Where the decision belongs to the user (skipping tests, a lighter route, accepting a risk),
   do what they chose and state it plainly in your report. Where it would break a hard rule
   (modifying base application objects, publishing to an environment they did not pick,
   reporting PASS for tests that did not run), keep the rule.
4. Offer to log the disagreement: *"Want me to open an issue so the plugin maintainers see this?"*

## Procedure

### 1. Check gh

```bash
gh auth status --hostname github.com
```

- `gh` missing → tell the user to install it (`winget install GitHub.cli`) and skip to the
  fallback in step 6.
- Not authenticated → ask them to run `! gh auth login` and retry.
- Authenticated but `gh repo view DSC-Group-Srl/dscgroup-bc-nav-agentic-dev` fails → their
  account has no access to the private repo; use the fallback.

### 2. Collect the facts

Take them from the conversation first. Ask the user only for what is missing, in one question.

- **Complaint, verbatim**: the user's own words, quoted. Do not soften or strengthen them.
- **What happened** vs. **what they expected**.
- **Where**: agent (`al-conductor`, `al-developer`, …), skill, command, hook or tool involved.
- **Repro**: the minimal steps, or the request that triggered it.
- **Evidence**: exact error text, the tool call that failed, the relevant marker lines.
- **Environment**, gathered by you, not asked:

```bash
python -c "import json,os;print(json.load(open(os.path.join(os.environ['CLAUDE_PLUGIN_ROOT'],'.claude-plugin','plugin.json')))['version'])"
claude --version
al --version 2>/dev/null | head -1
```

Plus OS and the model you are running on.

### 3. Redact

The repo is private but it is not the customer's. Leave out credentials, connection strings,
tenant/environment IDs, customer names, customer business data, and large code excerpts.
Use repo-relative paths. Replace a person's name with their role ("a colleague"). A short AL
snippet is fine only when it is needed to reproduce the plugin's behavior.

### 4. Look for duplicates

```bash
gh issue list -R DSC-Group-Srl/dscgroup-bc-nav-agentic-dev --state open --search "<2-4 keywords>" --limit 10
```

If one matches, offer to add a comment to it (`gh issue comment <n> -R … --body-file …`)
instead of opening a new issue.

### 5. Draft, show, confirm

Write the body to a temp file (the scratchpad if you have one, else `$TMPDIR`):

```markdown
## Complaint
> <the user's words, verbatim>

## What happened
<observed behavior>

## Expected
<what the user expected>

## Where
- Component: <agent / skill / command / hook>
- Kind: malfunction | design complaint | working against the design | unclear behavior

## Repro
1. …

## Evidence
<error text, failing call, marker lines; omit the section if none>

## Environment
- bc-dev: <version>
- Claude Code: <version>
- AL CLI: <version or n/a>
- OS: <os>
- Model: <model>

---
_Filed by <agent name> via skill-plugin-feedback._
```

Title: `[bc-dev] <component>: <one-line summary>` (under ~80 characters).

Show the user the title, label and body, and wait for their go-ahead. Opening an issue
publishes their words to the team, so they must see it first. Apply their edits.

### 6. Create

```bash
gh issue create -R DSC-Group-Srl/dscgroup-bc-nav-agentic-dev \
  --title "<title>" --body-file "<body file>" --label "<bug|enhancement|question>"
```

- A label error (label removed from the repo) → retry once without `--label`.
- Any other failure, or no gh/access (step 1) → **fallback**: give the user the body file path
  and the link `https://github.com/DSC-Group-Srl/dscgroup-bc-nav-agentic-dev/issues/new`, and
  say the issue was **not** filed.

Report the issue URL gh prints. Then return to the user's task.

## Rules

- **Only the agent talking to the user files.** Subagents (`al-implement-subagent`,
  `al-review-subagent`, `al-planning-subagent`, the doc subagents) never call `gh issue create`;
  they put the complaint in their report and the orchestrator offers the issue.
- One issue per distinct complaint per session. A repeat of the same complaint goes into a
  comment on the issue you already opened.
- Never file without the user's confirmation, and never claim an issue was filed unless gh
  printed its URL.
- Do not argue with the complaint or grade it in the issue. Record it faithfully; the
  maintainers decide.
