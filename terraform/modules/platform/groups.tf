# ---------------------------------------------------------------------------
# Per-project IDP groups — ADMIN/WRITE/READ × every project
# ---------------------------------------------------------------------------

resource "platform_group" "admin" {
  for_each = local.projects

  name        = local.project_groups[each.value.key].admin
  description = "Admin group for ${each.value.display_name} project. Managed by IDP sync."

  auto_join        = false
  admin_privileges = false
}

resource "platform_group" "write" {
  for_each = local.projects

  name        = local.project_groups[each.value.key].write
  description = "Write (Developer) group for ${each.value.display_name} project. Managed by IDP sync."

  auto_join        = false
  admin_privileges = false
}

resource "platform_group" "read" {
  for_each = local.projects

  name        = local.project_groups[each.value.key].read
  description = "Read (Viewer) group for ${each.value.display_name} project. Managed by IDP sync."

  auto_join        = false
  admin_privileges = false
}

# ---------------------------------------------------------------------------
# Platform-wide groups (not scoped to a single project)
# ---------------------------------------------------------------------------

resource "platform_group" "curation_approver" {
  name        = "curation-approver"
  description = "Curation approvers — approve package curation policies platform-wide. Managed by IDP sync."

  auto_join        = false
  admin_privileges = false
}

resource "platform_group" "security_admin" {
  name        = "security-admin"
  description = "Security administrators — Xray / Advanced Security platform-wide admin. Managed by IDP sync."

  auto_join        = false
  admin_privileges = false
}
