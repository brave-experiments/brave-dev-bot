#!/bin/bash
# Like timeout, but kills the entire process tree (not just the direct child).
#
# Usage: timeout-tree.sh <seconds> <command...>
#
# Problem: GNU timeout only kills the direct child's process group. If the child
# spawns subprocesses in new process groups (e.g., Claude's Bash tool), those
# survive and become zombie orphans reparented to init.
#
# Solution: Run the command in a new session (setsid) and kill the entire session
# on timeout.

set -e

if [ $# -lt 2 ]; then
  echo "Usage: timeout-tree.sh <seconds> <command...>"
  exit 1
fi

TIMEOUT_SECS="$1"
shift

# Run command in a new session so all descendants share one SID
setsid "$@" &
CMD_PID=$!

# Background watchdog: kill the entire process group after timeout
(
  sleep "$TIMEOUT_SECS"
  # Kill the process group (negative PID = process group)
  kill -- -"$CMD_PID" 2>/dev/null
  sleep 5
  # Force kill if still alive
  kill -9 -- -"$CMD_PID" 2>/dev/null
) &
WATCHDOG_PID=$!

# Wait for the command to finish
wait "$CMD_PID" 2>/dev/null
EXIT_CODE=$?

# Cancel the watchdog
kill "$WATCHDOG_PID" 2>/dev/null
wait "$WATCHDOG_PID" 2>/dev/null || true

if [ $EXIT_CODE -eq 137 ] || [ $EXIT_CODE -eq 143 ]; then
  echo "Job killed after exceeding timeout of ${TIMEOUT_SECS}s"
fi

exit $EXIT_CODE
