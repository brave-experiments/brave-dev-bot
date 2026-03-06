# Status: "committed" (Push and Create PR)

**Goal: Push branch and open pull request**

**IMPORTANT: This is the ONLY state where you should create a new PR. If status is "pushed", the PR already exists - NEVER create a duplicate PR.**

**NOTE: This step happens in the SAME iteration as "pending" → "committed" when all tests pass. Only proceed here if you just transitioned to "committed" in this iteration, OR if you're picking up a story that's already in "committed" status.**

## Steps

1. Change to git repo: `cd [targetRepoPath from bot config]`

2. Get branch name from story's `branchName` field

3. Push the branch: `git push -u origin <branch-name>`

4. Create PR using gh CLI with structured format:

   **SECURITY NOTE**: If this PR fixes a security-sensitive issue, use discretion in the title and description. See [SECURITY.md](../brave-core-tools/SECURITY.md#public-security-messaging) for detailed guidance on avoiding detailed vulnerability disclosure in public messages.

   **IMPORTANT**: Always create PRs in draft state using the `--draft` flag. This allows for human review before marking ready.

   **CRITICAL: Always include labels when creating the PR.** Determine which labels apply (see label rules below) and pass them directly to `gh pr create` using `--label` flags.

   ```bash
   gh pr create --draft --title "Story title" \
     --label "ai-generated" \
     --label "QA/No" \
     --label "release-notes/exclude" \
     --body "$(cat <<'EOF'
## Summary
[Brief description of what this PR does and why]

[If this is a Chromium test being disabled, add a clear note:]
**Note: This is a Chromium test** (located in `./src/` not `./src/brave/`).

## Root Cause
[Description of the underlying issue that needed to be fixed]

[If this is a Chromium test, include:]
- **Chromium upstream status**: [Chromium has also disabled this test / Chromium has not disabled this test / Evidence of upstream bug: crbug.com/XXXXX]
- **Brave modifications**: [Brave does not modify this code area / Brave has modifications in ./src/brave/chromium_src/[path] that may affect this test]

## Fix
[Description of how the fix addresses the root cause]

## Test Plan
- [x] Ran npm run format - passed
- [x] Ran npm run presubmit - passed
- [x] Ran npm run gn_check - passed
- [x] Ran npm run build - passed
- [x] Ran npm run test -- [test-name] - passed [N/N times]
- [ ] CI passes cleanly
EOF
)"
   ```

   **IMPORTANT**:
   - Fill in actual test commands and results from acceptance criteria
   - If `.ts`/`.tsx`/`.js` files were changed, add checkboxes for `npm run test-unit` and `npm run build-storybook` to the test plan
   - Keep the last checkbox "CI passes cleanly" unchecked
   - Do NOT add "Generated with Claude Code" or similar attribution
   - Capture the PR number from the output
   - **The `--label` flags above are an example for test fixes.** Adjust labels based on the rules in step 6 below. The `ai-generated` label is ALWAYS required.

5. **Assign the PR to yourself (the bot account):**

   ```bash
   gh pr edit <pr-number> --add-assignee @me
   ```

   This makes it clear who is responsible for the PR and helps with tracking.

6. **Set appropriate labels on the PR and linked issues:**

   Labels should have been applied during PR creation in step 4 via `--label` flags. If any labels were missed, add them now:

   ```bash
   # Add missing labels to PR (if not already applied during creation)
   gh pr edit <pr-number> --add-label "label1,label2"

   # Add labels to linked issue (ALWAYS required - cannot be done during PR creation)
   gh issue edit <issue-number> --add-label "label1,label2" --repo $ISSUE_REPO
   ```

   ### Label Rules

   **MANDATORY for ALL PRs (no exceptions):**
   - `ai-generated` — MUST be on every bot-created PR

   **For test issue fixes (add to BOTH PR and linked issue):**
   - `QA/No` — manual QA not needed
   - `release-notes/exclude` — not user-facing
   - `CI/skip` — **only if the change is limited to filter files** (e.g., `test/filters/`). This skips unnecessary CI for trivial filter-only changes.

   **For other PRs:**
   - `release-notes/exclude` — add to both PR and linked issue for changes typical users wouldn't care about (code cleanup, refactors, internal tooling, etc.)
   - `QA/No` — use judgment based on whether manual QA testing is needed

7. **If push or PR creation succeeds:**
   - Update the PRD status:
     ```bash
     python3 $BOT_DIR/scripts/update-prd-status.py pushed <story-id> --pr-number <number>
     ```
   - Append to `$BOT_DIR/data/progress.txt` (see [progress-reporting.md](./progress-reporting.md))
   - **Send Signal notification** (no-op if not configured):
     ```bash
     $BOT_DIR/scripts/signal-notify.sh "PR created: #<number> - <title> https://github.com/$PR_REPO/pull/<number>"
     ```
   - **END THE ITERATION** - Stop processing

8. **If push or PR creation fails:**
   - DO NOT update status in prd.json (keep as "committed")
   - Document failure in `$BOT_DIR/data/progress.txt`
   - **END THE ITERATION** - Stop processing
