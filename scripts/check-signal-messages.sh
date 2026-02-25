#!/bin/bash
# Pre-check script for Signal message processing cron job.
# Receives pending Signal messages, filters for the configured recipient,
# deduplicates against a cache, and writes pending messages to a file.
#
# Exit codes:
#   0 - New messages found, written to .ignore/signal-pending-messages.json
#   1 - No messages to process (not configured, no messages, or all cached)
#
# Called by cron BEFORE invoking Claude, so Claude only runs when needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_FILE="$BOT_DIR/.ignore/signal-messages-cache.json"
PENDING_FILE="$BOT_DIR/.ignore/signal-pending-messages.json"

# --- Pre-checks (exit silently if not configured) ---

if [[ -z "${SIGNAL_SENDER:-}" ]] || [[ -z "${SIGNAL_RECIPIENT:-}" ]]; then
  exit 1
fi

if ! command -v signal-cli &>/dev/null; then
  exit 1
fi

# --- Receive messages ---

RAW_MESSAGES=$(signal-cli -u "$SIGNAL_SENDER" receive --json 2>/dev/null || true)

if [[ -z "$RAW_MESSAGES" ]]; then
  exit 1
fi

# --- Filter, deduplicate, and write pending messages ---

python3 -c "
import json
import sys
import os

signal_recipient = os.environ.get('SIGNAL_RECIPIENT', '')
cache_file = '$CACHE_FILE'
pending_file = '$PENDING_FILE'

# Load cache (array of processed timestamps)
cached_timestamps = set()
if os.path.exists(cache_file):
    try:
        with open(cache_file) as f:
            cached_timestamps = set(json.load(f))
    except (json.JSONDecodeError, IOError):
        cached_timestamps = set()

# Parse raw messages (one JSON object per line)
raw_lines = sys.stdin.read().strip().split('\n')
new_messages = []

for line in raw_lines:
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except json.JSONDecodeError:
        continue

    envelope = msg.get('envelope', {})
    source = envelope.get('sourceNumber') or envelope.get('source', '')
    data_message = envelope.get('dataMessage')

    # Only messages from the configured recipient
    if source != signal_recipient:
        continue

    # Only data messages with text
    if not data_message or not data_message.get('message'):
        continue

    timestamp = data_message.get('timestamp', 0)

    # Skip already-processed messages
    if timestamp in cached_timestamps:
        continue

    new_messages.append({
        'timestamp': timestamp,
        'source': source,
        'message': data_message['message']
    })

if not new_messages:
    sys.exit(1)

# Write pending messages for the skill to process
with open(pending_file, 'w') as f:
    json.dump(new_messages, f, indent=2)

print(f'Found {len(new_messages)} new Signal message(s) to process')
sys.exit(0)
" <<< "$RAW_MESSAGES"
