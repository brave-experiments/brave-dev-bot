#!/usr/bin/env python3
"""Check if prd.json has active stories that need work.

Exit codes:
  0 - There are active stories to work on
  1 - No active stories (all merged/skipped/invalid, or no prd.json)
  2 - Error reading/parsing prd.json
"""

import json
import os
import sys

TERMINAL_STATUSES = {"merged", "skipped", "invalid"}


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    prd_file = os.path.join(script_dir, "prd.json")

    if not os.path.exists(prd_file):
        print("No prd.json found — nothing to work on.")
        return 1

    try:
        with open(prd_file) as f:
            prd = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"Error reading prd.json: {e}")
        return 2

    stories = prd.get("userStories", [])
    if not stories:
        print("prd.json has no user stories — nothing to work on.")
        return 1

    active = [s for s in stories if s.get("status", "pending") not in TERMINAL_STATUSES]

    if not active:
        print(
            f"All {len(stories)} stories are complete (merged/skipped/invalid) — nothing to work on."
        )
        return 1

    # Summarize what's active
    by_status = {}
    for s in active:
        status = s.get("status", "pending")
        by_status.setdefault(status, []).append(s.get("id", "?"))

    parts = []
    for status, ids in sorted(by_status.items()):
        parts.append(f"  {status}: {', '.join(ids)}")

    print(f"{len(active)} active story/stories found:")
    print("\n".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
