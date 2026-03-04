#!/bin/bash
# Gate script for run.sh cron job.
# Exits 0 if prd.json has actionable stories (not all merged/skipped/invalid).
# Exits 1 if no prd.json or no actionable work remains.
#
# Usage in cron: ./scripts/check-has-work.sh && git fetch origin && ... && ./run.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PRD_FILE="$BOT_DIR/data/prd.json"

if [ ! -f "$PRD_FILE" ]; then
  echo "No prd.json found — skipping run."
  exit 1
fi

# Count stories with actionable statuses (anything not merged/skipped/invalid)
ACTIONABLE=$(jq '[.stories[] | select(.status != "merged" and .status != "skipped" and .status != "invalid")] | length' "$PRD_FILE" 2>/dev/null || echo "0")

if [ "$ACTIONABLE" -eq 0 ]; then
  echo "No actionable stories in prd.json — skipping run."
  exit 1
fi

echo "$ACTIONABLE actionable stories found — proceeding."
exit 0
