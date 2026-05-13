# ---------------------------------------------------------------------------
# Terraform Repositories
# ---------------------------------------------------------------------------

resource "artifactory_local_terraform_module_repository" "this" {
  for_each = local.local_repos_terraform

  key         = each.key
  description = "${upper(each.value.stage)} Terraform modules for ${each.value.app} (${var.project_key})"

  project_key          = var.project_key
  project_environments = [each.value.env]
}

resource "artifactory_remote_terraform_repository" "this" {
  for_each = local.remote_repos_terraform

  key         = each.key
  url         = each.value.url
  description = "Proxy to public Terraform registry for ${var.project_key} project"

  project_key             = var.project_key
  terraform_registry_url  = "https://registry.terraform.io"
  terraform_providers_url = "https://releases.hashicorp.com"
  bypass_head_requests    = true
}

resource "artifactory_virtual_terraform_repository" "this" {
  for_each = local.virtual_repos_terraform

  key         = each.key
  description = "DEV Terraform virtual for ${each.value.app} (${var.project_key})"

  project_key = var.project_key

  repositories = [
    each.value.local_repo_key,
    each.value.remote_repo_key,
  ]

  depends_on = [
    artifactory_local_terraform_module_repository.this,
    artifactory_remote_terraform_repository.this,
  ]
}
