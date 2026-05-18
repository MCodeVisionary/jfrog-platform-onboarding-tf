module "curation" {
  source = "git::https://github.com/MCodeVisionary/jfrog-platform-onboarding-tf.git//terraform/modules/curation?ref=curation/v1.0.0"

  jfrog_url              = var.jfrog_url
  jfrog_access_token     = var.jfrog_access_token
  curation_policies_file = "${path.module}/curation_policies.json"
}
