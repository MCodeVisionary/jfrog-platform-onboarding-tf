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

```
terraform/
├── projects.json                # Single source of truth — edit this to add/change projects
├── versions.tf                  # Provider constraints (artifactory, project, platform, null)
├── variables.tf                 # Three inputs: jfrog_url, jfrog_access_token, config_file
├── locals.tf                    # Parses JSON; computes all resource combinations
├── providers.tf                 # Provider configuration
├── stages.tf                    # Global stages (DEV, QA, PROD) — check-before-create
├── groups.tf                    # IDP group shells per project
├── projects.tf                  # JFrog Projects + project-specific stages
├── repositories_npm.tf          # npm repos (local/remote/virtual)
├── repositories_python.tf       # Python repos
├── repositories_terraform.tf    # Terraform repos
├── repositories_docker.tf       # Docker repos
├── repositories_helm.tf         # Helm repos
├── outputs.tf                   # Project keys, group names, repo counts, virtual URLs
├── README.md                    # This file
├── run.sh                       # Idempotent run script (recommended entry point)
├── cleanup.sh                   # Remove all JFrog resources created by Terraform
└── terraform.tfvars.example     # Copy to terraform.tfvars and populate
```

---

## Quick Start

```bash
# 1. Configure credentials
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set jfrog_url and jfrog_access_token

# 2. Run via the helper script (recommended)
chmod +x run.sh
./run.sh

# — OR run manually —
terraform init
terraform plan
terraform apply
terraform apply   # second apply required only on first provisioning
```

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

- [jfrog/artifactory](https://registry.terraform.io/providers/jfrog/artifactory/latest)
- [jfrog/project](https://registry.terraform.io/providers/jfrog/project/latest)
- [jfrog/platform](https://registry.terraform.io/providers/jfrog/platform/latest)
- [hashicorp/null](https://registry.terraform.io/providers/hashicorp/null/latest)
