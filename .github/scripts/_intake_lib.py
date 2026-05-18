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


def issue_add_label(issue_number: int, label: str) -> None:
    gh("issue", "edit", str(issue_number), "--add-label", label, check=False)


def open_pr(branch: str, title: str, body: str, labels: list[str]) -> str:
    """Create a PR against main from the given branch. Returns the PR URL."""
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
    git("checkout", "-b", name)


def git_commit_and_push(message: str, branch: str) -> None:
    git("add", "-A")
    git("commit", "-m", message)
    git("push", "-u", "origin", branch)


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
