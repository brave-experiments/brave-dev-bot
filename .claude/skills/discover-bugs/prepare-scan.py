#!/usr/bin/env python3
"""Phase 1 pre-work for the discover-bugs skill.

Zero-LLM candidate selection for a bounded static bug scan of the target
repository. Selects source files that changed since the last scan (or over a
recent window), writes one subagent prompt file per chunk, and emits a small
manifest. The main LLM session only orchestrates — it never sees file contents.

Usage:
    python3 prepare-scan.py [--since-cache | --commits N | --days N]
                            [--max-files N] [--files-per-chunk N] [--auto]

Selection precedence (highest first):
    --commits N      diff HEAD~N..HEAD
    --days N         files touched by commits in the last N days
    --since-cache    diff <lastScanSha>..HEAD   (default; falls back to --days 7)
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_BOT_DIR = os.path.normpath(os.path.join(_SCRIPT_DIR, "..", "..", ".."))
sys.path.insert(0, os.path.join(_BOT_DIR, "scripts"))

from lib.load_config import load_config, require_config, get_config

# --- config -----------------------------------------------------------------
_config = load_config()
ISSUE_REPO = require_config(_config, "project.issueRepository")


def _resolve_target(rel):
    """Match run.sh: absolute paths as-is, else relative to the bot dir's parent."""
    if os.path.isabs(rel):
        return os.path.normpath(rel)
    return os.path.normpath(os.path.join(_BOT_DIR, "..", rel))


TARGET_REPO_PATH = _resolve_target(require_config(_config, "project.targetRepoPath"))
CACHE_PATH = os.path.join(_BOT_DIR, ".ignore", "discover-bugs-cache.json")

# Source extensions worth scanning for logic/lifetime bugs.
SOURCE_EXTS = {".cc", ".cpp", ".cxx", ".mm", ".m", ".h", ".hpp", ".ts", ".tsx", ".js"}
# Paths/patterns to skip — tests and generated/vendored trees are low signal.
SKIP_SUBSTR = ("/test/", "/tests/", "/third_party/", "/node_modules/", "/gen/")
SKIP_SUFFIX = ("_unittest.cc", "_browsertest.cc", "_unittest.mm", ".test.ts", ".test.tsx")

DEFAULT_MAX_FILES = 40
DEFAULT_FILES_PER_CHUNK = 5

# Bug-class rubric handed to every subagent. Focused on the classes that
# actually recur in Brave/Chromium C++ (the US-005 UAF was class #1).
RUBRIC = """\
Scan ONLY for high-confidence, concrete defects in the classes below. Do NOT
report style, naming, or subjective design preferences.

1. Lifetime / use-after-free: dangling `raw_ptr`/`raw_ref`, pointers outliving
   their owner, missing `RegisterWillDetach`/unsubscribe on teardown, capturing
   `this`/refs in callbacks that outlive the object, iterator invalidation.
2. Threading / sequence: cross-sequence access without posting, missing
   `SEQUENCE_CHECKER`, data races on shared state, blocking the UI thread.
3. Null / bounds: unchecked deref of a pointer that can be null (`GetFoo()`
   returning null, `WeakPtr` used after invalidation), off-by-one / OOB index.
4. Mojo / IPC: trusting a renderer-supplied value without validation, missing
   `mojo::ReportBadMessage`, lifetime of self-owned receivers.
5. Uninitialized / resource: uninitialized member read, leaked handle/fd,
   missing `Close()`/`Release()` on an error path.

For each finding you MUST be able to point to the exact line and explain the
concrete failure (what input/state triggers it, what goes wrong). If you are
not confident it is a real bug, DROP it — false positives are worse than misses.
"""


def log(msg):
    print(msg, file=sys.stderr)


def git(*args):
    """Read-only git in the target repo. Returns stdout (stripped) or ''."""
    try:
        out = subprocess.run(
            ["git", "-C", TARGET_REPO_PATH, *args],
            capture_output=True, text=True, timeout=120,
        )
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def load_cache():
    try:
        with open(CACHE_PATH) as f:
            return json.load(f)
    except Exception:
        return {"lastScanSha": None, "lastScanAt": None, "seen": {}}


def is_scannable(path):
    p = path.lower()
    if Path(path).suffix.lower() not in SOURCE_EXTS:
        return False
    if any(s in p for s in SKIP_SUBSTR):
        return False
    if any(p.endswith(s) for s in SKIP_SUFFIX):
        return False
    return True


def resolve_base(args, cache):
    """Return (base_ref, description). base_ref is a git ref or None (window)."""
    if args.commits:
        return f"HEAD~{args.commits}", f"last {args.commits} commits"
    if args.days:
        return None, f"last {args.days} days"
    # --since-cache (default)
    sha = cache.get("lastScanSha")
    if sha and git("rev-parse", "--verify", "--quiet", sha + "^{commit}"):
        return sha, f"since last scan ({sha[:12]})"
    log("No valid last-scan marker — falling back to last 7 days.")
    args.days = 7
    return None, "last 7 days (no cache)"


def changed_files(base_ref, days):
    if base_ref:
        raw = git("diff", "--name-only", f"{base_ref}..HEAD")
    else:
        # files touched by commits within the window
        raw = git("log", f"--since={days} days ago", "--name-only",
                  "--pretty=format:", "HEAD")
    files = sorted({ln.strip() for ln in raw.splitlines() if ln.strip()})
    return [f for f in files if is_scannable(f)]


def file_diff(base_ref, path):
    """Diff for a changed file (bounded); full file if newly added / no base."""
    if base_ref:
        d = git("diff", f"{base_ref}..HEAD", "--", path)
        if d:
            return d
    # new file or window mode — show current content with line numbers
    full = os.path.join(TARGET_REPO_PATH, path)
    try:
        with open(full, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
        return "\n".join(f"{i+1:>5}\t{ln}" for i, ln in enumerate(lines[:1200]))
    except Exception:
        return ""


def build_prompt(chunk_files, base_ref, results_file):
    parts = [
        "You are a C++/TypeScript bug-finding subagent scanning Brave (a Chromium "
        "fork) source for concrete defects.\n",
        RUBRIC,
        "\n--- FILES TO SCAN (unified diffs; scan the changed/new code) ---\n",
    ]
    for path in chunk_files:
        parts.append(f"\n### {path}\n```\n{file_diff(base_ref, path)}\n```\n")
    parts.append(f"""
--- OUTPUT ---
Read the actual source files under {TARGET_REPO_PATH} as needed to CONFIRM each
finding before reporting it. Then write a JSON file to EXACTLY this path:

  {results_file}

Schema:
{{
  "findings": [
    {{
      "file": "<repo-relative path>",
      "line": <int>,
      "bug_class": "lifetime|threading|null-bounds|mojo-ipc|uninitialized",
      "severity": "low|medium|high",
      "confidence": "low|medium|high",
      "title": "<one line>",
      "description": "<what input/state triggers it and what goes wrong>",
      "suggested_fix": "<concrete direction>"
    }}
  ]
}}

Report ONLY confidence:high findings. If you find nothing solid, write
{{"findings": []}}. Do not invent bugs to fill the list.
""")
    return "".join(parts)


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--since-cache", action="store_true")
    g.add_argument("--commits", type=int)
    g.add_argument("--days", type=int)
    ap.add_argument("--max-files", type=int, default=DEFAULT_MAX_FILES)
    ap.add_argument("--files-per-chunk", type=int, default=DEFAULT_FILES_PER_CHUNK)
    ap.add_argument("--auto", action="store_true")
    args = ap.parse_args()

    if not os.path.isdir(os.path.join(TARGET_REPO_PATH, ".git")):
        log(f"Error: target repo not found at {TARGET_REPO_PATH}")
        sys.exit(1)

    cache = load_cache()
    base_ref, base_desc = resolve_base(args, cache)
    head_sha = git("rev-parse", "HEAD")

    files = changed_files(base_ref, args.days)
    total_found = len(files)
    capped = False
    if len(files) > args.max_files:
        files = files[: args.max_files]
        capped = True

    work_dir = tempfile.mkdtemp(prefix="discover-bugs-")
    chunks = []
    for i in range(0, len(files), args.files_per_chunk):
        chunk_files = files[i : i + args.files_per_chunk]
        cid = f"chunk_{i // args.files_per_chunk}"
        prompt_file = os.path.join(work_dir, f"{cid}_prompt.txt")
        results_file = os.path.join(work_dir, f"{cid}_results.json")
        with open(prompt_file, "w") as f:
            f.write(build_prompt(chunk_files, base_ref, results_file))
        chunks.append({"chunk_id": cid, "files": chunk_files,
                       "prompt_file": prompt_file, "results_file": results_file})

    progress = [f"discover-bugs: base = {base_desc}",
                f"discover-bugs: {total_found} scannable file(s) changed"
                + (f", capped to {args.max_files}" if capped else "")
                + f" -> {len(chunks)} chunk(s)"]
    if capped:
        progress.append(f"discover-bugs: WARNING — {total_found - args.max_files} "
                        f"changed file(s) NOT scanned this run (raise --max-files).")
    for line in progress:
        log(line)

    manifest = {
        "work_dir": work_dir,
        "auto_mode": args.auto,
        "issue_repo": ISSUE_REPO,
        "target_repo_path": TARGET_REPO_PATH,
        "base_ref": base_ref,
        "base_desc": base_desc,
        "head_sha": head_sha,
        "cache_path": CACHE_PATH,
        "seen_count": len(cache.get("seen", {})),
        "total_changed": total_found,
        "capped": capped,
        "chunks": chunks,
        "progress_lines": progress,
    }
    manifest_path = os.path.join(work_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    print(json.dumps({"work_dir": work_dir, "manifest": manifest_path}))


if __name__ == "__main__":
    main()
