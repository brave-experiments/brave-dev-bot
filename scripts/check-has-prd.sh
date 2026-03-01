#!/bin/bash
# Gate script for add-backlog-to-prd cron job.
# Exits 0 if prd.json exists (has a PRD to add backlog to).
# Exits 1 if no prd.json (nothing to update).
#
# Usage in cron: ./scripts/check-has-prd.sh && claude -p '/add-backlog-to-prd' ...

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PRD_FILE="$BOT_DIR/data/prd.json"

if [ ! -f "$PRD_FILE" ]; then
  echo "No prd.json found — skipping add-backlog-to-prd."
  exit 1
fi

echo "prd.json exists — proceeding with add-backlog-to-prd."
exit 0
