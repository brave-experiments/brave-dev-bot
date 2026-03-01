#!/usr/bin/env python3
"""Select the next task to work on from prd.json using deterministic rules.

Reads prd.json and run-state.json, applies filtering and tier-based selection,
and outputs the selected story as JSON to stdout.

Exit codes:
  0 - Story selected (JSON output on stdout)
  1 - No candidates remain (run complete)
  2 - Error
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

TIER_URGENT = 1  # pushed + lastActivityBy == "reviewer"
TIER_HIGH = 2  # committed
TIER_MEDIUM = 3  # pushed + lastActivityBy != "reviewer"
TIER_NORMAL = 4  # pending
TIER_LOW = 5  # merged (needs recheck)

TIER_NAMES = {
    TIER_URGENT: "URGENT",
    TIER_HIGH: "HIGH",
    TIER_MEDIUM: "MEDIUM",
    TIER_NORMAL: "NORMAL",
    TIER_LOW: "LOW",
}

# Sentinel for missing timestamps (sorts before everything = oldest)
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


def parse_iso(ts):
    """Parse an ISO timestamp string, returning EPOCH if missing/invalid."""
    if not ts:
        return EPOCH
    try:
        # Handle Z suffix
        ts = ts.replace("Z", "+00:00")
        return datetime.fromisoformat(ts)
    except (ValueError, TypeError):
        return EPOCH


def now_iso():
    """Return current UTC time as ISO string."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def assign_tier(story):
    """Assign a priority tier to a story based on its status and lastActivityBy."""
    status = story.get("status", "pending")
    last_activity = story.get("lastActivityBy")

    if status == "pushed":
        if last_activity == "reviewer":
            return TIER_URGENT
        return TIER_MEDIUM
    elif status == "committed":
        return TIER_HIGH
    elif status == "pending":
        return TIER_NORMAL
    elif status == "merged":
        return TIER_LOW
    # Shouldn't reach here after filtering, but default to NORMAL
    return TIER_NORMAL


def sort_key(story):
    """Generate a sort key for a story within its tier.

    - Pushed stories (tiers 1, 3): sort by lastProcessedDate asc, then priority
    - Merged stories (tier 5): sort by nextMergedCheck asc, then priority
    - Other stories: sort by priority only
    """
    tier = assign_tier(story)
    priority = story.get("priority", 999)

    if story.get("status") == "pushed":
        last_processed = parse_iso(story.get("lastProcessedDate"))
        return (tier, last_processed, priority)
    elif story.get("status") == "merged":
        next_check = parse_iso(story.get("nextMergedCheck"))
        return (tier, next_check, priority)
    else:
        return (tier, EPOCH, priority)


def filter_stories(stories, run_state):
    """Apply all filtering rules to get candidate stories."""
    checked = set(run_state.get("storiesCheckedThisRun", []))
    skip_pushed = run_state.get("skipPushedTasks", False)
    enable_merge_backoff = run_state.get("enableMergeBackoff", True)
    merge_backoff_ids = run_state.get("mergeBackoffStoryIds")
    now = datetime.now(timezone.utc)

    candidates = []
    for story in stories:
        sid = story.get("id", "")
        status = story.get("status", "pending")

        # Filter 2.1: Terminal status exclusion
        if status in ("skipped", "invalid"):
            continue
        if status == "merged" and story.get("mergedCheckFinalState") is True:
            continue

        # Filter 2.2: Merged story backoff filtering
        if status == "merged":
            if not enable_merge_backoff:
                continue
            if merge_backoff_ids is not None and sid not in merge_backoff_ids:
                continue
            next_check = story.get("nextMergedCheck")
            if next_check:
                next_check_dt = parse_iso(next_check)
                if next_check_dt > now:
                    continue

        # Filter 2.3: Run state filtering
        if sid in checked:
            continue
        if skip_pushed and status == "pushed":
            continue

        candidates.append(story)

    return candidates


def llm_select(candidates, extra_prompt):
    """Use Claude CLI (haiku) to interpret extra_prompt and select a story."""
    summary_lines = []
    for s in candidates:
        summary_lines.append(
            f'- {s.get("id")}: "{s.get("title")}" '
            f"(status: {s.get('status')}, priority: {s.get('priority')})"
        )
    summary = "\n".join(summary_lines)

    prompt = (
        f"Given these candidate stories:\n{summary}\n\n"
        f"And this user request: {extra_prompt}\n\n"
        f"Which story should be selected? Reply with ONLY the story ID "
        f"(e.g., US-003). Nothing else."
    )

    try:
        result = subprocess.run(
            ["claude", "--print", "--model", "haiku", prompt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        response = result.stdout.strip()
        # Extract US-XXX pattern from response
        match = re.search(r"US-\d+", response)
        if match:
            selected_id = match.group(0)
            valid_ids = {s.get("id") for s in candidates}
            if selected_id in valid_ids:
                return selected_id
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass

    return None


def update_run_state(run_state_path, run_state, story_id):
    """Add story ID to storiesCheckedThisRun in run-state.json."""
    checked = run_state.get("storiesCheckedThisRun", [])
    if story_id not in checked:
        checked.append(story_id)
    run_state["storiesCheckedThisRun"] = checked

    with open(run_state_path, "w") as f:
        json.dump(run_state, f, indent=2)
        f.write("\n")


def update_prd(prd_path, prd, story, iteration_log):
    """Update story in prd.json: lastProcessedDate, iterationLogs."""
    # Set lastProcessedDate for pushed stories
    if story.get("status") == "pushed":
        story["lastProcessedDate"] = now_iso()

    # Append iteration log path
    if iteration_log:
        logs = story.get("iterationLogs", [])
        logs.append(iteration_log)
        story["iterationLogs"] = logs

    with open(prd_path, "w") as f:
        json.dump(prd, f, indent=2)
        f.write("\n")


def main():
    parser = argparse.ArgumentParser(description="Select next task from prd.json")
    parser.add_argument("--prd", help="Path to prd.json")
    parser.add_argument("--run-state", help="Path to run-state.json")
    parser.add_argument("--iteration-log", help="Log path to record in story")
    parser.add_argument(
        "--extra-prompt", default="", help="Extra prompt for LLM selection"
    )
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    bot_dir = os.path.dirname(script_dir)

    prd_path = args.prd or os.path.join(bot_dir, "prd.json")
    run_state_path = args.run_state or os.path.join(bot_dir, "run-state.json")

    # Read prd.json
    try:
        with open(prd_path) as f:
            prd = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"Error reading prd.json: {e}", file=sys.stderr)
        return 2

    # Read run-state.json
    try:
        with open(run_state_path) as f:
            run_state = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"Error reading run-state.json: {e}", file=sys.stderr)
        return 2

    stories = prd.get("userStories", [])
    if not stories:
        print(json.dumps({"selected": False, "reason": "No stories in prd.json"}))
        return 1

    # Apply filters
    candidates = filter_stories(stories, run_state)

    if not candidates:
        print(
            json.dumps(
                {"selected": False, "reason": "No candidates remain after filtering"}
            )
        )
        return 1

    # Selection
    selected = None

    # Try LLM-assisted selection if extra prompt provided
    if args.extra_prompt.strip():
        llm_choice = llm_select(candidates, args.extra_prompt)
        if llm_choice:
            selected = next((s for s in candidates if s.get("id") == llm_choice), None)

    # Fall back to deterministic tier-based selection
    if not selected:
        candidates.sort(key=sort_key)
        selected = candidates[0]

    story_id = selected.get("id", "?")
    status = selected.get("status", "pending")
    tier = assign_tier(selected)

    # Update run-state.json
    update_run_state(run_state_path, run_state, story_id)

    # Update prd.json
    update_prd(prd_path, prd, selected, args.iteration_log)

    # Output result
    result = {
        "selected": True,
        "storyId": story_id,
        "status": status,
        "tier": tier,
        "tierName": TIER_NAMES.get(tier, "UNKNOWN"),
        "title": selected.get("title", ""),
        "priority": selected.get("priority"),
        "candidateCount": len(candidates),
    }
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
