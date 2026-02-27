#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Updating brave-core-tools submodule..."
cd brave-core-tools
git fetch origin
git checkout origin/main
cd ..

git add brave-core-tools

if git diff --cached --quiet; then
  echo "No changes. Submodule already up to date."
else
  git commit -m "Update brave-core-tools submodule"
  git push
  echo "Done. Submodule updated, committed, and pushed."
fi
