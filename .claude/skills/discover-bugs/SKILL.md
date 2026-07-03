---
name: discover-bugs
description: "Scan the target repo for likely bugs (lifetime/UAF, threading, null-deref, mojo/IPC, uninitialized) over recently-changed code, verify them, and either report locally or file ai-generated GitHub issues for human confirmation. Triggers on: discover bugs, scan for bugs, bug scan, find bugs in code."
argument-hint: "[--since-cache|--commits N|--days N] [auto] [file-issues]"
allowed-tools: Bash
---

# Discover Bugs (static scan)

Bounded, verify-first static scan of the target repository for concrete
defects. Findings are **not** auto-fixed — they are reported for a human to
confirm. Confirmed issues then flow through the normal pipeline
(`add-backlog-to-prd` → `run.sh`).

**Default output is a local report only.** Issue filing to the configured issue
repository (`gh issue create --label ai-generated`) happens ONLY when invoked
with the `file-issues` argument, so the tracker is never spammed while scan
quality is still being tuned.

**NEVER** @-mention or tag anyone in a filed issue (repo rule). The
`ai-generated` label is the sole provenance signal.

---

## Architecture: file-based pipeline (mirrors review-prs)

All heavy data goes through files, not the LLM context:

1. **prepare-scan.py** (zero LLM tokens) — selects changed source files, writes
   one subagent prompt file per chunk, emits a manifest.
2. **Subagents** (subagent tokens only) — each reads its prompt file, reads the
   real source to CONFIRM each finding, writes a results JSON file.
3. **collect-findings.py** (zero LLM tokens) — confidence gate, dedup, then
   local report or issue filing; updates the scan cache.

---

## The Job

When invoked with `/discover-bugs [--since-cache|--commits N|--days N] [auto] [file-issues]`:

### Step 1: Prepare (zero LLM tokens)

```bash
BOT_DIR="<absolute path to brave-dev-bot directory>"
python3 $BOT_DIR/.claude/skills/discover-bugs/prepare-scan.py [--since-cache|--commits N|--days N]
```

Default window is `--since-cache` (diff since the last scan; falls back to the
last 7 days on first run). Stdout is a tiny JSON: `{"work_dir":..., "manifest":...}`.
Parse it to get `work_dir`.

### Step 2: Read manifest

Read `{work_dir}/manifest.json`. Print its `progress_lines` (for cron logs). Key
fields: `chunks` (each has `prompt_file` + `results_file`), `issue_repo`,
`target_repo_path`, `capped` (log the warning if true — files were dropped).

If `chunks` is empty, skip to Step 4 (nothing changed).

### Step 3: Launch subagents

For every chunk, launch a **Task subagent** (`subagent_type: "general-purpose"`)
with this prompt — **launch ALL chunks in a single message** so they run
concurrently:

```
Read your full scan instructions from: {prompt_file}
Execute them completely. Read the referenced source files under the target repo
to CONFIRM each finding before reporting it. Report ONLY confidence:high bugs.
Write your results JSON to the exact path named in the instructions.
```

Wait for all subagents to return. Do NOT file issues or write reports yourself —
that is Step 4's job.

### Step 4: Collect (zero LLM tokens)

```bash
python3 $BOT_DIR/.claude/skills/discover-bugs/collect-findings.py --work-dir "$WORK_DIR" [--file-issues]
```

Pass `--file-issues` ONLY if the invocation included the `file-issues` argument
(or `auto file-issues` in cron once quality is proven). Otherwise it writes a
local report to `logs/discover-bugs-<stamp>.md` and files nothing.

Read the script's stderr summary and print it for cron logs.

---

## Modes

- **default (report-only):** `/discover-bugs` — scan, verify, write local report.
- **file issues:** `/discover-bugs file-issues` — additionally file
  `ai-generated` issues for fresh high-confidence findings.
- **cron/headless:** `/discover-bugs --since-cache auto` — report-only by
  default; add `file-issues` to the cron args only after the false-positive rate
  is acceptable.

## Guardrails

- Report ONLY `confidence:high` findings (collect-findings enforces this).
- Dedup against the local seen-list AND open `ai-generated` issues — never
  re-file the same bug.
- Never auto-fix. Never @-mention. Never merge.
- `--max-files` caps work per run; the manifest logs anything dropped (no silent
  truncation).
