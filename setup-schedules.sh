#!/bin/bash
# Idempotent cron job setup for brave-core-bot
# Run this script to install/update all cron jobs.
# All schedule changes should be made here and committed to source control.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_BIN="/home/bbondy/.local/bin/claude"
CLAUDE_TOOLS="Bash,Read,Glob,Grep,Write,Edit,Task,WebFetch"
LOG_DIR="$SCRIPT_DIR/.ignore"

# Build the crontab content
# Note: add-backlog-to-prd runs 1 hour before each run.sh invocation
CRON_JOBS=$(cat <<EOF
# === brave-core-bot scheduled jobs ===
# Managed by setup-schedules.sh - do not edit manually

# Add backlog to PRD (1 hour before each run.sh)
0 3,12 * * * cd $SCRIPT_DIR && $CLAUDE_BIN -p '/add-backlog-to-prd' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/add-backlog-cron.log 2>&1

# Main agent run
0 4,13 * * * cd $SCRIPT_DIR && ./run.sh 3 >> $LOG_DIR/run-cron.log 2>&1

# Review PRs
0 5,8,10,12,14,16,18,20 * * * cd $SCRIPT_DIR && $CLAUDE_BIN -p '/review-prs 1d open auto' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/review-prs-cron.log 2>&1

# Learnable pattern search
0 6 * * * cd $SCRIPT_DIR && $CLAUDE_BIN -p '/learnable-pattern-search --username netzenbot 2d' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/learnable-pattern-search-cron.log 2>&1

# Check Signal messages (every hour, only runs Claude if messages pending)
0 * * * * cd $SCRIPT_DIR && source .envrc && ./scripts/check-signal-messages.sh && $CLAUDE_BIN -p '/check-signal' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/check-signal-cron.log 2>&1

# === end brave-core-bot ===
EOF
)

# Extract existing crontab, stripping any previous brave-core-bot block
EXISTING=$(crontab -l 2>/dev/null || true)
CLEANED=$(echo "$EXISTING" | sed '/^# === brave-core-bot scheduled jobs ===/,/^# === end brave-core-bot ===/d')

# Remove any legacy brave-core-bot lines that predate the managed block
CLEANED=$(echo "$CLEANED" | grep -v "brave-core-bot" || true)

# Combine preserved entries with new block
NEW_CRONTAB=$(printf '%s\n%s\n' "$CLEANED" "$CRON_JOBS" | sed '/^$/N;/^\n$/d')

echo "$NEW_CRONTAB" | crontab -

echo "Cron jobs installed successfully."
echo ""
echo "Current schedule:"
echo "  Every hour - /check-signal (only if messages pending)"
echo "  03:00 - /add-backlog-to-prd"
echo "  04:00 - run.sh (3 iterations)"
echo "  05:00, 08-20 (even) - /review-prs"
echo "  06:00 - /learnable-pattern-search"
echo "  12:00 - /add-backlog-to-prd"
echo "  13:00 - run.sh (3 iterations)"
echo ""
crontab -l
