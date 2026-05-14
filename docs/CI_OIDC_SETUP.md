# CI / OIDC setup

One-time setup so GitHub Actions can plan/apply against JFrog without a
long-lived token in repo secrets. Identity is established via OIDC token
exchange: GitHub mints a short-lived JWT, JFrog accepts it (because we tell
JFrog to trust this specific repository), and JFrog hands back a short-lived
JFrog access token scoped to one of two service users.

Total time: **~15 minutes**, all in the JFrog UI and GitHub Settings UI.

---

## 1. Create two JFrog users for CI

These users back the OIDC mappings. They never log in interactively — they
exist solely so workflows have something to assume.

| User                | Purpose                       | Permissions                                                    |
|---------------------|-------------------------------|----------------------------------------------------------------|
| `gh-actions-plan`   | PR validate, drift detection  | Read-only across the platform; **write to `terraform-state-local`** (state lock requires writes even for plan) |
| `gh-actions-apply`  | Apply on merge                | Admin scope (creates/edits projects, repos, groups, environments) + write to `terraform-state-local` |

**Create them:**
JFrog UI → Administration → Identity & Access → Users → **+ New User** for each.
- Mark *Disable internal password* (no human use).
- Leave email blank.

**Permissions for `gh-actions-plan`:**
- Administration → Identity & Access → Permissions → **+ New Permission**
- Name: `gh-actions-plan-perms`
- Resources: All repositories (read-only) + `terraform-state-local` (write)
- Assign to user `gh-actions-plan`

**Permissions for `gh-actions-apply`:**
- Easiest: assign the built-in **Admin** group to this user.
- Tighter: a custom permission with project-create, project-update,
  repository-create, repository-update, repository-delete, group-create,
  group-update, environment-create across the whole platform.

---

## 2. Configure GitHub as an OIDC provider in JFrog

JFrog UI → Administration → Identity & Access → **OIDC Integrations** → **+ New Integration**.

| Field           | Value                                                                                              |
|-----------------|----------------------------------------------------------------------------------------------------|
| Name            | `github`                                                                                           |
| Description     | OIDC trust for the jfrog-platform-onboarding-tf repo's GitHub Actions                              |
| Provider Type   | Generic OpenID Connect                                                                              |
| Issuer URL      | `https://token.actions.githubusercontent.com`                                                       |
| Audience        | (leave blank here — set per identity mapping below)                                                 |

Save.

---

## 3. Add two identity mappings

Each mapping says: *if a GitHub OIDC token with these claims arrives, mint a
JFrog token for this user.*

**Mapping A — plan identity:**
JFrog UI → OIDC Integration `github` → **Identity Mappings** → **+**

| Field      | Value                                                                                                       |
|------------|-------------------------------------------------------------------------------------------------------------|
| Name       | `github-plan`                                                                                                |
| Priority   | 100                                                                                                          |
| Claims     | `{ "iss": "https://token.actions.githubusercontent.com", "repository": "MCodeVisionary/jfrog-platform-onboarding-tf", "aud": "jfrog-tf-state-plan" }` |
| Token User | `gh-actions-plan`                                                                                            |
| Token Scope| `applied-permissions/user`                                                                                   |
| Token TTL  | 600 (10 minutes)                                                                                             |

**Mapping B — apply identity:**

| Field      | Value                                                                                                        |
|------------|--------------------------------------------------------------------------------------------------------------|
| Name       | `github-apply`                                                                                                 |
| Priority   | 100                                                                                                            |
| Claims     | `{ "iss": "https://token.actions.githubusercontent.com", "repository": "MCodeVisionary/jfrog-platform-onboarding-tf", "ref": "refs/heads/main", "aud": "jfrog-tf-state-apply" }` |
| Token User | `gh-actions-apply`                                                                                             |
| Token Scope| `applied-permissions/user`                                                                                     |
| Token TTL  | 1800 (30 minutes)                                                                                              |

The `ref` claim on Mapping B restricts apply privileges to runs on `main`. PR
runs (which use audience `jfrog-tf-state-plan`) cannot impersonate the apply
user even if compromised.

---

## 4. Repository settings on GitHub

GitHub UI → Settings (repo) → **Actions** → **General** →
- Workflow permissions: **Read and write permissions** (needed for posting PR comments and creating drift Issues)
- Allow GitHub Actions to create and approve pull requests: **enabled**

GitHub UI → Settings (repo) → **Branches** → branch protection rule for `main`:
- Require a pull request before merging: ✓
- Require approvals: 1
- Require review from Code Owners: ✓
- Require status checks to pass before merging: ✓ (check **PR Validate / plan**)
- Do not allow bypassing the above settings: ✓

GitHub UI → Settings (org) → **Teams** → create:
- `platform-admins`
- `cmrc-team`, `vntg-team`, `wlt-team`
Then edit `.github/CODEOWNERS` to replace placeholder team names if you used different ones.

---

## 5. Test the OIDC trust

After the above is configured:

1. Open a trivial PR — e.g. add a comment to `terraform/projects/cmrc/repos.json`.
2. Wait for **PR Validate** to run.
3. If you see a red-bold drift banner with a plan posted as a PR comment, OIDC is working.
4. If you see `OIDC exchange failed` in the workflow log, check:
   - The `repository` claim in the JFrog mapping exactly matches `<org>/<repo>` (case-sensitive)
   - The audience strings match (`jfrog-tf-state-plan` vs `jfrog-tf-state-apply`)
   - The OIDC Integration name in JFrog matches what the workflow passes (`provider_name: 'github'`)

---

## 6. Key things to know

- **No GitHub Secrets needed for JFrog auth.** No `JFROG_ACCESS_TOKEN` secret. The only thing GitHub stores about JFrog is the URL, which is hardcoded in workflow `env:` blocks — not a secret.
- **Rotation: automatic.** The JFrog tokens minted live 10–30 minutes. Workflow re-mints on every run.
- **Revoking access.** Delete or disable `gh-actions-plan` / `gh-actions-apply` in JFrog and every workflow run instantly fails. There's no token to invalidate.
- **State backend (`terraform-state-local`) needs write access from both identities** because `terraform init` and `terraform plan` both touch the lock file. The plan user only needs `LOCK`/`UNLOCK`/`GET` on the state path, not on real repos.
