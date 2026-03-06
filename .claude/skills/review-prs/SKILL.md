---
name: review-prs
description: "Review PRs in the configured PR repository for best practices violations. Supports single PR (#12345), state filter (open/closed/all), and auto mode for cron. Triggers on: review prs, review recent prs, /review-prs, check prs for best practices."
argument-hint: "[days|page<N>|#<PR>] [open|closed|all] [auto] [reviewer-priority]"
allowed-tools: Bash(gh pr diff:*)
---

# Review PRs for Best Practices

Scan recent open PRs in the configured PR repository (from `config.json` → `project.prRepository`) for violations of documented best practices.

- **Interactive mode** (default): drafts comments and asks for user approval before posting.
- **Auto mode** (`auto` argument): posts all violations automatically without approval. Designed for cron/headless use.

**IMPORTANT:** This skill only reviews PRs against existing best practices. It must NEVER create, modify, or add new best practice rules or documentation during a review run. Pattern extraction belongs to the `/learnable-pattern-search` skill, which has its own quality gates.

---

## The Job

When invoked with `/review-prs [days|page<N>|#<PR>] [open|closed|all] [auto] [reviewer-priority]`:

**Detect auto mode:** If the arguments contain `auto`, set `AUTO_MODE=true`. In auto mode, all violations are posted without asking for user approval. Strip `auto` from arguments before passing to the fetch script.

**Detect reviewer-priority mode:** If the arguments contain `reviewer-priority`, set `REVIEWER_PRIORITY=true`. Strip `reviewer-priority` from arguments before passing to the fetch script. When enabled, pass `--reviewer-priority $BOT_USERNAME` to the fetch script (after resolving `$BOT_USERNAME` in Step 0). This sorts PRs so those where the bot user is assigned as a reviewer are processed first.

1. **Fetch and filter PRs** by running the fetch script (pass through all arguments except `auto` and `reviewer-priority`, and append `--reviewer-priority $BOT_USERNAME` if `REVIEWER_PRIORITY` is set):
   ```bash
   python3 .claude/skills/review-prs/fetch-prs.py [args...] [--reviewer-priority $BOT_USERNAME]
   ```
   The script handles all fetching, filtering (drafts, uplifts, CI runs, l10n, date cutoff, external contributors), and cache checking. It outputs JSON:
   ```json
   {
     "prs": [{"number": 42001, "title": "...", "headRefOid": "abc123", "author": "user", "hasApproval": false, "isRequestedReviewer": true}],
     "cached_prs": [{"number": 42002, "title": "...", "headRefOid": "def456", "author": "user", "hasApproval": true, "isRequestedReviewer": false}],
     "summary": {"total_fetched": 50, "to_review": 5, "cached_with_possible_threads": 8, "skipped_filtered": 30, "skipped_cached": 7, "skipped_approved": 3, "skipped_external": 2}
   }
   ```
   - **`prs`**: PRs with new commits that need full review
   - **`cached_prs`**: PRs with same SHA as last review but may have unresolved bot threads needing resolution
   - **`skipped_approved`**: PRs the bot previously approved — completely skipped (won't haunt devs)
2. **Print progress summary** from the summary stats (this goes to stdout and will appear in cron logs):
   ```
   Found N PRs to review, C cached PRs to check for thread resolution (M skipped: X drafts/filtered, Y cached, Z approved)
   PRs to review: [PR #12345](https://github.com/$PR_REPO/pull/12345) (title), [PR #12346](https://github.com/$PR_REPO/pull/12346) (title), ...
   Cached PRs for thread resolution: [PR #12347](https://github.com/$PR_REPO/pull/12347), ...
   ```
3. **Review each PR** (from the `prs` array) one at a time using parallel chunk subagents (see Per-Document Review Workflow below)
4. **Aggregate and present findings** from all chunk subagents
5. **Update the cache for EVERY reviewed PR** — this is mandatory regardless of whether violations were found, comments were posted, or comments were skipped. See Step 6 in Per-Document Review Workflow.
6. **If AUTO_MODE**: post all violations immediately and log each result (see Auto Posting below — the per-PR logging and final summary are MANDATORY). **Otherwise**: draft each comment and ask user to approve before posting
7. **Process cached PRs for thread resolution** — for each PR in the `cached_prs` array, run ONLY Step 1.6 (Acknowledge and Resolve) and Step 1.7 (Approve if settled). Do NOT launch subagents or do full reviews — these PRs have already been reviewed at the current SHA

**NEVER post internal working output to GitHub.** Subagent AUDIT trails, SKIPPED_PRIOR sections, DOCUMENT headers, violation summaries, and category labels are internal-only. The only things that appear on GitHub are short inline comment text from each violation's `draft_comment`. Nothing else.

---

## Per-Document Review Workflow

**IMPORTANT:** The main context does NOT load best practices docs or PR diffs. Each PR is reviewed by multiple focused subagents — one per chunk of ~20 rules — running in parallel. Large best-practice documents are split into evenly-sized chunks by a preprocessing script, so each subagent handles a focused set of rules. This ensures every rule is systematically checked rather than relying on a single subagent to hold many rules in mind.

### Step 0: Resolve Bot Username and PR Repository

Before processing any PRs, resolve the bot's GitHub username and the target PR repository dynamically.

```bash
BOT_USERNAME=$(gh api user --jq '.login')
PR_REPO=$(jq -r '.project.prRepository // empty' $BOT_DIR/config.json)
if [ -z "$PR_REPO" ]; then echo "Error: project.prRepository not set in config.json. Run 'make setup'."; exit 1; fi
```

Use `$BOT_USERNAME` in ALL subsequent jq queries and comparisons that need to identify the bot's own comments. Use `$PR_REPO` in ALL `gh` commands and GitHub URL construction instead of hardcoding a repo name. These variables are referenced throughout all subsequent steps.

### Step 1: Fetch Diff and Classify Changed Files

Before launching subagents, fetch the full diff once. This diff will be reused by all subagents (they must NOT re-fetch it).

```bash
# Fetch the full diff once — save to a variable to pass to subagents
PR_DIFF=$(gh pr diff --repo $PR_REPO {number})
```

Extract the file list from the diff for classification:
```bash
echo "$PR_DIFF" | grep '^diff --git' | sed 's|.*b/||'
```

Classify the changed files:
- **has_cpp_files**: `.cc`, `.h`, `.mm` files
- **has_test_files**: `*_test.cc`, `*_browsertest.cc`, `*_unittest.cc`, `*.test.ts`, `*.test.tsx`
- **has_chromium_src**: `chromium_src/` paths
- **has_build_files**: `BUILD.gn`, `DEPS`, `*.gni`
- **has_frontend_files**: `.ts`, `.tsx`, `.html`, `.css`
- **has_android_files**: `.java`, `.kt` files, or paths containing `android/`
- **has_ios_files**: `.swift` files, or paths containing `ios/`
- **has_patch_files**: `.patch` files or paths containing `patches/`
- **has_nala_files**: files matching `*/res/drawable/*`, `*/res/values/*`, or `*/res/values-night/*`, paths `components/vector_icons/`, `.icon` files, or `.svg` files

### Step 1.5: Fetch Existing PR Comments (Re-review Context)

Before launching subagents, fetch all existing review comments and discussion on the PR using the filter script:

```bash
$BOT_DIR/scripts/filter-pr-reviews.sh {number} markdown
```

**External contributor PRs:** If the PR has `isExternalContributor: true` in the fetch output (allowed through because the bot is a requested reviewer), pass the PR author as a 4th argument to include their PR description unfiltered:
```bash
$BOT_DIR/scripts/filter-pr-reviews.sh {number} markdown $PR_REPO {author}
```
This includes the PR body/description from the external contributor so reviewers understand the PR's intent. Other comments from non-org members are still filtered for security.

This returns all past review comments, inline code comments, and discussion comments from Brave org members (filtered for security). Pass this output to each subagent as `PRIOR_COMMENTS` context (see Step 3).

**Why this matters:** When re-reviewing a PR after new commits, the bot must be aware of:
- Its own previous comments (identified by `$BOT_USERNAME` from Step 0) to avoid repeating the same feedback
- Author and reviewer responses that explain or justify a design choice
- Issues that were already acknowledged and addressed

If there are no prior comments (first review), skip this step and omit the prior comments section from the subagent prompt.

### Step 1.5.1: Extract PR Images (Visual Context)

After fetching comments, extract and download any screenshots or images from the PR description and org-member comments. These give subagents visual context about UI changes, which improves review quality.

```bash
python3 $BOT_DIR/scripts/extract-pr-images.py {number}
```

The script outputs JSON with downloaded image paths:
```json
{
  "images": [
    {"path": ".ignore/pr-images/12345/img_001.png", "abs_path": "/full/path/img_001.png", "source": "pr_body", "alt": "screenshot"},
    {"path": ".ignore/pr-images/12345/img_002.jpg", "abs_path": "/full/path/img_002.jpg", "source": "comment_by_user1", "alt": ""}
  ],
  "skipped": [...],
  "summary": {"downloaded": 2, "skipped": 0}
}
```

**Security:** The script only downloads images from org-member content and only from GitHub-hosted URLs. External user images are always skipped.

Save the `images` array as `PR_IMAGES` for use in Step 3. If no images were found (empty array), skip the image section in the subagent prompt.

### Step 1.6: Acknowledge and Resolve Addressed Comments

Resolve bot review threads where the developer has replied. This is a lightweight courtesy step that runs before launching subagents.

**When to run:** Only when Step 1.5 found prior bot comments (from `$BOT_USERNAME`) AND the developer has pushed new commits or replied since the bot's last review.

**MANDATORY: Run the resolve script. Do NOT manually add reactions or resolve threads — the script handles both atomically.**

```bash
python3 $BOT_DIR/scripts/resolve-bot-threads.py {number} "$BOT_USERNAME"
```

The script finds developer replies to bot review threads, resolves the thread via GraphQL, and adds a 👍 reaction — both or neither. It outputs JSON:
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

**CRITICAL — do NOT bypass the script:**
- Do NOT call `gh api .../reactions` on review thread replies yourself — the script handles this
- Do NOT call `resolveReviewThread` yourself — the script handles this
- The script is the ONLY way to add reactions and resolve review threads. This ensures they stay in sync (both happen or neither happens)

**Issue comments (separate from review threads):** After running the script, check general PR issue comments (not review thread replies). If the PR author posted an issue comment acknowledging feedback (e.g., "Fixed", "Done", "Addressed") and new commits were pushed, thumbs-up that issue comment:
```bash
gh api "repos/$PR_REPO/issues/comments/{comment_id}/reactions" \
  --method POST -f content="+1"
```
This is ONLY for general issue comments (the PR conversation tab), NOT for review thread replies.

**Important rules:**
- This step does NOT re-post any comments. It only reacts and resolves. **NEVER re-post the same feedback when resolving.**
- In auto mode, log the script output: `ACK: [PR #<number>](https://github.com/$PR_REPO/pull/<number>) - resolved N threads, M remaining unresolved`
- Skip this step entirely if there are no prior bot comments or no new commits/replies since the last review.

### Step 1.7: Approve if Settled (No Remaining Unresolved Threads)

**CRITICAL: This step is ONLY for cached PRs (the `cached_prs` array).** For PRs in the `prs` array that will get a full subagent review, do NOT run this step — approval is handled in Step 6 Step 7 after all subagents complete. Running Step 1.7 for full-review PRs causes duplicate approvals.

After Step 1.6 resolves addressed comments, check if the bot can approve this PR. **You MUST call the gate script — do NOT approve based on your own judgement or the Step 1.6 output alone.**

**MANDATORY: Run the gate script before ANY approval:**
```bash
python3 $BOT_DIR/scripts/check-can-approve.py {number} "$BOT_USERNAME"
```

The script checks programmatically and returns:
- **Exit code 0** + `"can_approve": true` → safe to approve
- **Exit code 1** + `"can_approve": false` + `"reason"` → do NOT approve, log the reason

The principle is simple: **only approve if the bot has zero outstanding comments of any kind.** A clean first review with no violations (zero prior comments) is a valid approval. The script checks:
1. No body-level review comments exist (these have no resolution mechanism and always block)
2. All inline review threads are resolved
3. The bot hasn't already approved at the current SHA

**CRITICAL: If the script returns exit code 1, you MUST NOT submit an APPROVE review. No exceptions. No overrides. No reinterpretation of the reason text. The script is the single source of truth. ANY non-zero exit code means DO NOT APPROVE — regardless of what the "reason" field says.**

**Only if the script returns exit code 0**, submit the APPROVE review:
```bash
gh api repos/$PR_REPO/pulls/{number}/reviews \
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
- If the bot has ANY outstanding comments — inline threads or body-level review comments (enforced by gate script)
- If the bot already approved at this SHA (enforced by gate script)
- **If a full subagent review (Step 2) is about to run** — this means the PR is in the `prs` array, NOT `cached_prs`. Do NOT approve here; defer to Step 6 Step 7

**Don't Haunt Developers:** Once the bot approves a PR, it is marked as settled in the cache. Future runs will completely skip this PR — no re-reviews, no comment checks, nothing. The bot has said its piece and moved on. The only way to re-review an approved PR is to explicitly request it with `#<PR_NUMBER>`.

**Auto mode logging:**
```
APPROVE: [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - all threads resolved, approved
```

### Step 2: Chunk Documents and Launch Subagents in Parallel

For each applicable best-practice document, run the chunking script to split it into groups of ~20 rules, then launch one **Task subagent** (subagent_type: "general-purpose") per chunk. **Use multiple Task tool calls in a single message** so they run in parallel. Pass the `PR_DIFF` content (fetched in Step 1) directly in each subagent's prompt so they don't need to fetch it again.

**Chunking step:** For each applicable document, run:
```bash
python3 $BOT_DIR/.claude/skills/review-prs/chunk-best-practices.py \
  $BOT_DIR/$BP_SUBMODULE/docs/best-practices/<doc>.md
```

This outputs JSON with one or more chunks per document. Each chunk contains:
- `doc`: the source document filename
- `chunk_index` / `total_chunks`: position within the document
- `rule_count`: number of `##` rules in this chunk
- `headings`: list of rule heading texts (for the audit trail)
- `content`: the full text to pass to the subagent (includes the doc header + the chunk's rules)

Small documents (≤20 rules) produce 1 chunk. Large documents are split evenly (e.g., 65 rules → 3 chunks of 22+22+21). Launch one subagent per chunk.

**Document applicability table:**

| Document | Condition |
|----------|-----------|
| `coding-standards.md` | has_cpp_files |
| `coding-standards-memory.md` | has_cpp_files |
| `coding-standards-apis.md` | has_cpp_files |
| `architecture.md` | Always |
| `documentation.md` | Always |
| `build-system.md` | has_build_files |
| `testing-async.md` | has_test_files |
| `testing-javascript.md` | has_test_files |
| `testing-navigation.md` | has_test_files |
| `testing-isolation.md` | has_test_files |
| `chromium-src-overrides.md` | has_chromium_src |
| `frontend.md` | has_frontend_files |
| `android.md` | has_android_files |
| `ios.md` | has_ios_files |
| `patches.md` | has_patch_files |
| `nala.md` | has_nala_files |

**Always launch at minimum:** architecture and documentation (apply to all PRs — layering, dependency injection, factory patterns, and documentation standards affect every change).

### Step 3: Subagent Prompt

Each subagent prompt MUST include:

1. **The PR number and repo** (from `$PR_REPO`)
2. **The chunk content** — embed the `content` field from the chunking script output directly in the prompt. The subagent does NOT read any files — all rules are provided inline. Include it like:
   ````
   Here are the best practice rules to check:
   ```markdown
   <chunk content>
   ```
   ````
3. **The PR diff content** — include the full diff text (fetched once in Step 1) directly in the prompt. The subagent MUST NOT call `gh pr diff` — the diff is already provided. Embed it in the prompt like:
   ````
   Here is the PR diff:
   ```diff
   <PR_DIFF content>
   ```
   ````
4. **PR images (visual context)** — if `PR_IMAGES` from Step 1.5.1 is non-empty, include the absolute file paths in the subagent prompt and instruct the subagent to view them:
   ````
   This PR includes screenshots/images. Use the Read tool to view each image for visual context about what the PR changes:
   - <abs_path_1> (from: <source>, alt: "<alt>")
   - <abs_path_2> (from: <source>, alt: "<alt>")
   ````
   The subagent can then use the Read tool on these local files to see the images (Claude is multimodal and can interpret images). This helps the subagent understand UI changes, visual regressions, or design intent shown in the PR. If `PR_IMAGES` is empty, omit this section entirely.
5. **The review rules** (copied into the subagent prompt):
   - Only flag violations in ADDED lines (+ lines), not existing code
   - Also flag bugs introduced by the change (e.g., missing string separators, duplicate DEPS entries, code inside wrong `#if` guard)
   - **Check surrounding context before making claims.** When a violation involves dependencies, includes, or patterns, read the full file context (e.g., the BUILD.gn deps list, existing includes in the file) to verify your claim is accurate. Do NOT claim a PR "adds a dependency" or "introduces a pattern" if it already existed before the PR.
   - **Only comment on things the PR author introduced.** If a dependency, pattern, or architectural issue already existed before this PR, do not flag it — even if it violates a best practice. The PR author is not responsible for pre-existing issues. Focus exclusively on what this PR changes or adds.
   - **Do not suggest renaming imported symbols defined outside the PR.** When a `+` line imports or calls a function/class/variable from another module, and that symbol's definition is NOT in a file changed by the PR, do not comment on the symbol's naming. The PR author cannot rename it without modifying the upstream module, which is out of scope. Only flag naming issues on symbols that are defined or renamed within the PR's changed files.
   - **Respect the intent of the PR.** If a PR is moving, renaming, or refactoring files, do not suggest restructuring dependencies, changing `public_deps` vs `deps`, or reorganizing code that was simply carried over from the old location. The author's goal is to preserve existing behavior, not to optimize the code they're moving. Only flag issues that are actual bugs introduced by the move (e.g., broken paths, missing deps that cause build failures), not "while you're here, you should also fix X" improvements.
   - Security-sensitive areas (wallet, crypto, sync, credentials) deserve extra scrutiny — type mismatches, truncation, and correctness issues should use stronger language
   - Do NOT flag: existing code the PR isn't changing, template functions defined in headers, simple inline getters in headers, style preferences not in the documented best practices, **include/import ordering** (this is handled by formatting tools and linters, not this bot)
   - **Every claim must be verified in the best practices source document.** Do NOT make claims based on general knowledge or assumptions about what "should" be a best practice. If the best practices docs do not contain a rule about something, do NOT flag it as a violation — even if you believe it to be true. For example, do NOT claim an API is "deprecated" or a pattern is "banned" unless the best practices doc explicitly says so. Hallucinated rules erode trust and waste developer time. When in doubt, do not comment.
   - Comment style: short (1-3 sentences), targeted, acknowledge context. Use "nit:" for genuinely minor/stylistic issues (including missing comments/documentation). Substantive issues (test reliability, correctness, banned APIs) should be direct without "nit:" prefix
6. **Best practice link requirement** — each rule in the best practices docs has a stable ID anchor (e.g., `<a id="CS-001"></a>`) on the line before the heading. For each violation, the subagent MUST include a direct link using that ID. The link format is:
   ```
   https://github.com/brave-experiments/brave-core-tools/tree/master/docs/best-practices/<doc>.md#<ID>
   ```
   For example, if the heading has `<a id="CS-042"></a>` above it, the link is `...coding-standards.md#CS-042`.

   **CRITICAL: The `rule_link` fragment MUST be an exact `<a id="...">` value from the rules provided in your chunk.** Look for the `<a id="..."></a>` tag on the line before the heading you're referencing and use that ID verbatim. Do NOT invent IDs, guess ID numbers, or construct anchors from heading text. If no `<a id>` tag exists for the rule, or if your observation is a general bug/correctness issue that doesn't map to any specific heading, omit the `rule_link` field entirely.

   **CRITICAL: Do NOT invent rules or claim things are deprecated/banned without verification.** Every best-practice violation you flag MUST correspond to an actual rule provided in your chunk. If you cannot point to the specific heading in the provided rules that contains the rule, do not flag it. Do not rely on general knowledge about Chromium conventions — only flag what is explicitly documented. A hallucinated rule (e.g., claiming an API is "deprecated" when the rules say nothing about it) erodes developer trust and is worse than no comment at all.
7. **Prior comments context (re-review awareness)** — if prior comments exist from Step 1.5, include them in the subagent prompt with these rules:
   - **Do NOT re-raise issues that the author or a reviewer has already explained or justified.** If a prior comment thread shows the author explaining why a design choice was made (e.g., "only two subclasses will ever use this, both pass constants"), accept that explanation and do not flag the same issue again.
   - **Do NOT repeat your own previous comments.** If a comment from the bot (identified by `$BOT_USERNAME` from Step 0) already raised the same point, skip it — even if the code hasn't changed. The author has already seen it.
   - **Do NOT flag new issues on re-review that were missed the first time.** If an issue existed in the code during the first review and was not caught, do not raise it on a subsequent review — unless it is a serious correctness or security concern. Flagging new nits or minor issues on re-review that the bot simply missed earlier is annoying to developers and should be avoided. Only flag issues on re-review if they were **introduced in commits since the last reviewed commit**.
   - **DO re-raise an issue only if:** (a) the author's explanation is factually incorrect or introduces a real risk, OR (b) new code in the latest diff introduces a new instance of the same problem that wasn't previously discussed.
   - When in doubt about whether an issue was addressed, err on the side of NOT re-raising it. Repeating resolved feedback is more disruptive than missing a marginal issue.
8. **The systematic audit requirement** (below)
9. **Required output format** (below)

### Step 4: Systematic Audit Requirement

**CRITICAL — this is what prevents the subagent from stopping after finding a few violations.**

The subagent MUST work through its chunk **heading by heading**, checking every `##` rule against the diff. It must output an audit trail listing EVERY `##` heading in the chunk with a verdict:

```
AUDIT:
PASS: ✅ Always Include What You Use (IWYU)
PASS: ✅ Use Positive Form for Booleans and Methods
N/A: ✅ Consistent Naming Across Layers
FAIL: ❌ Don't Use rapidjson
PASS: ✅ Use CHECK for Impossible Conditions
... (one entry per ## heading in the chunk)
```

Verdicts:
- **PASS**: Checked the diff — no violation found
- **N/A**: Rule doesn't apply to the types of changes in this diff
- **FAIL**: Violation found — must have a corresponding entry in VIOLATIONS

This forces the model to explicitly consider every rule rather than satisficing after a few findings.

### Step 5: Required Output Format

Each subagent MUST return this structured format:

```
DOCUMENT: <document name> (chunk <chunk_index+1>/<total_chunks>)
[PR #<number>](https://github.com/$PR_REPO/pull/<number>): <title>

AUDIT:
PASS: <rule heading>
N/A: <rule heading>
FAIL: <rule heading>
... (one line per ## heading in the chunk)

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

Process PRs **one at a time** (sequentially). After ALL chunk subagents return for a PR:

1. **Update the cache immediately** — run the cache update script right now, before doing anything else:
   ```bash
   python3 .claude/skills/review-prs/update-cache.py <PR_NUMBER> <HEAD_REF_OID>
   ```
   **This step is MANDATORY after every single PR review — regardless of outcome.** Update the cache even when:
   - No violations were found (all chunks returned NO_VIOLATIONS)
   - All violations were skipped due to re-review restraint (all SKIPPED_PRIOR)
   - The user rejects all comments in interactive mode
   - Comments fail to post due to API errors

   The cache tracks "we reviewed this SHA", not "we posted comments". Skipping this causes the same PR to be re-reviewed on the next run, wasting time and risking duplicate comments.
2. **Aggregate and prioritize violations** from all chunk subagents into a single list for the PR. **CRITICAL: Only extract the VIOLATIONS entries from subagent output.** The AUDIT trail, SKIPPED_PRIOR section, DOCUMENT header, and any other subagent working output are internal-only — they must NEVER appear in any GitHub review body, inline comment, or PR comment. Only the `draft_comment` text from each violation is posted.

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
   python3 ./brave-core-tools/scripts/manage-bp-ids.py --check-link <ID> --doc <doc>.md
   ```
   If the ID is invalid (exit code 1), strip the `[best practice](...)` link from the `draft_comment` text before posting. Log: `INVALID_LINK: stripped broken link #<ID> from <file>:<line>`. The comment text itself is still posted — only the broken link is removed.

   **Violations missing `rule_link` must be recovered or dropped — unless they are genuine bug/correctness/security findings.** Best-practice-style comments (style, conventions, patterns) must cite a specific rule so developers can understand the basis and push back. If a subagent returns such a violation without a `rule_link`, search the chunk content for a heading that matches the violation's subject. If a matching rule with an `<a id>` anchor exists, add the `rule_link` and post. If no matching rule exists, drop it — log: `DROPPED: no rule_link for <file>:<line> — "<draft_comment snippet>"`. However, high-severity findings (real bugs, correctness issues, security vulnerabilities, logic errors) may be posted without a `rule_link` since they don't need a style guide to justify them.
4. **Deep-dive validation and enhancement** — before posting, you MUST validate and enhance every remaining violation (typically 1–8 comments at this point) by reading the actual source code. This is a mandatory phase that ensures accuracy and improves comment quality.

   **Source code paths:** The target source tree location is determined by the `workingDirectory` config in `prd.json` (relative to the bot's parent directory). Use the absolute path derived from the bot directory. File paths in violations are relative to the working directory root.

   **For each violation, do the following:**
   - **Read the actual source file** at and around the flagged line. Use the Read tool (not the diff) to see the full file context — surrounding functions, class definitions, includes, namespace scope, and nearby code patterns.
   - **Verify the claim is true.** If the violation says "this should use X instead of Y", confirm that X is actually available, appropriate, and consistent with how the rest of the file/module works. If the violation claims something is missing (e.g., a missing include, a missing null check), verify it's actually missing in the full file, not just absent from the diff.
   - **Deprecation claims require header verification.** If the violation claims an API is deprecated, you MUST read the actual header file that declares the API (in the chromium or brave source tree) and confirm that a deprecation notice, `DEPRECATED` macro, or removal exists. Do NOT rely on training data or general knowledge to determine deprecation status — APIs change across chromium upgrades and your training data may be stale or wrong. If you cannot find the header or cannot confirm the deprecation in the source, drop the violation.
   - **Check surrounding context for justification.** Look for comments, TODOs, or patterns in the surrounding code that might explain why the author wrote the code a certain way. If the surrounding code uses the same pattern the violation is flagging, the comment may be invalid or should acknowledge the existing pattern.
   - **Enhance the comment with concrete context.** If the violation is valid, improve the `draft_comment` with specific details from the source — e.g., reference the specific function/class that provides the better alternative, mention the existing pattern in the file that the new code should follow, or cite a concrete example from nearby code.
   - **Sanitize @mentions in draft_comment.** Subagents may hallucinate GitHub usernames (e.g., adding wrong prefixes like "anthropic-simonhong" instead of "simonhong"). Before posting, scan each `draft_comment` for `@username` mentions and validate them against the PR's actual participants (author, reviewers, assignees) from the GitHub API data. If a mention doesn't match any real participant, fix it to the closest matching participant username. If no match can be determined, strip the `@mention` entirely. Do NOT drop the violation — only fix or remove the bad username. Log: `SANITIZED_MENTION: <file>:<line> — replaced @<hallucinated> with @<correct>` or `SANITIZED_MENTION: <file>:<line> — stripped invalid @<hallucinated>`.
   - **Drop false positives.** If reading the source reveals the violation is incorrect (the code is actually fine, the pattern is consistent with the codebase, or the claim is based on incomplete information from the diff alone), drop the violation. Log: `VALIDATED_DROP: <file>:<line> — <reason it was dropped>`.
   - **Log validation results** for each violation:
     - `VALIDATED: <file>:<line> — confirmed, <brief note on what was checked>`
     - `VALIDATED_ENHANCED: <file>:<line> — improved comment with <what context was added>`
     - `VALIDATED_DROP: <file>:<line> — <reason it was dropped>`

   **This phase is NOT optional.** Subagents work only from the diff, which lacks surrounding context. Reading the actual source code catches false positives that look like violations in the diff but are correct in context. Since there are typically only 1–8 comments at this stage, this deep dive is fast and dramatically improves review quality.

5. **If AUTO_MODE**: post the prioritized violations using the inline review API (see Auto Posting below), then move to the next PR
6. **If interactive mode**: present the prioritized violations to the user for approval before moving to the next PR
7. **If no violations across all categories**: run the approval gate script (see Step 1.7). A clean review with no violations is a valid reason to approve, even on first review with zero prior comments. **Only if exit code is 0**: submit an APPROVE review and mark as settled using `--approve`. This completes the bot's engagement with this PR — future runs will skip it entirely. Log: `APPROVE: [PR #<number>](...) - no violations, approved`. **If exit code is 1: do NOT approve** — log the reason and move on.
8. **If violations were posted**: do NOT approve. The bot will re-check this PR on the next run after the developer addresses the feedback

**PR Link Format (CRITICAL):** When displaying PR numbers to the user, ALWAYS use a full markdown link with the `$PR_REPO` URL: `[PR #<number>](https://github.com/$PR_REPO/pull/<number>) - <title>`. **NEVER use bare `#<number>` references** — the TUI auto-links them against the current repo's git remote, sending users to the wrong repository. Every single PR number shown to the user must be a full `https://github.com/$PR_REPO/pull/` link.

---

## Comment Style

- **Short and succinct** - 1-3 sentences max
- **Targeted** - reference specific files and code
- **Acknowledge context** - if upstream does the same thing, say so
- **No lecturing** - state the issue briefly
- **Link to the rule** - when the violation is an explicit best practice rule, append a link using the rule's stable ID anchor at the end of the comment. Example: `[best practice](https://github.com/brave-experiments/brave-core-tools/tree/master/docs/best-practices/coding-standards.md#CS-042)`. Only include the link for explicit documented rule violations, not for general bug/correctness observations.
- **Match tone to severity:**
  - **Genuine nits** (style, naming, minor cleanup, missing comments/documentation): use "nit:" prefix, "worth considering", "not blocking either way"
  - **Substantive issues** (test reliability, correctness, banned APIs, potential bugs): be direct and clear about why it needs to change. Do NOT use "nit:" for these — a `RunUntilIdle()` violation or a banned API usage is not a nit, it's a real problem.

---

## Interactive Posting

For each violation, present the draft and ask:

> **[PR #12345](https://github.com/$PR_REPO/pull/12345)** - `file:line` - [violation description]
> Draft: `[short comment]`
> Post this comment?

Use "nit:" prefix for genuinely minor/stylistic issues (missing comments/documentation, naming, minor cleanup), not for substantive concerns.

### Deduplication Before Posting (applies to BOTH interactive and auto mode)

Before presenting violations to the user (interactive) or posting them (auto), you MUST programmatically deduplicate against existing bot comments. This prevents the bot from re-posting the same comment when a PR is reviewed multiple times.

```bash
gh api "repos/$PR_REPO/pulls/{number}/comments" --paginate \
  --jq '[.[] | {path, line, body, user: .user.login}]'
```

**CRITICAL: Check comments from ALL users**, not just `$BOT_USERNAME`. If anyone (the bot under a different account, a human reviewer, or an automated tool) has already commented on the same file+line about the same concern, the bot must not pile on. This prevents:
- Cross-account duplicates (bot posted under a different account previously)
- Duplicating a human reviewer's feedback that already covers the same issue

For each violation, if an existing comment exists on the **same file path AND same line number**, drop the violation — regardless of who posted it. The issue was already raised. Log each: `DEDUP: skipped <file>:<line> — already commented by <user>`.

This is a **hard programmatic check** — it overrides subagent output. Even if a subagent reports a violation, if the bot already commented on that file+line, it must be dropped.

### Posting as Inline Code Comments

After deduplication, collect the remaining approved violations (interactive) or all remaining violations (auto) and post them as a **single review with inline comments** using the GitHub API. This places comments directly on the relevant code lines instead of as a general review comment.

```bash
gh api repos/$PR_REPO/pulls/{number}/reviews \
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
      "body": "comment text. [best practice](https://github.com/brave-experiments/brave-core-tools/tree/master/docs/best-practices/coding-standards.md#CS-042)"
    },
    {
      "path": "path/to/other_file.cc",
      "line": 15,
      "side": "RIGHT",
      "body": "another comment. [best practice](https://github.com/brave-experiments/brave-core-tools/tree/master/docs/best-practices/testing-async.md#TA-005)"
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
- If the API call fails (e.g., a line is outside the diff range), retry by splitting: post each inline comment individually via the single-comment API to create proper review threads:
  ```bash
  gh api repos/$PR_REPO/pulls/{number}/comments \
    --method POST \
    -f body="comment text" \
    -f commit_id="<HEAD_SHA>" \
    -f path="path/to/file.cc" \
    -F line=42 \
    -f side="RIGHT"
  ```
  If a specific comment still fails (line truly outside the diff), post it as a PR issue comment as a last resort, but log a warning — issue comments are NOT review threads and will block future approval via the gate check:
  ```bash
  gh pr comment --repo $PR_REPO {number} --body "[file:line] comment text"
  ```
  **NEVER use `gh pr review --comment --body "..."` as a fallback** — this creates a COMMENT review with body text that is NOT a review thread, cannot be resolved, and will block approval permanently via `check-can-approve.py`.

---

## Cached PR Comment Resolution

After processing all full reviews (the `prs` array), process each PR in the `cached_prs` array. These PRs have already been reviewed at the current SHA but may have unresolved bot comment threads that need attention.

**For each cached PR, run ONLY these steps:**

1. **Step 1.6** (Acknowledge and Resolve Addressed Comments) — check for developer replies/fixes and resolve addressed threads
2. **Step 1.7** (Approve if Settled) — run `check-can-approve.py` gate script; only approve if exit code is 0

**Do NOT launch subagents or run a full review** — the code hasn't changed since the last review. The only purpose is housekeeping: resolving addressed threads and approving when the developer has addressed all feedback.

**Skip a cached PR entirely if:**
- No bot comments exist on the PR (nothing to resolve). **IMPORTANT:** If `resolve-bot-threads.py` returns `total_bot_threads: 0`, there are no bot comments — skip this PR. Do NOT report it as having violations.
- No new replies or issue comments since the last review

**Auto mode logging for cached PRs:**
```
CACHED: [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - resolved N threads, M remaining
APPROVE: [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - all threads resolved, approved
```
or if nothing to do:
```
CACHED: [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - no unresolved bot threads
```

Include cached PRs in the final summary with a distinct marker:
```
  🔄 [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - resolved N threads, approved
  🔄 [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - M threads still unresolved
```

---

## Auto Posting

When `AUTO_MODE=true`, skip all interactive approval and post violations directly.

**Auto mode does NOT ask any questions** — no `AskUserQuestion` calls, no confirmation prompts. This is critical for headless/cron operation.

### Per-PR Logging (MANDATORY)

After processing each PR, you MUST print a structured log line to stdout. This is the **only** record of what the cron job did — if you skip this, the cron log will be empty and useless.

**If violations were posted**, capture the review URL from the `gh api` response (the `html_url` field) and log:
```
AUTO: [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - posted <N> comments - <review_url>
  - <file>:<line> (<rule name>)
  - <file>:<line> (<rule name>)
```

**If no violations found:**
```
AUTO: [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - no violations
```

**If the PR was skipped (error fetching diff, etc.):**
```
AUTO: [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - SKIPPED: <reason>
```

### Capturing the Review URL

When posting violations via `gh api repos/$PR_REPO/pulls/{number}/reviews`, the response JSON contains `html_url` — the direct link to the review on GitHub. You MUST capture this and include it in the log line. Example:
```bash
REVIEW_RESPONSE=$(gh api repos/$PR_REPO/pulls/{number}/reviews \
  --method POST --input - <<'EOF'
{ ... }
EOF
)
REVIEW_URL=$(echo "$REVIEW_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['html_url'])")
```

### Posting Flow

**Before any posting logic**, update the cache for this PR (see Step 6 in Per-Document Review Workflow). The cache must be updated even if there are no violations or all violations were skipped.

1. Collect all violations from all chunk subagents for the PR
2. **Deduplicate against existing bot comments (MANDATORY)** — before posting, fetch all existing bot comments on the PR and drop any violation that the bot already commented on:
   ```bash
   gh api "repos/$PR_REPO/pulls/{number}/comments" --paginate \
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
  ✅ [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - no violations, approved
  ❌ [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - <N> comments - <review_url>
  ⏭️ [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - SKIPPED: <reason>
  🔄 [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - resolved N threads, approved
  🔄 [PR #<number>](https://github.com/$PR_REPO/pull/<number>) (<title>) - M threads still unresolved
========================================
```

**This summary block is CRITICAL for cron log readability.** Do not skip it. Do not summarize with vague language like "All done" — list every PR explicitly.

**CRITICAL: What counts as a "violation" for reporting purposes.** A PR has violations ONLY if the bot successfully posted review comments on it (❌ category) OR `resolve-bot-threads.py` returned `unresolved_bot_threads > 0` (⚠️ category). If the bot found issues during review but failed to post comments, or if the bot has zero threads on the PR, it does NOT count as having violations. Never report a PR as having violations based on your own analysis alone — only based on actually-posted bot comments tracked by the scripts.

### Signal Notification (after final summary)

After printing the final summary, send a Signal notification. Only include PRs where the bot took action this run (posted comments, approved, resolved threads). Do NOT include PRs that were already approved with no new action. Format:

```bash
$BOT_DIR/scripts/signal-notify.sh "Review complete: <N> PRs reviewed, <M> with violations, <T> comments posted.

✅ Approved:
https://github.com/$PR_REPO/pull/111
https://github.com/$PR_REPO/pull/222

❌ Violations:
https://github.com/$PR_REPO/pull/333

🔄 Resolved threads:
https://github.com/$PR_REPO/pull/555

⚠️ Still containing violations:
https://github.com/$PR_REPO/pull/666
https://github.com/$PR_REPO/pull/777"
```

Rules:
- Only include PRs where the bot took action (approved, posted comments, resolved threads) in the main sections
- **"Still containing violations"** — ONLY list a PR here if `resolve-bot-threads.py` returned `unresolved_bot_threads > 0` for that PR during this run. Do NOT list PRs based on your own review findings or memory — the script output is the single source of truth. If `unresolved_bot_threads` is 0 (or the script was not run for a PR), that PR must NOT appear in this section.
- **Do NOT include** PRs that were already approved or skipped with no action — they are noise
- Omit a category line if it has zero PRs (e.g., omit "Violations:" if none)
- For cached PRs, append "(cached)" after the link
- This is a no-op if Signal is not configured

---

## Closed/Merged PR Workflow

When reviewing closed or merged PRs and a violation is found:

1. **Present the finding** to the user as usual (draft comment + ask for approval)
2. **If approved**, try to post inline review comments using the same `gh api` approach as open PRs. If the inline API fails (some merged PRs may not support it), fall back to a general comment:
   ```bash
   gh pr comment --repo $PR_REPO {number} --body "[file:line] comment text"
   ```
3. **Create a follow-up issue** in `$PR_REPO` to track the fix:
   ```bash
   gh issue create --repo $PR_REPO --title "Fix: <brief description of violation>" --body "$(cat <<'EOF'
   Found during post-merge review of [PR #<PR_NUMBER>](https://github.com/$PR_REPO/pull/<PR_NUMBER>).

   <description of the violation and what needs to change>

   See: https://github.com/$PR_REPO/pull/<PR_NUMBER>
   EOF
   )"
   ```
4. **Reference the new issue** back in the PR comment so the PR author can find it:
   ```bash
   gh pr comment --repo $PR_REPO <PR_NUMBER> --body "Created follow-up issue https://github.com/$PR_REPO/issues/<ISSUE_NUMBER> to track this."
   ```

This ensures violations on already-merged code don't get lost — they get tracked as actionable issues.
