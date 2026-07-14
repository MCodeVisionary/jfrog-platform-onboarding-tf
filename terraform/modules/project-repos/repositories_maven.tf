# ---------------------------------------------------------------------------
# Maven Repositories
# ---------------------------------------------------------------------------

resource "artifactory_local_maven_repository" "this" {
  for_each = local.local_repos_maven

  key         = each.key
  description = "${upper(each.value.stage)} Maven artifacts for ${each.value.app} (${var.project_key})"

  project_key          = var.project_key
  project_environments = [each.value.env]

  lifecycle {
    ignore_changes = [xray_index]
  }
}

resource "artifactory_remote_maven_repository" "this" {
  for_each = local.remote_repos_maven

  key         = each.key
  url         = each.value.url
  description = "Proxy to Maven Central for ${var.project_key} project"

  project_key = var.project_key
}

resource "artifactory_virtual_maven_repository" "this" {
  for_each = local.virtual_repos_maven

  key         = each.key
  description = "DEV Maven virtual for ${each.value.app} (${var.project_key})"

  project_key = var.project_key

  repositories = [
    each.value.local_repo_key,
    each.value.remote_repo_key,
  ]

  depends_on = [
    artifactory_local_maven_repository.this,
    artifactory_remote_maven_repository.this,
  ]
}
