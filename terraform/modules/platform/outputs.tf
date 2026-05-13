output "project_keys" {
  description = "Map of project keys to display names."
  value = {
    for _, v in local.projects : v.key => v.display_name
  }
}

output "project_admin_groups" {
  description = "Project Admin group name per project."
  value = {
    for _, v in local.projects : v.key => local.project_groups[v.key].admin
  }
}

output "project_write_groups" {
  description = "Developer (WRITE) group name per project."
  value = {
    for _, v in local.projects : v.key => local.project_groups[v.key].write
  }
}

output "project_read_groups" {
  description = "Viewer (READ) group name per project."
  value = {
    for _, v in local.projects : v.key => local.project_groups[v.key].read
  }
}

output "platform_groups" {
  description = "Platform-wide groups (not project-scoped)."
  value = {
    curation_approver = platform_group.curation_approver.name
    security_admin    = platform_group.security_admin.name
  }
}
