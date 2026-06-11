#!/usr/bin/env python3
"""Rebase all open PRs by the bot account onto the upstream default branch.

Reads the bot config, fetches the upstream remote, then for every open PR
authored by the bot (whose branch lives in the PR repo) checks out the branch,
rebases it onto <upstream>/<defaultBranch>, and force-pushes with
--force-with-lease.

Default mode is a dry-run plan. Pass --execute to actually rebase and push.

Usage:
    rebase-bot-prs.py [--execute] [PR_NUMBER ...]

Examples:
    rebase-bot-prs.py                 # plan: fetch + list what would be rebased
    rebase-bot-prs.py --execute       # rebase + force-push every open bot PR
    rebase-bot-prs.py --execute 36966 # only rebase PR #36966
"""

import json
import os
import subprocess
import sys


def run(cmd, cwd=None, check=True, capture=True):
    """Run a command, returning (rc, stdout, stderr)."""
    if not capture:
        sys.stdout.flush()  # keep our prints ordered with the child's live output
    res = subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        capture_output=capture,
    )
    if check and res.returncode != 0:
        out = (res.stdout or "") + (res.stderr or "")
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd)}\n{out}")
    return res.returncode, (res.stdout or "").strip(), (res.stderr or "").strip()


def load_config():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    bot_dir = os.path.realpath(os.path.join(script_dir, "..", "..", ".."))
    with open(os.path.join(bot_dir, "config.json")) as f:
        cfg = json.load(f)
    proj = cfg["project"]
    target = os.path.realpath(os.path.join(bot_dir, proj["targetRepoPath"]))
    return {
        "bot": cfg["bot"]["username"],
        "pr_repo": proj["prRepository"],
        "default_branch": proj.get("defaultBranch", "master"),
        "target_repo": target,
    }


def resolve_remote_for_repo(target, repo):
    """Return the remote whose URL points at `repo` (e.g. brave/brave-core)."""
    _, out, _ = run(["git", "remote", "-v"], cwd=target)
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and (f"{repo}.git" in parts[1] or parts[1].endswith(repo) or f":{repo}" in parts[1] or f"/{repo}" in parts[1]):
            return parts[0]
    return None


def resolve_upstream_remote(target, repo):
    """Prefer a literal `upstream` remote; otherwise the remote tracking `repo`."""
    _, out, _ = run(["git", "remote"], cwd=target)
    remotes = out.splitlines()
    if "upstream" in remotes:
        return "upstream"
    matched = resolve_remote_for_repo(target, repo)
    if matched:
        return matched
    if "origin" in remotes:
        return "origin"
    raise RuntimeError("Could not resolve an upstream remote tracking the PR repo.")


def list_bot_prs(pr_repo, bot):
    _, out, _ = run([
        "gh", "pr", "list",
        "--repo", pr_repo,
        "--author", bot,
        "--state", "open",
        "--json", "number,headRefName,title,isCrossRepository",
        "--limit", "200",
    ])
    return json.loads(out)


def working_tree_clean(target):
    _, out, _ = run(["git", "status", "--porcelain"], cwd=target)
    return out == ""


def current_ref(target):
    _, name, _ = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=target)
    if name == "HEAD":  # detached
        _, sha, _ = run(["git", "rev-parse", "HEAD"], cwd=target)
        return sha
    return name


def main():
    args = sys.argv[1:]
    execute = "--execute" in args
    only = {int(a) for a in args if a.isdigit()}

    cfg = load_config()
    target = cfg["target_repo"]
    pr_repo = cfg["pr_repo"]
    base_branch = cfg["default_branch"]

    if not os.path.isdir(os.path.join(target, ".git")) and not os.path.exists(os.path.join(target, ".git")):
        sys.exit(f"Target repo not found at {target}")

    upstream = resolve_upstream_remote(target, pr_repo)
    pr_remote = resolve_remote_for_repo(target, pr_repo) or upstream

    print(f"Target repo:     {target}")
    print(f"Upstream remote: {upstream} (rebase onto {upstream}/{base_branch})")
    print(f"Push remote:     {pr_remote}")
    print(f"PR repo:         {pr_repo}")
    print(f"Bot:             {cfg['bot']}")
    print()

    prs = list_bot_prs(pr_repo, cfg["bot"])
    if only:
        prs = [p for p in prs if p["number"] in only]

    skipped_forks = [p for p in prs if p["isCrossRepository"]]
    prs = [p for p in prs if not p["isCrossRepository"]]

    for p in skipped_forks:
        print(f"SKIP (fork branch, cannot push): #{p['number']} {p['title']}")

    if not prs:
        print("No eligible open bot PRs to rebase.")
        return

    # Always fetch upstream (and push remote) so master and branch refs are current.
    print(f"Fetching {upstream} ...")
    run(["git", "fetch", upstream], cwd=target, capture=False)
    if pr_remote != upstream:
        print(f"Fetching {pr_remote} ...")
        run(["git", "fetch", pr_remote], cwd=target, capture=False)
    print()

    print(f"{'Will rebase' if not execute else 'Rebasing'} {len(prs)} PR(s) onto {upstream}/{base_branch}:")
    for p in prs:
        print(f"  #{p['number']}  {p['headRefName']}  ({p['title']})")
    print()

    if not execute:
        print("Dry run only. Re-run with --execute to rebase and force-push.")
        return

    if not working_tree_clean(target):
        sys.exit(
            "ERROR: working tree is not clean. Commit, stash, or discard changes "
            "before running --execute. Aborting without touching any branch."
        )

    original = current_ref(target)
    results = []  # (number, branch, status, detail)

    try:
        for p in prs:
            num = p["number"]
            branch = p["headRefName"]
            print(f"\n=== PR #{num}  {branch} ===")
            try:
                # Point a local branch at the remote head and rebase it.
                run(["git", "checkout", "-B", branch, f"{pr_remote}/{branch}"], cwd=target, capture=False)
            except RuntimeError as e:
                results.append((num, branch, "ERROR", f"checkout failed: {e}"))
                continue

            rc, out, err = run(
                ["git", "rebase", f"{upstream}/{base_branch}"],
                cwd=target, check=False,
            )
            if rc != 0:
                # Conflict or other rebase failure — abort and leave PR untouched.
                run(["git", "rebase", "--abort"], cwd=target, check=False)
                detail = (out + "\n" + err).strip().splitlines()
                detail = detail[-1] if detail else "rebase failed"
                results.append((num, branch, "CONFLICT", detail))
                print(f"  CONFLICT — aborted rebase, skipping. ({detail})")
                continue

            rc, out, err = run(
                ["git", "push", "--force-with-lease", pr_remote, branch],
                cwd=target, check=False,
            )
            if rc != 0:
                detail = (out + "\n" + err).strip().splitlines()
                detail = detail[-1] if detail else "push failed"
                results.append((num, branch, "PUSH_FAILED", detail))
                print(f"  PUSH FAILED: {detail}")
                continue

            results.append((num, branch, "REBASED", "force-pushed"))
            print("  REBASED and force-pushed.")
    finally:
        print(f"\nRestoring original branch: {original}")
        run(["git", "checkout", original], cwd=target, check=False, capture=False)

    print("\n========== SUMMARY ==========")
    order = {"REBASED": 0, "CONFLICT": 1, "PUSH_FAILED": 2, "ERROR": 3}
    for num, branch, status, detail in sorted(results, key=lambda r: order.get(r[2], 9)):
        print(f"  [{status}] #{num} {branch} — {detail}")
    rebased = sum(1 for r in results if r[2] == "REBASED")
    print(f"\n{rebased}/{len(results)} rebased and pushed.")
    if any(r[2] != "REBASED" for r in results):
        print("Some PRs need manual attention (conflicts/failures listed above).")


if __name__ == "__main__":
    main()
