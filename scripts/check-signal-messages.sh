#!/bin/bash
# Pre-check script for Signal message processing cron job.
# Receives pending Signal messages, filters for the configured recipient,
# deduplicates against a cache, and writes pending messages to a file.
# Supports text messages and audio voice messages (transcribed via faster-whisper).
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
TRANSCRIBE_SCRIPT="$SCRIPT_DIR/transcribe-audio.py"

# --- Pre-checks (exit silently if not configured) ---

if [[ -z "${SIGNAL_SENDER:-}" ]] || [[ -z "${SIGNAL_RECIPIENT:-}" ]]; then
  exit 1
fi

if ! command -v signal-cli &>/dev/null; then
  exit 1
fi

# --- Receive messages ---

RAW_MESSAGES=$(signal-cli --output=json -u "$SIGNAL_SENDER" receive 2>/dev/null || true)

if [[ -z "$RAW_MESSAGES" ]]; then
  exit 1
fi

# --- Filter, deduplicate, and write pending messages ---

python3 -c "
import json
import sys
import os
import subprocess

signal_recipient = os.environ.get('SIGNAL_RECIPIENT', '')
cache_file = '$CACHE_FILE'
pending_file = '$PENDING_FILE'
transcribe_script = '$TRANSCRIBE_SCRIPT'
signal_attachments_dir = os.path.expanduser(
    '~/.var/app/org.asamk.SignalCli/data/signal-cli/attachments'
)

AUDIO_CONTENT_TYPES = {'audio/aac', 'audio/mp4', 'audio/mpeg', 'audio/ogg',
                       'audio/wav', 'audio/x-m4a', 'audio/mp4a-latm'}

def transcribe_audio(attachment_id):
    \"\"\"Transcribe an audio attachment to text. Returns text or None.\"\"\"
    if not os.path.isdir(signal_attachments_dir):
        return None
    for fname in os.listdir(signal_attachments_dir):
        if fname.startswith(attachment_id):
            audio_path = os.path.join(signal_attachments_dir, fname)
            break
    else:
        return None
    try:
        uv_path = os.path.expanduser('~/.local/bin/uv')
        if not os.path.exists(uv_path):
            uv_path = 'uv'
        result = subprocess.run(
            [uv_path, 'run', '--with', 'faster-whisper', 'python3',
             transcribe_script, audio_path],
            capture_output=True, text=True, timeout=120
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None

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

    if not data_message:
        continue

    timestamp = data_message.get('timestamp', 0)

    # Skip already-processed messages
    if timestamp in cached_timestamps:
        continue

    message_text = data_message.get('message', '')

    # Check for audio attachments if no text message
    if not message_text:
        attachments = data_message.get('attachments', [])
        for att in attachments:
            content_type = att.get('contentType', '')
            att_id = att.get('id', '')
            if content_type in AUDIO_CONTENT_TYPES and att_id:
                transcribed = transcribe_audio(att_id)
                if transcribed:
                    message_text = '[voice message] ' + transcribed
                    break
        if not message_text:
            continue

    new_messages.append({
        'timestamp': timestamp,
        'source': source,
        'message': message_text
    })

if not new_messages:
    sys.exit(1)

# Write pending messages for the skill to process
with open(pending_file, 'w') as f:
    json.dump(new_messages, f, indent=2)

print(f'Found {len(new_messages)} new Signal message(s) to process')
sys.exit(0)
" <<< "$RAW_MESSAGES"
