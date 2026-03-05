#!/bin/bash
# Gate script for review-prs cron job.
# Exits 0 if there are open PRs in brave/brave-core updated in the last day.
# Exits 1 if no recent PRs found (nothing to review).
#
# Usage in cron: ./scripts/check-new-prs.sh && claude -p '/review-prs 1d open auto' ...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/load-config.sh"

# Quick check: are there any open PRs updated in the last 24 hours?
CUTOFF_DATE=$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d "1 day ago" +%Y-%m-%d)

PR_COUNT=$(gh search prs --repo "$BOT_PR_REPO" --state open --sort updated --limit 1 --json number -- "updated:>=$CUTOFF_DATE" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$PR_COUNT" = "0" ]; then
  echo "No open PRs updated since $CUTOFF_DATE — skipping review-prs."
  exit 1
fi

echo "Found recent open PRs — proceeding with review-prs."
exit 0
