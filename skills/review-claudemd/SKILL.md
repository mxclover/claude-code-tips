---
name: review-claudemd
description: Review recent conversations to find improvements for CLAUDE.md files.
---

# Review CLAUDE.md from conversation history

Analyze recent conversations to improve both global (~/.claude/CLAUDE.md) and local (project) CLAUDE.md files.

## Step 1: Find conversation history

The project's conversation history is in `~/.claude/projects/`. The folder name is the project path with slashes replaced by dashes.

```bash
# Find the project folder (replace / with -)
PROJECT_PATH=$(pwd | sed 's|/|-|g' | sed 's|^-||')
CONVO_DIR=~/.claude/projects/-${PROJECT_PATH}
ls -lt "$CONVO_DIR"/*.jsonl | head -20
```

## Step 2: Extract recent conversations

Extract the 15-20 most recent conversations (excluding the current one) to a temp directory:

```bash
SCRATCH=/tmp/claudemd-review-$(date +%s)
mkdir -p "$SCRATCH"

# Get current session ID to exclude it
CURRENT_SESSION=$(tail -1 ~/.claude/history.jsonl 2>/dev/null | jq -r '.sessionId // empty')

for f in $(ls -t "$CONVO_DIR"/*.jsonl 2>/dev/null | head -25); do
  basename=$(basename "$f" .jsonl)

  # Skip current conversation
  [[ "$basename" == "$CURRENT_SESSION" ]] && continue

  # Skip empty or tiny files (<100 bytes — likely incomplete)
  [[ ! -s "$f" ]] && continue
  [[ $(wc -c < "$f") -lt 100 ]] && continue

  # Extract messages — handle both string and array content formats
  jq -r '
    if .type == "user" then
      "USER: " + (
        if (.message.content | type) == "string" then .message.content
        elif (.message.content | type) == "array" then
          [.message.content[] | select(.type == "text") | .text] | join("\n")
        else ""
        end
      )
    elif .type == "assistant" then
      "ASSISTANT: " + (
        if (.message.content | type) == "string" then .message.content
        elif (.message.content | type) == "array" then
          [.message.content[] | select(.type == "text") | .text] | join("\n")
        else ""
        end
      )
    else
      empty
    end
  ' "$f" 2>/dev/null | grep -v "^ASSISTANT: $" > "$SCRATCH/${basename}.txt"

  # Remove output files that ended up empty
  [[ ! -s "$SCRATCH/${basename}.txt" ]] && rm -f "$SCRATCH/${basename}.txt"
done

# Check we got enough conversations
FILE_COUNT=$(ls "$SCRATCH"/*.txt 2>/dev/null | wc -l)
echo "Extracted $FILE_COUNT conversations"
ls -lhS "$SCRATCH"
```

## Step 3: Spin up Sonnet subagents

Launch parallel Sonnet subagents to analyze conversations. Each agent should read:
- Global CLAUDE.md: `~/.claude/CLAUDE.md`
- Local CLAUDE.md: `./CLAUDE.md` (if exists)
- Batch of conversation files

Give each agent this prompt template:

```
Read:
1. Global CLAUDE.md: ~/.claude/CLAUDE.md
2. Local CLAUDE.md: [project]/CLAUDE.md
3. Conversations: [list of files]

Analyze the conversations against BOTH CLAUDE.md files. Find:
1. Instructions that exist but were violated (need reinforcement or rewording)
2. Patterns that should be added to LOCAL CLAUDE.md (project-specific)
3. Patterns that should be added to GLOBAL CLAUDE.md (applies everywhere)
4. Anything in either file that seems outdated or unnecessary

Be specific. Output bullet points only.
```

Batch conversations by size:
- Large (>100KB): 1-2 per agent
- Medium (10-100KB): 3-5 per agent
- Small (<10KB): 5-10 per agent

## Step 4: Aggregate findings

Combine results from all agents into a summary with these sections:

1. **Instructions violated** - existing rules that weren't followed (need stronger wording)
2. **Suggested additions - LOCAL** - project-specific patterns
3. **Suggested additions - GLOBAL** - patterns that apply everywhere
4. **Potentially outdated** - items that may no longer be relevant

Present as tables or bullet points. Ask user if they want edits drafted.
