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

**IMPORTANT:** This skill only reviews PRs against existing best practices. It must NEVER create, modify, or add new best practice rules or documentation during a review run. Pattern extraction belongs to the `/learnable-pattern-search` skill, which has its own quality gates.

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
     "prs": [{"number": 42001, "title": "...", "headRefOid": "abc123", "author": "user", "hasApproval": false}],
     "cached_prs": [{"number": 42002, "title": "...", "headRefOid": "def456", "author": "user", "hasApproval": true}],
     "summary": {"total_fetched": 50, "to_review": 5, "cached_with_possible_threads": 8, "skipped_filtered": 30, "skipped_cached": 7, "skipped_approved": 3}
   }
   ```
   - **`prs`**: PRs with new commits that need full review
   - **`cached_prs`**: PRs with same SHA as last review but may have unresolved bot threads needing resolution
   - **`skipped_approved`**: PRs the bot previously approved — completely skipped (won't haunt devs)
2. **Print progress summary** from the summary stats (this goes to stdout and will appear in cron logs):
   ```
   Found N PRs to review, C cached PRs to check for thread resolution (M skipped: X drafts/filtered, Y cached, Z approved)
   PRs to review: [PR #12345](https://github.com/brave/brave-core/pull/12345) (title), [PR #12346](https://github.com/brave/brave-core/pull/12346) (title), ...
   Cached PRs for thread resolution: [PR #12347](https://github.com/brave/brave-core/pull/12347), ...
   ```
3. **Review each PR** (from the `prs` array) one at a time using per-document parallel subagents (see Per-Document Review Workflow below)
4. **Aggregate and present findings** from all document subagents
5. **Update the cache for EVERY reviewed PR** — this is mandatory regardless of whether violations were found, comments were posted, or comments were skipped. See Step 6 in Per-Category Review Workflow.
6. **If AUTO_MODE**: post all violations immediately and log each result (see Auto Posting below — the per-PR logging and final summary are MANDATORY). **Otherwise**: draft each comment and ask user to approve before posting
7. **Process cached PRs for thread resolution** — for each PR in the `cached_prs` array, run ONLY Step 1.6 (Acknowledge and Resolve) and Step 1.7 (Approve if settled). Do NOT launch subagents or do full reviews — these PRs have already been reviewed at the current SHA

**NEVER post internal working output to GitHub.** Subagent AUDIT trails, SKIPPED_PRIOR sections, DOCUMENT headers, violation summaries, and category labels are internal-only. The only things that appear on GitHub are short inline comment text from each violation's `draft_comment`. Nothing else.

---

## Per-Document Review Workflow

**IMPORTANT:** The main context does NOT load best practices docs or PR diffs. Each PR is reviewed by multiple focused subagents — one per best-practice document — running in parallel. This ensures every rule is systematically checked rather than relying on a single subagent to hold many rules in mind.

### Step 0: Resolve Bot Username

Before processing any PRs, resolve the bot's GitHub username dynamically. Do NOT hardcode a username — different operators may run this skill under different GitHub accounts.

```bash
BOT_USERNAME=$(gh api user --jq '.login')
```

Use `$BOT_USERNAME` in ALL subsequent jq queries and comparisons that need to identify the bot's own comments. This variable is referenced throughout Steps 1.5, 1.6, 1.7, and the deduplication logic.

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
- **has_nala_files**: files matching `*/res/drawable/*`, `*/res/values/*`, or `*/res/values-night/*`, paths `components/vector_icons/`, `.icon` files, or `.svg` files

### Step 1.5: Fetch Existing PR Comments (Re-review Context)

Before launching subagents, fetch all existing review comments and discussion on the PR using the filter script:

```bash
./brave-core-bot/scripts/filter-pr-reviews.sh {number} markdown
```

This returns all past review comments, inline code comments, and discussion comments from Brave org members (filtered for security). Pass this output to each subagent as `PRIOR_COMMENTS` context (see Step 3).

**Why this matters:** When re-reviewing a PR after new commits, the bot must be aware of:
- Its own previous comments (identified by `$BOT_USERNAME` from Step 0) to avoid repeating the same feedback
- Author and reviewer responses that explain or justify a design choice
- Issues that were already acknowledged and addressed

If there are no prior comments (first review), skip this step and omit the prior comments section from the subagent prompt.

### Step 1.6: Acknowledge and Resolve Addressed Comments

When prior comments exist (re-review), check if the developer addressed previous bot review comments. For each addressed comment: add a 👍 reaction to the developer's reply AND resolve the review thread. This is a lightweight courtesy step that runs before launching subagents.

**When to run:** Only when Step 1.5 found prior bot comments (from `$BOT_USERNAME`) AND the developer has pushed new commits or replied since the bot's last review.

**How to detect and act:**

Run the resolve script to atomically handle all bot thread resolution:
```bash
python3 ./brave-core-bot/scripts/resolve-bot-threads.py {number} "$BOT_USERNAME"
```

The script fetches bot comments, finds developer replies, adds 👍 reactions, and resolves threads in a single deterministic pass. It outputs JSON:
```json
{
  "resolved": [{"botCommentId": 123, "threadId": "...", "replyId": 456, "replyUser": "dev"}],
  "already_resolved": [...],
  "no_reply": [...],
  "unresolved_bot_threads": 2,
  "total_bot_threads": 10
}
```

Use `--dry-run` to preview what would be done without making changes.

**Decision override:** Before running the script, briefly review the developer's replies (from Step 1.5 context). If any reply reveals a misunderstanding that could lead to a real bug or security issue, exclude that thread by resolving it manually after posting a follow-up reply. This should be rare — the default is to resolve.

Also check general issue comments — if the PR author posted a comment after the bot's review acknowledging the feedback (e.g., "Fixed", "Done", "Addressed", or describing what they changed), and new commits were pushed, thumbs-up that comment too:
```bash
gh api "repos/brave/brave-core/issues/comments/{comment_id}/reactions" \
  --method POST -f content="+1"
```

**Important rules:**
- The reaction and resolve APIs are idempotent — no need to check for duplicates first.
- This step does NOT re-post any comments. It only reacts and resolves. **NEVER re-post the same feedback when resolving.**
- In auto mode, log the script output: `ACK: [PR #<number>](https://github.com/brave/brave-core/pull/<number>) - resolved N threads, M remaining unresolved`
- Skip this step entirely if there are no prior bot comments or no new commits/replies since the last review.

### Step 1.7: Approve if Settled (No Remaining Unresolved Threads)

After Step 1.6 resolves addressed comments, check if the bot has any remaining unresolved threads on the PR. If ALL bot threads are now resolved (none left open) AND at least one bot thread existed (i.e., the bot previously left feedback), submit an APPROVE review and mark the PR as settled in the cache.

**When to approve:**
1. The bot previously left review comments on this PR (at least one thread existed)
2. All bot threads are now resolved (after Step 1.6 processing)
3. The bot has not already approved this SHA (check before posting)

**How to check remaining unresolved bot threads:**

Use the JSON output from the Step 1.6 resolve script. The `unresolved_bot_threads` and `total_bot_threads` fields tell you directly whether all bot threads are resolved.

If `unresolved_bot_threads` is 0 AND `total_bot_threads` > 0:

**Submit APPROVE review:**
```bash
gh api repos/brave/brave-core/pulls/{number}/reviews \
  --method POST \
  --input - <<'EOF'
{
  "event": "APPROVE",
  "body": ""
}
EOF
```

**Mark as approved in cache** (prevents the bot from coming back on future runs):
```bash
python3 .claude/skills/review-prs/update-cache.py <PR_NUMBER> <HEAD_REF_OID> --approve
```

**When NOT to approve:**
- If there are still unresolved bot threads (the developer hasn't addressed all feedback yet)
- If the bot never left any comments on this PR (nothing to settle — don't approve a PR you never reviewed)
- If Step 2 (full review) is about to run and may find new violations — for full reviews, defer approval to Step 6 after aggregation

**Don't Haunt Developers:** Once the bot approves a PR, it is marked as settled in the cache. Future runs will completely skip this PR — no re-reviews, no comment checks, nothing. The bot has said its piece and moved on. The only way to re-review an approved PR is to explicitly request it with `#<PR_NUMBER>`.

**Auto mode logging:**
```
APPROVE: [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - all threads resolved, approved
```

### Step 2: Launch Document Subagents in Parallel

Launch one **Task subagent** (subagent_type: "general-purpose") per applicable best-practice document. **Use multiple Task tool calls in a single message** so they run in parallel.

| Document | Doc to read | Condition |
|----------|-------------|-----------|
| **coding-standards** | `coding-standards.md` | has_cpp_files |
| **coding-standards-memory** | `coding-standards-memory.md` | has_cpp_files |
| **coding-standards-apis** | `coding-standards-apis.md` | has_cpp_files |
| **architecture** | `architecture.md` | Always |
| **documentation** | `documentation.md` | Always |
| **build-system** | `build-system.md` | has_build_files |
| **testing-async** | `testing-async.md` | has_test_files |
| **testing-javascript** | `testing-javascript.md` | has_test_files |
| **testing-navigation** | `testing-navigation.md` | has_test_files |
| **testing-isolation** | `testing-isolation.md` | has_test_files |
| **chromium-src** | `chromium-src-overrides.md` | has_chromium_src |
| **frontend** | `frontend.md` | has_frontend_files |
| **nala** | `nala.md` | has_nala_files |

All doc paths are under `./brave-core-bot/docs/best-practices/`.

**Always launch at minimum:** architecture and documentation (apply to all PRs — layering, dependency injection, factory patterns, and documentation standards affect every change).

### Step 3: Subagent Prompt

Each subagent prompt MUST include:

1. **The PR number and repo** (`brave/brave-core`)
2. **Which best practice doc to read** — only the one for this subagent (paths above)
3. **Instructions to fetch the diff** via `gh pr diff --repo brave/brave-core {number}`
4. **The review rules** (copied into the subagent prompt):
   - Only flag violations in ADDED lines (+ lines), not existing code
   - Also flag bugs introduced by the change (e.g., missing string separators, duplicate DEPS entries, code inside wrong `#if` guard)
   - **Check surrounding context before making claims.** When a violation involves dependencies, includes, or patterns, read the full file context (e.g., the BUILD.gn deps list, existing includes in the file) to verify your claim is accurate. Do NOT claim a PR "adds a dependency" or "introduces a pattern" if it already existed before the PR.
   - **Only comment on things the PR author introduced.** If a dependency, pattern, or architectural issue already existed before this PR, do not flag it — even if it violates a best practice. The PR author is not responsible for pre-existing issues. Focus exclusively on what this PR changes or adds.
   - **Respect the intent of the PR.** If a PR is moving, renaming, or refactoring files, do not suggest restructuring dependencies, changing `public_deps` vs `deps`, or reorganizing code that was simply carried over from the old location. The author's goal is to preserve existing behavior, not to optimize the code they're moving. Only flag issues that are actual bugs introduced by the move (e.g., broken paths, missing deps that cause build failures), not "while you're here, you should also fix X" improvements.
   - Security-sensitive areas (wallet, crypto, sync, credentials) deserve extra scrutiny — type mismatches, truncation, and correctness issues should use stronger language
   - Do NOT flag: existing code the PR isn't changing, template functions defined in headers, simple inline getters in headers, style preferences not in the documented best practices, **include/import ordering** (this is handled by formatting tools and linters, not this bot)
   - Comment style: short (1-3 sentences), targeted, acknowledge context. Use "nit:" for genuinely minor/stylistic issues (including missing comments/documentation). Substantive issues (test reliability, correctness, banned APIs) should be direct without "nit:" prefix
5. **Best practice link requirement** — each rule in the best practices docs has a stable ID anchor (e.g., `<a id="CS-001"></a>`) on the line before the heading. For each violation, the subagent MUST include a direct link using that ID. The link format is:
   ```
   https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/<doc>.md#<ID>
   ```
   For example, if the heading has `<a id="CS-042"></a>` above it, the link is `...coding-standards.md#CS-042`.

   **CRITICAL: The `rule_link` fragment MUST be an exact `<a id="...">` value from the document you read.** Look for the `<a id="..."></a>` tag on the line before the heading you're referencing and use that ID verbatim. Do NOT invent IDs, guess ID numbers, or construct anchors from heading text. If no `<a id>` tag exists for the rule, or if your observation is a general bug/correctness issue that doesn't map to any specific heading, omit the `rule_link` field entirely.

   **CRITICAL: Do NOT invent rules that contradict documented best practices.** If the best practices doc says "bump by 5", you must NOT suggest the opposite. If you're unsure whether a rule exists, read the actual document — do not guess or reconstruct rules from memory. A hallucinated rule that contradicts a real rule is worse than no comment at all.
6. **Prior comments context (re-review awareness)** — if prior comments exist from Step 1.5, include them in the subagent prompt with these rules:
   - **Do NOT re-raise issues that the author or a reviewer has already explained or justified.** If a prior comment thread shows the author explaining why a design choice was made (e.g., "only two subclasses will ever use this, both pass constants"), accept that explanation and do not flag the same issue again.
   - **Do NOT repeat your own previous comments.** If a comment from the bot (identified by `$BOT_USERNAME` from Step 0) already raised the same point, skip it — even if the code hasn't changed. The author has already seen it.
   - **Do NOT flag new issues on re-review that were missed the first time.** If an issue existed in the code during the first review and was not caught, do not raise it on a subsequent review — unless it is a serious correctness or security concern. Flagging new nits or minor issues on re-review that the bot simply missed earlier is annoying to developers and should be avoided. Only flag issues on re-review if they were **introduced in commits since the last reviewed commit**.
   - **DO re-raise an issue only if:** (a) the author's explanation is factually incorrect or introduces a real risk, OR (b) new code in the latest diff introduces a new instance of the same problem that wasn't previously discussed.
   - When in doubt about whether an issue was addressed, err on the side of NOT re-raising it. Repeating resolved feedback is more disruptive than missing a marginal issue.
7. **The systematic audit requirement** (below)
8. **Required output format** (below)

### Step 4: Systematic Audit Requirement

**CRITICAL — this is what prevents the subagent from stopping after finding a few violations.**

The subagent MUST work through its best practice doc **heading by heading**, checking every `##` rule against the diff. It must output an audit trail listing EVERY `##` heading with a verdict:

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
DOCUMENT: <document name>
[PR #<number>](https://github.com/brave/brave-core/pull/<number>): <title>

AUDIT:
PASS: <rule heading>
N/A: <rule heading>
FAIL: <rule heading>
... (one line per ## heading in the doc)

SKIPPED_PRIOR:
- file: <path>, issue: <brief description>, reason: <why not re-raised — e.g., "author explained in prior comment that only constant strings are passed", "already flagged in previous review">
NONE (if no prior issues were skipped)

VIOLATIONS:
- file: <path>, line: <line_number>, severity: <"high"|"medium"|"low">, rule: "<rule heading>", rule_link: <full GitHub URL to the rule heading>, issue: <brief description>, draft_comment: <1-3 sentence comment to post>
- ...
NO_VIOLATIONS (if none found)

Severity guide:
- **high**: Correctness bugs, use-after-free, security issues, banned APIs, test reliability problems (e.g., RunUntilIdle)
- **medium**: Substantive best practice violations (wrong container type, missing error handling, architectural issues)
- **low**: Nits, style preferences, missing docs, naming suggestions, minor cleanup
```

The `SKIPPED_PRIOR` section provides transparency about issues that were intentionally not re-raised due to prior discussion. This helps the operator verify the subagent correctly handled prior context.

### Step 6: Aggregate and Process Results

Process PRs **one at a time** (sequentially). After ALL document subagents return for a PR:

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
2. **Aggregate and prioritize violations** from all document subagents into a single list for the PR. **CRITICAL: Only extract the VIOLATIONS entries from subagent output.** The AUDIT trail, SKIPPED_PRIOR section, DOCUMENT header, and any other subagent working output are internal-only — they must NEVER appear in any GitHub review body, inline comment, or PR comment. Only the `draft_comment` text from each violation is posted.

   **Prioritization and cap (IMPORTANT):** Sort violations by severity: high → medium → low. Then apply these rules:
   - **Post at most 5 comments per PR.** Developers get overwhelmed by walls of review comments. Focus on what matters most.
   - **Always include all high-severity violations** (correctness, security, banned APIs) — these are non-negotiable.
   - **Fill remaining slots with medium-severity violations.**
   - **Only include low-severity (nits) if there are fewer than 3 higher-severity comments.** If there are already 3+ substantive comments, drop all nits — the developer has enough to focus on.
   - If there are more than 5 high+medium violations, cap at the 5 most impactful ones and note in the log how many were dropped.
   - **When in doubt, don't comment.** A review with 2 important comments is far more useful than one with 10 mixed-importance comments.
   - **Approved PRs — high-severity only.** If the PR's `hasApproval` field is `true` (meaning at least one reviewer has approved), drop ALL medium and low severity violations. Only post high-severity issues (correctness bugs, security vulnerabilities, banned APIs). A human reviewer already approved the PR, so the bot should only intervene for serious problems.
3. **Validate rule links** — for each violation with a `rule_link`, extract the fragment ID and validate it exists in the target doc:
   ```bash
   python3 ./brave-core-bot/scripts/manage-bp-ids.py --check-link <ID> --doc <doc>.md
   ```
   If the ID is invalid (exit code 1), strip the `[best practice](...)` link from the `draft_comment` text before posting. Log: `INVALID_LINK: stripped broken link #<ID> from <file>:<line>`. The comment text itself is still posted — only the broken link is removed.

   **Violations missing `rule_link` must be dropped.** Every comment the bot posts must cite a specific best practice rule so developers can understand the basis and push back if needed. If a subagent returns a violation without a `rule_link`, do NOT post it — log: `DROPPED: no rule_link for <file>:<line> — "<draft_comment snippet>"`. General observations that don't map to a documented rule should not be posted as review comments.
4. **If AUTO_MODE**: post the prioritized violations using the inline review API (see Auto Posting below), then move to the next PR
5. **If interactive mode**: present the prioritized violations to the user for approval before moving to the next PR
6. **If no violations across all categories AND all prior bot threads were resolved in Step 1.6**: submit an APPROVE review and mark as settled using `--approve` (see Step 1.7). This completes the bot's engagement with this PR — future runs will skip it entirely. Log: `APPROVE: [PR #<number>](...) - no violations, approved`
7. **If violations were posted**: do NOT approve. The bot will re-check this PR on the next run after the developer addresses the feedback

**PR Link Format (CRITICAL):** When displaying PR numbers to the user, ALWAYS use a full markdown link with the `brave/brave-core` URL: `[PR #<number>](https://github.com/brave/brave-core/pull/<number>) - <title>`. **NEVER use bare `#<number>` references** — the TUI auto-links them against the current repo's git remote (`brave-experiments/brave-core-bot`), sending users to the wrong repository. Every single PR number shown to the user must be a full `https://github.com/brave/brave-core/pull/` link.

---

## Comment Style

- **Short and succinct** - 1-3 sentences max
- **Targeted** - reference specific files and code
- **Acknowledge context** - if upstream does the same thing, say so
- **No lecturing** - state the issue briefly
- **Link to the rule** - when the violation is an explicit best practice rule, append a link using the rule's stable ID anchor at the end of the comment. Example: `[best practice](https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/coding-standards.md#CS-042)`. Only include the link for explicit documented rule violations, not for general bug/correctness observations.
- **Match tone to severity:**
  - **Genuine nits** (style, naming, minor cleanup, missing comments/documentation): use "nit:" prefix, "worth considering", "not blocking either way"
  - **Substantive issues** (test reliability, correctness, banned APIs, potential bugs): be direct and clear about why it needs to change. Do NOT use "nit:" for these — a `RunUntilIdle()` violation or a banned API usage is not a nit, it's a real problem.

---

## Interactive Posting

For each violation, present the draft and ask:

> **[PR #12345](https://github.com/brave/brave-core/pull/12345)** - `file:line` - [violation description]
> Draft: `[short comment]`
> Post this comment?

Use "nit:" prefix for genuinely minor/stylistic issues (missing comments/documentation, naming, minor cleanup), not for substantive concerns.

### Deduplication Before Posting (applies to BOTH interactive and auto mode)

Before presenting violations to the user (interactive) or posting them (auto), you MUST programmatically deduplicate against existing bot comments. This prevents the bot from re-posting the same comment when a PR is reviewed multiple times.

```bash
gh api "repos/brave/brave-core/pulls/{number}/comments" --paginate \
  --jq '[.[] | select(.user.login == "$BOT_USERNAME") | {path, line, body}]'
```

For each violation, if an existing bot comment exists on the **same file path AND same line number**, drop the violation. Do not re-post it even if the wording differs slightly — a comment on the same file+line means the issue was already raised. Log each: `DEDUP: skipped <file>:<line> — bot already commented`.

This is a **hard programmatic check** — it overrides subagent output. Even if a subagent reports a violation, if the bot already commented on that file+line, it must be dropped.

### Posting as Inline Code Comments

After deduplication, collect the remaining approved violations (interactive) or all remaining violations (auto) and post them as a **single review with inline comments** using the GitHub API. This places comments directly on the relevant code lines instead of as a general review comment.

```bash
gh api repos/brave/brave-core/pulls/{number}/reviews \
  --method POST \
  --input - <<'EOF'
{
  "event": "COMMENT",
  "body": "",
  "comments": [
    {
      "path": "path/to/file.cc",
      "line": 42,
      "side": "RIGHT",
      "body": "comment text. [best practice](https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/coding-standards.md#CS-042)"
    },
    {
      "path": "path/to/other_file.cc",
      "line": 15,
      "side": "RIGHT",
      "body": "another comment. [best practice](https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/testing-async.md#TA-005)"
    }
  ]
}
EOF
```

**Key details:**
- The `"body"` field at the top level MUST be an empty string `""`. **NEVER put subagent output, audit trails, violation summaries, attribution text, or any other text in the review body.** The review body is visible on GitHub as a prominent block of text. Only inline comment bodies carry the actual review content.
- `side: "RIGHT"` targets the new version of the file (added lines)
- `line` is the line number in the new file, which matches what the subagent reports from `+` lines in the diff
- All approved violations for a single PR are batched into one review (one notification to the author)
- If the API call fails (e.g., a line is outside the diff range), retry by splitting: post the valid inline comments and fall back to a general review comment for any that failed:
  ```bash
  gh pr review --repo brave/brave-core {number} --comment --body "[file:line] comment text"
  ```

---

## Cached PR Comment Resolution

After processing all full reviews (the `prs` array), process each PR in the `cached_prs` array. These PRs have already been reviewed at the current SHA but may have unresolved bot comment threads that need attention.

**For each cached PR, run ONLY these steps:**

1. **Step 1.6** (Acknowledge and Resolve Addressed Comments) — check for developer replies/fixes and resolve addressed threads
2. **Step 1.7** (Approve if Settled) — if all bot threads are now resolved, submit APPROVE and mark `--approve` in cache

**Do NOT launch subagents or run a full review** — the code hasn't changed since the last review. The only purpose is housekeeping: resolving addressed threads and approving when the developer has addressed all feedback.

**Skip a cached PR entirely if:**
- No bot comments exist on the PR (nothing to resolve)
- No new replies or issue comments since the last review

**Auto mode logging for cached PRs:**
```
CACHED: [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - resolved N threads, M remaining
APPROVE: [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - all threads resolved, approved
```
or if nothing to do:
```
CACHED: [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - no unresolved bot threads
```

Include cached PRs in the final summary with a distinct marker:
```
  🔄 [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - resolved N threads, approved
  🔄 [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - M threads still unresolved
```

---

## Auto Posting

When `AUTO_MODE=true`, skip all interactive approval and post violations directly.

**Auto mode does NOT ask any questions** — no `AskUserQuestion` calls, no confirmation prompts. This is critical for headless/cron operation.

### Per-PR Logging (MANDATORY)

After processing each PR, you MUST print a structured log line to stdout. This is the **only** record of what the cron job did — if you skip this, the cron log will be empty and useless.

**If violations were posted**, capture the review URL from the `gh api` response (the `html_url` field) and log:
```
AUTO: [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - posted <N> comments - <review_url>
  - <file>:<line> (<rule name>)
  - <file>:<line> (<rule name>)
```

**If no violations found:**
```
AUTO: [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - no violations
```

**If the PR was skipped (error fetching diff, etc.):**
```
AUTO: [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - SKIPPED: <reason>
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

1. Collect all violations from all document subagents for the PR
2. **Deduplicate against existing bot comments (MANDATORY)** — before posting, fetch all existing bot comments on the PR and drop any violation that the bot already commented on:
   ```bash
   gh api "repos/brave/brave-core/pulls/{number}/comments" --paginate \
     --jq '[.[] | select(.user.login == "$BOT_USERNAME") | {path, line, body}]'
   ```
   For each violation, check if an existing bot comment matches the **same file path AND same line number**. If a match exists, **drop the violation** — do not re-post it regardless of whether the wording differs. This is a hard programmatic check that cannot be overridden by subagent output.
   Log each dropped duplicate: `DEDUP: skipped <file>:<line> — bot already commented`
3. If violations remain after dedup, post them as a **single inline review** using the same `gh api` call as interactive mode (see "Posting as Inline Code Comments" above)
4. Capture the `html_url` from the API response
5. Print the per-PR log line (see format above)
6. If the inline review API call fails, fall back to general review comments (same fallback as interactive mode)
7. If no violations (or all were deduped), print the per-PR log line and move on

### Final Summary (MANDATORY)

After ALL PRs have been processed, you MUST print a final summary block. This is the last thing you output:

```
========================================
AUTO REVIEW SUMMARY
Date: <current date/time>
PRs reviewed: <N>
PRs with violations: <N>
Total comments posted: <N>
Cached PRs processed: <N>
PRs approved: <N>

RESULTS:
  ✅ [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - no violations, approved
  ❌ [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - <N> comments - <review_url>
  ⏭️ [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - SKIPPED: <reason>
  🔄 [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - resolved N threads, approved
  🔄 [PR #<number>](https://github.com/brave/brave-core/pull/<number>) (<title>) - M threads still unresolved
========================================
```

**This summary block is CRITICAL for cron log readability.** Do not skip it. Do not summarize with vague language like "All done" — list every PR explicitly.

### Signal Notification (after final summary)

After printing the final summary, send a Signal notification with a concise summary:

```bash
./brave-core-bot/scripts/signal-notify.sh "Review complete: <N> PRs reviewed, <M> with violations, <T> comments posted"
```

This is a no-op if Signal is not configured.

---

## Closed/Merged PR Workflow

When reviewing closed or merged PRs and a violation is found:

1. **Present the finding** to the user as usual (draft comment + ask for approval)
2. **If approved**, try to post inline review comments using the same `gh api` approach as open PRs. If the inline API fails (some merged PRs may not support it), fall back to a general comment:
   ```bash
   gh pr comment --repo brave/brave-core {number} --body "[file:line] comment text"
   ```
3. **Create a follow-up issue** in `brave/brave-core` to track the fix:
   ```bash
   gh issue create --repo brave/brave-core --title "Fix: <brief description of violation>" --body "$(cat <<'EOF'
   Found during post-merge review of [PR #<PR_NUMBER>](https://github.com/brave/brave-core/pull/<PR_NUMBER>).

   <description of the violation and what needs to change>

   See: https://github.com/brave/brave-core/pull/<PR_NUMBER>
   EOF
   )"
   ```
4. **Reference the new issue** back in the PR comment so the PR author can find it:
   ```bash
   gh pr comment --repo brave/brave-core <PR_NUMBER> --body "Created follow-up issue https://github.com/brave/brave-core/issues/<ISSUE_NUMBER> to track this."
   ```

This ensures violations on already-merged code don't get lost — they get tracked as actionable issues.
