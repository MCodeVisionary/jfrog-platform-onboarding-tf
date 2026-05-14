# CI / OIDC setup

GitHub Actions authenticates to JFrog via OIDC token exchange — no long-lived
JFrog token in repo secrets. Identity flows like this:

```
   GitHub Actions                 jfrog/setup-jfrog-cli@v4               JFrog Platform
   ──────────────                 ────────────────────────              ─────────────────
   workflow runs   ──── mint ───▶ GitHub OIDC JWT ──── exchange ──────▶ Access service
                                  (audience claim)                       validates issuer
                                                                          + claim mapping
                                                                  ◀──── short-lived JFrog
                                                                        access token
                                                                        (bound to mapped
                                                                         JFrog user)
```

Two identity mappings under one OIDC integration distinguish plan from apply:

| Workflow         | Audience claim          | JFrog user                                                              |
|------------------|-------------------------|-------------------------------------------------------------------------|
| `pr-validate`    | `jfrog-tf-state-plan`   | `gh-actions-plan` (read-only + write on `terraform-state-local`)        |
| `drift`          | `jfrog-tf-state-plan`   | (same as above)                                                         |
| `apply`          | `jfrog-tf-state-apply`  | `gh-actions-apply` (admin + write on `terraform-state-local`)           |

Total setup time: ~15 minutes, all in JFrog UI + GitHub Settings UI.

---

## 1. Create two JFrog users for CI

JFrog UI → **Administration → Identity & Access → Users → + New User** for each:

| User                | Purpose                       | Permissions                                                                |
|---------------------|-------------------------------|----------------------------------------------------------------------------|
| `gh-actions-plan`   | PR validate, drift detection  | Read on all repos + write on `terraform-state-local` (locking + state read) |
| `gh-actions-apply`  | Apply on merge                | Admin scope + write on `terraform-state-local`                              |

- Mark both as *Disable internal password* (no human use).
- Leave email blank.

### Permissions

For `gh-actions-plan`:
- **Administration → Identity & Access → Permissions → + New Permission**
- Repositories tab: all repos with **Read** action; `terraform-state-local` with **Write** action
- Assign to user `gh-actions-plan`

For `gh-actions-apply`:
- Easiest: assign the built-in **Admin** group to this user
- Tighter alternative: a custom permission with project-create/update,
  repository-create/update/delete, group-create/update, environment-create
  across all repos, plus write on `terraform-state-local`

---

## 2. Create the OIDC Integration in JFrog

JFrog UI → **Administration → Identity & Access → OIDC Integrations → + New Integration**.

| Field             | Value                                                                                                 |
|-------------------|--------------------------------------------------------------------------------------------------------|
| Name              | `github-tf-onboarding` *(this is what you'll set as `vars.OIDC_PROVIDER_NAME` in GitHub)*              |
| Description       | OIDC trust for the jfrog-platform-onboarding-tf repo's GitHub Actions                                  |
| Provider Type     | Generic OpenID Connect                                                                                  |
| Issuer URL        | `https://token.actions.githubusercontent.com`                                                            |
| Audience          | (leave blank here — set per identity mapping below)                                                      |

Save.

---

## 3. Add two identity mappings

Under the `github-tf-onboarding` integration → **Identity Mappings → +**.

### Mapping A — plan identity

| Field        | Value                                                                                                                        |
|--------------|------------------------------------------------------------------------------------------------------------------------------|
| Name         | `github-plan`                                                                                                                  |
| Priority     | 100                                                                                                                            |
| Claims (JSON)| `{ "iss": "https://token.actions.githubusercontent.com", "repository": "MCodeVisionary/jfrog-platform-onboarding-tf", "aud": "jfrog-tf-state-plan" }` |
| Token User   | `gh-actions-plan`                                                                                                              |
| Token Scope  | `applied-permissions/user`                                                                                                     |
| Token TTL    | 600 (10 minutes)                                                                                                               |

### Mapping B — apply identity

| Field        | Value                                                                                                                                                                  |
|--------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Name         | `github-apply`                                                                                                                                                           |
| Priority     | 100                                                                                                                                                                      |
| Claims (JSON)| `{ "iss": "https://token.actions.githubusercontent.com", "repository": "MCodeVisionary/jfrog-platform-onboarding-tf", "ref": "refs/heads/main", "aud": "jfrog-tf-state-apply" }` |
| Token User   | `gh-actions-apply`                                                                                                                                                       |
| Token Scope  | `applied-permissions/user`                                                                                                                                               |
| Token TTL    | 1800 (30 minutes)                                                                                                                                                        |

The `ref` claim on Mapping B restricts apply privileges to runs on `main`. PR
runs (which request audience `jfrog-tf-state-plan`) cannot impersonate the
apply user even if compromised.

---

## 4. Set GitHub repo variables

GitHub UI → **Settings → Secrets and variables → Actions → Variables tab → New repository variable**.

Create **four** variables (no secrets needed — these are non-sensitive identifiers):

| Variable name            | Value                                                  |
|--------------------------|--------------------------------------------------------|
| `JF_URL`                 | `https://mcodevisionaryorg.jfrog.io` (no trailing slash) |
| `OIDC_PROVIDER_NAME`     | `github-tf-onboarding` *(must match step 2)*           |
| `OIDC_AUDIENCE_PLAN`     | `jfrog-tf-state-plan` *(must match Mapping A)*         |
| `OIDC_AUDIENCE_APPLY`    | `jfrog-tf-state-apply` *(must match Mapping B)*        |

That's it — **no JFrog token stored anywhere**.

---

## 5. GitHub repo settings

### Workflow permissions
GitHub UI → **Settings → Actions → General → Workflow permissions**:
- **Read and write permissions** (workflows post PR comments and create drift Issues)
- **Allow GitHub Actions to create and approve pull requests:** enabled

### Branch protection for `main`
GitHub UI → **Settings → Branches → Branch protection rules → Add rule**:
- Branch name pattern: `main`
- Require a pull request before merging: ✓
- Require approvals: 1
- Require review from Code Owners: ✓
- Require status checks to pass before merging: ✓ — add **PR Validate / plan**
- Do not allow bypassing the above settings: ✓

### Teams (CODEOWNERS uses these)
GitHub UI → org-level **Teams → New team** for each:
- `platform-admins`
- `cmrc-team`, `vntg-team`, `wlt-team` *(or whatever team names match your projects)*

If your team names differ, edit `.github/CODEOWNERS` to match.

---

## 6. Test the setup

After steps 1–5 are done:

1. Open a trivial PR — e.g. tweak a comment in `terraform/projects/cmrc/repos.json`.
2. Wait for **PR Validate / plan** to run (~2–3 min).
3. If you see a red-bold drift banner with a plan posted as a PR comment, OIDC is working.

### Troubleshooting

| Symptom                                                              | Cause                                                          | Fix                                                                                                       |
|----------------------------------------------------------------------|----------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| Workflow fails with `OIDC token was not produced by setup-jfrog-cli` | `vars.OIDC_PROVIDER_NAME` doesn't match JFrog Integration name | Verify the OIDC Integration in JFrog UI; copy its name exactly into the GitHub repo variable              |
| Workflow fails with `403` from JFrog                                 | Identity mapping claim mismatch                                | The `repository` claim in your mapping must be exactly `<org>/<repo>` (case-sensitive); verify both sides |
| Workflow fails with `audience mismatch`                              | `vars.OIDC_AUDIENCE_PLAN` / `_APPLY` doesn't match a mapping  | Check the `aud` claim on the corresponding mapping in JFrog                                               |
| State backend errors with `endpoint requires auth`                   | OIDC succeeded but token's subject doesn't have access         | Add `gh-actions-plan` / `gh-actions-apply` write permission on the `terraform-state-local` repo            |
| PR validate runs but no comment posts                                | `pull-requests: write` permission missing                      | Repo Settings → Actions → Workflow permissions → enable Read and write                                    |

---

## 7. Key properties of this setup

- **No JFrog access tokens stored in GitHub Secrets.** The only GitHub-stored values are the JFrog URL, the OIDC provider name, and the two audience strings — none are sensitive.
- **Automatic rotation.** Workflow runs mint a fresh JFrog token each time, valid for 10 min (plan) / 30 min (apply). Expires before it can be misused.
- **One-step revocation.** Disable `gh-actions-plan` or `gh-actions-apply` in the JFrog UI and every workflow run instantly fails. There's no token to invalidate.
- **Audit trail.** JFrog logs every token-issue event with the GitHub claim payload, so you can trace exactly which PR/commit triggered which JFrog mutation.
- **Apply privileges are pinned to `main`.** Even if a PR's workflow is compromised, it cannot acquire the `apply` audience — that's gated by the `ref=refs/heads/main` claim on Mapping B.
