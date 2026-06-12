---
name: browser-verify
description: "Verify a story's user-facing behavior by driving a real dev Brave via the chrome-devtools MCP. Launches a throwaway remote-debuggable Brave, executes a test plan, records a PASS/FAIL verdict in progress.txt. Triggers on: browser verify, verify in browser, test in browser, run the test plan, browser-verify."
---

# Browser Verification

Functionally verify a story's user-facing behavior in a **real** browser — not just by
running unit/automated tests. Drive the locally-built dev Brave through a concrete test plan
using the `chrome-devtools` MCP, then record a PASS/FAIL verdict.

This is the executable, single-source-of-truth version of the procedure referenced by
`docs/workflow-pending.md` (step 6b). The autonomous loop (`run.sh`) also brings up the browser
for stories flagged `"browserVerify": true`; this skill works both inside that loop (browser
already running — reuse it) and standalone (a dev invokes it — start and stop the browser).

**Determine the bot directory:** This SKILL.md lives in `.claude/skills/browser-verify/`. Derive
the absolute bot directory from this file's path (referred to as `$BOT_DIR` below).

**Prerequisite:** the `chrome-devtools` MCP must be registered in `~/.claude.json` pointing at
`http://127.0.0.1:9223`. If the MCP tools are unavailable in this session, stop and report that
the MCP is not configured/loaded (a Claude restart may be required after configuring it).

---

## Step 1: Ensure a debuggable browser is running

The browser lifecycle is owned by `$BOT_DIR/scripts/launch-brave-debug.sh`. Check whether one is
already up before launching, so you don't stop a browser the autonomous loop started.

```bash
$BOT_DIR/scripts/launch-brave-debug.sh status
```

- **Reachable (exit 0):** a browser is already running (e.g. `run.sh` started it). Reuse it.
  Set a note that you did **NOT** start it, so you do **NOT** stop it in Step 5.
- **Not reachable (exit 1):** start one yourself:
  ```bash
  $BOT_DIR/scripts/launch-brave-debug.sh start
  ```
  Set a note that you **DID** start it, so you stop it in Step 5. If `start` fails (dev binary
  missing, port held by a non-debuggable process), stop and report — verification cannot proceed.

Confirm the discovery endpoint responds before driving it:

```bash
curl -fsS --max-time 2 http://127.0.0.1:9223/json/version | jq '.Browser'
```

---

## Step 2: Define the test plan

Write down, concretely, what the story changes and how to observe it. Keep it specific and
reproducible:

- **Preconditions** — required state/flags (the profile is throwaway; do not assume logins).
- **Steps** — exact actions (URLs to visit, elements to click, text to enter).
- **Expected** — the behavior the story specifies.

Base this on the story description and acceptance criteria, not on assumptions about the code.

---

## Step 3: Execute it via the chrome-devtools MCP

Drive the browser with the MCP tools:

- `mcp__chrome-devtools__list_pages` / `mcp__chrome-devtools__new_page` — manage tabs.
- `mcp__chrome-devtools__navigate_page` — go to a URL.
- `mcp__chrome-devtools__take_snapshot` — **prefer this** to locate elements (a11y tree with uids).
- `mcp__chrome-devtools__click` / `fill` / `type_text` / `press_key` — interact, using uids from
  the latest snapshot.
- `mcp__chrome-devtools__take_screenshot` (with a `filePath` inside `$BOT_DIR`) — capture visual
  state to confirm the result and attach evidence.

Record what you actually observe at each step.

---

## Step 4: Judge PASS / FAIL honestly

Compare **Observed** against **Expected**:

- If they match → **PASS**.
- If they do not → **FAIL**. The story is NOT done. Do not transition it to "committed". Keep
  working on the fix or report the failure.

Do not rationalize a near-miss into a pass.

---

## Step 5: Record the verdict in progress.txt

Append the **Browser Verification** block to the `pending → committed` entry in
`$BOT_DIR/data/progress.txt`, following the template in `docs/progress-reporting.md`:

```
- **Browser Verification**:
  - Test plan: [steps to observe the behavior]
  - Expected: [behavior the story specifies]
  - Observed: [what actually happened in the browser]
  - Screenshots: [paths under $BOT_DIR, or "none"]
  - Verdict: [PASS / FAIL]
```

Then tear down **only if you started the browser** in Step 1:

```bash
# Run ONLY if Step 1 launched the browser (status was "not reachable").
# If you reused a browser run.sh started, do NOT stop it.
$BOT_DIR/scripts/launch-brave-debug.sh stop
```

---

## Summary

1. Ensure a debuggable Brave is up on 9223 (reuse if present, else `start`).
2. Define a concrete test plan from the story.
3. Execute it via the chrome-devtools MCP, capturing observations + screenshots.
4. Judge PASS/FAIL honestly — FAIL means the story is not done.
5. Record the Browser Verification block in progress.txt; `stop` the browser only if you started it.
