---
name: half-clone
description: Clone the later half of the current conversation, discarding earlier context to reduce token usage while preserving recent work.
---

Clone the later half of the current conversation, discarding earlier context to reduce token usage while preserving recent work.

## Steps

1. Get the current session ID and project path:
   ```bash
   tail -1 ~/.claude/history.jsonl | jq -r '[.sessionId, .project] | @tsv'
   ```
   - If history.jsonl is empty or missing, inform the user that there is no conversation history to clone.

2. Find half-clone-conversation.sh:
   ```bash
   find ~/.claude -name "half-clone-conversation.sh" 2>/dev/null | sort -V | tail -1
   ```
   - This finds the script whether installed via plugin or manual symlink
   - Uses version sort to prefer the latest version if multiple exist
   - **If the script is not found**, inform the user that the half-clone plugin is not installed. They can install it from: https://github.com/anthropics/claude-code/tree/main/plugins

3. Preview the conversation to verify the session ID:
   ```bash
   <script-path> --preview <session-id> <project-path>
   ```
   - Check that the first and last messages match the current conversation

4. Run the clone: `<script-path> <session-id> <project-path>`
   - Always pass the project path from the history entry, not the current working directory

5. Tell the user they can access the half-cloned conversation with `claude -r` and look for the one marked `[HALF-CLONE <timestamp>]` (e.g., `[HALF-CLONE Jan 7 14:30]`). The script automatically appends a reference to the original conversation at the end of the cloned file.
