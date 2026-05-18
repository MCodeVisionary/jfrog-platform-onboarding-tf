provider "artifactory" {
  url          = var.jfrog_url
  access_token = var.jfrog_access_token
}

provider "project" {
  url          = var.jfrog_url
  access_token = var.jfrog_access_token
}

provider "platform" {
  url          = var.jfrog_url
  access_token = var.jfrog_access_token
}

provider "xray" {
  url          = var.jfrog_url
  access_token = var.jfrog_access_token
}
