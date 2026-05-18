#!/usr/bin/env python3
"""Intake bot — new-project flow.

Triggered by an Issue labelled `new-project` opened via the
`.github/ISSUE_TEMPLATE/new-project.yml` form. Parses, validates,
edits `terraform/platform/projects.json`, scaffolds
`terraform/projects/<key>/`, updates `.github/CODEOWNERS`, and opens a PR.
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
    git_commit_and_push,
    git_new_branch,
    issue_comment,
    open_pr,
    parse_issue_body,
    parse_yaml_dropdown_value,
)


SUPPORTED_PACKAGE_TYPES = ["npm", "python", "terraform", "docker", "helm"]
PLATFORM_PROJECTS_JSON = REPO_ROOT / "terraform" / "platform" / "projects.json"
PROJECTS_DIR = REPO_ROOT / "terraform" / "projects"
CODEOWNERS = REPO_ROOT / ".github" / "CODEOWNERS"


# ---------------------------------------------------------------------------
# Application-line parser
# ---------------------------------------------------------------------------

def parse_applications(raw: str) -> tuple[list[dict], list[str]]:
    """Parse the 'Initial applications and package types' field.

    Expected format (one per line):
        payment: npm, python, docker
        catalog: npm, helm

    Returns (apps, errors). Apps are [{"name": ..., "package_types": [...]}].
    Empty / whitespace-only input returns ([], []).
    """
    apps: list[dict] = []
    errors: list[str] = []
    if not raw.strip():
        return apps, errors

    seen_names: set[str] = set()
    for line_num, line in enumerate(raw.splitlines(), start=1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            errors.append(f"Application line {line_num} `{line}` is missing the `:` separator.")
            continue
        name, types_str = line.split(":", 1)
        name = name.strip().lower()
        if not re.match(r"^[a-z0-9][a-z0-9-]{1,30}$", name):
            errors.append(f"Application line {line_num}: name `{name}` is invalid.")
            continue
        if name in seen_names:
            errors.append(f"Application `{name}` is listed twice.")
            continue
        seen_names.add(name)
        types = [t.strip().lower() for t in types_str.split(",") if t.strip()]
        bad = [t for t in types if t not in SUPPORTED_PACKAGE_TYPES]
        if bad:
            errors.append(
                f"Application `{name}`: unsupported package_types {bad}. "
                f"Supported: {SUPPORTED_PACKAGE_TYPES}."
            )
            continue
        if not types:
            errors.append(f"Application `{name}`: no package types listed.")
            continue
        apps.append({"name": name, "package_types": types})
    return apps, errors


# ---------------------------------------------------------------------------
# CODEOWNERS edit
# ---------------------------------------------------------------------------

def add_codeowners_line(project_key: str, owning_team: str) -> None:
    """Insert a CODEOWNERS rule for the new project layer.

    Pattern matches what existed for cmrc/vntg/wlt:
      /terraform/projects/<key>/   <owning_team>  @MCodeVisionary/platform-admins
    """
    line_padding_target = 40
    path = f"/terraform/projects/{project_key}/"
    pad = max(line_padding_target - len(path), 1)
    new_rule = f"{path}{' ' * pad}{owning_team} @MCodeVisionary/platform-admins\n"

    with CODEOWNERS.open() as f:
        content = f.read()

    # Skip if already present
    if path in content:
        print(f"CODEOWNERS already contains {path}; skipping insert.")
        return

    # Insert just after the last existing /terraform/projects/<key>/ line if any,
    # otherwise append.
    pattern = re.compile(r"(^/terraform/projects/[a-z0-9-]+/.+\n)", re.MULTILINE)
    matches = list(pattern.finditer(content))
    if matches:
        last = matches[-1]
        insertion_point = last.end()
        new_content = content[:insertion_point] + new_rule + content[insertion_point:]
    else:
        new_content = content.rstrip() + "\n\n" + new_rule

    with CODEOWNERS.open("w") as f:
        f.write(new_content)
    print(f"CODEOWNERS updated with rule for {project_key}.")


# ---------------------------------------------------------------------------
# Project-layer scaffolding
# ---------------------------------------------------------------------------

# Tags to substitute. Kept simple to keep the templates readable inline.
TF_MAIN = '''module "repos" {{
  source = "git::https://github.com/MCodeVisionary/jfrog-platform-onboarding-tf.git//terraform/modules/project-repos?ref=project-repos/v1.1.0"

  jfrog_url          = var.jfrog_url
  jfrog_access_token = var.jfrog_access_token
  project_key        = "{project_key}"
  repos_config_file  = "${{path.module}}/repos.json"
}}
'''

TF_PROVIDERS = '''provider "artifactory" {
  url          = var.jfrog_url
  access_token = var.jfrog_access_token
}
'''

TF_VARIABLES = '''variable "jfrog_url" {
  description = "Base URL of the JFrog Platform instance."
  type        = string
}

variable "jfrog_access_token" {
  description = "JFrog Platform access token. Pass via TF_VAR_jfrog_access_token."
  type        = string
  sensitive   = true
}
'''

TF_VERSIONS = '''terraform {
  required_version = ">= 1.3.0"

  required_providers {
    artifactory = {
      source  = "jfrog/artifactory"
      version = "~> 12.5"
    }
  }
}
'''

TF_OUTPUTS = '''output "project_key" {
  value = module.repos.project_key
}

output "local_repository_count" {
  value = module.repos.local_repository_count
}

output "remote_repository_count" {
  value = module.repos.remote_repository_count
}

output "virtual_repository_count" {
  value = module.repos.virtual_repository_count
}

output "total_repository_count" {
  value = module.repos.total_repository_count
}

output "virtual_dev_repo_urls" {
  value = module.repos.virtual_dev_repo_urls
}
'''

TF_BACKEND = '''# ---------------------------------------------------------------------------
# Remote state — JFrog Artifactory `terraformbackend`-type repo.
# Locking disabled (see platform/backend.tf for rationale).
# Auth via TF_HTTP_USERNAME + TF_HTTP_PASSWORD env vars.
# ---------------------------------------------------------------------------
terraform {{
  backend "http" {{
    address       = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/projects/{project_key}/terraform.tfstate"
    update_method = "PUT"
  }}
}}
'''


def scaffold_project_layer(project_key: str, applications: list[dict]) -> None:
    layer_dir = PROJECTS_DIR / project_key
    layer_dir.mkdir(parents=True, exist_ok=True)

    (layer_dir / "main.tf").write_text(TF_MAIN.format(project_key=project_key))
    (layer_dir / "providers.tf").write_text(TF_PROVIDERS)
    (layer_dir / "variables.tf").write_text(TF_VARIABLES)
    (layer_dir / "versions.tf").write_text(TF_VERSIONS)
    (layer_dir / "outputs.tf").write_text(TF_OUTPUTS)
    (layer_dir / "backend.tf").write_text(TF_BACKEND.format(project_key=project_key))

    repos_json = {"project_key": project_key, "applications": applications}
    with (layer_dir / "repos.json").open("w") as f:
        json.dump(repos_json, f, indent=2)
        f.write("\n")
    print(f"Scaffolded {layer_dir}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    body = env("ISSUE_BODY")
    issue_number = env_int("ISSUE_NUMBER")
    issue_author = env("ISSUE_AUTHOR")

    sections = parse_issue_body(body)

    project_key = sections.get("Project key", "").strip().lower()
    display_name = sections.get("Display name", "").strip()
    description = sections.get("Description", "").strip()
    storage_str = parse_yaml_dropdown_value(sections.get("Storage quota (GiB)", "500"))
    owning_team = sections.get("GitHub team owning this project", "").strip()
    initial_apps_raw = sections.get(
        "(Optional) Initial applications and package types", ""
    )

    apps, app_errors = parse_applications(initial_apps_raw)

    # ---- Validate ---------------------------------------------------------
    errors: list[str] = list(app_errors)

    if not project_key:
        errors.append("Project key is missing.")
    elif not re.match(r"^[a-z][a-z0-9]{2,5}$", project_key):
        errors.append(
            f"Project key `{project_key}` must be lowercase, 3–6 chars, "
            "letters/digits only, starting with a letter."
        )
    else:
        # Already exists?
        with PLATFORM_PROJECTS_JSON.open() as f:
            existing = json.load(f)
        existing_keys = {v["key"] for v in existing["projects"].values()}
        if project_key in existing_keys:
            errors.append(
                f"Project key `{project_key}` already exists in "
                "`platform/projects.json`."
            )
        if (PROJECTS_DIR / project_key).exists():
            errors.append(
                f"`terraform/projects/{project_key}/` directory already exists."
            )

    if not display_name:
        errors.append("Display name is empty.")
    if not description:
        errors.append("Description is empty.")
    if not owning_team:
        errors.append("GitHub team owning this project is empty.")
    elif not re.match(r"^@[\w.-]+/[\w.-]+$", owning_team):
        errors.append(
            f"Owning team `{owning_team}` must look like `@org/team-handle`."
        )
    try:
        max_storage_gib = int(storage_str)
    except ValueError:
        errors.append(f"Storage quota `{storage_str}` is not an integer.")
        max_storage_gib = 500

    if errors:
        fail_validation(issue_number, errors)

    # ---- Apply edits ------------------------------------------------------
    # 1. Add to platform/projects.json
    with PLATFORM_PROJECTS_JSON.open() as f:
        existing = json.load(f)
    existing["projects"][display_name] = {
        "key": project_key,
        "display_name": display_name,
        "description": description,
        "max_storage_gib": max_storage_gib,
        "stages": ["all"],
    }
    with PLATFORM_PROJECTS_JSON.open("w") as f:
        json.dump(existing, f, indent=2)
        f.write("\n")
    print(f"Edited {PLATFORM_PROJECTS_JSON}")

    # 2. Scaffold projects/<key>/
    scaffold_project_layer(project_key, apps)

    # 3. Update CODEOWNERS
    add_codeowners_line(project_key, owning_team)

    # ---- Commit + push + PR ----------------------------------------------
    branch = f"intake/project/{issue_number}"
    git_new_branch(branch)
    git_commit_and_push(
        message=(
            f"intake: create project `{project_key}` ({display_name})\n\n"
            f"Owning team: {owning_team}\n"
            f"Initial apps: {[a['name'] for a in apps] or '(none)'}\n"
            f"Requested by @{issue_author} (closes #{issue_number})"
        ),
        branch=branch,
    )

    pr_body = "\n".join([
        f"Resolves #{issue_number} — auto-generated from the `new-project` Issue form.",
        "",
        f"**Project key:** `{project_key}`",
        f"**Display name:** `{display_name}`",
        f"**Description:** {description}",
        f"**Storage quota:** {max_storage_gib} GiB",
        f"**Owning team:** {owning_team}",
        f"**Initial applications:** "
            + (", ".join(f"`{a['name']}` ({'/'.join(a['package_types'])})" for a in apps) or "_(none — repos.json starts empty)_"),
        f"**Requested by:** @{issue_author}",
        "",
        "**What this PR does:**",
        f"- Adds `{display_name}` to `platform/projects.json`",
        f"- Scaffolds `terraform/projects/{project_key}/` (main.tf, providers.tf, "
        "variables.tf, versions.tf, outputs.tf, backend.tf, repos.json)",
        f"- Adds CODEOWNERS rule routing the new layer to {owning_team}",
        "",
        "After merge: platform layer applies the new project + groups + role "
        f"bindings; the new `projects/{project_key}/` layer applies its repos.",
    ])

    pr_url = open_pr(
        branch=branch,
        title=f"[intake] new project: {project_key} ({display_name})",
        body=pr_body,
        labels=["intake", "new-project"],
    )
    print(f"PR opened: {pr_url}")
    issue_comment(
        issue_number,
        f"Intake PR opened: {pr_url}\n\n"
        "Platform admins will be auto-requested for review. The plans for "
        "both the platform layer and the new project layer will post in the "
        "PR shortly.",
    )


if __name__ == "__main__":
    main()
