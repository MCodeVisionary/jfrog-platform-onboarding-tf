terraform {
  required_version = ">= 1.3.0"

  required_providers {
    xray = {
      source  = "jfrog/xray"
      version = "~> 3.0"
    }
  }
}
