# ---------------------------------------------------------------------------
# Helm Repositories
# ---------------------------------------------------------------------------

resource "artifactory_local_helm_repository" "this" {
  for_each = local.local_repos_helm

  key         = each.key
  description = "${upper(each.value.stage)} Helm charts for ${each.value.app} (${var.project_key})"

  project_key          = var.project_key
  project_environments = [each.value.env]

  lifecycle {
    ignore_changes = [force_non_duplicate_chart, force_metadata_name_version]
  }
}

resource "artifactory_remote_helm_repository" "this" {
  for_each = local.remote_repos_helm

  key         = each.key
  url         = each.value.url
  description = "Proxy to Helm stable chart repository for ${var.project_key} project"

  project_key = var.project_key
}

resource "artifactory_virtual_helm_repository" "this" {
  for_each = local.virtual_repos_helm

  key         = each.key
  description = "DEV Helm virtual for ${each.value.app} (${var.project_key})"

  project_key = var.project_key

  repositories = [
    each.value.local_repo_key,
    each.value.remote_repo_key,
  ]

  depends_on = [
    artifactory_local_helm_repository.this,
    artifactory_remote_helm_repository.this,
  ]
}
