#!/bin/bash
# Long-running AI agent loop
# Usage: ./run.sh [max_iterations] [tui] [extra_prompt_info...]

set -e

# Prevent concurrent runs — acquire an exclusive lock or exit immediately
LOCKFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.run.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Another run.sh is already running. Exiting."; exit 0; }

# Parse arguments
MAX_ITERATIONS=10

USE_TUI=false
EXTRA_PROMPT=""
PAST_TUI=false

for arg in "$@"; do
  if [ "$PAST_TUI" = true ]; then
    # Everything after 'tui' is extra prompt info
    if [ -n "$EXTRA_PROMPT" ]; then
      EXTRA_PROMPT="$EXTRA_PROMPT $arg"
    else
      EXTRA_PROMPT="$arg"
    fi
  elif [[ "$arg" =~ ^[0-9]+$ ]]; then
    MAX_ITERATIONS="$arg"
  elif [[ "$arg" == "tui" ]]; then
    USE_TUI=true
    PAST_TUI=true
  fi
done
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/data/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/data/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LOGS_DIR="$SCRIPT_DIR/logs"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
RUN_STATE_FILE="$SCRIPT_DIR/data/run-state.json"

# Function to switch back to master branch on exit
cleanup_and_return_to_master() {
  # Extract git repo directory from prd.json
  if [ -f "$PRD_FILE" ]; then
    GIT_REPO=$(jq -r '.config.workingDirectory // .config.gitRepo // .ralphConfig.workingDirectory // .ralphConfig.gitRepo // empty' "$PRD_FILE" 2>/dev/null || echo "")

    if [ -n "$GIT_REPO" ]; then
      # Handle relative paths - make them absolute from brave-browser root
      if [[ "$GIT_REPO" != /* ]]; then
        # Assume it's relative to brave-browser root (parent of brave-core-bot)
        BRAVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
        GIT_REPO="$BRAVE_ROOT/$GIT_REPO"
      fi

      if [ -d "$GIT_REPO/.git" ]; then
        echo ""
        echo "Switching back to master branch in $GIT_REPO..."
        cd "$GIT_REPO" && git checkout master 2>/dev/null || git checkout main 2>/dev/null || echo "Could not switch to master/main branch"
      fi
    fi
  fi
}

# Register cleanup function to run on exit
trap cleanup_and_return_to_master EXIT

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$LAST_BRANCH"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

# Verify org members file exists (required for prompt injection protection)
ORG_MEMBERS_FILE="$SCRIPT_DIR/.ignore/org-members.txt"
if [ ! -f "$ORG_MEMBERS_FILE" ]; then
  echo "Error: Org members file not found at $ORG_MEMBERS_FILE"
  echo "This file is required for prompt injection protection."
  echo "Run 'make setup' or create it manually:"
  echo "  mkdir -p $SCRIPT_DIR/.ignore && gh api 'orgs/brave/members' --paginate | jq -r '.[].login' > $ORG_MEMBERS_FILE"
  exit 1
fi

# Check if there are active stories in the PRD before starting
echo "Checking PRD for active work items..."
if ! python3 "$SCRIPT_DIR/scripts/check-prd-has-work.py"; then
  echo ""
  echo "No active work items found. Exiting without starting Claude."
  exit 0
fi

echo "Starting Claude Code agent - Max iterations: $MAX_ITERATIONS"
echo "Logs will be saved to: $LOGS_DIR"

# Fetch nightly version once per run (avoids redundant WebFetch in each iteration)
NIGHTLY_VERSION=$(python3 "$SCRIPT_DIR/scripts/get-nightly-version.py" 2>/dev/null || echo "")
if [ -n "$NIGHTLY_VERSION" ]; then
  echo "Nightly version: $NIGHTLY_VERSION"
else
  echo "Warning: Could not fetch nightly version (agent will fetch if needed)"
fi

# Reset run state at the start of each run
echo "Resetting run state for fresh start..."
"$SCRIPT_DIR/scripts/reset-run-state.sh"

# Track both loop count (for max iterations) and work iterations (actual state changes)
loop_count=0
work_iteration=0

while [ $loop_count -lt $MAX_ITERATIONS ]; do
  ((++loop_count))

  # Sync brave-core-bot repo to latest upstream master before each iteration
  echo "Syncing brave-core-bot to upstream/master..."
  cd "$SCRIPT_DIR"
  git fetch upstream 2>/dev/null || git fetch origin
  git checkout master 2>/dev/null
  git reset --hard upstream/master 2>/dev/null || git reset --hard origin/master
  cd - > /dev/null

  # Check if PRD still has active stories before each iteration
  if ! python3 "$SCRIPT_DIR/scripts/check-prd-has-work.py" > /dev/null 2>&1; then
    echo ""
    echo "No active work items remaining in PRD. Stopping."
    exit 0
  fi

  # Check if last iteration had state change (default to true for first iteration)
  HAD_STATE_CHANGE=$(jq -r '.lastIterationHadStateChange // true' "$RUN_STATE_FILE" 2>/dev/null || echo "true")

  # Only increment work iteration counter if there was actual state change
  if [ "$HAD_STATE_CHANGE" = "true" ]; then
    ((++work_iteration))
    echo ""
    echo "==============================================================="
    echo "  Work Iteration $work_iteration (loop $loop_count of $MAX_ITERATIONS)"
    echo "==============================================================="
  else
    echo ""
    echo "==============================================================="
    echo "  Checking next task (work iteration $work_iteration, loop $loop_count of $MAX_ITERATIONS)"
    echo "  Previous check had no state change - continuing without incrementing work iteration"
    echo "==============================================================="
  fi

  # Initialize runId if it's null (start of new run)
  RUN_ID=$(jq -r '.runId // "null"' "$RUN_STATE_FILE" 2>/dev/null || echo "null")
  if [ "$RUN_ID" = "null" ]; then
    # Initialize new run with current timestamp
    RUN_ID=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TMP_RUN_STATE=$(mktemp)
    jq --arg runId "$RUN_ID" '.runId = $runId | .storiesCheckedThisRun = [] | .lastIterationHadStateChange = true' "$RUN_STATE_FILE" > "$TMP_RUN_STATE" && mv "$TMP_RUN_STATE" "$RUN_STATE_FILE"
  fi

  # Generate log file path for this iteration
  # Create a filename-safe version of runId (replace colons and other special chars)
  RUN_ID_SAFE=$(echo "$RUN_ID" | sed 's/[^a-zA-Z0-9-]/-/g')
  ITERATION_LOG="$LOGS_DIR/iteration-${RUN_ID_SAFE}-loop-${loop_count}.log"

  # Store the current iteration log path in run-state.json
  TMP_RUN_STATE=$(mktemp)
  jq --arg logPath "$ITERATION_LOG" '.currentIterationLogPath = $logPath' "$RUN_STATE_FILE" > "$TMP_RUN_STATE" && mv "$TMP_RUN_STATE" "$RUN_STATE_FILE"

  echo "Logging to: $ITERATION_LOG"

  # Select next task deterministically
  TASK_JSON=""
  if [ -n "$EXTRA_PROMPT" ]; then
    TASK_JSON=$(python3 "$SCRIPT_DIR/scripts/select-task.py" \
      --prd "$PRD_FILE" \
      --run-state "$RUN_STATE_FILE" \
      --iteration-log "$ITERATION_LOG" \
      --extra-prompt "$EXTRA_PROMPT") || true
  else
    TASK_JSON=$(python3 "$SCRIPT_DIR/scripts/select-task.py" \
      --prd "$PRD_FILE" \
      --run-state "$RUN_STATE_FILE" \
      --iteration-log "$ITERATION_LOG") || true
  fi

  # Check if task was selected
  TASK_SELECTED=$(echo "$TASK_JSON" | jq -r '.selected // false' 2>/dev/null || echo "false")
  if [ "$TASK_SELECTED" != "true" ]; then
    REASON=$(echo "$TASK_JSON" | jq -r '.reason // "unknown"' 2>/dev/null || echo "unknown")
    echo "No more tasks to process: $REASON"
    break
  fi

  STORY_ID=$(echo "$TASK_JSON" | jq -r '.storyId')
  STORY_STATUS=$(echo "$TASK_JSON" | jq -r '.status')
  TIER_NAME=$(echo "$TASK_JSON" | jq -r '.tierName')
  STORY_TITLE=$(echo "$TASK_JSON" | jq -r '.title')
  echo "Selected: $STORY_ID - $STORY_TITLE (status: $STORY_STATUS, tier: $TIER_NAME)"

  # Run Claude Code with the agent prompt
  # Use a temp file to capture output while allowing real-time streaming
  TEMP_OUTPUT=$(mktemp)

  # Change to the parent directory (brave-browser) so relative paths in .claude/CLAUDE.md work
  BRAVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  cd "$BRAVE_ROOT"

  # Pre-generate session ID so we can print the resume command before Claude starts
  SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  echo ""
  echo "To monitor this session (read-only): claude --resume $SESSION_ID"
  echo ""

  # Claude Code: use --dangerously-skip-permissions for autonomous operation
  # Always use opus model (which has extended thinking built-in)
  # In print mode: use stream-json output format with verbose flag to capture detailed execution logs
  # In TUI mode: omit --print to show the interactive TUI
  CLAUDE_PROMPT="You are working on story $STORY_ID (current status: $STORY_STATUS).
Read ./brave-core-bot/data/prd.json for full story details.
Read ./brave-core-bot/data/progress.txt (check Codebase Patterns section).
Follow ./brave-core-bot/docs/workflow-${STORY_STATUS}.md for the workflow.
Follow the general instructions in ./brave-core-bot/.claude/CLAUDE.md."
  if [ -n "$NIGHTLY_VERSION" ]; then
    CLAUDE_PROMPT="$CLAUDE_PROMPT

Nightly version: $NIGHTLY_VERSION (use this for milestone names like '$NIGHTLY_VERSION - Nightly', do NOT fetch the release schedule)."
  fi
  if [ -n "$EXTRA_PROMPT" ]; then
    CLAUDE_PROMPT="$CLAUDE_PROMPT

Additional context: $EXTRA_PROMPT"
  fi

  if [ "$USE_TUI" = true ]; then
    # TUI mode: let Claude own the terminal directly (no piping)
    claude --dangerously-skip-permissions --model opus --session-id "$SESSION_ID" "$CLAUDE_PROMPT" || true
  else
    claude --dangerously-skip-permissions --print --model opus --verbose --output-format stream-json --session-id "$SESSION_ID" "$CLAUDE_PROMPT" 2>&1 | tee -a "$ITERATION_LOG" > "$TEMP_OUTPUT" || true
  fi

  echo "To continue this session: claude --resume $SESSION_ID"

  # Check for completion signal (print mode only — TUI mode skips this since user is watching)
  COMPLETION_CHECK=0
  if [ "$USE_TUI" != true ]; then
    COMPLETION_CHECK=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$TEMP_OUTPUT" 2>/dev/null | grep -c "<promise>COMPLETE</promise>" || true)
  fi
  if [ "$COMPLETION_CHECK" -gt 0 ]; then
    echo ""
    echo "Agent completed all tasks!"
    echo "Completed at work iteration $work_iteration (loop $loop_count of $MAX_ITERATIONS)"
    rm -f "$TEMP_OUTPUT"
    exit 0
  fi

  rm -f "$TEMP_OUTPUT"

  echo "Loop $loop_count complete. Starting fresh context..."
  sleep 2
done

echo ""
echo "Agent reached max loop iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Work iterations completed: $work_iteration"
echo "Check $PROGRESS_FILE for status."
exit 1
