#!/bin/bash
# Sync brave-core master to upstream/master and push to origin.
# Run before review-prs so best practices are read from the latest upstream state.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/load-config.sh"

BRAVE_CORE_DIR="$(cd "$SCRIPT_DIR/../$BOT_TARGET_REPO_PATH" && pwd)"

echo "Syncing brave-core at $BRAVE_CORE_DIR"

cd "$BRAVE_CORE_DIR"
git checkout master
git fetch upstream
git reset --hard upstream/master
git push origin master

echo "brave-core master synced to upstream/master"
