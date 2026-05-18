# CI authentication setup

GitHub Actions authenticates to JFrog using a **static long-lived access token**
stored as a GitHub Secret, plus the username and URL as repo Variables.

> **Trade-off note:** an earlier version of this doc described an OIDC-based
> setup (no stored token, auto-rotating short-lived credentials). The OIDC
> path had operational friction in this environment (identity mapping was
> issuing tokens for a user that didn't exist), so we switched to static auth.
> If you want to go back to OIDC, the older approach is in this file's git
> history.

Total setup time: ~5 minutes, all in JFrog UI + GitHub Settings UI.

---

## 1. Pick (or create) a JFrog user for CI

The workflows authenticate as a single JFrog user. You have two options:

**Option A — reuse your admin user** (quickest, ties CI to your account)
- Username: `maharship@jfrog.com`
- Already exists; already has admin scope

**Option B — dedicated service user** (recommended for anything beyond a quick demo)
- JFrog UI → Administration → Users → **+ New User**
- Username: `gh-actions` (lowercase, simple)
- Disable internal password (no human login)
- Permissions: assign the built-in **Admin** group, OR a tighter custom permission target including:
  - Read/Write on every repository (for repo creation in project layers)
  - Project create/update/delete (`jfrog-project` provider)
  - Group create/update (`jfrog-platform` provider)
  - Environment create/delete (for global stages)
  - **Xray Admin** (for `xray_curation_policy` resources in the curation layer)
  - Write on `terraform-state-local` (for the HTTP state backend)

---

## 2. Generate an access token for that user

JFrog UI → Administration → Identity & Access → **Access Tokens** → **Generate Token**:

| Field | Value |
|---|---|
| Token name | `gh-actions-ci` (or `maharship-ci` if reusing your user) |
| User name | `gh-actions` (or `maharship@jfrog.com`) |
| Scope | `applied-permissions/user` (whatever the user can do, the token can do) |
| Expiration | Pick a value you can renew on schedule — e.g. **90d**. Track it; set a calendar reminder for rotation. |
| Reference Token | Disabled (we need the JWT) |

Click Generate, then **copy the token string**. It's shown once and starts with `eyJ...`. Keep this open in a tab — you paste it in step 4.

---

## 3. Store the JFrog URL + username as GitHub Variables

GitHub UI → repo Settings → Secrets and variables → Actions → **Variables tab** → **New repository variable** for each:

| Variable name | Value |
|---|---|
| `JF_URL` | `https://mcodevisionaryorg.jfrog.io` *(no trailing slash, no `/artifactory`)* |
| `TF_HTTP_USERNAME` | `maharship@jfrog.com` *(or `gh-actions` if you went with Option B)* — must match the username you generated the token for in step 2 |

These are non-sensitive (a URL and a username), so Variables not Secrets.

---

## 4. Store the access token as a GitHub Secret

GitHub UI → repo Settings → Secrets and variables → Actions → **Secrets tab** → **New repository secret**:

| Secret name | Value |
|---|---|
| `JFROG_ACCESS_TOKEN` | (paste the JWT from step 2) |

**Important:** this exact name `JFROG_ACCESS_TOKEN` is hardcoded in the
workflow YAMLs in two places per file:

```yaml
TF_HTTP_PASSWORD:          ${{ secrets.JFROG_ACCESS_TOKEN }}
TF_VAR_jfrog_access_token: ${{ secrets.JFROG_ACCESS_TOKEN }}
```

If you want a different secret name, search/replace `JFROG_ACCESS_TOKEN`
across `.github/workflows/apply.yml`, `pr-validate.yml`, `drift.yml`.

---

## 5. GitHub repo settings (workflow permissions + branch protection)

### Workflow permissions
GitHub UI → repo Settings → Actions → General → **Workflow permissions**:
- **Read and write permissions** (the workflows post PR comments + create drift Issues)
- **Allow GitHub Actions to create and approve pull requests:** enabled
  *(needed for the intake bot — see [README §Self-service via GitHub Actions](../README.md))*

If the radios are greyed out, an org-level policy is locking them — change
at https://github.com/organizations/MCodeVisionary/settings/actions first.

### Branch protection for `main`
GitHub UI → Settings → Branches → **Branch protection rules → Add rule**:
- Branch name pattern: `main`
- Require a pull request before merging: ✓
- Require approvals: 1
- Require review from Code Owners: ✓
- Require status checks: ✓ → add **PR Validate / plan**
- Do not allow bypassing the above: ✓

### Teams (CODEOWNERS uses these)
GitHub UI → org Teams → New team for each:
- `platform-admins`
- `cmrc-team`, `vntg-team`, `wlt-team`

If your team names differ, edit `.github/CODEOWNERS` to match.

---

## 6. Test the setup

After steps 1–5 are done:

1. Open a trivial PR — e.g. tweak a comment in `terraform/projects/cmrc/repos.json`
2. Wait for **PR Validate / plan** to run (~2–3 min)
3. If you see a red-bold "Drift has been detected" comment with a plan, you're done.

The first run, expand the **"Terraform init + plan"** step → the `env:` block at top should show:

```
TF_HTTP_USERNAME: maharship@jfrog.com    (or gh-actions)
TF_HTTP_PASSWORD: ***
TF_VAR_jfrog_url: https://mcodevisionaryorg.jfrog.io
TF_VAR_jfrog_access_token: ***
```

If `TF_HTTP_USERNAME` shows a value that **doesn't match** what you set, the
Variable wasn't saved — re-check in the UI.

### Troubleshooting

| Symptom                                                              | Cause                                                                                   | Fix                                                                                                       |
|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| `HTTP remote state endpoint requires auth` (401)                     | `TF_HTTP_USERNAME` and the token's subject claim don't both resolve to the same user    | Verify `vars.TF_HTTP_USERNAME` matches the user the token was generated for                              |
| State backend errors only for the curation layer                     | Mapped user lacks Xray Admin scope                                                      | Assign Xray Admin (or the built-in Admin group) to the JFrog user                                        |
| State backend errors only for project layers                          | Mapped user lacks write on `terraform-state-local`                                       | Grant write/deploy on `terraform-state-local` for the user                                                |
| Plan succeeds but apply fails with 403                                | Mapped user lacks the permission for the specific resource being created                | Check the failing resource type and grant the matching JFrog permission                                  |
| Repo Variable update didn't take effect                              | Workflow logs show the value **at the moment the run started** — old runs show old vals  | Re-run the workflow after editing the Variable                                                            |

---

## 7. Rotating the token

The token expires (90 days if you used the suggested default). When it does,
every workflow run fails with 401.

To rotate:

1. JFrog UI → Access Tokens → Generate a fresh token for the same user
2. GitHub UI → Secrets tab → click `JFROG_ACCESS_TOKEN` → **Update value** → paste the new JWT → Save
3. (Optional) JFrog UI → revoke the old token

No commits, no workflow changes — the secret name stays the same, only the
stored value rotates.

Set a calendar reminder for ~85 days from now (5-day buffer before expiry).

---

## 8. Properties of this setup

- **One token, two roles.** The same JFrog JWT is sent as both:
  - HTTP basic-auth password to the state backend (`TF_HTTP_PASSWORD`)
  - Provider `access_token` argument for all four JFrog providers (`TF_VAR_jfrog_access_token`)
- **No OIDC trust.** The `.github/workflows/jfrog-github-oidc-example.yml` smoke-test file is left in the repo (manual-trigger only) as a reference if you decide to migrate to OIDC later.
- **Single point of revocation.** Disable the user in JFrog UI → every workflow fails on the next run. Useful in an incident.
- **Token has the full scope of the mapped user.** Don't give the user more than CI needs (avoid Platform Admin if Xray Admin + repo CRUD is enough).
