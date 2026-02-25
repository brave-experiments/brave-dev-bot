# Brave Core Bot

An autonomous coding agent for the Brave browser project. Built on Claude Code, it reads Product Requirements Documents (PRDs), implements user stories, runs tests, creates PRs, handles review feedback, and manages CI — all autonomously in iterative loops.

## Overview

The bot operates in an iterative loop with a state machine workflow:

1. Reads PRD from `prd.json`
2. Picks the next story using smart priority (reviewers first!):
   - **URGENT**: Pushed PRs where reviewer responded (respond immediately)
   - **HIGH**: Pushed PRs where bot responded (check for new reviews/merge)
   - **MEDIUM**: Committed PRs (create PR)
   - **NORMAL**: Start new development work
3. Executes based on current status:
   - **pending**: Implement, test, and commit → `committed`
   - **committed**: Push branch and create PR → `pushed` (lastActivityBy: "bot")
   - **pushed**: Check merge readiness FIRST, then:
     - If mergeable: Merge → `merged`
     - If reviewer commented: Implement feedback, push → (lastActivityBy: "bot")
     - If waiting: Skip to next story (will check again next iteration)
   - **merged**: Post-merge monitoring (CI breakage, flakes)
4. Updates progress in `progress.txt`
5. Repeats until all stories have terminal status (`merged`, `skipped`, or `invalid`)

**Story Lifecycle:**
```
     pending
        ↓
    (implement + test)
        ↓
    committed
        ↓
    (push + create PR)
        ↓
     pushed ◄─────────┐
    ╱   │   ╲         │
   ╱    │    ╲        │
merge  wait  review   │
  │     │     ↓       │
  │     │   (implement + test)
  │     │     ↓       │
  │     │   (commit + push)
  │     │     └───────┘
  ↓     │
merged  └─► (check again next iteration)
  ↓
(post-merge monitoring)
```

**Key Points:**
- Initial development: pending → (implement+test) → committed
- Review response: pushed → (implement+test) → (commit+push) → pushed
- **Same quality gates apply** — ALL tests must pass whether initial development or responding to reviews

**Anti-Stuck Guarantee:** Every `pushed` PR is checked for merge readiness on EVERY iteration, even when `lastActivityBy: "bot"`. Approved PRs never get stuck.

**Smart Waiting:** The bot tracks `lastActivityBy` to avoid spamming PRs while ensuring progress. See [docs/workflow-state-machine.md](docs/workflow-state-machine.md) for detailed flow.

## Prerequisites

- **Claude Code CLI** installed and configured
- **GitHub CLI** (`gh`) authenticated with your account
- **jq** for JSON parsing: `brew install jq` (macOS) or `sudo apt install jq` (Debian/Ubuntu)
- **Git** configured with your credentials
- **Python 3** (for utility scripts)
- Access to the `brave/brave-browser` repository

## Setup

### 1. Clone This Repository

Clone at the root of your brave-browser checkout, alongside the `src` directory:

```
brave-browser/
├── src/
│   └── brave/              # Target git repository
└── brave-core-bot/         # This bot (clone here)
    ├── run.sh
    ├── prd.json
    └── ...
```

```bash
cd /path/to/brave-browser
git clone https://github.com/brave-experiments/brave-core-bot.git
```

### 2. Configure Git

Configure git identity in the target repository (`src/brave`):

```bash
cd brave-browser/src/brave
git config user.name "netzenbot"
git config user.email "netzenbot@brave.com"
```

These settings are repository-specific (stored in `.git/config`), not global.

### 3. Create Configuration Files

Copy the example templates and customize:

```bash
cd brave-core-bot

cp prd.example.json prd.json
cp run-state.example.json run-state.json
cp progress.example.txt progress.txt
```

Edit `prd.json` to set your working directory path (e.g., `src/brave`).

These files contain user-specific paths and runtime state, so they're gitignored.

### 4. Run Setup Script

```bash
cd brave-core-bot
./setup.sh
```

This will:
- Install pre-commit hooks to the target repository and bot repository
- Validate `prd.json` configuration
- Verify git repo structure and user configuration
- Create and populate the org-members cache (`.ignore/org-members.txt`)
- Display next steps

### 5. Create Your PRD

**Option A: Use the `/prd` skill** (recommended)
```bash
claude
> /prd [describe your feature]
```
Follow the prompts, then use `/prd-json` to convert to `prd.json`.

**Option B: Manually edit `prd.json`**

```json
{
  "config": {
    "workingDirectory": "src/brave"
  },
  "userStories": [
    {
      "id": "STORY-1",
      "title": "Fix authentication test",
      "priority": 1,
      "status": "pending",
      "branchName": null,
      "prNumber": null,
      "prUrl": null,
      "lastActivityBy": null,
      "acceptanceCriteria": [
        "npm run test -- auth_tests from src/brave"
      ]
    }
  ]
}
```

**Status values:** `"pending"` | `"committed"` | `"pushed"` | `"merged"` | `"skipped"` | `"invalid"`

**lastActivityBy values:** `null` (fresh) | `"bot"` (waiting for reviewer) | `"reviewer"` (bot should act)

## Usage

### Run the Bot

```bash
cd brave-core-bot
./run.sh           # Default: 10 iterations
./run.sh 20        # Run 20 iterations
./run.sh 10 tui    # TUI mode (interactive terminal UI)
```

### Monitor Progress

```bash
tail -f progress.txt
```

### Stop the Bot

Press `Ctrl+C`. The bot will attempt to switch back to the master branch before exiting.

### Reset Between Runs

```bash
./reset-run-state.sh
```

Resets `run-state.json` for a fresh run while preserving configuration flags.

## Skills

All skills are available as slash commands in Claude Code. 20 skills are included:

### PRD & Project Management

| Skill | Description |
|-------|-------------|
| `/prd` | Generate structured PRDs with clarifying questions |
| `/prd-json` | Convert PRD markdown to `prd.json` format |
| `/prd-clean` | Archive merged/invalid stories to `prd.archived.json` |
| `/add-backlog-to-prd` | Fetch open issues from brave/brave-browser by label and add to PRD |

### Code Review & Quality

| Skill | Description |
|-------|-------------|
| `/review` | Review code for quality, root cause analysis, and fix confidence. Supports local mode (current branch) and PR mode (by URL or number) |
| `/review-prs` | Batch review PRs for best practices violations. Supports auto mode for cron. Deduplicates against existing bot comments. Tracks prior comment context |
| `/check-best-practices` | Audit local branch diff against all best practices documents using parallel subagents |
| `/preflight` | Run all preflight checks (format, gn_check, presubmit, build, tests) |
| `/learnable-pattern-search` | Analyze PR review comments to discover learnable patterns. Supports self-review mode to identify overly strict rules |

### Implementation & Git

| Skill | Description |
|-------|-------------|
| `/commit` | Create atomic commits without attribution. Supports `branch` and `push` keywords |
| `/pr` | Create pull request for current branch with auto-generated description |
| `/impl-review` | Implement review feedback on a PR: checkout, apply changes, preflight, commit, push. Supports auto mode |
| `/rebase-downstream` | Rebase a tree of dependent branches after upstream changes |
| `/clean-branches` | Delete local branches whose PRs have been merged |

### CI & Testing

| Skill | Description |
|-------|-------------|
| `/check-upstream-flake` | Query LUCI Analysis for upstream Chromium test flakiness (30-90 day lookback) |
| `/make-ci-green` | Re-run failed Jenkins CI jobs. Analyzes test failures, checks upstream flakiness, correlates with PR changes. Supports dry-run mode |
| `/top-crashers` | Analyze top crash data from Brave's Backtrace crash reporting |

### Release & Maintenance

| Skill | Description |
|-------|-------------|
| `/uplift` | Cherry-pick test/crash fixes to beta/release branches. Adds uplift labels to source PRs |
| `/update-best-practices` | Fetch and merge upstream Chromium documentation guidelines |
| `/check-milestones` | Check milestone status |

### Sharing Skills with src/brave

Skills can be symlinked to `src/brave/.claude/skills/` for use when working directly in the brave-core repo:

```bash
./sync-skills.sh        # Interactively symlink selected skills
./sync-best-practices.sh  # Symlink best practices to .claude/rules/
```

## Run State Configuration

`run-state.json` controls per-run behavior:

| Field | Description |
|-------|-------------|
| `runId` | Timestamp when this run started (auto-set) |
| `storiesCheckedThisRun` | Story IDs already processed in this run |
| `skipPushedTasks` | Skip all "pushed" PRs, only work on new development |
| `enableMergeBackoff` | Enable post-merge monitoring (default: true) |
| `mergeBackoffStoryIds` | Array of specific merged story IDs to check, or null for all |
| `lastIterationHadStateChange` | Tracks if work was done last iteration |

## Configuration Files

### prd.json

Product Requirements Document defining user stories and acceptance criteria.

- `config.workingDirectory`: Git repository path (typically `src/brave`)
- `userStories[].id`: Unique story identifier
- `userStories[].priority`: Execution order (1 = highest)
- `userStories[].status`: Story state
- `userStories[].branchName`: Git branch name (set when work starts)
- `userStories[].prNumber`: PR number (set when PR created)
- `userStories[].prUrl`: PR URL (set when PR created)
- `userStories[].lastActivityBy`: Who acted last — `"bot"` | `"reviewer"` | `null`
- `userStories[].acceptanceCriteria`: Test commands that must pass

### progress.txt

Log of completed iterations:
- Codebase Patterns section (reusable patterns discovered during development)
- Per-iteration entries with status transitions, files changed, test results
- Learnings for future iterations

### CLAUDE.md

Agent instructions defining workflow, testing requirements, git operations, security guidelines, and quality standards.

## Best Practices

The bot enforces a comprehensive set of best practices organized by category:

- **Architecture** — Layering, dependency injection, factory patterns
- **Coding Standards** — Naming, CHECK vs DCHECK, IWYU, ownership, WeakPtr, base utilities
- **Testing** — Async patterns, JavaScript tests, navigation, test isolation
- **Frontend** — TypeScript/React, XSS prevention, component patterns
- **Build System** — BUILD.gn, buildflags, DEPS, GRD resources
- **Chromium src/ Overrides** — Override patterns, minimizing duplication
- **Documentation** — Inline comments, method docs

See [BEST-PRACTICES.md](BEST-PRACTICES.md) for the full index and quick checklist.

## Git Workflow

### Branch Management

Each user story gets its own branch, created automatically by the bot from `prd.json`.

### Pre-commit Hooks

Two hooks are installed by `setup.sh`:

**Target repo hook** (`hooks/pre-commit`):
Blocks the `netzenbot` account from modifying dependency files (package.json, DEPS, Cargo.toml, go.mod, etc.). Prevents bots from introducing external dependencies without review.

**Bot repo hook** (`hooks/pre-commit-bot-repo`):
Blocks committing `prd.json`, `progress.txt`, and `run-state.json` to ensure user-specific files don't get committed.

### Commit Format

```
feat: [Story ID] - [Story Title]
```

Commits must NOT include `Co-Authored-By` lines.

## Testing

### Acceptance Criteria

All acceptance criteria tests MUST run and pass before marking a story as complete. The bot will:
- Run ALL tests specified in acceptance criteria
- Use background execution for long-running tests
- Never skip tests regardless of duration
- Only mark a story complete when tests actually pass

### Test Suite

Run the automated test suite to verify setup:

```bash
./tests/test-suite.sh
```

Validates GitHub API integration, file structure, filtering scripts, pre-commit hooks, and configuration files.

## Security

### Prompt Injection Protection

The bot filters all GitHub data (issues, PR reviews) through security scripts that check authors against Brave org membership:

```bash
./scripts/filter-issue-json.sh 12345 markdown   # Filtered issue content
./scripts/filter-pr-reviews.sh 12345             # Filtered PR reviews
```

External user content is marked as `[filtered]` to prevent prompt injection attacks.

### Org Member Cache

Org membership is cached in `.ignore/org-members.txt` (survives reboots, unlike /tmp). The cache is required for `run.sh` to start — regenerate with `setup.sh` if missing.

### Trusted Reviewers Allowlist

When running with an external GitHub account that can't see private org membership:

```bash
cd scripts
cp trusted-reviewers.txt.example trusted-reviewers.txt
# Add one trusted username per line
```

### Other Security Measures

- **Dependency restrictions**: Pre-commit hook prevents bot from updating dependencies
- **Bot permissions**: Uses `--dangerously-skip-permissions` for autonomous operation
- **Review differentiation**: Review skill rejects fixes that aren't materially different from previous failed attempts

See [SECURITY.md](SECURITY.md) for complete guidelines.

## Archiving

When the branch changes between runs, previous state is automatically archived:

```
brave-core-bot/archive/
  └── 2026-01-30-old-branch/
      ├── prd.json
      └── progress.txt
```

## Project Structure

```
brave-core-bot/
├── README.md                  # This file
├── CLAUDE.md                  # Claude agent instructions
├── BEST-PRACTICES.md          # Index of all best practices
├── SECURITY.md                # Security guidelines
├── LICENSE                    # MPL-2.0 license
├── setup.sh                   # Install hooks, validate config, create caches
├── run.sh                     # Main entry point (iterations, TUI mode)
├── check-should-continue.sh   # Check if bot should continue iterating
├── reset-run-state.sh         # Reset run state between runs
├── sync-skills.sh             # Symlink skills to src/brave
├── sync-best-practices.sh     # Symlink best practices to src/brave
├── prd.json                   # Product requirements (gitignored)
├── prd.example.json           # Example PRD template
├── run-state.json             # Run state tracking (gitignored)
├── run-state.example.json     # Example run state template
├── progress.txt               # Progress log (gitignored)
├── progress.example.txt       # Example progress template
├── .ignore/
│   └── org-members.txt        # Cached org members (security, gitignored)
├── .claude/
│   └── skills/                # Claude Code skills (20 skills)
│       ├── prd/               # PRD generation
│       ├── prd-json/          # PRD to JSON converter
│       ├── prd-clean/         # Archive merged/invalid stories
│       ├── add-backlog-to-prd/  # Fetch issues from GitHub
│       ├── commit/            # Commit without attribution
│       ├── pr/                # Create pull requests
│       ├── review/            # Code review (local + PR mode)
│       ├── review-prs/        # Batch PR review with caching
│       ├── check-best-practices/  # Audit diff against best practices
│       ├── impl-review/       # Implement review feedback
│       ├── rebase-downstream/ # Rebase dependent branches
│       ├── clean-branches/    # Delete merged branches
│       ├── preflight/         # Pre-review checks
│       ├── check-upstream-flake/  # LUCI flakiness analysis
│       ├── make-ci-green/     # Retry/analyze failed CI
│       ├── top-crashers/      # Crash analysis
│       ├── uplift/            # Cherry-pick to release branches
│       ├── check-milestones/  # Milestone status
│       ├── update-best-practices/ # Merge upstream Chromium guidelines
│       └── learnable-pattern-search/  # Analyze PR reviews for patterns
├── docs/                      # Detailed workflow and reference docs
│   ├── best-practices/        # Best practices sub-documents (12 files)
│   ├── workflow-state-machine.md
│   ├── workflow-pending.md
│   ├── workflow-committed.md
│   ├── workflow-pushed.md
│   ├── workflow-merged.md
│   ├── workflow-skipped-invalid.md
│   ├── testing-requirements.md
│   ├── git-repository.md
│   ├── progress-reporting.md
│   ├── run-state-management.md
│   └── learnable-patterns.md
├── hooks/
│   ├── pre-commit             # Target repo hook (blocks dependency updates)
│   └── pre-commit-bot-repo    # Bot repo hook (blocks config file commits)
├── scripts/
│   ├── check-upstream-flake.py  # LUCI Analysis API client
│   ├── top-crashers.py        # Crash data analysis
│   ├── fetch-issue.sh         # Fetch filtered GitHub issues
│   ├── filter-issue-json.sh   # Filter issues to org members
│   ├── filter-pr-reviews.sh   # Filter PR reviews to org members
│   └── trusted-reviewers.txt.example  # Allowlist template
├── logs/                      # Bot run logs
└── tests/
    ├── test-suite.sh          # Automated test suite
    └── README.md              # Test documentation
```

## Troubleshooting

### "Git user not configured"

Run `setup.sh` again or manually configure:
```bash
cd brave-browser/src/brave
git config user.name "netzenbot"
git config user.email "netzenbot@brave.com"
```

### "Pre-commit hook blocks my commit"

If the `netzenbot` account is trying to modify dependencies — this is intentional. Use existing libraries or a different git account.

### "Org members cache missing"

Run `setup.sh` to regenerate `.ignore/org-members.txt`, or manually:
```bash
gh api /orgs/brave/members --paginate --jq '.[].login' > .ignore/org-members.txt
```

### "Tests are taking too long"

Expected. The bot uses `run_in_background: true` and high timeouts (1-2 hours) for long operations.

### "Build failures after sync"

The bot will automatically rebase and re-sync:
```bash
git fetch
git rebase origin/master
npm run sync -- --no-history
```

## Contributing

When adding new patterns or learnings, see [docs/learnable-patterns.md](docs/learnable-patterns.md) for guidance on where each type of pattern belongs.

## License

This project is licensed under the Mozilla Public License 2.0 (MPL-2.0). See the [LICENSE](LICENSE) file for details.

## Support

For issues or questions:
- Check `progress.txt` for detailed logs
- Review `CLAUDE.md` for agent behavior
- Verify configuration with `./setup.sh`
- Run `./tests/test-suite.sh` to validate setup
