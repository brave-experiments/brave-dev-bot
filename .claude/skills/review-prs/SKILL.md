---
name: review-prs
description: "Review PRs in the configured PR repository for best practices violations. Supports single PR (#12345), state filter (open/closed/all), and auto mode for cron. Triggers on: review prs, review recent prs, /review-prs, check prs for best practices."
argument-hint: "[days|page<N>|#<PR>] [open|closed|all] [auto] [reviewer-priority]"
allowed-tools: Bash(gh pr diff:*)
---

# Review PRs for Best Practices

Scan recent open PRs in the configured PR repository for violations of documented best practices.

- **Interactive mode** (default): drafts comments and asks for user approval before posting.
- **Auto mode** (`auto` argument): posts all violations automatically without approval. Designed for cron/headless use.

**IMPORTANT:** This skill only reviews PRs against existing best practices. It must NEVER create, modify, or add new best practice rules or documentation during a review run.

---

## The Job

When invoked with `/review-prs [days|page<N>|#<PR>] [open|closed|all] [auto] [reviewer-priority]`:

### Step 1: Prepare (zero LLM tokens)

Run the prepare script with all arguments. It handles ALL pre-work: fetching PRs, diffs, classifying files, fetching comments, resolving threads, discovering best-practice docs, chunking rules, and building subagent prompts.

```bash
BOT_DIR="<absolute path to brave-dev-bot directory>"
PREPARE_ARGS=""
# Pass through days/page/PR# and state args directly
# Convert "auto" to --auto flag
# Convert "reviewer-priority" to --reviewer-priority flag
python3 $BOT_DIR/.claude/skills/review-prs/prepare-review.py [days|page<N>|#<PR>] [open|closed|all] [--auto] [--reviewer-priority]
```

The script outputs JSON to stdout (progress goes to stderr). Parse the JSON output. It contains:

- **`auto_mode`**: whether to post without approval
- **`bot_username`**: the bot's GitHub username
- **`pr_repo`**: the target PR repository
- **`fetch_summary`**: stats on how many PRs were fetched/filtered/skipped
- **`progress_lines`**: pre-formatted progress messages — print these to stdout for cron logs
- **`prs`**: array of PRs to review, each containing:
  - `number`, `title`, `headRefOid`, `author`, `hasApproval`
  - `diff`: the full PR diff text
  - `prior_comments`: markdown of prior review comments (or null)
  - `has_bot_comments`: whether the bot has prior comments
  - `images`: array of image paths for visual context
  - `thread_resolution`: results from resolving addressed threads
  - **`subagent_prompts`**: array of pre-built prompt strings for each rule chunk
- **`cached_prs`**: array of already-reviewed PRs with thread resolution and approval results (already processed by the script — no LLM action needed, just log results)
- **`errors`**: array of per-PR errors encountered during preparation

Print the `progress_lines` to stdout. Log any errors.

For each cached PR, log the result:
- If `approved` is true: `APPROVE: [PR #N](url) (title) - all threads resolved, approved`
- If `thread_resolution.unresolved_bot_threads > 0`: `CACHED: [PR #N](url) (title) - N threads still unresolved`
- If `thread_resolution.total_bot_threads == 0`: skip (no bot comments)

If there are no PRs to review (empty `prs` array), skip to the final summary.

### Step 2: Launch subagents

For every PR in the `prs` array, for every entry in that PR's `subagent_prompts` array, launch a **Task subagent** (subagent_type: "general-purpose") with the pre-built `prompt` string. **Launch ALL subagents across ALL PRs in a single message** so they run concurrently.

**CRITICAL: Launch ALL subagents — no exceptions.** The prepare script already filtered documents by file type. Every prompt in `subagent_prompts` MUST get a subagent. Do NOT skip any based on your own relevance judgment.

Wait for all subagents to return.

### Step 3: Parse subagent results

Each subagent returns structured output. Extract ONLY the `VIOLATIONS` section from each subagent's output. The AUDIT trail, SKIPPED_PRIOR section, and DOCUMENT header are internal-only — they must NEVER appear on GitHub.

Group violations by PR number (included in each subagent prompt).

**Expected subagent output format:**

```
DOCUMENT: <document name> (chunk N/M)
[PR #<number>](url): <title>

AUDIT:
PASS: <rule heading>
N/A: <rule heading>
FAIL: <rule heading>
...

SKIPPED_PRIOR:
- file: <path>, issue: <desc>, reason: <why>
NONE

VIOLATIONS:
- file: <path>, line: <line_number>, severity: <"high"|"medium"|"low">, rule: "<rule heading>", rule_link: <URL>, issue: <desc>, draft_comment: <1-3 sentence comment>
NO_VIOLATIONS
```

### Step 4: Deep-dive validation (LLM's actual job)

Before posting, validate and enhance every violation by reading the actual source code. This is the one phase that genuinely requires LLM judgment.

**Source code paths:** The target source tree is at `$BOT_DIR/../src/brave` (derived from `project.targetRepoPath` in config). File paths in violations are relative to this directory.

**For each violation:**
- **Read the actual source file** at and around the flagged line. Use the Read tool to see full context — surrounding functions, class definitions, includes, namespace scope.
- **Verify the claim is true.** If the violation says "use X instead of Y", confirm X is available and appropriate. If it claims something is missing, verify it's actually missing in the full file, not just absent from the diff.
- **Deprecation claims require header verification.** Read the actual header file to confirm. Do NOT rely on training data.
- **Check surrounding context for justification.** Look for comments, TODOs, or patterns that explain the code. If surrounding code uses the same pattern being flagged, the violation may be invalid.
- **Enhance the comment with concrete context** — reference specific functions, existing patterns, or nearby code.
- **Sanitize @mentions** — validate against actual PR participants. Fix or strip hallucinated usernames.
- **Drop false positives.** If reading the source reveals the violation is incorrect, drop it.
- **Log each result:**
  - `VALIDATED: <file>:<line> — confirmed, <note>`
  - `VALIDATED_ENHANCED: <file>:<line> — improved with <context>`
  - `VALIDATED_DROP: <file>:<line> — <reason>`

**This phase is NOT optional.** Subagents work only from the diff. Reading actual source catches false positives.

### Step 5: Post results (zero LLM tokens)

Build the input JSON for the post script and run it:

```bash
python3 $BOT_DIR/.claude/skills/review-prs/post-review.py \
  --pr-repo "$PR_REPO" --bot-username "$BOT_USERNAME" [--auto] [--input violations.json]
```

Or pipe via stdin. The input JSON format:

```json
{
  "pr_results": [
    {
      "number": 42001,
      "title": "Add feature X",
      "headRefOid": "abc123",
      "hasApproval": false,
      "violations": [
        {
          "file": "path/to/file.cc",
          "line": 42,
          "severity": "high",
          "rule": "Rule heading",
          "rule_link": "https://github.com/brave-experiments/brave-core-tools/tree/master/docs/best-practices/coding-standards.md#CS-042",
          "issue": "Brief description",
          "draft_comment": "The comment text to post. [best practice](url)"
        }
      ],
      "validation_log": ["VALIDATED: file.cc:42 — confirmed"]
    }
  ]
}
```

The script handles: prioritization/capping (5 per PR), rule link validation, deduplication against existing comments, posting as inline review, approval for clean PRs, cache updates, the final summary block, and Signal notification.

For **interactive mode** (no `--auto`): instead of calling post-review.py, present each violation to the user for approval:

> **[PR #12345](url)** - `file:line` - [violation description]
> Draft: `[short comment]`
> Post this comment?

Then pass only approved violations to post-review.py (without `--auto`).

Read the script's stderr output — it contains the per-PR log lines and the final summary block. Print these to stdout for cron logs. The script's stdout is a JSON result summary.

### Summary of what consumes LLM tokens

| Phase | Token cost | Who does it |
|-------|-----------|-------------|
| Fetch PRs, diffs, comments | **Zero** | `prepare-review.py` |
| Classify files, discover docs | **Zero** | `prepare-review.py` |
| Resolve threads, check approval | **Zero** | `prepare-review.py` |
| Build subagent prompts | **Zero** | `prepare-review.py` |
| Rule-checking subagents | **Subagent tokens** | Subagents (general-purpose) |
| Deep-dive validation | **Main session tokens** | LLM (Step 4) |
| Prioritize, dedup, post, approve | **Zero** | `post-review.py` |
| Signal notification | **Zero** | `post-review.py` |

---

## PR Link Format

When displaying PR numbers, ALWAYS use a full markdown link: `[PR #<number>](https://github.com/$PR_REPO/pull/<number>)`. NEVER use bare `#<number>` — the TUI auto-links them against the wrong repository.

---

## Closed/Merged PR Workflow

When reviewing closed or merged PRs and a violation is found:

1. **Present the finding** to the user (draft comment + ask for approval)
2. **If approved**, try to post inline review comments. If the API fails, fall back to:
   ```bash
   gh pr comment --repo $PR_REPO {number} --body "[file:line] comment text"
   ```
3. **Create a follow-up issue** in `$PR_REPO` to track the fix:
   ```bash
   gh issue create --repo $PR_REPO --title "Fix: <brief description>" --body "Found during post-merge review of PR #<NUMBER>. <description>"
   ```
4. **Reference the new issue** back in the PR comment.
