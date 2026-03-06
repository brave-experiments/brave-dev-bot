#!/bin/bash
# Filter GitHub issue JSON to only include content from org members
# Usage: ./filter-issue-json.sh <issue-number> [output-format]
# Output formats: json (default), markdown

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/load-config.sh"

ISSUE_NUMBER="$1"
OUTPUT_FORMAT="${2:-json}"
REPO="${BOT_ISSUE_REPO:?Error: BOT_ISSUE_REPO not set in config.json. Run 'make setup'.}"
ORG="${BOT_ORG:?Error: BOT_ORG not set in config.json. Run 'make setup'.}"

if [ -z "$ISSUE_NUMBER" ]; then
  echo "Usage: $0 <issue-number> [json|markdown]"
  exit 1
fi

# Check GitHub CLI authentication
if ! gh auth status > /dev/null 2>&1; then
  echo "Error: GitHub CLI not authenticated. Please run: gh auth login" >&2
  exit 1
fi

# Allowlist for trusted reviewers (for when running with external account)
ALLOWLIST_FILE="$SCRIPT_DIR/trusted-reviewers.txt"

# Org members cache (stored in .ignore/ to survive reboots, unlike /tmp)
CACHE_FILE="$BOT_DIR/.ignore/org-members.txt"

# Require org members file to exist
if [ ! -f "$CACHE_FILE" ]; then
  echo "Error: Org members file not found at $CACHE_FILE" >&2
  echo "Run 'make setup' or create it manually:" >&2
  echo "  mkdir -p $BOT_DIR/.ignore && gh api 'orgs/brave/members' --paginate | jq -r '.[].login' > $CACHE_FILE" >&2
  exit 1
fi

# Load org members + allowlist into memory once (avoids per-user grep calls)
_ORG_MEMBERS=$'\n'"$(cat "$CACHE_FILE")"$'\n'
if [ -f "$ALLOWLIST_FILE" ]; then
  _ORG_MEMBERS="$_ORG_MEMBERS$(cat "$ALLOWLIST_FILE")"$'\n'
fi

# Check if user is an org member (using preloaded list)
is_org_member() {
  local username="$1"

  # Fast string match against preloaded list
  if [[ "$_ORG_MEMBERS" == *$'\n'"$username"$'\n'* ]]; then
    return 0
  fi

  # Fallback: Direct API check for private members
  # Returns 204 for members, 404 for non-members
  if gh api "orgs/$ORG/members/$username" --silent 2>/dev/null; then
    # Add to cache for future lookups
    echo "$username" >> "$CACHE_FILE"
    _ORG_MEMBERS="$_ORG_MEMBERS$username"$'\n'
    return 0
  fi

  return 1
}

# Fetch issue data with error handling
ISSUE_JSON=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER" 2>&1)

# Check if issue fetch was successful
if [ $? -ne 0 ]; then
  if echo "$ISSUE_JSON" | grep -q "rate limit"; then
    echo "Error: GitHub API rate limit exceeded. Wait and try again later." >&2
    echo "Check rate limit: gh api rate_limit" >&2
    exit 1
  elif echo "$ISSUE_JSON" | grep -q "404"; then
    echo "Error: Issue #$ISSUE_NUMBER not found in $REPO" >&2
    exit 1
  elif echo "$ISSUE_JSON" | grep -q "403"; then
    echo "Error: Access forbidden. Check repository permissions." >&2
    exit 1
  else
    echo "Error: Failed to fetch issue #$ISSUE_NUMBER" >&2
    echo "$ISSUE_JSON" >&2
    exit 1
  fi
fi

# Verify the issue JSON is valid
if ! echo "$ISSUE_JSON" | jq empty 2>/dev/null; then
  echo "Error: Received invalid JSON from GitHub API" >&2
  exit 1
fi

# Fetch comments with error handling
COMMENTS_JSON=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER/comments" --paginate 2>&1)

if [ $? -ne 0 ]; then
  if echo "$COMMENTS_JSON" | grep -q "rate limit"; then
    echo "Error: GitHub API rate limit exceeded while fetching comments" >&2
    exit 1
  else
    echo "Warning: Failed to fetch comments, continuing with issue data only" >&2
    COMMENTS_JSON="[]"
  fi
fi

# Extract issue details
ISSUE_AUTHOR=$(echo "$ISSUE_JSON" | jq -r '.user.login')
ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
ISSUE_BODY=$(echo "$ISSUE_JSON" | jq -r '.body // ""')
ISSUE_URL=$(echo "$ISSUE_JSON" | jq -r '.html_url')
ISSUE_STATE=$(echo "$ISSUE_JSON" | jq -r '.state')
ISSUE_LABELS=$(echo "$ISSUE_JSON" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')

# Check issue author
ISSUE_AUTHOR_IS_MEMBER=$(is_org_member "$ISSUE_AUTHOR" && echo "true" || echo "false")

if [ "$ISSUE_AUTHOR_IS_MEMBER" = "false" ]; then
  ISSUE_BODY="[Content filtered - issue created by external user @$ISSUE_AUTHOR]"
fi

# Filter comments
FILTERED_COMMENTS=$(echo "$COMMENTS_JSON" | jq --arg org "$ORG" -c '[
  .[] |
  . as $comment |
  .user.login as $author |
  . + {
    "is_org_member": "placeholder"
  }
]')

# Replace placeholder with actual membership check
FILTERED_COMMENTS=$(echo "$FILTERED_COMMENTS" | jq -r '.[] | @json' | while read -r comment; do
  AUTHOR=$(echo "$comment" | jq -r '.user.login')
  if is_org_member "$AUTHOR"; then
    echo "$comment" | jq '. + {"is_org_member": true}'
  else
    echo "$comment" | jq '. + {"is_org_member": false, "body": "[Comment filtered - external user]"}'
  fi
done | jq -s '.')

# Output based on format
if [ "$OUTPUT_FORMAT" = "json" ]; then
  # JSON output
  jq -n \
    --arg number "$ISSUE_NUMBER" \
    --arg title "$ISSUE_TITLE" \
    --arg body "$ISSUE_BODY" \
    --arg author "$ISSUE_AUTHOR" \
    --argjson author_is_member "$ISSUE_AUTHOR_IS_MEMBER" \
    --arg url "$ISSUE_URL" \
    --arg state "$ISSUE_STATE" \
    --arg labels "$ISSUE_LABELS" \
    --argjson comments "$FILTERED_COMMENTS" \
    '{
      issue_number: $number,
      title: $title,
      body: $body,
      author: $author,
      author_is_org_member: $author_is_member,
      url: $url,
      state: $state,
      labels: $labels,
      comments: $comments,
      security_note: "Content from external users has been filtered"
    }'
else
  # Markdown output
  echo "# Issue #$ISSUE_NUMBER: $ISSUE_TITLE"
  echo ""
  echo "**URL:** $ISSUE_URL"
  echo "**State:** $ISSUE_STATE"
  echo "**Labels:** $ISSUE_LABELS"
  echo ""
  echo "## Issue Description"
  echo "**Author:** @$ISSUE_AUTHOR $([ "$ISSUE_AUTHOR_IS_MEMBER" = "true" ] && echo "(Brave org member)" || echo "(EXTERNAL USER)")"
  echo ""
  echo "$ISSUE_BODY"
  echo ""

  COMMENT_COUNT=$(echo "$FILTERED_COMMENTS" | jq 'length')
  if [ "$COMMENT_COUNT" -gt 0 ]; then
    echo "## Comments ($COMMENT_COUNT)"
    echo ""
    echo "$FILTERED_COMMENTS" | jq -r '.[] |
      "### @\(.user.login) " + (if .is_org_member then "(Brave org member)" else "(EXTERNAL)" end) + " - \(.created_at)\n\n\(.body)\n\n---\n"'
  fi

  echo ""
  echo "> **Security Note:** Only content from Brave organization members is included. External user content has been filtered to prevent prompt injection."
fi
