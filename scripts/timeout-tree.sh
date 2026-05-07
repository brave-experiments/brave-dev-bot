#!/bin/bash
# Like timeout, but kills the entire process tree (not just the direct child).
#
# Usage: timeout-tree.sh <seconds> <command...>
#
# Problem: GNU timeout only kills the direct child's process group. If the child
# spawns subprocesses in new process groups (e.g., Claude's Bash tool), those
# survive and become zombie orphans reparented to init.
#
# Solution: Recursively kill all descendant processes by walking the process tree.
# We avoid setsid because it creates a new session with no controlling terminal,
# which breaks Ink's raw mode check even in --print mode.

set -e

if [ $# -lt 2 ]; then
  echo "Usage: timeout-tree.sh <seconds> <command...>"
  exit 1
fi

TIMEOUT_SECS="$1"
shift

# Recursively kill a process and all its descendants (leaf-first)
kill_tree() {
  local sig="${1:-TERM}"
  local pid="$2"
  # Get children before killing the parent
  local children
  children=$(pgrep -P "$pid" 2>/dev/null) || true
  for child in $children; do
    kill_tree "$sig" "$child"
  done
  kill -"$sig" "$pid" 2>/dev/null || true
}

# Run command in background (inherits the current session/TTY)
"$@" &
CMD_PID=$!

# Background watchdog: kill the process tree after timeout
(
  sleep "$TIMEOUT_SECS"
  kill_tree TERM "$CMD_PID"
  sleep 5
  kill_tree KILL "$CMD_PID"
) &
WATCHDOG_PID=$!

# Wait for the command to finish
wait "$CMD_PID" 2>/dev/null
EXIT_CODE=$?

# Cancel the watchdog and its children (e.g. orphaned sleep subprocess)
kill_tree TERM "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true

if [ $EXIT_CODE -eq 137 ] || [ $EXIT_CODE -eq 143 ]; then
  echo "Job killed after exceeding timeout of ${TIMEOUT_SECS}s"
fi

exit $EXIT_CODE
