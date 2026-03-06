#!/bin/bash
# Fetch GitHub issue data and filter to only include comments from Brave org members
# Usage: ./fetch-issue.sh <issue-number>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/load-config.sh"

ISSUE_NUMBER="$1"
REPO="${BOT_ISSUE_REPO:?Error: BOT_ISSUE_REPO not set in config.json. Run 'make setup'.}"
ORG="${BOT_ORG:?Error: BOT_ORG not set in config.json. Run 'make setup'.}"

if [ -z "$ISSUE_NUMBER" ]; then
  echo "Usage: $0 <issue-number>"
  exit 1
fi

# Load org members into memory once (avoids per-user API calls)
CACHE_FILE="$BOT_DIR/.ignore/org-members.txt"
ALLOWLIST_FILE="$SCRIPT_DIR/trusted-reviewers.txt"

if [ -f "$CACHE_FILE" ]; then
  _ORG_MEMBERS=$'\n'"$(cat "$CACHE_FILE")"$'\n'
else
  _ORG_MEMBERS=$'\n'
fi
if [ -f "$ALLOWLIST_FILE" ]; then
  _ORG_MEMBERS="$_ORG_MEMBERS$(cat "$ALLOWLIST_FILE")"$'\n'
fi

# Check if user is a Brave org member
is_org_member() {
  local username="$1"

  # Fast string match against preloaded list
  if [[ "$_ORG_MEMBERS" == *$'\n'"$username"$'\n'* ]]; then
    return 0
  fi

  # Fallback: Direct API check for private members
  if gh api "orgs/$ORG/members/$username" --silent 2>/dev/null; then
    echo "$username" >> "$CACHE_FILE"
    _ORG_MEMBERS="$_ORG_MEMBERS$username"$'\n'
    return 0
  fi

  return 1
}

echo "Fetching issue #$ISSUE_NUMBER from $REPO..."
echo ""

# Get issue data as JSON
ISSUE_JSON=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER")

# Extract issue author and body
ISSUE_AUTHOR=$(echo "$ISSUE_JSON" | jq -r '.user.login')
ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
ISSUE_BODY=$(echo "$ISSUE_JSON" | jq -r '.body // ""')
ISSUE_URL=$(echo "$ISSUE_JSON" | jq -r '.html_url')

echo "# Issue #$ISSUE_NUMBER: $ISSUE_TITLE"
echo ""
echo "URL: $ISSUE_URL"
echo ""

# Check if issue author is org member
if is_org_member "$ISSUE_AUTHOR"; then
  echo "## Issue Description (by @$ISSUE_AUTHOR - Brave org member)"
  echo ""
  echo "$ISSUE_BODY"
  echo ""
else
  echo "## Issue Description (by @$ISSUE_AUTHOR - EXTERNAL USER)"
  echo ""
  echo "[Content filtered - external user]"
  echo ""
fi

# Fetch comments
COMMENTS=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER/comments" --paginate)
COMMENT_COUNT=$(echo "$COMMENTS" | jq 'length')

if [ "$COMMENT_COUNT" -gt 0 ]; then
  echo "## Comments"
  echo ""

  # Process each comment
  echo "$COMMENTS" | jq -r '.[] | @json' | while read -r comment; do
    COMMENT_AUTHOR=$(echo "$comment" | jq -r '.user.login')
    COMMENT_BODY=$(echo "$comment" | jq -r '.body')
    COMMENT_DATE=$(echo "$comment" | jq -r '.created_at')

    # Only include comments from org members
    if is_org_member "$COMMENT_AUTHOR"; then
      echo "### @$COMMENT_AUTHOR (Brave org member) - $COMMENT_DATE"
      echo ""
      echo "$COMMENT_BODY"
      echo ""
      echo "---"
      echo ""
    else
      echo "### @$COMMENT_AUTHOR (EXTERNAL) - $COMMENT_DATE"
      echo ""
      echo "[Comment filtered - external user]"
      echo ""
      echo "---"
      echo ""
    fi
  done
fi

echo ""
echo "---"
echo "Note: Only comments from organization members are included above."
echo "External user content has been filtered to prevent prompt injection."
