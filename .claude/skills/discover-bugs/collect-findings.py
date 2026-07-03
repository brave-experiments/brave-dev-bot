#!/usr/bin/env python3
"""Phase 3 collection for the discover-bugs skill.

Zero-LLM. Reads all subagent result files, applies the confidence gate,
deduplicates against previously-reported findings and open ai-generated
issues, then EITHER writes a local report (default) OR files GitHub issues
labeled `ai-generated` (--file-issues). Updates the scan cache either way.

Usage:
    python3 collect-findings.py --work-dir DIR [--file-issues]

Default is local-report-only: NO external writes until a human has reviewed
the scanner's false-positive rate. --file-issues flips on issue creation.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_BOT_DIR = os.path.normpath(os.path.join(_SCRIPT_DIR, "..", "..", ".."))
sys.path.insert(0, os.path.join(_BOT_DIR, "scripts"))

from lib.load_config import load_config, require_config, get_config

_config = load_config()
ISSUE_REPO = require_config(_config, "project.issueRepository")
AI_LABEL = "ai-generated"
LOGS_DIR = os.path.join(_BOT_DIR, "logs")


def log(msg):
    print(msg, file=sys.stderr)


def fingerprint(f):
    """Stable id for a finding: file + class + normalized title."""
    title = re.sub(r"\s+", " ", (f.get("title") or "").strip().lower())
    key = f"{f.get('file','')}|{f.get('bug_class','')}|{title}"
    return hashlib.sha1(key.encode()).hexdigest()[:16]


def load_manifest(work_dir):
    with open(os.path.join(work_dir, "manifest.json")) as f:
        return json.load(f)


def load_cache(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {"lastScanSha": None, "lastScanAt": None, "seen": {}}


def save_cache(path, cache):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(cache, f, indent=2)


def open_issue_titles():
    """Titles of currently-open ai-generated issues, for cross-run dedup."""
    try:
        out = subprocess.run(
            ["gh", "issue", "list", "--repo", ISSUE_REPO, "--label", AI_LABEL,
             "--state", "open", "--limit", "200", "--json", "title"],
            capture_output=True, text=True, timeout=60,
        )
        if out.returncode == 0:
            return {re.sub(r"\s+", " ", i["title"].strip().lower())
                    for i in json.loads(out.stdout or "[]")}
    except Exception:
        pass
    return set()


def collect_results(manifest):
    findings = []
    for chunk in manifest["chunks"]:
        rf = chunk["results_file"]
        if not os.path.exists(rf):
            log(f"discover-bugs: no result file for {chunk['chunk_id']} (subagent skipped?)")
            continue
        try:
            with open(rf) as f:
                data = json.load(f)
            for item in data.get("findings", []):
                findings.append(item)
        except Exception as e:
            log(f"discover-bugs: bad result file {rf}: {e}")
    return findings


def issue_body(f, head_sha):
    return f"""**Automated bug scan finding — please confirm before acting.**

This issue was filed by an automated static scan (label `{AI_LABEL}`). It has
not been human-verified. If it is a false positive, close it.

- **File:** `{f.get('file')}:{f.get('line')}`
- **Class:** {f.get('bug_class')}
- **Severity:** {f.get('severity')}  |  **Scanner confidence:** {f.get('confidence')}
- **Scanned commit:** `{(head_sha or '')[:12]}`

**What goes wrong**
{f.get('description','(none)')}

**Suggested direction**
{f.get('suggested_fix','(none)')}
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work-dir", required=True)
    ap.add_argument("--file-issues", action="store_true",
                    help="Create GitHub issues (default: local report only).")
    args = ap.parse_args()

    manifest = load_manifest(args.work_dir)
    cache_path = manifest["cache_path"]
    head_sha = manifest.get("head_sha")
    cache = load_cache(cache_path)
    seen = cache.setdefault("seen", {})

    raw = collect_results(manifest)

    # Confidence gate: v1 keeps only high-confidence.
    gated = [f for f in raw if (f.get("confidence") or "").lower() == "high"]
    dropped_conf = len(raw) - len(gated)

    # Dedup against local seen-list and open ai-generated issues.
    existing_titles = open_issue_titles()
    fresh, dup = [], 0
    for f in gated:
        fp = fingerprint(f)
        title_norm = re.sub(r"\s+", " ", (f.get("title") or "").strip().lower())
        if fp in seen or title_norm in existing_titles:
            dup += 1
            continue
        f["_fp"] = fp
        fresh.append(f)

    log(f"discover-bugs: {len(raw)} raw finding(s); "
        f"{dropped_conf} below high-confidence; {dup} duplicate(s); "
        f"{len(fresh)} fresh.")

    now = datetime.now(timezone.utc).isoformat()
    filed = []

    if args.file_issues:
        for f in fresh:
            title = f"[ai-bug] {f.get('title')}"
            body = issue_body(f, head_sha)
            try:
                out = subprocess.run(
                    ["gh", "issue", "create", "--repo", ISSUE_REPO,
                     "--label", AI_LABEL, "--title", title, "--body", body],
                    capture_output=True, text=True, timeout=90,
                )
                if out.returncode == 0:
                    url = out.stdout.strip()
                    seen[f["_fp"]] = {"issue": url, "reportedAt": now}
                    filed.append(url)
                    log(f"discover-bugs: filed {url}")
                else:
                    log(f"discover-bugs: gh issue create failed: {out.stderr.strip()}")
            except Exception as e:
                log(f"discover-bugs: gh issue create error: {e}")
    else:
        # Local report only. Record fresh findings in seen so we don't re-report
        # them next run even before issues are filed.
        for f in fresh:
            seen[f["_fp"]] = {"issue": None, "reportedAt": now}

    # Always write a local report artifact.
    os.makedirs(LOGS_DIR, exist_ok=True)
    stamp = now.replace(":", "").replace("-", "")[:15]
    report_json = os.path.join(LOGS_DIR, f"discover-bugs-{stamp}.json")
    with open(report_json, "w") as f:
        json.dump({"scanned_at": now, "head_sha": head_sha,
                   "fresh": fresh, "filed": filed,
                   "counts": {"raw": len(raw), "dropped_conf": dropped_conf,
                              "duplicate": dup, "fresh": len(fresh)}},
                  f, indent=2)

    report_md = os.path.join(LOGS_DIR, f"discover-bugs-{stamp}.md")
    with open(report_md, "w") as fh:
        fh.write(f"# Bug scan — {now}\n\nBase: {manifest.get('base_desc')}  |  "
                 f"Commit: {(head_sha or '')[:12]}\n\n")
        if not fresh:
            fh.write("No fresh high-confidence findings.\n")
        for f in fresh:
            link = f" — {seen[f['_fp']]['issue']}" if seen.get(f["_fp"], {}).get("issue") else ""
            fh.write(f"## {f.get('title')}{link}\n"
                     f"- `{f.get('file')}:{f.get('line')}` · {f.get('bug_class')} · "
                     f"sev {f.get('severity')}\n- {f.get('description')}\n"
                     f"- Fix: {f.get('suggested_fix')}\n\n")

    # Update cache marker so the next scan starts from here.
    if head_sha:
        cache["lastScanSha"] = head_sha
    cache["lastScanAt"] = now
    save_cache(cache_path, cache)

    mode = "filed as issues" if args.file_issues else "LOCAL REPORT ONLY (no issues filed)"
    log("=" * 60)
    log(f"discover-bugs summary — {mode}")
    log(f"  fresh high-confidence: {len(fresh)}")
    if args.file_issues:
        log(f"  issues created: {len(filed)}")
    log(f"  report: {report_md}")
    log("=" * 60)


if __name__ == "__main__":
    main()
