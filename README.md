# JFrog Platform — Terraform Configuration

Provisions all JFrog Projects, IDP groups, lifecycle stages, and repositories from a single JSON config file (`projects.json`). No repository or project is hardcoded in Terraform — every resource is derived from the JSON at plan time.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.3.0 | `brew install terraform` / [download](https://developer.hashicorp.com/terraform/downloads) |
| curl | any | pre-installed on macOS/Linux |
| JFrog access token | Platform Admin scope | JFrog UI → Administration → Identity & Access → Access Tokens |

Verify Terraform is installed:
```bash
terraform version
```

---

## File Structure

State is sharded into **5 separate layers** (one platform + N projects + one curation), each with its own remote state file in Artifactory. Modules are git-pinned by tag so different consumers can upgrade independently.

```
terraform/
├── platform/                          # ROOT LAYER 1 — projects, groups, stages, role bindings
│   ├── main.tf                        # calls module platform/v1.2.1 (git-pinned)
│   ├── providers.tf  versions.tf      # artifactory + project + platform + null providers
│   ├── variables.tf  outputs.tf
│   ├── backend.tf                     # remote state: terraform-state-local/platform/
│   └── projects.json                  # project metadata (no repo definitions)
│
├── projects/                          # ROOT LAYERS 2..N — one root config per JFrog Project
│   ├── cmrc/                          #   Commerce
│   │   ├── main.tf                    #   calls module project-repos/v1.1.0
│   │   ├── providers.tf  versions.tf  #   artifactory provider only
│   │   ├── variables.tf  outputs.tf
│   │   ├── backend.tf                 #   remote state: terraform-state-local/projects/cmrc/
│   │   └── repos.json                 #   THIS project's apps + package types
│   ├── vntg/  …                       #   Vantage
│   └── wlt/   …                       #   Wallet
│
├── curation/                          # ROOT LAYER N+1 — Xray curation policies (LAST in apply order)
│   ├── main.tf                        # calls module curation/v1.0.0
│   ├── providers.tf  versions.tf      # jfrog/xray ~> 3.0 only
│   ├── variables.tf  outputs.tf
│   ├── backend.tf                     # remote state: terraform-state-local/curation/
│   └── curation_policies.json         # platform-wide block policies (17 shipped)
│
├── modules/                           # REUSABLE MODULES — pinned by git tag
│   ├── platform/                      # tagged platform/v1.0.0 → v1.2.1
│   ├── project-repos/                 # tagged project-repos/v1.0.0 → v1.1.0
│   └── curation/                      # tagged curation/v1.0.0
│
├── terraform.tfvars                   # local credentials (gitignored)
├── terraform.tfvars.example
├── run.sh                             # orchestrator: platform → projects/* (parallel) → curation
└── cleanup.sh                         # orchestrator: curation → projects/* (parallel) → platform
```

The reusable modules under `modules/` are also versioned independently via git tags (e.g. `platform/v1.2.1`, `project-repos/v1.1.0`, `curation/v1.0.0`). Root configs pin the module source by `?ref=<tag>` so bumping one module doesn't affect the others.

---

## Quick Start

```bash
# 1. Configure credentials
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set jfrog_url and jfrog_access_token

# 2. Run the orchestrator
chmod +x run.sh cleanup.sh
./run.sh --auto    # applies every layer end-to-end (non-interactive)
```

`./run.sh` applies layers in this order:

| Phase | Layer | Resources |
|---|---|---|
| 1 | `platform/` | Projects, per-project groups (ADMIN/WRITE/READ), platform-wide groups (security-admin, curation-approver), global stages (DEV/QA/STG/PROD), group→role bindings |
| 2 | `projects/*/` in parallel | All repos for each project (local + remote + virtual × stages × package types) |
| 3 | `curation/` (LAST) | Xray curation policies (platform-wide; runs last because it has no dependency on platform/projects and any Curation API hiccup shouldn't block provisioning) |

To operate on a single layer in isolation:

```bash
# Just one project's repos
./run.sh --auto --project cmrc

# Just the platform layer
./run.sh --auto --platform-only

# Just curation
cd terraform/curation && terraform init && terraform apply -auto-approve
```

---

## Self-service via GitHub Actions

Teams don't need to clone the repo or run Terraform locally to add a project or a repository. They open a GitHub Issue using one of the two Issue Forms, and the intake bot opens a PR with the right file edits. After CODEOWNERS approval, merging triggers the apply workflow which talks to JFrog.

### End-to-end flow

```
1. GitHub UI → New Issue → pick a template:
     • "New repository (within an existing project)"   → label: new-repo
     • "New JFrog Project"                              → label: new-project

2. Issue submitted.
   .github/workflows/intake.yml fires automatically.

3. Bot parses the form body, validates, then either:
   ✘ Comments errors back + applies 'intake-blocked' label, leaves issue open.
     Fix the body, then add label 'intake-retry' to re-trigger.
   ✓ Opens an "[intake]" PR with the file edits and labels:
       intake, new-repo   (for new-repo flow)
       intake, new-project (for new-project flow)
     Comments back on the issue with the PR URL.

4. PR Validate workflow plans every affected layer, posts a red-bold
   "Drift has been detected" comment per layer with the full plan inside
   a <details> block.

5. CODEOWNERS auto-requests review:
     terraform/projects/<key>/  →  the project's team
     platform/                  →  platform-admins

6. Reviewer approves and merges (no auto-merge; explicit human gate).

7. Apply workflow fires on merge to main:
     - Plan & apply only the affected layers (path-filtered)
     - Per-layer parallelism capped to 4 (JFrog rate-limit)
     - Posts a red-bold "Drift has been detected" callout on the merged
       PR with apply status + resource counts + log tail
     - Original Issue auto-closes (PR body says "Resolves #<n>")

8. JFrog now has the new repos / project, project_key set at create-time.
```

### The two Issue Forms

#### `.github/ISSUE_TEMPLATE/new-repo.yml` — add a repo to an existing project

| Form field | Type | What the bot does with it |
|---|---|---|
| **Project** | dropdown (`cmrc` / `vntg` / `wlt`) | Selects which `terraform/projects/<key>/repos.json` to edit |
| **Application name** | text, lowercase | New `applications[]` entry name |
| **Package types** | multi-select checkboxes (npm, python, terraform, docker, helm) | Populates `package_types` array |
| **Rationale** | textarea, optional | Copied into the PR body for context |
| **Confirmations** | checkboxes, required | Validation guard rails |

For each `(package_type × stage)` combination, the apply workflow creates one local repo. Plus one shared remote per tech (shared across the project), and one virtual aggregator per app+tech for DEV. E.g. `payment + [npm, docker]` adds 8 new repos.

#### `.github/ISSUE_TEMPLATE/new-project.yml` — create a new JFrog Project

| Form field | Type | What the bot does with it |
|---|---|---|
| **Project key** | text, 3–6 chars lowercase | Used as the repo-key prefix everywhere; immutable |
| **Display name** | text | Shown in the JFrog UI |
| **Description** | textarea | Visible in JFrog and in the PR body |
| **Storage quota (GiB)** | dropdown (100 / 250 / 500 / 1000 / 2000) | Sets `max_storage_in_gibibytes` on the project resource |
| **GitHub team owning this project** | text (`@org/team-handle`) | Added to `.github/CODEOWNERS` to route future PRs |
| **Initial applications** | textarea, optional, format `name: type1, type2` per line | Pre-populates `repos.json` |
| **Confirmations** | checkboxes, required | Validation guard rails |

What the new-project PR contains:
- Entry added to `terraform/platform/projects.json`
- Scaffolds `terraform/projects/<key>/` with `main.tf` (module ref pinned to the latest tagged `project-repos` version), `providers.tf`, `variables.tf`, `versions.tf`, `outputs.tf`, `backend.tf` (remote state path), `repos.json` (pre-populated if `Initial applications` was filled)
- CODEOWNERS rule routing `/terraform/projects/<key>/` to the owning team plus `@MCodeVisionary/platform-admins`

### Validation rejections

If a teammate submits invalid input — e.g. `Project key: AB` (too short) or asks for a package type we don't support — the bot replies on the issue:

> ⚠️ **Intake blocked — request needs revision.**
>
> The form input failed validation:
> - Project key `AB` must be lowercase, 3–6 chars, letters/digits only, starting with a letter.
>
> Edit the issue body to fix the items above, then add the label `intake-retry` to retry, or open a fresh issue.

And applies the `intake-blocked` label. The teammate can edit the Issue body (GitHub allows it post-submit), apply `intake-retry`, and the bot re-runs. No PR is opened until validation passes.

### Workflow files

| File | Trigger | Purpose |
|---|---|---|
| [.github/workflows/intake.yml](.github/workflows/intake.yml) | `issues: opened` or `issues: labeled` with `intake-retry` | Parse issue body, validate, open PR |
| [.github/workflows/pr-validate.yml](.github/workflows/pr-validate.yml) | `pull_request` on `terraform/**` | `terraform plan` per affected layer, post red-bold comment |
| [.github/workflows/apply.yml](.github/workflows/apply.yml) | `push` to `main` on `terraform/**` | `terraform apply` per affected layer, post red-bold comment |
| [.github/workflows/drift.yml](.github/workflows/drift.yml) | `schedule: cron '0 9 * * *'` daily | `plan -refresh-only` per layer, open Issue if drift |
| [.github/scripts/intake_new_repo.py](.github/scripts/intake_new_repo.py) | Called by `intake.yml` | Body parser + validator + repos.json editor for new-repo |
| [.github/scripts/intake_new_project.py](.github/scripts/intake_new_project.py) | Called by `intake.yml` | Body parser + validator + scaffolder + CODEOWNERS editor for new-project |
| [.github/scripts/_intake_lib.py](.github/scripts/_intake_lib.py) | Imported by both intake scripts | Issue Forms parser, `gh`/`git` wrappers, failure path |

### Setup the workflows need (one-time, ~15 min)

The intake workflow itself runs with no external setup — it uses `GITHUB_TOKEN` to create branches, push, open PRs, and comment on Issues. But the *downstream* `pr-validate.yml` and `apply.yml` workflows talk to JFrog via OIDC, which needs a one-time setup in JFrog and GitHub:

See [docs/CI_OIDC_SETUP.md](docs/CI_OIDC_SETUP.md) for the step-by-step (creating 2 JFrog service users, one OIDC integration, two identity mappings, four GitHub repo variables, plus branch protection on `main`).

---

## Xray Curation Policies

Curation policies block packages at download time when they hit one of the conditions JFrog defines (CVE severity, malicious package, license, package age, etc.). They are platform-wide but **live in their own Terraform layer** (`terraform/curation/`) with their own state file — separate from the platform layer — because they use a different JFrog provider (`jfrog/xray`) and a different permission scope (Xray Admin).

### Where they live

| File | Purpose |
|---|---|
| [`terraform/curation/curation_policies.json`](terraform/curation/curation_policies.json) | The data file — one entry per policy. Edit this to add, remove, or modify policies. |
| [`terraform/curation/`](terraform/curation/) | Root config: `main.tf` (calls `curation/v1.0.0` module), `providers.tf` (xray), `variables.tf`, `versions.tf`, `outputs.tf`, `backend.tf` (remote state at `terraform-state-local/curation/`). |
| [`terraform/modules/curation/curation.tf`](terraform/modules/curation/curation.tf) | The `xray_curation_policy.this` resource block iterating the JSON. |
| [`terraform/modules/curation/locals.tf`](terraform/modules/curation/locals.tf) | JSON parser that strips documentation-only `_comment` / `_condition` fields. |

### Default policies shipped (17)

| Risk type | Policy | Condition ID |
|---|---|---|
| security | `block_malicious_package` | 1 |
| security | `block_cvss_9to10_with_fix_version` | 2 |
| security | `block_cvss_9to10_with_or_without_fix_version` | 3 |
| security | `block_cvss_7to9_with_fix_version` | 4 |
| security | `block_cvss_7to9_with_or_without_fix_version` | 5 |
| security | `block_cvss_4to7_with_fix_version` | 6 |
| security | `block_cvss_4to7_with_or_without_fix_version` | 7 |
| legal | `block_no_license` | 8 |
| legal | `block_license_AGPL` | 9 |
| legal | `block_license_GPL` | 10 |
| legal | `block_license_LGPL` | 11 |
| operational | `block_aged_package_without_newer_version` | 12 |
| operational | `block_aged_package_with_newer_version` | 13 |
| operational | `block_immature_packages_2d` (permissive) | 14 |
| operational | `block_immature_packages_14d` (moderate) | 15 |
| operational | `block_immature_packages_30d` (strict) | 16 |
| operational | `block_image_not_offical_docker_hub` | 17 |

All policies share the same shape: `scope = all_repos`, `policy_action = block`, `waiver_request_config = forbidden`. To deviate from this default per-policy, just add the override field directly on the JSON entry (e.g. `"waiver_request_config": "manual"`, `"decision_owners": ["..."]`, `"repo_exclude": [...]`).

### Adding a new policy

1. Pick the JFrog-side condition ID you want to enforce. The full catalog lives at JFrog UI → Administration → Curation → Conditions. Predefined conditions cover CVE bands, license bans, age, immaturity, Docker Hub officiality, and more.

2. Add an entry to `terraform/curation/curation_policies.json`:

   ```json
   {
     "name":         "block_my_new_thing",
     "condition_id": "42",
     "_condition":   "human-readable description (optional, ignored by terraform)"
   }
   ```

3. Open a PR. `pr-validate.yml` plans the platform layer and posts the red-bold drift banner showing the new `xray_curation_policy.this["block_my_new_thing"]` resource. After merge, `apply.yml` creates it.

### Removing a policy

Delete its entry from `curation_policies.json`, open a PR. Terraform plan shows `-1` for `xray_curation_policy.this["..."]`. After merge, the policy is removed from JFrog Curation. No state surgery required.

### Apply / destroy order

The curation layer is wired into the same orchestration scripts as the platform and project layers:

- `./run.sh` applies: **platform** → **curation** → **projects/* in parallel**
- `./cleanup.sh` destroys in reverse: **projects/* in parallel** → **curation** → **platform**

You can also operate on the curation layer in isolation:

```bash
# Apply only curation (assumes platform layer already exists)
cd terraform/curation && terraform init && terraform apply

# Destroy only curation
cd terraform/curation && terraform destroy
```

### Provider + permissions

The curation layer uses the [`jfrog/xray ~> 3.0`](https://registry.terraform.io/providers/jfrog/xray/latest) provider, isolated from the other JFrog providers (`artifactory`, `project`, `platform`) used by the platform layer. The `gh-actions-apply` OIDC user used by CI needs **Xray Admin** scope — without it, apply fails with HTTP 403. See [docs/CI_OIDC_SETUP.md](docs/CI_OIDC_SETUP.md) §1 for the permission setup.

---

## Cleanup — removing all resources

```bash
chmod +x cleanup.sh

./cleanup.sh              # interactive — prompts at each stage
./cleanup.sh --auto       # non-interactive, auto-approves (CI use)
./cleanup.sh --state-only # wipe local state/cache only, do not touch JFrog
```

`cleanup.sh` will:
- Show a summary of all resources that will be destroyed
- Require typing the word `destroy` to confirm (interactive mode)
- Run `terraform destroy` to remove all JFrog projects, repos, and groups
- Offer to clean up local state files, provider cache, and credentials

`projects.json` and all `.tf` source files are **never** removed by the cleanup script.

---

## Configuration — projects.json

All project structure is defined in `projects.json`. To add a project, application, or package type — edit only the JSON. No `.tf` file changes needed.

### Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `projects` | object | Yes | Top-level map. Key = display name (e.g. `"Commerce"`) |
| `key` | string | Yes | JFrog project key — immutable, used as repo prefix. e.g. `cmrc` |
| `display_name` | string | Yes | Name shown in JFrog UI |
| `description` | string | No | Free-text description |
| `max_storage_gib` | number | No | Storage quota in GiB. Default `500`. Use `-1` for unlimited |
| `stages` | array | Yes | `["all"]` = global only. `["all","UAT"]` = global + project-specific UAT |
| `applications[].name` | string | Yes | App name used in repo names. Lowercase |
| `applications[].package_types` | array | Yes | Subset of: `npm`, `python`, `docker`, `helm`, `terraform` |

### Stages logic

```
["all"]              →  DEV, QA, PROD              (global only)
["all", "UAT"]       →  DEV, QA, PROD + UAT        (global + project-specific)
["all","UAT","STG"]  →  DEV, QA, PROD + UAT + STG  (global + multiple)
```

### Example — add a new project

```json
{
  "projects": {
    "Payments": {
      "key":             "pmts",
      "display_name":    "Payments",
      "description":     "Payments platform",
      "max_storage_gib": 500,
      "stages":          ["all"],
      "applications": [
        {
          "name":          "invoice",
          "package_types": ["npm", "docker", "helm"]
        }
      ]
    }
  }
}
```

Then run:
```bash
./run.sh
# or: terraform plan && terraform apply
```

---

## Lifecycle Stages

`stages.tf` manages global stages (DEV, QA, PROD) with **check-before-create** logic:

- Calls the JFrog REST API to check whether each stage exists
- If it exists → skips with a log message
- If it does not exist → creates it via POST
- Safe to run multiple times — the check prevents duplicate creation

---

## Known Issues

### Double apply on first provisioning

When repos are first created, Artifactory briefly assigns them to the `default` project before the `project` resource claims them. A second `terraform apply` reassigns them correctly. This only happens on the **first** provisioning — the `run.sh` script handles it automatically.

All repo resources carry `lifecycle { ignore_changes = [project_key] }` to prevent perpetual plan diffs after the second apply.

Reference: [jfrog/terraform-provider-artifactory#779](https://github.com/jfrog/terraform-provider-artifactory/issues/779)

---

## Credentials

### Finding your JFrog Platform URL

Your JFrog URL is in the browser address bar when you are logged in. The format depends on how your instance is hosted:

| Hosting type | URL format | Example |
|-------------|-----------|---------|
| JFrog Cloud | `https://<your-org>.jfrog.io` | `https://acme.jfrog.io` |
| Self-hosted, custom domain | `https://jfrog.<your-company>.com` | `https://jfrog.acme.com` |
| Self-hosted, with port | `https://<host>:<port>` | `https://jfrog.acme.com:8082` |

Do **not** include a trailing slash. Do **not** include `/artifactory` — Terraform adds the correct path per API call.

### Generating an access token

JFrog UI → **Administration** → **Identity & Access** → **Access Tokens** → **Generate Token**

Set the scope to **Platform Admin**. Copy the token — it is shown only once.

### Supply credentials in one of two ways

**Option A — `terraform.tfvars` (local development)**
```hcl
jfrog_url          = "https://acme.jfrog.io"
jfrog_access_token = "eyJ..."
```

**Option B — environment variables (CI/CD)**
```bash
export TF_VAR_jfrog_url="https://acme.jfrog.io"
export TF_VAR_jfrog_access_token="eyJ..."
```

Never commit `terraform.tfvars` — it is git-ignored by default.

---

## Providers

Each layer pulls in only what it needs. No layer pulls all five.

| Provider | Used by layer(s) | Purpose |
|---|---|---|
| [jfrog/artifactory `~> 12.5`](https://registry.terraform.io/providers/jfrog/artifactory/latest) | `platform/`, `projects/*/` | Local / remote / virtual repos |
| [jfrog/project `~> 1.9`](https://registry.terraform.io/providers/jfrog/project/latest) | `platform/` | JFrog Project resources + `project_group` role bindings |
| [jfrog/platform `~> 2.2`](https://registry.terraform.io/providers/jfrog/platform/latest) | `platform/` | IDP `platform_group` shells |
| [jfrog/xray `~> 3.0`](https://registry.terraform.io/providers/jfrog/xray/latest) | `curation/` | `xray_curation_policy` resources |
| [hashicorp/null `~> 3.0`](https://registry.terraform.io/providers/hashicorp/null/latest) | `platform/` | `null_resource` provisioners for global and project-specific stages (the platform provider has no native stage resource yet) |
