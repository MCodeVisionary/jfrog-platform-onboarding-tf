terraform {
  required_version = ">= 1.3.0"

  required_providers {
    artifactory = {
      source  = "jfrog/artifactory"
      version = "~> 12.5"
    }
  }
}
