---
name: rebase-bot-prs
description: "Rebase all open PRs by the bot account onto the upstream default branch. Fetches the upstream remote first to ensure it is up to date, then rebases each bot PR branch and force-pushes with --force-with-lease. Triggers on: rebase bot prs, rebase all my prs, rebase open prs on upstream, update prs against master."
argument-hint: "[#<PR> ...]"
allowed-tools: Bash(python3:*), Bash(git fetch:*), Bash(git status:*), Bash(gh pr list:*)
---

# Rebase Bot PRs on Upstream

Rebase every open PR authored by the bot account onto the upstream default
branch (`upstream/master`), fetching upstream first so the base is current.

A single script does the work. It reads `config.json` for the bot username, PR
repository (`brave/brave-core`), default branch, and target repo path, so no
arguments are required.

## Remote resolution

The project docs call the canonical remote `upstream`, but a given checkout may
only have `origin` pointing at the PR repo. The script resolves this
automatically: it prefers a literal `upstream` remote, otherwise uses whichever
remote's URL matches `prRepository`, otherwise `origin`. It rebases onto
`<resolved-remote>/<defaultBranch>` and force-pushes branches to the remote that
hosts them.

## Safety properties

- **Fetch first.** Always `git fetch` the upstream remote (and the push remote
  if different) before rebasing, so master is up to date.
- **Clean tree required.** `--execute` aborts immediately if the working tree is
  dirty — it will not touch any branch.
- **Conflicts are skipped, not forced.** If a rebase hits a conflict the script
  runs `git rebase --abort`, leaves that PR untouched, and reports it for manual
  handling.
- **`--force-with-lease`**, never a bare `--force`, so a branch that moved on the
  remote since the fetch is not clobbered.
- **Fork PRs skipped.** Cross-repository (fork) PR branches can't be pushed to
  and are listed as skipped.
- **Original branch restored** at the end (even on error).

## Steps

`BOT_DIR` = absolute path to the `brave-dev-bot` directory.

### Step 1: Plan (dry run)

```bash
python3 "$BOT_DIR/.claude/skills/rebase-bot-prs/rebase-bot-prs.py"
```

This fetches upstream and prints exactly which PR branches would be rebased.
Show the plan to the user.

To restrict to specific PRs, pass their numbers: `... rebase-bot-prs.py 36966 36725`.

### Step 2: Execute

Force-pushing rewrites the bot's PR branches — a consequential, outward-facing
action. If the user already asked to "rebase all the PRs" treat that as
authorization and proceed; otherwise confirm the plan from Step 1 first.

```bash
python3 "$BOT_DIR/.claude/skills/rebase-bot-prs/rebase-bot-prs.py" --execute
```

### Step 3: Report

Relay the script's SUMMARY. For any PR marked `CONFLICT`, `PUSH_FAILED`, or
`ERROR`, surface the detail so the user can resolve it manually — do not attempt
to force past a conflict.

## Notes

- Run from anywhere; the script locates the target repo from config.
- The script never merges master into a branch — it always rebases, per project
  git policy.
- It does not create, close, or comment on PRs; it only updates branches.
