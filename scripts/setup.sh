#!/bin/bash
# Setup script for brave-bot
# This script creates config.json (if missing), installs hooks, and validates the environment.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
HOOK_SOURCE="$PROJECT_ROOT/hooks/pre-commit"
CONFIG_FILE="$PROJECT_ROOT/config.json"

echo "==================================="
echo "  Brave Bot Setup"
echo "==================================="
echo ""

# --- Config wizard: create config.json if missing ---
if [ ! -f "$CONFIG_FILE" ]; then
  echo "No config.json found. Let's set up a new project."
  echo ""

  read -p "Project name (e.g. brave-core): " CFG_PROJECT_NAME
  read -p "GitHub org (e.g. brave): " CFG_ORG
  read -p "PR repository (owner/repo, e.g. brave/brave-core): " CFG_PR_REPO
  read -p "Issue repository (owner/repo, e.g. brave/brave-browser): " CFG_ISSUE_REPO
  read -p "Default branch (e.g. master): " CFG_DEFAULT_BRANCH
  CFG_DEFAULT_BRANCH="${CFG_DEFAULT_BRANCH:-master}"
  read -p "Bot GitHub username (e.g. netzenbot): " CFG_BOT_USER
  read -p "Bot email (e.g. netzenbot@brave.com): " CFG_BOT_EMAIL
  read -p "Issue labels (comma-separated, e.g. bot/type/test): " CFG_LABELS_RAW

  # Build labels JSON array
  CFG_LABELS_JSON=$(echo "$CFG_LABELS_RAW" | python3 -c "
import sys, json
labels = [l.strip() for l in sys.stdin.read().split(',') if l.strip()]
print(json.dumps(labels))
")

  cat > "$CONFIG_FILE" <<CFGEOF
{
  "project": {
    "name": "$CFG_PROJECT_NAME",
    "org": "$CFG_ORG",
    "prRepository": "$CFG_PR_REPO",
    "issueRepository": "$CFG_ISSUE_REPO",
    "defaultBranch": "$CFG_DEFAULT_BRANCH"
  },
  "bot": {
    "username": "$CFG_BOT_USER",
    "email": "$CFG_BOT_EMAIL",
    "claudeModel": "opus",
    "claudeBin": null
  },
  "labels": {
    "prLabels": ["ai-generated"],
    "issueLabels": $CFG_LABELS_JSON,
    "disabledTestLabel": "disabled-brave-test"
  },
  "bestPractices": {
    "submodule": "brave-core-tools",
    "indexFile": "BEST-PRACTICES.md",
    "securityFile": "SECURITY.md"
  },
  "schedules": {
    "syncRepo": false,
    "syncRepoPath": null
  }
}
CFGEOF
  echo ""
  echo "✓ Config written to $CONFIG_FILE"
  echo ""
fi

# Source config
source "$SCRIPT_DIR/lib/load-config.sh"

# Initialize submodule
echo "Initializing $BOT_BP_SUBMODULE submodule..."
cd "$PROJECT_ROOT"
git submodule update --init --recursive
echo "✓ Submodule initialized"
echo ""

# Check if prd.json exists (not required — can be created later)
if [ ! -f "$PROJECT_ROOT/data/prd.json" ]; then
  echo "ℹ️  No data/prd.json found (this is normal for fresh setup)."
  echo "   Create one when you're ready to start the bot."
  echo "   See data/prd.example.json for the template."
  echo ""

  # Without a prd.json we can't validate the git repo. Skip hook installation
  # for now — it will be done on the next setup run.
  SKIP_GIT_VALIDATION=true
fi

# Extract git repo from data/prd.json if it exists
GIT_REPO=""
if [ "${SKIP_GIT_VALIDATION:-}" != "true" ]; then
  GIT_REPO=$(jq -r '.config.workingDirectory // .config.gitRepo // .ralphConfig.workingDirectory // .ralphConfig.gitRepo // empty' "$PROJECT_ROOT/data/prd.json" 2>/dev/null || echo "")

  if [ -z "$GIT_REPO" ]; then
    echo "⚠️  Warning: Could not find git repository in prd.json"
    echo "   Please set config.workingDirectory or config.gitRepo"
    echo ""
    SKIP_GIT_VALIDATION=true
  fi
fi

if [ "${SKIP_GIT_VALIDATION:-}" != "true" ]; then
  # Handle relative paths
  if [[ "$GIT_REPO" != /* ]]; then
    GIT_REPO="$PARENT_ROOT/$GIT_REPO"
  fi

  echo "Target git repository: $GIT_REPO"
  echo ""

  # Verify git repo exists
  if [ ! -d "$GIT_REPO/.git" ]; then
    echo "⚠️  Warning: $GIT_REPO is not a git repository"
    echo "   Hook installation skipped."
    echo ""
    SKIP_GIT_VALIDATION=true
  fi
fi

if [ "${SKIP_GIT_VALIDATION:-}" != "true" ]; then
  # Check git config (needed before hook installation)
  echo "Checking git configuration..."
  cd "$GIT_REPO"

  GIT_USER=$(git config user.name || echo "")
  GIT_EMAIL=$(git config user.email || echo "")

  if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
    echo ""
    echo "⚠️  Git user configuration not found in target repo."
    echo "   Configure it with:"
    echo ""
    echo "  cd $GIT_REPO"
    echo "  git config user.name \"$BOT_USERNAME\""
    echo "  git config user.email \"$BOT_EMAIL\""
    echo ""
  else
    echo "✓ Git user: $GIT_USER"
    echo "✓ Git email: $GIT_EMAIL"
    echo ""
  fi

  # Install pre-commit hook for target repo
  if [ -n "$GIT_USER" ]; then
    HOOK_DEST="$GIT_REPO/.git/hooks/pre-commit"
    echo "Installing pre-commit hook to target repo..."
    sed "s/__BOT_USERNAME__/$GIT_USER/g" "$HOOK_SOURCE" > "$HOOK_DEST"
    chmod +x "$HOOK_DEST"
    echo "✓ Pre-commit hook installed to $HOOK_DEST (bot user: $GIT_USER)"
    echo ""
  fi
fi

# Install pre-commit hook for bot repo itself
BOT_HOOK_SOURCE="$PROJECT_ROOT/hooks/pre-commit-bot-repo"
BOT_HOOK_DEST="$PROJECT_ROOT/.git/hooks/pre-commit"

echo "Installing pre-commit hook to bot repo..."
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

# Check for xvfb on Linux (needed for browser tests in headless/SSH environments)
if [[ "$(uname)" == "Linux" ]]; then
  if ! command -v xvfb-run &> /dev/null; then
    echo "⚠️  Warning: xvfb-run not found"
    echo "   Browser tests require a display server. On headless Linux (SSH, CI), install xvfb:"
    echo "   sudo apt-get install xvfb"
    echo ""
  else
    echo "✓ xvfb-run found (needed for browser tests in headless environments)"
    echo ""
  fi
fi

echo "==================================="
echo "  Setup Complete!"
echo "==================================="
echo ""
echo "Project: $BOT_PROJECT_NAME"
echo "PR Repository: $BOT_PR_REPO"
echo "Issue Repository: $BOT_ISSUE_REPO"
echo ""
echo "Next steps:"
echo "1. Create data/prd.json (see data/prd.example.json)"
echo "2. Configure git user/email in the target repo"
echo "3. Run the bot: cd $PROJECT_ROOT && ./run.sh"
echo ""
