# ---------------------------------------------------------------------------
# Docker Repositories
# ---------------------------------------------------------------------------

resource "artifactory_local_docker_v2_repository" "this" {
  for_each = local.local_repos_docker

  key         = each.key
  description = "${upper(each.value.stage)} Docker images for ${each.value.app} (${var.project_key})"

  tag_retention   = 10
  max_unique_tags = 50

  project_key          = var.project_key
  project_environments = [each.value.env]

  lifecycle {
    ignore_changes = [xray_index]
  }
}

resource "artifactory_remote_docker_repository" "this" {
  for_each = local.remote_repos_docker

  key         = each.key
  url         = each.value.url
  description = "Proxy to Docker Hub for ${var.project_key} project"

  project_key           = var.project_key
  block_pushing_schema1 = true
}

resource "artifactory_virtual_docker_repository" "this" {
  for_each = local.virtual_repos_docker

  key         = each.key
  description = "DEV Docker virtual for ${each.value.app} (${var.project_key})"

  project_key = var.project_key

  repositories = [
    each.value.local_repo_key,
    each.value.remote_repo_key,
  ]

  resolve_docker_tags_by_timestamp = true

  depends_on = [
    artifactory_local_docker_v2_repository.this,
    artifactory_remote_docker_repository.this,
  ]
}
