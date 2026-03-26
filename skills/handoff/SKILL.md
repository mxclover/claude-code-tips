---
name: handoff
description: Write or update a handoff document so the next agent with fresh context can continue this work. Use when ending a long session, switching tasks, or preparing for another agent to continue.
---

Write or update a handoff document so the next agent with fresh context can continue this work efficiently.

## Steps

1. Check if HANDOFF.md already exists in the project root
2. If it exists, read it first to understand prior context before updating
3. Review the current conversation to extract all relevant context
4. Create or update the document using the template below

## Template

The document MUST include all of the following sections. If a section has no content, write "None" — do not omit the section.

```markdown
# Handoff — [Brief Task Title]

> Last updated: [date] by [agent/human]

## Goal
What we're trying to accomplish. Include the business/user motivation, not just the technical task.

## Architecture & Context
- Tech stack and key frameworks involved
- Relevant project structure (key directories, config files)
- Important constraints or conventions (e.g., i18n, server components only)

## Current Progress
What's been done so far. Use checkboxes:
- [x] Completed items
- [ ] Incomplete items

## Key Decisions & Trade-offs
Decisions made during this session and WHY. This prevents the next agent from re-debating settled questions.

## What Worked
Approaches that succeeded — so the next agent can build on them.

## What Didn't Work
Approaches that failed and WHY — so they're not repeated.

## Known Issues & Risks
Bugs, edge cases, or risks discovered but not yet addressed.

## Key File Map
| File | Role |
|------|------|
| path/to/file | Brief description |

## Environment & Dependencies
Any setup steps, env vars, or dependencies the next agent needs to know about.

## Next Steps
Clear, ordered action items for continuing. Be specific enough that someone with zero prior context can start immediately.
1. First thing to do
2. Second thing to do
```

## Guidelines

- **Be specific**: "Fixed the auth bug" is useless. "Fixed race condition in `useAuth` hook where concurrent refresh token calls caused logout — see `src/hooks/useAuth.ts:42`" is actionable.
- **Preserve history**: When updating an existing HANDOFF.md, preserve prior "What Didn't Work" entries — they are the most valuable section for avoiding repeated mistakes.
- **Include file paths**: Always use project-relative paths so the next agent can navigate directly.
- **Keep it scannable**: Use tables, checkboxes, and headers. The next agent should be able to understand the situation in 30 seconds.

Save as HANDOFF.md in the project root and tell the user the file path so they can start a fresh conversation with `Read HANDOFF.md` as the first message.
