output "project_key" {
  description = "Project key these repos belong to."
  value       = var.project_key
}

output "local_repository_count" {
  description = "Total number of local repositories created."
  value       = length(local.local_repos)
}

output "remote_repository_count" {
  description = "Total number of remote repositories created."
  value       = length(local.remote_repos)
}

output "virtual_repository_count" {
  description = "Total number of virtual repositories created."
  value       = length(local.virtual_repos)
}

output "total_repository_count" {
  description = "Total number of repositories created across all types."
  value       = length(local.local_repos) + length(local.remote_repos) + length(local.virtual_repos)
}

output "virtual_dev_repo_urls" {
  description = "Developer-facing virtual repository URLs for DEV stage."
  value = {
    for k, v in local.virtual_repos : "${var.project_key}/${v.app}/${v.tech}" => "${var.jfrog_url}/artifactory/${k}"
    if v.stage == "dev"
  }
}
