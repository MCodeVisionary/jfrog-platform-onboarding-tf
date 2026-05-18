module "platform" {
  source = "git::https://github.com/MCodeVisionary/jfrog-platform-onboarding-tf.git//terraform/modules/platform?ref=platform/v1.2.1"

  jfrog_url            = var.jfrog_url
  jfrog_access_token   = var.jfrog_access_token
  projects_config_file = "${path.module}/projects.json"
}
