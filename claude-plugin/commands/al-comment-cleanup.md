---
description: >
  Remove every non-documentation comment from an AL repo (DSC hard rule: no comments in code).
  Deletes explanations, section headers, TODOs, change markers and commented-out code; moves real
  documentation into XML doc comments; lists the choices a comment was defending so the user can
  judge them. Use on a repo full of AI-left comments, or when dredd reports Check J findings.
allowed-tools: Read, Grep, Glob, Bash, Task
argument-hint: "[folder or app path]"
---

# AL comment cleanup

DSC hard rule: code carries no comments except `///` doc comments (and, in test codeunits, the
`// [FEATURE] [SCENARIO] [GIVEN] [WHEN] [THEN]` lines). The comment guard stops new ones; this
command removes the ones already there. Old comments are not harmless: agents read them as
instructions, and many were left by AI and are stale or wrong.

Scope: `$ARGUMENTS`, or the repo root when empty.

## 1. Inventory

```bash
python "${CLAUDE_PLUGIN_ROOT}/tools/comment-guard/comment_guard.py" scan <scope> --json > "<scratchpad>/comments.json"
```

Show the user one block: total comments, files, the 5 files with the most, and how many look like
commented-out code. Branch: follow the git branch policy (stay on the current branch unless the
user agrees to a new one). Then proceed: the user asked for the cleanup by running this command.

## 2. Batches

Split the files into batches of about 15 files or 300 comments, one feature folder per batch where
possible. Batches touch disjoint files, so run up to 3 `bc-dev:al-developer` tasks in parallel.
The main thread never edits AL itself (main-thread guard).

Brief for each task (fill in the file list and the comment list for those files):

> Remove the comments listed below from these AL files. DSC hard rule: no comments in code except
> `///` doc comments (and `// [GIVEN]`-style lines in test codeunits). Do not commit and do not
> create branches: other batches run in the same working tree. For each comment decide:
> 1. **Restates the code, section header, ticket or change marker (`//<< MD 050624`), TODO with
>    no open work, commented-out code** → delete it.
> 2. **Documentation** (what a procedure is for, who calls it, an ordering or transaction
>    constraint such as a required `Commit()`, an edge case) → move it into the enclosing
>    procedure's or object's `///` doc comment (`<summary>`, or `<remarks>` for the rest), then
>    delete the inline comment. Add the doc comment if the procedure has none.
> 3. **The code can say it** → rename a local variable or a local/internal procedure, extract a
>    small local procedure whose name states the intent, introduce a named constant or Label.
>    Never rename anything public, published or used by another app, and never change behaviour.
> 4. **Defends a choice** ("we do X because Y", "workaround", "hack", "not ideal") → apply 2 or 3,
>    and also add the choice to the Doubts list in your report with file:line and one sentence.
> 5. **Open work** (TODO/FIXME that still applies) → delete it and add it to the Open work list.
>
> Compile with every analyzer on after the batch (same as any change). The diff must contain only
> comment removals, doc-comment additions and the renames/extractions from 3; no logic change.
> Return: files changed, comments removed, moved to doc comments, renamed/extracted, the Doubts
> list and the Open work list, and the compile result.

## 3. Verify

Re-run the scan on the scope: it must report 0. Any remaining hit is either a missed comment
(send it back) or a scanner false positive (a `//` inside an unusual string literal): report those
to the user by file:line, never wrap them in a suppression.

Then commit on the current branch, one commit per app: `refactor: remove non-documentation
comments (DSC no-comments rule)`.

## 4. Report to the user

- comments removed, files touched, compile result;
- moved into doc comments: count;
- **Doubts**: the choices comments were defending, file:line + one sentence each. These are the
  spots where an agent was not sure. Offer to open a triage on any of them;
- **Open work**: the TODOs that still applied, as a list the user can turn into Issues;
- the commit(s) made. Push only when the user says so.
