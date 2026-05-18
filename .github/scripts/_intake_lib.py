"""Shared helpers for the intake bot.

Parses GitHub Issue Form bodies, runs `gh` CLI commands, and writes back to
the issue. Kept dependency-free (stdlib only) so the GitHub-hosted runner
needs zero extra setup.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


# ---------------------------------------------------------------------------
# Issue body parsing
# ---------------------------------------------------------------------------

def parse_issue_body(body: str) -> dict[str, str]:
    """Parse a GitHub Issue Forms body into a {heading: value} dict.

    Issue Forms render fields as:

        ### Heading

        value text

        ### Next heading

        value text

    Checkbox fields look like:

        ### Heading

        - [x] option A
        - [ ] option B

    For checkbox sections, the value is the raw list (with the "[x]"/" "
    markers preserved). Use `parse_checkbox_section` on it.
    """
    if not body:
        return {}
    sections: dict[str, str] = {}
    # split on lines that start with "### "
    parts = re.split(r"(?m)^###\s+", body)
    # first part is anything before the first heading (usually empty)
    for chunk in parts[1:]:
        # first line is the heading
        lines = chunk.splitlines()
        if not lines:
            continue
        heading = lines[0].strip()
        value = "\n".join(lines[1:]).strip()
        sections[heading] = value
    return sections


def parse_checkbox_section(value: str) -> list[str]:
    """Extract checked options from a checkbox-style field value.

    Returns the labels (text after "[x]") of items that are checked.
    Issue Forms render unchecked checkboxes with a literal "[ ]".
    """
    checked: list[str] = []
    for line in value.splitlines():
        m = re.match(r"\s*-\s*\[(.)\]\s*(.+?)\s*$", line)
        if m and m.group(1).lower() == "x":
            checked.append(m.group(2))
    return checked


def parse_yaml_dropdown_value(value: str) -> str:
    """Issue Forms dropdown values arrive as plain text on their own line.
    This is a no-op aliased name for clarity at call sites."""
    return value.strip()


# ---------------------------------------------------------------------------
# `gh` CLI wrappers
# ---------------------------------------------------------------------------

def gh(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Run the `gh` CLI. GH_TOKEN env var must be set by the workflow."""
    result = subprocess.run(
        ["gh", *args], capture_output=True, text=True, check=False
    )
    if check and result.returncode != 0:
        print(f"::error::gh {' '.join(args)} failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result


def issue_comment(issue_number: int, body: str) -> None:
    gh("issue", "comment", str(issue_number), "--body", body)


# Default colors for the labels the bot relies on. Used by ensure_labels()
# when a label needs to be auto-created on first use.
_DEFAULT_LABEL_COLORS = {
    "intake":          "0e8a16",  # green   — bot-opened PR
    "new-repo":        "1d76db",  # blue    — repo intake
    "new-project":     "5319e7",  # purple  — project intake
    "intake-blocked":  "d93f0b",  # red     — validation failed, needs revision
    "intake-retry":    "fbca04",  # yellow  — user-applied; tells bot to re-run
}


def ensure_labels(labels: list[str]) -> None:
    """Create any missing labels in the repo (idempotent).

    `gh pr create --label X` and `gh issue edit --add-label X` both fail
    hard if X doesn't exist. The bot's first run on a fresh repo would hit
    this every time, so we self-heal: check what exists, create what's
    missing. Safe to call repeatedly.
    """
    # List existing labels once
    r = gh("label", "list", "--json", "name", "--limit", "200", check=False)
    if r.returncode != 0:
        # Non-fatal — fall through and let downstream commands fail with a
        # clearer error if it really matters
        print(f"::warning::could not list labels: {r.stderr}", file=sys.stderr)
        return
    try:
        existing = {item["name"] for item in json.loads(r.stdout or "[]")}
    except Exception:
        existing = set()

    for label in labels:
        if label in existing:
            continue
        color = _DEFAULT_LABEL_COLORS.get(label, "ededed")  # neutral grey fallback
        desc = f"Auto-created by intake bot for label '{label}'"
        cr = gh("label", "create", label, "--color", color, "--description", desc, check=False)
        if cr.returncode == 0:
            print(f"created missing label: {label}")
        elif "already exists" in (cr.stderr or "").lower():
            pass  # raced with another job; fine
        else:
            print(f"::warning::could not create label '{label}': {cr.stderr}", file=sys.stderr)


def issue_add_label(issue_number: int, label: str) -> None:
    ensure_labels([label])
    gh("issue", "edit", str(issue_number), "--add-label", label, check=False)


def open_pr(branch: str, title: str, body: str, labels: list[str]) -> str:
    """Create a PR against main from the given branch. Returns the PR URL."""
    if labels:
        ensure_labels(labels)
    args = [
        "pr", "create",
        "--base", "main",
        "--head", branch,
        "--title", title,
        "--body", body,
    ]
    for label in labels:
        args += ["--label", label]
    r = gh(*args)
    return r.stdout.strip()


# ---------------------------------------------------------------------------
# Git wrappers
# ---------------------------------------------------------------------------

def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(
        ["git", "-C", str(REPO_ROOT), *args],
        capture_output=True, text=True, check=False,
    )
    if check and result.returncode != 0:
        print(f"::error::git {' '.join(args)} failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result


def git_new_branch(name: str) -> None:
    """Check out a branch named `name`. Idempotent: works whether the
    branch is brand new, exists locally, or exists only on the remote.

    Needed because a previous bot run might have left the branch behind
    after a partial failure (push succeeded, PR open failed). On re-trigger
    we want to pick up where we left off, not crash on 'branch already exists'.
    """
    # Already on this branch?
    cur = git("rev-parse", "--abbrev-ref", "HEAD", check=False).stdout.strip()
    if cur == name:
        return
    # Exists locally?
    local = git("rev-parse", "--verify", name, check=False)
    if local.returncode == 0:
        git("checkout", name)
        return
    # Exists on remote?
    git("fetch", "origin", check=False)
    remote = git("ls-remote", "--heads", "origin", name, check=False).stdout.strip()
    if remote:
        git("checkout", "-b", name, f"origin/{name}")
        return
    # Fresh branch
    git("checkout", "-b", name)


def git_commit_and_push(message: str, branch: str) -> None:
    """Commit any pending changes (no-op if working tree clean) and push.

    Idempotent against re-runs: if the previous run already committed and
    pushed the same edits, both commit and push are skipped/no-op'd.
    """
    git("add", "-A")
    status = git("status", "--porcelain", check=False).stdout.strip()
    if status:
        git("commit", "-m", message)
    else:
        print("No changes to commit — working tree clean (likely resuming a previous run)")
    # Push always; if remote already matches, this is a no-op.
    git("push", "-u", "origin", branch, check=False)


def find_pr_for_branch(branch: str) -> dict | None:
    """Return the open PR (any state) for `branch`, or None if no PR exists.
    Used so the bot doesn't try to create a duplicate PR on re-trigger.
    """
    r = gh("pr", "list", "--head", branch, "--state", "all",
           "--json", "url,number,state", check=False)
    try:
        prs = json.loads(r.stdout or "[]")
    except Exception:
        return None
    return prs[0] if prs else None


# ---------------------------------------------------------------------------
# Failure path
# ---------------------------------------------------------------------------

def fail_validation(issue_number: int, errors: list[str]) -> None:
    """Comment the validation errors back on the issue, add intake-blocked
    label, and exit nonzero so the workflow run shows red."""
    bullets = "\n".join(f"- {e}" for e in errors)
    body = (
        "> [!WARNING]\n"
        "> **Intake blocked — request needs revision.**\n\n"
        "The form input failed validation:\n\n"
        f"{bullets}\n\n"
        "Edit the issue body to fix the items above, then add the label "
        "`intake-retry` to retry, or open a fresh issue."
    )
    issue_comment(issue_number, body)
    issue_add_label(issue_number, "intake-blocked")
    print("::error::Validation failed; commented on issue.")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Required env vars
# ---------------------------------------------------------------------------

def env(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        print(f"::error::missing required env var {name}", file=sys.stderr)
        sys.exit(2)
    return v


def env_int(name: str) -> int:
    return int(env(name))
