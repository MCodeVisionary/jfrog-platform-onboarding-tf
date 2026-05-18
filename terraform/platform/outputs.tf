output "project_keys" {
  description = "Map of project keys to display names."
  value       = module.platform.project_keys
}

output "project_admin_groups" {
  value = module.platform.project_admin_groups
}

output "project_write_groups" {
  value = module.platform.project_write_groups
}

output "project_read_groups" {
  value = module.platform.project_read_groups
}

output "platform_groups" {
  value = module.platform.platform_groups
}

output "curation_policy_count" {
  value = module.platform.curation_policy_count
}

output "curation_policy_names" {
  value = module.platform.curation_policy_names
}
