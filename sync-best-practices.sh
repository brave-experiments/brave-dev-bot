#!/bin/bash
# Sync best practices from brave-core-bot to src/brave/.claude/rules via symlink

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BP_SRC="$SCRIPT_DIR/docs/best-practices"
BP_DEST="$SCRIPT_DIR/../src/brave/.claude/rules/best-practices"

if [ ! -d "$BP_SRC" ]; then
  echo "No best practices found in $BP_SRC"
  exit 1
fi

# If it's already a valid symlink, nothing to do
if [ -L "$BP_DEST" ] && [ -e "$BP_DEST" ]; then
  echo "Already symlinked: $BP_DEST -> $(readlink "$BP_DEST")"
  exit 0
fi

# Clean up broken symlink or directory of old per-file symlinks
if [ -L "$BP_DEST" ]; then
  echo "Removing broken symlink: $BP_DEST"
  rm "$BP_DEST"
elif [ -d "$BP_DEST" ]; then
  echo "Removing old per-file symlinks directory: $BP_DEST"
  rm -rf "$BP_DEST"
fi

mkdir -p "$(dirname "$BP_DEST")"
ln -s "../../../../brave-core-bot/docs/best-practices" "$BP_DEST"
echo "Linked: $BP_DEST -> ../../../../brave-core-bot/docs/best-practices"
