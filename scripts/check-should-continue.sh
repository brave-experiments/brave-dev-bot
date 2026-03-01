#!/bin/bash
# check-should-continue.sh
# Enforces the stop condition: after marking a story as merged, check if work should continue
# Exit codes:
#   0 = COMPLETE (all stories merged)
#   1 = STOP (story just completed, next iteration should pick up next story)
#   2 = CONTINUE (no story just completed, can continue working)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"

# Check if prd.json exists
if [ ! -f "$PRD_FILE" ]; then
  echo "ERROR: prd.json not found at $PRD_FILE"
  exit 3
fi

# Count non-merged stories
non_merged=$(jq '[.userStories[] | select(.status != "merged")] | length' "$PRD_FILE")

# Check if all stories are merged
if [ "$non_merged" -eq 0 ]; then
  echo "✅ COMPLETE: All stories merged!"
  echo "The agent should reply with: <promise>COMPLETE</promise>"
  exit 0
fi

# Check if we just completed a story (passed as first argument)
if [ "$1" == "story-completed" ]; then
  echo "🛑 STOP: Story completed. $non_merged stories remaining."
  echo "The agent MUST end the response now. Next iteration will pick up the next story."
  exit 1
fi

# Otherwise, continue working
echo "▶️  CONTINUE: $non_merged stories remaining, no story just completed."
exit 2
