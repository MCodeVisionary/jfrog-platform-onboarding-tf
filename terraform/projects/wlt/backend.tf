# ---------------------------------------------------------------------------
# Remote state — JFrog Artifactory (generic local repo: terraform-state-local).
# Auth via TF_HTTP_USERNAME and TF_HTTP_PASSWORD env vars.
# ---------------------------------------------------------------------------
terraform {
  backend "http" {
    address        = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/projects/wlt/terraform.tfstate"
    lock_address   = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/projects/wlt/terraform.tfstate.lock"
    unlock_address = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/projects/wlt/terraform.tfstate.lock"
    lock_method    = "PUT"
    unlock_method  = "DELETE"
  }
}
