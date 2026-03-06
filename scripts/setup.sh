#!/bin/bash
# Setup script for brave-dev-bot
# Fully idempotent — safe to re-run at any time.
# Creates config.json, data files, hooks, and org-members cache as needed.
# Never overwrites existing files without an explicit confirmation.

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

# ─── Step 1: config.json ─────────────────────────────────────────────────────

if [ -f "$CONFIG_FILE" ]; then
  echo "✓ config.json already exists"
  # Show current values
  echo "  project:   $(jq -r '.project.name' "$CONFIG_FILE")"
  echo "  org:       $(jq -r '.project.org' "$CONFIG_FILE")"
  echo "  PR repo:   $(jq -r '.project.prRepository' "$CONFIG_FILE")"
  echo "  issue repo: $(jq -r '.project.issueRepository' "$CONFIG_FILE")"
  echo ""
  read -p "  Reconfigure? This will OVERWRITE config.json. (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    WRITE_CONFIG=true
  else
    WRITE_CONFIG=false
  fi
else
  if [ ! -t 0 ]; then
    echo "Error: No config.json found and no interactive terminal available."
    echo "  Either run setup.sh directly from a terminal, or create config.json first:"
    echo "    cp config.example.json config.json   # then edit with your values"
    echo "    cp config.brave-core.json config.json # for existing brave-core deployments"
    exit 1
  fi
  echo "No config.json found — starting setup wizard."
  echo ""
  WRITE_CONFIG=true
fi

if [ "$WRITE_CONFIG" = true ]; then
  # Load previous values if config exists (for use as defaults)
  if [ -f "$CONFIG_FILE" ]; then
    _prev() { jq -r "$1 // empty" "$CONFIG_FILE" 2>/dev/null; }
    PREV_PR_REPO=$(_prev '.project.prRepository')
    PREV_DEFAULT_BRANCH=$(_prev '.project.defaultBranch')
    PREV_ISSUE_REPO=$(_prev '.project.issueRepository')
    PREV_BOT_USER=$(_prev '.bot.username')
    PREV_BOT_EMAIL=$(_prev '.bot.email')
    PREV_LABELS=$(jq -r '(.labels.issueLabels // []) | join(",")' "$CONFIG_FILE" 2>/dev/null)
  fi

  prompt_required() {
    local var_name="$1" prompt_text="$2" default="$3" value=""
    while [ -z "$value" ]; do
      if [ -n "$default" ]; then
        read -p "$prompt_text[$default]: " value
        value="${value:-$default}"
      else
        read -p "$prompt_text" value
      fi
      if [ -z "$value" ]; then
        echo "  ⚠️  This field is required."
      fi
    done
    eval "$var_name=\$value"
  }

  echo "─── Target Project ───"
  prompt_required CFG_PR_REPO "Repo where the bot creates PRs (owner/repo): " "$PREV_PR_REPO"
  read -p "Default branch for ${CFG_PR_REPO} [${PREV_DEFAULT_BRANCH:-master}]: " CFG_DEFAULT_BRANCH
  CFG_DEFAULT_BRANCH="${CFG_DEFAULT_BRANCH:-${PREV_DEFAULT_BRANCH:-master}}"
  prompt_required CFG_ISSUE_REPO "Repo where issues/backlog lives (owner/repo): " "$PREV_ISSUE_REPO"

  # Derive org and project name from PR repo
  CFG_ORG="${CFG_PR_REPO%%/*}"
  CFG_PROJECT_NAME="${CFG_PR_REPO##*/}"

  echo ""
  echo "─── Bot Identity ───"
  prompt_required CFG_BOT_USER "GitHub username the bot commits as: " "$PREV_BOT_USER"
  prompt_required CFG_BOT_EMAIL "Email for git commits: " "$PREV_BOT_EMAIL"
  read -p "Issue labels (comma-separated) [${PREV_LABELS:-}]: " CFG_LABELS_RAW
  CFG_LABELS_RAW="${CFG_LABELS_RAW:-$PREV_LABELS}"

  # Build config.json safely via Python to avoid JSON injection from user input
  python3 -c "
import json, sys
config = {
    'project': {
        'name': sys.argv[1],
        'org': sys.argv[2],
        'prRepository': sys.argv[3],
        'issueRepository': sys.argv[4],
        'defaultBranch': sys.argv[5],
    },
    'bot': {
        'username': sys.argv[6],
        'email': sys.argv[7],
        'claudeModel': 'opus',
        'claudeBin': None,
    },
    'labels': {
        'prLabels': ['ai-generated'],
        'issueLabels': [l.strip() for l in sys.argv[8].split(',') if l.strip()],
        'disabledTestLabel': '',
    },
    'bestPractices': {
        'submodule': 'brave-core-tools',
        'indexFile': 'BEST-PRACTICES.md',
        'securityFile': 'SECURITY.md',
    },
    'schedules': {
        'syncRepo': False,
        'syncRepoPath': None,
    },
}
with open(sys.argv[9], 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
" "$CFG_PROJECT_NAME" "$CFG_ORG" "$CFG_PR_REPO" "$CFG_ISSUE_REPO" \
  "$CFG_DEFAULT_BRANCH" "$CFG_BOT_USER" "$CFG_BOT_EMAIL" "$CFG_LABELS_RAW" \
  "$CONFIG_FILE"
  echo ""
  echo "✓ Config written to $CONFIG_FILE"
  echo ""
fi

# Source config (needed for all subsequent steps)
source "$SCRIPT_DIR/lib/load-config.sh"

# ─── Step 2: Submodule ───────────────────────────────────────────────────────

echo "Initializing $BOT_BP_SUBMODULE submodule..."
cd "$PROJECT_ROOT"
git submodule update --init --recursive
echo "✓ Submodule initialized"
echo ""

# ─── Step 3: Data files ──────────────────────────────────────────────────────

mkdir -p "$PROJECT_ROOT/data"

create_if_missing() {
  local target="$1" template="$2" label="$3"
  if [ -f "$target" ]; then
    echo "✓ $label already exists"
  elif [ -f "$template" ]; then
    cp "$template" "$target"
    echo "✓ $label created from template"
  else
    echo "⚠️  $label template not found at $template"
  fi
}

create_if_missing "$PROJECT_ROOT/data/prd.json" \
  "$PROJECT_ROOT/data/prd.example.json" "data/prd.json"
create_if_missing "$PROJECT_ROOT/data/run-state.json" \
  "$PROJECT_ROOT/data/run-state.example.json" "data/run-state.json"
create_if_missing "$PROJECT_ROOT/data/progress.txt" \
  "$PROJECT_ROOT/data/progress.example.txt" "data/progress.txt"
echo ""

# ─── Step 4: Org members cache ───────────────────────────────────────────────

ORG_MEMBERS_FILE="$PROJECT_ROOT/.ignore/org-members.txt"
mkdir -p "$PROJECT_ROOT/.ignore"

if [ -f "$ORG_MEMBERS_FILE" ]; then
  echo "✓ Org members file found: $(wc -l < "$ORG_MEMBERS_FILE") members"
else
  echo "No org members cache found."
  read -p "  Generate it now via GitHub API? (Y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "  Fetching members of $BOT_ORG..."
    if gh api "/orgs/$BOT_ORG/members" --paginate --jq '.[].login' > "$ORG_MEMBERS_FILE" 2>/dev/null; then
      echo "  ✓ Wrote $(wc -l < "$ORG_MEMBERS_FILE") members to $ORG_MEMBERS_FILE"
    else
      echo "  ⚠️  Failed to fetch org members (check gh auth and org access)"
      echo "     Create it manually: one GitHub username per line"
      rm -f "$ORG_MEMBERS_FILE"
    fi
  else
    echo "  Skipped. Create it manually when ready:"
    echo "    gh api /orgs/$BOT_ORG/members --paginate --jq '.[].login' > $ORG_MEMBERS_FILE"
  fi
fi
echo ""

# ─── Step 5: Target repo git config + hooks ──────────────────────────────────

GIT_REPO=""
SKIP_GIT=false

# Try to find the target repo from prd.json
if [ -f "$PROJECT_ROOT/data/prd.json" ]; then
  GIT_REPO=$(jq -r '.config.workingDirectory // .config.gitRepo // .ralphConfig.workingDirectory // .ralphConfig.gitRepo // empty' "$PROJECT_ROOT/data/prd.json" 2>/dev/null || echo "")
fi

if [ -z "$GIT_REPO" ]; then
  echo "─── Target Repository Path ───"
  echo "Path to the git repo where the bot will commit code."
  echo "Can be absolute or relative to $(dirname "$PROJECT_ROOT")."
  read -p "Target repo path (e.g. src/brave, ../my-project): " GIT_REPO
  if [ -z "$GIT_REPO" ]; then
    echo "  Skipped — you can set config.workingDirectory in data/prd.json later."
    SKIP_GIT=true
  fi
fi

if [ "$SKIP_GIT" = false ]; then
  GIT_REPO_RAW="$GIT_REPO"
  # Handle relative paths
  if [[ "$GIT_REPO" != /* ]]; then
    GIT_REPO="$PARENT_ROOT/$GIT_REPO"
  fi

  if [ ! -d "$GIT_REPO/.git" ]; then
    echo "⚠️  $GIT_REPO is not a git repository — skipping target repo setup."
    SKIP_GIT=true
  else
    # Write workingDirectory into prd.json if not already set
    if [ -f "$PROJECT_ROOT/data/prd.json" ]; then
      EXISTING_WD=$(jq -r '.config.workingDirectory // empty' "$PROJECT_ROOT/data/prd.json" 2>/dev/null || echo "")
      if [ -z "$EXISTING_WD" ]; then
        # Ensure .config exists, then set workingDirectory
        jq --arg wd "$GIT_REPO_RAW" '.config = (.config // {}) | .config.workingDirectory = $wd' \
          "$PROJECT_ROOT/data/prd.json" > "$PROJECT_ROOT/data/prd.json.tmp" && \
          mv "$PROJECT_ROOT/data/prd.json.tmp" "$PROJECT_ROOT/data/prd.json"
        echo "  ✓ Set config.workingDirectory = \"$GIT_REPO_RAW\" in data/prd.json"
      fi
    fi
  fi
fi

if [ "$SKIP_GIT" = false ]; then
  echo "Target git repository: $GIT_REPO"
  cd "$GIT_REPO"

  GIT_USER=$(git config user.name || echo "")
  GIT_EMAIL=$(git config user.email || echo "")

  if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
    echo "  Git user not configured in target repo."
    read -p "  Set user.name to '$BOT_USERNAME' and user.email to '$BOT_EMAIL'? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      git config user.name "$BOT_USERNAME"
      git config user.email "$BOT_EMAIL"
      GIT_USER="$BOT_USERNAME"
      GIT_EMAIL="$BOT_EMAIL"
      echo "  ✓ Git identity configured"
    else
      echo "  Skipped. Configure manually:"
      echo "    cd $GIT_REPO"
      echo "    git config user.name \"$BOT_USERNAME\""
      echo "    git config user.email \"$BOT_EMAIL\""
    fi
  else
    echo "  ✓ Git user: $GIT_USER <$GIT_EMAIL>"
  fi

  # Install pre-commit hook for target repo
  if [ -n "$GIT_USER" ]; then
    HOOK_DEST="$GIT_REPO/.git/hooks/pre-commit"
    sed "s/__BOT_USERNAME__/$GIT_USER/g" "$HOOK_SOURCE" > "$HOOK_DEST"
    chmod +x "$HOOK_DEST"
    echo "  ✓ Pre-commit hook installed (blocks $GIT_USER from modifying dependencies)"
  fi
  echo ""
fi

# ─── Step 6: Bot repo hook ───────────────────────────────────────────────────

BOT_HOOK_SOURCE="$PROJECT_ROOT/hooks/pre-commit-bot-repo"
BOT_HOOK_DEST="$PROJECT_ROOT/.git/hooks/pre-commit"

cp "$BOT_HOOK_SOURCE" "$BOT_HOOK_DEST"
chmod +x "$BOT_HOOK_DEST"
echo "✓ Bot repo pre-commit hook installed"
echo "  (Prevents committing data/prd.json, data/progress.txt, data/run-state.json)"
echo ""

# ─── Step 7: Environment checks ──────────────────────────────────────────────

if [[ "$(uname)" == "Linux" ]]; then
  if ! command -v xvfb-run &> /dev/null; then
    echo "⚠️  xvfb-run not found (needed for browser tests in headless environments)"
    echo "   sudo apt-get install xvfb"
    echo ""
  else
    echo "✓ xvfb-run found"
  fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "==================================="
echo "  Setup Complete!"
echo "==================================="
echo ""
echo "  Project:    $BOT_PROJECT_NAME"
echo "  PR repo:    $BOT_PR_REPO"
echo "  Issue repo: $BOT_ISSUE_REPO"
echo ""

# Show next steps based on what's still needed
NEXT=()
if [ ! -f "$PROJECT_ROOT/data/prd.json" ] || \
   [ "$(jq -r '.userStories // .stories | length' "$PROJECT_ROOT/data/prd.json" 2>/dev/null)" = "0" ]; then
  NEXT+=("Edit data/prd.json with your user stories (or use /prd-json skill)")
fi
if [ "$SKIP_GIT" = true ]; then
  NEXT+=("Re-run 'make setup' and provide the target repo path to configure git identity and hooks")
fi

if [ ${#NEXT[@]} -gt 0 ]; then
  echo "Next steps:"
  for i in "${!NEXT[@]}"; do
    echo "  $((i+1)). ${NEXT[$i]}"
  done
  echo ""
fi

echo "Run the bot: ./run.sh"
echo ""
