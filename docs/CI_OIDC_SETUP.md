# CI / OIDC setup

GitHub Actions authenticates to JFrog via OIDC token exchange — no long-lived
JFrog token stored in repo secrets. Identity flows like this:

```
   GitHub Actions                 jfrog/setup-jfrog-cli@v4               JFrog Platform
   ──────────────                 ────────────────────────              ─────────────────
   workflow runs   ──── mint ───▶ GitHub OIDC JWT  ─── exchange ──────▶ Access service
                                  (subject: <org>/<repo>...              validates issuer
                                   :ref:refs/heads/main)                  + claim mapping
                                                                  ◀──── short-lived JFrog
                                                                        access token
                                                                        (bound to the
                                                                         mapped JFrog user)
```

A **single** OIDC integration in JFrog covers all three workflows
(`pr-validate`, `apply`, `drift`). The integration is identified in each
workflow by the literal string:

```
MCodeVisionary/jfrog-platform-onboarding-tf@github
```

This is the format `<github-org>/<github-repo>@<oidc-integration-name>` — the
`@github` suffix matches the name of the OIDC Integration created in JFrog.

Total setup time: ~10 minutes, all in JFrog UI + GitHub Settings UI.

---

## 1. Create the JFrog service user for CI

JFrog UI → **Administration → Identity & Access → Users → + New User**:

| User                | Purpose                       | Permissions                                                                                          |
|---------------------|-------------------------------|------------------------------------------------------------------------------------------------------|
| `gh-actions`        | Plan, apply, drift detection  | **Admin scope** + write on `terraform-state-local` + **Xray Admin** (for curation policy management) |

- Mark *Disable internal password* (no human use).
- Leave email blank.

The simplest permission grant is to assign the built-in **Admin** group. If
you want tighter scoping, the user needs:

- Repository create/update/delete on all repositories
- Project create/update/delete
- Group create/update
- Environment create/delete (for global stages)
- **Xray Admin** scope (for `xray_curation_policy` management — without
  this, the curation layer's apply fails with HTTP 403)
- Write on the `terraform-state-local` generic local repo (for the
  HTTP-backend state files)

---

## 2. Create the OIDC Integration in JFrog

JFrog UI → **Administration → Identity & Access → OIDC Integrations → + New Integration**.

| Field             | Value                                                                                                 |
|-------------------|--------------------------------------------------------------------------------------------------------|
| Name              | `github` *(this is the `@github` suffix in the workflow's `oidc-provider-name`)*                       |
| Description       | OIDC trust for the jfrog-platform-onboarding-tf repo's GitHub Actions                                  |
| Provider Type     | Generic OpenID Connect                                                                                  |
| Issuer URL        | `https://token.actions.githubusercontent.com`                                                            |
| Audience          | `jfrog-github-oidc` *(or whatever the JFrog UI defaults to — it's only consumed by the identity mapping below)* |

Save.

---

## 3. Add an identity mapping

Under the `github` integration → **Identity Mappings → + New Mapping**.

| Field        | Value                                                                                                         |
|--------------|---------------------------------------------------------------------------------------------------------------|
| Name         | `github-main`                                                                                                  |
| Priority     | 100                                                                                                            |
| Claims (JSON)| `{ "iss": "https://token.actions.githubusercontent.com", "repository": "MCodeVisionary/jfrog-platform-onboarding-tf" }` |
| Token User   | `gh-actions`                                                                                                   |
| Token Scope  | `applied-permissions/user`                                                                                     |
| Token TTL    | 1800 (30 minutes)                                                                                              |

**Optional hardening — restrict apply privileges to `main` branch:**
If you want PR runs (which run on feature branches) to be unable to
acquire write privileges even if compromised, split this into TWO mappings
and use the workflow's `oidc-audience` argument to pick between them. The
current single-mapping setup trusts any commit on this repo equally — fine
for a small team, less so for a large one.

---

## 4. Set GitHub repo variables

GitHub UI → **Settings → Secrets and variables → Actions → Variables tab → New repository variable**.

| Variable name            | Value                                                  |
|--------------------------|--------------------------------------------------------|
| `JF_URL`                 | `https://mcodevisionaryorg.jfrog.io` (no trailing slash) |

That's the only repo variable needed. No JFrog token is stored anywhere
in GitHub.

(Older versions of this guide also asked for `OIDC_PROVIDER_NAME`,
`OIDC_AUDIENCE_PLAN`, `OIDC_AUDIENCE_APPLY` — they're no longer used.
The provider name is now hardcoded in every workflow as
`MCodeVisionary/jfrog-platform-onboarding-tf@github`, and no audience
parameter is passed.)

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
4. The example workflow at `.github/workflows/jfrog-github-oidc-example.yml` is a minimal "does `jf rt ping` work" smoke test you can trigger on push — useful for isolating OIDC failures from terraform failures.

### Troubleshooting

| Symptom                                                              | Cause                                                          | Fix                                                                                                       |
|----------------------------------------------------------------------|----------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| Workflow fails with `OIDC token was not produced by setup-jfrog-cli` | OIDC integration name doesn't match `@github` suffix           | The string after `@` in `oidc-provider-name` (currently `github`) must equal the JFrog Integration name   |
| Workflow fails with `403` from JFrog                                 | Identity mapping claim mismatch                                | The `repository` claim in your mapping must be exactly `MCodeVisionary/jfrog-platform-onboarding-tf` (case-sensitive)  |
| State backend errors with `endpoint requires auth`                   | OIDC succeeded but the mapped user lacks state-repo write      | Add the `gh-actions` user write permission on `terraform-state-local`                                     |
| Curation apply fails with HTTP 403                                   | Mapped user is missing Xray Admin scope                        | Assign Xray Admin (or the built-in Admin group) to `gh-actions`                                          |
| PR validate runs but no comment posts                                | `pull-requests: write` permission missing                      | Repo Settings → Actions → Workflow permissions → enable Read and write                                    |

---

## 7. Key properties of this setup

- **No JFrog access tokens stored in GitHub Secrets.** The only GitHub-stored value is `JF_URL` (non-sensitive).
- **Automatic rotation.** Workflow runs mint a fresh JFrog token each time, valid for 30 minutes. Expires before it can be misused.
- **One-step revocation.** Disable the `gh-actions` user in the JFrog UI and every workflow run instantly fails. There's no token to invalidate.
- **Audit trail.** JFrog logs every token-issue event with the GitHub claim payload, so you can trace exactly which PR/commit triggered which JFrog mutation.
