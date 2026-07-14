# ---------------------------------------------------------------------------
# Hugging Face Repositories
#
# No virtual repository type exists for huggingfaceml in the provider, so
# unlike the other techs this is local + remote only. techs_without_virtual
# in locals.tf keeps huggingface out of virtual_repos generation.
# ---------------------------------------------------------------------------

resource "artifactory_local_huggingfaceml_repository" "this" {
  for_each = local.local_repos_huggingface

  key         = each.key
  description = "${upper(each.value.stage)} Hugging Face models for ${each.value.app} (${var.project_key})"

  project_key          = var.project_key
  project_environments = [each.value.env]

  lifecycle {
    ignore_changes = [xray_index]
  }
}

resource "artifactory_remote_huggingfaceml_repository" "this" {
  for_each = local.remote_repos_huggingface

  key         = each.key
  url         = each.value.url
  description = "Proxy to Hugging Face Hub for ${var.project_key} project"

  project_key = var.project_key
}
