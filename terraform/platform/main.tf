module "platform" {
  source = "../modules/platform"

  jfrog_url            = var.jfrog_url
  jfrog_access_token   = var.jfrog_access_token
  projects_config_file = "${path.module}/projects.json"
}
