#!/bin/bash
# Filter PR review comments to only include Brave org members
# Prevents prompt injection from external contributors

set -e

PR_NUMBER="$1"
OUTPUT_FORMAT="${2:-markdown}"  # markdown or json
PR_REPO="${3:-brave/brave-core}"  # Default to brave-core where PRs are created
INCLUDE_AUTHOR="${4:-}"  # Optional: include this author's PR body unfiltered (for external contributor PRs)

if [ -z "$PR_NUMBER" ]; then
  echo "Usage: $0 <pr-number> [markdown|json] [repo]"
  echo "  repo defaults to: brave/brave-core"
  exit 1
fi

# Check GitHub CLI authentication
if ! gh auth status > /dev/null 2>&1; then
  echo "Error: GitHub CLI not authenticated. Please run: gh auth login" >&2
  exit 1
fi

# Allowlist for trusted reviewers (for when running with external account)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST_FILE="$SCRIPT_DIR/trusted-reviewers.txt"

# Org members cache (stored in .ignore/ to survive reboots, unlike /tmp)
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_FILE="$BOT_DIR/.ignore/org-members.txt"

# Require org members file to exist
if [ ! -f "$CACHE_FILE" ]; then
  echo "Error: Org members file not found at $CACHE_FILE" >&2
  echo "Run setup.sh or create it manually:" >&2
  echo "  mkdir -p $BOT_DIR/.ignore && gh api 'orgs/brave/members' --paginate | jq -r '.[].login' > $CACHE_FILE" >&2
  exit 1
fi

# Function to check if user is org member
is_org_member() {
  local username="$1"

  # First check allowlist (for trusted reviewers when using external account)
  if [ -f "$ALLOWLIST_FILE" ] && grep -q "^${username}$" "$ALLOWLIST_FILE"; then
    return 0
  fi

  # Check cache (fast path)
  if grep -q "^${username}$" "$CACHE_FILE"; then
    return 0
  fi

  # Fallback: Direct API check for private members
  # Returns 204 for members, 404 for non-members
  if gh api "orgs/brave/members/$username" --silent 2>/dev/null; then
    # Add to cache for future lookups
    echo "$username" >> "$CACHE_FILE"
    return 0
  fi

  return 1
}

# Fetch PR data with error handling
PR_DATA=$(gh api "repos/$PR_REPO/pulls/$PR_NUMBER" 2>&1)

# Check if PR fetch was successful
if [ $? -ne 0 ]; then
  if echo "$PR_DATA" | grep -q "rate limit"; then
    echo "Error: GitHub API rate limit exceeded. Wait and try again later." >&2
    echo "Check rate limit: gh api rate_limit" >&2
    exit 1
  elif echo "$PR_DATA" | grep -q "404"; then
    echo "Error: PR #$PR_NUMBER not found in $PR_REPO" >&2
    exit 1
  elif echo "$PR_DATA" | grep -q "403"; then
    echo "Error: Access forbidden. Check repository permissions." >&2
    exit 1
  else
    echo "Error: Failed to fetch PR #$PR_NUMBER" >&2
    echo "$PR_DATA" >&2
    exit 1
  fi
fi

# Verify the PR JSON is valid
if ! echo "$PR_DATA" | jq empty 2>/dev/null; then
  echo "Error: Received invalid JSON from GitHub API" >&2
  exit 1
fi

PR_TITLE=$(echo "$PR_DATA" | jq -r '.title')
PR_AUTHOR=$(echo "$PR_DATA" | jq -r '.user.login')
PR_STATE=$(echo "$PR_DATA" | jq -r '.state')
PR_MERGEABLE=$(echo "$PR_DATA" | jq -r '.mergeable')
PR_MERGED=$(echo "$PR_DATA" | jq -r '.merged')

# Fetch reviews with error handling
REVIEWS=$(gh api "repos/$PR_REPO/pulls/$PR_NUMBER/reviews" --paginate 2>&1)
if [ $? -ne 0 ]; then
  if echo "$REVIEWS" | grep -q "rate limit"; then
    echo "Error: GitHub API rate limit exceeded while fetching reviews" >&2
    exit 1
  else
    echo "Warning: Failed to fetch reviews, continuing without review data" >&2
    REVIEWS="[]"
  fi
fi

# Fetch review comments with error handling
REVIEW_COMMENTS=$(gh api "repos/$PR_REPO/pulls/$PR_NUMBER/comments" --paginate 2>&1)
if [ $? -ne 0 ]; then
  if echo "$REVIEW_COMMENTS" | grep -q "rate limit"; then
    echo "Error: GitHub API rate limit exceeded while fetching review comments" >&2
    exit 1
  else
    echo "Warning: Failed to fetch review comments, continuing without comment data" >&2
    REVIEW_COMMENTS="[]"
  fi
fi

# Fetch general PR comments with error handling
ISSUE_COMMENTS=$(gh api "repos/$PR_REPO/issues/$PR_NUMBER/comments" --paginate 2>&1)
if [ $? -ne 0 ]; then
  if echo "$ISSUE_COMMENTS" | grep -q "rate limit"; then
    echo "Error: GitHub API rate limit exceeded while fetching discussion comments" >&2
    exit 1
  else
    echo "Warning: Failed to fetch discussion comments, continuing without comment data" >&2
    ISSUE_COMMENTS="[]"
  fi
fi

# Get latest push timestamp from PR data
LATEST_PUSH_TIMESTAMP=$(echo "$PR_DATA" | jq -r '.head.sha' | xargs -I {} gh api "repos/$PR_REPO/commits/{}" --jq '.commit.committer.date')

# Find latest reviewer activity timestamp (from Brave org members only)
LATEST_REVIEWER_TIMESTAMP=""

# Check reviews
if [ "$(echo "$REVIEWS" | jq 'length')" -gt 0 ]; then
  LATEST_REVIEW_TIME=$(echo "$REVIEWS" | jq -r --arg cache "$(cat "$CACHE_FILE")" '.[] | select(.user.login as $u | ($cache | split("\n") | index($u))) | .submitted_at' | sort -r | head -1)
  if [ -n "$LATEST_REVIEW_TIME" ]; then
    LATEST_REVIEWER_TIMESTAMP="$LATEST_REVIEW_TIME"
  fi
fi

# Check review comments
if [ "$(echo "$REVIEW_COMMENTS" | jq 'length')" -gt 0 ]; then
  LATEST_COMMENT_TIME=$(echo "$REVIEW_COMMENTS" | jq -r --arg cache "$(cat "$CACHE_FILE")" '.[] | select(.user.login as $u | ($cache | split("\n") | index($u))) | .created_at' | sort -r | head -1)
  if [ -n "$LATEST_COMMENT_TIME" ] && [ "$LATEST_COMMENT_TIME" \> "$LATEST_REVIEWER_TIMESTAMP" ]; then
    LATEST_REVIEWER_TIMESTAMP="$LATEST_COMMENT_TIME"
  fi
fi

# Check issue comments
if [ "$(echo "$ISSUE_COMMENTS" | jq 'length')" -gt 0 ]; then
  LATEST_ISSUE_TIME=$(echo "$ISSUE_COMMENTS" | jq -r --arg cache "$(cat "$CACHE_FILE")" '.[] | select(.user.login as $u | ($cache | split("\n") | index($u))) | .created_at' | sort -r | head -1)
  if [ -n "$LATEST_ISSUE_TIME" ] && [ "$LATEST_ISSUE_TIME" \> "$LATEST_REVIEWER_TIMESTAMP" ]; then
    LATEST_REVIEWER_TIMESTAMP="$LATEST_ISSUE_TIME"
  fi
fi

# Determine who went last
WHO_WENT_LAST="unknown"
if [ -z "$LATEST_REVIEWER_TIMESTAMP" ]; then
  WHO_WENT_LAST="bot"  # No reviewer activity yet
elif [ "$LATEST_REVIEWER_TIMESTAMP" \> "$LATEST_PUSH_TIMESTAMP" ]; then
  WHO_WENT_LAST="reviewer"  # Reviewer commented after bot's last push
else
  WHO_WENT_LAST="bot"  # Bot pushed after reviewer's last comment
fi

if [ "$OUTPUT_FORMAT" = "json" ]; then
  # JSON output - filter arrays
  FILTERED_REVIEWS=$(echo "$REVIEWS" | jq --arg cache "$(cat "$CACHE_FILE")" '
    map(
      . as $review |
      if ($cache | split("\n") | index($review.user.login)) then
        .
      else
        .body = "[Comment filtered - external user]" |
        .filtered = true
      end
    )
  ')

  FILTERED_REVIEW_COMMENTS=$(echo "$REVIEW_COMMENTS" | jq --arg cache "$(cat "$CACHE_FILE")" '
    map(
      . as $comment |
      if ($cache | split("\n") | index($comment.user.login)) then
        .
      else
        .body = "[Comment filtered - external user]" |
        .filtered = true
      end
    )
  ')

  FILTERED_ISSUE_COMMENTS=$(echo "$ISSUE_COMMENTS" | jq --arg cache "$(cat "$CACHE_FILE")" '
    map(
      . as $comment |
      if ($cache | split("\n") | index($comment.user.login)) then
        .
      else
        .body = "[Comment filtered - external user]" |
        .filtered = true
      end
    )
  ')

  # Include PR body for external contributor PRs when INCLUDE_AUTHOR is set
  INCLUDE_PR_BODY="false"
  if [ -n "$INCLUDE_AUTHOR" ] && [ "$INCLUDE_AUTHOR" = "$PR_AUTHOR" ]; then
    INCLUDE_PR_BODY="true"
  fi

  # Output combined JSON with timestamp comparison
  jq -n \
    --argjson pr_data "$PR_DATA" \
    --argjson reviews "$FILTERED_REVIEWS" \
    --argjson review_comments "$FILTERED_REVIEW_COMMENTS" \
    --argjson issue_comments "$FILTERED_ISSUE_COMMENTS" \
    --arg latest_push "$LATEST_PUSH_TIMESTAMP" \
    --arg latest_reviewer "$LATEST_REVIEWER_TIMESTAMP" \
    --arg who_went_last "$WHO_WENT_LAST" \
    --arg include_pr_body "$INCLUDE_PR_BODY" \
    '{
      pr: (if $include_pr_body == "true" then $pr_data else ($pr_data | del(.body)) end),
      reviews: $reviews,
      review_comments: $review_comments,
      issue_comments: $issue_comments,
      timestamp_analysis: {
        latest_push_timestamp: $latest_push,
        latest_reviewer_timestamp: $latest_reviewer,
        who_went_last: $who_went_last
      }
    }'

else
  # Markdown output
  echo "# PR #$PR_NUMBER: $PR_TITLE"
  echo ""
  echo "**Author:** @$PR_AUTHOR $(is_org_member "$PR_AUTHOR" && echo "(Brave org member)" || echo "(EXTERNAL)")"
  echo "**State:** $PR_STATE"
  echo "**Merged:** $PR_MERGED"
  echo "**Mergeable:** $PR_MERGEABLE"
  echo ""

  # Include PR body/description for external contributor PRs when INCLUDE_AUTHOR is set
  if [ -n "$INCLUDE_AUTHOR" ] && [ "$INCLUDE_AUTHOR" = "$PR_AUTHOR" ]; then
    PR_BODY=$(echo "$PR_DATA" | jq -r '.body // ""')
    if [ -n "$PR_BODY" ] && [ "$PR_BODY" != "null" ]; then
      echo "## PR Description (from external contributor @$PR_AUTHOR)"
      echo ""
      echo "$PR_BODY"
      echo ""
    fi
  fi

  echo "## Timestamp Analysis"
  echo ""
  echo "**Latest Push:** $LATEST_PUSH_TIMESTAMP"
  echo "**Latest Reviewer Activity:** ${LATEST_REVIEWER_TIMESTAMP:-None}"
  echo "**Who Went Last:** $WHO_WENT_LAST"
  echo ""

  # Reviews
  echo "## Reviews"
  echo ""
  REVIEW_COUNT=$(echo "$REVIEWS" | jq 'length')
  if [ "$REVIEW_COUNT" -eq 0 ]; then
    echo "No reviews yet."
    echo ""
  else
    echo "$REVIEWS" | jq -r '.[] | "\(.user.login)|\(.state)|\(.submitted_at)|\(.body)"' | while IFS='|' read -r username state submitted_at body; do
      if is_org_member "$username"; then
        echo "### @$username (Brave org member) - $state - $submitted_at"
        echo ""
        if [ -n "$body" ] && [ "$body" != "null" ]; then
          echo "$body"
        fi
        echo ""
      else
        echo "### @$username (EXTERNAL) - $state - $submitted_at"
        echo ""
        echo "[Review filtered - external user]"
        echo ""
      fi
    done
  fi

  # Review Comments (inline code comments)
  echo "## Review Comments (Code)"
  echo ""
  COMMENT_COUNT=$(echo "$REVIEW_COMMENTS" | jq 'length')
  if [ "$COMMENT_COUNT" -eq 0 ]; then
    echo "No review comments."
    echo ""
  else
    echo "$REVIEW_COMMENTS" | jq -r '.[] | "\(.user.login)|\(.path)|\(.created_at)|\(.body)"' | while IFS='|' read -r username path created_at body; do
      if is_org_member "$username"; then
        echo "### @$username (Brave org member) - $created_at"
        echo "**File:** $path"
        echo ""
        echo "$body"
        echo ""
      else
        echo "### @$username (EXTERNAL) - $created_at"
        echo "**File:** $path"
        echo ""
        echo "[Comment filtered - external user]"
        echo ""
      fi
    done
  fi

  # Issue Comments (general PR discussion)
  echo "## Discussion Comments"
  echo ""
  ISSUE_COMMENT_COUNT=$(echo "$ISSUE_COMMENTS" | jq 'length')
  if [ "$ISSUE_COMMENT_COUNT" -eq 0 ]; then
    echo "No discussion comments."
    echo ""
  else
    echo "$ISSUE_COMMENTS" | jq -r '.[] | "\(.user.login)|\(.created_at)|\(.body)"' | while IFS='|' read -r username created_at body; do
      if is_org_member "$username"; then
        echo "### @$username (Brave org member) - $created_at"
        echo ""
        echo "$body"
        echo ""
      else
        echo "### @$username (EXTERNAL) - $created_at"
        echo ""
        echo "[Comment filtered - external user]"
        echo ""
      fi
    done
  fi
fi
