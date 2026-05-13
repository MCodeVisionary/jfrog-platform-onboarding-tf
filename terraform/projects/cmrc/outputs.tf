output "project_key" {
  value = module.repos.project_key
}

output "local_repository_count" {
  value = module.repos.local_repository_count
}

output "remote_repository_count" {
  value = module.repos.remote_repository_count
}

output "virtual_repository_count" {
  value = module.repos.virtual_repository_count
}

output "total_repository_count" {
  value = module.repos.total_repository_count
}

output "virtual_dev_repo_urls" {
  value = module.repos.virtual_dev_repo_urls
}
