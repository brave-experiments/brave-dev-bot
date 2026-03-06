#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/load-config.sh"

cd "$BOT_DIR"

echo "Updating $BOT_BP_SUBMODULE submodule..."
cd "$BOT_BP_SUBMODULE"
git fetch origin
BOT_REPO_BRANCH=$(bot_config '.project.botRepoBranch')
BOT_REPO_BRANCH="${BOT_REPO_BRANCH:-master}"
git checkout "origin/$BOT_REPO_BRANCH"
cd ..

git add brave-core-tools

if git diff --cached --quiet; then
  echo "No changes. Submodule already up to date."
else
  git commit -m "Update $BOT_BP_SUBMODULE submodule"
  git push
  echo "Done. Submodule updated, committed, and pushed."
fi
