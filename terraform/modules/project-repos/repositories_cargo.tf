# ---------------------------------------------------------------------------
# Cargo Repositories
#
# No virtual repository type exists for cargo in the provider, so unlike
# the other techs this is local + remote only. techs_without_virtual in
# locals.tf keeps cargo out of virtual_repos generation.
# ---------------------------------------------------------------------------

resource "artifactory_local_cargo_repository" "this" {
  for_each = local.local_repos_cargo

  key         = each.key
  description = "${upper(each.value.stage)} Cargo crates for ${each.value.app} (${var.project_key})"

  project_key          = var.project_key
  project_environments = [each.value.env]

  lifecycle {
    ignore_changes = [xray_index]
  }
}

resource "artifactory_remote_cargo_repository" "this" {
  for_each = local.remote_repos_cargo

  key         = each.key
  url         = each.value.url
  description = "Proxy to crates.io for ${var.project_key} project"

  project_key = var.project_key
}
