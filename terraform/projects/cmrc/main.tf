module "repos" {
  source = "git::https://github.com/MCodeVisionary/jfrog-platform-onboarding-tf.git//terraform/modules/project-repos?ref=project-repos/v1.2.0"

  jfrog_url          = var.jfrog_url
  jfrog_access_token = var.jfrog_access_token
  project_key        = "cmrc"
  repos_config_file  = "${path.module}/repos.json"
}
