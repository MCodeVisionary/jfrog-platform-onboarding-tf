# ---------------------------------------------------------------------------
# Remote state — JFrog Artifactory (generic local repo: terraform-state-local).
# Auth comes from environment variables, not this file:
#   TF_HTTP_USERNAME           — JFrog identity (e.g. service user)
#   TF_HTTP_PASSWORD           — JFrog access token (or, via OIDC exchange, a
#                                short-lived token issued by JFrog)
# ---------------------------------------------------------------------------
terraform {
  backend "http" {
    address        = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/platform/terraform.tfstate"
    lock_address   = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/platform/terraform.tfstate.lock"
    unlock_address = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/platform/terraform.tfstate.lock"
    lock_method    = "PUT"
    unlock_method  = "DELETE"
  }
}
