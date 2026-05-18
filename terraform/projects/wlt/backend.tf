# ---------------------------------------------------------------------------
# Remote state — JFrog Artifactory `terraformbackend`-type repo.
# Locking disabled (see platform/backend.tf for rationale).
# Auth via TF_HTTP_USERNAME + TF_HTTP_PASSWORD env vars.
# ---------------------------------------------------------------------------
terraform {
  backend "http" {
    address       = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/projects/wlt/terraform.tfstate"
    update_method = "PUT"
  }
}
