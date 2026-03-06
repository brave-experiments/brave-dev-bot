#!/bin/bash
# Shared config loader for brave-dev-bot shell scripts.
#
# Usage (from any script):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/load-config.sh"
#
# Exports:
#   BOT_PROJECT_NAME, BOT_ORG, BOT_PR_REPO, BOT_ISSUE_REPO,
#   BOT_DEFAULT_BRANCH, BOT_USERNAME, BOT_EMAIL,
#   BOT_CLAUDE_MODEL, BOT_CLAUDE_BIN, BOT_BP_SUBMODULE
#
# Also provides:
#   bot_config '.some.jq.path'  — raw jq query against the config file

BOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BOT_CONFIG_FILE="$BOT_DIR/config.json"
if [ ! -f "$BOT_CONFIG_FILE" ]; then
  BOT_CONFIG_FILE="$BOT_DIR/config.example.json"
fi

if [ ! -f "$BOT_CONFIG_FILE" ]; then
  echo "Error: No config.json or config.example.json found in $BOT_DIR" >&2
  return 1 2>/dev/null || exit 1
fi

bot_config() {
  jq -r "$1 // empty" "$BOT_CONFIG_FILE"
}

BOT_PROJECT_NAME=$(bot_config '.project.name')
BOT_ORG=$(bot_config '.project.org')
BOT_PR_REPO=$(bot_config '.project.prRepository')
BOT_ISSUE_REPO=$(bot_config '.project.issueRepository')
BOT_DEFAULT_BRANCH=$(bot_config '.project.defaultBranch')

BOT_USERNAME=$(bot_config '.bot.username')
BOT_EMAIL=$(bot_config '.bot.email')
BOT_CLAUDE_MODEL=$(bot_config '.bot.claudeModel')
BOT_CLAUDE_BIN=$(bot_config '.bot.claudeBin')

BOT_BP_SUBMODULE=$(bot_config '.bestPractices.submodule')

# Fall back to 'claude' if claudeBin is not set
if [ -z "$BOT_CLAUDE_BIN" ]; then
  BOT_CLAUDE_BIN="$(which claude 2>/dev/null || echo "claude")"
fi

export BOT_DIR BOT_CONFIG_FILE
export BOT_PROJECT_NAME BOT_ORG BOT_PR_REPO BOT_ISSUE_REPO BOT_DEFAULT_BRANCH
export BOT_USERNAME BOT_EMAIL BOT_CLAUDE_MODEL BOT_CLAUDE_BIN
export BOT_BP_SUBMODULE
