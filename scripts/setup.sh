#!/bin/bash
# Setup script for brave-core-bot
# This script installs the pre-commit hook and helps configure git

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRAVE_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
HOOK_SOURCE="$PROJECT_ROOT/hooks/pre-commit"

echo "==================================="
echo "  Brave Core Bot Setup"
echo "==================================="
echo ""

# Initialize brave-core-tools submodule
echo "Initializing brave-core-tools submodule..."
cd "$PROJECT_ROOT"
git submodule update --init --recursive
echo "✓ Submodule initialized at: $PROJECT_ROOT/brave-core-tools"
echo ""

# Validate directory structure
EXPECTED_REPO_PATH="$BRAVE_ROOT/src/brave"
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
if [ ! -f "$PROJECT_ROOT/data/prd.json" ]; then
  echo "❌ Error: data/prd.json not found in $PROJECT_ROOT"
  echo "   Please create a data/prd.json file before running setup."
  exit 1
fi

# Extract git repo from data/prd.json
GIT_REPO=$(jq -r '.config.workingDirectory // .config.gitRepo // .ralphConfig.workingDirectory // .ralphConfig.gitRepo // empty' "$PROJECT_ROOT/data/prd.json" 2>/dev/null || echo "")

if [ -z "$GIT_REPO" ]; then
  echo "❌ Error: Could not find git repository in prd.json"
  echo "   Please set config.workingDirectory or config.gitRepo"
  exit 1
fi

# Handle relative paths
if [[ "$GIT_REPO" != /* ]]; then
  GIT_REPO="$BRAVE_ROOT/$GIT_REPO"
fi

echo "Target git repository: $GIT_REPO"
echo ""

# Verify git repo exists
if [ ! -d "$GIT_REPO/.git" ]; then
  echo "❌ Error: $GIT_REPO is not a git repository"
  exit 1
fi

# Check git config (needed before hook installation)
echo "Checking git configuration..."
cd "$GIT_REPO"

GIT_USER=$(git config user.name || echo "")
GIT_EMAIL=$(git config user.email || echo "")

if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
  echo ""
  echo "❌ Error: Git user configuration not found!"
  echo ""
  echo "Please configure git for this repository before running setup:"
  echo ""
  echo "  cd $GIT_REPO"
  echo "  git config user.name \"your-bot-name\""
  echo "  git config user.email \"your-bot@example.com\""
  echo ""
  exit 1
fi

echo "✓ Git user: $GIT_USER"
echo "✓ Git email: $GIT_EMAIL"
echo ""

# Install pre-commit hook for target repo (src/brave)
# Replaces __BOT_USERNAME__ placeholder with the configured git user
HOOK_DEST="$GIT_REPO/.git/hooks/pre-commit"

echo "Installing pre-commit hook to target repo..."
sed "s/__BOT_USERNAME__/$GIT_USER/g" "$HOOK_SOURCE" > "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo "✓ Pre-commit hook installed to $HOOK_DEST (bot user: $GIT_USER)"
echo ""

# Install pre-commit hook for brave-core-bot repo itself
BOT_HOOK_SOURCE="$PROJECT_ROOT/hooks/pre-commit-bot-repo"
BOT_HOOK_DEST="$PROJECT_ROOT/.git/hooks/pre-commit"

echo "Installing pre-commit hook to brave-core-bot repo..."
cp "$BOT_HOOK_SOURCE" "$BOT_HOOK_DEST"
chmod +x "$BOT_HOOK_DEST"
echo "✓ Pre-commit hook installed to $BOT_HOOK_DEST"
echo "  (Prevents committing data/prd.json, data/progress.txt, data/run-state.json)"
echo ""

# Check org members cache exists (manually maintained, never auto-generated)
ORG_MEMBERS_FILE="$PROJECT_ROOT/.ignore/org-members.txt"
mkdir -p "$PROJECT_ROOT/.ignore"

if [ -f "$ORG_MEMBERS_FILE" ]; then
  echo "✓ Org members file found: $(wc -l < "$ORG_MEMBERS_FILE") members"
else
  echo "⚠️  Warning: Org members file not found at $ORG_MEMBERS_FILE"
  echo "   This file must be created manually. It is never auto-generated."
  echo "   Create it with one GitHub username per line."
fi
echo ""

echo "==================================="
echo "  Setup Complete!"
echo "==================================="
echo ""
echo "Next steps:"
echo "1. Configure git user/email if not already set (see above)"
echo "2. Review prd.json and update configuration as needed"
echo "3. Run the bot: cd $PROJECT_ROOT && ./run.sh"
echo ""
