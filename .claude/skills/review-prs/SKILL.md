---
name: review-prs
description: "Review PRs in brave/brave-core for best practices violations. Supports single PR (#12345), state filter (open/closed/all), and auto mode for cron. Triggers on: review prs, review recent prs, /review-prs, check prs for best practices."
argument-hint: "[days|page<N>|#<PR>] [open|closed|all] [auto]"
allowed-tools: Bash(gh pr diff:*)
---

# Review PRs for Best Practices

Scan recent open PRs in `brave/brave-core` for violations of documented best practices.

- **Interactive mode** (default): drafts comments and asks for user approval before posting.
- **Auto mode** (`auto` argument): posts all violations automatically without approval. Designed for cron/headless use.

---

## The Job

When invoked with `/review-prs [days|page<N>|#<PR>] [open|closed|all] [auto]`:

**Detect auto mode:** If the arguments contain `auto`, set `AUTO_MODE=true`. In auto mode, all violations are posted without asking for user approval. Strip `auto` from arguments before passing to the fetch script.

1. **Fetch and filter PRs** by running the fetch script (pass through all arguments except `auto`):
   ```bash
   python3 .claude/skills/review-prs/fetch-prs.py [args...]
   ```
   The script handles all fetching, filtering (drafts, uplifts, CI runs, l10n, date cutoff), and cache checking. It outputs JSON:
   ```json
   {
     "prs": [{"number": 42001, "title": "...", "headRefOid": "abc123", "author": "user"}],
     "summary": {"total_fetched": 50, "to_review": 5, "skipped_filtered": 30, "skipped_cached": 15}
   }
   ```
2. **Print progress summary** from the summary stats (this goes to stdout and will appear in cron logs):
   ```
   Found N PRs to review (M skipped: X drafts/filtered, Y cached)
   PRs to review: #12345 (title), #12346 (title), ...
   ```
3. **Review each PR** one at a time using per-category parallel subagents (see Per-Category Review Workflow below)
4. **Aggregate and present findings** from all category subagents
5. **Update the cache for EVERY reviewed PR** — this is mandatory regardless of whether violations were found, comments were posted, or comments were skipped. See Step 6 in Per-Category Review Workflow.
6. **If AUTO_MODE**: post all violations immediately and log each result (see Auto Posting below — the per-PR logging and final summary are MANDATORY). **Otherwise**: draft each comment and ask user to approve before posting

---

## Per-Category Review Workflow

**IMPORTANT:** The main context does NOT load best practices docs or PR diffs. Each PR is reviewed by multiple focused subagents — one per best-practice category — running in parallel. This ensures every rule is systematically checked rather than relying on a single subagent to hold 150+ rules in mind.

### Step 1: Classify Changed Files

Before launching subagents, fetch the file list to determine which categories apply:

```bash
gh pr diff --repo brave/brave-core {number} --name-only
```

Classify the changed files:
- **has_cpp_files**: `.cc`, `.h`, `.mm` files
- **has_test_files**: `*_test.cc`, `*_browsertest.cc`, `*_unittest.cc`, `*.test.ts`, `*.test.tsx`
- **has_chromium_src**: `chromium_src/` paths
- **has_build_files**: `BUILD.gn`, `DEPS`, `*.gni`
- **has_frontend_files**: `.ts`, `.tsx`, `.html`, `.css`

### Step 1.5: Fetch Existing PR Comments (Re-review Context)

Before launching subagents, fetch all existing review comments and discussion on the PR using the filter script:

```bash
./brave-core-bot/scripts/filter-pr-reviews.sh {number} markdown
```

This returns all past review comments, inline code comments, and discussion comments from Brave org members (filtered for security). Pass this output to each subagent as `PRIOR_COMMENTS` context (see Step 3).

**Why this matters:** When re-reviewing a PR after new commits, the bot must be aware of:
- Its own previous comments (from "brave-core-bot" or "Review via brave-core-bot") to avoid repeating the same feedback
- Author and reviewer responses that explain or justify a design choice
- Issues that were already acknowledged and addressed

If there are no prior comments (first review), skip this step and omit the prior comments section from the subagent prompt.

### Step 1.6: Acknowledge Addressed Comments (Thumbs-Up)

When prior comments exist (re-review), check if the developer addressed previous bot review comments and acknowledge their replies with a 👍 reaction. This is a lightweight courtesy step that runs before launching subagents.

**When to run:** Only when Step 1.5 found prior bot comments (from "brave-core-bot" or containing "Review via brave-core-bot") AND the developer has pushed new commits since the bot's last review.

**How to detect and react:**

1. Fetch the bot's previous inline review comment IDs:
   ```bash
   gh api "repos/brave/brave-core/pulls/{number}/comments" --paginate \
     --jq '[.[] | select(.user.login == "brave-core-bot") | {id, body, created_at, path}]'
   ```

2. Fetch all review comments to find developer replies to those bot comments:
   ```bash
   gh api "repos/brave/brave-core/pulls/{number}/comments" --paginate \
     --jq '[.[] | select(.in_reply_to_id != null) | {id, user: .user.login, body, created_at, in_reply_to_id}]'
   ```

3. For each reply where:
   - `in_reply_to_id` matches a bot comment ID
   - The reply author is a Brave org member (typically the PR author)
   - New commits were pushed after the bot's review (the developer acted on the feedback)

   Add a 👍 reaction to the developer's reply:
   ```bash
   gh api "repos/brave/brave-core/pulls/comments/{reply_comment_id}/reactions" \
     --method POST -f content="+1"
   ```

4. Also check general issue comments — if the PR author posted a comment after the bot's review acknowledging the feedback (e.g., "Fixed", "Done", "Addressed", or describing what they changed), and new commits were pushed, thumbs-up that comment too:
   ```bash
   gh api "repos/brave/brave-core/issues/comments/{comment_id}/reactions" \
     --method POST -f content="+1"
   ```

**Important rules:**
- The reaction API is idempotent — if the bot already reacted, the API returns the existing reaction. No need to check for duplicates first.
- This step does NOT affect the review itself — it's purely an acknowledgment gesture before launching subagents.
- In auto mode, log each acknowledgment: `ACK: PR #<number> - 👍 comment by @<user> (addressed bot feedback)`
- Skip this step entirely if there are no prior bot comments or no new commits since the last review.

### Step 2: Launch Category Subagents in Parallel

Launch one **Task subagent** (subagent_type: "general-purpose") per applicable category. **Use multiple Task tool calls in a single message** so they run in parallel.

| Category | Doc(s) to read | Condition |
|----------|---------------|-----------|
| **coding-standards** | `coding-standards.md` | has_cpp_files |
| **architecture** | `architecture.md`, `documentation.md` | Always |
| **build-system** | `build-system.md` | has_build_files |
| **testing** | `testing-async.md`, `testing-javascript.md`, `testing-navigation.md`, `testing-isolation.md` | has_test_files |
| **chromium-src** | `chromium-src-overrides.md` | has_chromium_src |
| **frontend** | `frontend.md` | has_frontend_files |

All doc paths are under `./brave-core-bot/docs/best-practices/`.

**Always launch at minimum:** architecture (applies to all PRs — layering, dependency injection, factory patterns affect every change).

### Step 3: Subagent Prompt

Each subagent prompt MUST include:

1. **The PR number and repo** (`brave/brave-core`)
2. **Which best practice doc(s) to read** — only the ones for this category (paths above)
3. **Instructions to fetch the diff** via `gh pr diff --repo brave/brave-core {number}`
4. **The review rules** (copied into the subagent prompt):
   - Only flag violations in ADDED lines (+ lines), not existing code
   - Also flag bugs introduced by the change (e.g., missing string separators, duplicate DEPS entries, code inside wrong `#if` guard)
   - **Check surrounding context before making claims.** When a violation involves dependencies, includes, or patterns, read the full file context (e.g., the BUILD.gn deps list, existing includes in the file) to verify your claim is accurate. Do NOT claim a PR "adds a dependency" or "introduces a pattern" if it already existed before the PR.
   - **Only comment on things the PR author introduced.** If a dependency, pattern, or architectural issue already existed before this PR, do not flag it — even if it violates a best practice. The PR author is not responsible for pre-existing issues. Focus exclusively on what this PR changes or adds.
   - **Respect the intent of the PR.** If a PR is moving, renaming, or refactoring files, do not suggest restructuring dependencies, changing `public_deps` vs `deps`, or reorganizing code that was simply carried over from the old location. The author's goal is to preserve existing behavior, not to optimize the code they're moving. Only flag issues that are actual bugs introduced by the move (e.g., broken paths, missing deps that cause build failures), not "while you're here, you should also fix X" improvements.
   - Security-sensitive areas (wallet, crypto, sync, credentials) deserve extra scrutiny — type mismatches, truncation, and correctness issues should use stronger language
   - Do NOT flag: existing code the PR isn't changing, template functions defined in headers, simple inline getters in headers, style preferences not in the documented best practices
   - Comment style: short (1-3 sentences), targeted, acknowledge context. Use "nit:" for genuinely minor/stylistic issues (including missing comments/documentation and alphabetical ordering). Substantive issues (test reliability, correctness, banned APIs) should be direct without "nit:" prefix
5. **Best practice link requirement** — for each violation, the subagent MUST include a direct link to the specific rule heading in the best practices doc. The link format is:
   ```
   https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/<doc>.md#<heading-anchor>
   ```
   Where `<heading-anchor>` is the `##` heading converted to a GitHub anchor (lowercase, spaces to hyphens, special characters removed). For example, `## Don't Use rapidjson` becomes `#dont-use-rapidjson`.
6. **Prior comments context (re-review awareness)** — if prior comments exist from Step 1.5, include them in the subagent prompt with these rules:
   - **Do NOT re-raise issues that the author or a reviewer has already explained or justified.** If a prior comment thread shows the author explaining why a design choice was made (e.g., "only two subclasses will ever use this, both pass constants"), accept that explanation and do not flag the same issue again.
   - **Do NOT repeat your own previous comments.** If a comment from "brave-core-bot" or containing "Review via brave-core-bot" already raised the same point, skip it — even if the code hasn't changed. The author has already seen it.
   - **Do NOT flag new issues on re-review that were missed the first time.** If an issue existed in the code during the first review and was not caught, do not raise it on a subsequent review — unless it is a serious correctness or security concern. Flagging new nits or minor issues on re-review that the bot simply missed earlier is annoying to developers and should be avoided. Only flag issues on re-review if they were **introduced in commits since the last reviewed commit**.
   - **DO re-raise an issue only if:** (a) the author's explanation is factually incorrect or introduces a real risk, OR (b) new code in the latest diff introduces a new instance of the same problem that wasn't previously discussed.
   - When in doubt about whether an issue was addressed, err on the side of NOT re-raising it. Repeating resolved feedback is more disruptive than missing a marginal issue.
7. **The systematic audit requirement** (below)
8. **Required output format** (below)

### Step 4: Systematic Audit Requirement

**CRITICAL — this is what prevents the subagent from stopping after finding a few violations.**

The subagent MUST work through its best practice doc(s) **heading by heading**, checking every `##` rule against the diff. It must output an audit trail listing EVERY `##` heading with a verdict:

```
AUDIT:
PASS: ✅ Always Include What You Use (IWYU)
PASS: ✅ Use Positive Form for Booleans and Methods
N/A: ✅ Consistent Naming Across Layers
FAIL: ❌ Don't Use rapidjson
PASS: ✅ Use CHECK for Impossible Conditions
... (one entry per ## heading in the doc)
```

Verdicts:
- **PASS**: Checked the diff — no violation found
- **N/A**: Rule doesn't apply to the types of changes in this diff
- **FAIL**: Violation found — must have a corresponding entry in VIOLATIONS

This forces the model to explicitly consider every rule rather than satisficing after a few findings.

### Step 5: Required Output Format

Each subagent MUST return this structured format:

```
CATEGORY: <category name>
[PR #<number>](https://github.com/brave/brave-core/pull/<number>): <title>

AUDIT:
PASS: <rule heading>
N/A: <rule heading>
FAIL: <rule heading>
... (one line per ## heading in the doc(s))

SKIPPED_PRIOR:
- file: <path>, issue: <brief description>, reason: <why not re-raised — e.g., "author explained in prior comment that only constant strings are passed", "already flagged in previous review">
NONE (if no prior issues were skipped)

VIOLATIONS:
- file: <path>, line: <line_number>, rule: "<rule heading>", rule_link: <full GitHub URL to the rule heading>, issue: <brief description>, draft_comment: <1-3 sentence comment to post>
- ...
NO_VIOLATIONS (if none found)
```

The `SKIPPED_PRIOR` section provides transparency about issues that were intentionally not re-raised due to prior discussion. This helps the operator verify the subagent correctly handled prior context.

### Step 6: Aggregate and Process Results

Process PRs **one at a time** (sequentially). After ALL category subagents return for a PR:

1. **Update the cache immediately** — run the cache update script right now, before doing anything else:
   ```bash
   python3 .claude/skills/review-prs/update-cache.py <PR_NUMBER> <HEAD_REF_OID>
   ```
   **This step is MANDATORY after every single PR review — regardless of outcome.** Update the cache even when:
   - No violations were found (all categories returned NO_VIOLATIONS)
   - All violations were skipped due to re-review restraint (all SKIPPED_PRIOR)
   - The user rejects all comments in interactive mode
   - Comments fail to post due to API errors

   The cache tracks "we reviewed this SHA", not "we posted comments". Skipping this causes the same PR to be re-reviewed on the next run, wasting time and risking duplicate comments.
2. **Aggregate violations** from all category subagents into a single list for the PR
3. **If AUTO_MODE**: post all violations immediately using the inline review API (see Auto Posting below), then move to the next PR
4. **If interactive mode**: present violations to the user for approval before moving to the next PR
5. If no violations across all categories, briefly note that and move on

**PR Link Format:** When displaying PR numbers to the user, always use a proper markdown link: `[PR #<number>](https://github.com/brave/brave-core/pull/<number>) - <title>`. Never use bare `#<number>` references — they don't produce clickable links to the correct PR.

---

## Comment Style

- **Short and succinct** - 1-3 sentences max
- **Targeted** - reference specific files and code
- **Acknowledge context** - if upstream does the same thing, say so
- **No lecturing** - state the issue briefly
- **Link to the rule** - when the violation is an explicit best practice rule, append a link to the specific rule at the end of the comment. Example: `[best practice](https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/coding-standards.md#dont-use-rapidjson)`. Only include the link for explicit documented rule violations, not for general bug/correctness observations.
- **Match tone to severity:**
  - **Genuine nits** (style, naming, minor cleanup, missing comments/documentation, alphabetical ordering): use "nit:" prefix, "worth considering", "not blocking either way"
  - **Substantive issues** (test reliability, correctness, banned APIs, potential bugs): be direct and clear about why it needs to change. Do NOT use "nit:" for these — a `RunUntilIdle()` violation or a banned API usage is not a nit, it's a real problem.

---

## Interactive Posting

For each violation, present the draft and ask:

> **[PR #12345](https://github.com/brave/brave-core/pull/12345)** - `file:line` - [violation description]
> Draft: `[short comment]`
> Post this comment?

Use "nit:" prefix for genuinely minor/stylistic issues (missing comments/documentation, alphabetical ordering, naming, minor cleanup), not for substantive concerns.

**The "Review via brave-core-bot" attribution MUST appear exactly once per review** — on the top-level review body, NOT on each inline comment. Individual inline comments should contain only the comment text itself.

### Posting as Inline Code Comments

After presenting all violations for a PR, collect the approved ones and post them as a **single review with inline comments** using the GitHub API. This places comments directly on the relevant code lines instead of as a general review comment.

```bash
gh api repos/brave/brave-core/pulls/{number}/reviews \
  --method POST \
  --input - <<'EOF'
{
  "event": "COMMENT",
  "body": "Review via brave-core-bot",
  "comments": [
    {
      "path": "path/to/file.cc",
      "line": 42,
      "side": "RIGHT",
      "body": "comment text. [best practice](https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/coding-standards.md#rule-anchor)"
    },
    {
      "path": "path/to/other_file.cc",
      "line": 15,
      "side": "RIGHT",
      "body": "another comment. [best practice](https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/testing-async.md#rule-anchor)"
    }
  ]
}
EOF
```

**Key details:**
- The `"body": "Review via brave-core-bot"` at the top level provides the attribution once for the entire review
- Individual comment bodies should NOT include the "Review via brave-core-bot: " prefix
- `side: "RIGHT"` targets the new version of the file (added lines)
- `line` is the line number in the new file, which matches what the subagent reports from `+` lines in the diff
- All approved violations for a single PR are batched into one review (one notification to the author)
- If the API call fails (e.g., a line is outside the diff range), retry by splitting: post the valid inline comments and fall back to a general review comment for any that failed. **Only the fallback general comment needs the prefix** since it's standalone:
  ```bash
  gh pr review --repo brave/brave-core {number} --comment --body "Review via brave-core-bot: [file:line] comment text"
  ```

---

## Auto Posting

When `AUTO_MODE=true`, skip all interactive approval and post violations directly.

**Auto mode does NOT ask any questions** — no `AskUserQuestion` calls, no confirmation prompts. This is critical for headless/cron operation.

### Per-PR Logging (MANDATORY)

After processing each PR, you MUST print a structured log line to stdout. This is the **only** record of what the cron job did — if you skip this, the cron log will be empty and useless.

**If violations were posted**, capture the review URL from the `gh api` response (the `html_url` field) and log:
```
AUTO: PR #<number> (<title>) - posted <N> comments - <review_url>
  - <file>:<line> (<rule name>)
  - <file>:<line> (<rule name>)
```

**If no violations found:**
```
AUTO: PR #<number> (<title>) - no violations
```

**If the PR was skipped (error fetching diff, etc.):**
```
AUTO: PR #<number> (<title>) - SKIPPED: <reason>
```

### Capturing the Review URL

When posting violations via `gh api repos/brave/brave-core/pulls/{number}/reviews`, the response JSON contains `html_url` — the direct link to the review on GitHub. You MUST capture this and include it in the log line. Example:
```bash
REVIEW_RESPONSE=$(gh api repos/brave/brave-core/pulls/{number}/reviews \
  --method POST --input - <<'EOF'
{ ... }
EOF
)
REVIEW_URL=$(echo "$REVIEW_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['html_url'])")
```

### Posting Flow

**Before any posting logic**, update the cache for this PR (see Step 6 in Per-Category Review Workflow). The cache must be updated even if there are no violations or all violations were skipped.

1. Collect all violations from all category subagents for the PR
2. If violations exist, post them as a **single inline review** using the same `gh api` call as interactive mode (see "Posting as Inline Code Comments" above)
3. Capture the `html_url` from the API response
4. Print the per-PR log line (see format above)
5. If the inline review API call fails, fall back to general review comments (same fallback as interactive mode)
6. If no violations, print the per-PR log line and move on

### Final Summary (MANDATORY)

After ALL PRs have been processed, you MUST print a final summary block. This is the last thing you output:

```
========================================
AUTO REVIEW SUMMARY
Date: <current date/time>
PRs reviewed: <N>
PRs with violations: <N>
Total comments posted: <N>

RESULTS:
  ✅ PR #<number> (<title>) - no violations
  ❌ PR #<number> (<title>) - <N> comments - <review_url>
  ⏭️ PR #<number> (<title>) - SKIPPED: <reason>
========================================
```

**This summary block is CRITICAL for cron log readability.** Do not skip it. Do not summarize with vague language like "All done" — list every PR explicitly.

---

## Closed/Merged PR Workflow

When reviewing closed or merged PRs and a violation is found:

1. **Present the finding** to the user as usual (draft comment + ask for approval)
2. **If approved**, try to post inline review comments using the same `gh api` approach as open PRs. If the inline API fails (some merged PRs may not support it), fall back to a general comment:
   ```bash
   gh pr comment --repo brave/brave-core {number} --body "Review via brave-core-bot: [file:line] comment text"
   ```
3. **Create a follow-up issue** in `brave/brave-core` to track the fix:
   ```bash
   gh issue create --repo brave/brave-core --title "Fix: <brief description of violation>" --body "$(cat <<'EOF'
   Found during post-merge review of #<PR_NUMBER>.

   <description of the violation and what needs to change>

   See: https://github.com/brave/brave-core/pull/<PR_NUMBER>
   EOF
   )"
   ```
4. **Reference the new issue** back in the PR comment so the PR author can find it:
   ```bash
   gh pr comment --repo brave/brave-core <PR_NUMBER> --body "Created follow-up issue #<ISSUE_NUMBER> to track this."
   ```

This ensures violations on already-merged code don't get lost — they get tracked as actionable issues.
