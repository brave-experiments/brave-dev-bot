# Ralph Agent Workflow - Stop Condition Enforcement

## Critical Rule: One Story Per Iteration

Each agent iteration should complete **exactly ONE story**, then stop. The next iteration will automatically pick up the next highest priority story.

## Stop Condition Check Script

After any story status change to `"merged"`, the agent MUST:

1. Update `prd.json` with `status: "merged"`
2. Update `progress.txt` with merge details
3. **IMMEDIATELY run the stop condition check**:
   ```bash
   ./brave-core-bot/scripts/check-should-continue.sh story-completed
   ```

4. **Act on the exit code**:
   - **Exit code 0**: All stories merged → Reply with `<promise>COMPLETE</promise>`
   - **Exit code 1**: Story completed, more remain → **END RESPONSE IMMEDIATELY**
   - **Exit code 2**: No story just completed → Continue working

## Why This Matters

Without this check, the agent may start working on the next story within the same iteration, causing:
- Confusion about which iteration completed which work
- Potential for doing multiple stories when only one was requested
- Difficulty tracking progress per iteration

## Example Correct Flow

```
[Iteration N]
1. Check US-003 PR status
2. Find it's merged
3. Update prd.json: US-003 status = "merged"
4. Update progress.txt
5. Run: ./scripts/check-should-continue.sh story-completed
6. Script returns exit code 1 (STOP)
7. END RESPONSE ← STOP HERE!

[Iteration N+1]
1. Read prd.json
2. Identify US-004 as next priority
3. Begin work on US-004
4. ...
```

## Example Incorrect Flow (BUG)

```
[Iteration N]
1. Check US-003 PR status
2. Find it's merged
3. Update prd.json: US-003 status = "merged"
4. Update progress.txt
5. ❌ Skip stop condition check
6. ❌ Start working on US-004 ← WRONG!
7. ❌ Checkout master, fetch issue, etc.
```

## Script Details

The `check-should-continue.sh` script:
- Reads `prd.json`
- Counts stories where `status != "merged"`
- Returns appropriate exit code based on state
- Provides clear console output about what the agent should do

## Integration Point

This check is documented in **progress.txt → Codebase Patterns** section (first item) so every iteration sees it immediately.
