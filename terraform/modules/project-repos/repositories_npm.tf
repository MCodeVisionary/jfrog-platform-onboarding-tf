# ---------------------------------------------------------------------------
# npm Repositories — all scoped to var.project_key
# ---------------------------------------------------------------------------

resource "artifactory_local_npm_repository" "this" {
  for_each = local.local_repos_npm

  key         = each.key
  description = "${upper(each.value.stage)} npm packages for ${each.value.app} (${var.project_key})"

  project_key          = var.project_key
  project_environments = [each.value.env]
}

resource "artifactory_remote_npm_repository" "this" {
  for_each = local.remote_repos_npm

  key         = each.key
  url         = each.value.url
  description = "Proxy to public npm registry for ${var.project_key} project"

  project_key = var.project_key
}

resource "artifactory_virtual_npm_repository" "this" {
  for_each = local.virtual_repos_npm

  key         = each.key
  description = "DEV npm virtual for ${each.value.app} (${var.project_key})"

  project_key = var.project_key

  repositories = [
    each.value.local_repo_key,
    each.value.remote_repo_key,
  ]

  default_deployment_repo = each.value.local_repo_key

  depends_on = [
    artifactory_local_npm_repository.this,
    artifactory_remote_npm_repository.this,
  ]
}
