# JFrog Platform — Terraform Configuration

Provisions JFrog Projects, IDP groups, lifecycle stages, repositories, and Xray curation policies. State is sharded into 5 independent layers (1 platform + N projects + 1 curation), each with its own remote state file in Artifactory. Resource definitions are data-driven — repos come from per-project `repos.json` files, curation policies from `curation_policies.json`, project metadata from `platform/projects.json`. No repo/project/policy is hardcoded in Terraform.

Teammates open requests via GitHub Issue Forms; an intake bot opens the PR; CI plans and applies. See [Self-service via GitHub Actions](#self-service-via-github-actions).

For visual overviews — full architecture, self-service sequence, module/state versioning, apply/cleanup ordering — see [docs/architecture.md](docs/architecture.md).

---

## Prerequisites

### Tools

| Tool | Version | Install | Used for |
|------|---------|---------|---------|
| Terraform | >= 1.3.0 | `brew install terraform` / [download](https://developer.hashicorp.com/terraform/downloads) | All `terraform plan` / `apply` / `init` |
| curl | any | pre-installed on macOS/Linux | `null_resource` stage create/check, cleanup.sh stage delete |
| jq | any | `brew install jq` | run.sh / cleanup.sh JSON parsing |
| Python 3 | any | pre-installed on macOS | Decoding JFrog JWT to derive `TF_HTTP_USERNAME` in run.sh / cleanup.sh |
| JFrog access token | Platform Admin scope (or Admin + Xray Admin for curation) | JFrog UI → Administration → Identity & Access → Access Tokens | Local dev + CI (via static auth — see [docs/CI_OIDC_SETUP.md](docs/CI_OIDC_SETUP.md)) |

Verify Terraform is installed:
```bash
terraform version
```

### Environment variables that Terraform reads

You don't normally export these by hand — `run.sh` and `cleanup.sh` derive them from `terraform.tfvars` automatically, and in CI they come from GitHub repo settings (see [docs/CI_OIDC_SETUP.md](docs/CI_OIDC_SETUP.md)). The list below is for reference, for cases where you run `terraform plan` / `apply` directly inside one of the layer directories without the wrapper scripts.

| Env var | Required? | Value | Consumed by |
|---|---|---|---|
| `TF_VAR_jfrog_url` | yes | `https://<your-org>.jfrog.io` (no trailing slash, no `/artifactory`) | All `provider {}` blocks in every layer's `providers.tf` |
| `TF_VAR_jfrog_access_token` | yes | The JFrog JWT access token (`eyJ…`) | All `provider {}` blocks (`artifactory`, `project`, `platform`, `xray`) |
| `TF_HTTP_USERNAME` | yes | The JFrog username whose token is in `TF_HTTP_PASSWORD` (e.g. `maharship@jfrog.com`). **Must equal the token's `sub` claim** | The HTTP state backend (`backend.tf`) — basic-auth username for `terraform-state-local` |
| `TF_HTTP_PASSWORD` | yes | Same value as `TF_VAR_jfrog_access_token` (the JFrog token) | The HTTP state backend — basic-auth password |
| `TF_PARALLELISM` | optional | Integer (default `4`) | `run.sh` / `cleanup.sh` pass it as `terraform -parallelism=N` to cap concurrent JFrog API calls (avoids HTTP 429 from the GRPC pool) |
| `TF_IN_AUTOMATION` | optional | `"true"` | Terraform itself — silences interactive hints. CI workflows set this; local dev usually doesn't bother |
| `TF_INPUT` | optional | `"false"` | Terraform itself — disables interactive prompts so failures don't hang. CI workflows set this |

**Why two env vars carry the same token** (`TF_HTTP_PASSWORD` and `TF_VAR_jfrog_access_token`): the HTTP state backend is initialized before Terraform variables resolve, so it can't reference `var.*` — it has its own `TF_HTTP_*` env-var contract. The providers use `TF_VAR_*` normal variable plumbing. One token, two consumers, two env-var names.

#### Where they get set in each context

| Context | How env vars get populated |
|---|---|
| **Local dev (`./run.sh`)** | `run.sh` reads `terraform.tfvars` and exports `TF_VAR_*` + `TF_HTTP_*`. Username for HTTP backend is decoded from the token's JWT `sub` claim at runtime. |
| **CI (apply / pr-validate / drift)** | Workflow `env:` blocks read from `vars.JF_URL`, `vars.TF_HTTP_USERNAME` (GitHub repo Variables) and `secrets.JFROG_ACCESS_TOKEN` (GitHub repo Secret). |
| **Manual `terraform plan` in a layer dir** | You export them yourself: `export TF_VAR_jfrog_url=… TF_VAR_jfrog_access_token=… TF_HTTP_USERNAME=… TF_HTTP_PASSWORD=…` before running terraform. |

For the CI side, see [docs/CI_OIDC_SETUP.md](docs/CI_OIDC_SETUP.md) for the one-time setup of the GitHub Variables + Secret.

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

## Fork & customize (only if you're using this for a different JFrog tenant)

This repo ships as a **concrete, working example** tied to `mcodevisionaryorg.jfrog.io` and the projects `cmrc` / `vntg` / `wlt`. Easier to read than placeholders, and the file paths/structure are self-explanatory.

If you fork for a different tenant, run this one-shot helper to swap the example host for yours:

```bash
./scripts/setup.sh <your-jfrog-host>

# Examples:
./scripts/setup.sh acme.jfrog.io
./scripts/setup.sh jfrog.acme-internal.com
./scripts/setup.sh acme.jfrog.io:8082
```

The script edits the 5 `terraform/<layer>/backend.tf` files plus the `.github/scripts/intake_new_project.py` template so new project scaffolds inherit your host. It's idempotent — safe to re-run; running with the same host is a no-op.

Other edits a fork would typically also do (manual — script doesn't touch these):
- `.github/CODEOWNERS` — team handles (`@MCodeVisionary/...` → `@<your-org>/...`)
- The `source = "git::https://github.com/MCodeVisionary/..."` URLs in `terraform/{platform,curation,projects/*}/main.tf` — point them at your fork
- `terraform/platform/projects.json` — your projects, not the demo cmrc/vntg/wlt set
- `terraform/projects/<key>/repos.json` — your apps & package types
- `terraform/curation/curation_policies.json` — keep, adjust, or drop the 17 default policies

If you're just **reading the repo** (not deploying to a different tenant), skip this section — the example values are intentional.

---

## Quick Start

If you've forked for your own tenant, run `./scripts/setup.sh <your-jfrog-host>` first (see [Fork & customize](#fork--customize-only-if-youre-using-this-for-a-different-jfrog-tenant) above). Otherwise:

```bash
# 1. Configure credentials
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars — set jfrog_url and jfrog_access_token

# 2. Run the orchestrator
chmod +x terraform/run.sh terraform/cleanup.sh
cd terraform && ./run.sh --auto    # applies every layer end-to-end (non-interactive)
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
| **Package types** | multi-select checkboxes (npm, python, terraform, docker, helm, nuget, maven, huggingface, rpm, debian, cargo, alpine, go) | Populates `package_types` array |
| **Rationale** | textarea, optional | Copied into the PR body for context |
| **Confirmations** | checkboxes, required | Validation guard rails |

For each `(package_type × stage)` combination, the apply workflow creates one local repo. Plus one shared remote per tech (shared across the project), and one virtual aggregator per app+tech for DEV. E.g. `payment + [npm, docker]` adds 8 new repos. Exception: `huggingface` and `cargo` have no virtual repository type in the provider, so they only get local + remote repos.

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

## State versioning (per-apply history)

Every successful `apply.yml` run archives the new state file to a timestamped + commit-SHA path inside the same Artifactory `terraform-state-local` repo. No external infrastructure, no extra cost.

### Layout

```
terraform-state-local/
├── platform/
│   ├── terraform.tfstate                                ← always = latest
│   └── _archive/
│       ├── 2026-05-18T22-50-26Z_341b0258.tfstate        ← per-apply snapshot
│       ├── 2026-05-19T09-32-01Z_b42b73f6.tfstate
│       └── …
├── curation/
│   └── (same)
└── projects/
    ├── cmrc/  (same)
    ├── vntg/  (same)
    └── wlt/   (same)
```

Each archive filename is `<UTC-timestamp>_<short-commit-sha>.tfstate`. Sortable lexicographically by time, links back to the PR via `git log <sha>`.

### When archives are written

- **After every successful `apply.yml` run.** One archive per applied layer per merge to `main`.
- **Never** by `pr-validate.yml` or `drift.yml` (they don't write state).

The archive step is `continue-on-error: true` — if Artifactory is briefly unreachable for the copy, the workflow still passes (the real apply already succeeded and the latest state is on the live path).

### Browsing history

Via the Artifactory UI: **Artifactory → Tree** → `terraform-state-local` → `<layer>` → `_archive/` → drill into any file to download.

Via the API:

```bash
curl -u "<user>:<token>" \
  "https://mcodevisionaryorg.jfrog.io/artifactory/api/storage/terraform-state-local/projects/cmrc/_archive?list" \
  | jq -r '.files[].uri'
```

### Restoring a previous state

```bash
USER="<your-jfrog-username>"
TOK="<your-jfrog-access-token>"
BASE="https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/projects/cmrc"
ARCHIVE_FILE="_archive/2026-05-18T22-50-26Z_341b0258.tfstate"

# Copy the archived version back into the live path
curl -fsS -u "$USER:$TOK" "$BASE/$ARCHIVE_FILE" \
  | curl -fsS -u "$USER:$TOK" -X PUT --data-binary @- "$BASE/terraform.tfstate"
```

After restore, the next `terraform plan` shows what would have to change to converge from the restored state to what's actually in JFrog. Use carefully — restoring state without thinking about whether JFrog matches it can create orphan resources or false-positive recreations.

### Tying an archive back to a PR

The 8-char commit SHA in the filename is the merge commit. Look it up:

```bash
git show 341b0258                # see the merge commit
git log 341b0258 -1 --format="%s" # one-line subject
```

If it's an intake-bot PR, the subject is `intake: add <app> to project <key>` and the merge points back to the original Issue via the `Resolves #<N>` line in the PR body.

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

## Configuration files

Project metadata and repo definitions are split across multiple JSON files matching the layer they belong to. **No `.tf` edits are needed to add a project or repo** — only the JSON.

### `platform/projects.json` — project metadata only

```json
{
  "projects": {
    "Commerce": {
      "key":             "cmrc",
      "display_name":    "Commerce",
      "description":     "Commerce product — payment and catalog applications",
      "max_storage_gib": 500,
      "stages":          ["all"]
    }
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| Top-level keys | string | Yes | Display name (e.g. `"Commerce"`) — used by terraform as map key |
| `key` | string | Yes | JFrog project key — immutable, lowercase, 3–6 chars; used as repo prefix |
| `display_name` | string | Yes | Name shown in JFrog UI |
| `description` | string | No | Free-text description |
| `max_storage_gib` | number | No | Storage quota in GiB (default `500`) |
| `stages` | array | Yes | `["all"]` = global stages only. `["all","UAT"]` = global + project-specific `<key>-UAT` |

### `projects/<key>/repos.json` — applications and repos per project

```json
{
  "project_key": "cmrc",
  "applications": [
    { "name": "payment", "package_types": ["npm", "python", "docker", "helm", "terraform"] },
    { "name": "catalog", "package_types": ["npm", "docker", "helm"] }
  ]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `project_key` | string | Yes | Must match the parent dir name (`projects/<key>/`) |
| `applications[].name` | string | Yes | Lowercase, 2–31 chars, letters/digits/hyphens, starts with letter/digit |
| `applications[].package_types` | array | Yes | Subset of: `npm`, `python`, `terraform`, `docker`, `helm`, `nuget`, `maven`, `huggingface`, `rpm`, `debian`, `cargo`, `alpine`, `go` |

For each `(application × package_type × stage)` combo, the module generates:
- One **local** repo: `<key>-<app>-<tech>-<stage>-local`
- One **virtual** repo (DEV only): `<key>-<app>-<tech>-dev-virtual` — except `huggingface` and `cargo`, which have no virtual repository type in the provider

And one **remote** repo per unique `package_type` per project: `<key>-<tech>-remote` (shared across the project's apps).

### `curation/curation_policies.json` — Xray curation policies

Covered separately in [§ Xray Curation Policies](#xray-curation-policies).

### Stages logic

```
["all"]              →  DEV, QA, STG, PROD             (global only, inherited by every project)
["all", "UAT"]       →  DEV, QA, STG, PROD + <key>-UAT (global + this project's UAT)
```

Global stages (DEV / QA / STG / PROD) are managed by the platform layer's `null_resource.global_stages`. DEV and PROD are JFrog-protected built-ins and persist even through cleanup; QA and STG are created/destroyed by the workflow.

### Adding a new project

Don't hand-edit `platform/projects.json` and create `projects/<key>/` directories yourself — open a **New JFrog Project** Issue via the form (see [Self-service via GitHub Actions](#self-service-via-github-actions)) and the intake bot scaffolds everything for you.

### Adding a repo to an existing project

Open a **New repository** Issue. The bot appends an `applications[]` entry to `projects/<key>/repos.json` for you.

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

JFrog UI → **Administration** → **Identity & Access** → **Access Tokens** → **Generate Token**.

Required scope:
- **Platform Admin** for the platform + projects layers (creates projects, groups, repos, environments)
- **Xray Admin** is additionally needed for the curation layer (managing `xray_curation_policy`)

Copy the token — it is shown only once.

### Local development — `terraform.tfvars`

```hcl
jfrog_url          = "https://acme.jfrog.io"
jfrog_access_token = "eyJ..."
```

Never commit `terraform.tfvars` — it's in `.gitignore`. `run.sh` and `cleanup.sh` read it directly and export the right env vars:
- `TF_VAR_jfrog_url`, `TF_VAR_jfrog_access_token` → fed to provider configs
- `TF_HTTP_USERNAME` → derived from the token's JWT `sub` claim
- `TF_HTTP_PASSWORD` → same value as the access token; used by the HTTP state backend

### CI/CD — GitHub Variables + Secret (static auth)

GitHub Actions authenticates via static credentials stored in repo settings. See [docs/CI_OIDC_SETUP.md](docs/CI_OIDC_SETUP.md) for the full setup (~5 minutes), but in brief:

| Storage | Name | Type | Value |
|---|---|---|---|
| Variables tab | `JF_URL` | Variable | `https://<your-org>.jfrog.io` |
| Variables tab | `TF_HTTP_USERNAME` | Variable | The JFrog username (e.g. `maharship@jfrog.com`) |
| Secrets tab | `JFROG_ACCESS_TOKEN` | **Secret** | The JFrog JWT access token |

The three workflows (`pr-validate.yml`, `apply.yml`, `drift.yml`) reference these directly — no OIDC, no token exchange.

### Why two env-var names for the same token (`TF_HTTP_PASSWORD` and `TF_VAR_jfrog_access_token`)

The same JFrog token is consumed by two independent code paths in a single `terraform apply` run:

| Consumer | Reads from | Why |
|---|---|---|
| HTTP state backend (`backend.tf`) | `TF_HTTP_PASSWORD` | Backend blocks can't reference Terraform variables — they're parsed before variables resolve. Backend's contract is the env-var name `TF_HTTP_*`. |
| Provider configs (`providers.tf`) | `var.jfrog_access_token` (← `TF_VAR_jfrog_access_token`) | Standard Terraform variable plumbing |

So a single secret in GitHub Storage, referenced twice in the workflow YAML. The duplication is a Terraform limitation, not our choice.

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
