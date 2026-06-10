#!/bin/bash
# Manage a throwaway, remote-debuggable Brave instance for test-plan verification.
#
# This is an INTERNAL helper invoked by run.sh — not meant to be run by hand in
# normal operation. run.sh calls `start` before a browser-verifiable story's
# Claude session (so chrome-devtools-mcp can attach) and `stop` after.
#
# chrome-devtools-mcp is configured (in ~/.claude.json) with
#   --browserUrl http://127.0.0.1:9223
# and attaches to an ALREADY-RUNNING browser at session start. So the browser
# must be up and serving the /json discovery endpoints BEFORE the Claude
# session starts — that is what `start` guarantees (it blocks until
# /json/version responds).
#
# Port 9223 (NOT 9222) is intentional: 9222 is the default people use for their
# daily Brave/Chrome. A dedicated port keeps this throwaway dev Brave from
# colliding with whatever browser you already have open.
#
# IMPORTANT: the browser MUST be launched WITH --remote-debugging-port (done
# below). The chrome://inspect "Allow remote debugging" toggle ALONE is not
# enough — it exposes a WebSocket but the HTTP /json discovery endpoints return
# 404, and chrome-devtools-mcp needs /json/version to find the browser.
#
# Usage:
#   ./scripts/launch-brave-debug.sh start [start_url]   # launch (bg), wait until ready
#   ./scripts/launch-brave-debug.sh stop                # kill the instance we started
#   ./scripts/launch-brave-debug.sh status              # 0 if reachable, 1 otherwise
#
# Exit codes for `start`: 0 = ready (newly launched or already running),
#                         1 = could not start (binary missing, port held by a
#                             non-debuggable process, or never became ready).
#
# Notes:
# - Uses a throwaway --user-data-dir so it never touches your real Brave profile.
# - --autoConnect cannot be used because it only finds official Google Chrome.

set -e

DEBUG_PORT=9223
DEBUG_HOST=127.0.0.1
PROFILE_DIR="${TMPDIR:-/tmp}/brave-debug-profile"
PIDFILE="$PROFILE_DIR/debug-brave.pid"
READY_URL="http://$DEBUG_HOST:$DEBUG_PORT/json/version"
READY_TIMEOUT=30  # seconds to wait for /json/version after launch

# Load bot config so we can resolve the Brave binary per-machine (no hardcoded path).
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SELF_DIR/lib/load-config.sh" 2>/dev/null || true

# Resolve the built Brave binary, highest precedence first:
#   1. BRAVE_BIN env var
#   2. config.json  ->  browserVerify.braveBinary  (exported as BOT_BRAVE_BIN)
#   3. auto-detect under the target repo's build output (out/<config>/...)
# Echoes the resolved path on stdout; returns non-zero if none found.
resolve_brave_bin() {
  # 1. explicit env override
  if [ -n "${BRAVE_BIN:-}" ]; then
    printf '%s\n' "$BRAVE_BIN"
    return 0
  fi
  # 2. configured path
  if [ -n "${BOT_BRAVE_BIN:-}" ]; then
    printf '%s\n' "$BOT_BRAVE_BIN"
    return 0
  fi
  # 3. auto-detect from the target repo's build output
  local repo="${BOT_TARGET_REPO_PATH:-}"
  [ -n "$repo" ] || return 1
  case "$repo" in
    /*) ;;
    *) repo="$(cd "${BOT_DIR:-$SELF_DIR/..}/.." 2>/dev/null && pwd)/$repo" ;;
  esac
  # brave-core sits at <chromium_src>/src/brave; the build output is at <...>/src/out.
  local out_root=""
  if [ -d "$repo/out" ]; then
    out_root="$repo/out"
  elif [ -d "$(dirname "$repo")/out" ]; then
    out_root="$(dirname "$repo")/out"
  fi
  [ -n "$out_root" ] || return 1
  local found
  # macOS: the main .app bundle for any channel (Development/Beta/Nightly/Brave Browser).
  # The binary sits 5 levels under out/ (<config>/X.app/Contents/MacOS/<name>), so search
  # to depth 6. Exclude the "... Helper" bundles (Renderer/GPU/Alerts) — we want the main app.
  found=$(find "$out_root" -maxdepth 6 -type f -path '*.app/Contents/MacOS/*Browser*' 2>/dev/null \
            | grep -v 'Helper' | head -1)
  # Linux: a bare `brave` executable directly under out/<config>/.
  [ -n "$found" ] || found=$(find "$out_root" -maxdepth 2 -type f -name 'brave' -perm -u+x 2>/dev/null | head -1)
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}

# True if the debug endpoint is reachable (browser up AND serving /json).
is_ready() {
  curl -fsS --max-time 2 "$READY_URL" >/dev/null 2>&1
}

cmd_status() {
  if is_ready; then
    echo "Debug Brave is reachable at $READY_URL"
    return 0
  fi
  echo "Debug Brave is NOT reachable at $READY_URL"
  return 1
}

cmd_start() {
  local start_url="${1:-about:blank}"

  # Idempotent: if something is already serving /json on the port, reuse it.
  if is_ready; then
    echo "Debug Brave already reachable at $READY_URL — reusing it."
    return 0
  fi

  # Port held but NOT serving /json (e.g. a real Brave with only the toggle on,
  # or a stale process). We can't drive that reliably — fail loudly.
  if lsof -nP -iTCP:"$DEBUG_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Error: port $DEBUG_PORT is in use but $READY_URL is not responding." >&2
    echo "Something is holding the port without serving the debug endpoints." >&2
    echo "Free it first: lsof -nP -iTCP:$DEBUG_PORT -sTCP:LISTEN" >&2
    return 1
  fi

  local brave_bin
  brave_bin="$(resolve_brave_bin || true)"
  if [ -z "$brave_bin" ] || [ ! -x "$brave_bin" ]; then
    echo "Error: could not find a built Brave binary to launch." >&2
    [ -n "$brave_bin" ] && echo "  Resolved to a non-executable path: $brave_bin" >&2
    echo "Set it one of these ways (highest precedence first):" >&2
    echo "  1. export BRAVE_BIN=\"/path/to/Brave Browser <Channel>.app/Contents/MacOS/Brave Browser <Channel>\"" >&2
    echo "  2. config.json: \"browserVerify\": { \"braveBinary\": \"/path/to/...\" }" >&2
    echo "  3. build Brave so it appears under <targetRepoPath>/../out/<config>/ (auto-detected)" >&2
    return 1
  fi

  mkdir -p "$PROFILE_DIR"

  echo "Launching debug Brave on port $DEBUG_PORT (profile: $PROFILE_DIR, throwaway)"
  echo "  binary: $brave_bin"
  "$brave_bin" \
    --remote-debugging-port="$DEBUG_PORT" \
    --user-data-dir="$PROFILE_DIR" \
    --no-first-run \
    --no-default-browser-check \
    "$start_url" >/dev/null 2>&1 &
  local pid=$!
  echo "$pid" > "$PIDFILE"

  # Block until the discovery endpoint responds (that's what MCP needs), or time out.
  local waited=0
  while [ "$waited" -lt "$READY_TIMEOUT" ]; do
    if is_ready; then
      echo "Debug Brave ready at $READY_URL (pid $pid)"
      return 0
    fi
    # Bail early if the process died (e.g. crashed on launch).
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "Error: debug Brave (pid $pid) exited before becoming ready." >&2
      rm -f "$PIDFILE"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  echo "Error: debug Brave did not serve $READY_URL within ${READY_TIMEOUT}s." >&2
  kill "$pid" 2>/dev/null || true
  rm -f "$PIDFILE"
  return 1
}

cmd_stop() {
  if [ -f "$PIDFILE" ]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "Stopping debug Brave (pid $pid)"
      kill "$pid" 2>/dev/null || true
      # Give it a moment, then force if still alive.
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
  else
    echo "No pidfile at $PIDFILE — nothing started by this script to stop."
  fi
  # Remove the throwaway profile so each run starts clean.
  rm -rf "$PROFILE_DIR" 2>/dev/null || true
}

case "${1:-start}" in
  start)  shift || true; cmd_start "$@" ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  *)
    echo "Usage: $0 {start [url] | stop | status}" >&2
    exit 2
    ;;
esac
