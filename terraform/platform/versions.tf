terraform {
  required_version = ">= 1.3.0"

  required_providers {
    artifactory = {
      source  = "jfrog/artifactory"
      version = "~> 12.5"
    }
    project = {
      source  = "jfrog/project"
      version = "~> 1.9"
    }
    platform = {
      source  = "jfrog/platform"
      version = "~> 2.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    xray = {
      source  = "jfrog/xray"
      version = "~> 3.0"
    }
  }
}
