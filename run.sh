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
source "$SCRIPT_DIR/scripts/lib/load-config.sh"

PRD_FILE="$SCRIPT_DIR/data/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/data/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LOGS_DIR="$SCRIPT_DIR/logs"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
RUN_STATE_FILE="$SCRIPT_DIR/data/run-state.json"

# Resolve target repo path from config.json (with prd.json fallback for migration)
GIT_REPO="${BOT_TARGET_REPO_PATH:-}"
if [ -z "$GIT_REPO" ] && [ -f "$PRD_FILE" ]; then
  GIT_REPO=$(jq -r '.config.workingDirectory // .config.gitRepo // .ralphConfig.workingDirectory // .ralphConfig.gitRepo // empty' "$PRD_FILE" 2>/dev/null || echo "")
fi
if [ -n "$GIT_REPO" ] && [[ "$GIT_REPO" != /* ]]; then
  PARENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  GIT_REPO="$PARENT_ROOT/$GIT_REPO"
fi

# Function to switch back to master branch on exit
cleanup_and_return_to_master() {
  if [ -n "$GIT_REPO" ] && [ -d "$GIT_REPO/.git" ]; then
    echo ""
    echo "Switching back to $BOT_DEFAULT_BRANCH branch in $GIT_REPO..."
    cd "$GIT_REPO"
    git stash --include-untracked 2>/dev/null || true
    git checkout "$BOT_DEFAULT_BRANCH" 2>/dev/null || echo "Could not switch to $BOT_DEFAULT_BRANCH branch"
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
  echo "  mkdir -p $SCRIPT_DIR/.ignore && gh api 'orgs/$BOT_ORG/members' --paginate | jq -r '.[].login' > $ORG_MEMBERS_FILE"
  exit 1
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

  # Initialize runId if it's null (start of new run)
  RUN_ID=$(jq -r '.runId // "null"' "$RUN_STATE_FILE" 2>/dev/null || echo "null")
  if [ "$RUN_ID" = "null" ]; then
    # Initialize new run with current timestamp
    RUN_ID=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TMP_RUN_STATE=$(mktemp)
    jq --arg runId "$RUN_ID" '.runId = $runId | .storiesCheckedThisRun = [] | .lastIterationHadStateChange = true' "$RUN_STATE_FILE" > "$TMP_RUN_STATE" && mv "$TMP_RUN_STATE" "$RUN_STATE_FILE"
  fi

  # Generate log file path for this iteration (needed by select-task.py)
  RUN_ID_SAFE=$(echo "$RUN_ID" | sed 's/[^a-zA-Z0-9-]/-/g')
  ITERATION_LOG="$LOGS_DIR/iteration-${RUN_ID_SAFE}-loop-${loop_count}.log"

  # Select next task — this is the gate check; exit early if no candidates
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
  STORY_DETAILS=$(echo "$TASK_JSON" | jq -c '.storyDetails')
  PRD_CONFIG=$(echo "$TASK_JSON" | jq -c '.config')
  echo "Selected: $STORY_ID - $STORY_TITLE (status: $STORY_STATUS, tier: $TIER_NAME)"

  # Task confirmed — proceed with iteration setup
  # Store the current iteration log path in run-state.json
  TMP_RUN_STATE=$(mktemp)
  jq --arg logPath "$ITERATION_LOG" '.currentIterationLogPath = $logPath' "$RUN_STATE_FILE" > "$TMP_RUN_STATE" && mv "$TMP_RUN_STATE" "$RUN_STATE_FILE"

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

  echo "Logging to: $ITERATION_LOG"

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
  # In print mode: use stream-json output format with verbose flag to capture detailed execution logs
  # In TUI mode: omit --print to show the interactive TUI
  BOT_DIRNAME=$(basename "$SCRIPT_DIR")
  CLAUDE_PROMPT="You are working on story $STORY_ID (current status: $STORY_STATUS).
Follow ./$BOT_DIRNAME/docs/workflow-${STORY_STATUS}.md for the workflow.
Follow the general instructions in ./$BOT_DIRNAME/.claude/CLAUDE.md.

Story details:
$STORY_DETAILS

PRD config:
$PRD_CONFIG"
  if [ -n "$NIGHTLY_VERSION" ]; then
    CLAUDE_PROMPT="$CLAUDE_PROMPT

Nightly version: $NIGHTLY_VERSION (use this for milestone names like '$NIGHTLY_VERSION - Nightly', do NOT fetch the release schedule)."
  fi
  if [ -n "$EXTRA_PROMPT" ]; then
    CLAUDE_PROMPT="$CLAUDE_PROMPT

Additional context: $EXTRA_PROMPT"
  fi

  # Log the prompt to the iteration log so it can be audited later
  if [ "$USE_TUI" != true ]; then
    jq -n --arg storyId "$STORY_ID" --arg status "$STORY_STATUS" --arg tier "$TIER_NAME" --arg prompt "$CLAUDE_PROMPT" \
      '{"type":"prompt","storyId":$storyId,"status":$status,"tier":$tier,"prompt":$prompt}' >> "$ITERATION_LOG"
  fi

  if [ "$USE_TUI" = true ]; then
    # TUI mode: let Claude own the terminal directly (no piping)
    $BOT_CLAUDE_BIN --dangerously-skip-permissions --model "$BOT_CLAUDE_MODEL" --session-id "$SESSION_ID" "$CLAUDE_PROMPT" || true
  else
    $BOT_CLAUDE_BIN --dangerously-skip-permissions --print --model "$BOT_CLAUDE_MODEL" --verbose --output-format stream-json --session-id "$SESSION_ID" "$CLAUDE_PROMPT" 2>&1 | tee -a "$ITERATION_LOG" > "$TEMP_OUTPUT" || true
  fi

  echo "To continue this session: claude --resume $SESSION_ID"

  # Check for completion signal (print mode only — TUI mode skips this since user is watching)
  COMPLETION_CHECK=0
  if [ "$USE_TUI" != true ]; then
    # Extract text from stream-json, check for completion signal.
    # Use tail -1 to guarantee a single integer (jq on mixed stderr/json can produce multiline output).
    COMPLETION_CHECK=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$TEMP_OUTPUT" 2>/dev/null | grep -c "<promise>COMPLETE</promise>" 2>/dev/null | tail -1)
    COMPLETION_CHECK=$((COMPLETION_CHECK + 0))
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
