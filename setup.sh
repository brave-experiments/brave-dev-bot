#!/bin/bash
# Setup script for brave-core-bot
# This script installs the pre-commit hook and helps configure git

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SOURCE="$SCRIPT_DIR/hooks/pre-commit"

echo "==================================="
echo "  Brave Core Bot Setup"
echo "==================================="
echo ""

# Validate directory structure
EXPECTED_REPO_PATH="$(dirname "$SCRIPT_DIR")/src/brave"
if [ ! -d "$EXPECTED_REPO_PATH" ]; then
  echo "⚠️  Warning: Expected directory structure not found"
  echo ""
  echo "This script expects to be run from:"
  echo "  brave-browser/brave-core-bot/"
  echo ""
  echo "Where brave-browser contains:"
  echo "  - src/brave/ (target git repository)"
  echo "  - brave-core-bot/ (this directory)"
  echo ""
  echo "Expected path not found: $EXPECTED_REPO_PATH"
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 1
  fi
  echo ""
fi

# Check if prd.json exists
if [ ! -f "$SCRIPT_DIR/prd.json" ]; then
  echo "❌ Error: prd.json not found in $SCRIPT_DIR"
  echo "   Please create a prd.json file before running setup."
  exit 1
fi

# Extract git repo from prd.json
GIT_REPO=$(jq -r '.config.workingDirectory // .config.gitRepo // .ralphConfig.workingDirectory // .ralphConfig.gitRepo // empty' "$SCRIPT_DIR/prd.json" 2>/dev/null || echo "")

if [ -z "$GIT_REPO" ]; then
  echo "❌ Error: Could not find git repository in prd.json"
  echo "   Please set config.workingDirectory or config.gitRepo"
  exit 1
fi

# Handle relative paths
if [[ "$GIT_REPO" != /* ]]; then
  BRAVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  GIT_REPO="$BRAVE_ROOT/$GIT_REPO"
fi

echo "Target git repository: $GIT_REPO"
echo ""

# Verify git repo exists
if [ ! -d "$GIT_REPO/.git" ]; then
  echo "❌ Error: $GIT_REPO is not a git repository"
  exit 1
fi

# Install pre-commit hook for target repo (src/brave)
HOOK_DEST="$GIT_REPO/.git/hooks/pre-commit"

echo "Installing pre-commit hook to target repo..."
cp "$HOOK_SOURCE" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo "✓ Pre-commit hook installed to $HOOK_DEST"
echo ""

# Install pre-commit hook for brave-core-bot repo itself
BOT_HOOK_SOURCE="$SCRIPT_DIR/hooks/pre-commit-bot-repo"
BOT_HOOK_DEST="$SCRIPT_DIR/.git/hooks/pre-commit"

echo "Installing pre-commit hook to brave-core-bot repo..."
cp "$BOT_HOOK_SOURCE" "$BOT_HOOK_DEST"
chmod +x "$BOT_HOOK_DEST"
echo "✓ Pre-commit hook installed to $BOT_HOOK_DEST"
echo "  (Prevents committing prd.json, progress.txt, run-state.json)"
echo ""

# Check git config
echo "Checking git configuration..."
cd "$GIT_REPO"

GIT_USER=$(git config user.name || echo "")
GIT_EMAIL=$(git config user.email || echo "")

if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
  echo ""
  echo "⚠️  Git user configuration not found!"
  echo ""
  echo "Please configure git for this repository:"
  echo ""
  echo "  cd $GIT_REPO"
  echo "  git config user.name \"Your Bot Name\""
  echo "  git config user.email \"your-bot@example.com\""
  echo ""
  echo "For the netzenbot account (with dependency restrictions):"
  echo "  git config user.name \"netzenbot\""
  echo "  git config user.email \"netzenbot@brave.com\""
  echo ""
else
  echo "✓ Git user: $GIT_USER"
  echo "✓ Git email: $GIT_EMAIL"
  echo ""
fi

# Create org members cache for prompt injection protection
ORG_MEMBERS_DIR="$SCRIPT_DIR/.ignore"
ORG_MEMBERS_FILE="$ORG_MEMBERS_DIR/org-members.txt"
mkdir -p "$ORG_MEMBERS_DIR"

echo "Fetching Brave org members list..."
if gh api "orgs/brave/members" --paginate 2>/dev/null | jq -r '.[].login' > "$ORG_MEMBERS_FILE"; then
  echo "✓ Org members cached: $(wc -l < "$ORG_MEMBERS_FILE") members → $ORG_MEMBERS_FILE"
else
  echo "⚠️  Warning: Could not fetch org members. You may need to create it manually:"
  echo "  gh api 'orgs/brave/members' --paginate | jq -r '.[].login' > $ORG_MEMBERS_FILE"
fi
echo ""

echo "==================================="
echo "  Setup Complete!"
echo "==================================="
echo ""
echo "Next steps:"
echo "1. Configure git user/email if not already set (see above)"
echo "2. Review prd.json and update configuration as needed"
echo "3. Run the bot: cd $SCRIPT_DIR && ./run.sh"
echo ""
