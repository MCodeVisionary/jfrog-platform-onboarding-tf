# ---------------------------------------------------------------------------
# Remote state — JFrog Artifactory `terraformbackend`-type repo.
#
# Locking is intentionally NOT configured here: Artifactory's terraform-backend
# repo does not implement the WebDAV-style LOCK/UNLOCK semantics that
# Terraform's HTTP backend expects. Concurrent-apply protection is handled
# instead by:
#   - CI: GitHub Actions `concurrency: { group: ... }` in apply.yml
#   - Local: discipline + only one engineer running apply against an env
#
# update_method = PUT because Artifactory's repo API only accepts PUT for
# generic object uploads (POST returns 405).
#
# Auth comes from environment variables:
#   TF_HTTP_USERNAME — JFrog username (subject claim of the access token)
#   TF_HTTP_PASSWORD — JFrog access token
# ---------------------------------------------------------------------------
terraform {
  backend "http" {
    address       = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/platform/terraform.tfstate"
    update_method = "PUT"
  }
}
