#!/usr/bin/env python3
"""Intake bot — new-repo flow.

Triggered by an Issue labelled `new-repo` opened via the
`.github/ISSUE_TEMPLATE/new-repo.yml` form. Parses the body, validates,
edits `terraform/projects/<key>/repos.json`, opens a PR.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _intake_lib import (  # noqa: E402
    REPO_ROOT,
    env,
    env_int,
    fail_validation,
    find_pr_for_branch,
    git_commit_and_push,
    git_new_branch,
    issue_comment,
    open_pr,
    parse_checkbox_section,
    parse_issue_body,
    parse_yaml_dropdown_value,
)


SUPPORTED_PACKAGE_TYPES = ["npm", "python", "terraform", "docker", "helm", "nuget", "maven", "huggingface"]
PROJECTS_DIR = REPO_ROOT / "terraform" / "projects"
PLATFORM_PROJECTS_JSON = REPO_ROOT / "terraform" / "platform" / "projects.json"


def project_key_lookup() -> dict[str, str]:
    """Return {project_key: display_name} from platform/projects.json."""
    with PLATFORM_PROJECTS_JSON.open() as f:
        config = json.load(f)
    return {v["key"]: k for k, v in config["projects"].items()}


def main() -> None:
    body = env("ISSUE_BODY")
    issue_number = env_int("ISSUE_NUMBER")
    issue_author = env("ISSUE_AUTHOR")

    sections = parse_issue_body(body)

    # ---- Parse ------------------------------------------------------------
    project_key = parse_yaml_dropdown_value(sections.get("Project", ""))
    application = sections.get("Application name", "").strip()
    package_types = parse_checkbox_section(sections.get("Package types", ""))
    rationale = sections.get("Rationale (optional)", "").strip()

    print(f"Parsed: project={project_key} app={application} types={package_types}")

    # ---- Validate ---------------------------------------------------------
    errors: list[str] = []
    known_projects = project_key_lookup()

    if not project_key:
        errors.append("Project is missing.")
    elif project_key not in known_projects:
        errors.append(
            f"Project key `{project_key}` is not in `platform/projects.json`. "
            f"Known: {sorted(known_projects)}."
        )

    if not application:
        errors.append("Application name is empty.")
    elif not re.match(r"^[a-z0-9][a-z0-9-]{1,30}$", application):
        errors.append(
            f"Application name `{application}` must be lowercase, 2–31 chars, "
            "letters/digits/hyphens only, starting with a letter or digit."
        )

    if not package_types:
        errors.append("No package types selected. At least one required.")
    else:
        bad = [t for t in package_types if t not in SUPPORTED_PACKAGE_TYPES]
        if bad:
            errors.append(
                f"Unsupported package type(s): {bad}. "
                f"Supported: {SUPPORTED_PACKAGE_TYPES}."
            )

    # If project exists, also check the application isn't already there
    if project_key in known_projects and application:
        repos_json = PROJECTS_DIR / project_key / "repos.json"
        if repos_json.exists():
            with repos_json.open() as f:
                cfg = json.load(f)
            existing_apps = [a["name"] for a in cfg.get("applications", [])]
            if application in existing_apps:
                errors.append(
                    f"Application `{application}` already exists in "
                    f"`projects/{project_key}/repos.json`."
                )

    if errors:
        fail_validation(issue_number, errors)

    # ---- Branch first (so we operate on the right tree if resuming) ------
    branch = f"intake/repo/{issue_number}"
    git_new_branch(branch)

    # ---- Edit repos.json --------------------------------------------------
    repos_json = PROJECTS_DIR / project_key / "repos.json"
    with repos_json.open() as f:
        cfg = json.load(f)
    apps = cfg.setdefault("applications", [])
    if not any(a.get("name") == application for a in apps):
        apps.append({"name": application, "package_types": package_types})
        with repos_json.open("w") as f:
            json.dump(cfg, f, indent=2)
            f.write("\n")
        print(f"Edited {repos_json}")
    else:
        print(f"{repos_json} already contains `{application}` — leaving as-is")

    # ---- Commit + push (no-op if previous run already did this) ----------
    git_commit_and_push(
        message=(
            f"intake: add `{application}` to project `{project_key}`\n\n"
            f"Package types: {', '.join(package_types)}\n"
            f"Requested by @{issue_author} (closes #{issue_number})"
        ),
        branch=branch,
    )

    # ---- If a PR already exists for this branch, reuse it ----------------
    existing = find_pr_for_branch(branch)
    if existing:
        print(f"PR already open for {branch}: {existing.get('url')}")
        issue_comment(
            issue_number,
            f"Intake PR already exists: {existing.get('url')}\n\n"
            "Re-trigger absorbed (no duplicate PR opened).",
        )
        return

    pr_body_lines = [
        f"Resolves #{issue_number} — auto-generated from the `new-repo` Issue form.",
        "",
        f"**Project:** `{project_key}` ({known_projects[project_key]})",
        f"**Application:** `{application}`",
        f"**Package types:** {', '.join(package_types)}",
        f"**Requested by:** @{issue_author}",
    ]
    if rationale:
        pr_body_lines += ["", "**Rationale:**", rationale]
    pr_body_lines += [
        "",
        "After this merges, `apply.yml` will create the corresponding "
        "local/remote/virtual repositories in JFrog for every (package_type × stage) "
        "combination. The PR Validate workflow will post the full plan in a comment below.",
    ]

    pr_url = open_pr(
        branch=branch,
        title=f"[intake] new repo: {project_key}/{application}",
        body="\n".join(pr_body_lines),
        labels=["intake", "new-repo"],
    )
    print(f"PR opened: {pr_url}")
    issue_comment(
        issue_number,
        f"Intake PR opened: {pr_url}\n\n"
        "CODEOWNERS will be auto-requested for review. The plan posts there shortly.",
    )


if __name__ == "__main__":
    main()
