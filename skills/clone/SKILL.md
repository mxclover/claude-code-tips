---
name: clone
description: Clone the current conversation so the user can branch off and try a different approach.
---

Clone the current conversation so the user can branch off and try a different approach.

## Steps

1. Get the current session ID and project path:
   ```bash
   tail -1 ~/.claude/history.jsonl | jq -r '[.sessionId, .project] | @tsv'
   ```
   - If history.jsonl is empty or missing, inform the user that there is no conversation history to clone.

2. Find clone-conversation.sh:
   ```bash
   find ~/.claude -name "clone-conversation.sh" 2>/dev/null | sort -V | tail -1
   ```
   - This finds the script whether installed via plugin or manual symlink
   - Uses version sort to prefer the latest version if multiple exist
   - **If the script is not found**, inform the user that the clone plugin is not installed. They can install it from: https://github.com/anthropics/claude-code/tree/main/plugins

3. Run: `<script-path> <session-id> <project-path>`
   - Always pass the project path from the history entry, not the current working directory

4. Tell the user they can access the cloned conversation with `claude -r` and look for the one marked `[CLONED <timestamp>]` (e.g., `[CLONED Jan 7 14:30]`)
