module "repos" {
  source = "../../modules/project-repos"

  jfrog_url          = var.jfrog_url
  jfrog_access_token = var.jfrog_access_token
  project_key        = "wlt"
  repos_config_file  = "${path.module}/repos.json"
}
