# ---------------------------------------------------------------------------
# Python (PyPI) Repositories
# ---------------------------------------------------------------------------

resource "artifactory_local_pypi_repository" "this" {
  for_each = local.local_repos_python

  key         = each.key
  description = "${upper(each.value.stage)} Python packages for ${each.value.app} (${var.project_key})"

  project_key          = var.project_key
  project_environments = [each.value.env]
}

resource "artifactory_remote_pypi_repository" "this" {
  for_each = local.remote_repos_python

  key         = each.key
  url         = each.value.url
  description = "Proxy to Python Package Index (PyPI) for ${var.project_key} project"

  project_key = var.project_key
}

resource "artifactory_virtual_pypi_repository" "this" {
  for_each = local.virtual_repos_python

  key         = each.key
  description = "DEV Python virtual for ${each.value.app} (${var.project_key})"

  project_key = var.project_key

  repositories = [
    each.value.local_repo_key,
    each.value.remote_repo_key,
  ]

  default_deployment_repo = each.value.local_repo_key

  depends_on = [
    artifactory_local_pypi_repository.this,
    artifactory_remote_pypi_repository.this,
  ]
}
