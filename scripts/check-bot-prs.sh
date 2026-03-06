#!/bin/bash
# Gate script for learnable-pattern-search cron job.
# If a username is provided, exits 0 if that user has reviewed merged PRs in the lookback window.
# If no username is provided, exits 0 if any merged PRs exist in the lookback window.
# Exits 1 if no recent PRs found (nothing to learn from).
#
# Usage in cron:
#   ./scripts/check-bot-prs.sh              # check for any merged PRs (2 day default)
#   ./scripts/check-bot-prs.sh 7            # any merged PRs in last 7 days
#   ./scripts/check-bot-prs.sh 2 myuser     # merged PRs reviewed by myuser in last 2 days

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/load-config.sh"

LOOKBACK_DAYS="${1:-2}"
BOT_USERNAME_ARG="${2:-}"

CUTOFF_DATE=$(date -u -v-${LOOKBACK_DAYS}d +%Y-%m-%d 2>/dev/null || date -u -d "$LOOKBACK_DAYS days ago" +%Y-%m-%d)

if [ -n "$BOT_USERNAME_ARG" ]; then
  PR_COUNT=$(gh search prs --repo "$BOT_PR_REPO" --reviewed-by "$BOT_USERNAME_ARG" --state merged --sort updated --limit 1 --json number -- "updated:>=$CUTOFF_DATE" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
else
  PR_COUNT=$(gh search prs --repo "$BOT_PR_REPO" --state merged --sort updated --limit 1 --json number -- "updated:>=$CUTOFF_DATE" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
fi

if [ "$PR_COUNT" = "0" ]; then
  if [ -n "$BOT_USERNAME_ARG" ]; then
    echo "No merged PRs reviewed by $BOT_USERNAME_ARG since $CUTOFF_DATE — skipping learnable-pattern-search."
  else
    echo "No merged PRs since $CUTOFF_DATE — skipping learnable-pattern-search."
  fi
  exit 1
fi

echo "Found recent merged PRs — proceeding with learnable-pattern-search."
exit 0
