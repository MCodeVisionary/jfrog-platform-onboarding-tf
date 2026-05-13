# ---------------------------------------------------------------------------
# Group → Role bindings (new-style project_group resource).
# Replaces the deprecated `group {}` blocks on the project resource, which
# the provider silently ignores when use_project_group_resource = true.
#
# Bindings derived from local.project_role_bindings:
#   ADMIN-{key}     → Project Admin
#   WRITE-{key}     → Developer
#   READ-{key}      → Viewer
#   security-admin  → Security Manager (every project)
# ---------------------------------------------------------------------------

resource "project_group" "this" {
  for_each = {
    for b in local.project_role_bindings : "${b.project_key}-${b.group_name}" => b
  }

  project_key = each.value.project_key
  name        = each.value.group_name
  roles       = each.value.roles

  depends_on = [
    project.this,
    platform_group.admin,
    platform_group.write,
    platform_group.read,
    platform_group.security_admin,
  ]
}
