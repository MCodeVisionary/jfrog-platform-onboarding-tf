# ---------------------------------------------------------------------------
# RPM Repositories
# ---------------------------------------------------------------------------

resource "artifactory_local_rpm_repository" "this" {
  for_each = local.local_repos_rpm

  key         = each.key
  description = "${upper(each.value.stage)} RPM packages for ${each.value.app} (${var.project_key})"

  project_key          = var.project_key
  project_environments = [each.value.env]

  lifecycle {
    ignore_changes = [xray_index]
  }
}

resource "artifactory_remote_rpm_repository" "this" {
  for_each = local.remote_repos_rpm

  key         = each.key
  url         = each.value.url
  description = "Proxy to CentOS mirror for ${var.project_key} project"

  project_key = var.project_key
}

resource "artifactory_virtual_rpm_repository" "this" {
  for_each = local.virtual_repos_rpm

  key         = each.key
  description = "DEV RPM virtual for ${each.value.app} (${var.project_key})"

  project_key = var.project_key

  repositories = [
    each.value.local_repo_key,
    each.value.remote_repo_key,
  ]

  depends_on = [
    artifactory_local_rpm_repository.this,
    artifactory_remote_rpm_repository.this,
  ]
}
