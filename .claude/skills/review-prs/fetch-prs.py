#!/usr/bin/env python3
"""Fetch and filter brave/brave-core PRs for review.

Handles all PR fetching, filtering, and cache checking in one script
so the LLM doesn't burn tokens on this logic.

Usage: fetch-prs.py [days|page<N>|#<PR>] [open|closed|all]

Examples:
  fetch-prs.py              # Default: 5 days, open PRs
  fetch-prs.py 3            # Last 3 days, open PRs
  fetch-prs.py page2        # Page 2 (PRs 21-40), open PRs
  fetch-prs.py 7 closed     # Last 7 days, closed PRs
  fetch-prs.py page1 all    # Page 1, all states
  fetch-prs.py #12345       # Single PR by number
  fetch-prs.py 12345        # Single PR by number (large numbers treated as PR#)

Output: JSON with "prs" array and "summary" stats.
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone


CACHE_PATH = ".ignore/review-prs-cache.json"
SKIP_PREFIXES = ["CI run for", "Backport", "Update l10n"]
SKIP_CONTAINS = ["uplift to", "Just to test CI"]


def parse_args():
    mode = "days"
    days = 5
    page = None
    pr_number = None
    state = "open"

    for arg in sys.argv[1:]:
        if arg.startswith("#"):
            mode = "single"
            pr_number = int(arg[1:])
        elif arg.startswith("page"):
            mode = "page"
            page = int(arg[4:])
        elif arg in ("open", "closed", "all"):
            state = arg
        else:
            try:
                num = int(arg)
                # Large numbers (>365) are PR numbers, not day counts
                if num > 365:
                    mode = "single"
                    pr_number = num
                else:
                    days = num
            except ValueError:
                pass

    return mode, days, page, pr_number, state


def fetch_single_pr(pr_number):
    fields = "number,title,updatedAt,author,isDraft,headRefOid"
    result = subprocess.run(
        [
            "gh", "pr", "view", str(pr_number),
            "--repo", "brave/brave-core",
            "--json", fields,
        ],
        capture_output=True, text=True, check=True,
    )
    return [json.loads(result.stdout)]


def fetch_prs(mode, days, page, pr_number, state):
    if mode == "single":
        return fetch_single_pr(pr_number)

    fields = "number,title,updatedAt,author,isDraft,headRefOid"
    base_cmd = [
        "gh", "pr", "list", "--repo", "brave/brave-core",
        "--state", state, "--json", fields,
    ]

    if mode == "page":
        limit = page * 20
        result = subprocess.run(
            base_cmd + ["--limit", str(limit)],
            capture_output=True, text=True, check=True,
        )
        prs = json.loads(result.stdout)
        prs.sort(key=lambda p: p.get("updatedAt", ""), reverse=True)
        start = (page - 1) * 20
        return prs[start:start + 20]
    else:
        result = subprocess.run(
            base_cmd + ["--limit", "200"],
            capture_output=True, text=True, check=True,
        )
        prs = json.loads(result.stdout)
        # Sort by updatedAt descending (newest first) since --sort is
        # not available in all gh versions
        prs.sort(key=lambda p: p.get("updatedAt", ""), reverse=True)
        return prs


def load_cache():
    try:
        with open(CACHE_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def should_skip_title(title):
    for prefix in SKIP_PREFIXES:
        if title.startswith(prefix):
            return True
    for pattern in SKIP_CONTAINS:
        if pattern in title:
            return True
    return False


def get_cutoff(mode, days, cache):
    """Determine the cutoff time for filtering PRs.

    Uses the last successful run timestamp from the cache if available,
    falling back to N days ago. This prevents gaps if a cron run is missed.
    """
    if mode != "days":
        return None

    last_run = cache.get("_last_run")
    if last_run:
        return datetime.fromisoformat(last_run)

    return datetime.now(timezone.utc) - timedelta(days=days)


def filter_prs(prs, mode, days, cache):
    cutoff = get_cutoff(mode, days, cache)

    to_review = []
    skipped_filtered = 0
    skipped_cached = 0

    for pr in prs:
        if pr.get("isDraft"):
            skipped_filtered += 1
            continue

        if should_skip_title(pr.get("title", "")):
            skipped_filtered += 1
            continue

        if cutoff and mode == "days":
            updated = datetime.fromisoformat(
                pr["updatedAt"].replace("Z", "+00:00")
            )
            if updated < cutoff:
                skipped_filtered += 1
                continue

        pr_num = str(pr["number"])
        head_sha = pr.get("headRefOid", "")
        if cache.get(pr_num) == head_sha:
            skipped_cached += 1
            continue

        to_review.append(pr)

    return to_review, skipped_filtered, skipped_cached


def main():
    mode, days, page, pr_number, state = parse_args()
    prs = fetch_prs(mode, days, page, pr_number, state)

    if mode == "single":
        # Skip all filtering for single PR review
        to_review = prs
        skipped_filtered = 0
        skipped_cached = 0
    else:
        cache = load_cache()
        to_review, skipped_filtered, skipped_cached = filter_prs(
            prs, mode, days, cache
        )

    output = {
        "prs": [
            {
                "number": pr["number"],
                "title": pr["title"],
                "headRefOid": pr["headRefOid"],
                "author": pr.get("author", {}).get("login", "unknown"),
            }
            for pr in to_review
        ],
        "summary": {
            "total_fetched": len(prs),
            "to_review": len(to_review),
            "skipped_filtered": skipped_filtered,
            "skipped_cached": skipped_cached,
        },
    }

    json.dump(output, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
