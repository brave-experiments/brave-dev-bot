#!/bin/bash
# Idempotent cron job setup for brave-dev-bot
# Run this script to install/update all cron jobs.
# All schedule changes should be made here and committed to source control.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/load-config.sh"

CLAUDE_BIN="$BOT_CLAUDE_BIN"
CLAUDE_TOOLS="Bash,Read,Glob,Grep,Write,Edit,Task,WebFetch"
LOG_DIR="$PROJECT_ROOT/.ignore"

# Derive the PATH from CLAUDE_BIN's directory
CLAUDE_BIN_DIR=$(dirname "$CLAUDE_BIN")

# Resolve sync repo path from config (optional — only for projects that sync from upstream)
SYNC_REPO_ENABLED=$(bot_config '.schedules.syncRepo')
SYNC_REPO_PATH=$(bot_config '.schedules.syncRepoPath')

# Use project name for cron block marker to allow multiple projects on same machine
# Avoid special regex characters — use parentheses instead of brackets so the
# marker survives sed pattern matching without escaping.
# Bot repo's own default branch (for cron git checkout/reset)
BOT_REPO_BRANCH=$(bot_config '.project.botRepoBranch')
BOT_REPO_BRANCH="${BOT_REPO_BRANCH:-master}"

CRON_MARKER="brave-dev-bot ($BOT_PROJECT_NAME)"

# Build the crontab content
# Note: add-backlog-to-prd runs 1 hour before each run.sh invocation
CRON_JOBS=$(cat <<EOF
# === $CRON_MARKER scheduled jobs ===
# Managed by sync-schedules.sh - do not edit manually
SHELL=/bin/bash
PATH=$CLAUDE_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

# Add backlog to PRD (15 min before each run.sh) — skip if no prd.json
# Gate check runs before git sync to avoid wasted fetches
45 3,7,15,19 * * * cd $PROJECT_ROOT && source .envrc && ./scripts/check-has-prd.sh && git fetch origin && git checkout $BOT_REPO_BRANCH && git reset --hard origin/$BOT_REPO_BRANCH && ./scripts/update-submodule.sh && ./scripts/with-lock.sh add-backlog -- $CLAUDE_BIN -p '/add-backlog-to-prd' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/add-backlog-cron.log 2>&1

# Main agent run — skip if no actionable stories
# Gate check runs before git sync to avoid wasted fetches
10 0,8,12,16 * * * cd $PROJECT_ROOT && source .envrc && ./scripts/check-has-work.sh && git fetch origin && git checkout $BOT_REPO_BRANCH && git reset --hard origin/$BOT_REPO_BRANCH && ./scripts/update-submodule.sh && ./run.sh 3 >> $LOG_DIR/run-cron.log 2>&1

# Review PRs — skip if no recent open PRs
# Gate check runs before git sync to avoid wasted fetches
0 0,4,8,10,12,14,16,18,20 * * * cd $PROJECT_ROOT && source .envrc && ./scripts/check-new-prs.sh && git fetch origin && git checkout $BOT_REPO_BRANCH && git reset --hard origin/$BOT_REPO_BRANCH && ./scripts/update-submodule.sh && ./scripts/with-lock.sh review-prs -- $CLAUDE_BIN -p '/review-prs 1d open auto reviewer-priority' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/review-prs-cron.log 2>&1

# Learnable pattern search — skip if no recent merged PRs
# Gate check runs before git sync to avoid wasted fetches
0 6 * * * cd $PROJECT_ROOT && source .envrc && ./scripts/check-bot-prs.sh && git fetch origin && git checkout $BOT_REPO_BRANCH && git reset --hard origin/$BOT_REPO_BRANCH && ./scripts/update-submodule.sh && ./scripts/with-lock.sh learnable-pattern-search -- $CLAUDE_BIN -p '/learnable-pattern-search 2d' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/learnable-pattern-search-cron.log 2>&1

# Check Signal messages (every 5 min, offset to avoid git lock contention with other jobs)
# Gate check runs before git sync to avoid wasted fetches (288 runs/day, most exit early)
1,6,11,16,21,26,31,36,41,46,51,56 * * * * cd $PROJECT_ROOT && source .envrc && ./scripts/check-signal-messages.sh && git fetch origin && git checkout $BOT_REPO_BRANCH && git reset --hard origin/$BOT_REPO_BRANCH && ./scripts/update-submodule.sh && ./scripts/with-lock.sh check-signal -- $CLAUDE_BIN -p '/check-signal' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/check-signal-cron.log 2>&1

# Update best practices from upstream Chromium docs (monthly, 1st of each month)
15 4 1 * * cd $PROJECT_ROOT && source .envrc && git fetch origin && git checkout $BOT_REPO_BRANCH && git reset --hard origin/$BOT_REPO_BRANCH && ./scripts/update-submodule.sh && ./scripts/with-lock.sh update-best-practices -- $CLAUDE_BIN -p '/update-best-practices' --allowedTools '$CLAUDE_TOOLS' >> $LOG_DIR/update-best-practices-cron.log 2>&1

$(if [ "$SYNC_REPO_ENABLED" = "true" ] && [ -n "$SYNC_REPO_PATH" ]; then
cat <<SYNC
# Sync repo origin/$BOT_DEFAULT_BRANCH from upstream/$BOT_DEFAULT_BRANCH (daily at 00:01)
1 0 * * * cd $SYNC_REPO_PATH && git fetch upstream && git push origin upstream/$BOT_DEFAULT_BRANCH:$BOT_DEFAULT_BRANCH && git fetch origin >> $LOG_DIR/sync-repo-cron.log 2>&1
SYNC
fi)

# === end $CRON_MARKER ===
EOF
)

# Extract existing crontab, stripping any previous block for this project.
# Use fixed-string matching (no regex) to avoid issues with special characters
# in the project name.
EXISTING=$(crontab -l 2>/dev/null || true)
BLOCK_START="# === $CRON_MARKER scheduled jobs ==="
BLOCK_END="# === end $CRON_MARKER ==="
CLEANED=$(awk -v start="$BLOCK_START" -v end="$BLOCK_END" '$0==start{skip=1} $0==end{skip=0;next} !skip' <<< "$EXISTING")

# Strip legacy marker formats from previous versions
CLEANED=$(echo "$CLEANED" | sed '/^# === brave-core-bot scheduled jobs ===/,/^# === end brave-core-bot ===/d')
CLEANED=$(echo "$CLEANED" | sed '/^# === brave-bot \[.*\] scheduled jobs ===/,/^# === end brave-bot \[.*\] ===/d')
CLEANED=$(echo "$CLEANED" | sed '/^# === brave-bot (.*) scheduled jobs ===/,/^# === end brave-bot (.*) ===/d')

# Combine preserved entries with new block
NEW_CRONTAB=$(printf '%s\n%s\n' "$CLEANED" "$CRON_JOBS" | sed '/^$/N;/^\n$/d')

echo "$NEW_CRONTAB" | crontab -

echo "Cron jobs installed successfully."
echo ""
echo "Current schedule:"
echo "  00:01 - sync repo origin/$BOT_DEFAULT_BRANCH from upstream (if enabled)"
echo "  00:10 - run.sh (3 iterations)"
echo "  Every 5 min at :01,:06,:11,...,:56 - /check-signal (only if messages pending)"
echo "  03:45, 07:45, 15:45, 19:45 - /add-backlog-to-prd"
echo "  00:10, 08:00, 12:00, 16:00 - run.sh (3 iterations)"
echo "  08:00-20:00 (every 2h), 00:00, 04:00 - /review-prs"
echo "  1st of month, 04:15 - /update-best-practices"
echo "  06:00 - /learnable-pattern-search"
echo ""
crontab -l
