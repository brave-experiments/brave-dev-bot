#!/bin/bash
# Idempotent cron job setup for brave-core-bot
# Run this script to install/update all cron jobs.
# All schedule changes should be made here and committed to source control.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_BIN="/home/bbondy/.local/bin/claude"
CLAUDE_TOOLS="Bash,Read,Glob,Grep,Write,Edit,Task,WebFetch"
LOG_DIR="$PROJECT_ROOT/.ignore"

# Build the crontab content
# Note: add-backlog-to-prd runs 1 hour before each run.sh invocation
CRON_JOBS=$(cat <<EOF
# === brave-core-bot scheduled jobs ===
# Managed by sync-schedules.sh - do not edit manually
SHELL=/bin/bash
PATH=/home/bbondy/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

# Add backlog to PRD (15 min before each run.sh) — skip if no prd.json
45 3,7,11,15,19,23 * * * cd $PROJECT_ROOT && git fetch origin && git checkout master && git reset --hard origin/master && git submodule update --init --recursive && source .envrc && ./scripts/check-has-prd.sh && $CLAUDE_BIN -p '/add-backlog-to-prd' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/add-backlog-cron.log 2>&1

# Main agent run — run.sh has its own prd check built in
10 0,4,8,12,16,20 * * * cd $PROJECT_ROOT && git fetch origin && git checkout master && git reset --hard origin/master && git submodule update --init --recursive && source .envrc && ./run.sh 3 >> $LOG_DIR/run-cron.log 2>&1

# Review PRs — skip if no recent open PRs
0 2,5,8-20,23 * * * cd $PROJECT_ROOT && git fetch origin && git checkout master && git reset --hard origin/master && git submodule update --init --recursive && source .envrc && ./scripts/check-new-prs.sh && $CLAUDE_BIN -p '/review-prs 1d open auto reviewer-priority' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/review-prs-cron.log 2>&1

# Learnable pattern search — skip if no recent merged PRs
0 6 * * * cd $PROJECT_ROOT && git fetch origin && git checkout master && git reset --hard origin/master && git submodule update --init --recursive && source .envrc && ./scripts/check-bot-prs.sh && $CLAUDE_BIN -p '/learnable-pattern-search 2d' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/learnable-pattern-search-cron.log 2>&1

# Check Signal messages (every 5 min, offset to avoid git lock contention with other jobs)
1,6,11,16,21,26,31,36,41,46,51,56 * * * * cd $PROJECT_ROOT && git fetch origin && git checkout master && git reset --hard origin/master && git submodule update --init --recursive && source .envrc && ./scripts/check-signal-messages.sh && $CLAUDE_BIN -p '/check-signal' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/check-signal-cron.log 2>&1

# Sync src/brave origin/master from upstream/master (daily at 00:01)
1 0 * * * cd /home/bbondy/projects/brave-browser/src/brave && git fetch upstream && git push origin upstream/master:master && git fetch origin >> $LOG_DIR/sync-brave-core-cron.log 2>&1

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
echo "  00:01 - sync src/brave origin/master from upstream"
echo "  00:10 - run.sh (3 iterations)"
echo "  Every 5 min at :01,:06,:11,...,:56 - /check-signal (only if messages pending)"
echo "  03:45, 07:45, 11:45, 15:45, 19:45, 23:45 - /add-backlog-to-prd"
echo "  04:00, 08:00, 12:00, 16:00, 20:00 - run.sh (3 iterations)"
echo "  08:00-20:00 (hourly), 23:00, 02:00, 05:00 - /review-prs"
echo "  06:00 - /learnable-pattern-search"
echo ""
crontab -l
