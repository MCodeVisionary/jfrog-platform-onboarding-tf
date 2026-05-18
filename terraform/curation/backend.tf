# ---------------------------------------------------------------------------
# Remote state — JFrog Artifactory `terraformbackend`-type repo, dedicated
# path for the curation layer.
# Locking disabled (see platform/backend.tf for the rationale).
# Auth via TF_HTTP_USERNAME + TF_HTTP_PASSWORD env vars.
# ---------------------------------------------------------------------------
terraform {
  backend "http" {
    address       = "https://mcodevisionaryorg.jfrog.io/artifactory/terraform-state-local/curation/terraform.tfstate"
    update_method = "PUT"
  }
}
