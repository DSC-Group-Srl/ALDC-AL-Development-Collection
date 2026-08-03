---
description: >
  Generate or update CLAUDE.md file tracking project conventions, decisions, and
  configuration for continuity across sessions. Use when you need to create or update
  project memory, track decisions, or maintain session continuity.
allowed-tools: Read, Grep, Glob, Write, Edit
---

# AL Project Memory (CLAUDE.md) Generator

Generate and maintain a `CLAUDE.md` file that serves as the **project memory and configuration** - tracking conventions, decisions, learnings, and important context across development sessions.

## Purpose

The `CLAUDE.md` file provides:
- **Project Conventions**: Naming, structure, and coding standards for this project
- **Session Continuity**: What happened in previous sessions
- **Decision Log**: Why things were done a certain way
- **Problem/Solution Patterns**: What issues occurred and how they were solved
- **TODO Tracking**: What needs to be done next
- **Learning Journal**: Insights gained during development
- **Agent Context**: Loaded automatically by agents for consistent behavior

This enables AI assistants and developers to pick up where they left off and build on previous work. The `CLAUDE.md` file replaces the legacy `memory.md` pattern, leveraging Claude Code's built-in project memory mechanism.

## Execution Steps

### 1. Initialize CLAUDE.md Structure

If `CLAUDE.md` doesn't exist, create with this template:

```markdown
# Project Configuration - [Extension Name]

> **Purpose**: Project conventions, decisions, and configuration for AI agents and developers
> **Maintained by**: AI assistants and developers
> **Last Updated**: [Date]

## Project Conventions

**Naming Prefix**: [e.g., DSC]
**Table ID Range**: [e.g., 50100..50199]
**Page ID Range**: [e.g., 50100..50199]
**Codeunit ID Range**: [e.g., 50100..50199]
**Report ID Range**: [e.g., 50100..50199]
**Query ID Range**: [e.g., 50100..50199]

**Structure**: Feature-based organization (`src/feature/subfeature/`)
**Events**: Event-driven architecture preferred
**Permissions**: Least-privilege principle

## Quick Reference

**Current Focus**: [What we're working on now]
**Next Steps**: [Immediate next actions]
**Blockers**: [Current blockers if any]

---

### [Date] - Session [N]

**Focus**: [What was worked on]

**Completed**:
- [Task 1]
- [Task 2]

**Decisions Made**:
- **[Decision]**: [Rationale]

**Problems Encountered**:
- **[Problem]**: [Solution or workaround]

**Next Session**:
- [ ] [Task to continue]
- [ ] [Task to start]

**Notes**:
- [Any important observations]

---

## Decision Log

### [Date] - [Decision Title]

**Context**: [Why this decision needed to be made]  
**Options Considered**:
1. [Option 1]: [Pros/Cons]
2. [Option 2]: [Pros/Cons]

**Decision**: [What was chosen]  
**Rationale**: [Why this option]  
**Impact**: [What this affects]  
**Review Date**: [When to revisit if applicable]

---

## Problem/Solution Patterns

### [Problem Category] - [Specific Issue]

**Symptom**: [What we observed]  
**Root Cause**: [What was actually wrong]  
**Solution**: [How we fixed it]  
**Prevention**: [How to avoid in future]  
**Related Code**: [File paths or line numbers]

---

## Learning Journal

### [Date] - [Topic/Insight]

**What We Learned**: [Key insight or pattern discovered]  
**Why It Matters**: [Impact on project]  
**Where Applied**: [Code locations]  
**Resources**: [Links to docs, articles that helped]

---

## TODO & Backlog

### High Priority
- [ ] [Task] - [Why important] - [Target date]

### Medium Priority
- [ ] [Task] - [Context]

### Future Ideas
- [ ] [Idea] - [Rationale]

### Done ✅
- [x] [Completed task] - [Date completed]
```

### 2. If CLAUDE.md Exists - Update It

**Add new session entry:**
```
# Check for recent changes
Bash: git diff / git status

# Check current problems
Bash: al compile   (read the compiler output)

# Check open work
the TodoWrite list
```

**Update with:**
- New session log entry at the top
- Any decisions made in this session
- Problems solved
- Learnings discovered
- Progress on existing TODOs
- New TODOs identified

### 3. Session Entry Creation

For each development session, document:

**Format:**
```markdown
### [Today's Date] - Session N

**Focus**: [Main task(s) worked on]

**Completed**:
- ✅ [Specific accomplishment 1]
- ✅ [Specific accomplishment 2]

**Decisions Made**:
- **[Decision Topic]**: [Choice made and brief reason]

**Problems Encountered**:
- **[Problem Description]**: 
  - Symptom: [What we saw]
  - Cause: [Root cause if known]
  - Solution: [How fixed or workaround]

**Learnings**:
- [Insight gained from this session]

**Next Session**:
- [ ] [Continue/start task 1]
- [ ] [Continue/start task 2]

**Files Changed**:
- `[file path]`: [What changed]

**Notes**:
- [Any other important context]
```

### 4. Decision Documentation

When architectural/technical decisions are made:

```markdown
### [Date] - [Decision Title]

**Context**: 
[What situation required this decision? What were we trying to solve?]

**Options Considered**:
1. **[Option 1]**
   - Pros: [Benefits]
   - Cons: [Drawbacks]
   
2. **[Option 2]**
   - Pros: [Benefits]
   - Cons: [Drawbacks]

**Decision**: [What we chose]

**Rationale**: 
[Why this option was best given the context, constraints, and requirements]

**Implementation Notes**:
- [Key points about how this was implemented]

**Impact**: 
- Code: [What code was affected]
- Performance: [Performance implications if any]
- Maintenance: [Ongoing maintenance considerations]

**Review Date**: [Optional - when to revisit this decision]

**References**:
- [Links to documentation, discussions, etc.]
```

### 5. Problem/Solution Pattern Documentation

When bugs are fixed or challenges overcome:

```markdown
### [Category] - [Problem Title]

**Date Encountered**: [Date]

**Symptom**: 
[What behavior did we observe? What was wrong?]

**Context**:
[When does this happen? What conditions trigger it?]

**Root Cause**: 
[What was actually causing the problem?]

**Solution**: 
[How we fixed it - code changes, configuration, etc.]

**Code Changed**:
```al
// Before
[problematic code]

// After
[fixed code]
```

**Prevention**: 
[How to avoid this in the future - pattern to follow, test to add, etc.]

**Related**:
- Files: `[file paths]`
- Similar issues: [References to related problems]
- Documentation: [Links to relevant docs]
```

### 6. Learning Capture

When discovering new patterns or insights:

```markdown
### [Date] - [Topic]

**What We Learned**:
[The key insight, pattern, or understanding gained]

**How We Learned It**:
[Through debugging, documentation, experimentation, etc.]

**Why It Matters**:
[Impact on the project, development efficiency, code quality, etc.]

**Where Applied**:
- `[file path]`: [How this learning was applied]

**Best Practice**:
[If this leads to a best practice for this project]

**Resources**:
- [Links to documentation that helped]
- [Code examples from BC or other sources]
```

### 7. Update Quick Reference

At the end of each session, update the top section:

```markdown
## Quick Reference

**Current Focus**: [Update with current work]  
**Last Session**: [Date of last session]  
**Next Steps**: 
1. [Most imMEDIUMte next action]
2. [Second priority]

**Active Blockers**: 
- [Blocker 1]: [Status]

**Recent Achievements** (Last 7 days):
- [Achievement 1]
- [Achievement 2]

**Active Branch**: [Git branch if relevant]
```

### 8. Maintenance & Cleanup

**Weekly:**
- Move completed TODOs to "Done" section
- Archive old session entries (keep last 10, summarize older ones)
- Update code evolution section if major changes

**Monthly:**
- Review decision log - mark outdated decisions
- Consolidate similar problem/solution patterns
- Clean up deprecated patterns section
- Update environment notes if setup changed

## Output Format

Deliver:
1. ✅ Created/updated `CLAUDE.md` at project root
2. ✅ Summary of key additions made
3. ✅ Highlight any important patterns/decisions documented
4. ✅ Suggest next session focus based on TODOs

## Integration with Development Workflow

### At Session Start
```markdown
**AI Assistant**: Load CLAUDE.md to understand:
- What was done last session
- What the plan was for this session
- Any blockers or important context
```

### During Development
```markdown
**Capture**:
- Decisions as they're made
- Problems as they're encountered
- Learnings as they're discovered
```

### At Session End
```markdown
**Update**:
- Session log with completion status
- TODOs with progress
- Quick Reference with next steps
```

## Key Principles

- **Chronological**: Most recent first for quick access
- **Searchable**: Use clear headings and keywords
- **Contextual**: Include enough context to understand later
- **Actionable**: TODOs and next steps are concrete
- **Honest**: Document failures and mistakes - they're learning opportunities
- **Linked**: Reference files, line numbers, other sections
- **Concise**: Important but brief - detailed docs go in context.md

## Success Criteria

A successful `CLAUDE.md` enables:
- ✅ Picking up project after weeks away
- ✅ Understanding why code is the way it is
- ✅ Avoiding repeat mistakes
- ✅ Building on previous learnings
- ✅ Tracking progress over time
- ✅ AI assistant continuity across sessions

## Collaboration

When multiple developers work on the project:
- Each adds their session entries
- Decisions are collaborative - note who participated
- Problem solutions are shared learning
- TODOs can be assigned to people
- Communication log tracks cross-team discussions
